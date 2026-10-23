import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/routing/oneova_share_engine.dart';
import 'package:oneova/backend/social/models/content.dart';

void main() {
  group('OneovaShareEngine Tests', () {
    late OneovaShareEngine engine;

    setUp(() {
      engine = OneovaShareEngine();
    });

    test('generateWebShareUrl produces canonical https://oneova.app/p/{contentId}', () {
      expect(
        engine.generateWebShareUrl('dance_clip_42'),
        'https://oneova.app/p/dance_clip_42',
      );
      expect(
        engine.generateWebShareUrl('dance_clip_42', referrerId: 'user_99'),
        'https://oneova.app/p/dance_clip_42?ref=user_99',
      );
    });

    test('generateDeepLinkUri produces native oneova://content/{contentId}', () {
      expect(
        engine.generateDeepLinkUri('dance_clip_42'),
        'oneova://content/dance_clip_42',
      );
    });

    test('generateCryptographicShareUrl generates valid HMAC-SHA256 signature and verifies it', () {
      final signedUrl = engine.generateCryptographicShareUrl(
        'secure_video_88',
        ttl: const Duration(hours: 24),
        referrerId: 'ref_partner',
      );

      final uri = Uri.parse(signedUrl);
      expect(uri.host, 'oneova.app');
      expect(uri.path, '/p/secure_video_88');
      expect(uri.queryParameters.containsKey('sig'), isTrue);
      expect(uri.queryParameters.containsKey('exp'), isTrue);

      // Verify the signed URL
      final isValid = engine.verifySignature(uri);
      expect(isValid, isTrue);

      // Tampering with contentId should invalidate signature
      final tamperedUri = uri.replace(path: '/p/tampered_video');
      expect(engine.verifySignature(tamperedUri), isFalse);
    });

    test('generateOpenGraphMetadata and HTML output includes complete tags', () {
      final content = Content(
        id: 'promo_video',
        authorId: 'director_sam',
        description: 'Exclusive first look at Oneova studio workflow',
        mediaUrl: 'https://cdn.oneova.app/promo.mp4',
        mediaMetadata: MediaMetadata(
          thumbnailUrl: 'https://cdn.oneova.app/thumb.jpg',
          duration: const Duration(seconds: 45),
        ),
        createdAt: DateTime.now(),
      );

      final og = engine.fromContent(content, authorName: 'Sam Director');
      expect(og.contentId, 'promo_video');
      expect(og.playUrl, 'https://cdn.oneova.app/promo.mp4');
      expect(og.thumbnailUrl, 'https://cdn.oneova.app/thumb.jpg');

      final html = engine.generateOpenGraphHtml(og);
      expect(html, contains('<meta property="og:site_name" content="Oneova" />'));
      expect(html, contains('<meta property="og:video" content="https://cdn.oneova.app/promo.mp4" />'));
      expect(html, contains('<meta name="twitter:card" content="player" />'));
      expect(html, contains('<meta name="al:ios:url" content="oneova://content/promo_video" />'));
    });

    test('resolveShareLink safely parses all URI formats to /hub/home?v={contentId}', () {
      // 1. Standard web link
      expect(
        engine.resolveShareLink(Uri.parse('https://oneova.app/p/video_alpha')),
        '/hub/home?v=video_alpha',
      );

      // 2. Custom native deep link
      expect(
        engine.resolveShareLink(Uri.parse('oneova://content/video_alpha')),
        '/hub/home?v=video_alpha',
      );

      // 3. Alternative deep link scheme
      expect(
        engine.resolveShareLink(Uri.parse('oneova://p/video_alpha')),
        '/hub/home?v=video_alpha',
      );

      // 4. Query param based web link
      expect(
        engine.resolveShareLink(Uri.parse('https://oneova.app/hub/home?v=video_alpha')),
        '/hub/home?v=video_alpha',
      );

      // 5. Signed link with extra query params
      expect(
        engine.resolveShareLink(Uri.parse('https://oneova.app/p/video_alpha?sig=123&exp=456&ref=abc')),
        '/hub/home?v=video_alpha',
      );

      // 6. Invalid URI returns null
      expect(engine.resolveShareLink(Uri.parse('https://google.com/search')), isNull);
    });

    test('resolveShareLinkDetails parses rich resolution object', () {
      final signedUrl = engine.generateCryptographicShareUrl('vid_007', referrerId: 'affiliate_1');
      final res = engine.resolveShareLinkDetails(Uri.parse(signedUrl));

      expect(res.isValid, isTrue);
      expect(res.contentId, 'vid_007');
      expect(res.route, '/hub/home?v=vid_007');
      expect(res.isSignatureVerified, isTrue);
      expect(res.referrerId, 'affiliate_1');
    });
  });
}
