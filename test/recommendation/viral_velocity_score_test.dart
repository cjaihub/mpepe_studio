import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/recommendation/algorithm/oneova_neural_ranker.dart';
import 'package:oneova/backend/recommendation/algorithm/online_feature_store.dart';
import 'package:oneova/backend/recommendation/algorithm/viral_trending_engine.dart';
import 'package:oneova/backend/recommendation/algorithm/viral_velocity_score.dart';
import 'package:oneova/backend/social/models/content.dart';

void main() {
  const scorer = ViralVelocityScorer();

  group('ViralVelocityScorer', () {
    test('zero engagement on an old post scores ~0 (no invented signal)', () {
      final b = scorer.score(const ViralSignals(ageHours: 72));
      expect(b.engagementPoints, 0);
      expect(b.watchPoints, 0);
      expect(b.freshnessBonus, 0);
      expect(b.score, closeTo(0, 1e-9));
    });

    test('brand-new post with no engagement still gets the freshness boost', () {
      final b = scorer.score(const ViralSignals(ageHours: 0));
      expect(b.freshnessBonus, ViralVelocityScorer.freshnessMax);
      expect(b.score, closeTo(ViralVelocityScorer.freshnessMax, 1e-9));
      expect(b.reasons, contains('new post boost'));
    });

    test('freshness boost shrinks linearly and ends at the window', () {
      final half = scorer.score(const ViralSignals(ageHours: 3));
      final after = scorer.score(const ViralSignals(ageHours: 6));
      expect(half.freshnessBonus, closeTo(ViralVelocityScorer.freshnessMax / 2, 1e-9));
      expect(after.freshnessBonus, 0);
    });

    test('engagement points use the documented weights', () {
      final b = scorer.score(const ViralSignals(
        likes: 10, comments: 2, shares: 1, saves: 3, follows: 1, ageHours: 10,
      ));
      expect(b.engagementPoints, 10 * 1 + 2 * 3 + 1 * 5 + 3 * 4 + 1 * 8);
    });

    test('same engagement arriving faster scores higher (velocity)', () {
      const fast = ViralSignals(views: 200, likes: 50, comments: 10, ageHours: 2);
      const slow = ViralSignals(views: 200, likes: 50, comments: 10, ageHours: 20);
      expect(scorer.score(fast).velocityPerHour, greaterThan(scorer.score(slow).velocityPerHour));
      expect(scorer.score(fast).score, greaterThan(scorer.score(slow).score));
    });

    test('a share or follow is worth more than a like', () {
      const base = ViralSignals(views: 100, likes: 5, ageHours: 12);
      const withLike = ViralSignals(views: 100, likes: 6, ageHours: 12);
      const withShare = ViralSignals(views: 100, likes: 5, shares: 1, ageHours: 12);
      const withFollow = ViralSignals(views: 100, likes: 5, follows: 1, ageHours: 12);
      final s0 = scorer.score(base).score;
      final sLike = scorer.score(withLike).score;
      final sShare = scorer.score(withShare).score;
      final sFollow = scorer.score(withFollow).score;
      expect(sLike, greaterThan(s0));
      expect(sShare, greaterThan(sLike));
      expect(sFollow, greaterThan(sShare));
    });

    test('completions and watch time count, and watch time is capped', () {
      const dur = Duration(seconds: 20);
      final noWatch = scorer.score(const ViralSignals(views: 50, ageHours: 8, videoDuration: dur));
      final watched = scorer.score(const ViralSignals(
        views: 50, completions: 30, watchTimeMs: 50 * 20000, ageHours: 8, videoDuration: dur,
      ));
      expect(watched.watchPoints, 30 * 2 + 50.0);
      expect(watched.score, greaterThan(noWatch.score));

      final farmed = scorer.score(const ViralSignals(
        views: 1, watchTimeMs: 1000 * 20000, ageHours: 8, videoDuration: dur,
      ));
      expect(farmed.watchPoints, 3.0); // capped at 3 full plays per view
    });

    test('quality is smoothed: tiny samples are not "perfect" and stay in 0.5–2.0', () {
      final tiny = scorer.score(const ViralSignals(views: 2, likes: 2, ageHours: 10));
      expect(tiny.qualityMultiplier, lessThanOrEqualTo(2.0));
      final poor = scorer.score(const ViralSignals(views: 10000, likes: 1, ageHours: 10));
      expect(poor.qualityMultiplier, 0.5);
      expect(poor.reasons, contains('low engagement per view'));
      final none = scorer.score(const ViralSignals(ageHours: 10));
      expect(none.qualityMultiplier, closeTo(1.0, 1e-9));
    });

    test('time decay halves every half-life', () {
      final d0 = scorer.score(const ViralSignals(ageHours: 0)).timeDecay;
      final d1 = scorer.score(const ViralSignals(ageHours: ViralVelocityScorer.halfLifeHours)).timeDecay;
      final d2 = scorer.score(const ViralSignals(ageHours: ViralVelocityScorer.halfLifeHours * 2)).timeDecay;
      expect(d0, 1.0);
      expect(d1, closeTo(0.5, 1e-9));
      expect(d2, closeTo(0.25, 1e-9));
    });

    test('a fast-rising new post beats an older post with bigger totals', () {
      final now = DateTime(2026, 10, 18, 12);
      final rising = _content('rising', now.subtract(const Duration(hours: 3)),
          views: 400, likes: 120, comments: 30, shares: 15, saves: 20);
      final stale = _content('stale', now.subtract(const Duration(days: 6)),
          views: 20000, likes: 900, comments: 80, shares: 20, saves: 40);
      expect(scorer.scoreContent(rising, now: now), greaterThan(scorer.scoreContent(stale, now: now)));
    });

    test('fromContent reads only real counters (shares include reposts)', () {
      final now = DateTime(2026, 10, 18, 12);
      final c = _content('c', now.subtract(const Duration(hours: 5)),
          views: 10, likes: 4, comments: 1, shares: 2, reposts: 3, saves: 1,
          completions: 6, watchMs: 90000, follows: 2);
      final s = ViralSignals.fromContent(c, now: now);
      expect(s.ageHours, closeTo(5, 1e-9));
      expect(s.shares, 5);
      expect(s.completions, 6);
      expect(s.watchTimeMs, 90000);
      expect(s.follows, 2);
    });

    test('explanation lists the factors behind the score', () {
      final b = scorer.score(const ViralSignals(
        views: 100, likes: 40, shares: 3, follows: 2, ageHours: 2,
      ));
      expect(b.reasons.any((r) => r.contains('per hour')), isTrue);
      expect(b.reasons, contains('2 follows gained from this post'));
      expect(b.reasons, contains('shared 3 times'));
      expect(b.reasons, contains('new post boost'));
    });
  });

  test('For You ranker puts the viral post above an equal-but-stale one', () {
    final db = FakeFirebaseFirestore();
    final store = OnlineFeatureStore(db);
    final ranker = OneOvaNeuralRanker(store, ViralTrendingEngine(firestore: db));
    final now = DateTime.now();
    final viral = _content('viral', now.subtract(const Duration(hours: 2)),
        author: 'a', views: 300, likes: 150, comments: 40, shares: 25, saves: 30, follows: 6);
    final stale = _content('stale', now.subtract(const Duration(days: 10)),
        author: 'b', views: 300, likes: 20, comments: 2);
    final ranked = ranker.rankForYouFeed(userId: 'u', candidates: [stale, viral]);
    expect(ranked.first.id, 'viral');
  });
}

Content _content(
  String id,
  DateTime createdAt, {
  String author = 'author',
  int views = 0,
  int likes = 0,
  int comments = 0,
  int shares = 0,
  int reposts = 0,
  int saves = 0,
  int completions = 0,
  int watchMs = 0,
  int follows = 0,
}) {
  return Content(
    id: id,
    authorId: author,
    description: '',
    type: ContentType.short_video,
    mediaUrl: 'https://example.com/$id.mp4',
    mediaMetadata: MediaMetadata(duration: const Duration(seconds: 15)),
    hashtags: const [],
    mentions: const [],
    viewCount: views,
    likeCount: likes,
    commentCount: comments,
    shareCount: shares,
    repostCount: reposts,
    saveCount: saves,
    completionCount: completions,
    watchTimeMs: watchMs,
    followerConversions: follows,
    createdAt: createdAt,
  );
}
