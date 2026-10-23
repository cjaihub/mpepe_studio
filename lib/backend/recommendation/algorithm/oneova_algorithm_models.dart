import 'package:cloud_firestore/cloud_firestore.dart';

/// OneOva Neural Pulse & Flow Algorithm (ONPA-Flow) Data Models
/// 
/// Research-backed models fusing:
/// 1. Real-time in-session dwell & micro-gestures (Monolith arXiv:2209.07663)
/// 2. Cross-modal conversational affinity from DMs/Chat (Conversational Graph)
/// 3. Multi-tier progressive test pools for easy creator virality (ByteDance Cold-Start)
/// 4. Contextual Multi-Armed Bandits (LinUCB exploration)

enum ViralTier {
  tier0Seed,      // 0 - 300 impressions (Cold-start incubator)
  tier1Emerging,  // 301 - 5,000 impressions (High completion & loop)
  tier2Trending,  // 5,001 - 50,000 impressions (Accelerated breakout)
  tier3Megapool,  // 50,001+ impressions (Global viral feed)
}

enum MicroGestureType {
  fastSkip,          // Swiped away in < 1500ms (-1.5 penalty)
  partialWatch,      // Watched 15% - 75% (+0.5)
  fullCompletion,    // Watched >= 90% (+2.5)
  loopReplay,        // Watched >= 150% (+4.5 per loop)
  commentDrawerOpen, // Read/wrote comments (+2.0)
  authorProfileTap,  // Clicked creator avatar (+2.5)
  audioDiscTap,      // Clicked sound track (+2.0)
  shareToChat,       // Shared in OneOva Direct Chat (+5.0)
  shareExternal,     // Shared to external app (+4.5)
  doubleTapLike,     // Liked (+1.2)
  bookmarkSave,      // Saved (+3.0)
  videoPauseInspect, // Paused to inspect details (+0.8)
}

/// Comprehensive telemetry capture for a single video viewing session
class VideoWatchTelemetry {
  final String userId;
  final String contentId;
  final String authorId;
  final List<String> hashtags;
  final String? audioTrackId;
  
  final int dwellTimeMs;
  final int videoDurationMs;
  final double completionRate; // dwellTimeMs / videoDurationMs
  final int loopCount;         // floor(dwellTimeMs / videoDurationMs)
  final bool isFastSkip;       // dwellTimeMs < 1500
  
  final bool openedComments;
  final bool tappedProfile;
  final bool tappedAudio;
  final bool liked;
  final bool saved;
  final bool shared;
  final bool paused;
  
  final DateTime timestamp;

  const VideoWatchTelemetry({
    required this.userId,
    required this.contentId,
    required this.authorId,
    required this.hashtags,
    this.audioTrackId,
    required this.dwellTimeMs,
    required this.videoDurationMs,
    required this.completionRate,
    required this.loopCount,
    required this.isFastSkip,
    this.openedComments = false,
    this.tappedProfile = false,
    this.tappedAudio = false,
    this.liked = false,
    this.saved = false,
    this.shared = false,
    this.paused = false,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'contentId': contentId,
      'authorId': authorId,
      'hashtags': hashtags,
      'audioTrackId': audioTrackId,
      'dwellTimeMs': dwellTimeMs,
      'videoDurationMs': videoDurationMs,
      'completionRate': completionRate,
      'loopCount': loopCount,
      'isFastSkip': isFastSkip,
      'openedComments': openedComments,
      'tappedProfile': tappedProfile,
      'tappedAudio': tappedAudio,
      'liked': liked,
      'saved': saved,
      'shared': shared,
      'paused': paused,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }
}

/// Privacy-preserving conversational signal extracted from OneOva chat
class ChatConversationalSignal {
  final String userId;
  final List<String> extractedTopics; // Lowercase entity keywords e.g. ['tech', 'music', 'fashion']
  final String? sharedContentId;      // If a reel was shared directly in DM
  final String? chatPartnerId;        // Peer user ID for collaborative graph
  final DateTime timestamp;

  const ChatConversationalSignal({
    required this.userId,
    required this.extractedTopics,
    this.sharedContentId,
    this.chatPartnerId,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'extractedTopics': extractedTopics,
      'sharedContentId': sharedContentId,
      'chatPartnerId': chatPartnerId,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }
}

/// Dynamic in-session user affinity profile updated on every swipe and chat
class UserAffinityProfile {
  final String userId;
  final Map<String, double> topicAffinities;     // Topic -> Affinity score (0.0 - 100.0)
  final Map<String, double> authorAffinities;    // Author -> Affinity score
  final Map<String, double> audioAffinities;     // Audio -> Affinity score
  final Map<String, double> chatPeerAffinities;  // Chat partner -> Interaction frequency
  final Set<String> sharedInChatVideoIds;        // Video IDs shared in DMs
  final List<String> recentWatchHistory;         // Last 30 watched video IDs (for deduplication)
  final DateTime sessionStartTime;
  final int totalVideosSwipedThisSession;
  final double averageDwellRatio;               // Running average of completion rate

