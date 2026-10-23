enum SyncSessionType {
  watchParty,
  videoDiscussion,
  creatorPremiere,
  learningSession,
}

enum PlaybackState {
  playing,
  paused,
  buffering,
  ended,
}

enum ParticipantRole {
  host,
  moderator,
  viewer,
}

class SyncParticipant {
  final String userId;
  ParticipantRole role;
  bool isAudioMuted;
  bool isVideoMuted;
  DateTime joinedAt;

  SyncParticipant({
    required this.userId,
    this.role = ParticipantRole.viewer,
    this.isAudioMuted = true,
    this.isVideoMuted = true,
    required this.joinedAt,
  });
}

class SyncPlaybackContext {
  final String contentId; // ID of the video/content
  PlaybackState state;
  Duration currentPosition;
  DateTime lastUpdatedAt;

  SyncPlaybackContext({
    required this.contentId,
    this.state = PlaybackState.paused,
    this.currentPosition = Duration.zero,
    required this.lastUpdatedAt,
  });

  /// Derives the exact playback position for a late-joiner based on elapsed time since the last host sync
  Duration get calculatedRealtimePosition {
    if (state != PlaybackState.playing) {
      return currentPosition;
    }
    final elapsed = DateTime.now().difference(lastUpdatedAt);
    return currentPosition + elapsed;
  }
}

class SyncSession {
  final String id;
  final String title;
  final SyncSessionType type;
  final bool isPrivate;
  final String hostId;
  
  SyncPlaybackContext playback;
  final Map<String, SyncParticipant> participants;

  SyncSession({
    required this.id,
    required this.title,
    required this.type,
    required this.isPrivate,
    required this.hostId,
    required this.playback,
    Map<String, SyncParticipant>? participants,
  }) : participants = participants ?? {};

  bool isHostOrMod(String userId) {
    if (userId == hostId) return true;
    final p = participants[userId];
    return p != null && (p.role == ParticipantRole.host || p.role == ParticipantRole.moderator);
  }
}
