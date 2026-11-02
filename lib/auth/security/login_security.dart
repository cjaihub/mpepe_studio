import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'login_history.dart';

/// One proof a user gave during sign-in.
enum AuthFactor {
  /// Oneova password, verified by Firebase Auth (email/password provider).
  password,

  /// SMS code, verified by Firebase Phone Auth.
  smsOtp,

  /// Google sign-in, verified by Firebase Auth.
  federated,

  /// Fingerprint / face, verified by the OS (local_auth).
  biometric,

  /// App PIN set on this device by this same account.
  pin,

  /// This device's fingerprint-sign-in key, verified by the server.
  deviceKey,

  /// This device is registered as trusted for the account in Firestore.
  trustedDevice,
}

/// Result of scanning this device against the account's trusted devices.
class DeviceScan {
  final String deviceId;
  final String label;
  final bool trusted;
  final bool isPhysicalDevice;
  final DateTime? trustedAt;

  const DeviceScan({
    required this.deviceId,
    required this.label,
    required this.trusted,
    required this.isPhysicalDevice,
    this.trustedAt,
  });
}

/// Oneova sign-in security: device identity, trusted-device registry and the
/// "at least two factors" session gate that the router enforces.
///
/// Rules ([missingFactor] / [meetsPolicy]):
/// 1. A device that is not trusted for the account must pass an SMS code
///    before the session is accepted; only then is the device trusted.
/// 2. At least two different factors.
/// 3. At least one of password / fingerprint / federated sign-in, so a
///    stolen SIM plus a stolen phone is not enough on its own.
/// 4. A fingerprint never creates or opens an account by itself: it only
///    counts together with this device's server-issued key or an existing
///    session, and only on a device already trusted for that account.
class LoginSecurity extends ChangeNotifier {
  LoginSecurity._() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null || (_verifiedUid != null && user.uid != _verifiedUid)) {
        _verifiedUid = null;
        _pending.clear();
        // Signing out ends the verified session for good on this device.
        if (user == null && _restored) _storage.delete(key: _verifiedKey);
      }
      notifyListeners();
    });
  }

  static final LoginSecurity instance = LoginSecurity._();

  static const _storage = FlutterSecureStorage();
  static const _deviceIdKey = 'oneova_trusted_device_id';
  static const _verifiedKey = 'oneova_mfa_verified_session';

  // ignore: unused_field
  StreamSubscription<User?>? _authSub;
  String? _verifiedUid;
  bool _restored = false;
  String? _deviceId;
  String? _deviceLabel;
  bool _isPhysical = true;
  final Map<String, Set<AuthFactor>> _pending = {};

  /// Signed-in user domain used for password sign-in by phone number.
  static const authEmailDomain = 'phone.oneova.app';

  /// The Firebase email/password identity for a phone number (E.164).
  static String authEmailForPhone(String e164) {
    final digits = e164.replaceAll(RegExp(r'\D'), '');
    return 'p$digits@$authEmailDomain';
  }

  bool get restored => _restored;

  /// True when [user] is authenticated with Oneova. Once signed in,
  /// session remains permanently trusted until explicit logout or security alert.
  bool isVerified(User? user) => user != null && !user.isAnonymous;

  /// Factors already given for [uid] in this app run (e.g. the SMS code in the
  /// signup wizard), so the login screen does not ask for them again.
  Set<AuthFactor> pendingFactorsFor(String uid) => {...?_pending[uid]};

  void recordFactor(String uid, AuthFactor factor) {
    (_pending[uid] ??= <AuthFactor>{}).add(factor);
  }

  /// Restores the verified flag after an app restart. The flag is bound to
  /// this device id and uid, and is dropped if the device was removed from the
  /// account's trusted devices (e.g. "sign out other devices").
  Future<void> restore() async {
    if (_restored) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      final saved = await _storage.read(key: _verifiedKey).timeout(const Duration(seconds: 2));
      if (user != null && !user.isAnonymous && saved != null) {
        final id = await deviceId();
        if (saved == '${user.uid}|$id') {
          final scan = await scanDevice(user.uid).timeout(const Duration(seconds: 3));
          if (scan.trusted) {
            _verifiedUid = user.uid;
          } else {
            await _storage.delete(key: _verifiedKey).timeout(const Duration(seconds: 2));
          }
        }
      }
    } on TimeoutException {
      // Offline: keep the bound flag; the check runs again on next launch.
      final user = FirebaseAuth.instance.currentUser;
      try {
        final saved = await _storage.read(key: _verifiedKey).timeout(const Duration(seconds: 2));
        if (user != null && saved == '${user.uid}|${await deviceId()}') _verifiedUid = user.uid;
      } catch (_) {}
    } catch (e) {
      debugPrint('[LoginSecurity] restore: $e');
    }
    _restored = true;
    notifyListeners();
  }

  /// Stable random id for this install, kept in Keystore / Keychain.
  Future<String> deviceId() async {
    if (_deviceId != null) return _deviceId!;
    String? id;
    try {
      id = await _storage.read(key: _deviceIdKey).timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('[LoginSecurity] deviceId read timeout/error: $e');
    }
    if (id == null || id.length < 32) {
      final rnd = Random.secure();
      id = List<int>.generate(16, (_) => rnd.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      try {
        await _storage.write(key: _deviceIdKey, value: id).timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint('[LoginSecurity] deviceId write timeout/error: $e');
      }
    }
    _deviceId = id;
    return id;
  }

  Future<void> _loadDeviceInfo() async {
    if (_deviceLabel != null) return;
    try {
      final info = DeviceInfoPlugin();
      if (!kIsWeb && Platform.isAndroid) {
        final a = await info.androidInfo;
        _deviceLabel = '${a.manufacturer} ${a.model}'.trim();
        _isPhysical = a.isPhysicalDevice;
      } else if (!kIsWeb && Platform.isIOS) {
        final i = await info.iosInfo;
        _deviceLabel = i.utsname.machine;
        _isPhysical = i.isPhysicalDevice;
      } else {
        _deviceLabel = kIsWeb ? 'Web browser' : Platform.operatingSystem;
      }
    } catch (_) {
      _deviceLabel = kIsWeb ? 'Web browser' : defaultTargetPlatform.name;
    }
  }

  DocumentReference<Map<String, dynamic>> _deviceDoc(String uid, String id) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('trusted_devices').doc(id);

  /// Checks whether this device is trusted for [uid].
  Future<DeviceScan> scanDevice(String uid) async {
    final id = await deviceId();
    await _loadDeviceInfo();
    var trusted = false;
    DateTime? at;
    try {
      final doc = await _deviceDoc(uid, id).get().timeout(const Duration(seconds: 2));
      trusted = doc.exists && doc.data()?['revoked'] != true;
      at = (doc.data()?['trustedAt'] as Timestamp?)?.toDate();
    } catch (e) {
      debugPrint('[LoginSecurity] scan: $e');
    }
    return DeviceScan(
      deviceId: id,
      label: _deviceLabel ?? 'This device',
      trusted: trusted,
      isPhysicalDevice: _isPhysical,
      trustedAt: at,
    );
  }

  /// What the user still has to give, or null when the policy is met.
  /// [hasPassword] / [biometricReady] describe the account on this device.
  static AuthFactor? missingFactor(
    Set<AuthFactor> factors, {
    required bool deviceTrusted,
    required bool hasPassword,
    required bool biometricReady,
    bool pinReady = false,
  }) {
    final f = {...factors, if (deviceTrusted) AuthFactor.trustedDevice};
    final deviceCheck = f.contains(AuthFactor.biometric) || f.contains(AuthFactor.pin);
    final localReady = biometricReady || pinReady;
    final localFactor = biometricReady ? AuthFactor.biometric : AuthFactor.pin;
    // Rule 1: new device must pass an SMS code.
    if (!deviceTrusted && !f.contains(AuthFactor.smsOtp)) return AuthFactor.smsOtp;
    // Rule 3: a knowledge / inherence / federated proof.
    final hasStrong = f.contains(AuthFactor.password) ||
        f.contains(AuthFactor.federated) ||
        (deviceCheck && deviceTrusted);
    if (!hasStrong) {
      if (deviceTrusted && localReady) return localFactor;
      return AuthFactor.password;
    }
    // Rule 2: two different factors.
    if (f.length < 2) return AuthFactor.smsOtp;
    // Extra layer: password-only on a trusted device also needs the
    // fingerprint (or the account's PIN) when it is set up here.
    if (localReady &&
        deviceTrusted &&
        !deviceCheck &&
        !f.contains(AuthFactor.smsOtp) &&
        !f.contains(AuthFactor.federated)) {
      return localFactor;
    }
    return null;
  }

  static bool meetsPolicy(Set<AuthFactor> factors, {required bool deviceTrusted}) =>
      missingFactor(factors, deviceTrusted: deviceTrusted, hasPassword: true, biometricReady: false) == null;

  /// Accepts the session for [user] after the policy is met. Trusts this
  /// device when an SMS code was part of the sign-in.
  Future<void> markVerified(User user, Set<AuthFactor> factors, {required bool deviceTrusted}) async {
    if (user.isAnonymous) throw StateError('Guest sessions cannot be verified');
    if (!meetsPolicy(factors, deviceTrusted: deviceTrusted)) {
      throw StateError('Sign-in needs two different checks');
    }
    final id = await deviceId();
    await _loadDeviceInfo();
    final now = FieldValue.serverTimestamp();
    final methods = factors.map((f) => f.name).toList()..sort();
    try {
      if (!deviceTrusted && factors.contains(AuthFactor.smsOtp)) {
        await _deviceDoc(user.uid, id).set({
          'label': _deviceLabel ?? 'This device',
          'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
          'physical': _isPhysical,
          'trustedAt': now,
          'trustedVia': 'sms_otp',
          'lastSeenAt': now,
        });
      } else {
        await _deviceDoc(user.uid, id).set({'lastSeenAt': now}, SetOptions(merge: true));
      }
      await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('security_events').add({
        'type': 'sign_in',
        'factors': methods,
        'deviceId': id,
        'deviceLabel': _deviceLabel,
        'newDevice': !deviceTrusted,
        'at': now,
      });
    } catch (e) {
      debugPrint('[LoginSecurity] device record: $e');
    }
    // Account login log (Settings → Security → Login activity). Not awaited:
    // a slow location or network must not hold up the sign-in.
    unawaited(LoginHistory.instance.recordSuccess(user, method: methods.join('+'), newDevice: !deviceTrusted));
    _verifiedUid = user.uid;
    _pending.remove(user.uid);
    await _storage.write(key: _verifiedKey, value: '${user.uid}|$id');
    notifyListeners();
  }

  /// Forget the verified session (sign-out, lock, revoke).
  Future<void> clear() async {
    _verifiedUid = null;
    _pending.clear();
    await _storage.delete(key: _verifiedKey);
    notifyListeners();
  }

  /// Routes a guest (anonymous) session may open.
  static bool isGuestRoute(String path) =>
      path == '/hub/home' || path == '/biz_feed' || path == '/hub/discover' ||
      (path.startsWith('/profile/') && path != '/profile/me' && path != '/profile/earnings' && path != '/profile/monetization');
}
