import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../social/models/content.dart';
import 'oneova_algorithm_models.dart';
import 'online_feature_store.dart';
import 'viral_trending_engine.dart';
import 'viral_velocity_score.dart';

final oneOvaNeuralRankerProvider = Provider<OneOvaNeuralRanker>((ref) {
  return OneOvaNeuralRanker(
    ref.read(onlineFeatureStoreProvider),
    ref.read(viralTrendingEngineProvider),
  );
});

/// OneOva Neural Pulse & Flow Master Ranker (ONPA-Flow)
/// 
/// Fuses:
/// 1. Real-time in-session behavioral telemetry (Monolith online learning)
/// 2. Conversational signals from OneOva chat
/// 3. LinUCB cold-start exploration bandit for easy virality
/// 4. Maximal Marginal Relevance (MMR) for dopamine rhythm pacing
class OneOvaNeuralRanker {
  final OnlineFeatureStore _featureStore;
  final ViralTrendingEngine _trendingEngine;

  final ViralVelocityScorer _viralScorer = const ViralVelocityScorer();

  OneOvaNeuralRanker(this._featureStore, this._trendingEngine);

  /// Ranks candidates for the user's "For You" feed
  List<Content> rankForYouFeed({
    required String userId,
    required List<Content> candidates,
    List<String> hiddenCreators = const [],
    List<String> hiddenTopics = const [],
  }) {
    if (candidates.isEmpty) return [];

    final profile = _featureStore.getProfile(userId);
    final epsilon = _featureStore.getDynamicExplorationEpsilon(userId);

    // Filter out hidden topics and hidden creators
    final eligibleCandidates = candidates.where((c) {
      if (hiddenCreators.contains(c.authorId)) return false;
      if (c.hashtags.any((t) => hiddenTopics.contains(t.toLowerCase()))) return false;
      // Filter out images that crash video player
      if (c.mediaUrl.contains('picsum')) return false;
      return true;
    }).toList();

    if (eligibleCandidates.isEmpty) return [];

    // Filter out videos watched recently in this active session (deduplication)
    final freshPool = eligibleCandidates.where(
      (c) => !profile.recentWatchHistory.contains(c.id),
    ).toList();

    final candidatePool = freshPool.isNotEmpty ? freshPool : eligibleCandidates;

    // Estimate global view volume for UCB bandit calculation
    int totalViewsEstimate = 0;
    for (final c in candidatePool) {
      totalViewsEstimate += c.viewCount;
    }
    totalViewsEstimate = math.max(10000, totalViewsEstimate);

    // Extract recent authors for fatigue damping
    final recentAuthors = candidatePool
        .take(10)
        .map((c) => c.authorId)
        .toList();

    // Compute Neural Pulse Flow Score for each candidate
    final List<MapEntry<Content, double>> scoredCandidates = [];

    for (final c in candidatePool) {
      final score = _computeItemScore(
        content: c,
        profile: profile,
        epsilon: epsilon,
        totalViewsEstimate: totalViewsEstimate,
        recentAuthors: recentAuthors,
      );
      scoredCandidates.add(MapEntry(c, score));
    }

    // Sort by computed score
    scoredCandidates.sort((a, b) => b.value.compareTo(a.value));

    // Apply MMR (Maximal Marginal Relevance) Diversity Re-Ranking
    return _applyMaximalMarginalRelevance(
      scoredCandidates.map((e) => e.key).toList(),
      profile,
    );
  }

