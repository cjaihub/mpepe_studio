import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper over the native payment device key (Android:
/// `DeviceKeyChannel.kt`). The private key lives in the phone's secure hardware
/// and signs only after a strong fingerprint or face check.
class DeviceKey {
  DeviceKey._();

  static const MethodChannel _ch = MethodChannel('com.oneova.app/device_key');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 'ready', 'not_enrolled', 'no_hardware', 'unavailable' or 'unsupported'.
  static Future<String> availability() async {
    if (!supported) return 'unsupported';
    return await _ch.invokeMethod<String>('available') ?? 'unavailable';
  }

  static Future<bool> exists(String alias) async =>
      supported && (await _ch.invokeMethod<bool>('exists', {'alias': alias}) ?? false);

  static Future<void> delete(String alias) async {
    if (supported) await _ch.invokeMethod<bool>('delete', {'alias': alias});
  }

  /// Makes a new key for [challenge] (base64url). Returns the public key
  /// (base64 SPKI) and the attestation chain (base64 DER, leaf first).
  static Future<({String publicKey, List<String> attestation})> create(String alias, String challenge) async {
    final r = await _ch.invokeMapMethod<String, Object?>('create', {'alias': alias, 'challenge': challenge});
    if (r == null) throw const DeviceKeyException('device_key');
    return (
      publicKey: r['publicKey'] as String,
      attestation: [for (final c in (r['attestation'] as List? ?? const [])) c as String],
    );
  }

  /// Shows the system biometric prompt and signs [data]. Returns base64 DER.
  static Future<String> sign(String alias, Uint8List data, {required String title, String subtitle = ''}) async {
    try {
      final s = await _ch.invokeMethod<String>('sign', {
        'alias': alias,
        'data': _b64url(data),
        'title': title,
        'subtitle': subtitle,
      });
      if (s == null) throw const DeviceKeyException('sign_failed');
      return s;
    } on PlatformException catch (e) {
      throw DeviceKeyException(e.code);
    }
  }

  static String _b64url(Uint8List b) => base64Url.encode(b).replaceAll('=', '');
}

class DeviceKeyException implements Exception {
  /// cancelled, lockout, invalidated, no_key, auth_error, sign_failed, device_key
  final String code;
  const DeviceKeyException(this.code);

  String get message => switch (code) {
        'cancelled' => 'Cancelled.',
        'lockout' => 'Too many tries. Unlock your phone, then try again.',
        'invalidated' => 'Your fingerprints or face changed, so register this phone again.',
        'no_key' => 'This phone isn’t registered for payments yet.',
        _ => 'We couldn’t confirm it’s you. Try again.',
      };

  @override
  String toString() => 'DeviceKeyException($code)';
}
