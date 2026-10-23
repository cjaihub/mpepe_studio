import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/moderation/services/content_safety_moderation_engine.dart';

void main() {
  group('Security Penetration & Content Safety Tests', () {
    late ContentSafetyModerationEngine safetyEngine;

    setUp(() {
      safetyEngine = ContentSafetyModerationEngine();
    });

    test('Penetration Test: Explicit sexual terms on public submissions trigger instant Burn Notice & Account Suspension', () async {
      final explicitPrompts = [
        'Watch hot free porn video here',
        'Check out my private nude leaks #xxx',
        'Direct sexual content and nudity exposed',
        'Explicit pornography clip for public viewing',
      ];

      for (final text in explicitPrompts) {
        final result = await safetyEngine.scanContent(
          text: text,
          isPublic: true,
          authorId: 'attacker_uid_1',
          contentId: 'content_exploit_1',
        );

        expect(result.isAllowed, isFalse, reason: 'Explicit content must not be allowed on public surfaces');
        expect(result.isBurnNoticeTriggered, isTrue, reason: 'Burn notice must be triggered immediately');
        expect(result.shouldSuspendAccount, isTrue, reason: 'Violating account must be suspended');
        expect(result.violationReason, contains('forbidden'));
      }
    });

    test('Security Test: Safe creative reels pass without flags', () async {
      final cleanPrompts = [
        'Behind the scenes in the Oneova sound studio! #music #producer',
        'New camera angle tutorial for mobile filmmakers #creator #oneova',
        'Epic drone shots of Mount Kilimanjaro at sunrise',
      ];

      for (final text in cleanPrompts) {
        final result = await safetyEngine.scanContent(
          text: text,
          tags: ['oneova', 'creator', 'cinema'],
          isPublic: true,
          authorId: 'creator_uid_1',
        );

        expect(result.isAllowed, isTrue);
        expect(result.isBurnNoticeTriggered, isFalse);
        expect(result.shouldSuspendAccount, isFalse);
      }
    });

    test('Search Injection Test: Adult / pornographic search strings are blocked and sanitized', () {
      final maliciousQueries = [
        'free porn videos',
        'xxx adult content',
        'naked leaked models',
        'hentai sex videos',
      ];

      for (final q in maliciousQueries) {
        final check = safetyEngine.filterSearchQuery(q);
        expect(check.isAllowed, isFalse, reason: 'Adult query "$q" should be blocked');
        expect(check.blockedReason, isNotNull);
      }

      final legitimateQueries = [
        'Nairobi food festival',
        'Acoustic guitar chords',
        'How to make viral reels',
        'Oneova AI assistant tips',
      ];

      for (final q in legitimateQueries) {
        final check = safetyEngine.filterSearchQuery(q);
        expect(check.isAllowed, isTrue, reason: 'Legitimate query "$q" should be allowed');
      }
    });

    test('Feed Sanitization Test: Burned items or explicit tags are excluded from public candidate pool', () {
      final safeItem = safetyEngine.isCandidateSafe(
        description: 'Vibrant sunset dance in Kampala',
        hashtags: ['dance', 'vibes', 'oneova'],
        status: 'published',
      );
      expect(safeItem, isTrue);

      final burnedItem = safetyEngine.isCandidateSafe(
        description: 'Previously burned content',
        hashtags: ['viral'],
        status: 'burned_notice_takedown',
      );
      expect(burnedItem, isFalse);

      final explicitTagItem = safetyEngine.isCandidateSafe(
        description: 'Normal looking video title',
        hashtags: ['dance', 'nude', 'fun'],
        status: 'published',
      );
      expect(explicitTagItem, isFalse);
    });

    test('Privacy Isolation Test: Intimate expressions confined to private inboxes do not trigger public Burn Notice', () async {
      final privateResult = await safetyEngine.scanContent(
        text: 'Private intimate conversation in 1-on-1 inbox',
        isPublic: false,
        authorId: 'user_private_uid',
      );

      // Private messaging allowed without burning or suspending
      expect(privateResult.isBurnNoticeTriggered, isFalse);
      expect(privateResult.shouldSuspendAccount, isFalse);
    });
  });
}
