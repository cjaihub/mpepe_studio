import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../backend/ice_servers.dart';
import 'desktop_firebase_rest_client.dart';
import 'desktop_input_router.dart';

enum DesktopResponderStatus {
  stopped,
  standby,
  negotiating,
  streaming,
  controlOnly,
  error,
}

class DesktopResponderSnapshot {
  final DesktopResponderStatus status;
  final bool screenShareActive;
  final bool dataChannelOpen;
  final String? activeSessionId;
  final String? statusDetail;

  const DesktopResponderSnapshot({
    this.status = DesktopResponderStatus.stopped,
    this.screenShareActive = false,
    this.dataChannelOpen = false,
    this.activeSessionId,
    this.statusDetail,
  });

  DesktopResponderSnapshot copyWith({
    DesktopResponderStatus? status,
    bool? screenShareActive,
    bool? dataChannelOpen,
    String? activeSessionId,
    String? statusDetail,
  }) {
    return DesktopResponderSnapshot(
      status: status ?? this.status,
      screenShareActive: screenShareActive ?? this.screenShareActive,
      dataChannelOpen: dataChannelOpen ?? this.dataChannelOpen,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      statusDetail: statusDetail ?? this.statusDetail,
    );
  }
}

/// Native Flutter Desktop WebRTC Responder for Oneova Computer Agent.
///
/// Polls `registered_computers/{deviceId}/webrtc_signaling` via
/// [DesktopFirebaseRestClient] for incoming SDP offers from paired Oneova
/// mobile devices, streams the live desktop display via ScreenCaptureKit
/// (`getDisplayMedia`), and executes ultra-low-latency trackpad, mouse, hotkey,
/// text, wake/unlock, and AI commands over the `'mouse_control'` DataChannel.
class DesktopWebRTCResponder {
  final DesktopFirebaseRestClient _cloud;
  final Future<void> Function(String prompt)? onAiCommand;
  final void Function(String commandSummary)? onControlEvent;

  final ValueNotifier<DesktopResponderSnapshot> state =
      ValueNotifier(const DesktopResponderSnapshot());

  StreamSubscription<List<DesktopRestDoc>>? _signalingSub;
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  RTCDataChannel? _fastChannel;
  Process? _keepAwake;
  final List<({RTCRtpSender sender, MediaStreamTrack track})> _videoSenders = [];
  MediaStream? _displayStream;
  String? _deviceId;
  String? _activeSessionId;
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingCallerCandidates = [];
  final Set<String> _handledOfferDocIds = {};
  final Set<String> _handledCandidateDocIds = {};
  Future<void> _keyChain = Future.value();

  static bool _isKeyPacket(String raw) =>
      raw.contains('"key_tap"') ||
      raw.contains('"key_press"') ||
      raw.contains('"key_combination"') ||
      raw.contains('"type_text"') ||
      raw.contains('"paste_text"');
  Timer? _resubscribeTimer;
  DateTime _lastSweep = DateTime.fromMillisecondsSinceEpoch(0);

  /// Signaling docs older than this are finished with and get deleted, so
  /// the collection never grows large enough to hide a new offer.
  static const _staleAfterSeconds = 120;

  DesktopWebRTCResponder({
    DesktopFirebaseRestClient? cloudClient,
    this.onAiCommand,
    this.onControlEvent,
  }) : _cloud = cloudClient ?? DesktopFirebaseRestClient.instance;

  bool get isRunning => state.value.status != DesktopResponderStatus.stopped;

  Future<void> start(String deviceId) async {
    if (_deviceId == deviceId && _signalingSub != null) return;
    await stop();

    _deviceId = deviceId;
    state.value = const DesktopResponderSnapshot(
      status: DesktopResponderStatus.standby,
      statusDetail: 'Ready for mobile connection',
    );
    _startKeepAwake();

    if (!kIsWeb && Platform.isMacOS) {
      try {
        await Helper.requestCapturePermission();
      } catch (e) {
        debugPrint('[DesktopWebRTCResponder] Screen capture preflight notice: $e');
      }
    }

    _subscribeSignaling(deviceId);
  }

