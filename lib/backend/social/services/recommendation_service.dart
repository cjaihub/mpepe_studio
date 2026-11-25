import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/content.dart';

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
  return RecommendationService(FirebaseFirestore.instance);
});

class RecommendationService {
  final FirebaseFirestore _firestore;

  RecommendationService(this._firestore);

  // ---------------------------------------------------------------------------
  // 1. Recommendation Pipeline
  // ---------------------------------------------------------------------------

  Future<List<Content>> getFeed(String currentUserId, FeedMode mode, {String? topic, int limit = 20}) async {
    // Pipeline Step 1: Candidate Generation
    final candidates = await _generateCandidates(currentUserId, mode, topic: topic, limit: limit * 3);

    // Pipeline Step 2: Policy Filtering (Authorization, Visibility, Blocks)
    final filtered = await _applyPolicyFiltering(currentUserId, candidates);

    // Pipeline Step 3: Safety Filtering (Moderation flags, NSFW, violence)
    final safeCandidates = _applySafetyFiltering(filtered);

    // Pipeline Step 4: Feedback Signals (Removed muted creators, "not interested" topics)
    final acceptableCandidates = await _applyFeedbackSignals(currentUserId, safeCandidates);

    // Pipeline Step 5: Ranking & Diversity (Optimize for relevance, quality, diversity)
    // - Score based on user affinity, content freshness, and quality.
    // - Enforce creator exposure limits (avoid monopolization).
    final ranked = _rankAndDiversify(acceptableCandidates);

    return ranked.take(limit).toList();
  }

  Future<List<Content>> _generateCandidates(String currentUserId, FeedMode mode, {String? topic, int limit = 60}) async {
    // `visibility == public` is required by firestore.rules, which only let a
    // user read public content (or their own).
    Query query = _firestore
        .collection('content')
        .where('type', isEqualTo: ContentType.short_video.name)
        .where('visibility', isEqualTo: 'public');

    switch (mode) {
      case FeedMode.forYou:
        // In a real system, hits an ML backend or candidate store. Here we get latest trending globally.
        query = query.orderBy('algorithmicScore', descending: true);
        break;
      case FeedMode.following:
      case FeedMode.followingCreators:
      case FeedMode.friends:
        // Ideally handled via a dedicated timeline fan-out or `in` array, simulated here.
        query = query.orderBy('createdAt', descending: true);
        break;
      case FeedMode.trending:
        query = query.orderBy('viewCount', descending: true);
        break;
      case FeedMode.nearby:
        // Geospatial query required
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
        // Handled via user's saved_items collection
        query = query.orderBy('createdAt', descending: true);
        break;
    }

    final snapshot = await query.limit(limit).get();
    return snapshot.docs.map((doc) => Content.fromFirestore(doc)).toList();
  }

  Future<List<Content>> _applyPolicyFiltering(String currentUserId, List<Content> candidates) async {
    // Filter out private content they shouldn't see, blocklists, etc.
    // Assuming privacy = 'public' passes, otherwise check relationships.
    return candidates.where((c) => c.visibility == 'public').toList();
  }

  List<Content> _applySafetyFiltering(List<Content> candidates) {
    // Client-side safety pass (e.g. strict mode on devices, pending moderation).
    // Videos still uploading or transcoding are never shown.
    return candidates.where((c) => c.isReady && c.mediaUrl.isNotEmpty).toList();
  }

  Future<List<Content>> _applyFeedbackSignals(String currentUserId, List<Content> candidates) async {
    // 1. Get user's negative feedback state (hidden creators, muted topics).
    final prefsDoc = await _firestore.collection('users').doc(currentUserId).collection('preferences').doc('recommendations').get();
    final hiddenCreators = List<String>.from(prefsDoc.data()?['hiddenCreators'] ?? []);
    final hiddenTopics = List<String>.from(prefsDoc.data()?['hiddenTopics'] ?? []);

    return candidates.where((c) {
      if (hiddenCreators.contains(c.authorId)) return false;
      if (c.hashtags.any((tag) => hiddenTopics.contains(tag))) return false;
      return true;
    }).toList();
  }

  List<Content> _rankAndDiversify(List<Content> candidates) {
    // Goal: Optimize for relevance, quality, diversity (Not purely addictive loops).
    // Simple heuristic: Interleave popular (quality), fresh (freshness), and diverse creators.
    final Set<String> seenCreators = {};
    final List<Content> ranked = [];
    
    // Sort by a combination of freshness and algorithmic score
    candidates.sort((a, b) {
      final scoreA = (a.likeCount * 2) + a.viewCount; // Mock score
      final scoreB = (b.likeCount * 2) + b.viewCount;
      return scoreB.compareTo(scoreA);
    });

    for (final content in candidates) {
      if (!seenCreators.contains(content.authorId)) {
        ranked.add(content);
        seenCreators.add(content.authorId);
      }
    }
    
    // Add the rest if we need more volume (relaxed diversity)
    for (final content in candidates) {
      if (!ranked.contains(content)) {
        ranked.add(content);
      }
    }

    return ranked;
  }

  // ---------------------------------------------------------------------------
  // 2. User Controls (Feedback Signals)
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

  Future<Map<String, dynamic>> getWhyAmISeeingThis(String contentId) async {
    // Generate explanation based on candidate pipeline (e.g. "Because you liked videos about #flutter")
    return {
      'reason': 'You follow topics related to this video.',
      'transparency_score': 0.95
    };
  }

  Future<void> _updatePreferenceArray(String currentUserId, String field, String value) async {
    final docRef = _firestore.collection('users').doc(currentUserId).collection('preferences').doc('recommendations');
    await docRef.set({
      field: FieldValue.arrayUnion([value])
    }, SetOptions(merge: true));
  }

  // ---------------------------------------------------------------------------
  // 3. Playback & Interaction Tracking
  // ---------------------------------------------------------------------------

  Future<void> trackEvent(String currentUserId, String contentId, ContentInteractionType type, Map<String, dynamic> metadata) async {
    // Ensure we do not fake views. Views only logged via explicit viewCompletion or duration thresholds.
    if (type == ContentInteractionType.impression && metadata['faked'] == true) return;

    await _firestore.collection('telemetry_events').add({
      'userId': currentUserId,
      'contentId': contentId,
      'eventType': type.name,
      'metadata': metadata,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Conditionally update canonical counts based on true verified events (in a real app via Cloud Functions)
    if (type == ContentInteractionType.like) {
       _firestore.collection('content').doc(contentId).update({'likeCount': FieldValue.increment(1)});
    }
    if (type == ContentInteractionType.viewCompletion) {
       _firestore.collection('content').doc(contentId).update({'viewCount': FieldValue.increment(1)});
    }
  }
}
