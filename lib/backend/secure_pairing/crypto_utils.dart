import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart';

class CryptoUtils {
  /// Derives a 32-byte AES key from a 6-digit PIN and a salt using SHA-256.
  static enc.Key deriveKeyFromPin(String pin, String salt) {
    // In a real production environment, you might use PBKDF2 or Argon2.
    // For this local pairing, a SHA-256 hash of the PIN + salt is sufficient.
    final bytes = utf8.encode(pin + salt);
    final digest = sha256.convert(bytes);
    return enc.Key(Uint8List.fromList(digest.bytes));
  }

  /// Encrypts a payload string using AES-GCM (Authenticated Encryption).
  static String encryptPayload(String payload, enc.Key key) {
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encrypt(payload, iv: iv);
    
    // Combine IV and Ciphertext, then base64 encode
    final combined = iv.bytes + encrypted.bytes;
    return base64Encode(combined);
  }

  /// Decrypts a payload string using AES-GCM.
  static String? decryptPayload(String encryptedBase64, enc.Key key) {
    try {
      final combined = base64Decode(encryptedBase64);
      if (combined.length <= 16) return null; // Invalid length

      final ivBytes = combined.sublist(0, 16);
      final cipherBytes = combined.sublist(16);

      final iv = enc.IV(Uint8List.fromList(ivBytes));
      final encrypted = enc.Encrypted(Uint8List.fromList(cipherBytes));
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));

      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      // Decryption failed (wrong PIN or tampered data)
      return null;
    }
  }
}
