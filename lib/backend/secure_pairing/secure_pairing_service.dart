import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
    
    // We don't save the key yet, because the salt must be shared with the client.
    // For local pairing over Firebase, we will actually just use the 6-digit PIN 
    // as the shared secret (the salt can just be a known constant or we don't use it, 
    // but to be secure, the Desktop should write the salt to Firestore so Mobile can read it).
    
    state = state.copyWith(activePin: pin);
    return pin;
  }

  /// Derives the AES key once the Desktop knows the Mobile has authenticated
  void setDerivedKey(enc.Key key) {
    state = state.copyWith(activeKey: key);
  }

  Future<String?> loadPersistedPairing() async {
    final uid = await _storage.read(key: 'paired_uid');
    final keyBase64 = await _storage.read(key: 'paired_key');

    if (uid != null && keyBase64 != null) {
      final key = enc.Key.fromBase64(keyBase64);
      state = state.copyWith(activeKey: key);
      return uid;
    }
    return null;
  }

  Future<void> persistPairing(String uid, enc.Key key) async {
    await _storage.write(key: 'paired_uid', value: uid);
    await _storage.write(key: 'paired_key', value: key.base64);
  }

  Future<void> clearPairing() async {
    await _storage.delete(key: 'paired_uid');
    await _storage.delete(key: 'paired_key');
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