  const UserAffinityProfile({
    required this.userId,
    this.topicAffinities = const {},
    this.authorAffinities = const {},
    this.audioAffinities = const {},
    this.chatPeerAffinities = const {},
    this.sharedInChatVideoIds = const {},
    this.recentWatchHistory = const [],
    required this.sessionStartTime,
    this.totalVideosSwipedThisSession = 0,
    this.averageDwellRatio = 0.5,
  });

  UserAffinityProfile copyWith({
    Map<String, double>? topicAffinities,
    Map<String, double>? authorAffinities,
    Map<String, double>? audioAffinities,
    Map<String, double>? chatPeerAffinities,
    Set<String>? sharedInChatVideoIds,
    List<String>? recentWatchHistory,
    DateTime? sessionStartTime,
    int? totalVideosSwipedThisSession,
    double? averageDwellRatio,
  }) {
    return UserAffinityProfile(
      userId: userId,
      topicAffinities: topicAffinities ?? this.topicAffinities,
      authorAffinities: authorAffinities ?? this.authorAffinities,
      audioAffinities: audioAffinities ?? this.audioAffinities,
      chatPeerAffinities: chatPeerAffinities ?? this.chatPeerAffinities,
      sharedInChatVideoIds: sharedInChatVideoIds ?? this.sharedInChatVideoIds,
      recentWatchHistory: recentWatchHistory ?? this.recentWatchHistory,
      sessionStartTime: sessionStartTime ?? this.sessionStartTime,
      totalVideosSwipedThisSession: totalVideosSwipedThisSession ?? this.totalVideosSwipedThisSession,
      averageDwellRatio: averageDwellRatio ?? this.averageDwellRatio,
    );
  }
}

/// Algorithmic engagement & velocity vector computed for each video
class VideoAlgorithmicMetrics {
  final String contentId;
  final ViralTier viralTier;
  final int impressionCount;
  final double completionRate;    // Total completed / total impressions
  final double loopRate;          // Total loops / total impressions
  final double skipRate;          // Total fast-skips / total impressions
  final double shareRatio;        // Total shares / total impressions
  final double commentRatio;      // Total comments / total impressions
  final double likeRatio;         // Total likes / total impressions
  final double viralVelocityScore;// Real-time escalation score
  final double explorationBonus;  // UCB / Thompson Sampling exploration factor
  final DateTime publishedAt;

  const VideoAlgorithmicMetrics({
    required this.contentId,
    this.viralTier = ViralTier.tier0Seed,
    this.impressionCount = 0,
    this.completionRate = 0.0,
    this.loopRate = 0.0,
    this.skipRate = 0.0,
    this.shareRatio = 0.0,
    this.commentRatio = 0.0,
    this.likeRatio = 0.0,
    this.viralVelocityScore = 50.0,
    this.explorationBonus = 1.0,
    required this.publishedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'contentId': contentId,
      'viralTier': viralTier.name,
      'impressionCount': impressionCount,
      'completionRate': completionRate,
      'loopRate': loopRate,
      'skipRate': skipRate,
      'shareRatio': shareRatio,
      'commentRatio': commentRatio,
      'likeRatio': likeRatio,
      'viralVelocityScore': viralVelocityScore,
      'explorationBonus': explorationBonus,
      'publishedAt': publishedAt,
    };
  }

  factory VideoAlgorithmicMetrics.fromMap(Map<String, dynamic> data, String id) {
    return VideoAlgorithmicMetrics(
      contentId: id,
      viralTier: ViralTier.values.firstWhere(
        (t) => t.name == data['viralTier'],
        orElse: () => ViralTier.tier0Seed,
      ),
      impressionCount: (data['impressionCount'] as num?)?.toInt() ?? 0,
      completionRate: (data['completionRate'] as num?)?.toDouble() ?? 0.0,
      loopRate: (data['loopRate'] as num?)?.toDouble() ?? 0.0,
      skipRate: (data['skipRate'] as num?)?.toDouble() ?? 0.0,
      shareRatio: (data['shareRatio'] as num?)?.toDouble() ?? 0.0,
      commentRatio: (data['commentRatio'] as num?)?.toDouble() ?? 0.0,
      likeRatio: (data['likeRatio'] as num?)?.toDouble() ?? 0.0,
      viralVelocityScore: (data['viralVelocityScore'] as num?)?.toDouble() ?? 50.0,
      explorationBonus: (data['explorationBonus'] as num?)?.toDouble() ?? 1.0,
      publishedAt: (data['publishedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
