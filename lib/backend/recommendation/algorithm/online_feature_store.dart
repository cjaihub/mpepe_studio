import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'oneova_algorithm_models.dart';

final onlineFeatureStoreProvider = Provider<OnlineFeatureStore>((ref) {
  return OnlineFeatureStore(FirebaseFirestore.instance);
});

/// OneOva Online Feature Store
/// 
/// Real-time in-session feature store based on ByteDance Monolith principles:
/// Updates user's latent preference vector instantaneously in memory
/// using Exponential Moving Average (EMA) interest drift equations.
class OnlineFeatureStore {
  final FirebaseFirestore _firestore;

  // In-memory cache for ultra-fast, zero-latency ranking
  final Map<String, UserAffinityProfile> _sessionProfiles = {};

  // Exponential moving average decay factor (0.80 = recent 5 swipes carry heavy weight)
  static const double _decayFactor = 0.80;

  // Maximum topics kept in active affinity cache
  static const int _maxTopics = 50;

  OnlineFeatureStore(this._firestore);

  /// Retrieves or initializes the active in-session profile for a user
  UserAffinityProfile getProfile(String userId) {
    return _sessionProfiles.putIfAbsent(
      userId,
      () => UserAffinityProfile(
        userId: userId,
        sessionStartTime: DateTime.now(),
      ),
    );
  }

  /// Processes real-time watch telemetry from the video player and updates in-memory affinities
  void recordWatchTelemetry(VideoWatchTelemetry telemetry) {
    final profile = getProfile(telemetry.userId);

    // 1. Calculate Reward Delta based on Micro-Gestures & Watch Ratio
    double rewardDelta = 0.0;

    if (telemetry.isFastSkip) {
      // Swiped away in under 1.5s -> Negative feedback
      rewardDelta = -2.0;
    } else {
      // Reward completion
      if (telemetry.completionRate >= 0.90) {
        rewardDelta += 3.0;
      } else if (telemetry.completionRate >= 0.50) {
        rewardDelta += 1.2;
      } else {
        rewardDelta += 0.3;
      }

      // Reward looping (each loop is massive dopamine confirmation)
      if (telemetry.loopCount > 0) {
        rewardDelta += math.min(10.0, telemetry.loopCount * 4.0);
      }

      // Reward micro-actions
      if (telemetry.openedComments) rewardDelta += 2.0;
      if (telemetry.tappedProfile) rewardDelta += 2.5;
      if (telemetry.tappedAudio) rewardDelta += 2.0;
      if (telemetry.liked) rewardDelta += 1.5;
      if (telemetry.saved) rewardDelta += 3.5;
      if (telemetry.shared) rewardDelta += 5.0; // Sharing is the #1 viral signal
      if (telemetry.paused) rewardDelta += 0.8;
    }

    // 2. Update Topic Affinities with Exponential Moving Average
    final updatedTopics = Map<String, double>.from(profile.topicAffinities);
    for (final tag in telemetry.hashtags) {
      final cleanTag = tag.trim().toLowerCase().replaceAll('#', '');
      if (cleanTag.isEmpty) continue;

      final currentScore = updatedTopics[cleanTag] ?? 10.0;
      // EMA: S_t = lambda * S_{t-1} + (1 - lambda) * (Current + Delta)
      final newScore = (_decayFactor * currentScore) + ((1 - _decayFactor) * (currentScore + rewardDelta * 5.0));
      updatedTopics[cleanTag] = newScore.clamp(0.0, 100.0);
    }

    // Keep top topics sorted
    if (updatedTopics.length > _maxTopics) {
      final sortedEntries = updatedTopics.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      updatedTopics.clear();
      for (final e in sortedEntries.take(_maxTopics)) {
        updatedTopics[e.key] = e.value;
      }
    }

    // 3. Update Creator / Author Affinity
    final updatedAuthors = Map<String, double>.from(profile.authorAffinities);
    if (telemetry.authorId.isNotEmpty) {
      final currentAuthorScore = updatedAuthors[telemetry.authorId] ?? 5.0;
      final newAuthorScore = (currentAuthorScore + (rewardDelta * 2.0)).clamp(0.0, 100.0);
      updatedAuthors[telemetry.authorId] = newAuthorScore;
    }

    // 4. Update Audio Affinity
    final updatedAudio = Map<String, double>.from(profile.audioAffinities);
    if (telemetry.audioTrackId != null && telemetry.audioTrackId!.isNotEmpty) {
      final currentAudioScore = updatedAudio[telemetry.audioTrackId!] ?? 5.0;
      final newAudioScore = (currentAudioScore + (rewardDelta * 1.5)).clamp(0.0, 100.0);
      updatedAudio[telemetry.audioTrackId!] = newAudioScore;
    }

    // 5. Update Watch History (last 50 items for deduplication & diversity)
    final history = List<String>.from(profile.recentWatchHistory);
    history.insert(0, telemetry.contentId);
    if (history.length > 50) history.removeLast();

    // 6. Running average of completion rate
    final count = profile.totalVideosSwipedThisSession + 1;
    final newAvgDwell = ((profile.averageDwellRatio * (count - 1)) + telemetry.completionRate) / count;

    _sessionProfiles[telemetry.userId] = profile.copyWith(
      topicAffinities: updatedTopics,
      authorAffinities: updatedAuthors,
      audioAffinities: updatedAudio,
      recentWatchHistory: history,
      totalVideosSwipedThisSession: count,
      averageDwellRatio: newAvgDwell,
    );

    // Asynchronously log telemetry event to Firestore
    _persistTelemetryAsync(telemetry);
  }

