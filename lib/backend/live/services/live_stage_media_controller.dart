import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LIVE STAGE MEDIA — real participant video for the Live Studio.
//
// Transport: flutter_webrtc + Firestore signaling, the same stack as
// `backend/calling/providers/webrtc_connection_manager.dart`, scoped to
// live_streams/{streamId}/signaling.
//
// Topology (one-way sessions, no offer glare):
//   • Publishers = host + approved stage guests. They capture camera + mic.
//   • Every client (viewer OR publisher) opens ONE receive-only
//     RTCPeerConnection per publisher. The subscriber sends the offer, the
//     publisher answers with its local tracks.
//
// ⚠ Scale: this is a P2P mesh — each publisher uploads one copy per
// subscriber. Fine for small rooms; large audiences need an SFU. The UI only
// depends on [LiveStageMediaState], so swapping the transport is local to
// this file.
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, dynamic> _kIceConfig = {
  'sdpSemantics': 'unified-plan',
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ],
};

@immutable
class LiveStageMediaState {
  /// Remote publisher video, keyed by publisher uid.
  final Map<String, RTCVideoRenderer> renderers;

  /// Publisher uids whose connection is up and has delivered media.
  final Set<String> connected;

  /// Own camera preview when the current user is on stage.
  final RTCVideoRenderer? localRenderer;
  final bool isPublishing;
  final bool isStartingMedia;
  final bool micMuted;
  final bool cameraOff;

  /// Loudest publisher right now (null = nobody speaking).
  final String? activeSpeakerId;
  final String? error;

  const LiveStageMediaState({
    this.renderers = const {},
    this.connected = const {},
    this.localRenderer,
    this.isPublishing = false,
    this.isStartingMedia = false,
    this.micMuted = false,
    this.cameraOff = false,
    this.activeSpeakerId,
    this.error,
  });

  LiveStageMediaState copyWith({
    Map<String, RTCVideoRenderer>? renderers,
    Set<String>? connected,
    RTCVideoRenderer? localRenderer,
    bool clearLocalRenderer = false,
    bool? isPublishing,
    bool? isStartingMedia,
    bool? micMuted,
    bool? cameraOff,
    String? activeSpeakerId,
    bool clearActiveSpeaker = false,
    String? error,
    bool clearError = false,
  }) {
    return LiveStageMediaState(
      renderers: renderers ?? this.renderers,
      connected: connected ?? this.connected,
      localRenderer:
          clearLocalRenderer ? null : (localRenderer ?? this.localRenderer),
      isPublishing: isPublishing ?? this.isPublishing,
      isStartingMedia: isStartingMedia ?? this.isStartingMedia,
      micMuted: micMuted ?? this.micMuted,
      cameraOff: cameraOff ?? this.cameraOff,
      activeSpeakerId: clearActiveSpeaker
          ? null
          : (activeSpeakerId ?? this.activeSpeakerId),
      error: clearError ? null : (error ?? this.error),
    );
  }

  /// Renderer for any stage member, including the current user.
  RTCVideoRenderer? rendererFor(String uid, String selfUid) =>
      uid == selfUid ? localRenderer : renderers[uid];

  bool hasLiveVideo(String uid, String selfUid) {
    if (uid == selfUid) return isPublishing && !cameraOff && localRenderer != null;
    return connected.contains(uid) && renderers.containsKey(uid);
  }
}

final liveStageMediaProvider = NotifierProvider.autoDispose
    .family<LiveStageMediaController, LiveStageMediaState, String>(
        LiveStageMediaController.new);

class LiveStageMediaController extends Notifier<LiveStageMediaState> {
  LiveStageMediaController(this.streamId);

  final String streamId;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String get _me => FirebaseAuth.instance.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _signaling =>
      _db.collection('live_streams').doc(streamId).collection('signaling');

  // Subscriptions I opened (publisherId → pc) and sessions I serve
  // as a publisher (subscriberId → pc).
  final Map<String, RTCPeerConnection> _subs = {};
  final Map<String, RTCPeerConnection> _pubs = {};
  final Map<RTCPeerConnection, List<RTCIceCandidate>> _pendingIce = {};
  final Set<RTCPeerConnection> _remoteDescSet = {};

  // Private mirrors so teardown never has to read `state` while disposing.
  final Map<String, RTCVideoRenderer> _rendererMirror = {};
  RTCVideoRenderer? _localRendererMirror;

