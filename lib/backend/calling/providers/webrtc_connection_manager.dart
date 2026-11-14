import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../security/e2e_encryption_service.dart';
import '../services/call_ice_config.dart';
import 'call_media_service.dart';

/// A message from another person in the call over the call's data channel
/// (DTLS-encrypted end to end between the two phones; no server reads it).
class CallDataMessage {
  final String from;
  final String? text;
  final Uint8List? bytes;
  const CallDataMessage(this.from, {this.text, this.bytes});
}

/// Link quality of one peer, shown as a small badge in the call UI.
enum PeerLinkState { connecting, connected, reconnecting, failed }

/// Network quality to one peer, from round-trip time and packet loss.
enum CallQuality { unknown, good, fair, poor }

class PeerState {
  final String remoteUserId;
  final RTCPeerConnection connection;
  final RTCVideoRenderer renderer;
  final PeerLinkState link;
  final bool isOfferer;
  final bool hasRemoteVideo;
  final int videoRevision;

  /// Audio/video frames to this peer are AES-GCM encrypted with a key derived
  /// from both users' Oneova Shield identity keys, on top of DTLS-SRTP.
  final bool frameEncrypted;
  final CallQuality quality;

  const PeerState({
    required this.remoteUserId,
    required this.connection,
    required this.renderer,
    required this.isOfferer,
    this.link = PeerLinkState.connecting,
    this.hasRemoteVideo = false,
    this.videoRevision = 0,
    this.frameEncrypted = false,
    this.quality = CallQuality.unknown,
  });

  bool get isConnected => link == PeerLinkState.connected;

  PeerState copyWith({
    PeerLinkState? link,
    bool? hasRemoteVideo,
    int? videoRevision,
    bool? frameEncrypted,
    CallQuality? quality,
  }) =>
      PeerState(
        remoteUserId: remoteUserId,
        connection: connection,
        renderer: renderer,
        isOfferer: isOfferer,
        link: link ?? this.link,
        hasRemoteVideo: hasRemoteVideo ?? this.hasRemoteVideo,
        videoRevision: videoRevision ?? this.videoRevision,
        frameEncrypted: frameEncrypted ?? this.frameEncrypted,
        quality: quality ?? this.quality,
      );
}

class WebRTCMeshState {
  final Map<String, PeerState> peers;
  const WebRTCMeshState({this.peers = const {}});

  bool get anyConnected => peers.values.any((p) => p.isConnected);
  bool get anyReconnecting => peers.values.any((p) => p.link == PeerLinkState.reconnecting);

  /// Every connected peer has frame encryption on.
  bool get allFrameEncrypted =>
      peers.isNotEmpty && peers.values.every((p) => p.frameEncrypted);

  /// Worst link among connected peers, for the "weak connection" badge.
  CallQuality get worstQuality {
    var worst = CallQuality.unknown;
    for (final p in peers.values) {
      if (p.isConnected && p.quality.index > worst.index) worst = p.quality;
    }
    return worst;
  }
}

final webrtcConnectionManagerProvider =
    NotifierProvider<WebRTCConnectionManager, WebRTCMeshState>(WebRTCConnectionManager.new);

/// Full-mesh WebRTC: one RTCPeerConnection per remote participant, signaled
/// through `calls/{callId}/signaling`.
///
/// Every connection negotiates one audio and one video transceiver up front,
/// so turning the camera on in an audio call is a `replaceTrack` and never
/// needs renegotiation. Mesh works well up to about 6 people; beyond that an
/// SFU (LiveKit, mediasoup, Janus) is needed because each phone uploads its
/// video once per peer.
class WebRTCConnectionManager extends Notifier<WebRTCMeshState> {
  static const int maxMeshParticipants = 6;
  static const Duration _candidateBatchWindow = Duration(milliseconds: 35);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String get _me => FirebaseAuth.instance.currentUser?.uid ?? '';

