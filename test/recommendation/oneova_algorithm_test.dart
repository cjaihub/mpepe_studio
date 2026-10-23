import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/social/models/content.dart';
import 'package:oneova/backend/recommendation/algorithm/oneova_algorithm_models.dart';
import 'package:oneova/backend/recommendation/algorithm/online_feature_store.dart';
import 'package:oneova/backend/recommendation/algorithm/chat_affinity_extractor.dart';
import 'package:oneova/backend/recommendation/algorithm/viral_trending_engine.dart';
import 'package:oneova/backend/recommendation/algorithm/oneova_neural_ranker.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

void main() {
  group('OneOva Neural Pulse & Flow Algorithm (ONPA-Flow) Tests', () {
    late FakeFirebaseFirestore fakeFirestore;
    late OnlineFeatureStore featureStore;
    late ChatAffinityExtractor chatExtractor;
    late ViralTrendingEngine trendingEngine;
    late OneOvaNeuralRanker ranker;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      featureStore = OnlineFeatureStore(fakeFirestore);
      chatExtractor = ChatAffinityExtractor(featureStore);
      trendingEngine = ViralTrendingEngine(firestore: fakeFirestore);
      ranker = OneOvaNeuralRanker(featureStore, trendingEngine);
    });

    test('OnlineFeatureStore: Fast skip (<1500ms) penalizes topic affinity', () {
      const userId = 'user_test_1';
      final telemetry = VideoWatchTelemetry(
        userId: userId,
        contentId: 'vid_skip_1',
        authorId: 'author_a',
        hashtags: ['gaming', 'fortnite'],
        dwellTimeMs: 800, // < 1500ms = fast skip
        videoDurationMs: 15000,
        completionRate: 0.05,
        loopCount: 0,
        isFastSkip: true,
        timestamp: DateTime.now(),
      );

      featureStore.recordWatchTelemetry(telemetry);
      final profile = featureStore.getProfile(userId);

      // Score should have received negative penalty
      expect(profile.topicAffinities['gaming'], isNotNull);
      expect(profile.topicAffinities['gaming']! < 10.0, isTrue);
    });

    test('OnlineFeatureStore: Deep watch and looping surges topic affinity', () {
      const userId = 'user_test_2';
      final telemetry = VideoWatchTelemetry(
        userId: userId,
        contentId: 'vid_loop_1',
        authorId: 'author_viral',
        hashtags: ['music', 'synthwave'],
        dwellTimeMs: 45000,
        videoDurationMs: 15000,
        completionRate: 3.0,
        loopCount: 3, // looped 3 times!
        isFastSkip: false,
        liked: true,
        shared: true,
        timestamp: DateTime.now(),
      );

      featureStore.recordWatchTelemetry(telemetry);
      final profile = featureStore.getProfile(userId);

      expect(profile.topicAffinities['music'], isNotNull);
      expect(profile.topicAffinities['music']! > 15.0, isTrue);
      expect(profile.authorAffinities['author_viral']! > 10.0, isTrue);
    });

    test('ChatAffinityExtractor: Extracts conversational tokens and primes feature store', () {
      const senderId = 'user_alice';
      const recipientId = 'user_bob';
      const text = 'Check out this sick beat! We need more #afrobeats and electronic music in OneOva';

      chatExtractor.processChatMessage(
        senderId: senderId,
        recipientId: recipientId,
        rawText: text,
      );

      final aliceProfile = featureStore.getProfile(senderId);
      final bobProfile = featureStore.getProfile(recipientId);

      expect(aliceProfile.topicAffinities.containsKey('afrobeats'), isTrue);
      expect(aliceProfile.topicAffinities.containsKey('electronic'), isTrue);
      expect(bobProfile.topicAffinities.containsKey('afrobeats'), isTrue);
    });

    test('ChatAffinityExtractor: Detects shared video links in chat', () {
      const senderId = 'user_charlie';
      chatExtractor.processChatMessage(
        senderId: senderId,
        recipientId: 'user_david',
        rawText: 'Watch this https://oneova.app/v/viral_dance_99 right now!',
      );

      final charlieProfile = featureStore.getProfile(senderId);
      expect(charlieProfile.sharedInChatVideoIds.contains('viral_dance_99'), isTrue);
    });

    test('ViralTrendingEngine: Calculates high velocity for fresh high-engagement videos', () {
      final viralContent = Content(
        id: 'c_viral_1',
        authorId: 'creator_star',
        description: 'Epic guitar solo #music',
        mediaUrl: 'https://example.com/v1.mp4',
        mediaMetadata: MediaMetadata(duration: const Duration(seconds: 15)),
        hashtags: ['music'],
        viewCount: 1000,
        likeCount: 350, // 35% like ratio
        shareCount: 150, // 15% share ratio
        commentCount: 80,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)), // fresh (1 hr ago)
      );

      final velocity = trendingEngine.calculateVelocityScore(viralContent);
      expect(velocity > 50.0, isTrue);

      final tier = trendingEngine.evaluateViralTier(viralContent);
      expect(tier != ViralTier.tier0Seed, isTrue);
    });

    test('ViralTrendingEngine: UCB Bandit exploration awards bonus to fresh cold-start videos', () {
      final coldStartContent = Content(
        id: 'c_cold_1',
        authorId: 'creator_newbie',
        description: 'My very first video! #art',
        mediaUrl: 'https://example.com/v_art.mp4',
        mediaMetadata: MediaMetadata(duration: const Duration(seconds: 10)),
        hashtags: ['art'],
        viewCount: 5, // very few views!
        createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
      );

      final establishedContent = Content(
        id: 'c_established_1',
        authorId: 'creator_mega',
        description: 'Another video #art',
        mediaUrl: 'https://example.com/v_mega.mp4',
        mediaMetadata: MediaMetadata(duration: const Duration(seconds: 10)),
        hashtags: ['art'],
        viewCount: 250000,
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
      );

      final coldBonus = trendingEngine.calculateExplorationBonus(coldStartContent, 1000000);
      final estBonus = trendingEngine.calculateExplorationBonus(establishedContent, 1000000);

      // Cold start MUST have significantly higher exploration bonus
      expect(coldBonus > estBonus, isTrue);
    });

    test('OneOvaNeuralRanker: Ranks videos according to in-session topic and chat affinity', () {
      const userId = 'user_ranker_test';

      // Simulate user having high in-session affinity for 'tech' and chat sharing 'vid_ai'
      chatExtractor.processChatMessage(
        senderId: userId,
        recipientId: 'friend_1',
        rawText: 'Look at this amazing #tech breakthrough! https://oneova.app/v/vid_ai',
      );

      final videoTech = Content(
        id: 'vid_ai',
        authorId: 'tech_guru',
        description: 'New AI model #tech',
        mediaUrl: 'https://example.com/tech.mp4',
        mediaMetadata: MediaMetadata(),
        hashtags: ['tech'],
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      );

      final videoUnrelated = Content(
        id: 'vid_gardening',
        authorId: 'gardener_bob',
        description: 'How to water plants #gardening',
        mediaUrl: 'https://example.com/garden.mp4',
        mediaMetadata: MediaMetadata(),
        hashtags: ['gardening'],
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      );

      final ranked = ranker.rankForYouFeed(
        userId: userId,
        candidates: [videoUnrelated, videoTech],
      );

      expect(ranked.first.id, equals('vid_ai'));
    });
  });
}
