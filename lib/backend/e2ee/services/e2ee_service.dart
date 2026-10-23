import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/crypto_models.dart';
import 'dart:convert';
// import 'package:cryptography/cryptography.dart'; // Abstracted for architectural diagram

final e2eeServiceProvider = Provider<E2EEService>((ref) {
  return E2EEService();
});

class E2EEService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;

  /// Registers a new device session and uploads the public key to Firestore.
  /// The private key NEVER leaves the secure enclave of the device.
  Future<void> registerDevice(String deviceId, String deviceName, String publicKey) async {
    final uid = _userId;
    if (uid == null) return;

    final session = DeviceSession(
      deviceId: deviceId,
      userId: uid,
      deviceName: deviceName,
      publicKey: publicKey,
      status: DeviceStatus.active,
      lastActive: DateTime.now(),
    );

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('devices')
        .doc(deviceId)
        .set(session.toMap());
  }

  /// Revokes a device. Its public key will no longer be used by peers to encrypt 
  /// future messages, breaking forward secrecy for that compromised device.
  Future<void> revokeDevice(String deviceId) async {
    final uid = _userId;
    if (uid == null) return;

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('devices')
        .doc(deviceId)
        .update({'status': DeviceStatus.revoked.name});
  }

  /// Explicit Boundary: E2EE Encrypt
  /// This takes plaintext on the client device and returns a purely opaque EncryptedPayload.
  /// Server/AI models cannot read this.
  Future<EncryptedPayload> encryptForPeer(String plaintext, String peerPublicKey, String myDeviceId) async {
    // In production, this uses an implementation of the Signal Protocol (Double Ratchet)
    // or AES-GCM with ECDH key exchange.
    // 
    // Example conceptual flow:
    // final sharedSecret = await ECDH.compute(myPrivateKey, peerPublicKey);
    // final aesGcm = AesGcm.with256bits();
    // final secretBox = await aesGcm.encrypt(
    //   utf8.encode(plaintext),
    //   secretKey: sharedSecret,
    // );
    
    // Simulating the opaque result:
    final ciphertext = base64Encode(utf8.encode(plaintext)); // Dummy encryption
    final iv = base64Encode(List.generate(12, (i) => i)); 
    final mac = base64Encode(List.generate(16, (i) => i));

    return EncryptedPayload(
      ciphertext: ciphertext,
      iv: iv,
      mac: mac,
      senderDeviceId: myDeviceId,
    );
  }

  /// Explicit Boundary: E2EE Decrypt
  /// Takes an opaque payload and uses the local secure enclave private key to decrypt.
  Future<String> decryptFromPeer(EncryptedPayload payload, String myPrivateKey) async {
    // Uses local private key + sender's public key (retrieved via senderDeviceId)
    // to decrypt the message locally.
    
    // Simulating dummy decryption
    return utf8.decode(base64Decode(payload.ciphertext));
  }
}