  Set<String> _desiredPublishers = {};
  final Map<String, String> _queuedOffers = {};
  final Map<String, Timer> _connectTimeouts = {};
  MediaStream? _localStream;
  Completer<void>? _localReady;
  StreamSubscription? _signalSub;
  Timer? _statsTimer;
  DateTime _sessionStart = DateTime.now();
  DateTime _lastSpeakAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  @override
  LiveStageMediaState build() {
    _sessionStart = DateTime.now();
    ref.onDispose(_teardown);
    _listenSignaling();
    _statsTimer =
        Timer.periodic(const Duration(milliseconds: 700), (_) => _pollAudioLevels());
    return const LiveStageMediaState();
  }

  // ───────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ───────────────────────────────────────────────────────────────────────

  /// Reconcile connections with the current stage roster. Call whenever the
  /// participants / stream doc change.
  Future<void> syncStage({
    required Set<String> publisherIds,
    required bool selfIsPublisher,
  }) async {
    if (_disposed || _me.isEmpty) return;
    final others = publisherIds.where((id) => id != _me).toSet();
    _desiredPublishers = others;

    if (selfIsPublisher && !state.isPublishing && !state.isStartingMedia) {
      await _startPublishing();
    } else if (!selfIsPublisher && state.isPublishing) {
      await _stopPublishing();
    }

    for (final id in _subs.keys.toList()) {
      if (!others.contains(id)) await _closeSubscription(id);
    }
    for (final id in others) {
      if (!_subs.containsKey(id)) await _subscribe(id);
    }
  }

  void toggleMic() {
    final tracks = _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    final muted = !state.micMuted;
    for (final t in tracks) {
      t.enabled = !muted;
    }
    _set(state.copyWith(micMuted: muted));
  }

