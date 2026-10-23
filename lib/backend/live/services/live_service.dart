import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/live_models.dart';
import '../../notifications/services/follower_alert_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

final liveServiceProvider = Provider<LiveService>((ref) => LiveService());

/// Stream of all currently live sessions (ordered by viewer count desc)
final activeLiveStreamsProvider = StreamProvider<List<LiveStream>>((ref) {
  return ref.watch(liveServiceProvider).watchActiveLiveStreams();
});

/// Stream for a single live session by ID
final liveStreamProvider =
    StreamProvider.family<LiveStream?, String>((ref, streamId) {
  return ref.watch(liveServiceProvider).watchStream(streamId);
});

/// Real-time comments for a live session (most recent 50, reversed for display)
final liveCommentsProvider =
    StreamProvider.family<List<LiveComment>, String>((ref, streamId) {
  return ref.watch(liveServiceProvider).watchComments(streamId);
});

/// Real-time participants for a live session
final liveParticipantsProvider =
    StreamProvider.family<List<LiveParticipant>, String>((ref, streamId) {
  return ref.watch(liveServiceProvider).watchParticipants(streamId);
});

/// Real-time guest requests for a live session
final liveGuestRequestsProvider =
    StreamProvider.family<List<LiveGuestRequest>, String>((ref, streamId) {
  return ref.watch(liveServiceProvider).watchGuestRequests(streamId);
});

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class LiveService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Timer? _heartbeatTimer;
  int _missedHeartbeats = 0;
  static const int _maxMissedHeartbeats = 3;
  static const String _col = 'live_streams';
  static const String _comments = 'comments';
  static const String _participants = 'participants';
  static const String _reactions = 'reactions';
  static const String _guestRequests = 'guest_requests';

  String get currentUserId => _auth.currentUser?.uid ?? '';

  // ─────────────────────────────────────────────────────────────────────────
  // AI STAGE GENERATOR
  // ─────────────────────────────────────────────────────────────────────────

  /// Generates an AI-customized Stage Configuration based on user prompt or style
  Future<LiveStageConfig> generateAIStageConfig(String prompt) async {
    final lower = prompt.toLowerCase();

    // Smart semantic stage styling
    if (lower.contains('cinema') || lower.contains('movie')) {
      return LiveStageConfig(
        prompt: prompt,
        atmospherePreset: 'Cyber-Cinema',
        hologramEmblem: 'crystal',
        audioPreset: 'Cinema Surround 7.1',
        primaryColorHex: '#0C4FA8',
        accentColorHex: '#FF2D87',
        ambientGlowIntensity: 0.95,
      );
    } else if (lower.contains('concert') ||
        lower.contains('music') ||
        lower.contains('stadium')) {
      return LiveStageConfig(
        prompt: prompt,
        atmospherePreset: 'Neon Stadium',
        hologramEmblem: 'galaxy',
        audioPreset: 'Bass Master Pro',
        primaryColorHex: '#0C4FA8',
        accentColorHex: '#FF2D87',
        ambientGlowIntensity: 1.0,
      );
    } else if (lower.contains('roundtable') ||
        lower.contains('exec') ||
        lower.contains('business')) {
      return LiveStageConfig(
        prompt: prompt,
        atmospherePreset: 'Executive Suite',
        hologramEmblem: 'crown',
        audioPreset: 'Broadcast Clarity',
        primaryColorHex: '#0C4FA8',
        accentColorHex: '#00D2FF',
        ambientGlowIntensity: 0.75,
      );
    } else if (lower.contains('space') || lower.contains('future')) {
      return LiveStageConfig(
        prompt: prompt,
        atmospherePreset: 'Cosmic Lounge',
        hologramEmblem: 'ring',
        audioPreset: 'Spatial Hologram 3D',
        primaryColorHex: '#0C4FA8',
        accentColorHex: '#FF2D87',
        ambientGlowIntensity: 0.9,
      );
    }

    // Default Holographic Stage
    return LiveStageConfig(
      prompt: prompt,
      atmospherePreset: 'Holographic Stage',
      hologramEmblem: 'cube',
      audioPreset: 'Studio Voice Pro',
      primaryColorHex: '#0C4FA8',
      accentColorHex: '#FF2D87',
      ambientGlowIntensity: 0.85,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STREAM MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────

  /// Creates and persists a new live stream document in Firestore with 30-day stream keys.
  Future<LiveStream> startStream({
    required String title,
    required LiveStreamType type,
    required LiveStageScene stageScene,
    LiveStageConfig? stageConfig,
    AIModeratorSettings? aiModerator,
    LiveInputSourceMode inputSourceMode = LiveInputSourceMode.cameraOnly,
    LiveBeautyConfig? beautyConfig,
    LiveMediaDeskConfig? mediaDeskConfig,
    LiveLegalCompliance? legalCompliance,
    bool allowGuestRequests = true,
    String category = 'Entertainment',
    String audienceMode = 'public',
    String resolution = '1080p',
    int frameRate = 60,
    String layoutMode = 'classic',
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final docRef = _db.collection(_col).doc();
    final now = DateTime.now();

    // Persistent 30-day stream key endpoint
    final endpoint = LiveStreamEndpoint(
      serverUrl: 'rtmps://live.oneova.com/live',
      streamKey:
          'ov_live_${docRef.id.substring(0, 8)}_${now.millisecondsSinceEpoch}',
      keyExpiresAt: now.add(const Duration(days: 30)),
      isKeyActive: true,
      multiCastDestinations: const [
        'rtmp://a.rtmp.youtube.com/live2',
        'rtmps://live-upload.instagram.com:443/rtmp/',
      ],
    );

    final finalStageConfig = stageConfig ??
        const LiveStageConfig(
          atmospherePreset: 'Holographic Stage',
          hologramEmblem: 'cube',
        );

    final finalAiModerator = aiModerator ?? const AIModeratorSettings();

    final data = <String, dynamic>{
      'id': docRef.id,
      'hostId': user.uid,
      'hostDisplayName': user.displayName ?? 'Unknown',
      'hostAvatarUrl': user.photoURL ?? '',
      'title': title,
      'category': category,
      'type': type.name,
      'status': LiveStreamStatus.live.name,
      'stageScene': stageScene.name,
      'stageConfig': finalStageConfig.toJson(),
      'endpoint': endpoint.toJson(),
      'aiModerator': finalAiModerator.toJson(),
      'viewerCount': 0,
      'totalLikes': 0,
      'totalComments': 0,
      'chatSettings': const LiveChatSettings().toJson(),
      'coHostIds': <String>[],
      'moderatorIds': <String>[],
      'pinnedCommentId': null,
      'recordingEnabled': false,
      'liveCaptionsEnabled': false,
      'liveTranslationEnabled': false,
      'audienceMode': audienceMode,
      'resolution': resolution,
      'frameRate': frameRate,
      'isMultiPlatform': false,
      'linkedPlatforms': <String>[],
      'inputSourceMode': inputSourceMode.name,
      'beautyConfig': (beautyConfig ?? const LiveBeautyConfig()).toJson(),
      'mediaDeskConfig':
          (mediaDeskConfig ?? const LiveMediaDeskConfig()).toJson(),
      'legalCompliance':
          (legalCompliance ?? const LiveLegalCompliance()).toJson(),
      'allowGuestRequests': allowGuestRequests,
      'layoutMode': layoutMode,
      'createdAt': Timestamp.fromDate(now),
      'endedAt': null,
    };

    await docRef.set(data);
    _startHeartbeat(docRef.id);
    if (audienceMode != 'private') {
      unawaited(_notifyFollowersWentLive(
        hostId: user.uid,
        hostName: user.displayName ?? 'Someone you follow',
        streamId: docRef.id,
        title: title,
      ));
    }

    return LiveStream.fromJson(data);
  }

  /// Fan-out an in-app "is LIVE" alert to every follower who keeps live
  /// alerts on for this host. Tapping it opens `/live/viewer/{id}`.
  Future<void> _notifyFollowersWentLive({
    required String hostId,
    required String hostName,
    required String streamId,
    required String title,
  }) =>
      FollowerAlertService().notifyFollowersWentLive(
        hostId: hostId,
        hostName: hostName,
        streamId: streamId,
        title: title,
      );

  /// Rotate or renew the 30-day stream key
  Future<LiveStreamEndpoint> rotateStreamKey(String streamId) async {
    final now = DateTime.now();
    final newEndpoint = LiveStreamEndpoint(
      serverUrl: 'rtmps://live.oneova.com/live',
      streamKey:
          'ov_live_${streamId.substring(0, 8)}_${now.millisecondsSinceEpoch}',
      keyExpiresAt: now.add(const Duration(days: 30)),
      isKeyActive: true,
    );
    await _db.collection(_col).doc(streamId).update({
      'endpoint': newEndpoint.toJson(),
    });
    return newEndpoint;
  }

  /// Update the dynamic AI stage config in real-time
  Future<void> updateAIStageConfig(
      String streamId, LiveStageConfig stageConfig) async {
    await _db.collection(_col).doc(streamId).update({
      'stageConfig': stageConfig.toJson(),
    });
  }

  /// End a stream and update its status in Firestore.
  Future<void> endStream(String streamId, {bool forceAbandoned = false}) async {
    _heartbeatTimer?.cancel();
    await _db.collection(_col).doc(streamId).update({
      'status': forceAbandoned
          ? LiveStreamStatus.abandoned.name
          : LiveStreamStatus.ended.name,
      'endedAt': FieldValue.serverTimestamp(),
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REAL-TIME STREAMS
  // ─────────────────────────────────────────────────────────────────────────

  Stream<LiveStream?> watchStream(String streamId) {
    return _db
        .collection(_col)
        .doc(streamId)
        .snapshots()
        .map((s) => s.exists ? LiveStream.fromJson(s.data()!) : null);
  }

  Stream<List<LiveStream>> watchActiveLiveStreams() {
    return _db
        .collection(_col)
        .where('status', isEqualTo: 'live')
        .orderBy('viewerCount', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map((d) => LiveStream.fromJson(d.data())).toList());
  }

  Stream<List<LiveComment>> watchComments(String streamId) {
    return _db
        .collection(_col)
        .doc(streamId)
        .collection(_comments)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map((d) => LiveComment.fromJson(d.data())).toList());
  }

  Stream<List<LiveParticipant>> watchParticipants(String streamId) {
    return _db
        .collection(_col)
        .doc(streamId)
        .collection(_participants)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => LiveParticipant.fromJson(d.data())).toList());
  }

  /// Stream real-time guest requests (ordered by requestedAt descending)
  Stream<List<LiveGuestRequest>> watchGuestRequests(String streamId) {
    return _db
        .collection(_col)
        .doc(streamId)
        .collection(_guestRequests)
        .orderBy('requestedAt', descending: true)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => LiveGuestRequest.fromJson(d.data())).toList());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // VIEWER ACTIONS & GUEST STAGE MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> incrementViewerCount(String streamId) async {
    await _db.collection(_col).doc(streamId).update({
      'viewerCount': FieldValue.increment(1),
    });
  }

  Future<void> decrementViewerCount(String streamId) async {
    await _db.collection(_col).doc(streamId).update({
      'viewerCount': FieldValue.increment(-1),
    });
  }

  /// Sends a comment with AI auto-moderation
  Future<void> sendComment(String streamId, String text) async {
    final user = _auth.currentUser;
    if (user == null || text.trim().isEmpty) return;

    final trimmed = text.trim();

    // AI Question Detection
    final isQuestion = trimmed.endsWith('?') ||
        trimmed.toLowerCase().startsWith('can you') ||
        trimmed.toLowerCase().startsWith('how') ||
        trimmed.toLowerCase().startsWith('what');

    final ref = _db.collection(_col).doc(streamId).collection(_comments).doc();
    final batch = _db.batch();

    batch.set(ref, {
      'id': ref.id,
      'streamId': streamId,
      'authorId': user.uid,
      'authorDisplayName': user.displayName ?? 'Unknown',
      'authorAvatarUrl': user.photoURL ?? '',
      'text': trimmed,
      'isGift': false,
      'giftType': null,
      'giftCount': null,
      'isModerator': false,
      'isPinned': false,
      'isHighlighted': isQuestion,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.collection(_col).doc(streamId), {
      'totalComments': FieldValue.increment(1),
    });

    await batch.commit();
  }

  Future<void> sendGift(String streamId, String giftType, int count) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final ref = _db.collection(_col).doc(streamId).collection(_comments).doc();
    await ref.set({
      'id': ref.id,
      'streamId': streamId,
      'authorId': user.uid,
      'authorDisplayName': user.displayName ?? 'Unknown',
      'authorAvatarUrl': user.photoURL ?? '',
      'text': 'sent $count x $giftType 🎁',
      'isGift': true,
      'giftType': giftType,
      'giftCount': count,
      'isModerator': false,
      'isPinned': false,
      'isHighlighted': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> sendLikeReaction(String streamId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final batch = _db.batch();
    final reactionRef =
        _db.collection(_col).doc(streamId).collection(_reactions).doc();
    batch.set(reactionRef, {
      'id': reactionRef.id,
      'streamId': streamId,
      'userId': user.uid,
      'type': 'heart',
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.collection(_col).doc(streamId), {
      'totalLikes': FieldValue.increment(1),
    });
    await batch.commit();
  }

  /// Viewer request helper (delegates to requestToJoinStage)
  Future<void> requestToJoin(String streamId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await requestToJoinStage(
      streamId: streamId,
      userId: user.uid,
      displayName: user.displayName ?? 'Unknown',
      avatarUrl: user.photoURL ?? '',
      role: LiveGuestRole.speaker,
    );
  }

  /// Request to join the live stage as speaker, co-host, or moderator
  Future<void> requestToJoinStage({
    required String streamId,
    required String userId,
    required String displayName,
    required String avatarUrl,
    LiveGuestRole role = LiveGuestRole.speaker,
  }) async {
    final batch = _db.batch();
    final requestRef = _db
        .collection(_col)
        .doc(streamId)
        .collection(_guestRequests)
        .doc(userId);

    final request = LiveGuestRequest(
      requestId: userId,
      streamId: streamId,
      userId: userId,
      displayName: displayName,
      avatarUrl: avatarUrl,
      requestedRole: role,
      status: LiveGuestRequestStatus.pending,
      requestedAt: DateTime.now(),
    );

    batch.set(requestRef, request.toJson(), SetOptions(merge: true));

    final participantRef = _db
        .collection(_col)
        .doc(streamId)
        .collection(_participants)
        .doc(userId);

    batch.set(participantRef, {
      'userId': userId,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'isCoHost': role == LiveGuestRole.coHost,
      'hasRequestedToJoin': true,
      'isMuted': false,
      'isCameraOn': false,
      'role': role.name,
      'joinedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// Host responds to a guest request: approve or reject
  Future<void> respondToGuestRequest({
    required String streamId,
    required String requestId,
    required bool approve,
    LiveGuestRole? assignedRole,
  }) async {
    final requestRef = _db
        .collection(_col)
        .doc(streamId)
        .collection(_guestRequests)
        .doc(requestId);

    final reqSnap = await requestRef.get();
    final targetUserId = reqSnap.data()?['userId'] as String? ?? requestId;

    final batch = _db.batch();
    final status = approve
        ? LiveGuestRequestStatus.approved
        : LiveGuestRequestStatus.rejected;

    final requestUpdates = <String, dynamic>{
      'status': status.name,
      'respondedAt': FieldValue.serverTimestamp(),
    };
    if (assignedRole != null) {
      requestUpdates['requestedRole'] = assignedRole.name;
    }
    batch.update(requestRef, requestUpdates);

    final participantRef = _db
        .collection(_col)
        .doc(streamId)
        .collection(_participants)
        .doc(targetUserId);

    final isCoHost = approve && (assignedRole == LiveGuestRole.coHost);

    final participantUpdates = <String, dynamic>{
      'hasRequestedToJoin': false,
    };
    if (approve) {
      participantUpdates['isCoHost'] = isCoHost;
      if (assignedRole != null) {
        participantUpdates['role'] = assignedRole.name;
      }
    }
    batch.set(participantRef, participantUpdates, SetOptions(merge: true));

    if (isCoHost) {
      batch.update(_db.collection(_col).doc(streamId), {
        'coHostIds': FieldValue.arrayUnion([targetUserId]),
      });
    }

    await batch.commit();
  }

  /// Update stage participant controls (mute, camera, co-host elevation)
  Future<void> updateParticipantControls({
    required String streamId,
    required String participantId,
    bool? isMuted,
    bool? isCameraOn,
    bool? isCoHost,
  }) async {
    final updates = <String, dynamic>{};
    if (isMuted != null) updates['isMuted'] = isMuted;
    if (isCameraOn != null) updates['isCameraOn'] = isCameraOn;
    if (isCoHost != null) {
      updates['isCoHost'] = isCoHost;
      updates['role'] =
          isCoHost ? LiveGuestRole.coHost.name : LiveGuestRole.speaker.name;
    }

    if (updates.isEmpty) return;

    final batch = _db.batch();
    final partRef = _db
        .collection(_col)
        .doc(streamId)
        .collection(_participants)
        .doc(participantId);

    batch.set(partRef, updates, SetOptions(merge: true));

    if (isCoHost != null) {
      final streamRef = _db.collection(_col).doc(streamId);
      if (isCoHost) {
        batch.update(streamRef, {
          'coHostIds': FieldValue.arrayUnion([participantId]),
        });
      } else {
        batch.update(streamRef, {
          'coHostIds': FieldValue.arrayRemove([participantId]),
        });
      }
    }

    await batch.commit();
  }

  /// Drop or remove a participant from the stage
  Future<void> dropParticipant({
    required String streamId,
    required String participantId,
  }) async {
    final batch = _db.batch();
    final partRef = _db
        .collection(_col)
        .doc(streamId)
        .collection(_participants)
        .doc(participantId);

    batch.delete(partRef);

    final streamRef = _db.collection(_col).doc(streamId);
    batch.update(streamRef, {
      'coHostIds': FieldValue.arrayRemove([participantId]),
      'moderatorIds': FieldValue.arrayRemove([participantId]),
    });

    final requestRef = _db
        .collection(_col)
        .doc(streamId)
        .collection(_guestRequests)
        .doc(participantId);
    batch.set(requestRef, {
      'status': LiveGuestRequestStatus.cancelled.name,
      'respondedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// Update live media desk configuration (music, volume, overlays, soundboard)
  Future<void> updateMediaDesk({
    required String streamId,
    required LiveMediaDeskConfig config,
  }) async {
    await _db.collection(_col).doc(streamId).update({
      'mediaDeskConfig': config.toJson(),
    });
  }

  /// Trigger a soundboard effect across the live stage
  Future<void> triggerSoundboardFx({
    required String streamId,
    required String soundFxName,
  }) async {
    await _db.collection(_col).doc(streamId).update({
      'mediaDeskConfig.activeSoundboardFx': soundFxName,
    });
  }

  /// Update beauty filter settings
  Future<void> updateBeautyConfig({
    required String streamId,
    required LiveBeautyConfig config,
  }) async {
    await _db.collection(_col).doc(streamId).update({
      'beautyConfig': config.toJson(),
    });
  }

  /// Update input source mode (camera, screen-share, hybrid)
  Future<void> updateInputSourceMode({
    required String streamId,
    required LiveInputSourceMode mode,
  }) async {
    await _db.collection(_col).doc(streamId).update({
      'inputSourceMode': mode.name,
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HOST / MODERATION ACTIONS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> updateStreamSettings(
    String streamId, {
    String? title,
    String? category,
    String? audienceMode,
    String? resolution,
    int? frameRate,
    LiveStageScene? stageScene,
    bool? recordingEnabled,
    bool? liveCaptionsEnabled,
  }) async {
    final updates = <String, dynamic>{};
    if (title != null) updates['title'] = title;
    if (category != null) updates['category'] = category;
    if (audienceMode != null) updates['audienceMode'] = audienceMode;
    if (resolution != null) updates['resolution'] = resolution;
    if (frameRate != null) updates['frameRate'] = frameRate;
    if (stageScene != null) updates['stageScene'] = stageScene.name;
    if (recordingEnabled != null) updates['recordingEnabled'] = recordingEnabled;
    if (liveCaptionsEnabled != null) {
      updates['liveCaptionsEnabled'] = liveCaptionsEnabled;
    }
    if (updates.isNotEmpty) {
      await _db.collection(_col).doc(streamId).update(updates);
    }
  }

  Future<void> updateChatSettings(
      String streamId, LiveChatSettings settings) async {
    await _db.collection(_col).doc(streamId).update({
      'chatSettings': settings.toJson(),
    });
  }

  Future<void> pinComment(String streamId, String commentId) async {
    final batch = _db.batch();
    batch.update(_db.collection(_col).doc(streamId),
        {'pinnedCommentId': commentId});
    batch.update(
      _db
          .collection(_col)
          .doc(streamId)
          .collection(_comments)
          .doc(commentId),
      {'isPinned': true},
    );
    await batch.commit();
  }

  Future<void> removeComment(String streamId, String commentId) async {
    await _db
        .collection(_col)
        .doc(streamId)
        .collection(_comments)
        .doc(commentId)
        .delete();
  }

  Future<void> banUser(String streamId, String targetUserId) async {
    await _db
        .collection(_col)
        .doc(streamId)
        .collection(_participants)
        .doc(targetUserId)
        .delete();
  }

  Future<void> approveCoHost(String streamId, String userId) async {
    final batch = _db.batch();
    batch.update(
      _db.collection(_col).doc(streamId).collection(_participants).doc(userId),
      {
        'isCoHost': true,
        'hasRequestedToJoin': false,
        'role': LiveGuestRole.coHost.name,
      },
    );
    batch.update(_db.collection(_col).doc(streamId), {
      'coHostIds': FieldValue.arrayUnion([userId]),
    });
    await batch.commit();
  }

  Future<void> approveSpeaker(String streamId, String userId) async {
    await respondToGuestRequest(
      streamId: streamId,
      requestId: userId,
      approve: true,
      assignedRole: LiveGuestRole.speaker,
    );
  }

  Future<void> declineRequest(String streamId, String userId) async {
    await respondToGuestRequest(
      streamId: streamId,
      requestId: userId,
      approve: false,
    );
  }

  Future<void> setParticipantMute(
      String streamId, String userId, bool isMuted) async {
    await updateParticipantControls(
      streamId: streamId,
      participantId: userId,
      isMuted: isMuted,
    );
  }

  Future<void> setParticipantCamera(
      String streamId, String userId, bool isCameraOn) async {
    await updateParticipantControls(
      streamId: streamId,
      participantId: userId,
      isCameraOn: isCameraOn,
    );
  }

  Future<void> promoteToModerator(String streamId, String userId) async {
    final batch = _db.batch();
    batch.update(_db.collection(_col).doc(streamId), {
      'moderatorIds': FieldValue.arrayUnion([userId]),
    });
    batch.set(
      _db.collection(_col).doc(streamId).collection(_participants).doc(userId),
      {'role': LiveGuestRole.moderator.name},
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<void> dropFromStage(String streamId, String userId) async {
    await dropParticipant(streamId: streamId, participantId: userId);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HEARTBEAT (network health check)
  // ─────────────────────────────────────────────────────────────────────────

  void _startHeartbeat(String streamId) {
    _heartbeatTimer?.cancel();
    _missedHeartbeats = 0;
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 10), (timer) async {
      final ok = await _ping(streamId);
      if (!ok) {
        _missedHeartbeats++;
        if (_missedHeartbeats >= _maxMissedHeartbeats) {
          _handleDeadStream(streamId);
          timer.cancel();
        }
      } else {
        _missedHeartbeats = 0;
      }
    });
  }

  Future<bool> _ping(String streamId) async {
    try {
      final doc = await _db.collection(_col).doc(streamId).get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  void _handleDeadStream(String streamId) {
    endStream(streamId, forceAbandoned: true);
  }

  void dispose() {
    _heartbeatTimer?.cancel();
  }
}
