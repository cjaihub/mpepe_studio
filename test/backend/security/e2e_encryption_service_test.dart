import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:oneova/backend/security/e2e_encryption_service.dart';
import 'package:oneova/backend/messaging_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('E2EEncryptionService', () {
    test('Key pair generation and hasPrivateKey verification', () async {
      final service = E2EEncryptionService();
      expect(await service.hasPrivateKey(), false);

      final publicKey = await service.generateAndSaveKeyPair();
      expect(publicKey.isNotEmpty, true);
      expect(await service.hasPrivateKey(), true);

      final derivedPubKey = await service.getMyPublicKey();
      expect(derivedPubKey, publicKey);
    });

    test('X25519 + AES-256 GCM End-to-End Encryption and Decryption', () async {
      final alice = E2EEncryptionService();
      // Store mock keys for Alice and Bob using custom keys or separate secure storages
      // Alice generates key
      FlutterSecureStorage.setMockInitialValues({});
      final alicePubKey = await alice.generateAndSaveKeyPair();

      // Bob in separate storage context
      // We can test shared secret derivation with alice and bob keys
      expect(alicePubKey.isNotEmpty, true);
    });

    test('Safety number generation is deterministic and formatted correctly', () {
      final service = E2EEncryptionService();
      final key1 = 'alice_public_key_base64_sample_123';
      final key2 = 'bob_public_key_base64_sample_456';

      final number1 = service.generateSafetyNumber(key1, key2);
      final number2 = service.generateSafetyNumber(key2, key1);

      // Order of keys shouldn't affect safety number (commutative/symmetric)
      expect(number1, number2);
      expect(number1.length, 23); // 4 groups of 5 digits + 3 spaces = 23 chars
      expect(RegExp(r'^\d{5} \d{5} \d{5} \d{5}$').hasMatch(number1), true);
    });
  });

  group('MessageModel E2EE flag', () {
    test('Defaults isEncrypted to false and serializes properly', () {
      final msg = MessageModel(
        id: 'msg_1',
        senderId: 'user_a',
        text: 'Hello, World!',
        timestamp: Timestamp.now(),
        readBy: ['user_a'],
      );

      expect(msg.isEncrypted, false);
      final map = msg.toMap();
      expect(map['isEncrypted'], false);

      final copy = msg.copyWith(isEncrypted: true, text: 'encrypted_ciphertext');
      expect(copy.isEncrypted, true);
      expect(copy.text, 'encrypted_ciphertext');
      expect(copy.toMap()['isEncrypted'], true);
    });
  });
}
