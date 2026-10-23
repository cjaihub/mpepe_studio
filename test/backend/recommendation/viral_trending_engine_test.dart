import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:oneova/backend/recommendation/algorithm/geo_radius_distribution_engine.dart';
import 'package:oneova/backend/recommendation/algorithm/viral_trending_engine.dart';
import 'package:oneova/backend/social/models/content.dart';

void main() {
  group('ViralTrendingEngine Tests', () {
    late FakeFirebaseFirestore fakeFirestore;
    late GeoRadiusDistributionEngine geoEngine;
    late ViralTrendingEngine engine;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      geoEngine = GeoRadiusDistributionEngine();
      engine = ViralTrendingEngine(
        firestore: fakeFirestore,
        geoEngine: geoEngine,
      );
    });

    test('calculateVelocityScore incorporates geo multiplier and watch time', () {
      final content = Content(
        id: 'test_video_1',
        authorId: 'creator_1',
        description: 'New hit song release #music',
        mediaUrl: 'https://cdn.example.com/video1.mp4',
        mediaMetadata: MediaMetadata(duration: const Duration(seconds: 30)),
        latitude: 37.7749,
        longitude: -122.4194,
        viewCount: 100,
        likeCount: 20,
        commentCount: 5,
        shareCount: 10,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      final baselineVelocity = engine.calculateVelocityScore(content);
      expect(baselineVelocity, greaterThan(0.0));

      // With Hyperlocal coordinates (< 10 km away): 1.5x boost
      final boostedVelocity = engine.calculateVelocityScore(
        content,
        userLat: 37.7790,
        userLng: -122.4100,
        watchTimeSeconds: 45.0, // Over-completed (looped)
        loopCount: 2,
        chatShareCount: 5,
      );

      expect(boostedVelocity, greaterThan(baselineVelocity));
    });

    test('calculateViralMultiplier scales with loops, chat shares, and conversions', () {
      final content = Content(
        id: 'v1',
        authorId: 'a1',
        description: 'viral test',
        mediaUrl: '',
        mediaMetadata: MediaMetadata(),
        createdAt: DateTime.now(),
      );

      final standardMultiplier = engine.calculateViralMultiplier(content);
      expect(standardMultiplier, 1.0);

      final viralMultiplier = engine.calculateViralMultiplier(
        content,
        geoMultiplier: 1.5,
        loopCount: 3,
        chatShareCount: 5,
        isFollowConversion: true,
        completionRatio: 1.5,
      );

      expect(viralMultiplier, greaterThan(2.0));
      expect(viralMultiplier, lessThanOrEqualTo(3.5));
    });

    test('atomicLikeGuard performs atomic increment and prevents duplicate likes', () async {
      await fakeFirestore.collection('content').doc('video_123').set({
        'authorId': 'creator_abc',
        'description': 'Amazing dance move',
        'mediaUrl': 'https://example.com/video.mp4',
        'likeCount': 0,
        'viewCount': 10,
        'commentCount': 0,
        'shareCount': 0,
        'createdAt': DateTime.now(),
      });

      await fakeFirestore.collection('users').doc('creator_abc').set({
        'username': 'creator_abc',
        'likeCount': 0,
      });

      // 1. First like succeeds
      final result1 = await engine.atomicLikeGuard(
        userId: 'viewer_xyz',
        contentId: 'video_123',
        authorId: 'creator_abc',
      );

      expect(result1.success, isTrue);
      expect(result1.alreadyLiked, isFalse);
      expect(result1.newLikeCount, 1);
      expect(result1.viralMultiplier, greaterThanOrEqualTo(1.0));

      final contentDoc = await fakeFirestore.collection('content').doc('video_123').get();
      expect(contentDoc.data()?['likeCount'], 1);

      // 2. Second like by same user is idempotent
      final result2 = await engine.atomicLikeGuard(
        userId: 'viewer_xyz',
        contentId: 'video_123',
        authorId: 'creator_abc',
      );

      expect(result2.success, isTrue);
      expect(result2.alreadyLiked, isTrue);
    });

    test('atomicFollowGuard applies viral conversion boost when originated from video', () async {
      await fakeFirestore.collection('users').doc('creator_star').set({
        'username': 'creator_star',
        'followersCount': 10,
      });
      await fakeFirestore.collection('users').doc('fan_1').set({
        'username': 'fan_1',
        'followingCount': 5,
      });
      await fakeFirestore.collection('content').doc('viral_card_99').set({
        'authorId': 'creator_star',
        'description': 'Masterclass reel',
        'mediaUrl': 'https://video.mp4',
        'viewCount': 500,
        'likeCount': 50,
        'commentCount': 10,
        'shareCount': 20,
        'createdAt': DateTime.now(),
      });

      final followResult = await engine.atomicFollowGuard(
        currentUserId: 'fan_1',
        targetUserId: 'creator_star',
        originatingContentId: 'viral_card_99',
      );

      expect(followResult.success, isTrue);
      expect(followResult.alreadyFollowing, isFalse);
      expect(followResult.conversionBonusApplied, isTrue);
      expect(followResult.viralMultiplierBoost, 1.35);

      final creatorDoc = await fakeFirestore.collection('users').doc('creator_star').get();
      expect(creatorDoc.data()?['followersCount'], 11);

      final videoDoc = await fakeFirestore.collection('content').doc('viral_card_99').get();
      expect(videoDoc.data()?['followerConversions'], 1);
    });
  });
}
