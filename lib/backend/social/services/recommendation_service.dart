import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/content.dart';
import '../../recommendation/algorithm/oneova_algorithm_models.dart';
import '../../recommendation/algorithm/online_feature_store.dart';
import '../../recommendation/algorithm/viral_trending_engine.dart';
import '../../recommendation/algorithm/oneova_neural_ranker.dart';
import '../../recommendation/algorithm/viral_velocity_score.dart';
import '../../moderation/services/content_safety_moderation_engine.dart';

enum FeedMode {
  forYou,
  following,
  friends,
  trending,
  nearby,
  latest,
  followingCreators,
  topic,
  saved,
}

enum ContentInteractionType {
  impression,
  viewStart,
  viewCompletion,
  watchDuration,
  rewatch,
  skip,
  like,
  reaction,
  comment,
  share,
  save,
  follow,
  notInterested,
  report,
  soundInteraction,
}

final recommendationServiceProvider = Provider<RecommendationService>((ref) {
  return RecommendationService(
    FirebaseFirestore.instance,
    neuralRanker: ref.read(oneOvaNeuralRankerProvider),
    featureStore: ref.read(onlineFeatureStoreProvider),
    trendingEngine: ref.read(viralTrendingEngineProvider),
    safetyEngine: ref.read(contentSafetyModerationEngineProvider),
  );
});

/// OneOva Recommendation Service
/// 
/// Integrates the OneOva Neural Pulse & Flow Algorithm (ONPA-Flow):
/// - Real-time in-session behavioral telemetry (OnlineFeatureStore)
/// - Conversational intelligence from OneOva chat (ChatAffinityExtractor)
/// - Multi-tier viral incubator & LinUCB exploration (ViralTrendingEngine)
/// - Multi-objective heavy ranking with MMR diversity (OneOvaNeuralRanker)
class RecommendationService {
  final FirebaseFirestore _firestore;
  final OneOvaNeuralRanker? neuralRanker;
  final OnlineFeatureStore? featureStore;
  final ViralTrendingEngine? trendingEngine;
  final ContentSafetyModerationEngine? safetyEngine;

  RecommendationService(
    this._firestore, {
    this.neuralRanker,
    this.featureStore,
    this.trendingEngine,
    this.safetyEngine,
  });

  // ---------------------------------------------------------------------------
  // 1. Recommendation Pipeline
  // ---------------------------------------------------------------------------

  Future<List<Content>> getFeed(String currentUserId, FeedMode mode, {String? topic, int limit = 20}) async {
    // Pipeline Step 1: Candidate Generation
    final candidates = await _generateCandidates(currentUserId, mode, topic: topic, limit: limit * 3);
    final ranked = await rankCandidates(currentUserId, mode, candidates);
    return ranked.take(limit).toList();
  }

  /// Content types the home feed shows: reels play, photos render full-screen.
  static const feedContentTypes = <String>['short_video', 'photo'];

  /// Whether [c] may appear in other users' public feeds.
  static bool isFeedEligible(Content c) =>
      c.visibility == 'public' &&
      feedContentTypes.contains(c.type.name) &&
      c.mediaUrl.isNotEmpty &&
      !c.mediaUrl.contains('picsum');

