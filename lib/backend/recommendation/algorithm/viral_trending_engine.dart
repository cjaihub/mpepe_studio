import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../social/models/content.dart';
import 'geo_radius_distribution_engine.dart';
import 'oneova_algorithm_models.dart';

final viralTrendingEngineProvider = Provider<ViralTrendingEngine>((ref) {
  return ViralTrendingEngine(
    geoEngine: ref.read(geoRadiusDistributionEngineProvider),
  );
});

/// Result of an atomic like transaction with viral acceleration evaluation
class ViralLikeResult {
  final bool success;
  final bool alreadyLiked;
  final int newLikeCount;
  final double viralMultiplier;
  final double updatedVelocity;

  const ViralLikeResult({
    required this.success,
    this.alreadyLiked = false,
    this.newLikeCount = 0,
    this.viralMultiplier = 1.0,
    this.updatedVelocity = 0.0,
  });
}

/// Result of an atomic unlike transaction
class ViralUnlikeResult {
  final bool success;
  final bool alreadyUnliked;
  final int newLikeCount;

  const ViralUnlikeResult({
    required this.success,
    this.alreadyUnliked = false,
    this.newLikeCount = 0,
  });
}

/// Result of an atomic follow transaction with creator conversion viral boost
class ViralFollowResult {
  final bool success;
  final bool alreadyFollowing;
  final bool conversionBonusApplied;
  final double viralMultiplierBoost;

  const ViralFollowResult({
    required this.success,
    this.alreadyFollowing = false,
    this.conversionBonusApplied = false,
    this.viralMultiplierBoost = 1.0,
  });
}

/// OneOva "Easy-To-Trend" Viral Acceleration & Distribution Engine
///
/// Research-backed algorithmic incubator that provides fair, democratized virality:
/// 1. Guaranteed 300-view Tier 0 seed sandbox for every creator.
/// 2. Smart Geo-Radius relevance multipliers (1.5x hyperlocal, 1.3x city, 1.1x regional).
/// 3. Enhanced Engagement Velocity balancing completion, looping, and OneOva DM chat shares.
/// 4. Atomic transaction guards for Likes & Follows with instant viral multipliers.
/// 5. LinUCB/Thompson-style Exploration Bandit for cold-start discovery.
/// 6. Exponential Creator Anti-Monopoly Dampener.
class ViralTrendingEngine {
  final FirebaseFirestore _firestore;
  final GeoRadiusDistributionEngine _geoEngine;