  /// Injects conversational keywords or DM shares directly into user profile
  void recordConversationalSignal(ChatConversationalSignal signal) {
    final profile = getProfile(signal.userId);

    final updatedTopics = Map<String, double>.from(profile.topicAffinities);
    for (final topic in signal.extractedTopics) {
      final clean = topic.trim().toLowerCase();
      if (clean.length < 2) continue;
      // Chat topics receive an instant high-intent priming boost
      final current = updatedTopics[clean] ?? 20.0;
      updatedTopics[clean] = (current + 15.0).clamp(0.0, 100.0);
    }

    final updatedSharedVideos = Set<String>.from(profile.sharedInChatVideoIds);
    if (signal.sharedContentId != null) {
      updatedSharedVideos.add(signal.sharedContentId!);
    }

    final updatedPeers = Map<String, double>.from(profile.chatPeerAffinities);
    if (signal.chatPartnerId != null) {
      final peerCurrent = updatedPeers[signal.chatPartnerId!] ?? 5.0;
      updatedPeers[signal.chatPartnerId!] = (peerCurrent + 10.0).clamp(0.0, 100.0);
    }

    _sessionProfiles[signal.userId] = profile.copyWith(
      topicAffinities: updatedTopics,
      sharedInChatVideoIds: updatedSharedVideos,
      chatPeerAffinities: updatedPeers,
    );
  }

  /// Calculates dynamic exploration epsilon (Contextual Bandit)
  /// As session duration increases or dwell ratio drops, exploration increases to avoid fatigue
  double getDynamicExplorationEpsilon(String userId) {
    final profile = getProfile(userId);
    final sessionDurationMins = DateTime.now().difference(profile.sessionStartTime).inMinutes;

    // Base exploration: 15% (ensures new creators get discovered)
    double epsilon = 0.15;

    // If user has been watching for > 15 mins, fatigue increases -> inject variety
    if (sessionDurationMins > 15) {
      epsilon += 0.10;
    }

    // If average dwell is very low (< 0.35, user is aggressively skipping), boost exploration
    if (profile.totalVideosSwipedThisSession > 5 && profile.averageDwellRatio < 0.35) {
      epsilon += 0.15;
    }

    return epsilon.clamp(0.10, 0.40);
  }

  Future<void> _persistTelemetryAsync(VideoWatchTelemetry telemetry) async {
    try {
      await _firestore.collection('telemetry_events').add(telemetry.toMap());
    } catch (_) {
      // Silent catch to prevent UI interruption
    }
  }

  /// Hydrates profile from Firestore on cold app start
  Future<void> hydrateProfile(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).collection('algorithmic_state').doc('current').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final rawTopics = (data['topicAffinities'] as Map<String, dynamic>?) ?? {};
        final rawAuthors = (data['authorAffinities'] as Map<String, dynamic>?) ?? {};

        final topics = rawTopics.map((k, v) => MapEntry(k, (v as num).toDouble()));
        final authors = rawAuthors.map((k, v) => MapEntry(k, (v as num).toDouble()));

        final existing = getProfile(userId);
        _sessionProfiles[userId] = existing.copyWith(
          topicAffinities: {...topics, ...existing.topicAffinities},
          authorAffinities: {...authors, ...existing.authorAffinities},
        );
      }
    } catch (_) {
      // Offline fallback
    }
  }

  /// Flushes user affinity profile to Firestore for cross-session continuity
  Future<void> flushProfile(String userId) async {
    final profile = _sessionProfiles[userId];
    if (profile == null) return;

    try {
      await _firestore.collection('users').doc(userId).collection('algorithmic_state').doc('current').set({
        'topicAffinities': profile.topicAffinities,
        'authorAffinities': profile.authorAffinities,
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Safe fallback
    }
  }
}