  String? _callId;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _signalSub;
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};
  final Map<String, List<Map<String, dynamic>>> _outgoingCandidates = {};
  final Map<String, Timer> _candidateFlushTimers = {};
  final Map<String, RTCRtpSender> _audioSenders = {};
  final Map<String, RTCRtpSender> _videoSenders = {};
  // One negotiated data channel per peer (interpreter audio, captions).
  final Map<String, RTCDataChannel> _dataChannels = {};
  final Set<String> _dataOpen = {};
  final StreamController<CallDataMessage> _dataIn = StreamController.broadcast();
  final StreamController<String> _dataOpened = StreamController.broadcast();
  final Map<String, MediaStream> _remoteStreams = {};
  final Map<String, MediaStreamTrack> _remoteVideoTracks = {};
  final Set<String> _needsVideoUpgradeOffer = {};
  final Map<String, Timer> _disconnectTimers = {};
  final Set<String> _creating = {};
  final Map<String, DateTime> _lastPliSent = {};

  // Link quality sampling and ICE-restart retries.
  Timer? _statsTimer;
  final Map<String, ({num lost, num received})> _lastRx = {};
  final Map<String, DateTime> _lastRestart = {};
  final Map<String, int> _iceRestartRetries = {};
  CallQuality _cappedFor = CallQuality.unknown;

  // Frame encryption (insertable streams) per remote peer.
  final Map<String, KeyProvider> _keyProviders = {};
  final Map<String, List<FrameCryptor>> _cryptors = {};
  final Set<String> _offeredE2ee = {};

  /// One queue of WebRTC work per remote peer.
  ///
  /// On Android, libwebrtc calls flutter_webrtc's Java `onAddTrack` on its
  /// signaling thread in the middle of `setRemoteDescription`. That callback
  /// walks `PeerConnection.getTransceivers()`, which disposes the Java
  /// wrappers handed out by the previous call. If Dart reaches the same
  /// connection from the main thread at that moment (another
  /// `getTransceivers`, a remote track lookup, `close`/`dispose` on hang-up),
  /// one thread uses wrappers the other just disposed. The Java exception on
  /// the signaling thread aborts the whole app (SIGABRT in
  /// libjingle_peerconnection_so). Running every operation on a connection
  /// one after another keeps Dart away from it until the description is set.
  final Map<String, Future<void>> _peerOps = {};
  static const Duration _peerOpTimeout = Duration(seconds: 15);

  /// Runs [op] after every earlier operation on [uid]'s connection. Never
  /// throws; returns null when [op] fails or times out.
  Future<T?> _serial<T>(String uid, Future<T> Function() op, {Duration timeout = _peerOpTimeout}) {
    final done = Completer<T?>();
    final prev = _peerOps[uid] ?? Future<void>.value();
    final next = prev.then((_) async {
      try {
        done.complete(await op().timeout(timeout));
      } catch (e) {
        debugPrint('[Mesh] operation for $uid failed: $e');
        if (!done.isCompleted) done.complete(null);
      }
    });
    _peerOps[uid] = next;
    next.whenComplete(() {
      if (identical(_peerOps[uid], next)) _peerOps.remove(uid);
    });
    return done.future;
  }

  /// [peer] is still the connection this manager holds for its user (not
  /// removed, not replaced, call not left).
  bool _isLive(String callId, PeerState peer) =>
      _callId == callId && identical(state.peers[peer.remoteUserId]?.connection, peer.connection);

  /// Signaling writes are fire-and-forget: Firestore applies them in order
  /// locally, and awaiting the server ack would stall the peer's queue while
  /// the network is down.
  void _write(String callId, Map<String, dynamic> data) {
    unawaited(_signaling(callId).add(data).then<void>((_) {}, onError: (Object e) {
      debugPrint('[Mesh] signaling write ${data['type']} failed: $e');
    }));
  }

  /// Tunes Opus SDP parameters for zero-server-cost HD fullband voice clarity,
  /// packet-loss resilience (in-band FEC), silence savings (DTX), and 20ms
  /// low-latency framing.
  @visibleForTesting
  static String? tuneOpusSdp(String? sdp) {
    if (sdp == null || sdp.isEmpty) return sdp;
    final nl = sdp.contains('\r\n') ? '\r\n' : '\n';
    final lines = sdp.split(RegExp(r'\r?\n'));
    String? opusPt;
    int opusRtpmapIdx = -1;
    for (var i = 0; i < lines.length; i++) {
      final m = RegExp(r'^a=rtpmap:(\d+)\s+opus/48000', caseSensitive: false).firstMatch(lines[i]);
      if (m != null) {
        opusPt = m.group(1);
        opusRtpmapIdx = i;
        break;
      }
    }
    if (opusPt == null) return sdp;

    const desired = <String, String>{
      'minptime': '10',
      'ptime': '20',
      'useinbandfec': '1',
      'usedtx': '1',
      'maxaveragebitrate': '48000',
      'stereo': '0',
      'sprop-stereo': '0',
    };

    final prefix = 'a=fmtp:$opusPt ';
    var fmtpIdx = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].startsWith(prefix)) {
        fmtpIdx = i;
        break;
      }
    }
    if (fmtpIdx >= 0) {
      final rawParams = lines[fmtpIdx].substring(prefix.length).trim();
      final map = <String, String>{};
      for (final part in rawParams.split(';')) {
        final kv = part.trim().split('=');
        if (kv.length == 2 && kv[0].isNotEmpty) {
          map[kv[0].trim()] = kv[1].trim();
        }
      }
      map.addAll(desired);
      lines[fmtpIdx] = '$prefix${map.entries.map((e) => '${e.key}=${e.value}').join(';')}';
    } else if (opusRtpmapIdx >= 0) {
      lines.insert(
        opusRtpmapIdx + 1,
        '$prefix${desired.entries.map((e) => '${e.key}=${e.value}').join(';')}',
      );
    }
    return lines.join(nl);
  }

  Future<String?> _setLocalDescriptionTuned(RTCPeerConnection pc, RTCSessionDescription desc) async {
    final tunedSdp = tuneOpusSdp(desc.sdp);
    if (tunedSdp != null && tunedSdp != desc.sdp) {
      try {
        await pc.setLocalDescription(RTCSessionDescription(tunedSdp, desc.type));
        return tunedSdp;
      } catch (e) {
        debugPrint('[Mesh] tuned SDP fallback: $e');
      }
    }
    await pc.setLocalDescription(desc);
    return desc.sdp;
  }

  @override
  WebRTCMeshState build() {
    ref.onDispose(_teardown);
    return const WebRTCMeshState();
  }

  CollectionReference<Map<String, dynamic>> _signaling(String callId) =>
      _firestore.collection('calls').doc(callId).collection('signaling');

  /// Starts listening for offers/answers/candidates addressed to this user.
  void attach(String callId) {
    if (_callId == callId && _signalSub != null) return;
    _callId = callId;
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (_) => _sampleLinks());
    _signalSub?.cancel();
    _signalSub = _signaling(callId)
        .where('targetId', isEqualTo: _me)
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null) continue;
        final from = data['senderId'] as String?;
        if (from == null || from.isEmpty) continue;
        _serial(from, () => _handleSignal(callId, data)).whenComplete(() {
          change.doc.reference.delete().catchError((_) {});
        });
      }
    }, onError: (Object e) => debugPrint('[Mesh] signaling stream error: $e'));
  }

  /// Opens a connection to [remoteUserId]. The side that joins later is the
  /// offerer, so two peers never both send an initial offer.
  Future<void> connectTo(String remoteUserId, {required bool offerer}) async {
    final callId = _callId;
    if (callId == null || remoteUserId == _me) return;
    if (state.peers.containsKey(remoteUserId) || _creating.contains(remoteUserId)) return;
    // Reserved before queueing so a second connectTo for the same user bails.
    _creating.add(remoteUserId);
    await _serial(remoteUserId, () async {
      try {
        if (_callId != callId || state.peers.containsKey(remoteUserId)) return;
        final peer = await _createPeer(callId, remoteUserId, offerer: offerer);
        if (peer != null && offerer) await _sendOffer(callId, peer);
      } finally {
        _creating.remove(remoteUserId);
      }
    });
  }

  /// Opens the connection to [remoteUserId]. Returns null when the call was
  /// left while it was being set up (the half-built connection is closed).
  /// Only call from [remoteUserId]'s queue ([_serial]).
  Future<PeerState?> _createPeer(String callId, String remoteUserId, {required bool offerer}) async {
    _creating.add(remoteUserId);
    final renderer = RTCVideoRenderer();
    RTCPeerConnection? created;
    var owned = false;
    try {
      await renderer.initialize();
      renderer.onFirstFrameRendered = () {
        _patch(remoteUserId, (p) => p.copyWith(hasRemoteVideo: true, videoRevision: p.videoRevision + 1));
      };
      renderer.onResize = () {
        _patch(remoteUserId, (p) => p.copyWith(videoRevision: p.videoRevision + 1));
      };

      created = await createPeerConnection(CallIceConfig.configuration());
      final pc = created;
      // Hung up while the connection was opening: `finally` closes it.
      if (_callId != callId) return null;

      // Negotiated on both sides with the same id, so it's in the first
      // offer/answer with no extra signalling. Older app versions simply
      // don't open it, and the features that need it stay off.
      try {
        final dc = await pc.createDataChannel(
          'oneova-x',
          RTCDataChannelInit()
            ..negotiated = true
            ..id = 7
            ..ordered = true,
        );
        _bindDataChannel(remoteUserId, dc);
      } catch (e) {
        debugPrint('[Mesh] data channel for $remoteUserId: $e');
      }

      // Unified Plan: ONLY the offerer pre-creates SendRecv transceivers before
      // SDP exchange. The answerer must call setRemoteDescription(offer) first
      // and then bind its local tracks via pc.addTrack(...) so libwebrtc
      // associates them with the incoming m=audio / m=video sections and emits
      // valid a=msid attributes for both iOS and Android native video renderers.
      if (offerer) {
        final local = ref.read(callMediaServiceProvider).localStream;
        final streams = local != null ? [local] : <MediaStream>[];
        final audio = local?.getAudioTracks() ?? const <MediaStreamTrack>[];
        final audioInit = RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv, streams: streams);
        final audioTx = audio.isNotEmpty
            ? await pc.addTransceiver(
                track: audio.first,
                kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
                init: audioInit,
              )
            : await pc.addTransceiver(kind: RTCRtpMediaType.RTCRtpMediaTypeAudio, init: audioInit);
        _audioSenders[remoteUserId] = audioTx.sender;

        final video = local?.getVideoTracks() ?? const <MediaStreamTrack>[];
        final videoInit = RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv, streams: streams);
        final videoTx = video.isNotEmpty
            ? await pc.addTransceiver(
                track: video.first,
                kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
                init: videoInit,
              )
            : await pc.addTransceiver(kind: RTCRtpMediaType.RTCRtpMediaTypeVideo, init: videoInit);
        _videoSenders[remoteUserId] = videoTx.sender;
      }

      // Fires while setRemoteDescription is still running natively. Remote
      // tracks arrive enabled; setting `enabled` here (as before) made the
      // Android plugin look the track up through getTransceivers() on the
      // main thread, racing the signaling thread (native abort). Rendering is
      // queued behind the description so nothing touches the connection
      // until it is set.
      pc.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          _remoteStreams[remoteUserId] = event.streams.first;
        }
        final stream = event.streams.isNotEmpty ? event.streams.first : _remoteStreams[remoteUserId];
        if (event.track.kind == 'video') {
          _remoteVideoTracks[remoteUserId] = event.track;
          unawaited(_serial(remoteUserId, () => _bindRemoteVideo(remoteUserId, renderer, stream, event.track)));
          event.track.onUnMute = () {
            final latestStream = _remoteStreams[remoteUserId] ?? stream;
            unawaited(_serial(remoteUserId, () => _bindRemoteVideo(remoteUserId, renderer, latestStream, event.track)));
          };
          event.track.onEnded = () {
            _patch(remoteUserId, (p) => p.copyWith(hasRemoteVideo: false, videoRevision: p.videoRevision + 1));
          };
        } else if (stream != null && _remoteVideoTracks[remoteUserId] != null && renderer.srcObject == null) {
          final videoTrack = _remoteVideoTracks[remoteUserId]!;
          unawaited(_serial(remoteUserId, () => _bindRemoteVideo(remoteUserId, renderer, stream, videoTrack)));
        }
      };

      pc.onIceCandidate = (RTCIceCandidate c) {
        if (c.candidate == null || c.candidate!.isEmpty) return;
        _queueOutgoingCandidate(callId, remoteUserId, c);
      };

      pc.onConnectionState = (RTCPeerConnectionState s) => _onConnectionState(remoteUserId, s);

      if (_callId != callId) return null;
      final peer = PeerState(
        remoteUserId: remoteUserId,
        connection: pc,
        renderer: renderer,
        isOfferer: offerer,
      );
      state = WebRTCMeshState(peers: {...state.peers, remoteUserId: peer});
      owned = true;
      _applyBitrateCaps();
      return peer;
    } finally {
      _creating.remove(remoteUserId);
      if (!owned) {
        if (!state.peers.containsKey(remoteUserId)) {
          _audioSenders.remove(remoteUserId);
          _videoSenders.remove(remoteUserId);
        }
        unawaited(_closeQuietly(created, renderer));
      }
    }
  }

  /// Closes a connection and its renderer, ignoring errors. Callbacks are
  /// cleared first so late native events can't act on a peer that is gone.
  Future<void> _closeQuietly(RTCPeerConnection? pc, RTCVideoRenderer? renderer) async {
    if (renderer != null) {
      try {
        renderer.onFirstFrameRendered = null;
        renderer.onResize = null;
        renderer.srcObject = null;
        await renderer.dispose();
      } catch (_) {}
    }
    if (pc != null) {
      pc.onTrack = null;
      pc.onIceCandidate = null;
      pc.onConnectionState = null;
      try {
        await pc.close();
      } catch (_) {}
      try {
        await pc.dispose();
      } catch (_) {}
    }
  }

  Future<void> _bindRemoteVideo(
    String remoteUserId,
    RTCVideoRenderer renderer,
    MediaStream? stream,
    MediaStreamTrack videoTrack,
  ) async {
    // The peer was removed (hang-up) before this queued bind ran.
    if (!identical(state.peers[remoteUserId]?.renderer, renderer)) return;
    try {
      if (stream != null) {
        await renderer.setSrcObject(stream: stream, trackId: videoTrack.id);
      } else {
        final fallback = await createLocalMediaStream('remote_$remoteUserId');
        renderer.srcObject = fallback;
      }
    } catch (e) {
      debugPrint('[Mesh] bindRemoteVideo fallback for $remoteUserId: $e');
      if (stream != null) renderer.srcObject = stream;
    }
    _patch(
      remoteUserId,
      (p) => p.copyWith(hasRemoteVideo: true, videoRevision: p.videoRevision + 1),
    );
    final callId = _callId;
    if (callId != null) {
      _requestKeyframe(callId, remoteUserId);
    }
  }

  /// Binds the answerer's local audio/video tracks onto the exact transceivers
  /// created by `setRemoteDescription(offer)` so Unified Plan `m=` sections and
  /// `a=msid` stream bindings match symmetrically.
  Future<void> _bindAnswererTracks(String remoteUserId, RTCPeerConnection pc) async {
    final local = ref.read(callMediaServiceProvider).localStream;
    if (local == null) return;
    final audio = local.getAudioTracks();
    final video = local.getVideoTracks();

    if (!_audioSenders.containsKey(remoteUserId) && audio.isNotEmpty) {
      _audioSenders[remoteUserId] = await pc.addTrack(audio.first, local);
    }
    if (!_videoSenders.containsKey(remoteUserId)) {
      if (video.isNotEmpty) {
        _videoSenders[remoteUserId] = await pc.addTrack(video.first, local);
        _needsVideoUpgradeOffer.remove(remoteUserId);
      } else {
        // Leave incoming video transceiver as RecvOnly until local user turns
        // camera on, at which point pc.addTrack(video, local) + renegotiation
        // reuses this exact m=video section with valid a=msid.
        _needsVideoUpgradeOffer.add(remoteUserId);
      }
    } else if (video.isNotEmpty) {
      await _videoSenders[remoteUserId]!.replaceTrack(video.first);
    }
    _applyBitrateCaps();
  }

  void _queueOutgoingCandidate(String callId, String remoteUserId, RTCIceCandidate c) {
    final bucket = _outgoingCandidates.putIfAbsent(remoteUserId, () => []);
    bucket.add({
      'candidate': c.candidate,
      'sdpMid': c.sdpMid,
      'sdpMLineIndex': c.sdpMLineIndex,
    });
    _candidateFlushTimers[remoteUserId] ??= Timer(_candidateBatchWindow, () {
      _flushOutgoingCandidates(callId, remoteUserId);
    });
  }

  void _flushOutgoingCandidates(String callId, String remoteUserId) {
    _candidateFlushTimers.remove(remoteUserId)?.cancel();
    final batch = _outgoingCandidates.remove(remoteUserId);
    if (batch == null || batch.isEmpty || _callId != callId) return;
    if (batch.length == 1) {
      final single = batch.first;
      _write(callId, {
        'type': 'candidate',
        'senderId': _me,
        'targetId': remoteUserId,
        'candidate': single['candidate'],
        'sdpMid': single['sdpMid'],
        'sdpMLineIndex': single['sdpMLineIndex'],
        'timestamp': FieldValue.serverTimestamp(),
      });
    } else {
      _write(callId, {
        'type': 'candidates',
        'senderId': _me,
        'targetId': remoteUserId,
        'candidates': batch,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Only call from the peer's queue ([_serial]).
  Future<void> _sendOffer(String callId, PeerState peer, {bool iceRestart = false}) async {
    try {
      if (!_isLive(callId, peer)) return;
      final pc = peer.connection;
      final offer = await pc.createOffer({
        if (iceRestart) 'iceRestart': true,
      });
      if (!_isLive(callId, peer)) return;
      final sdp = await _setLocalDescriptionTuned(pc, offer);
      final current = state.peers[peer.remoteUserId] ?? peer;
      final e2ee = current.frameEncrypted ? null : await _e2eeOffer(peer.remoteUserId);
      if (!_isLive(callId, peer)) return;
      if (e2ee != null) _offeredE2ee.add(peer.remoteUserId);
      _write(callId, {
        'type': 'offer',
        'senderId': _me,
        'targetId': peer.remoteUserId,
        'sdp': sdp,
        'iceRestart': iceRestart,
        'e2ee': ?e2ee,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[Mesh] offer to ${peer.remoteUserId} failed: $e');
    }
  }

  /// Only call from the sender's queue ([_serial]), so a description is
  /// never set while anything else is using that connection.
  Future<void> _handleSignal(String callId, Map<String, dynamic> data) async {
    final from = data['senderId'] as String?;
    final type = data['type'] as String?;
    if (from == null || type == null) return;
    // A late signal from a call this phone already left.
    if (_callId != callId) return;

    try {
      switch (type) {
        case 'offer':
          // A newer joiner is calling us; we answer. Our own connectTo for
          // this user runs in the same queue, so it has finished by now.
          final peer = state.peers[from] ?? await _createPeer(callId, from, offerer: false);
          if (peer == null || !_isLive(callId, peer)) return;
          final pc = peer.connection;
          if (pc.signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
            // Glare: both sides offered. The lower uid backs off.
            if (_me.compareTo(from) > 0) return;
            await pc.setLocalDescription(RTCSessionDescription('', 'rollback'));
          }
          await pc.setRemoteDescription(RTCSessionDescription(data['sdp'] as String?, 'offer'));
          if (!_isLive(callId, peer)) return;
          await _bindAnswererTracks(from, pc);
          await _flushCandidates(from, pc);
          final answer = await pc.createAnswer();
          if (!_isLive(callId, peer)) return;
          final answerSdp = await _setLocalDescriptionTuned(pc, answer);
          // Turn frame encryption on after transceivers are associated, only
          // when both sides hold matching Oneova Shield keys.
          var e2eeOn = state.peers[from]?.frameEncrypted ?? false;
          if (!e2eeOn && await _e2eeOfferMatches(from, data['e2ee']) && _isLive(callId, peer)) {
            e2eeOn = await _enableFrameCrypto(callId, from);
          }
          if (!_isLive(callId, peer)) return;
          _write(callId, {
            'type': 'answer',
            'senderId': _me,
            'targetId': from,
            'sdp': answerSdp,
            if (e2eeOn) 'e2ee': {'v': 1},
            'timestamp': FieldValue.serverTimestamp(),
          });
          if (e2eeOn) _scheduleKeyframeNudge(from);
          break;
        case 'answer':
          final peer = state.peers[from];
          if (peer == null) return;
          final pc = peer.connection;
          if (pc.signalingState != RTCSignalingState.RTCSignalingStateHaveLocalOffer) return;
          await pc.setRemoteDescription(RTCSessionDescription(data['sdp'] as String?, 'answer'));
          if (!_isLive(callId, peer)) return;
          await _flushCandidates(from, pc);
          final hadOfferE2ee = _offeredE2ee.remove(from);
          if (data['e2ee'] is Map && hadOfferE2ee) {
            final enabled = await _enableFrameCrypto(callId, from);
            if (enabled) _scheduleKeyframeNudge(from);
          } else if (hadOfferE2ee) {
            await _disposeFrameCrypto(from);
          }
          break;
        case 'candidate':
          await _ingestCandidate(
            from,
            RTCIceCandidate(
              data['candidate'] as String?,
              data['sdpMid'] as String?,
              (data['sdpMLineIndex'] as num?)?.toInt(),
            ),
          );
          break;
        case 'candidates':
          final list = data['candidates'];
          if (list is List) {
            for (final item in list) {
              if (item is Map) {
                await _ingestCandidate(
                  from,
                  RTCIceCandidate(
                    item['candidate'] as String?,
                    item['sdpMid'] as String?,
                    (item['sdpMLineIndex'] as num?)?.toInt(),
                  ),
                );
              }
            }
          }
          break;
        case 'pli':
          await _nudgeVideoKeyframe(from);
          break;
        case 'restart':
          final peer = state.peers[from];
          if (peer != null && peer.isOfferer) await _sendOffer(callId, peer, iceRestart: true);
          break;
      }
    } catch (e) {
      debugPrint('[Mesh] handling $type from $from failed: $e');
    }
  }

  Future<void> _ingestCandidate(String from, RTCIceCandidate candidate) async {
    if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
    final pc = state.peers[from]?.connection;
    final remote = pc == null ? null : await pc.getRemoteDescription();
    if (pc == null || remote == null) {
      _pendingCandidates.putIfAbsent(from, () => []).add(candidate);
    } else {
      await pc.addCandidate(candidate);
    }
  }

  Future<void> _flushCandidates(String from, RTCPeerConnection pc) async {
    final queued = _pendingCandidates.remove(from);
    if (queued == null) return;
    for (final c in queued) {
      try {
        await pc.addCandidate(c);
      } catch (e) {
        debugPrint('[Mesh] queued candidate rejected: $e');
      }
    }
  }

  void _scheduleKeyframeNudge(String uid) {
    Timer(const Duration(milliseconds: 220), () {
      if (_callId == null || !state.peers.containsKey(uid)) return;
      unawaited(_serial(uid, () => _nudgeVideoKeyframe(uid)));
    });
  }

  /// Forces the outbound video encoder to emit a fresh IDR keyframe so a peer
  /// whose frame cryptor or decoder just initialised renders immediately.
  Future<void> _nudgeVideoKeyframe(String uid) async {
    final sender = _videoSenders[uid];
    if (sender == null) return;
    try {
      final track = sender.track;
      if (track != null) {
        await sender.replaceTrack(track);
      }
      final params = sender.parameters;
      if (params.encodings != null && params.encodings!.isNotEmpty) {
        await sender.setParameters(params);
      }
    } catch (_) {}
  }

  void _requestKeyframe(String callId, String uid) {
    if (_callId != callId) return;
    final now = DateTime.now();
    final prev = _lastPliSent[uid];
    if (prev != null && now.difference(prev) < const Duration(seconds: 2)) return;
    _lastPliSent[uid] = now;
    unawaited(
      _signaling(callId)
          .add({
            'type': 'pli',
            'senderId': _me,
            'targetId': uid,
            'timestamp': FieldValue.serverTimestamp(),
          })
          .then<void>((_) {}, onError: (_) {}),
    );
  }

  void _onConnectionState(String uid, RTCPeerConnectionState s) {
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _disconnectTimers.remove(uid)?.cancel();
        _iceRestartRetries.remove(uid);
        _patch(uid, (p) => p.copyWith(link: PeerLinkState.connected));
        _applyBitrateCaps();
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        _patch(uid, (p) => p.copyWith(link: PeerLinkState.reconnecting));
        // Often recovers on its own (brief handover); restart if it doesn't.
        _disconnectTimers[uid]?.cancel();
        _disconnectTimers[uid] = Timer(const Duration(seconds: 3), () => restartIce(uid));
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _patch(uid, (p) => p.copyWith(link: PeerLinkState.reconnecting));
        restartIce(uid);
        break;
      default:
        break;
    }
  }

  /// ICE restart for one peer with exponential backoff & max 3 retries to prevent connection storm/crashes.
  Future<void> restartIce(String uid) async {
    final callId = _callId;
    final peer = state.peers[uid];
    if (callId == null || peer == null || peer.isConnected) return;

    final retries = _iceRestartRetries[uid] ?? 0;
    if (retries >= 3) {
      debugPrint('[Mesh] ICE restart retries exhausted for $uid, marking link failed');
      _patch(uid, (p) => p.copyWith(link: PeerLinkState.failed));
      return;
    }
    _iceRestartRetries[uid] = retries + 1;
    _lastRestart[uid] = DateTime.now();
    await _requestIceRound(callId, peer);
  }

  /// Offerer: sends an ICE-restart offer. Answerer: asks the offerer to.
  Future<void> _requestIceRound(String callId, PeerState peer) async {
    if (peer.isOfferer) {
      await _serial(peer.remoteUserId, () => _sendOffer(callId, peer, iceRestart: true));
    } else {
      _write(callId, {
        'type': 'restart',
        'senderId': _me,
        'targetId': peer.remoteUserId,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Called when Wi-Fi/cellular changes: every peer gets a fresh ICE round.
  Future<void> restartAll() async {
    final callId = _callId;
    if (callId == null) return;
    for (final peer in state.peers.values.toList()) {
      _patch(peer.remoteUserId, (p) => p.copyWith(link: PeerLinkState.reconnecting));
      await _requestIceRound(callId, peer);
    }
  }

  /// Hot-swaps the outgoing microphone track on every connection (e.g. toggling
  /// Studio Voice Clean DSP) without dropping or renegotiating the call.
  Future<void> replaceAudioTrack(MediaStreamTrack? track) async {
    for (final entry in _audioSenders.entries.toList()) {
      await _serial(entry.key, () async {
        if (!identical(_audioSenders[entry.key], entry.value)) return;
        await entry.value.replaceTrack(track);
      });
    }
  }

  /// Swaps the outgoing camera track on every connection (camera on/off,
  /// camera flip, or audio→video upgrade).
  Future<void> replaceVideoTrack(MediaStreamTrack? track) async {
    final callId = _callId;
    if (callId == null) return;
    for (final peer in state.peers.values.toList()) {
      await _serial(peer.remoteUserId, () async {
        if (_isLive(callId, peer)) await _replaceVideoTrackFor(callId, peer, track);
      });
    }
    unawaited(_applyBitrateCaps());
  }

  Future<void> _replaceVideoTrackFor(String callId, PeerState peer, MediaStreamTrack? track) async {
    final local = ref.read(callMediaServiceProvider).localStream;
    final uid = peer.remoteUserId;
    try {
      if (track != null && _needsVideoUpgradeOffer.remove(uid) && local != null) {
        _videoSenders[uid] = await peer.connection.addTrack(track, local);
        await _sendOffer(callId, peer);
      } else if (_videoSenders.containsKey(uid)) {
        await _videoSenders[uid]!.replaceTrack(track);
      } else if (track != null) {
        final transceivers = await peer.connection.getTransceivers();
        final videoTx = transceivers
            .where((t) => t.receiver.track?.kind == 'video' || t.sender.track?.kind == 'video')
            .firstOrNull;
        if (videoTx != null) {
          _videoSenders[uid] = videoTx.sender;
          await videoTx.sender.replaceTrack(track);
        } else if (local != null) {
          _videoSenders[uid] = await peer.connection.addTrack(track, local);
          await _sendOffer(callId, peer);
        }
      }
      if (track != null) {
        _requestKeyframe(callId, uid);
      }
    } catch (e) {
      debugPrint('[Mesh] replaceVideoTrack($uid) failed: $e');
    }
  }

  /// Tunes per-peer video bitrate, 30fps smoothness (`MAINTAIN_FRAMERATE`), and
  /// high-priority audio RTP scheduling at $0 server cost.
  Future<void> _applyBitrateCaps() async {
    final n = state.peers.length;
    var cap = n <= 1 ? 1800000 : (n <= 3 ? 750000 : 350000);
    // On a weak link send less video so audio keeps flowing smoothly.
    _cappedFor = state.worstQuality;
    if (_cappedFor == CallQuality.poor) cap = cap < 280000 ? cap : 280000;
    if (_cappedFor == CallQuality.fair) cap = (cap * 0.65).round();
    final targetFps = _cappedFor == CallQuality.poor ? 20 : 30;

    for (final sender in _audioSenders.values.toList()) {
      try {
        final params = sender.parameters;
        final encodings = params.encodings;
        if (encodings == null || encodings.isEmpty) continue;
        for (final e in encodings) {
          e.maxBitrate = 48000;
          e.priority = RTCPriorityType.high;
          e.networkPriority = RTCPriorityType.high;
        }
        await sender.setParameters(params);
      } catch (_) {}
    }

    for (final sender in _videoSenders.values.toList()) {
      try {
        final params = sender.parameters;
        params.degradationPreference = RTCDegradationPreference.MAINTAIN_FRAMERATE;
        final encodings = params.encodings;
        if (encodings == null || encodings.isEmpty) continue;
        for (final e in encodings) {
          e.maxBitrate = cap;
          e.maxFramerate = targetFps;
        }
        await sender.setParameters(params);
      } catch (_) {
        // Not supported on every platform; ignore.
      }
    }
  }

  /// Every few seconds: rates each connected link from RTT and packet loss,
  /// and keeps retrying ICE restarts for links that are still down.
  Future<void> _sampleLinks() async {
    for (final peer in state.peers.values.toList()) {
      final uid = peer.remoteUserId;
      if (peer.link == PeerLinkState.reconnecting) {
        final last = _lastRestart[uid];
        if (last == null || DateTime.now().difference(last) > const Duration(seconds: 8)) {
          unawaited(restartIce(uid));
        }
        continue;
      }
      if (!peer.isConnected) continue;
      try {
        final reports = await peer.connection.getStats();
        num? rtt;
        num lost = 0;
        num received = 0;
        for (final r in reports) {
          final v = r.values;
          if (r.type == 'candidate-pair' && ('${v['nominated']}' == 'true' || v['state'] == 'succeeded')) {
            final x = _num(v['currentRoundTripTime']);
            if (x != null && x > 0) rtt = x;
          } else if (r.type == 'inbound-rtp') {
            lost += _num(v['packetsLost']) ?? 0;
            received += _num(v['packetsReceived']) ?? 0;
          }
        }
        final prev = _lastRx[uid];
        _lastRx[uid] = (lost: lost, received: received);
        var loss = 0.0;
        if (prev != null) {
          final dl = lost - prev.lost;
          final dr = received - prev.received;
          if (dl >= 0 && dl + dr > 0) loss = dl / (dl + dr);
        }
        final q = (rtt != null && rtt > 0.6) || loss > 0.08
            ? CallQuality.poor
            : (rtt != null && rtt > 0.3) || loss > 0.03
                ? CallQuality.fair
                : CallQuality.good;
        if (q != state.peers[uid]?.quality) _patch(uid, (p) => p.copyWith(quality: q));
      } catch (_) {
        // Stats are best effort.
      }
    }
    if (state.worstQuality != _cappedFor) unawaited(_applyBitrateCaps());
  }

  static num? _num(Object? v) => v is num ? v : num.tryParse('$v');

  /// How long closing a connection waits for the operation already running on
  /// it (normally a few milliseconds) before closing anyway, so hang-up never
  /// hangs on a slow network call.
  static const Duration _closeWait = Duration(seconds: 3);

  Future<void> removePeer(String uid) async {
    final peer = state.peers[uid];
    if (peer != null) {
      // Out of the state first: queued and running operations see the peer
      // is gone and stop at their next step.
      final next = Map<String, PeerState>.from(state.peers)..remove(uid);
      state = WebRTCMeshState(peers: next);
    }
    _disconnectTimers.remove(uid)?.cancel();
    _candidateFlushTimers.remove(uid)?.cancel();
    // Never close a connection while a description is being set on it: the
    // native track callbacks would use disposed objects and abort the app.
    final pending = _peerOps[uid];
    if (pending != null) {
      try {
        await pending.timeout(_closeWait);
      } catch (_) {}
    }
    _forgetPeer(uid);
    await _disposeFrameCrypto(uid);
    if (peer == null) return;
    await _closeQuietly(peer.connection, peer.renderer);
    unawaited(_applyBitrateCaps());
  }

  void _bindDataChannel(String uid, RTCDataChannel dc) {
    _dataChannels[uid] = dc;
    dc.onDataChannelState = (s) {
      if (!identical(_dataChannels[uid], dc)) return;
      if (s == RTCDataChannelState.RTCDataChannelOpen) {
        _dataOpen.add(uid);
        _dataOpened.add(uid);
      } else if (s == RTCDataChannelState.RTCDataChannelClosed || s == RTCDataChannelState.RTCDataChannelClosing) {
        _dataOpen.remove(uid);
      }
    };
    dc.onMessage = (m) {
      if (!identical(_dataChannels[uid], dc)) return;
      _dataIn.add(m.isBinary ? CallDataMessage(uid, bytes: m.binary) : CallDataMessage(uid, text: m.text));
    };
  }

  /// Messages from people in the call.
  Stream<CallDataMessage> get dataMessages => _dataIn.stream;

  /// A person's data channel just opened (say hello: your language, etc.).
  Stream<String> get dataChannelOpened => _dataOpened.stream;

  Set<String> get dataReadyPeers => Set.unmodifiable(_dataOpen);

  /// Sends to one person. Returns false if their channel isn't open.
  bool sendData(String uid, {String? text, Uint8List? bytes}) {
    final dc = _dataChannels[uid];
    if (dc == null || !_dataOpen.contains(uid)) return false;
    try {
      unawaited(dc.send(bytes != null ? RTCDataChannelMessage.fromBinary(bytes) : RTCDataChannelMessage(text ?? '')).catchError((_) {}));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Bytes waiting to go out to [uid]; used to drop audio instead of building delay.
  Future<int> bufferedAmount(String uid) async {
    try {
      return _dataChannels[uid]?.bufferedAmount ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Mutes or unmutes what we hear from [uid] (interpreter mode plays the
  /// translation instead of their original voice).
  Future<void> setRemoteAudioEnabled(String uid, bool enabled) async {
    await _serial(uid, () async {
      final tracks = _remoteStreams[uid]?.getAudioTracks() ?? const <MediaStreamTrack>[];
      for (final t in tracks) {
        t.enabled = enabled;
      }
    });
  }

  void _closeData(String uid) {
    _dataOpen.remove(uid);
    final dc = _dataChannels.remove(uid);
    if (dc == null) return;
    dc.onMessage = null;
    dc.onDataChannelState = null;
    unawaited(dc.close().catchError((_) {}));
  }

  /// Drops everything kept about [uid]'s connection.
  void _forgetPeer(String uid) {
    _closeData(uid);
    _disconnectTimers.remove(uid)?.cancel();
    _candidateFlushTimers.remove(uid)?.cancel();
    _outgoingCandidates.remove(uid);
    _lastRx.remove(uid);
    _lastRestart.remove(uid);
    _iceRestartRetries.remove(uid);
    _lastPliSent.remove(uid);
    _audioSenders.remove(uid);
    _videoSenders.remove(uid);
    _remoteStreams.remove(uid);
    _remoteVideoTracks.remove(uid);
    _needsVideoUpgradeOffer.remove(uid);
    _pendingCandidates.remove(uid);
    _offeredE2ee.remove(uid);
  }

  // ---------------------------------------------------------------------------
  // Frame encryption
  // ---------------------------------------------------------------------------

  static bool get _frameCryptoSupported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Fingerprints of my local key and of the peer key I fetched, so the
  /// answerer can confirm we agree before either side encrypts.
  Future<Map<String, dynamic>?> _e2eeOffer(String remoteUserId) async {
    if (!_frameCryptoSupported) return null;
    try {
      final e2ee = ref.read(e2eEncryptionServiceProvider);
      // Runs inside the peer's queue: a slow key lookup must not hold up the
      // call, it just means this call goes without frame encryption.
      const limit = Duration(seconds: 4);
      final mine = await e2ee.getMyPublicKey().timeout(limit);
      final theirs = await e2ee.getRecipientPublicKey(remoteUserId).timeout(limit);
      if (mine == null || theirs == null || theirs.isEmpty) return null;
      return {
        'v': 1,
        'me': e2ee.publicKeyFingerprint(mine),
        'peer': e2ee.publicKeyFingerprint(theirs),
      };
    } catch (e) {
      debugPrint('[Mesh] e2ee offer skipped: $e');
      return null;
    }
  }

  Future<bool> _e2eeOfferMatches(String from, Object? offer) async {
    if (offer is! Map || offer['v'] != 1) return false;
    final mine = await _e2eeOffer(from);
    if (mine == null) return false;
    // Their "me" must be the key I see for them, and their "peer" must be mine.
    return offer['me'] == mine['peer'] && offer['peer'] == mine['me'];
  }

  /// Attaches AES-GCM frame cryptors to every active sender and receiver of the
  /// connection to [uid], matched by media kind rather than raw transceiver
  /// index. Returns whether encryption is on.
  Future<bool> _enableFrameCrypto(String callId, String uid) async {
    final pc = state.peers[uid]?.connection;
    if (pc == null) return false;
    if (_cryptors.containsKey(uid)) return true;
    try {
      final e2ee = ref.read(e2eEncryptionServiceProvider);
      final peerKey = await e2ee.getRecipientPublicKey(uid);
      if (peerKey == null) return false;
      final key = await e2ee.deriveCallFrameKey(peerKey, callId);

      final provider = await frameCryptorFactory.createDefaultKeyProvider(KeyProviderOptions(
        sharedKey: true,
        ratchetSalt: Uint8List.fromList('oneova-call-frames'.codeUnits),
        ratchetWindowSize: 0,
        failureTolerance: -1,
        keyDerivationAlgorithm: KeyDerivationAlgorithm.kHKDF,
      ));
      await provider.setSharedKey(key: key);

      final cryptors = <FrameCryptor>[];
      final transceivers = await pc.getTransceivers();
      final seenKinds = <String>{};
      for (var i = 0; i < transceivers.length; i++) {
        final t = transceivers[i];
        if (t.stoped) continue;
        final rawKind = t.receiver.track?.kind ?? t.sender.track?.kind ?? 'm$i';
        final kindKey = seenKinds.add(rawKind) ? rawKind : '$rawKind$i';
        final tx = await frameCryptorFactory.createFrameCryptorForRtpSender(
          participantId: '$uid#tx#$kindKey',
          sender: t.sender,
          algorithm: Algorithm.kAesGcm,
          keyProvider: provider,
        );
        final rx = await frameCryptorFactory.createFrameCryptorForRtpReceiver(
          participantId: '$uid#rx#$kindKey',
          receiver: t.receiver,
          algorithm: Algorithm.kAesGcm,
          keyProvider: provider,
        );
        tx.onFrameCryptorStateChanged = (id, s) {
          if (s != FrameCryptorState.FrameCryptorStateOk && s != FrameCryptorState.FrameCryptorStateNew) {
            debugPrint('[Mesh] frame cryptor $id: $s');
          }
        };
        rx.onFrameCryptorStateChanged = (id, s) {
          if (s == FrameCryptorState.FrameCryptorStateDecryptionFailed && rawKind == 'video') {
            _requestKeyframe(callId, uid);
          } else if (s != FrameCryptorState.FrameCryptorStateOk && s != FrameCryptorState.FrameCryptorStateNew) {
            debugPrint('[Mesh] frame cryptor $id: $s');
          }
        };
        for (final c in [tx, rx]) {
          await c.setKeyIndex(0);
          await c.setEnabled(true);
          cryptors.add(c);
        }
      }
      _keyProviders[uid] = provider;
      _cryptors[uid] = cryptors;
      _patch(uid, (p) => p.copyWith(frameEncrypted: true));
      return true;
    } catch (e) {
      debugPrint('[Mesh] frame encryption unavailable for $uid: $e');
      await _disposeFrameCrypto(uid);
      return false;
    }
  }

  Future<void> _disposeFrameCrypto(String uid) async {
    for (final c in _cryptors.remove(uid) ?? const <FrameCryptor>[]) {
      try {
        await c.dispose();
      } catch (_) {}
    }
    try {
      await _keyProviders.remove(uid)?.dispose();
    } catch (_) {}
  }

  void _patch(String uid, PeerState Function(PeerState) f) {
    final peer = state.peers[uid];
    if (peer == null) return;
    state = WebRTCMeshState(peers: {...state.peers, uid: f(peer)});
  }

  Future<void> leaveMesh() async {
    // Stop new work first: no more signals, stats, ICE restarts or offers for
    // this call reach a connection while it is closing.
    _stopCallActivity();
    final ids = state.peers.keys.toList();
    await Future.wait(ids.map(removePeer));
    _teardown();
    state = const WebRTCMeshState();
  }

  void _stopCallActivity() {
    _statsTimer?.cancel();
    _statsTimer = null;
    _signalSub?.cancel();
    _signalSub = null;
    _callId = null;
    for (final t in _disconnectTimers.values) {
      t.cancel();
    }
    _disconnectTimers.clear();
  }

  void _teardown() {
    _stopCallActivity();
    for (final uid in _dataChannels.keys.toList()) {
      _closeData(uid);
    }
    _cappedFor = CallQuality.unknown;
    for (final t in _disconnectTimers.values) {
      t.cancel();
    }
    _disconnectTimers.clear();
    for (final t in _candidateFlushTimers.values) {
      t.cancel();
    }
    _candidateFlushTimers.clear();
    _outgoingCandidates.clear();
    _pendingCandidates.clear();
    _audioSenders.clear();
    _videoSenders.clear();
    _remoteStreams.clear();
    _remoteVideoTracks.clear();
    _needsVideoUpgradeOffer.clear();
    _lastPliSent.clear();
    _iceRestartRetries.clear();
    _lastRx.clear();
    _lastRestart.clear();
    _offeredE2ee.clear();

    // Provider disposed mid-call: close whatever is still open.
    for (final peer in state.peers.values.toList()) {
      unawaited(_closeQuietly(peer.connection, peer.renderer));
    }
    for (final uid in _cryptors.keys.toList()) {
      unawaited(_disposeFrameCrypto(uid));
    }
  }
}