  ViralTrendingEngine({
    FirebaseFirestore? firestore,
    GeoRadiusDistributionEngine? geoEngine,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _geoEngine = geoEngine ?? GeoRadiusDistributionEngine();

  // Exploration coefficient for Upper Confidence Bound (UCB)
  static const double _explorationCoeff = 1.65;

  // Escalation Velocity Thresholds
  static const double _tier1Threshold = 60.0;
  static const double _tier2Threshold = 75.0;
  static const double _tier3Threshold = 88.0;

  // Enhanced engagement weight constants
  static const double _weightCompletion = 45.0;
  static const double _weightLoops = 35.0;
  static const double _weightChatShares = 35.0; // High value for DM virality
  static const double _weightExternalShares = 20.0;
  static const double _weightLikes = 15.0;
  static const double _weightComments = 10.0;

  /// Calculates the real-time Viral Velocity Score for a video.
  ///
  /// Incorporates:
  /// - Geo-relevance multiplier from viewer coordinates (or direct parameter)
  /// - Enhanced watch time completion rates
  /// - Loop replay ratios
  /// - OneOva Direct Chat shares vs external shares
  /// - Time-decay dynamics
  double calculateVelocityScore(
    Content content, {
    double? userLat,
    double? userLng,
    double? geoMultiplier,
    double? watchTimeSeconds,
    int? loopCount,
    int? chatShareCount,
  }) {
    final views = math.max(1, content.viewCount);
    final likes = content.likeCount;
    final comments = content.commentCount;
    final totalShares = content.shareCount;

    // Derived baseline engagement ratios
    final likeRatio = (likes / views).clamp(0.0, 1.0);
    final commentRatio = (comments / views).clamp(0.0, 0.5);
    final totalShareRatio = (totalShares / views).clamp(0.0, 0.5);

    // 1. Enhanced Completion Rate (actual watch time vs estimated duration)
    double completionRate;
    final durationSecs = content.mediaMetadata.duration?.inSeconds;
    if (watchTimeSeconds != null && durationSecs != null && durationSecs > 0) {
      completionRate = (watchTimeSeconds / durationSecs).clamp(0.0, 3.0);
    } else {
      // Estimated completion rate derived from high-affinity interaction signals
      completionRate = (0.35 + (likeRatio * 0.40) + (totalShareRatio * 0.80)).clamp(0.1, 1.0);
    }

    // 2. Loop Rate (actual replay loops vs estimated)
    double loopRate;
    if (loopCount != null && loopCount > 0) {
      loopRate = loopCount.toDouble().clamp(0.0, 5.0);
    } else {
      loopRate = (totalShareRatio * 1.5 + (comments / views) * 0.5).clamp(0.0, 2.0);
    }

    // 3. OneOva Chat Share Ratio (super-signal for social virality)
    final resolvedChatShares = chatShareCount ?? (totalShares * 0.45).round();
    final chatShareRatio = (resolvedChatShares / views).clamp(0.0, 0.5);
    final externalShareRatio = math.max(0.0, totalShareRatio - chatShareRatio);

    // 4. Age decay factor: logarithmic dampening allows fresh content to surge
    final ageHours = math.max(0.1, DateTime.now().difference(content.createdAt).inMinutes / 60.0);
    final ageDecay = math.log(ageHours + 2.0); // e.g. 1 hr -> ln(3) = 1.09, 24 hr -> ln(26) = 3.25

    // 5. Geo-Relevance Multiplier
    final resolvedGeoMultiplier = geoMultiplier ??
        _geoEngine.calculateGeoRelevanceScore(content, userLat, userLng);

    // 6. Enhanced Engagement Quality Numerator
    final engagementQuality = (completionRate * _weightCompletion) +
        (loopRate * _weightLoops) +
        (chatShareRatio * 100.0 * (_weightChatShares / 100.0)) +
        (externalShareRatio * 100.0 * (_weightExternalShares / 100.0)) +
        (likeRatio * 100.0 * (_weightLikes / 100.0)) +
        (commentRatio * 100.0 * (_weightComments / 100.0));

    final baseVelocity = (engagementQuality / ageDecay) * 2.5;
    final boostedVelocity = baseVelocity * resolvedGeoMultiplier;

    return boostedVelocity.clamp(0.0, 100.0);
  }

  /// Calculates a compound viral multiplier for real-time acceleration
  double calculateViralMultiplier(
    Content content, {
    double geoMultiplier = 1.0,
    int loopCount = 0,
    int chatShareCount = 0,
    bool isFollowConversion = false,
    double completionRatio = 0.5,
  }) {
    final loopBoost = (loopCount >= 2) ? 1.4 : (loopCount >= 1 ? 1.2 : 1.0);
    final chatBoost = (chatShareCount > 0) ? 1.3 : 1.0;
    final followBoost = isFollowConversion ? 1.35 : 1.0;
    final completionBoost = (completionRatio >= 1.0) ? 1.25 : 1.0;

    final multiplier = geoMultiplier * loopBoost * chatBoost * followBoost * completionBoost;
    return multiplier.clamp(1.0, 3.5);
  }

  /// Evaluates which viral tier the video belongs to and whether it qualifies for promotion
  ViralTier evaluateViralTier(Content content) {
    final views = content.viewCount;
    final velocity = calculateVelocityScore(content);

    if (views < 350) {
      // Tier 0: Incubator Sandbox
      return (velocity >= _tier1Threshold) ? ViralTier.tier1Emerging : ViralTier.tier0Seed;
    } else if (views < 5000) {
      // Tier 1: Emerging
      return (velocity >= _tier2Threshold) ? ViralTier.tier2Trending : ViralTier.tier1Emerging;
    } else if (views < 50000) {
      // Tier 2: Trending
      return (velocity >= _tier3Threshold) ? ViralTier.tier3Megapool : ViralTier.tier2Trending;
    } else {
      // Tier 3: Global Megapool
      return ViralTier.tier3Megapool;
    }
  }

  /// Upper Confidence Bound (UCB) exploration bonus for cold start
  /// Gives fresh, under-viewed videos a mathematical boost to ensure every video is tested
  double calculateExplorationBonus(Content content, int totalGlobalViewsEstimate) {
    final views = math.max(1, content.viewCount);
    final nTotal = math.max(1000, totalGlobalViewsEstimate);

    // UCB-1 formula: c * sqrt(ln(N) / n)
    final exploration = _explorationCoeff * math.sqrt(math.log(nTotal) / views);

    // Freshness booster for videos under 24 hours old
    final ageHours = DateTime.now().difference(content.createdAt).inHours;
    final freshnessMultiplier = (ageHours < 6)
        ? 2.5
        : (ageHours < 24)
            ? 1.5
            : 1.0;

    return (exploration * freshnessMultiplier).clamp(0.0, 25.0);
  }

  /// Calculates author fatigue dampener to prevent feed monopoly
  /// If an author appears multiple times in recent history, penalize subsequent cards
  double calculateAuthorFatigueDampener(String authorId, List<String> recentAuthors) {
    int occurrences = 0;
    for (final id in recentAuthors.take(10)) {
      if (id == authorId) occurrences++;
    }

    if (occurrences == 0) return 1.0;
    // Exponential dampening: 1 occurrence -> 0.50, 2 occurrences -> 0.25, 3 -> 0.12
    return math.exp(-0.7 * occurrences);
  }

  /// Sorts and ranks candidates specifically for the Trending feed
  List<Content> rankForTrending(
    List<Content> candidates, {
    double? userLat,
    double? userLng,
  }) {
    final List<MapEntry<Content, double>> scored = [];

    for (final item in candidates) {
      final velocity = calculateVelocityScore(item, userLat: userLat, userLng: userLng);
      final views = item.viewCount;
      final likes = item.likeCount;
      final shares = item.shareCount;

      // Composite trending score: 60% velocity, 20% raw volume, 20% freshness
      final volumeScore = (likes * 2.0) + (shares * 4.0) + math.min(100.0, views / 50.0);
      final ageHours = math.max(0.1, DateTime.now().difference(item.createdAt).inHours.toDouble());
      final freshnessScore = math.max(0.0, 100.0 - (ageHours * 1.5));

      final compositeScore = (velocity * 0.60) + (volumeScore * 0.20) + (freshnessScore * 0.20);
      scored.add(MapEntry(item, compositeScore));
    }

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((e) => e.key).toList();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ATOMIC LIKE & FOLLOW TRANSACTION GUARDS WITH VIRAL MULTIPLIERS
  // ──────────────────────────────────────────────────────────────────────────

  /// Atomic transaction guard for content likes.
  ///
  /// Prevents double-liking race conditions, atomically updates post and author karma,
  /// and calculates immediate viral acceleration boosts.
  Future<ViralLikeResult> atomicLikeGuard({
    required String userId,
    required String contentId,
    required String authorId,
    double? userLat,
    double? userLng,
  }) async {
    final likeRef = _firestore.collection('content_likes').doc('${userId}_$contentId');
    final userLikeRef = _firestore.collection('users').doc(userId).collection('likes').doc(contentId);
    final contentRef = _firestore.collection('content').doc(contentId);
    final authorRef = _firestore.collection('users').doc(authorId);

    return await _firestore.runTransaction((tx) async {
      final likeDoc = await tx.get(likeRef);
      if (likeDoc.exists) {
        // Idempotent: User has already liked this content
        return const ViralLikeResult(
          success: true,
          alreadyLiked: true,
        );
      }

      final contentDoc = await tx.get(contentRef);
      if (!contentDoc.exists) {
        throw Exception('Target content does not exist: $contentId');
      }

      final likeData = {
        'userId': userId,
        'contentId': contentId,
        'authorId': authorId,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Set unique like markers
      tx.set(likeRef, likeData);
      tx.set(userLikeRef, likeData);

      // Increment like count on content
      tx.update(contentRef, {
        'likeCount': FieldValue.increment(1),
      });

      // Increment creator karma/likes on profile
      tx.update(authorRef, {
        'likeCount': FieldValue.increment(1),
      });

      // Calculate new viral velocity with immediate multiplier boost
      final content = Content.fromFirestore(contentDoc);
      final geoMultiplier = _geoEngine.calculateGeoRelevanceScore(content, userLat, userLng);
      final viralMultiplier = calculateViralMultiplier(
        content,
        geoMultiplier: geoMultiplier,
        completionRatio: 1.0,
      );

      final updatedVelocity = calculateVelocityScore(
        content,
        geoMultiplier: geoMultiplier,
      );

      // Persist updated viral velocity score on content
      tx.update(contentRef, {
        'viralVelocityScore': updatedVelocity,
      });

      return ViralLikeResult(
        success: true,
        alreadyLiked: false,
        newLikeCount: content.likeCount + 1,
        viralMultiplier: viralMultiplier,
        updatedVelocity: updatedVelocity,
      );
    });
  }

  /// Atomic transaction guard for unliking content.
  Future<ViralUnlikeResult> atomicUnlikeGuard({
    required String userId,
    required String contentId,
    required String authorId,
  }) async {
    final likeRef = _firestore.collection('content_likes').doc('${userId}_$contentId');
    final userLikeRef = _firestore.collection('users').doc(userId).collection('likes').doc(contentId);
    final contentRef = _firestore.collection('content').doc(contentId);
    final authorRef = _firestore.collection('users').doc(authorId);

    return await _firestore.runTransaction((tx) async {
      final likeDoc = await tx.get(likeRef);
      if (!likeDoc.exists) {
        return const ViralUnlikeResult(
          success: true,
          alreadyUnliked: true,
        );
      }

      final contentDoc = await tx.get(contentRef);

      tx.delete(likeRef);
      tx.delete(userLikeRef);

      int currentLikes = 0;
      if (contentDoc.exists) {
        currentLikes = (contentDoc.data()?['likeCount'] as num?)?.toInt() ?? 0;
        final newLikes = math.max(0, currentLikes - 1);
        tx.update(contentRef, {'likeCount': newLikes});
      }

      tx.update(authorRef, {'likeCount': FieldValue.increment(-1)});

      return ViralUnlikeResult(
        success: true,
        alreadyUnliked: false,
        newLikeCount: math.max(0, currentLikes - 1),
      );
    });
  }

  /// Atomic transaction guard for user follow actions.
  ///
  /// When a follow originates directly from a video card (`originatingContentId`),
  /// that video receives a high-impact viral conversion multiplier boost (1.35x).
  Future<ViralFollowResult> atomicFollowGuard({
    required String currentUserId,
    required String targetUserId,
    String? originatingContentId,
  }) async {
    if (currentUserId == targetUserId) {
      return const ViralFollowResult(success: false);
    }

    final relRef = _firestore.collection('relationships').doc('${currentUserId}_$targetUserId');
    final currentUserRef = _firestore.collection('users').doc(currentUserId);
    final targetUserRef = _firestore.collection('users').doc(targetUserId);

    return await _firestore.runTransaction((tx) async {
      final relDoc = await tx.get(relRef);
      if (relDoc.exists) {
        final data = relDoc.data() ?? {};
        final status = data['status'];
        if (status == 'accepted' || status == 'pending') {
          return const ViralFollowResult(
            success: true,
            alreadyFollowing: true,
          );
        }
      }

      DocumentSnapshot<Map<String, dynamic>>? contentDoc;
      DocumentReference<Map<String, dynamic>>? contentRef;
      if (originatingContentId != null) {
        contentRef = _firestore.collection('content').doc(originatingContentId);
        contentDoc = await tx.get(contentRef);
      }

      // Record relationship
      tx.set(relRef, {
        'followerId': currentUserId,
        'followedId': targetUserId,
        'status': 'accepted',
        'createdAt': FieldValue.serverTimestamp(),
        'originatingContentId': originatingContentId,
      });

      // Update counters atomically
      tx.update(targetUserRef, {'followersCount': FieldValue.increment(1)});
      tx.update(currentUserRef, {'followingCount': FieldValue.increment(1)});

      double multiplierBoost = 1.0;
      bool conversionBonusApplied = false;

      // Video-to-follower conversion bonus
      if (contentDoc != null && contentDoc.exists && contentRef != null) {
        final content = Content.fromFirestore(contentDoc);
        multiplierBoost = 1.35; // 35% conversion multiplier boost
        conversionBonusApplied = true;

        final boostedVelocity = (calculateVelocityScore(content) * multiplierBoost).clamp(0.0, 100.0);
        tx.update(contentRef, {
          'followerConversions': FieldValue.increment(1),
          'viralVelocityScore': boostedVelocity,
        });
      }

      return ViralFollowResult(
        success: true,
        alreadyFollowing: false,
        conversionBonusApplied: conversionBonusApplied,
        viralMultiplierBoost: multiplierBoost,
      );
    });
  }
}
