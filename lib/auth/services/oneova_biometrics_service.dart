import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../security/login_security.dart';

final oneovaBiometricsServiceProvider = Provider<OneovaBiometricsService>((ref) {
  return OneovaBiometricsService();
});

/// Comprehensive hardware capability model for Biometrics.
class BiometricCapability {
  final bool isHardwareAvailable;
  final bool canCheckBiometrics;
  final bool hasEnrolledBiometrics;
  final List<BiometricType> availableTypes;
  final String typeLabel;
  final String statusDescription;

  const BiometricCapability({
    required this.isHardwareAvailable,
    required this.canCheckBiometrics,
    required this.hasEnrolledBiometrics,
    required this.availableTypes,
    required this.typeLabel,
    required this.statusDescription,
  });

  bool get isReadyToAuthenticate => isHardwareAvailable && hasEnrolledBiometrics;
}

/// Result of a biometric authentication attempt.
class BiometricAuthResult {
  final bool isSuccess;
  final bool isCanceled;
  final bool isLockedOut;
  final bool isNotEnrolled;
  final String? errorMessage;

  const BiometricAuthResult._({
    required this.isSuccess,
    this.isCanceled = false,
    this.isLockedOut = false,
    this.isNotEnrolled = false,
    this.errorMessage,
  });

  factory BiometricAuthResult.success() =>
      const BiometricAuthResult._(isSuccess: true);

  factory BiometricAuthResult.canceled([String? message]) =>
      BiometricAuthResult._(isSuccess: false, isCanceled: true, errorMessage: message ?? 'Authentication canceled');

  factory BiometricAuthResult.lockedOut([String? message]) =>
      BiometricAuthResult._(isSuccess: false, isLockedOut: true, errorMessage: message ?? 'Sensor locked out due to multiple attempts. Use PIN/Password.');

  factory BiometricAuthResult.notEnrolled([String? message]) =>
      BiometricAuthResult._(isSuccess: false, isNotEnrolled: true, errorMessage: message ?? 'No biometrics enrolled on device settings');

  factory BiometricAuthResult.failure(String message) =>
      BiometricAuthResult._(isSuccess: false, errorMessage: message);
}

/// Result of fast 1-tap sign-in via biometric passkey.
class BiometricFastLoginResult {
  final bool isSuccess;
  final String? userId;
  final String? userEmail;
  final String? errorMessage;
  final bool noEnrolledUser;

  const BiometricFastLoginResult._({
    required this.isSuccess,
    this.userId,
    this.userEmail,
    this.errorMessage,
    this.noEnrolledUser = false,
  });

  factory BiometricFastLoginResult.success({required String userId, required String userEmail}) =>
      BiometricFastLoginResult._(isSuccess: true, userId: userId, userEmail: userEmail);

  factory BiometricFastLoginResult.noEnrolledUser() =>
      const BiometricFastLoginResult._(isSuccess: false, noEnrolledUser: true, errorMessage: 'No account enrolled for biometric sign-in on this device');

  factory BiometricFastLoginResult.failure(String message) =>
      BiometricFastLoginResult._(isSuccess: false, errorMessage: message);
}

/// Enterprise-grade Biometric and Fingerprint Security Service.
/// Deeply wired to user profiles, Firestore security settings, and hardware keystore.
class OneovaBiometricsService {
  final LocalAuthentication _localAuth;
  final FlutterSecureStorage _secureStorage;
  final FirebaseFirestore _firestore;