  void toggleCamera() {
    final tracks = _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    final off = !state.cameraOff;
    for (final t in tracks) {
      t.enabled = !off;
    }
    _set(state.copyWith(cameraOff: off));
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  // ───────────────────────────────────────────────────────────────────────
  // PUBLISHING (host / approved guests)
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _startPublishing() async {
    _set(state.copyWith(isStartingMedia: true, clearError: true));
    _localReady = Completer<void>();
    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
      });
      if (_disposed) {
        await stream.dispose();
        return;
      }
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      renderer.srcObject = stream;
      _localStream = stream;
      _localRendererMirror = renderer;
      _set(state.copyWith(
        localRenderer: renderer,
        isPublishing: true,
        isStartingMedia: false,
        micMuted: false,
        cameraOff: false,
      ));
      _localReady?.complete();
      final queued = Map.of(_queuedOffers);
      _queuedOffers.clear();
      for (final e in queued.entries) {
        unawaited(_answerOffer(e.key, e.value).catchError((Object err) {
          debugPrint('[LiveStageMedia] queued answer failed: $err');
        }));
      }
    } catch (e) {
      debugPrint('[LiveStageMedia] getUserMedia failed: $e');
      _localReady?.completeError(e);
      _localReady = null;
      _set(state.copyWith(
        isStartingMedia: false,
        error: 'Camera or microphone permission is required to go on stage.',
      ));
    }
  }

  Future<void> _stopPublishing() async {
    _queuedOffers.clear();
    for (final id in _pubs.keys.toList()) {
      await _closePublisherSession(id);
    }
    final local = _localRendererMirror;
    _localRendererMirror = null;
    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    _localStream = null;
    _localReady = null;
    _set(state.copyWith(isPublishing: false, clearLocalRenderer: true));
    local?.srcObject = null;
    await local?.dispose();
  }

  Future<void> _answerOffer(String subscriberId, String sdp) async {
    final ready = _localReady;
    if (ready == null) {
      // Our own roster update may not have landed yet: keep the latest offer
      // per subscriber and answer it as soon as publishing starts.
      _queuedOffers[subscriberId] = sdp;
      return;
    }
    try {
      await ready.future;
    } catch (_) {
      return;
    }
    if (_disposed || _localStream == null) return;

    await _closePublisherSession(subscriberId); // replace stale session
    final pc = await createPeerConnection(_kIceConfig);
    _pubs[subscriberId] = pc;
    final sessionId = '${subscriberId}__$_me';

    pc.onIceCandidate = (c) => _sendCandidate(c, to: subscriberId, sessionId: sessionId, side: 'pub');
    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _closePublisherSession(subscriberId);
      }
    };

    // Order matters: remote offer first so addTrack reuses its transceivers.
    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    await _markRemoteDescSet(pc);
    for (final track in _localStream!.getTracks()) {
      await pc.addTrack(track, _localStream!);
    }
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await _signaling.add({
      'type': 'answer',
      'from': _me,
      'to': subscriberId,
      'sessionId': sessionId,
      'sdp': answer.sdp,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _closePublisherSession(String subscriberId) async {
    final pc = _pubs.remove(subscriberId);
    if (pc == null) return;
    _pendingIce.remove(pc);
    _remoteDescSet.remove(pc);
    await pc.close();
  }

  // ───────────────────────────────────────────────────────────────────────
  // SUBSCRIBING (everyone)
  // ───────────────────────────────────────────────────────────────────────

  final Set<String> _subscribing = {};

  Future<void> _subscribe(String publisherId) async {
    if (_subs.containsKey(publisherId) || !_subscribing.add(publisherId)) return;
    try {
      await _openSubscription(publisherId);
    } catch (e) {
      debugPrint('[LiveStageMedia] subscribe($publisherId) failed: $e');
    } finally {
      _subscribing.remove(publisherId);
    }
  }

  Future<void> _openSubscription(String publisherId) async {
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    final pc = await createPeerConnection(_kIceConfig);
    if (_disposed || !_desiredPublishers.contains(publisherId)) {
      await pc.close();
      await renderer.dispose();
      return;
    }
    _subs[publisherId] = pc;
    final sessionId = '${_me}__$publisherId';

    await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );

    pc.onTrack = (RTCTrackEvent e) {
      if (e.streams.isEmpty) return;
      renderer.srcObject = e.streams.first;
      _set(state.copyWith(connected: {...state.connected, publisherId}));
    };
    pc.onIceCandidate = (c) => _sendCandidate(c, to: publisherId, sessionId: sessionId, side: 'sub');
    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _closeSubscription(publisherId).then((_) {
          // Retry once the publisher is still on stage.
          Future.delayed(const Duration(seconds: 2), () {
            if (!_disposed &&
                _desiredPublishers.contains(publisherId) &&
                !_subs.containsKey(publisherId)) {
              _subscribe(publisherId);
            }
          });
        });
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _set(state.copyWith(connected: {...state.connected}..remove(publisherId)));
      }
    };

    _rendererMirror[publisherId] = renderer;
    _set(state.copyWith(renderers: {...state.renderers, publisherId: renderer}));

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await _signaling.add({
      'type': 'offer',
      'from': _me,
      'to': publisherId,
      'sessionId': sessionId,
      'sdp': offer.sdp,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // If the publisher never answers (offline, or its client was not ready),
    // tear down and re-offer while they are still on stage.
    _connectTimeouts[publisherId]?.cancel();
    _connectTimeouts[publisherId] = Timer(const Duration(seconds: 12), () {
      if (_disposed ||
          !identical(_subs[publisherId], pc) ||
          state.connected.contains(publisherId)) {
        return;
      }
      _closeSubscription(publisherId).then((_) {
        if (!_disposed && _desiredPublishers.contains(publisherId)) {
          _subscribe(publisherId);
        }
      });
    });
  }

  Future<void> _closeSubscription(String publisherId) async {
    _connectTimeouts.remove(publisherId)?.cancel();
    final pc = _subs.remove(publisherId);
    final renderer = _rendererMirror.remove(publisherId);
    _set(state.copyWith(
      renderers: {...state.renderers}..remove(publisherId),
      connected: {...state.connected}..remove(publisherId),
      clearActiveSpeaker: state.activeSpeakerId == publisherId,
    ));
    if (pc != null) {
      _pendingIce.remove(pc);
      _remoteDescSet.remove(pc);
      await pc.close();
    }
    if (renderer != null) {
      renderer.srcObject = null;
      await renderer.dispose();
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // SIGNALING
  // ───────────────────────────────────────────────────────────────────────

  void _listenSignaling() {
    final me = _me;
    if (me.isEmpty) return;
    _signalSub = _signaling.where('to', isEqualTo: me).snapshots().listen(
      (snap) async {
        for (final change in snap.docChanges) {
          if (change.type != DocumentChangeType.added) continue;
          final data = change.doc.data();
          if (data == null) continue;

          // Drop leftovers from earlier sessions.
          final ts = data['createdAt'];
          if (ts is Timestamp &&
              ts.toDate().isBefore(_sessionStart.subtract(const Duration(seconds: 30)))) {
            unawaited(change.doc.reference.delete());
            continue;
          }

          final from = data['from'] as String? ?? '';
          try {
            switch (data['type']) {
              case 'offer':
                await _answerOffer(from, data['sdp'] as String);
                break;
              case 'answer':
                final pc = _subs[from];
                if (pc != null) {
                  await pc.setRemoteDescription(
                      RTCSessionDescription(data['sdp'] as String, 'answer'));
                  await _markRemoteDescSet(pc);
                }
                break;
              case 'candidate':
                // side 'sub' = sent by a subscriber → my publisher session.
                final pc = data['side'] == 'sub' ? _pubs[from] : _subs[from];
                if (pc != null) {
                  await _addCandidate(
                    pc,
                    RTCIceCandidate(
                      data['candidate'] as String?,
                      data['sdpMid'] as String?,
                      (data['sdpMLineIndex'] as num?)?.toInt(),
                    ),
                  );
                }
                break;
            }
          } catch (e) {
            debugPrint('[LiveStageMedia] signaling error: $e');
          }
          unawaited(change.doc.reference.delete());
        }
      },
      onError: (e) => debugPrint('[LiveStageMedia] signaling stream error: $e'),
    );
  }

  Future<void> _sendCandidate(
    RTCIceCandidate c, {
    required String to,
    required String sessionId,
    required String side,
  }) async {
    if (c.candidate == null || _disposed) return;
    await _signaling.add({
      'type': 'candidate',
      'from': _me,
      'to': to,
      'sessionId': sessionId,
      'side': side,
      'candidate': c.candidate,
      'sdpMid': c.sdpMid,
      'sdpMLineIndex': c.sdpMLineIndex,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _addCandidate(RTCPeerConnection pc, RTCIceCandidate c) async {
    if (_remoteDescSet.contains(pc)) {
      await pc.addCandidate(c);
    } else {
      (_pendingIce[pc] ??= []).add(c);
    }
  }

  Future<void> _markRemoteDescSet(RTCPeerConnection pc) async {
    _remoteDescSet.add(pc);
    final pending = _pendingIce.remove(pc) ?? const [];
    for (final c in pending) {
      await pc.addCandidate(c);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // ACTIVE SPEAKER (audio levels from getStats)
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _pollAudioLevels() async {
    if (_disposed) return;
    String? loudest;
    double best = 0.04; // speaking threshold

    for (final entry in _subs.entries) {
      final level = await _readLevel(entry.value, 'inbound-rtp');
      if (level > best) {
        best = level;
        loudest = entry.key;
      }
    }
    if (state.isPublishing && !state.micMuted && _pubs.isNotEmpty) {
      final level = await _readLevel(_pubs.values.first, 'media-source');
      if (level > best) loudest = _me;
    }

    if (_disposed) return;
    final now = DateTime.now();
    if (loudest != null) {
      _lastSpeakAt = now;
      if (loudest != state.activeSpeakerId) {
        _set(state.copyWith(activeSpeakerId: loudest));
      }
    } else if (state.activeSpeakerId != null &&
        now.difference(_lastSpeakAt) > const Duration(milliseconds: 1500)) {
      _set(state.copyWith(clearActiveSpeaker: true));
    }
  }

  Future<double> _readLevel(RTCPeerConnection pc, String reportType) async {
    try {
      final reports = await pc.getStats();
      for (final r in reports) {
        if (r.type != reportType) continue;
        final kind = r.values['kind'] ?? r.values['mediaType'];
        if (kind != 'audio') continue;
        final level = r.values['audioLevel'];
        if (level is num) return level.toDouble();
      }
    } catch (_) {}
    return 0;
  }

  // ───────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ───────────────────────────────────────────────────────────────────────

  void _set(LiveStageMediaState next) {
    if (_disposed) return;
    state = next;
  }

  Future<void> _teardown() async {
    _disposed = true;
    _statsTimer?.cancel();
    for (final t in _connectTimeouts.values) {
      t.cancel();
    }
    _connectTimeouts.clear();
    _queuedOffers.clear();
    await _signalSub?.cancel();
    final renderers = _rendererMirror.values.toList();
    _rendererMirror.clear();
    final local = _localRendererMirror;
    _localRendererMirror = null;
    for (final pc in [..._subs.values, ..._pubs.values]) {
      await pc.close();
    }
    _subs.clear();
    _pubs.clear();
    _pendingIce.clear();
    _remoteDescSet.clear();
    for (final r in renderers) {
      r.srcObject = null;
      await r.dispose();
    }
    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    _localStream = null;
    local?.srcObject = null;
    await local?.dispose();
  }
}
