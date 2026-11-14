import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'device_key.dart';

/// Where this phone stands for payments.
enum PaymentDeviceStatus { unsupported, noBiometrics, notRegistered, needsTrust, trusted }

class PaymentDevice {
  final String id;
  final String label;
  final String hardware;
  final bool trusted;
  final DateTime? coolDownUntil;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
  final bool thisPhone;
  const PaymentDevice({
    required this.id,
    required this.label,
    required this.hardware,
    required this.trusted,
    this.coolDownUntil,
    this.createdAt,
    this.lastUsedAt,
    this.thisPhone = false,
  });
}

class VerifyResult {
  final bool ok;
  final bool registered;
  final bool trusted;
  const VerifyResult({required this.ok, required this.registered, required this.trusted});
}

/// Registers this phone's hardware key with the server and proves it with a
/// biometric. Server: functions/src/pay/devices.ts. Nothing secret is stored
/// here: the device id is not a secret, the private key never leaves the chip.
class PaymentDeviceService {
  PaymentDeviceService._();
  static final PaymentDeviceService instance = PaymentDeviceService._();

  final FirebaseFunctions _fn = FirebaseFunctions.instance;
  static const _storage = FlutterSecureStorage();

  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('signed out');
    return uid;
  }

  /// One key per account on this phone.
  String _alias(String uid) => 'u_${uid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '')}';
  String _idKey(String uid) => 'pay_device_id_$uid';

  Future<String?> localDeviceId() async => _storage.read(key: _idKey(_uid));

  Future<PaymentDeviceStatus> status() async {
    final a = await DeviceKey.availability();
    if (a == 'unsupported' || a == 'no_hardware') return PaymentDeviceStatus.unsupported;
    if (a != 'ready') return PaymentDeviceStatus.noBiometrics;
    final uid = _uid;
    final id = await _storage.read(key: _idKey(uid));
    if (id == null || !await DeviceKey.exists(_alias(uid))) return PaymentDeviceStatus.notRegistered;
    final mine = (await list()).where((d) => d.id == id).firstOrNull;
    if (mine == null) {
      await _forget(uid);
      return PaymentDeviceStatus.notRegistered;
    }
    return mine.trusted ? PaymentDeviceStatus.trusted : PaymentDeviceStatus.needsTrust;
  }

  Future<Map<String, dynamic>> _call(String name, [Map<String, Object?> data = const {}]) async {
    final r = await _fn.httpsCallable(name).call<Object?>(data);
    return Map<String, dynamic>.from((r.data as Map?) ?? const {});
  }

  Future<({String id, String challenge})> _challenge(String purpose) async {
    final r = await _call('payDeviceChallenge', {'purpose': purpose});
    return (id: r['challengeId'] as String, challenge: r['challenge'] as String);
  }

  /// Exactly the bytes the server rebuilds in `proofPayload()` (sorted keys, no spaces).
  static Uint8List proof(Map<String, Object?> fields) {
    final sorted = SplayTreeMap<String, Object?>.from({'v': 1, ...fields}..removeWhere((_, v) => v == null));
    return Uint8List.fromList(utf8.encode(jsonEncode(sorted)));
  }

  Future<String> _label() async {
    try {
      if (Platform.isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        return '${a.manufacturer} ${a.model}'.trim();
      }
    } catch (_) {}
    return 'This phone';
  }

  /// Makes the key, proves it with a biometric, and registers it.
  Future<String> register() async {
    final uid = _uid;
    final alias = _alias(uid);
    final c = await _challenge('register');
    final key = await DeviceKey.create(alias, c.challenge);
    try {
      final sig = await DeviceKey.sign(
        alias,
        proof({'purpose': 'register', 'uid': uid, 'challengeId': c.id, 'challenge': c.challenge}),
        title: 'Register this phone for payments',
        subtitle: 'Use your fingerprint or face',
      );
      final r = await _call('payDeviceRegister', {
        'challengeId': c.id,
        'publicKey': key.publicKey,
        'attestation': key.attestation,
        'signature': sig,
        'label': await _label(),
      });
      final id = r['deviceId'] as String;
      await _storage.write(key: _idKey(uid), value: id);
      return id;
    } catch (_) {
      await DeviceKey.delete(alias);
      rethrow;
    }
  }

  /// Call after the email code screen (purpose sensitive_action) returns true.
  Future<DateTime?> trust() async {
    final id = await localDeviceId();
    if (id == null) throw const DeviceKeyException('no_key');
    final r = await _call('payDeviceTrust', {'deviceId': id});
    final cd = r['coolDownUntil'];
    return cd is num ? DateTime.fromMillisecondsSinceEpoch(cd.toInt()) : null;
  }

  /// Live round trip: biometric → hardware signature → server check.
  Future<VerifyResult> verify({String title = 'Confirm it’s you', String subtitle = ''}) async {
    final uid = _uid;
    final id = await localDeviceId();
    if (id == null || !await DeviceKey.exists(_alias(uid))) return const VerifyResult(ok: false, registered: false, trusted: false);
    final c = await _challenge('verify');
    String sig;
    try {
      sig = await DeviceKey.sign(
        _alias(uid),
        proof({'purpose': 'verify', 'uid': uid, 'challengeId': c.id, 'challenge': c.challenge, 'deviceId': id}),
        title: title,
        subtitle: subtitle,
      );
    } on DeviceKeyException catch (e) {
      if (e.code == 'invalidated' || e.code == 'no_key') {
        await _forget(uid);
        return const VerifyResult(ok: false, registered: false, trusted: false);
      }
      rethrow;
    }
    final r = await _call('payDeviceVerify', {'challengeId': c.id, 'deviceId': id, 'signature': sig});
    final registered = r['registered'] == true;
    if (!registered) await _forget(uid);
    return VerifyResult(ok: r['ok'] == true, registered: registered, trusted: r['trusted'] == true);
  }

  Future<List<PaymentDevice>> list() async {
    final mine = await _storage.read(key: _idKey(_uid));
    final r = await _call('payDeviceList');
    DateTime? t(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    return [
      for (final d in (r['devices'] as List? ?? const []))
        if (d is Map)
          PaymentDevice(
            id: d['id'] as String,
            label: (d['label'] as String?)?.isNotEmpty == true ? d['label'] as String : 'Phone',
            hardware: d['hardware'] as String? ?? '',
            trusted: d['trusted'] == true,
            coolDownUntil: t(d['coolDownUntil']),
            createdAt: t(d['createdAt']),
            lastUsedAt: t(d['lastUsedAt']),
            thisPhone: d['id'] == mine,
          ),
    ];
  }

  Future<void> revoke(String deviceId) async {
    await _call('payDeviceRevoke', {'deviceId': deviceId});
    final uid = _uid;
    if (await _storage.read(key: _idKey(uid)) == deviceId) await _forget(uid);
  }

  Future<void> _forget(String uid) async {
    await _storage.delete(key: _idKey(uid));
    await DeviceKey.delete(_alias(uid));
  }
}
