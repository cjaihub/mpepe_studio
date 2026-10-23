import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../security/e2e_encryption_service.dart';
import '../services/call_ice_config.dart';
import 'call_media_service.dart';

/// Link quality of one peer, shown as a small badge in the call UI.
enum PeerLinkState { connecting, connected, reconnecting, failed }

class PeerState {
  final String remoteUserId;
  final RTCPeerConnection connection;
  final RTCVideoRenderer renderer;
  final PeerLinkState link;
  final bool isOfferer;
  final bool hasRemoteVideo;

  /// Audio/video frames to this peer are AES-GCM encrypted with a key derived
  /// from both users' Oneova Shield identity keys, on top of DTLS-SRTP.
  final bool frameEncrypted;

  const PeerState({
    required this.remoteUserId,
    required this.connection,
    required this.renderer,
    required this.isOfferer,
    this.link = PeerLinkState.connecting,
    this.hasRemoteVideo = false,
    this.frameEncrypted = false,
  });

  bool get isConnected => link == PeerLinkState.connected;

  PeerState copyWith({PeerLinkState? link, bool? hasRemoteVideo, bool? frameEncrypted}) => PeerState(
        remoteUserId: remoteUserId,
        connection: connection,
        renderer: renderer,
        isOfferer: isOfferer,
        link: link ?? this.link,
        hasRemoteVideo: hasRemoteVideo ?? this.hasRemoteVideo,
        frameEncrypted: frameEncrypted ?? this.frameEncrypted,
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

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String get _me => FirebaseAuth.instance.currentUser?.uid ?? '';

  String? _callId;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _signalSub;
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};
  final Map<String, RTCRtpSender> _videoSenders = {};
  final Map<String, Timer> _disconnectTimers = {};
  final Set<String> _creating = {};

