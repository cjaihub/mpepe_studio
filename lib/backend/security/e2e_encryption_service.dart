import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final e2eEncryptionServiceProvider = Provider<E2EEncryptionService>((ref) {
  return E2EEncryptionService();
});

class E2EEncryptionService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final X25519 _keyExchangeAlgorithm = X25519();
  final AesGcm _encryptionAlgorithm = AesGcm.with256bits();
  final Map<String, String> _publicKeyCache = {};

  static const String _privateKeyKey = 'e2ee_private_key';

  /// Generates a new X25519 key pair and saves the private key securely.
  /// Returns the public key in Base64 for uploading to the server.
  Future<String> generateAndSaveKeyPair() async {
    final keyPair = await _keyExchangeAlgorithm.newKeyPair();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();

    await _secureStorage.write(
      key: _privateKeyKey,
      value: base64Encode(privateKeyBytes),
    );

    return base64Encode(publicKey.bytes);
  }

  /// Calculates the shared secret using our private key and their public key.
  Future<SecretKey> _calculateSharedSecret(String theirPublicKeyBase64) async {
    final myPrivateKeyBase64 = await _secureStorage.read(key: _privateKeyKey);
    if (myPrivateKeyBase64 == null) {
      throw Exception('Private key not found. Cannot negotiate shared secret.');
    }

    final myPrivateKeyBytes = base64Decode(myPrivateKeyBase64);
    final myKeyPair = await _keyExchangeAlgorithm.newKeyPairFromSeed(myPrivateKeyBytes);

    final theirPublicKeyBytes = base64Decode(theirPublicKeyBase64);
    final theirPublicKey = SimplePublicKey(theirPublicKeyBytes, type: KeyPairType.x25519);

    return await _keyExchangeAlgorithm.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: theirPublicKey,
    );
  }

  /// Encrypts plaintext using the negotiated shared secret.
  /// Returns a Base64 string containing both the ciphertext and nonce.
  Future<String> encryptMessage(String plaintext, String recipientPublicKeyBase64) async {
    final sharedSecret = await _calculateSharedSecret(recipientPublicKeyBase64);
    
    final secretBox = await _encryptionAlgorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: sharedSecret,
    );

    // Combine nonce and ciphertext (mac is included in ciphertext by cryptography package)
    final combinedBytes = [...secretBox.nonce, ...secretBox.cipherText, ...secretBox.mac.bytes];
    return base64Encode(combinedBytes);
  }

  /// Decrypts a previously encrypted message.
  Future<String> decryptMessage(String encryptedBase64, String senderPublicKeyBase64) async {
    try {
      final sharedSecret = await _calculateSharedSecret(senderPublicKeyBase64);
      final combinedBytes = base64Decode(encryptedBase64);

      final nonceLength = _encryptionAlgorithm.nonceLength;
      final macLength = _encryptionAlgorithm.macAlgorithm.macLength;

      if (combinedBytes.length < nonceLength + macLength) {
        return encryptedBase64;
      }

      final nonce = combinedBytes.sublist(0, nonceLength);
      final cipherText = combinedBytes.sublist(nonceLength, combinedBytes.length - macLength);
      final macBytes = combinedBytes.sublist(combinedBytes.length - macLength);

      final secretBox = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(macBytes),
      );

      final cleartextBytes = await _encryptionAlgorithm.decrypt(
        secretBox,
        secretKey: sharedSecret,
      );

      return utf8.decode(cleartextBytes);
    } catch (e) {
      debugPrint('E2EE Decrypt error, fallback to raw: $e');
      return encryptedBase64;
    }
  }

  /// Checks if this device currently holds an E2EE private key.
  Future<bool> hasPrivateKey() async {
    final key = await _secureStorage.read(key: _privateKeyKey);
    return key != null && key.isNotEmpty;
  }

  /// Returns the current user's Base64 public key derived from the stored private key.
  Future<String?> getMyPublicKey() async {
    try {
      final myPrivateKeyBase64 = await _secureStorage.read(key: _privateKeyKey);
      if (myPrivateKeyBase64 == null) return null;
      final myPrivateKeyBytes = base64Decode(myPrivateKeyBase64);
      final myKeyPair = await _keyExchangeAlgorithm.newKeyPairFromSeed(myPrivateKeyBytes);
      final publicKey = await myKeyPair.extractPublicKey();
      return base64Encode(publicKey.bytes);
    } catch (e) {
      debugPrint('Error deriving public key: $e');
      return null;
    }
  }

  /// Ensures the user has an E2EE key pair on device and the public key is registered in Firestore.
  Future<void> ensureUserE2eeKeys(String userId) async {
    if (userId.isEmpty) return;
    try {
      final exists = await hasPrivateKey();
      String? pubKey;
      if (!exists) {
        pubKey = await generateAndSaveKeyPair();
        await FirebaseFirestore.instance.collection('users').doc(userId).set({
          'e2eePublicKey': pubKey,
        }, SetOptions(merge: true));
      } else {
        // Ensure Firestore also has the public key in case this device is set up but user record lacks it
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
        if (!userDoc.exists || userDoc.data()?['e2eePublicKey'] == null) {
          pubKey = await getMyPublicKey();
          if (pubKey != null) {
            await FirebaseFirestore.instance.collection('users').doc(userId).set({
              'e2eePublicKey': pubKey,
            }, SetOptions(merge: true));
          }
        }
      }
    } catch (e) {
      debugPrint('Error ensuring user E2EE keys: $e');
    }
  }

  /// Fetches the recipient's public key from Firestore.
  Future<String?> getRecipientPublicKey(String recipientUserId) async {
    if (recipientUserId.isEmpty) return null;
    if (_publicKeyCache.containsKey(recipientUserId)) {
      return _publicKeyCache[recipientUserId];
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(recipientUserId).get();
      if (doc.exists) {
        final key = doc.data()?['e2eePublicKey'] as String?;
        if (key != null && key.isNotEmpty) {
          _publicKeyCache[recipientUserId] = key;
          return key;
        }
      }
    } catch (e) {
      debugPrint('Error fetching recipient public key: $e');
    }
    return null;
  }

  /// Generates a human-readable safety number / fingerprint for verifying encryption between two users.
  String generateSafetyNumber(String myPubKey, String theirPubKey) {
    if (myPubKey.isEmpty || theirPubKey.isEmpty) return '00000 00000 00000 00000';
    final sorted = [myPubKey, theirPubKey]..sort();
    final bytes = utf8.encode(sorted.join('::'));
    final digest = crypto.sha256.convert(bytes);
    final hex = digest.toString();
    final num1 = BigInt.parse(hex.substring(0, 16), radix: 16).toString().padLeft(20, '0').substring(0, 20);
    return '${num1.substring(0, 5)} ${num1.substring(5, 10)} ${num1.substring(10, 15)} ${num1.substring(15, 20)}';
  }

  // --- PER-PEER KEYS (chat media, call frames) ---

  /// Derives a purpose-specific 256-bit key from the X25519 secret shared
  /// with [peerPublicKeyBase64], so media and call frames never reuse the
  /// raw text key. Both sides of a 1:1 chat derive the same key.
  Future<SecretKey> _derivePeerSubKey(String peerPublicKeyBase64, String info) async {
    final shared = await _calculateSharedSecret(peerPublicKeyBase64);
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: shared,
      nonce: utf8.encode('oneova-shield-v1'),
      info: utf8.encode(info),
    );
  }

  /// Encrypts a chat attachment with the per-chat key (nonce + ciphertext + mac).
  Future<List<int>> encryptBytesForPeer(List<int> data, String peerPublicKeyBase64) async {
    final key = await _derivePeerSubKey(peerPublicKeyBase64, 'chat-media');
    return encryptBytes(data, key);
  }

  /// Decrypts an attachment made by [encryptBytesForPeer]. Throws on tampering.
  Future<List<int>> decryptBytesFromPeer(List<int> data, String peerPublicKeyBase64) async {
    final key = await _derivePeerSubKey(peerPublicKeyBase64, 'chat-media');
    return decryptBytes(data, key);
  }

  /// Raw 32-byte key for WebRTC frame encryption in call [callId].
  Future<Uint8List> deriveCallFrameKey(String peerPublicKeyBase64, String callId) async {
    final key = await _derivePeerSubKey(peerPublicKeyBase64, 'call-frames:$callId');
    return Uint8List.fromList(await key.extractBytes());
  }

  /// Short hash of a public key, exchanged during call setup so both sides
  /// can confirm they hold matching keys before turning frame encryption on.
  String publicKeyFingerprint(String publicKeyBase64) =>
      crypto.sha256.convert(utf8.encode(publicKeyBase64)).toString().substring(0, 32);

  // --- ATTACHMENT ENCRYPTION ---

  /// Generates a random symmetric key for encrypting an attachment.
  Future<SecretKey> generateSymmetricKey() async {
    return await _encryptionAlgorithm.newSecretKey();
  }

  /// Exports a symmetric key to a Base64 string so it can be sent in a message.
  Future<String> exportSymmetricKey(SecretKey key) async {
    final keyBytes = await key.extractBytes();
    return base64Encode(keyBytes);
  }

  /// Imports a symmetric key from a Base64 string.
  Future<SecretKey> importSymmetricKey(String base64Key) async {
    final keyBytes = base64Decode(base64Key);
    return SecretKey(keyBytes);
  }

  /// Encrypts raw bytes (e.g., file data) using a symmetric key.
  Future<List<int>> encryptBytes(List<int> data, SecretKey key) async {
    final secretBox = await _encryptionAlgorithm.encrypt(
      data,
      secretKey: key,
    );
    // Combine nonce + ciphertext + mac
    return [...secretBox.nonce, ...secretBox.cipherText, ...secretBox.mac.bytes];
  }

  /// Decrypts raw bytes using a symmetric key.
  Future<List<int>> decryptBytes(List<int> encryptedData, SecretKey key) async {
    final nonceLength = _encryptionAlgorithm.nonceLength;
    final macLength = _encryptionAlgorithm.macAlgorithm.macLength;

    if (encryptedData.length < nonceLength + macLength) {
      throw Exception('Invalid encrypted bytes format');
    }

    final nonce = encryptedData.sublist(0, nonceLength);
    final cipherText = encryptedData.sublist(nonceLength, encryptedData.length - macLength);
    final macBytes = encryptedData.sublist(encryptedData.length - macLength);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    return await _encryptionAlgorithm.decrypt(
      secretBox,
      secretKey: key,
    );
  }
}