  /// Multi-Objective Score Equation:
  /// S(u, c) = [S_topic + S_chat + S_author + S_audio + S_velocity + (UCB * epsilon)] * FatigueDampener
  double _computeItemScore({
    required Content content,
    required UserAffinityProfile profile,
    required double epsilon,
    required int totalViewsEstimate,
    required List<String> recentAuthors,
  }) {
    // 1. Topic Match Score
    double topicScore = 0.0;
    for (final tag in content.hashtags) {
      final clean = tag.trim().toLowerCase().replaceAll('#', '');
      final affinity = profile.topicAffinities[clean];
      if (affinity != null) {
        topicScore += affinity * 1.4;
      }
    }

    // 2. Chat & Conversational Affinity Score (The OneOva Superpower)
    double chatScore = 0.0;
    // Direct share in DM: massive 45.0 point priority
    if (profile.sharedInChatVideoIds.contains(content.id)) {
      chatScore += 45.0;
    }
    // Social graph: Content from authors who are frequent chat partners
    final peerAffinity = profile.chatPeerAffinities[content.authorId];
    if (peerAffinity != null) {
      chatScore += peerAffinity * 1.8;
    }

    // 3. Creator Loyalty Score
    final authorAffinity = profile.authorAffinities[content.authorId] ?? 0.0;
    final authorScore = authorAffinity * 1.5;

    // 4. Audio Resonance Score
    final musicId = content.mediaMetadata.musicId;
    final audioAffinity = (musicId != null) ? (profile.audioAffinities[musicId] ?? 0.0) : 0.0;
    final audioScore = audioAffinity * 1.2;

    // 5. Viral Velocity: real likes/comments/shares/saves/completions/watch
    // time/follows per hour since posting, time-decayed, fresh-post boost.
    // Typical range 0–10, scaled so a fast-rising post can out-rank weak
    // personal affinity but not a direct share in chat.
    final velocityScore = _viralScorer.scoreContent(content) * 4.0;

    // 6. Cold-Start Bandit Exploration Bonus (Guarantees new creators trend easily)
    final ucbBonus = _trendingEngine.calculateExplorationBonus(content, totalViewsEstimate);
    final weightedExploration = ucbBonus * epsilon * 3.5;

    // 7. Base Quality: lifetime real engagement, log-scaled and capped so
    // old totals can't outweigh current velocity.
    final baseQuality = math.min(
      10.0,
      math.log(1 + content.likeCount + content.commentCount * 3 + (content.shareCount + content.repostCount) * 5 + content.saveCount * 4),
    );

    // 8. Media Quality & Mobile Feed Immersion Bonus (1080p+/adaptive/9:16 vertical)
    double mediaQualityBonus = 0.0;
    if (content.mediaMetadata.isAdaptiveBitrate ||
        content.mediaMetadata.resolutions.any((r) => r.contains('1080') || r.contains('4k'))) {
      mediaQualityBonus += 8.0;
    }
    if ((content.mediaMetadata.aspectRatio - (9 / 16)).abs() < 0.05) {
      mediaQualityBonus += 4.0;
    }

    // 9. Collaboration & Shared Fanbase Resonance (Cross-pollination of follower pools)
    double collaborationBonus = 0.0;
    if (content.mentions.isNotEmpty ||
        content.attribution?.derivativeType == DerivativeType.remix ||
        content.attribution?.derivativeType == DerivativeType.duet) {
      collaborationBonus += 12.0;
    }

    // 10. Geolocation Proximity & Local Pulse
    double locationBonus = 0.0;
    if (content.location != null && content.location!.trim().isNotEmpty) {
      locationBonus += 5.0;
    }

    // Composite Un-damped Score
    final rawComposite = topicScore +
        chatScore +
        authorScore +
        audioScore +
        velocityScore +
        weightedExploration +
        baseQuality +
        mediaQualityBonus +
        collaborationBonus +
        locationBonus;

    // 8. Creator Fatigue Dampener (Prevents feed monopolization)
    final fatigueMultiplier = _trendingEngine.calculateAuthorFatigueDampener(
      content.authorId,
      recentAuthors,
    );

    return rawComposite * fatigueMultiplier;
  }

  /// Applies MMR (Maximal Marginal Relevance) to pace the dopamine rhythm:
  /// Prevents clustering of identical creators or same topics
  List<Content> _applyMaximalMarginalRelevance(
    List<Content> rankedList,
    UserAffinityProfile profile,
  ) {
    if (rankedList.length <= 2) return rankedList;

    final List<Content> diversified = [];
    final List<Content> remaining = List.from(rankedList);

    // Pick top video as anchor
    diversified.add(remaining.removeAt(0));

    while (remaining.isNotEmpty && diversified.length < rankedList.length) {
      final lastVideo = diversified.last;
      int bestIndex = 0;
      double bestDiversityScore = -999999.0;

      for (int i = 0; i < math.min(10, remaining.length); i++) {
        final candidate = remaining[i];
        
        // Dissimilarity penalty
        double similarityPenalty = 0.0;
        
        // Same creator penalty
        if (candidate.authorId == lastVideo.authorId) {
          similarityPenalty += 40.0;
        }

        // Shared hashtags penalty
        final sharedTags = candidate.hashtags.where(
          (t) => lastVideo.hashtags.contains(t),
        ).length;
        similarityPenalty += sharedTags * 8.0;

        // Effective MMR score
        final rankPriority = (remaining.length - i).toDouble();
        final mmrScore = rankPriority - similarityPenalty;

        if (mmrScore > bestDiversityScore) {
          bestDiversityScore = mmrScore;
          bestIndex = i;
        }
      }

      diversified.add(remaining.removeAt(bestIndex));
    }

    return diversified;
  }
}