  /// Maps a `content` query snapshot to feed items, newest first. Malformed
  /// docs are skipped so one bad write can't empty everyone's feed.
  static List<Content> mapFeedDocs(Iterable<DocumentSnapshot> docs) {
    final items = <Content>[];
    for (final doc in docs) {
      try {
        final c = Content.fromFirestore(doc);
        if (isFeedEligible(c)) items.add(c);
      } catch (e) {
        debugPrint('[RecommendationService] skipping malformed content ${doc.id}: $e');
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  /// Real-time feed candidates: emits again whenever anyone publishes,
  /// edits or removes content (For You), or when the people the user follows
  /// post or the follow graph itself changes (Following / Friends).
  Stream<List<Content>> watchFeedCandidates(String currentUserId, FeedMode mode, {int limit = 60}) {
    switch (mode) {
      case FeedMode.following:
      case FeedMode.followingCreators:
      case FeedMode.friends:
        return _watchFollowingCandidates(currentUserId, limit: limit);
      default:
        return _firestore
            .collection('content')
            .where('type', whereIn: feedContentTypes)
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .snapshots()
            .map((s) => mapFeedDocs(s.docs));
    }
  }

  /// Follow graph (`relationships`, accepted) → one live `content` query per
  /// 30 followed authors, merged newest first.
  Stream<List<Content>> _watchFollowingCandidates(String currentUserId, {required int limit}) {
    late StreamController<List<Content>> controller;
    StreamSubscription? graphSub;
    final chunkSubs = <StreamSubscription>[];
    var chunkResults = <List<Content>>[];

    void cancelChunks() {
      for (final s in chunkSubs) {
        s.cancel();
      }
      chunkSubs.clear();
    }

    void emit() {
      final merged = chunkResults.expand((l) => l).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      controller.add(merged.length > limit ? merged.sublist(0, limit) : merged);
    }

    controller = StreamController<List<Content>>(
      onListen: () {
        graphSub = _firestore
            .collection('relationships')
            .where('followerId', isEqualTo: currentUserId)
            .where('status', isEqualTo: 'accepted')
            .snapshots()
            .listen((graph) {
          final ids = graph.docs
              .map((d) => d.data()['followingId'])
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList();
          cancelChunks();
          if (ids.isEmpty) {
            chunkResults = [];
            controller.add(const []);
            return;
          }
          final chunks = <List<String>>[
            for (var i = 0; i < ids.length; i += 30) ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30),
          ];
          chunkResults = List.generate(chunks.length, (_) => <Content>[]);
          for (var i = 0; i < chunks.length; i++) {
            chunkSubs.add(_firestore
                .collection('content')
                .where('authorId', whereIn: chunks[i])
                .orderBy('createdAt', descending: true)
                .limit(limit)
                .snapshots()
                .listen((s) {
              chunkResults[i] = mapFeedDocs(s.docs);
              emit();
            }, onError: controller.addError));
          }
        }, onError: controller.addError);
      },
      onCancel: () async {
        cancelChunks();
        await graphSub?.cancel();
      },
    );
    return controller.stream;
  }

  /// Pipeline steps 2–5 (policy, safety, feedback signals, ranking) over
  /// already generated candidates. Shared by [getFeed] and the live feed.
  Future<List<Content>> rankCandidates(String currentUserId, FeedMode mode, List<Content> candidates) async {
    return _rank(currentUserId, mode, await _filterWithFeedback(currentUserId, candidates));
  }

  /// Pipeline steps 2–4 only: what a newly published item must pass before
  /// it is slotted into a feed that is already on screen.
  Future<List<Content>> filterCandidates(String currentUserId, List<Content> candidates) async {
    final feedback = await _filterWithFeedback(currentUserId, candidates);
    return feedback.candidates;
  }

  Future<_FeedbackFilterResult> _filterWithFeedback(String currentUserId, List<Content> candidates) async {
    // Pipeline Step 2: Policy Filtering (Authorization, Visibility, Blocks)
    final filtered = await _applyPolicyFiltering(currentUserId, candidates);

    // Pipeline Step 3: Safety Filtering (Moderation flags, NSFW, violence)
    final safeCandidates = _applySafetyFiltering(filtered);

    // Pipeline Step 4: Feedback Signals (Removed muted creators, "not interested" topics)
    return _applyFeedbackSignals(currentUserId, safeCandidates);
  }

  List<Content> _rank(String currentUserId, FeedMode mode, _FeedbackFilterResult feedbackResult) {
    final acceptableCandidates = feedbackResult.candidates;

    // Pipeline Step 5: Advanced Ranking & Diversity
    List<Content> ranked;

    if (mode == FeedMode.forYou && neuralRanker != null) {
      // OneOva Neural Pulse & Flow Master Ranker (ONPA-Flow)
      ranked = neuralRanker!.rankForYouFeed(
        userId: currentUserId,
        candidates: acceptableCandidates,
        hiddenCreators: feedbackResult.hiddenCreators,
        hiddenTopics: feedbackResult.hiddenTopics,
      );
    } else if (mode == FeedMode.trending && trendingEngine != null) {
      // OneOva Viral Trending Velocity Ranker
      ranked = trendingEngine!.rankForTrending(acceptableCandidates);
    } else {
      // Heuristic fallback for other modes (Following, Friends, Topics)
      ranked = _rankAndDiversify(acceptableCandidates);
    }

    return ranked;
  }

  Future<List<Content>> _generateCandidates(String currentUserId, FeedMode mode, {String? topic, int limit = 60}) async {
    Query query = _firestore.collection('content').where('type', isEqualTo: ContentType.short_video.name);

    switch (mode) {
      case FeedMode.forYou:
        query = query.orderBy('createdAt', descending: true);
        break;
      case FeedMode.following:
      case FeedMode.followingCreators:
      case FeedMode.friends:
        final followingSnapshot = await _firestore.collection('relationships')
            .where('followerId', isEqualTo: currentUserId)
            .where('status', isEqualTo: 'accepted')
            .get();
        final followingIds = followingSnapshot.docs.map((d) => d.data()['followingId'] as String).toList();
        
        if (followingIds.isEmpty) {
          return [];
        }
        
        List<Content> allFollowedContent = [];
        for (var i = 0; i < followingIds.length; i += 30) {
          final chunk = followingIds.sublist(i, i + 30 > followingIds.length ? followingIds.length : i + 30);
          final q = query.where('authorId', whereIn: chunk).orderBy('createdAt', descending: true).limit(limit);
          final snap = await q.get();
          allFollowedContent.addAll(snap.docs.map((d) => Content.fromFirestore(d)));
        }
        
        allFollowedContent.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (allFollowedContent.length > limit) {
          allFollowedContent = allFollowedContent.sublist(0, limit);
        }
        return allFollowedContent;
      case FeedMode.trending:
        query = query.orderBy('viewCount', descending: true);
        break;
      case FeedMode.nearby:
        query = query.orderBy('createdAt', descending: true);
        break;
      case FeedMode.latest:
        query = query.orderBy('createdAt', descending: true);
        break;
      case FeedMode.topic:
        if (topic != null) {
          query = query.where('hashtags', arrayContains: topic).orderBy('createdAt', descending: true);
        }
        break;
      case FeedMode.saved:
        query = query.orderBy('createdAt', descending: true);
        break;
    }

    final snapshot = await query.limit(limit).get();
    final allContent = snapshot.docs.map((doc) => Content.fromFirestore(doc)).toList();
    // Filter out image URLs that crash video player
    return allContent.where((c) => !c.mediaUrl.contains('picsum')).toList();
  }

  Future<List<Content>> _applyPolicyFiltering(String currentUserId, List<Content> candidates) async {
    return candidates.where((c) => c.visibility == 'public').toList();
  }

  List<Content> _applySafetyFiltering(List<Content> candidates) {
    final activeSafetyEngine = safetyEngine ?? ContentSafetyModerationEngine(_firestore);
    return candidates.where((c) {
      return activeSafetyEngine.isCandidateSafe(
        description: c.description,
        hashtags: c.hashtags,
        status: null,
      );
    }).toList();
  }

  Future<_FeedbackFilterResult> _applyFeedbackSignals(String currentUserId, List<Content> candidates) async {
    if (currentUserId.isEmpty || currentUserId == 'unknown') {
      return _FeedbackFilterResult(
        candidates: candidates,
        hiddenCreators: const [],
        hiddenTopics: const [],
      );
    }
    List<String> hiddenCreators = [];
    List<String> hiddenTopics = [];
    try {
      final prefsDoc = await _firestore.collection('users').doc(currentUserId).collection('preferences').doc('recommendations').get();
      hiddenCreators = List<String>.from(prefsDoc.data()?['hiddenCreators'] ?? []);
      hiddenTopics = List<String>.from(prefsDoc.data()?['hiddenTopics'] ?? []);
    } catch (_) {
      // Unauthenticated or preferences document not yet created
    }

    final filtered = candidates.where((c) {
      if (hiddenCreators.contains(c.authorId)) return false;
      if (c.hashtags.any((tag) => hiddenTopics.contains(tag))) return false;
      return true;
    }).toList();

    return _FeedbackFilterResult(
      candidates: filtered,
      hiddenCreators: hiddenCreators,
      hiddenTopics: hiddenTopics,
    );
  }

  List<Content> _rankAndDiversify(List<Content> candidates) {
    final Set<String> seenCreators = {};
    final List<Content> ranked = [];
    
    candidates.sort((a, b) {
      final scoreA = (a.likeCount * 2) + a.viewCount;
      final scoreB = (b.likeCount * 2) + b.viewCount;
      return scoreB.compareTo(scoreA);
    });

    for (final content in candidates) {
      if (!seenCreators.contains(content.authorId)) {
        ranked.add(content);
        seenCreators.add(content.authorId);
      }
    }
    
    for (final content in candidates) {
      if (!ranked.contains(content)) {
        ranked.add(content);
      }
    }

    return ranked;
  }

  // ---------------------------------------------------------------------------
  // 2. Real-Time Telemetry & Watch Interaction Recording
  // ---------------------------------------------------------------------------

  /// Records comprehensive video watch telemetry to update user's online feature store
  void recordWatchTelemetry(VideoWatchTelemetry telemetry) {
    featureStore?.recordWatchTelemetry(telemetry);
  }

  // ---------------------------------------------------------------------------
  // 3. User Controls (Feedback Signals)
  // ---------------------------------------------------------------------------

  Future<void> hideCreator(String currentUserId, String creatorId) async {
    await _updatePreferenceArray(currentUserId, 'hiddenCreators', creatorId);
    trackEvent(currentUserId, 'system', ContentInteractionType.notInterested, {'reason': 'hide_creator', 'creatorId': creatorId});
  }

  Future<void> hideTopic(String currentUserId, String topic) async {
    await _updatePreferenceArray(currentUserId, 'hiddenTopics', topic);
    trackEvent(currentUserId, 'system', ContentInteractionType.notInterested, {'reason': 'hide_topic', 'topic': topic});
  }

  Future<void> markNotInterested(String currentUserId, String contentId) async {
    await _firestore.collection('users').doc(currentUserId)
      .collection('interactions').doc(contentId).set({
        'notInterested': true,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    trackEvent(currentUserId, contentId, ContentInteractionType.notInterested, {});
  }

  Future<void> resetRecommendations(String currentUserId) async {
    await _firestore.collection('users').doc(currentUserId).collection('preferences').doc('recommendations').delete();
  }

  Future<Map<String, dynamic>> getWhyAmISeeingThis(String contentId, {String? userId}) async {
    final uid = userId ?? 'currentUser';
    final profile = featureStore?.getProfile(uid);

    if (profile != null) {
      if (profile.sharedInChatVideoIds.contains(contentId)) {
        return {
          'reason': 'Shared or recommended directly in your OneOva Chats.',
          'transparency_score': 0.99,
        };
      }
    }

    return {
      'reason': 'Curated by OneOva Neural Pulse & Flow based on your watch patterns and trending topics.',
      'transparency_score': 0.95,
    };
  }

  /// The viral-velocity factors behind a reel's For You rank.
  ViralScoreBreakdown explainViral(Content content) =>
      const ViralVelocityScorer().score(ViralSignals.fromContent(content));

  Future<void> _updatePreferenceArray(String currentUserId, String field, String value) async {
    final docRef = _firestore.collection('users').doc(currentUserId).collection('preferences').doc('recommendations');
    await docRef.set({
      field: FieldValue.arrayUnion([value])
    }, SetOptions(merge: true));
  }

  // ---------------------------------------------------------------------------
  // 4. Playback & Interaction Tracking
  // ---------------------------------------------------------------------------

  Future<void> trackEvent(String currentUserId, String contentId, ContentInteractionType type, Map<String, dynamic> metadata) async {
    if (type == ContentInteractionType.impression && metadata['faked'] == true) return;

    await _firestore.collection('telemetry_events').add({
      'userId': currentUserId,
      'contentId': contentId,
      'eventType': type.name,
      'metadata': metadata,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // likeCount is owned by InteractionRepository's one-per-user transaction;
    // incrementing it here too would double-count likes. viewCount is owned
    // by InteractionRepository.recordView (once per viewer), so a completed
    // play counts as a completion, not another view.
    final contentRef = _firestore.collection('content').doc(contentId);
    Map<String, dynamic>? counters;
    switch (type) {
      case ContentInteractionType.viewCompletion:
        counters = {'completionCount': FieldValue.increment(1)};
        break;
      case ContentInteractionType.watchDuration:
        final ms = (metadata['durationMs'] as num?)?.toInt() ?? 0;
        // Ignore empty and absurd (>10 min) slots.
        if (ms > 0 && ms <= 600000) counters = {'watchTimeMs': FieldValue.increment(ms)};
        break;
      case ContentInteractionType.follow:
        counters = {'followerConversions': FieldValue.increment(1)};
        break;
      default:
        break;
    }
    if (counters != null && contentId.isNotEmpty && contentId != 'system') {
      // Ranking counters are best-effort; a failed write must not break playback.
      contentRef.update(counters).catchError((Object e) {
        debugPrint('[RecommendationService] ${type.name} counter skipped: $e');
      });
    }
  }
}

class _FeedbackFilterResult {
  final List<Content> candidates;
  final List<String> hiddenCreators;
  final List<String> hiddenTopics;

  _FeedbackFilterResult({
    required this.candidates,
    required this.hiddenCreators,
    required this.hiddenTopics,
  });
}