  // Frame encryption (insertable streams) per remote peer.
  final Map<String, KeyProvider> _keyProviders = {};
  final Map<String, List<FrameCryptor>> _cryptors = {};
  final Set<String> _offeredE2ee = {};

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
    _signalSub?.cancel();
    _signalSub = _signaling(callId)
        .where('targetId', isEqualTo: _me)
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null) continue;
        _handleSignal(callId, data).whenComplete(() {
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
    final peer = await _createPeer(callId, remoteUserId, offerer: offerer);
    if (offerer) await _sendOffer(callId, peer);
  }

  Future<PeerState> _createPeer(String callId, String remoteUserId, {required bool offerer}) async {
    _creating.add(remoteUserId);
    try {
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      final pc = await createPeerConnection(CallIceConfig.configuration());

      final local = ref.read(callMediaServiceProvider).localStream;
      final streams = local != null ? [local] : <MediaStream>[];
      final audio = local?.getAudioTracks() ?? const <MediaStreamTrack>[];
      if (audio.isNotEmpty) {
        await pc.addTrack(audio.first, local!);
      } else {
        await pc.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv, streams: streams),
        );
      }
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

      pc.onTrack = (RTCTrackEvent event) async {
        MediaStream? stream = event.streams.isNotEmpty ? event.streams.first : renderer.srcObject;
        if (stream == null) {
          stream = await createLocalMediaStream('remote_$remoteUserId');
          await stream.addTrack(event.track);
        }
        renderer.srcObject = stream;
        if (event.track.kind == 'video') _patch(remoteUserId, (p) => p.copyWith(hasRemoteVideo: true));
      };

      pc.onIceCandidate = (RTCIceCandidate c) {
        if (c.candidate == null) return;
        _signaling(callId).add({
          'type': 'candidate',
          'senderId': _me,
          'targetId': remoteUserId,
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
          'timestamp': FieldValue.serverTimestamp(),
        });
      };

      pc.onConnectionState = (RTCPeerConnectionState s) => _onConnectionState(remoteUserId, s);

      final peer = PeerState(
        remoteUserId: remoteUserId,
        connection: pc,
        renderer: renderer,
        isOfferer: offerer,
      );
      state = WebRTCMeshState(peers: {...state.peers, remoteUserId: peer});
      _applyBitrateCaps();
      return peer;
    } finally {
      _creating.remove(remoteUserId);
    }
  }

  Future<void> _sendOffer(String callId, PeerState peer, {bool iceRestart = false}) async {
    try {
      final offer = await peer.connection.createOffer({
        if (iceRestart) 'iceRestart': true,
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      await peer.connection.setLocalDescription(offer);
      final e2ee = peer.frameEncrypted ? null : await _e2eeOffer(peer.remoteUserId);
      if (e2ee != null) _offeredE2ee.add(peer.remoteUserId);
      await _signaling(callId).add({
        'type': 'offer',
        'senderId': _me,
        'targetId': peer.remoteUserId,
        'sdp': offer.sdp,
        'iceRestart': iceRestart,
        'e2ee': ?e2ee,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[Mesh] offer to ${peer.remoteUserId} failed: $e');
    }
  }

  Future<void> _handleSignal(String callId, Map<String, dynamic> data) async {
    final from = data['senderId'] as String?;
    final type = data['type'] as String?;
    if (from == null || type == null) return;

    try {
      switch (type) {
        case 'offer':
          var peer = state.peers[from];
          if (peer == null) {
            // A newer joiner is calling us; we answer.
            if (_creating.contains(from)) {
              await Future<void>.delayed(const Duration(milliseconds: 300));
              peer = state.peers[from];
            }
            peer ??= await _createPeer(callId, from, offerer: false);
          }
          final pc = peer.connection;
          if (pc.signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
            // Glare: both sides offered. The lower uid backs off.
            if (_me.compareTo(from) > 0) return;
            await pc.setLocalDescription(RTCSessionDescription('', 'rollback'));
          }
          await pc.setRemoteDescription(RTCSessionDescription(data['sdp'] as String?, 'offer'));
          await _flushCandidates(from, pc);
          // Turn frame encryption on before answering, only when both sides
          // hold matching keys (checked through the fingerprints in the offer).
          var e2eeOn = state.peers[from]?.frameEncrypted ?? false;
          if (!e2eeOn && await _e2eeOfferMatches(from, data['e2ee'])) {
            e2eeOn = await _enableFrameCrypto(callId, from);
          }
          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          await _signaling(callId).add({
            'type': 'answer',
            'senderId': _me,
            'targetId': from,
            'sdp': answer.sdp,
            if (e2eeOn) 'e2ee': {'v': 1},
            'timestamp': FieldValue.serverTimestamp(),
          });
          break;
        case 'answer':
          final pc = state.peers[from]?.connection;
          if (pc == null) return;
          if (pc.signalingState != RTCSignalingState.RTCSignalingStateHaveLocalOffer) return;
          if (data['e2ee'] is Map && _offeredE2ee.remove(from)) {
            await _enableFrameCrypto(callId, from);
          }
          await pc.setRemoteDescription(RTCSessionDescription(data['sdp'] as String?, 'answer'));
          await _flushCandidates(from, pc);
          break;
        case 'candidate':
          final candidate = RTCIceCandidate(
            data['candidate'] as String?,
            data['sdpMid'] as String?,
            (data['sdpMLineIndex'] as num?)?.toInt(),
          );
          final pc = state.peers[from]?.connection;
          final remote = pc == null ? null : await pc.getRemoteDescription();
          if (pc == null || remote == null) {
            _pendingCandidates.putIfAbsent(from, () => []).add(candidate);
          } else {
            await pc.addCandidate(candidate);
          }
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

  void _onConnectionState(String uid, RTCPeerConnectionState s) {
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _disconnectTimers.remove(uid)?.cancel();
        _patch(uid, (p) => p.copyWith(link: PeerLinkState.connected));
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

  /// ICE restart for one peer: the offerer re-offers, the answerer asks it to.
  Future<void> restartIce(String uid) async {
    final callId = _callId;
    final peer = state.peers[uid];
    if (callId == null || peer == null || peer.isConnected) return;
    if (peer.isOfferer) {
      await _sendOffer(callId, peer, iceRestart: true);
    } else {
      await _signaling(callId).add({
        'type': 'restart',
        'senderId': _me,
        'targetId': uid,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Called when Wi-Fi/cellular changes: every peer gets a fresh ICE round.
  Future<void> restartAll() async {
    final callId = _callId;
    if (callId == null) return;
    for (final peer in state.peers.values) {
      _patch(peer.remoteUserId, (p) => p.copyWith(link: PeerLinkState.reconnecting));
      if (peer.isOfferer) {
        await _sendOffer(callId, peer, iceRestart: true);
      } else {
        await _signaling(callId).add({
          'type': 'restart',
          'senderId': _me,
          'targetId': peer.remoteUserId,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  /// Swaps the outgoing camera track on every connection (camera on/off,
  /// audio→video upgrade). No renegotiation needed.
  Future<void> replaceVideoTrack(MediaStreamTrack? track) async {
    for (final sender in _videoSenders.values) {
      try {
        await sender.replaceTrack(track);
      } catch (e) {
        debugPrint('[Mesh] replaceTrack failed: $e');
      }
    }
  }

  /// Lowers per-peer video bitrate as the mesh grows so phones don't saturate
  /// their uplink.
  Future<void> _applyBitrateCaps() async {
    final n = state.peers.length;
    final cap = n <= 1 ? 1500000 : (n <= 3 ? 600000 : 300000);
    for (final sender in _videoSenders.values) {
      try {
        final params = sender.parameters;
        final encodings = params.encodings;
        if (encodings == null || encodings.isEmpty) continue;
        for (final e in encodings) {
          e.maxBitrate = cap;
        }
        await sender.setParameters(params);
      } catch (_) {
        // Not supported on every platform; ignore.
      }
    }
  }

  Future<void> removePeer(String uid) async {
    _disconnectTimers.remove(uid)?.cancel();
    _videoSenders.remove(uid);
    _pendingCandidates.remove(uid);
    _offeredE2ee.remove(uid);
    await _disposeFrameCrypto(uid);
    final peer = state.peers[uid];
    if (peer == null) return;
    final next = Map<String, PeerState>.from(state.peers)..remove(uid);
    state = WebRTCMeshState(peers: next);
    try {
      await peer.connection.close();
    } catch (_) {}
    try {
      peer.renderer.srcObject = null;
      await peer.renderer.dispose();
    } catch (_) {}
    _applyBitrateCaps();
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
      final mine = await e2ee.getMyPublicKey();
      final theirs = await e2ee.getRecipientPublicKey(remoteUserId);
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

  /// Attaches AES-GCM frame cryptors to every sender and receiver of the
  /// connection to [uid]. Returns whether encryption is on.
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
      for (var i = 0; i < transceivers.length; i++) {
        final t = transceivers[i];
        final tx = await frameCryptorFactory.createFrameCryptorForRtpSender(
          participantId: '$uid#tx$i',
          sender: t.sender,
          algorithm: Algorithm.kAesGcm,
          keyProvider: provider,
        );
        final rx = await frameCryptorFactory.createFrameCryptorForRtpReceiver(
          participantId: '$uid#rx$i',
          receiver: t.receiver,
          algorithm: Algorithm.kAesGcm,
          keyProvider: provider,
        );
        for (final c in [tx, rx]) {
          c.onFrameCryptorStateChanged = (id, s) {
            if (s != FrameCryptorState.FrameCryptorStateOk) debugPrint('[Mesh] frame cryptor $id: $s');
          };
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
    final ids = state.peers.keys.toList();
    for (final id in ids) {
      await removePeer(id);
    }
    _teardown();
    state = const WebRTCMeshState();
  }

  void _teardown() {
    _signalSub?.cancel();
    _signalSub = null;
    _callId = null;
    for (final t in _disconnectTimers.values) {
      t.cancel();
    }
    _disconnectTimers.clear();
    _pendingCandidates.clear();
    _videoSenders.clear();
  }
}
