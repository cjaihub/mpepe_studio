import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Validates incoming webhook payloads using an HMAC signature.
/// This prevents Webhook Attacks where malicious actors attempt to spoof 
/// media transcoding status or monetization events.
class WebhookVerifier {
  final String _sharedSecret;

  WebhookVerifier(this._sharedSecret);

  /// Validates the signature of the raw payload against the provided header.
  bool verifySignature({
    required String rawPayload,
    required String signatureHeader, // e.g., 'sha256=....'
  }) {
    if (_sharedSecret.isEmpty || signatureHeader.isEmpty) return false;

    try {
      final parts = signatureHeader.split('=');
      if (parts.length != 2 || parts[0] != 'sha256') return false;
      
      final providedSignature = parts[1];
      
      final keyBytes = utf8.encode(_sharedSecret);
      final messageBytes = utf8.encode(rawPayload);
      
      final hmac = Hmac(sha256, keyBytes);
      final digest = hmac.convert(messageBytes);
      final expectedSignature = digest.toString();
      
      // Use constant-time comparison in a real backend context.
      return providedSignature == expectedSignature;
    } catch (e) {
      return false;
    }
  }
}
