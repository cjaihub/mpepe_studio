import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

class SecurePairingState {
  final String? activePin;
  final enc.Key? activeKey;
  final String salt;

  SecurePairingState({this.activePin, this.activeKey, required this.salt});

  SecurePairingState copyWith({
    String? activePin,
    enc.Key? activeKey,
    String? salt,
  }) {
    return SecurePairingState(
      activePin: activePin ?? this.activePin,
      activeKey: activeKey ?? this.activeKey,
      salt: salt ?? this.salt,
    );
  }
}

class SecurePairingService extends Notifier<SecurePairingState> {
  final _storage = const FlutterSecureStorage();
  static const _fallbackUidKey = 'sp_paired_uid';
  static const _fallbackKeyKey = 'sp_paired_key';

  @override
  SecurePairingState build() {
    // Generate a fixed salt per session (in production this should be persisted per-device)
    final salt = _generateRandomString(16);
    return SecurePairingState(salt: salt);
  }

  /// Generates a random 6-digit PIN for pairing
  String generatePairingPin() {
    final random = Random();
    final pin = (100000 + random.nextInt(900000)).toString();
    state = state.copyWith(activePin: pin);
    return pin;
  }

  /// Derives the AES key once the Desktop knows the Mobile has authenticated
  void setDerivedKey(enc.Key key) {
    state = state.copyWith(activeKey: key);
  }

  Future<String?> loadPersistedPairing() async {
    String? uid;
    String? keyBase64;
    try {
      uid = await _storage.read(key: 'paired_uid');
      keyBase64 = await _storage.read(key: 'paired_key');
    } catch (_) {
      // Fallback to SharedPreferences on desktop builds without Keychain group entitlements.
    }

    if (uid == null || keyBase64 == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        uid ??= prefs.getString(_fallbackUidKey);
        keyBase64 ??= prefs.getString(_fallbackKeyKey);
      } catch (_) {}
    }

    if (uid != null && keyBase64 != null) {
      final key = enc.Key.fromBase64(keyBase64);
      state = state.copyWith(activeKey: key);
      return uid;
    }
    return null;
  }

  Future<void> persistPairing(String uid, enc.Key key) async {
    try {
      await _storage.write(key: 'paired_uid', value: uid);
      await _storage.write(key: 'paired_key', value: key.base64);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_fallbackUidKey, uid);
      await prefs.setString(_fallbackKeyKey, key.base64);
    } catch (_) {}
  }

  Future<void> clearPairing() async {
    try {
      await _storage.delete(key: 'paired_uid');
      await _storage.delete(key: 'paired_key');
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_fallbackUidKey);
      await prefs.remove(_fallbackKeyKey);
    } catch (_) {}
    state = SecurePairingState(salt: _generateRandomString(16));
  }

  String _generateRandomString(int length) {
    const chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
    final random = Random.secure();
    return String.fromCharCodes(Iterable.generate(
        length, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
  }
}

final securePairingProvider = NotifierProvider<SecurePairingService, SecurePairingState>(() {
  return SecurePairingService();
});