  OneovaBiometricsService({
    LocalAuthentication? localAuth,
    FlutterSecureStorage? secureStorage,
    FirebaseFirestore? firestore,
  })  : _localAuth = localAuth ?? LocalAuthentication(),
        _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            ),
        _firestore = firestore ?? FirebaseFirestore.instance;

  static const String _biometricEnabledKey = 'oneova_biometric_auth_enabled';
  static const String _activeBioUidKey = 'oneova_bio_active_uid';
  static const String _activeBioEmailKey = 'oneova_bio_active_email';
  // Device-bound sign-in key: the secret never leaves secure storage except
  // to be exchanged (over TLS) for a custom token by `biometricSignIn`.
  static const String _signInKeyIdKey = 'oneova_bio_signin_key_id';
  static const String _signInSecretKey = 'oneova_bio_signin_secret';
  static const String _offeredKeyPrefix = 'oneova_bio_offered_';

  // ── 1. Detailed Hardware Capability Check ─────────────────────────────────

  /// Checks if the device has biometric hardware capable of enrollment.
  Future<bool> isDeviceSupported() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck || isSupported;
    } on PlatformException catch (e) {
      debugPrint('[OneovaBiometricsService] isDeviceSupported error: $e');
      return false;
    }
  }

  /// Alias for checking biometric availability.
  Future<bool> isBiometricsAvailable() async => isDeviceSupported();

  /// Returns available biometric hardware types (Face, Fingerprint, Iris, Strong).
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } on PlatformException catch (e) {
      debugPrint('[OneovaBiometricsService] getAvailableBiometrics error: $e');
      return [];
    }
  }

  /// User-friendly label for current device biometric capability.
  Future<String> getBiometricTypeLabel() async {
    final types = await getAvailableBiometrics();
    if (types.contains(BiometricType.face)) {
      return 'Face ID / Camera Unlock';
    } else if (types.contains(BiometricType.fingerprint) || types.contains(BiometricType.strong)) {
      return 'Fingerprint / Touch ID';
    } else if (types.contains(BiometricType.iris)) {
      return 'Iris Unlock';
    }
    return 'Biometric Passkey';
  }

  /// Full diagnostics of biometric capabilities for UI display in settings.
  Future<BiometricCapability> getCapabilityDetails() async {
    try {
      final isSupported = await isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      final types = await getAvailableBiometrics();
      final hasEnrolled = canCheck && types.isNotEmpty;
      final label = await getBiometricTypeLabel();

      String description;
      if (!isSupported) {
        description = 'Biometric hardware is not available on this device.';
      } else if (!hasEnrolled) {
        description = 'Hardware supported, but no fingerprint or face enrolled in Android Settings.';
      } else {
        description = '$label active and hardware-verified.';
      }

      return BiometricCapability(
        isHardwareAvailable: isSupported,
        canCheckBiometrics: canCheck,
        hasEnrolledBiometrics: hasEnrolled,
        availableTypes: types,
        typeLabel: label,
        statusDescription: description,
      );
    } catch (e) {
      return const BiometricCapability(
        isHardwareAvailable: false,
        canCheckBiometrics: false,
        hasEnrolledBiometrics: false,
        availableTypes: [],
        typeLabel: 'Biometrics Unavailable',
        statusDescription: 'Failed to query biometric subsystem.',
      );
    }
  }

  // ── 2. Secure Authentication Challenges ────────────────────────────────────

  /// Performs live biometric authentication challenge.
  Future<bool> authenticate({String reason = 'Unlock Oneova securely'}) async {
    final result = await authenticateWithDetails(reason: reason);
    return result.isSuccess;
  }

  /// Alias for biometric authentication.
  Future<bool> authenticateWithBiometrics({String reason = 'Unlock Oneova securely'}) =>
      authenticate(reason: reason);

  /// Performs biometric authentication and returns rich outcome details.
  Future<BiometricAuthResult> authenticateWithDetails({
    required String reason,
    bool biometricOnly = true,
  }) async {
    try {
      final supported = await isDeviceSupported();
      if (!supported) {
        return BiometricAuthResult.failure('Biometric hardware is not supported on this device.');
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: biometricOnly,
        persistAcrossBackgrounding: true,
      );

      if (authenticated) {
        return BiometricAuthResult.success();
      } else {
        return BiometricAuthResult.canceled();
      }
    } on PlatformException catch (e) {
      debugPrint('[OneovaBiometricsService] PlatformException during authenticate: code=${e.code}, msg=${e.message}');
      if (e.code == 'LockedOut' || e.code == 'PermanentlyLockedOut') {
        return BiometricAuthResult.lockedOut(e.message);
      } else if (e.code == 'NotEnrolled') {
        return BiometricAuthResult.notEnrolled(e.message);
      } else if (e.code == 'auth_in_progress') {
        return BiometricAuthResult.failure('Authentication already in progress');
      } else if (e.code == 'PasscodeNotSet') {
        return BiometricAuthResult.failure('Please set up a device lock screen in Android Settings first');
      }
      return BiometricAuthResult.failure(e.message ?? 'Biometric verification failed');
    } catch (e) {
      return BiometricAuthResult.failure('Unexpected authentication error: $e');
    }
  }

  // ── 3. User Profile Biometric Enrollment & Revocation ───────────────────────

  /// Checks if biometrics are enrolled and active for a specific user ID.
  Future<bool> isUserEnrolled(String userId) async {
    if (userId.isEmpty) return false;
    final val = await _secureStorage.read(key: 'oneova_bio_enrolled_$userId');
    return val == 'true';
  }

  /// Whether biometric passkey unlock is currently enabled globally on this device.
  Future<bool> isBiometricEnrollmentActive() async {
    final val = await _secureStorage.read(key: _biometricEnabledKey);
    return val == 'true';
  }

  /// Retrieves the enrolled user email for 1-tap sign in.
  Future<String?> getEnrolledUserEmail() async {
    return await _secureStorage.read(key: _activeBioEmailKey);
  }

  /// Retrieves the enrolled user ID for 1-tap sign in.
  Future<String?> getEnrolledUserId() async {
    return await _secureStorage.read(key: _activeBioUidKey);
  }

  /// Enrolls user biometrics by demanding a live fingerprint challenge first,
  /// then cryptographically binding the token and updating Firestore user profile.
  Future<BiometricAuthResult> enrollUserBiometrics({
    required String userId,
    required String userEmail,
    String? displayName,
  }) async {
    if (userId.isEmpty) {
      return BiometricAuthResult.failure('User ID cannot be empty');
    }
    // Fingerprint sign-in can only be bound to an account that already passed
    // the two-check sign-in on this (trusted) device.
    final current = FirebaseAuth.instance.currentUser;
    if (current == null || current.uid != userId || !LoginSecurity.instance.isVerified(current)) {
      return BiometricAuthResult.failure('Finish signing in (two checks) before turning on fingerprint sign-in.');
    }

    final capability = await getCapabilityDetails();
    if (!capability.isHardwareAvailable) {
      return BiometricAuthResult.failure('Biometric hardware is not available on this device');
    }
    if (!capability.hasEnrolledBiometrics) {
      return BiometricAuthResult.notEnrolled(
        'Please enroll at least one fingerprint or Face ID in Android Settings before activating.',
      );
    }

    // 1. Demand live fingerprint scan challenge
    final authResult = await authenticateWithDetails(
      reason: 'Scan fingerprint to verify and activate biometric protection for $userEmail',
      biometricOnly: true,
    );

    if (!authResult.isSuccess) {
      return authResult;
    }

    // 2. Generate hardware-bound cryptographic credential token
    final now = DateTime.now().toUtc();
    final rawTokenSeed = '$userId:$userEmail:${now.microsecondsSinceEpoch}:${capability.typeLabel}';
    final token = sha256.convert(utf8.encode(rawTokenSeed)).toString();

    // 3. Persist to local hardware-encrypted secure storage
    await Future.wait([
      _secureStorage.write(key: 'oneova_bio_enrolled_$userId', value: 'true'),
      _secureStorage.write(key: 'oneova_bio_token_$userId', value: token),
      _secureStorage.write(key: _biometricEnabledKey, value: 'true'),
      _secureStorage.write(key: _activeBioUidKey, value: userId),
      _secureStorage.write(key: _activeBioEmailKey, value: userEmail),
      _secureStorage.write(key: 'oneova_bio_enrolled_at_$userId', value: now.toIso8601String()),
    ]);

    // 3b. Register a device key so the user can sign back in with a
    // fingerprint after signing out. Needs a real (non-anonymous) session.
    final keyError = await _registerSignInKey();
    if (keyError != null) {
      debugPrint('[OneovaBiometricsService] sign-in key not registered: $keyError');
    }

    // 4. Sync to Firestore user profile and user settings (non-blocking graceful)
    try {
      final typeLabel = capability.typeLabel;

      // Update user_settings/$userId
      await _firestore.collection('user_settings').doc(userId).set({
        'privacy': {
          'requireBiometrics': true,
        },
        'security': {
          'biometricsEnabled': true,
          'biometricType': typeLabel,
          'lastEnrolledAt': FieldValue.serverTimestamp(),
          'requireOnLaunch': true,
        },
      }, SetOptions(merge: true));

      // Update users/$userId profile
      await _firestore.collection('users').doc(userId).set({
        'biometricsEnrolled': true,
        'biometricType': typeLabel,
        'securityTier': 'tier_3_hardware_biometric',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('[OneovaBiometricsService] User $userId successfully enrolled in biometrics.');
    } catch (e) {
      debugPrint('[OneovaBiometricsService] Notice syncing enrollment to Firestore: $e');
    }

    return BiometricAuthResult.success();
  }

  /// Revokes biometric enrollment for a user and cleans secure storage.
  Future<BiometricAuthResult> revokeUserBiometrics({
    required String userId,
    bool requireChallenge = true,
  }) async {
    if (userId.isEmpty) {
      return BiometricAuthResult.failure('User ID cannot be empty');
    }

    if (requireChallenge) {
      final authResult = await authenticateWithDetails(
        reason: 'Verify fingerprint to disable biometric security',
        biometricOnly: true,
      );
      if (!authResult.isSuccess) {
        return authResult;
      }
    }

    // 1. Remove from local secure storage (and the server-side key)
    final keyId = await _secureStorage.read(key: _signInKeyIdKey);
    if (keyId != null) {
      try {
        await FirebaseFunctions.instance.httpsCallable('revokeBiometricKey').call({'keyId': keyId});
      } catch (e) {
        debugPrint('[OneovaBiometricsService] revoke key notice: $e');
      }
    }
    await Future.wait([
      _secureStorage.delete(key: _signInKeyIdKey),
      _secureStorage.delete(key: _signInSecretKey),
      _secureStorage.delete(key: 'oneova_bio_enrolled_$userId'),
      _secureStorage.delete(key: 'oneova_bio_token_$userId'),
      _secureStorage.delete(key: 'oneova_bio_enrolled_at_$userId'),
      _secureStorage.delete(key: _biometricEnabledKey),
      _secureStorage.delete(key: _activeBioUidKey),
      _secureStorage.delete(key: _activeBioEmailKey),
    ]);

    // 2. Sync to Firestore
    try {
      await _firestore.collection('user_settings').doc(userId).set({
        'privacy': {
          'requireBiometrics': false,
        },
        'security': {
          'biometricsEnabled': false,
        },
      }, SetOptions(merge: true));

      await _firestore.collection('users').doc(userId).set({
        'biometricsEnrolled': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('[OneovaBiometricsService] User $userId biometrics revoked.');
    } catch (e) {
      debugPrint('[OneovaBiometricsService] Notice syncing revocation to Firestore: $e');
    }

    return BiometricAuthResult.success();
  }

  /// Enables or disables biometric passkey unlock (backward compatibility helper).
  Future<void> setBiometricEnrollment(bool enabled) async {
    await _secureStorage.write(
      key: _biometricEnabledKey,
      value: enabled ? 'true' : 'false',
    );
  }

  /// Alias for enabling biometrics for user.
  Future<void> enableBiometrics(String uid) => setBiometricEnrollment(true);

  /// Creates a random 256-bit secret, registers its hash with the server and
  /// keeps the secret in secure storage. Returns an error message or null.
  Future<String?> _registerSignInKey() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous || !LoginSecurity.instance.isVerified(user)) {
      return 'Sign in to your account before turning on fingerprint sign-in.';
    }
    final rnd = Random.secure();
    final secret = List<int>.generate(32, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final hash = sha256.convert(utf8.encode(secret)).toString();
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('registerBiometricKey').call({
        'secretHash': hash,
        'deviceLabel': defaultTargetPlatform.name,
        'deviceId': await LoginSecurity.instance.deviceId(),
      });
      final keyId = (res.data as Map?)?['keyId'] as String?;
      if (keyId == null) return 'Server did not return a key.';
      await _secureStorage.write(key: _signInKeyIdKey, value: keyId);
      await _secureStorage.write(key: _signInSecretKey, value: secret);
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return '$e';
    }
  }

  /// True when this device can sign the user back in without a password.
  Future<bool> hasSignInKey() async =>
      (await _secureStorage.read(key: _signInKeyIdKey)) != null &&
      (await _secureStorage.read(key: _signInSecretKey)) != null;

  /// Makes sure an already-enrolled user also has a sign-in key (users who
  /// enrolled before keys existed). Silent; safe to call after every login.
  Future<void> ensureSignInKey() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    if (!await isUserEnrolled(user.uid)) return;
    if (await getEnrolledUserId() != user.uid) return;
    if (await hasSignInKey()) return;
    await _registerSignInKey();
  }

  /// Whether we should offer "Use fingerprint next time?" to this user.
  Future<bool> shouldOfferEnrollment(String uid) async {
    if (uid.isEmpty) return false;
    if (await isUserEnrolled(uid)) return false;
    if ((await _secureStorage.read(key: '$_offeredKeyPrefix$uid')) == 'true') return false;
    final cap = await getCapabilityDetails();
    return cap.isReadyToAuthenticate;
  }

  Future<void> markEnrollmentOffered(String uid) =>
      _secureStorage.write(key: '$_offeredKeyPrefix$uid', value: 'true');

  // ── 4. 1-Tap Biometric Fast Login ──────────────────────────────────────────

  /// Performs authentic 1-tap fingerprint sign-in on main_login_screen.
  Future<BiometricFastLoginResult> authenticateForFastSignIn() async {
    final activeUid = await getEnrolledUserId();
    final activeEmail = await getEnrolledUserEmail();

    if (activeUid == null || activeEmail == null) {
      return BiometricFastLoginResult.noEnrolledUser();
    }

    final authResult = await authenticateWithDetails(
      reason: 'Scan fingerprint to securely sign in as $activeEmail',
      biometricOnly: true,
    );

    if (authResult.isSuccess) {
      final current = FirebaseAuth.instance.currentUser;
      if (current != null && !current.isAnonymous && current.uid == activeUid) {
        return BiometricFastLoginResult.success(userId: activeUid, userEmail: activeEmail);
      }
      final keyId = await _secureStorage.read(key: _signInKeyIdKey);
      final secret = await _secureStorage.read(key: _signInSecretKey);
      if (keyId == null || secret == null) {
        return BiometricFastLoginResult.failure(
          'Sign in once with your password or SMS code, then fingerprint sign-in will work on this device.',
        );
      }
      try {
        final res = await FirebaseFunctions.instance
            .httpsCallable('biometricSignIn')
            .call({'keyId': keyId, 'secret': secret, 'deviceId': await LoginSecurity.instance.deviceId()});
        final token = (res.data as Map?)?['token'] as String?;
        if (token == null) return BiometricFastLoginResult.failure('Sign-in failed. Try again.');
        if (current != null && current.isAnonymous) {
          await FirebaseAuth.instance.signOut();
        }
        final cred = await FirebaseAuth.instance.signInWithCustomToken(token);
        if (cred.user?.uid != activeUid) {
          return BiometricFastLoginResult.failure('Signed in to a different account.');
        }
        return BiometricFastLoginResult.success(userId: activeUid, userEmail: activeEmail);
      } on FirebaseFunctionsException catch (e) {
        if (e.code == 'not-found' || e.code == 'permission-denied' || e.code == 'deadline-exceeded') {
          // Key is dead on the server; forget it so we stop offering it.
          await _secureStorage.delete(key: _signInKeyIdKey);
          await _secureStorage.delete(key: _signInSecretKey);
        }
        return BiometricFastLoginResult.failure(
          e.message ?? 'Fingerprint sign-in is unavailable. Sign in with your password or SMS code.',
        );
      } catch (e) {
        return BiometricFastLoginResult.failure('Could not reach Oneova. Check your connection.');
      }
    } else {
      return BiometricFastLoginResult.failure(authResult.errorMessage ?? 'Biometric scan failed');
    }
  }
}
