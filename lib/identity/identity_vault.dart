import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/services/oneova_biometrics_service.dart';

/// Keeps identity credentials on this phone only, encrypted with AES-256-GCM.
///
/// The 256-bit key is random, lives in the Android Keystore / iOS Keychain
/// (flutter_secure_storage), and is never uploaded. Reading a credential asks
/// for the phone's fingerprint / face / PIN first when the device has one.
class IdentityVault {
  IdentityVault({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static final _algo = AesGcm.with256bits();
  static const _keyName = 'oneova_id_vault_key_v1';
  static String _slot(String uid, String kind) => 'oneova_id_cred_${kind}_$uid';

  Future<SecretKey> _key() async {
    final existing = await _storage.read(key: _keyName);
    if (existing != null) return SecretKey(base64Decode(existing));
    final k = await _algo.newSecretKey();
    await _storage.write(key: _keyName, value: base64Encode(await k.extractBytes()));
    return k;
  }

  Future<String> encrypt(String plain) async {
    final box = await _algo.encrypt(utf8.encode(plain), secretKey: await _key());
    return 'v1.${base64Encode(box.concatenation())}';
  }

  Future<String?> decrypt(String sealed) async {
    if (!sealed.startsWith('v1.')) return null;
    try {
      final box = SecretBox.fromConcatenation(base64Decode(sealed.substring(3)),
          nonceLength: _algo.nonceLength, macLength: _algo.macAlgorithm.macLength);
      return utf8.decode(await _algo.decrypt(box, secretKey: await _key()));
    } catch (_) {
      return null; // tampered or from another install
    }
  }

  Future<void> save(String uid, String kind, String credential) async =>
      _storage.write(key: _slot(uid, kind), value: await encrypt(credential));

  Future<bool> has(String uid, String kind) async => (await _storage.read(key: _slot(uid, kind))) != null;

  /// Asks for biometrics (when available) before returning the credential.
  Future<String?> read(String uid, String kind, {String reason = 'Open your Oneova ID'}) async {
    final sealed = await _storage.read(key: _slot(uid, kind));
    if (sealed == null) return null;
    final bio = OneovaBiometricsService();
    if (await bio.isDeviceSupported() && !await bio.authenticate(reason: reason)) return null;
    return decrypt(sealed);
  }

  Future<void> wipe(String uid, String kind) => _storage.delete(key: _slot(uid, kind));
}

/// Reads the claims of an SD-JWT VC kept on the phone (no network).
Map<String, Object?> credentialClaims(String sdJwt) {
  final parts = sdJwt.split('~');
  final out = <String, Object?>{};
  for (final d in parts.skip(1).where((p) => p.isNotEmpty)) {
    try {
      final arr = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(d)))) as List;
      if (arr.length == 3) out['${arr[1]}'] = arr[2];
    } catch (_) {}
  }
  return out;
}