  static int _ageSeconds(Map<String, dynamic> data, DateTime now) {
    final ts = data['timestamp'];
    DateTime? created;
    if (ts is Timestamp) created = ts.toDate();
    if (ts is DateTime) created = ts;
    return created != null ? now.difference(created).inSeconds.abs() : 999;
  }

  /// Deletes finished signaling docs (old offers and ICE candidates from
  /// earlier attempts). Runs at most every 30 s.
  void _sweepStale(String signalingPath, List<DesktopRestDoc> docs) {
    final now = DateTime.now();
    if (now.difference(_lastSweep).inSeconds < 30) return;
    _lastSweep = now;
    for (final doc in docs) {
      if (_ageSeconds(doc.data, now) <= _staleAfterSeconds) continue;
      _handledOfferDocIds.add(doc.id);
      _handledCandidateDocIds.add(doc.id);
      unawaited(
        _cloud.deleteDocument('$signalingPath/${doc.id}').catchError((_) {}),
      );
    }
  }

  void _subscribeSignaling(String deviceId) {
    _resubscribeTimer?.cancel();
    final signalingPath = 'registered_computers/$deviceId/webrtc_signaling';
    bool isFirstSnapshot = true;

    _signalingSub = _cloud
        .watchCollection(
          signalingPath,
          // Fast only while an offer/ICE exchange is under way; otherwise a
          // slow idle poll is enough to notice the next offer.
          interval: const Duration(milliseconds: 750),
          idleInterval: const Duration(seconds: 3),
          keepFast: () =>
              state.value.status == DesktopResponderStatus.negotiating,
        )
        .listen(
      (docs) async {
        if (isFirstSnapshot) {
          isFirstSnapshot = false;
          _lastSweep = DateTime.fromMillisecondsSinceEpoch(0);
          final now = DateTime.now();
          for (final doc in docs) {
            final type = doc.data['type'] as String?;
            final ageSeconds = _ageSeconds(doc.data, now);
            if (ageSeconds > 14 && ageSeconds <= _staleAfterSeconds) {
              if (type == 'offer') _handledOfferDocIds.add(doc.id);
              if (type == 'caller_candidate') _handledCandidateDocIds.add(doc.id);
            }
          }
        }
        _sweepStale(signalingPath, docs);

        for (final doc in docs) {
          final docId = doc.id;
          final data = doc.data;
          final type = data['type'] as String?;
          final sessionId = data['session_id'] as String?;

          if (type == 'offer' && !_handledOfferDocIds.contains(docId)) {
            _handledOfferDocIds.add(docId);
            final sdp = data['sdp'] as String?;
            if (sdp != null && sdp.isNotEmpty) {
              await _handleIncomingOffer(
                deviceId: deviceId,
                sdp: sdp,
                sessionId: sessionId,
                mode: data['mode'] as String?,
              );
            }
          } else if (type == 'caller_candidate' &&
              !_handledCandidateDocIds.contains(docId)) {
            _handledCandidateDocIds.add(docId);
            if (_activeSessionId != null &&
                sessionId != null &&
                sessionId != _activeSessionId) {
              continue;
            }
            final candidateStr = data['candidate'] as String?;
            if (candidateStr != null && candidateStr.isNotEmpty) {
              final candidate = RTCIceCandidate(
                candidateStr,
                data['sdpMid'] as String?,
                (data['sdpMLineIndex'] as num?)?.toInt(),
              );
              if (_remoteDescriptionSet && _peerConnection != null) {
                try {
                  await _peerConnection!.addCandidate(candidate);
                } catch (e) {
                  debugPrint('[DesktopWebRTCResponder] addCandidate error: $e');
                }
              } else {
                _pendingCallerCandidates.add(candidate);
              }
            }
          }
        }
      },
      onError: (Object error) {
        debugPrint('[DesktopWebRTCResponder] Signaling stream error: $error');
        state.value = state.value.copyWith(
          status: DesktopResponderStatus.error,
          statusDetail: error.toString(),
        );
        // A permission error pauses polling until the path is watched again;
        // re-bind after a short wait so the agent never stays deaf to offers.
        _resubscribeTimer?.cancel();
        _resubscribeTimer = Timer(const Duration(seconds: 10), () async {
          if (_deviceId != deviceId) return;
          await _signalingSub?.cancel();
          _signalingSub = null;
          if (_deviceId != deviceId) return;
          if (state.value.status == DesktopResponderStatus.error) {
            state.value = const DesktopResponderSnapshot(
              status: DesktopResponderStatus.standby,
              statusDetail: 'Ready for mobile connection',
            );
          }
          _subscribeSignaling(deviceId);
        });
      },
    );
  }

