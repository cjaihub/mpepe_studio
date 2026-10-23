import 'dart:convert';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final pinAuthServiceProvider = Provider<PinAuthService>((ref) {
  return PinAuthService(const FlutterSecureStorage());
});

/// Enterprise-grade PIN service with:
/// - SHA-256 + per-user salt hashing (PIN never stored plain-text)
/// - Brute-force lockout after [maxAttempts] failures
/// - Secure atomic clear for logout flows
class PinAuthService {
  final FlutterSecureStorage _secureStorage;

  // Storage keys
  static const String _pinHashKey = 'user_app_pin_hash';
  static const String _pinSaltKey = 'user_app_pin_salt';
  static const String _failedAttemptsKey = 'pin_failed_attempts';
  static const String _lockoutUntilKey = 'pin_lockout_until';
  static const String _pinOwnerKey = 'user_app_pin_owner_uid';

  /// Number of failed attempts before lockout
  static const int maxAttempts = 5;

  /// Lockout duration in minutes
  static const int lockoutMinutes = 15;

  PinAuthService(this._secureStorage);

  // ── Hash helpers ───────────────────────────────────────────────────────────

  /// Generates a random 32-byte hex salt
  String _generateSalt() {
    final rnd = Random.secure();
    return List<int>.generate(32, (_) => rnd.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// SHA-256(pin + salt)
  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$pin:$salt');
    return sha256.convert(bytes).toString();
  }

  // ── Core PIN operations ────────────────────────────────────────────────────

  Future<bool> hasPinSet() async {
    final hash = await _secureStorage.read(key: _pinHashKey);
    return hash != null && hash.isNotEmpty;
  }

  /// Hash the PIN with a fresh salt and persist both.
  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    final hash = _hashPin(pin, salt);
    final owner = FirebaseAuth.instance.currentUser;
    await Future.wait([
      _secureStorage.write(key: _pinHashKey, value: hash),
      _secureStorage.write(key: _pinSaltKey, value: salt),
      // The PIN belongs to the account that set it; sign-in only accepts it
      // for that same account.
      if (owner != null && !owner.isAnonymous) _secureStorage.write(key: _pinOwnerKey, value: owner.uid),
      _secureStorage.delete(key: _failedAttemptsKey),
      _secureStorage.delete(key: _lockoutUntilKey),
    ]);
  }

  /// Verify attempt. Increments failure counter; locks out after [maxAttempts].
  /// Returns [PinVerifyResult] with outcome and remaining attempts.
  Future<PinVerifyResult> verifyPin(String pin) async {
    // Check lockout first
    final lockoutStatus = await getLockoutStatus();
    if (lockoutStatus.isLockedOut) {
      return PinVerifyResult.lockedOut(lockoutStatus.remainingMinutes);
    }

    final storedHash = await _secureStorage.read(key: _pinHashKey);
    final salt = await _secureStorage.read(key: _pinSaltKey);

    if (storedHash == null || salt == null) {
      return PinVerifyResult.noPinSet();
    }

    final attempt = _hashPin(pin, salt);
    if (attempt == storedHash) {
      // Success — reset failure counter
      await Future.wait([
        _secureStorage.delete(key: _failedAttemptsKey),
        _secureStorage.delete(key: _lockoutUntilKey),
      ]);
      return PinVerifyResult.success();
    }

    // Wrong PIN — increment counter
    final attempts = await _getFailedAttempts() + 1;
    await _secureStorage.write(key: _failedAttemptsKey, value: attempts.toString());

    final remaining = maxAttempts - attempts;
    if (remaining <= 0) {
      // Trigger lockout
      final lockoutUntil = DateTime.now().add(Duration(minutes: lockoutMinutes));
      await _secureStorage.write(
        key: _lockoutUntilKey,
        value: lockoutUntil.millisecondsSinceEpoch.toString(),
      );
      return PinVerifyResult.lockedOut(lockoutMinutes);
    }

    return PinVerifyResult.wrongPin(remaining);
  }

  Future<int> _getFailedAttempts() async {
    final val = await _secureStorage.read(key: _failedAttemptsKey);
    return int.tryParse(val ?? '0') ?? 0;
  }

