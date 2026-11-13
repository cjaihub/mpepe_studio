import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';

import '../../backend/calling/services/call_ice_config.dart';
import '../models/host_shorts_session.dart';

final hostShortsServiceProvider = NotifierProvider<HostShortsService, HostShortsSession?>(() {
  return HostShortsService();
});

/// Camera share ("Host Shorts"): a second phone streams its camera to the
/// host over WebRTC, as Angle B.
///
/// Signalling goes through `host_shorts_sessions/{pairCode}`:
/// - the host creates the doc and waits;
/// - Cam B opens its camera, creates the offer (it is the one sending
///   video) and writes `offer`; ICE goes to `camBCandidates`;
/// - the host answers (`answer`, ICE in `hostCandidates`), shows the stream
///   and, while it records, records Angle B to a file with MediaRecorder.
/// A data channel carries record start/stop to Cam B. Latency, resolution
/// and frame rate come from the connection's own stats.
class HostShortsService extends Notifier<HostShortsSession?> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  RTCVideoRenderer? _remoteRenderer;
  RTCVideoRenderer? _localRenderer;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  MediaRecorder? _angleRecorder;
  String? _anglePath;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _iceSub;
  Timer? _statsTimer;
  bool _answered = false;
  bool _remoteSet = false;
  final List<RTCIceCandidate> _pendingIce = [];

  /// Why the last host / join attempt failed (shown to the user).
  String? lastError;

  RTCVideoRenderer get remoteRenderer => _remoteRenderer ??= RTCVideoRenderer();

  /// Cam B's own camera preview.
  RTCVideoRenderer get localRenderer => _localRenderer ??= RTCVideoRenderer();

  bool get isCamB => state?.remoteDevice != null && state?.hostDevice.deviceId == 'host_director';

  @override
  HostShortsSession? build() {
    ref.onDispose(() {
      _cleanup();
    });
    return null;
  }

  Future<void> ensureRendererInitialized() async {
    _remoteRenderer ??= RTCVideoRenderer();
    try {
      await _remoteRenderer!.initialize();
    } catch (_) {}
  }

  DocumentReference<Map<String, dynamic>> _doc(String code) => _db.collection('host_shorts_sessions').doc(code);

  // ── Host (Cam A) ────────────────────────────────────────────────────────

  /// Opens a session and returns its 6-digit code, or null (see [lastError]).
  Future<String?> startHostingSession() async {
    lastError = null;
    final user = _auth.currentUser;
    if (user == null) {
      lastError = 'Sign in to share a camera.';
      return null;
    }
    await _cleanup();
    await ensureRendererInitialized();
    final code = (100000 + Random.secure().nextInt(900000)).toString();
    final host = HostShortsDevice(
      deviceId: 'host_${user.uid}',
      deviceName: 'Cam A (host)',
      role: HostShortsRole.hostDirector,
      resolution: '',
      fps: 0,
      latencyMs: 0,
    );
    final session = HostShortsSession(
      sessionId: code,
      pairCode: code,
      hostUid: user.uid,
      hostDevice: host,
      status: HostShortsStatus.hosting,
      createdAt: DateTime.now(),
    );
    try {
      await _doc(code).set({
        ...session.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 6))),
      });
    } catch (e) {
      lastError = 'Could not start camera share: $e';
      return null;
    }
    state = session;
    _answered = false;
    _remoteSet = false;
    _pc = await _newPeer(code, mine: 'hostCandidates', theirs: 'camBCandidates');
    _pc!.onTrack = (RTCTrackEvent e) {
      if (e.track.kind != 'video' || e.streams.isEmpty) return;
      _remoteStream = e.streams.first;
      remoteRenderer.srcObject = _remoteStream;
      final s = state;
      if (s != null) state = s.copyWith(status: HostShortsStatus.streaming);
    };
    _pc!.onDataChannel = (ch) {
      _dc = ch;
      _dc!.onMessage = (m) => _onCommand(m.text);
    };
    _docSub = _doc(code).snapshots().listen((snap) => _onHostDoc(code, snap));
    _startStats();
    return code;
  }

  Future<void> _onHostDoc(String code, DocumentSnapshot<Map<String, dynamic>> snap) async {
    final data = snap.data();
    final pc = _pc;
    if (data == null || pc == null) return;
    final remote = data['remoteDevice'];
    if (remote is Map && state != null) {
      state = state!.copyWith(remoteDevice: HostShortsDevice.fromMap(Map<String, dynamic>.from(remote)));
    }
    final offer = data['offer'];
    if (offer is Map && !_answered) {
      _answered = true;
      try {
        await pc.setRemoteDescription(RTCSessionDescription(offer['sdp'] as String?, offer['type'] as String?));
        _remoteSet = true;
        await _flushIce();
        final answer = await pc.createAnswer({'offerToReceiveVideo': true});
        await pc.setLocalDescription(answer);
        await _doc(code).update({
          'answer': {'sdp': answer.sdp, 'type': answer.type},
          'status': HostShortsStatus.connected.name,
        });
        if (state != null) state = state!.copyWith(status: HostShortsStatus.connected);
      } catch (e) {
        debugPrint('[CameraShare] answer failed: $e');
        _answered = false;
      }
    }
  }

  // ── Cam B ───────────────────────────────────────────────────────────────

  /// Joins [pairCode] as the second camera: opens this phone's back camera
  /// and streams it to the host. The caller must release its own camera
  /// first. Returns false with [lastError] set.
  Future<bool> joinAsCamB(String pairCode, {bool frontCamera = false}) async {
    lastError = null;
    final user = _auth.currentUser;
    if (user == null) {
      lastError = 'Sign in to join a camera share.';
      return false;
    }
    final code = pairCode.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      lastError = 'Enter the 6-digit code shown on the host phone.';
      return false;
    }
    await _cleanup();
    final DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await _doc(code).get();
    } catch (e) {
      lastError = 'Could not reach the session: $e';
      return false;
    }
    final data = doc.data();
    if (!doc.exists || data == null) {
      lastError = 'No camera share with code $code. Check the host phone.';
      return false;
    }
    if (data['offer'] != null) {
      lastError = 'Another camera is already connected to this session.';
      return false;
    }
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': frontCamera ? 'user' : 'environment',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'frameRate': {'ideal': 30},
        },
      });
    } catch (e) {
      lastError = 'This phone\'s camera could not open: $e';
      return false;
    }
    await localRenderer.initialize();
    localRenderer.srcObject = _localStream;

    final me = HostShortsDevice(
      deviceId: 'camb_${user.uid}',
      deviceName: Platform.isIOS ? 'iPhone (Cam B)' : 'Android (Cam B)',
      role: HostShortsRole.remoteCamB,
      resolution: '720p',
      fps: 30,
      latencyMs: 0,
    );
    state = HostShortsSession(
      sessionId: code,
      pairCode: code,
      hostUid: (data['hostUid'] as String?) ?? '',
      hostDevice: const HostShortsDevice(deviceId: 'host_director', deviceName: 'Cam A (host)', role: HostShortsRole.hostDirector),
      remoteDevice: me,
      status: HostShortsStatus.connecting,
      createdAt: DateTime.now(),
    );
    _remoteSet = false;
    try {
      final pc = _pc = await _newPeer(code, mine: 'camBCandidates', theirs: 'hostCandidates');
      for (final t in _localStream!.getVideoTracks()) {
        await pc.addTrack(t, _localStream!);
      }
      _dc = await pc.createDataChannel('host_shorts_control', RTCDataChannelInit()..ordered = true);
      _dc!.onMessage = (m) => _onCommand(m.text);
      final offer = await pc.createOffer({});
      await pc.setLocalDescription(offer);
      await _doc(code).update({
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'remoteDevice': me.toMap(),
        'status': HostShortsStatus.connecting.name,
      });
      _docSub = _doc(code).snapshots().listen((snap) async {
        final d = snap.data();
        if (d == null) {
          // The host ended the session.
          await disconnectSession();
          return;
        }
        final answer = d['answer'];
        if (answer is Map && !_remoteSet && _pc != null) {
          try {
            await _pc!.setRemoteDescription(RTCSessionDescription(answer['sdp'] as String?, answer['type'] as String?));
            _remoteSet = true;
            await _flushIce();
          } catch (e) {
            debugPrint('[CameraShare] answer not applied: $e');
          }
        }
        final layout = HostShortsLayout.values.where((l) => l.name == d['layout']).firstOrNull;
        if (layout != null && state != null && state!.layout != layout) state = state!.copyWith(layout: layout);
        final rec = d['isSyncedRecording'] == true;
        if (state != null && state!.isSyncedRecording != rec) state = state!.copyWith(isSyncedRecording: rec);
      });
      _startStats();
      return true;
    } catch (e) {
      lastError = 'Could not connect to the host: $e';
      await _cleanup();
      state = null;
      return false;
    }
  }

  // ── Shared WebRTC plumbing ──────────────────────────────────────────────

  Future<RTCPeerConnection> _newPeer(String code, {required String mine, required String theirs}) async {
    final pc = await createPeerConnection(CallIceConfig.configuration());
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      _doc(code).collection(mine).add({
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      }).then((_) {}, onError: (Object _) {});
    };
    pc.onIceConnectionState = (s) {
      final st = state;
      if (st == null) return;
      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        state = st.copyWith(status: HostShortsStatus.streaming);
      } else if (s == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        state = st.copyWith(status: HostShortsStatus.connecting);
      } else if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        lastError = 'The phones could not reach each other. Put both on the same Wi-Fi and try again.';
        state = st.copyWith(status: HostShortsStatus.connecting);
      }
    };
    _iceSub = _doc(code).collection(theirs).snapshots().listen((q) {
      for (final ch in q.docChanges) {
        if (ch.type != DocumentChangeType.added) continue;
        final m = ch.doc.data();
        if (m == null) continue;
        final cand = RTCIceCandidate(m['candidate'] as String?, m['sdpMid'] as String?, (m['sdpMLineIndex'] as num?)?.toInt());
        if (_remoteSet) {
          pc.addCandidate(cand).catchError((_) {});
        } else {
          _pendingIce.add(cand);
        }
      }
    });
    return pc;
  }

  Future<void> _flushIce() async {
    final pc = _pc;
    if (pc == null) return;
    for (final c in [..._pendingIce]) {
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    }
    _pendingIce.clear();
  }

  void _onCommand(String message) {
    final s = state;
    if (s == null) return;
    if (message == 'CMD:START_RECORD') state = s.copyWith(isSyncedRecording: true);
    if (message == 'CMD:STOP_RECORD') state = s.copyWith(isSyncedRecording: false);
  }

  /// Real latency (half the ICE round trip), resolution and frame rate.
  void _startStats() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final pc = _pc;
      final s = state;
      if (pc == null || s == null) return;
      try {
        final reports = await pc.getStats();
        double? rtt;
        int? w, h;
        double? fps;
        for (final r in reports) {
          final v = r.values;
          if (r.type == 'candidate-pair' && (v['state'] == 'succeeded') && v['currentRoundTripTime'] != null) {
            rtt = (v['currentRoundTripTime'] as num).toDouble();
          }
          if ((r.type == 'inbound-rtp' || r.type == 'outbound-rtp') && (v['kind'] == 'video' || v['mediaType'] == 'video')) {
            w = (v['frameWidth'] as num?)?.toInt() ?? w;
            h = (v['frameHeight'] as num?)?.toInt() ?? h;
            fps = (v['framesPerSecond'] as num?)?.toDouble() ?? fps;
          }
        }
        final dev = s.remoteDevice;
        if (dev == null) return;
        final short = (w != null && h != null) ? min(w, h) : null;
        state = s.copyWith(
          remoteDevice: HostShortsDevice(
            deviceId: dev.deviceId,
            deviceName: dev.deviceName,
            role: dev.role,
            batteryPercent: dev.batteryPercent,
            latencyMs: rtt == null ? dev.latencyMs : (rtt * 500).round(),
            isRecording: s.isSyncedRecording,
            resolution: short == null ? dev.resolution : '${short}p',
            fps: fps == null ? dev.fps : fps.round(),
          ),
        );
      } catch (_) {}
    });
  }

  // ── Host controls ───────────────────────────────────────────────────────

  void switchLayout(HostShortsLayout newLayout) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(layout: newLayout);
    _doc(s.pairCode).update({'layout': newLayout.name}).catchError((_) {});
  }

  void setAudioSource(HostShortsAudioSource source) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(audioSource: source);
  }

  /// Tells Cam B the host started or stopped recording.
  void triggerSyncRecord(bool start) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(isSyncedRecording: start);
    try {
      _dc?.send(RTCDataChannelMessage(start ? 'CMD:START_RECORD' : 'CMD:STOP_RECORD'));
    } catch (_) {}
    _doc(s.pairCode).update({'isSyncedRecording': start}).catchError((_) {});
  }

  /// Host: records the incoming Angle B stream next to its own take.
  Future<bool> startAngleRecording() async {
    final track = _remoteStream?.getVideoTracks().firstOrNull;
    if (track == null) return false;
    try {
      final dir = await getTemporaryDirectory();
      _anglePath = '${dir.path}/oneova_angle_b_${DateTime.now().millisecondsSinceEpoch}.mp4';
      _angleRecorder = MediaRecorder();
      await _angleRecorder!.start(_anglePath!, videoTrack: track);
      return true;
    } catch (e) {
      debugPrint('[CameraShare] Angle B recording failed: $e');
      _angleRecorder = null;
      return false;
    }
  }

  /// Finishes Angle B; returns the file, or null when nothing was recorded.
  Future<String?> stopAngleRecording() async {
    final rec = _angleRecorder;
    final path = _anglePath;
    _angleRecorder = null;
    _anglePath = null;
    if (rec == null || path == null) return null;
    try {
      await rec.stop();
      final f = File(path);
      if (await f.exists() && await f.length() > 0) return path;
    } catch (e) {
      debugPrint('[CameraShare] Angle B stop failed: $e');
    }
    return null;
  }

  Future<void> _cleanup() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    await _docSub?.cancel();
    _docSub = null;
    await _iceSub?.cancel();
    _iceSub = null;
    _pendingIce.clear();
    try {
      await _angleRecorder?.stop();
    } catch (_) {}
    _angleRecorder = null;
    try {
      await _dc?.close();
    } catch (_) {}
    _dc = null;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    for (final t in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      try {
        await t.stop();
      } catch (_) {}
    }
    try {
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    _remoteStream = null;
    _remoteRenderer?.srcObject = null;
    _localRenderer?.srcObject = null;
  }

  /// Ends the session (the host deletes it; Cam B just leaves).
  Future<void> disconnectSession() async {
    final s = state;
    state = null;
    if (s != null) {
      final uid = _auth.currentUser?.uid;
      if (s.hostUid == uid && s.hostDevice.deviceId != 'host_director') {
        final ref = _doc(s.pairCode);
        for (final sub in ['hostCandidates', 'camBCandidates']) {
          try {
            final q = await ref.collection(sub).get();
            for (final d in q.docs) {
              await d.reference.delete();
            }
          } catch (_) {}
        }
        await ref.delete().catchError((_) {});
      }
    }
    await _cleanup();
  }
}