  Future<void> _handleIncomingOffer({
    required String deviceId,
    required String sdp,
    required String? sessionId,
    String? mode,
  }) async {
    await _closePeerSession();

    _activeSessionId = sessionId;
    _remoteDescriptionSet = false;
    _pendingCallerCandidates.clear();

    state.value = DesktopResponderSnapshot(
      status: DesktopResponderStatus.negotiating,
      activeSessionId: sessionId,
      statusDetail: 'Negotiating WebRTC session...',
    );

    final signalingPath = 'registered_computers/$deviceId/webrtc_signaling';

    try {
      final pc = await createPeerConnection({
        // STUN + short-lived TURN relay (works across different networks).
        'iceServers': await IceServers.resolve(
          () => _cloud.callCallable('getIceServers', const {}),
        ),
        'sdpSemantics': 'unified-plan',
      });
      _peerConnection = pc;

      pc.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
        unawaited(
          _cloud.addDocument(signalingPath, {
            'type': 'callee_candidate',
            'session_id': ?sessionId,
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'timestamp': DateTime.now().toUtc(),
          }).catchError((Object e) {
            debugPrint('[DesktopWebRTCResponder] Failed to write ICE candidate: $e');
            return '';
          }),
        );
      };

      pc.onDataChannel = (RTCDataChannel channel) {
        if (channel.label == 'pointer_fast') {
          // Unordered lane: pointer/scroll deltas only, applied synchronously.
          _fastChannel = channel;
          channel.onMessage = (RTCDataChannelMessage message) {
            if (!message.isBinary) _handleFastJson(message.text);
          };
          return;
        }
        _dataChannel = channel;
        channel.onDataChannelState = (RTCDataChannelState dcState) {
          final isOpen = dcState == RTCDataChannelState.RTCDataChannelOpen;
          state.value = state.value.copyWith(dataChannelOpen: isOpen);
        };
        channel.onMessage = (RTCDataChannelMessage message) {
          if (message.isBinary) return;
          final raw = message.text;
          // Key presses run one at a time, in order, so fast typing never
          // arrives scrambled. Everything else (clicks, moves) runs at once.
          if (_isKeyPacket(raw)) {
            _keyChain = _keyChain
                .then((_) => _handleControlJson(raw))
                .catchError((Object _) {});
          } else {
            _handleControlJson(raw);
          }
        };
      };

      bool hasScreenTrack = false;
      // Phone-as-controller sessions only carry input; skip screen capture
      // so the desktop spends nothing on encoding and input stays snappy.
      if (mode != 'controller') {
      try {
        Helper.setScreenCaptureCursor(true);
        final stream = await navigator.mediaDevices.getDisplayMedia({
          'audio': false,
          'video': {
            'mandatory': {
              'frameRate': 30,
            },
          },
        });
        _displayStream = stream;
        for (final track in stream.getVideoTracks()) {
          final sender = await pc.addTrack(track, stream);
          _videoSenders.add((sender: sender, track: track));
          hasScreenTrack = true;
        }
      } catch (captureErr) {
        debugPrint(
          '[DesktopWebRTCResponder] Screen capture unavailable ($captureErr); continuing with DataChannel remote control.',
        );
      }
      }
      final controllerMode = mode == 'controller';

      pc.onConnectionState = (RTCPeerConnectionState pcState) {
        if (pcState == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          state.value = state.value.copyWith(
            status: hasScreenTrack
                ? DesktopResponderStatus.streaming
                : DesktopResponderStatus.controlOnly,
            screenShareActive: hasScreenTrack,
            statusDetail: hasScreenTrack
                ? 'Live screen + input bridge active'
                : controllerMode
                    ? 'Phone controller connected'
                    : 'Input bridge active (grant Screen Recording for display)',
          );
        } else if (pcState ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            pcState == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            pcState == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          state.value = const DesktopResponderSnapshot(
            status: DesktopResponderStatus.standby,
            statusDetail: 'Ready for mobile connection',
          );
        }
      };

      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      _remoteDescriptionSet = true;

      for (final c in _pendingCallerCandidates) {
        try {
          await pc.addCandidate(c);
        } catch (_) {}
      }
      _pendingCallerCandidates.clear();

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await _tuneVideoSenders();

      await _cloud.addDocument(signalingPath, {
        'type': 'answer',
        'session_id': ?sessionId,
        'sdp': answer.sdp,
        'screen_capture': hasScreenTrack,
        'timestamp': DateTime.now().toUtc(),
      });
    } catch (e) {
      debugPrint('[DesktopWebRTCResponder] Offer handling failed: $e');
      state.value = DesktopResponderSnapshot(
        status: DesktopResponderStatus.error,
        statusDetail: e.toString(),
      );
    }
  }

  /// High-rate packets from the `pointer_fast` lane. Short keys keep each
  /// datagram tiny: `{"a":"mv","dx":..,"dy":..}` / `{"a":"sc","dx":..,"dy":..}`.
  void _handleFastJson(String raw) {
    try {
      final packet = jsonDecode(raw) as Map<String, dynamic>;
      final action = (packet['a'] ?? packet['action'] ?? '').toString();
      final dx = (packet['dx'] as num?)?.toDouble() ?? 0.0;
      final dy = (packet['dy'] as num?)?.toDouble() ?? 0.0;
      switch (action) {
        case 'mv':
        case 'mouse_move':
          DesktopInputRouter.moveBy(dx, dy);
          break;
        case 'sc':
          DesktopInputRouter.scrollPixels(dx, dy);
          break;
        case 'mt':
          // Absolute pointer from the phone's live screen view (0..1).
          final nx = ((packet['nx'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
          final ny = ((packet['ny'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
          final b = DesktopInputRouter.getMainDisplayBounds();
          DesktopInputRouter.moveTo(nx * b.width, ny * b.height);
          break;
        case 'mouse_scroll':
          DesktopInputRouter.scroll(dy);
          break;
      }
    } catch (e) {
      debugPrint('[DesktopWebRTCResponder] Fast packet error: $e');
    }
  }

  void _reply(Map<String, dynamic> packet) {
    final dc = _dataChannel;
    if (dc == null || dc.state != RTCDataChannelState.RTCDataChannelOpen) return;
    try {
      dc.send(RTCDataChannelMessage(jsonEncode(packet)));
    } catch (_) {}
  }

  /// Keeps the live screen smooth on phones: a 5K/4K desktop is scaled to
  /// about 1920 px wide at 30 fps with a bitrate cap, so the encoder never
  /// falls behind and the phone never drops frames decoding it.
  Future<void> _tuneVideoSenders() async {
    for (final v in _videoSenders) {
      try {
        final settings = v.track.getSettings();
        final width = (settings['width'] as num?)?.toDouble() ?? 0;
        final scale = width > 1920 ? width / 1920 : 1.0;
        final params = v.sender.parameters;
        final encodings = params.encodings;
        if (encodings == null || encodings.isEmpty) continue;
        for (final e in encodings) {
          e.scaleResolutionDownBy = scale;
          e.maxFramerate = 30;
          e.maxBitrate = 6000000;
        }
        await v.sender.setParameters(params);
      } catch (e) {
        debugPrint('[DesktopWebRTCResponder] sender tuning notice: $e');
      }
    }
  }

  Future<void> _replyStatus() async {
    final b = DesktopInputRouter.getMainDisplayBounds();
    final app = await DesktopInputRouter.getActiveAppName();
    final locked = await DesktopInputRouter.isScreenLocked();
    _reply({
      'action': 'status',
      'app': app,
      'locked': locked,
      'awake_guard': _keepAwake != null,
      'screen': {'w': b.width, 'h': b.height},
    });
  }

  Future<void> _replyVolumeState() async {
    final vol = await DesktopInputRouter.getVolume();
    if (vol == null) return;
    _reply({'action': 'volume_state', 'level': vol.level, 'muted': vol.muted});
  }

  Future<void> _handleControlJson(String raw) async {
    try {
      final packet = jsonDecode(raw) as Map<String, dynamic>;
      final action =
          (packet['action'] ?? packet['type'] ?? packet['command'] ?? '')
              .toString();
      switch (action) {
        case 'mouse_move':
          final dx = (packet['dx'] as num?)?.toDouble() ?? 0.0;
          final dy = (packet['dy'] as num?)?.toDouble() ?? 0.0;
          DesktopInputRouter.moveBy(dx, dy);
          break;
        case 'mouse_move_normalized':
          final nx = ((packet['nx'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
          final ny = ((packet['ny'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
          final bounds = DesktopInputRouter.getMainDisplayBounds();
          DesktopInputRouter.moveTo(nx * bounds.width, ny * bounds.height);
          break;
        case 'mouse_click_normalized':
          final nx = ((packet['nx'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
          final ny = ((packet['ny'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
          final bounds = DesktopInputRouter.getMainDisplayBounds();
          await DesktopInputRouter.clickAt(nx * bounds.width, ny * bounds.height);
          onControlEvent?.call('Tap (${(nx * 100).round()}%, ${(ny * 100).round()}%)');
          break;
        case 'mouse_right_click_normalized':
          final nx = ((packet['nx'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
          final ny = ((packet['ny'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
          final bounds = DesktopInputRouter.getMainDisplayBounds();
          await DesktopInputRouter.clickAt(nx * bounds.width, ny * bounds.height, right: true);
          onControlEvent?.call('Right Click (${(nx * 100).round()}%, ${(ny * 100).round()}%)');
          break;
        case 'mouse_double_click_normalized':
          final nx = ((packet['nx'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
          final ny = ((packet['ny'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
          final bounds = DesktopInputRouter.getMainDisplayBounds();
          await DesktopInputRouter.clickAt(
            nx * bounds.width,
            ny * bounds.height,
            doubleClick: true,
          );
          onControlEvent?.call('Double Click (${(nx * 100).round()}%, ${(ny * 100).round()}%)');
          break;
        case 'mouse_scroll':
          final dy = (packet['dy'] as num?)?.toDouble() ?? 0.0;
          DesktopInputRouter.scroll(dy);
          break;
        case 'mv':
        case 'sc':
        case 'mt':
          _handleFastJson(raw);
          break;
        case 'status_get':
          await _replyStatus();
          break;
        case 'wake_display':
          await DesktopInputRouter.wakeDisplay();
          onControlEvent?.call('Wake display');
          await _replyStatus();
          break;
        case 'unlock_secure':
          // The password is used once and never logged or stored here.
          final secret = (packet['password'] ?? '').toString();
          final ok = await DesktopInputRouter.unlockWithPassword(secret);
          onControlEvent?.call(ok ? 'Unlock requested' : 'Unlock failed');
          await Future<void>.delayed(const Duration(milliseconds: 900));
          await _replyStatus();
          break;
        case 'ping':
          _reply({'action': 'pong', 't': packet['t']});
          break;
        case 'media_key':
          final key = (packet['key'] ?? '').toString();
          await DesktopInputRouter.mediaKey(key);
          onControlEvent?.call('Media: $key');
          if (key == 'mute' || key == 'vol_up' || key == 'vol_down') {
            // Let the system apply the key before reading the level back.
            await Future<void>.delayed(const Duration(milliseconds: 140));
            await _replyVolumeState();
          }
          break;
        case 'volume_set':
          final level = (packet['level'] as num?)?.round();
          if (level != null) {
            await DesktopInputRouter.setVolume(level);
          }
          break;
        case 'volume_mute':
          await DesktopInputRouter.setMuted(packet['muted'] == true);
          await _replyVolumeState();
          break;
        case 'volume_get':
          await _replyVolumeState();
          break;
        case 'mouse_left_click':
        case 'mouse_click':
          await DesktopInputRouter.clickCurrent();
          onControlEvent?.call('Mouse Left Click');
          break;
        case 'mouse_double_click':
          await DesktopInputRouter.doubleClickCurrent();
          onControlEvent?.call('Mouse Double Click');
          break;
        case 'mouse_right_click':
          await DesktopInputRouter.rightClickCurrent();
          onControlEvent?.call('Mouse Right Click');
          break;
        case 'mouse_left_down':
          DesktopInputRouter.leftClickDown();
          break;
        case 'mouse_left_up':
          DesktopInputRouter.leftClickUp();
          break;
        case 'key_tap':
        case 'key_press':
          final key = (packet['key'] ?? '').toString();
          if (key.isNotEmpty) {
            await DesktopInputRouter.tapKey(key);
            onControlEvent?.call('Key: $key');
          }
          break;
        case 'key_combination':
          final combo = (packet['combo'] ?? '').toString();
          if (combo.isNotEmpty) {
            await DesktopInputRouter.sendHotkey(combo);
            onControlEvent?.call('Hotkey: $combo');
          }
          break;
        case 'paste_text':
        case 'type_text':
          final text = (packet['text'] ?? '').toString();
          final pressEnter = packet['pressEnter'] == true;
          if (text.isNotEmpty) {
            await DesktopInputRouter.pasteTextInstant(text, pressEnter: pressEnter);
            onControlEvent?.call('Typed ${text.length} chars');
          }
          break;
        case 'wake_and_unlock':
          final passkey = (packet['passkey'] ?? '').toString();
          await DesktopInputRouter.wakeAndUnlock(passkey);
          onControlEvent?.call('Wake & Unlock');
          break;
        case 'ai_command':
          final prompt = (packet['prompt'] ?? '').toString();
          if (prompt.isNotEmpty && onAiCommand != null) {
            onControlEvent?.call('Ova AI: $prompt');
            await onAiCommand!(prompt);
          }
          break;
      }
    } catch (e) {
      debugPrint('[DesktopWebRTCResponder] Control packet error: $e');
    }
  }

  Future<void> _closePeerSession() async {
    _remoteDescriptionSet = false;
    _pendingCallerCandidates.clear();
    try {
      await _dataChannel?.close();
    } catch (_) {}
    _dataChannel = null;
    try {
      await _fastChannel?.close();
    } catch (_) {}
    _fastChannel = null;
    if (DesktopInputRouter.isLeftButtonDown) {
      // Never leave the desktop stuck mid-drag when the phone drops off.
      DesktopInputRouter.leftClickUp();
    }

    _videoSenders.clear();
    if (_displayStream != null) {
      try {
        for (final track in _displayStream!.getTracks()) {
          await track.stop();
        }
        await _displayStream!.dispose();
      } catch (_) {}
      _displayStream = null;
    }

    try {
      await _peerConnection?.close();
    } catch (_) {}
    _peerConnection = null;
  }

  /// Keeps the Mac from idle-sleeping while the agent runs so the phone can
  /// always reach it; the display may still sleep and lock. `-w` ties the
  /// assertion to this process, so it ends if the agent quits or crashes.
  void _startKeepAwake() {
    if (kIsWeb || !Platform.isMacOS || _keepAwake != null) return;
    unawaited(() async {
      try {
        _keepAwake = await Process.start('caffeinate', ['-i', '-w', '$pid']);
      } catch (e) {
        debugPrint('[DesktopWebRTCResponder] keep-awake unavailable: $e');
      }
    }());
  }

  void _stopKeepAwake() {
    _keepAwake?.kill();
    _keepAwake = null;
  }

  Future<void> stop() async {
    _resubscribeTimer?.cancel();
    _resubscribeTimer = null;
    _stopKeepAwake();
    await _signalingSub?.cancel();
    _signalingSub = null;
    _deviceId = null;
    _activeSessionId = null;
    await _closePeerSession();
    state.value = const DesktopResponderSnapshot(
      status: DesktopResponderStatus.stopped,
    );
  }

  void dispose() {
    unawaited(stop());
    state.dispose();
  }
}
