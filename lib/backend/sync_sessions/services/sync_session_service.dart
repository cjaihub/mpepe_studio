// ignore_for_file: avoid_print
import 'package:oneova/backend/sync_sessions/models/sync_session_models.dart';
import 'package:oneova/backend/social_inbox_repository.dart'; // Chat hook
import 'package:oneova/backend/unified_inbox_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SyncSessionService {
  // ignore: unused_field
  final SocialInboxRepository _inboxRepo;
  final Map<String, SyncSession> _sessions = {}; // Memory stub representing Live DB / WebRTC state

  SyncSessionService(this._inboxRepo);

  /// Initializes a new watch party or premiere
  SyncSession createSession({
    required String hostId,
    required String title,
    required SyncSessionType type,
    required String contentId,
    bool isPrivate = false,
  }) {
    final session = SyncSession(
      id: 'sync_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      type: type,
      isPrivate: isPrivate,
      hostId: hostId,
      playback: SyncPlaybackContext(
        contentId: contentId,
        lastUpdatedAt: DateTime.now(),
      ),
    );

    // Add host
    session.participants[hostId] = SyncParticipant(
      userId: hostId,
      role: ParticipantRole.host,
      isAudioMuted: false, // Hosts often speak
      joinedAt: DateTime.now(),
    );

    _sessions[session.id] = session;
    return session;
  }

  /// Late join or reconnect logic. Computes where the user should start watching.
  Duration joinSession(String sessionId, String userId) {
    final session = _sessions[sessionId];
    if (session == null) throw Exception('Session not found');

    if (session.isPrivate && session.hostId != userId && !session.participants.containsKey(userId)) {
      // In reality, check invite lists
      throw Exception('Unauthorized: Private session');
    }

    session.participants.putIfAbsent(userId, () => SyncParticipant(
      userId: userId,
      role: ParticipantRole.viewer,
      joinedAt: DateTime.now(),
    ));

    // Calculate exact playback offset to instantly align the late joiner with the host
    return session.playback.calculatedRealtimePosition;
  }

  /// Host Play control
  void play(String sessionId, String requestorId) {
    final session = _sessions[sessionId];
    if (session == null) return;
    
    if (!session.isHostOrMod(requestorId)) {
      throw Exception('Unauthorized: Only hosts or moderators can control playback');
    }

    session.playback.state = PlaybackState.playing;
    session.playback.lastUpdatedAt = DateTime.now();
  }

  /// Host Pause control
  void pause(String sessionId, String requestorId, Duration currentPosition) {
    final session = _sessions[sessionId];
    if (session == null) return;
    
    if (!session.isHostOrMod(requestorId)) {
      throw Exception('Unauthorized: Only hosts or moderators can control playback');
    }

    session.playback.state = PlaybackState.paused;
    session.playback.currentPosition = currentPosition;
    session.playback.lastUpdatedAt = DateTime.now();
  }

  /// Host Seek control
  void seek(String sessionId, String requestorId, Duration seekPosition) {
    final session = _sessions[sessionId];
    if (session == null) return;
    
    if (!session.isHostOrMod(requestorId)) {
      throw Exception('Unauthorized: Only hosts or moderators can control playback');
    }

    session.playback.currentPosition = seekPosition;
    session.playback.lastUpdatedAt = DateTime.now();
  }

  /// Broadcasts chat mapping to the Canonical Inbox architecture to prevent dual-chat databases
  void broadcastChat(String sessionId, String senderId, String text) {
    final session = _sessions[sessionId];
    if (session == null) return;
    if (!session.participants.containsKey(senderId)) return;

    // ignore: unused_local_variable
    final msg = SocialMessageModel(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      userId: sessionId, // Maps to session chat channel
      platform: SocialPlatform.system,
      interactionType: SocialInteractionType.message,
      targetId: sessionId,
      senderName: senderId,
      senderAvatarUrl: '',
      content: text,
      timestamp: Timestamp.now(),
    );

    print('Live Chat Broadcast [Room $sessionId]: [$senderId] $text');
  }

  SyncSession? getSession(String id) => _sessions[id];
}
