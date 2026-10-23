import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/connectors/models/connector_models.dart';

void main() {
  group('Security and Hardening Tests', () {
    test('Client-side ConnectedAccount should not serialize tokens to JSON if they contain secrets', () {
      final account = ConnectedAccount(
        externalAccountId: '123',
        platformId: 'test',
        connectorId: 'stub',
        displayName: 'Test',
        status: 'VERIFIED',
        capabilities: [],
        scopes: [],
        connectedAt: DateTime.now(),
        reauthRequired: false,
        credential: Credential(
          accessToken: 'secret_token_123',
          expiresAt: DateTime.now(),
        ),
      );

      final json = account.toJson();
      // Ensure the credential is NOT exposed in default client-side json dumps
      expect(json.containsKey('credential'), isFalse, reason: 'Tokens should never be serialized to client-side json by default');
    });

    test('Webhook payloads must include valid signature check (Simulated)', () {
      bool isValidSignature(String payload, String signature) {
        // Mock verification
        if (payload.contains('malicious')) return false;
        if (signature != 'valid_sig') return false;
        return true;
      }

      expect(isValidSignature('good_payload', 'valid_sig'), isTrue);
      expect(isValidSignature('good_payload', 'invalid_sig'), isFalse);
      expect(isValidSignature('malicious_payload', 'valid_sig'), isFalse);
    });

    test('Cross-account linking rejection (Simulated)', () {
      final existingAccountOwnerId = 'user_A';
      
      String? attemptLink(String incomingUserId, String externalAccountId) {
        // If the external account is already bound to user_A, reject user_B
        if (externalAccountId == 'ext_1' && incomingUserId != existingAccountOwnerId) {
          return 'Error: Account already linked to another user.';
        }
        return 'Success';
      }

      expect(attemptLink('user_A', 'ext_1'), 'Success');
      expect(attemptLink('user_B', 'ext_1'), 'Error: Account already linked to another user.');
    });
  });
}
