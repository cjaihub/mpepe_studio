import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova/auth/security/login_security.dart';
import 'package:oneova/auth/services/oneova_biometric_lock_service.dart';
import 'package:oneova/security/services/oneova_security_shield.dart';
import 'package:oneova/security/services/oneova_ai_encryption_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Oneova Feed-First & Security Architecture Test Suite', () {
    test('LoginSecurity allows guest routes for public reels & discovery', () {
      expect(LoginSecurity.isGuestRoute('/hub/home'), isTrue);
      expect(LoginSecurity.isGuestRoute('/biz_feed'), isTrue);
      expect(LoginSecurity.isGuestRoute('/hub/discover'), isTrue);
      expect(LoginSecurity.isGuestRoute('/profile/user_12345'), isTrue);
      expect(LoginSecurity.isGuestRoute('/profile/me'), isFalse);
    });

    test('OneovaSecurityShield detects phishing and malicious patterns', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final shield = container.read(oneovaSecurityShieldProvider);

      // Phishing URLs
      expect(shield.isThreat('https://0neova.com/login'), isTrue);
      expect(shield.isThreat('http://oneova-verify.xyz/auth?token=123'), isTrue);
      expect(shield.isThreat('http://192.168.1.100:8080/steal_auth'), isTrue);
      expect(shield.isThreat('javascript:alert(1)'), isTrue);
      expect(shield.isThreat('https://mpepe-claim.net/gift'), isTrue);

      // Safe official URLs
      expect(shield.isThreat('https://oneova.app/sound/track_98'), isFalse);
      expect(shield.isThreat('https://oneova.web.app/privacy.html'), isFalse);
      expect(shield.isThreat('https://youtube.com/watch?v=abcd'), isFalse);
      expect(shield.validateSafeUrl('https://oneova.app/reels/feed'), isTrue);
    });

    test('OneovaAiEncryptionVault encrypts and decrypts AI payloads faithfully', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final vault = container.read(oneovaAiEncryptionVaultProvider);
      const testUserId = 'test_user_789';
      const secretPrompt = 'Help me schedule my private reel for tomorrow at 8pm';

      final encrypted = await vault.encryptAiPayload(testUserId, secretPrompt);
      expect(encrypted, startsWith('oneova_enc_v1:'));
      expect(encrypted, isNot(contains(secretPrompt)));

      final decrypted = await vault.decryptAiPayload(testUserId, encrypted);
      expect(decrypted, equals(secretPrompt));
    });

    test('OvaAutonomousExecutor executes high-confidence actions autonomously', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final executor = container.read(ovaAutonomousExecutorProvider);
      bool actionRan = false;

      // Low confidence (< 0.80) is rejected
      final rejected = await executor.executeWithConfidence(
        actionType: 'schedule_post',
        summary: 'Low confidence test',
        confidenceScore: 0.65,
        parameters: {'time': 'tomorrow'},
        onExecute: () async {
          actionRan = true;
        },
      );
      expect(rejected, isFalse);
      expect(actionRan, isFalse);

      // High confidence (>= 0.80) executes
      final executed = await executor.executeWithConfidence(
        actionType: 'apply_look',
        summary: 'Apply Clean Pro Look',
        confidenceScore: 0.95,
        parameters: {'look': 'clean_pro'},
        onExecute: () async {
          actionRan = true;
        },
      );
      expect(executed, isTrue);
      expect(actionRan, isTrue);
      expect(executor.history.isNotEmpty, isTrue);
      expect(executor.history.first.summary, 'Apply Clean Pro Look');
    });
  });
}