  Future<LockoutStatus> getLockoutStatus() async {
    final lockoutUntilStr = await _secureStorage.read(key: _lockoutUntilKey);
    if (lockoutUntilStr == null) return LockoutStatus.notLocked();

    final lockoutUntil = DateTime.fromMillisecondsSinceEpoch(
      int.tryParse(lockoutUntilStr) ?? 0,
    );

    if (DateTime.now().isAfter(lockoutUntil)) {
      // Lockout expired — clear it
      await Future.wait([
        _secureStorage.delete(key: _lockoutUntilKey),
        _secureStorage.delete(key: _failedAttemptsKey),
      ]);
      return LockoutStatus.notLocked();
    }

    final remaining = lockoutUntil.difference(DateTime.now()).inMinutes + 1;
    return LockoutStatus.locked(remaining);
  }

  /// Called after successful biometric auth — resets lockout without PIN
  Future<void> resetLockout() async {
    await Future.wait([
      _secureStorage.delete(key: _failedAttemptsKey),
      _secureStorage.delete(key: _lockoutUntilKey),
    ]);
  }

  /// Removes PIN — used when user changes PIN or during full logout
  Future<void> removePin() async {
    await Future.wait([
      _secureStorage.delete(key: _pinHashKey),
      _secureStorage.delete(key: _pinSaltKey),
      _secureStorage.delete(key: _pinOwnerKey),
      _secureStorage.delete(key: _failedAttemptsKey),
      _secureStorage.delete(key: _lockoutUntilKey),
    ]);
  }

  /// True when a PIN is set on this device by [uid].
  Future<bool> isPinOwnedBy(String uid) async =>
      await hasPinSet() && (await _secureStorage.read(key: _pinOwnerKey)) == uid;

  /// Nuclear clear — removes ALL pin-related secure storage keys
  /// Used by SecureLogoutService
  Future<void> clearAll() => removePin();

  // ── Session Timeout Management ─────────────────────────────────────────────

  /// Used by AppLifecycleObserver / startup to check if session expired.
  Future<bool> isSessionExpired({int timeoutMinutes = 5}) async {
    final lastActiveStr = await _secureStorage.read(key: 'last_active_time');
    if (lastActiveStr == null) return false; // If not set, don't lock out

    final lastActive = DateTime.fromMillisecondsSinceEpoch(
      int.tryParse(lastActiveStr) ?? 0,
    );
    final elapsed = DateTime.now().difference(lastActive);
    return elapsed.inMinutes >= timeoutMinutes;
  }

  /// Sets the last active time to now.
  Future<void> setLastActiveNow() async {
    await _secureStorage.write(
      key: 'last_active_time',
      value: DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }
}

// ── Result types ───────────────────────────────────────────────────────────

enum PinVerifyOutcome { success, wrongPin, lockedOut, noPinSet }

class PinVerifyResult {
  final PinVerifyOutcome outcome;
  final int remainingAttempts;
  final int lockoutMinutes;

  const PinVerifyResult._({
    required this.outcome,
    this.remainingAttempts = 0,
    this.lockoutMinutes = 0,
  });

  factory PinVerifyResult.success() =>
      const PinVerifyResult._(outcome: PinVerifyOutcome.success);

  factory PinVerifyResult.wrongPin(int remaining) =>
      PinVerifyResult._(outcome: PinVerifyOutcome.wrongPin, remainingAttempts: remaining);

  factory PinVerifyResult.lockedOut(int minutes) =>
      PinVerifyResult._(outcome: PinVerifyOutcome.lockedOut, lockoutMinutes: minutes);

  factory PinVerifyResult.noPinSet() =>
      const PinVerifyResult._(outcome: PinVerifyOutcome.noPinSet);

  bool get isSuccess => outcome == PinVerifyOutcome.success;
  bool get isLockedOut => outcome == PinVerifyOutcome.lockedOut;
  bool get isWrongPin => outcome == PinVerifyOutcome.wrongPin;
}

class LockoutStatus {
  final bool isLockedOut;
  final int remainingMinutes;

  const LockoutStatus._({required this.isLockedOut, this.remainingMinutes = 0});

  factory LockoutStatus.notLocked() => const LockoutStatus._(isLockedOut: false);
  factory LockoutStatus.locked(int minutes) =>
      LockoutStatus._(isLockedOut: true, remainingMinutes: minutes);
}
