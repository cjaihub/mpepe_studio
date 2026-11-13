import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'ice_servers.dart';

enum WebRTCStatus { disconnected, connecting, connected, error }

class WebRTCConnection {
  final WebRTCStatus status;
  final RTCVideoRenderer? renderer;
  final RTCPeerConnection? peerConnection;
  final RTCDataChannel? dataChannel;
  final String? errorMessage;
  final bool hasVideoStream;
  final bool isDataChannelOpen;
  final int reconnectAttempt;

  WebRTCConnection({
    this.status = WebRTCStatus.disconnected,
    this.renderer,
    this.peerConnection,
    this.dataChannel,
    this.errorMessage,
    this.hasVideoStream = false,
    this.isDataChannelOpen = false,
    this.reconnectAttempt = 0,
  });

  WebRTCConnection copyWith({
    WebRTCStatus? status,
    RTCVideoRenderer? renderer,
    RTCPeerConnection? peerConnection,
    RTCDataChannel? dataChannel,
    String? errorMessage,
    bool? hasVideoStream,
    bool? isDataChannelOpen,
    int? reconnectAttempt,
  }) {
    return WebRTCConnection(
      status: status ?? this.status,
      renderer: renderer ?? this.renderer,
      peerConnection: peerConnection ?? this.peerConnection,
      dataChannel: dataChannel ?? this.dataChannel,
      errorMessage: errorMessage ?? this.errorMessage,
      hasVideoStream: hasVideoStream ?? this.hasVideoStream,
      isDataChannelOpen: isDataChannelOpen ?? this.isDataChannelOpen,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
    );
  }
}

class WebRTCDesktopState {
  final Map<String, WebRTCConnection> connections;

  WebRTCDesktopState({this.connections = const {}});

  WebRTCDesktopState copyWith({
    Map<String, WebRTCConnection>? connections,
  }) {
    return WebRTCDesktopState(
      connections: connections ?? this.connections,
    );
  }
}

class WebRTCDesktopService extends Notifier<WebRTCDesktopState> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _signalingSubs = {};
  final Map<String, Timer> _connectTimeoutTimers = {};
  final Map<String, Timer> _reconnectTimers = {};
  final Set<String> _manualDisconnects = {};

  /// Signaling session of the latest attempt per device, so its offer and
  /// ICE docs can be removed when the next attempt starts or on disconnect.
  final Map<String, String> _sessionIds = {};

  /// How long to wait for the desktop's answer. The desktop polls Firestore
  /// (up to ~3 s when idle) and may start screen capture before answering.
  static const _answerTimeout = Duration(seconds: 20);

  /// Best-effort delete of one attempt's signaling docs. Leftover docs pile
  /// up and slow (or, on older desktop builds, hide) the next offer.
  void _cleanupSession(String deviceToken, String? sessionId) {
    if (sessionId == null) return;
    final ref = _firestore
        .collection('registered_computers')
        .doc(deviceToken)
        .collection('webrtc_signaling');
    unawaited(() async {
      try {
        final snap = await ref.where('session_id', isEqualTo: sessionId).get();
        for (final doc in snap.docs) {
          await doc.reference.delete();
        }
      } catch (e) {
        debugPrint('[WebRTC Client] signaling cleanup notice: $e');
      }
    }());
  }

  /// Screens that need the live link (connect page preview, control panel)
  /// hold it; it closes 20 s after the last one lets go, so opening the
  /// panel from the computer page is instant but nothing streams to nobody.
  final Map<String, int> _holders = {};
  final Map<String, Timer> _idleTimers = {};

  void hold(String deviceToken, {String mode = 'remote'}) {
    _holders[deviceToken] = (_holders[deviceToken] ?? 0) + 1;
    _idleTimers.remove(deviceToken)?.cancel();
    final c = state.connections[deviceToken];
    if (c == null ||
        c.status == WebRTCStatus.disconnected ||
        c.status == WebRTCStatus.error) {
      unawaited(connect(deviceToken, mode: mode));
    }
  }

  void release(String deviceToken) {
    final n = (_holders[deviceToken] ?? 1) - 1;
    if (n > 0) {
      _holders[deviceToken] = n;
      return;
    }
    _holders.remove(deviceToken);
    _idleTimers.remove(deviceToken)?.cancel();
    _idleTimers[deviceToken] = Timer(const Duration(seconds: 20), () {
      _idleTimers.remove(deviceToken);
      if (!_holders.containsKey(deviceToken)) disconnect(deviceToken);
    });
  }

  /// Session mode per device: `remote` (screen + input) or `controller`
  /// (phone-as-controller: input only, no screen capture on the desktop).
  final Map<String, String> _modes = {};

  /// Unordered, partially-reliable channel per device for high-rate pointer
  /// and scroll deltas. Clicks and media stay on the reliable channel.
  final Map<String, RTCDataChannel> _fastChannels = {};
  final StreamController<({String deviceToken, Map<String, dynamic> packet})>
      _incoming = StreamController.broadcast();

  /// Packets the desktop sends back (pong, volume state, ...).
  Stream<({String deviceToken, Map<String, dynamic> packet})> get incoming =>
      _incoming.stream;

  String modeOf(String deviceToken) => _modes[deviceToken] ?? 'remote';

  bool isFastChannelOpen(String deviceToken) =>
      _fastChannels[deviceToken]?.state == RTCDataChannelState.RTCDataChannelOpen;

  void _closeFastChannel(String deviceToken) {
    final fast = _fastChannels.remove(deviceToken);
    try {
      fast?.close();
    } catch (_) {}
  }

  void _onRawMessage(String deviceToken, RTCDataChannelMessage message) {
    if (message.isBinary) return;
    try {
      final decoded = jsonDecode(message.text);
      if (decoded is Map<String, dynamic>) {
        _incoming.add((deviceToken: deviceToken, packet: decoded));
      }
    } catch (_) {}
  }

  @override
  WebRTCDesktopState build() {
    ref.onDispose(() {
      disconnectAll();
      unawaited(_incoming.close());
    });
    return WebRTCDesktopState();
  }

  Future<void> forceReconnect(String deviceToken) async {
    _manualDisconnects.remove(deviceToken);
    _reconnectTimers.remove(deviceToken)?.cancel();
    _connectTimeoutTimers.remove(deviceToken)?.cancel();
    await _signalingSubs.remove(deviceToken)?.cancel();
    _closeFastChannel(deviceToken);
    _disposeConnectionResources(state.connections[deviceToken]);
    _updateConnection(deviceToken, WebRTCConnection(status: WebRTCStatus.disconnected));
    await connect(deviceToken, attempt: 0, mode: modeOf(deviceToken));
  }

  void _scheduleAutoReconnect(String deviceToken, int currentAttempt) {
    if (_manualDisconnects.contains(deviceToken)) return;
    if (currentAttempt >= 5) return;
    _reconnectTimers.remove(deviceToken)?.cancel();
    final delaySec = (2 << currentAttempt).clamp(2, 16);
    _reconnectTimers[deviceToken] = Timer(Duration(seconds: delaySec), () {
      if (_manualDisconnects.contains(deviceToken)) return;
      final current = state.connections[deviceToken];
      final controllerMode = modeOf(deviceToken) == 'controller';
      if (current?.status == WebRTCStatus.connected &&
          (current?.hasVideoStream == true ||
              (controllerMode && current?.isDataChannelOpen == true))) {
        return;
      }
      unawaited(connect(
        deviceToken,
        attempt: currentAttempt + 1,
        force: true,
        mode: modeOf(deviceToken),
      ));
    });
  }

  Future<void> connect(
    String deviceToken, {
    int attempt = 0,
    bool force = false,
    String mode = 'remote',
  }) async {
    _manualDisconnects.remove(deviceToken);
    final existing = state.connections[deviceToken];
    if (!force &&
        (existing?.status == WebRTCStatus.connecting ||
            existing?.status == WebRTCStatus.connected)) {
      return;
    }

    _connectTimeoutTimers.remove(deviceToken)?.cancel();
    _reconnectTimers.remove(deviceToken)?.cancel();
    await _signalingSubs.remove(deviceToken)?.cancel();
    _closeFastChannel(deviceToken);
    _disposeConnectionResources(existing);
    _modes[deviceToken] = mode;
    final controllerMode = mode == 'controller';

    _updateConnection(
      deviceToken,
      WebRTCConnection(
        status: WebRTCStatus.connecting,
        reconnectAttempt: attempt,
      ),
    );

    final sessionId = '${DateTime.now().microsecondsSinceEpoch}';
    _cleanupSession(deviceToken, _sessionIds[deviceToken]);
    _sessionIds[deviceToken] = sessionId;
    final deviceRef = _firestore.collection('registered_computers').doc(deviceToken);
    final signalingRef = deviceRef.collection('webrtc_signaling');

    try {
      final renderer = RTCVideoRenderer();
      await renderer.initialize();

      final peerConnection = await createPeerConnection({
        // STUN + short-lived TURN relay (works across different networks).
        'iceServers': await IceServers.resolve(() async {
          final res = await FirebaseFunctions.instance
              .httpsCallable('getIceServers')
              .call<Map<String, dynamic>>();
          return Map<String, dynamic>.from(res.data);
        }),
        'sdpSemantics': 'unified-plan',
      });

      final dcInit = RTCDataChannelInit()..ordered = true;
      final dataChannel = await peerConnection.createDataChannel('mouse_control', dcInit);
      dataChannel.onMessage = (m) => _onRawMessage(deviceToken, m);

      // Low-latency lane: unordered, packets expire after 60 ms instead of
      // queueing behind retransmits. Relative deltas tolerate the odd drop.
      final fastInit = RTCDataChannelInit()
        ..ordered = false
        ..maxRetransmitTime = 60;
      final fastChannel = await peerConnection.createDataChannel('pointer_fast', fastInit);
      _fastChannels[deviceToken] = fastChannel;

      dataChannel.onDataChannelState = (RTCDataChannelState dcState) {
        debugPrint('[WebRTC Client] DataChannel ($deviceToken) state: $dcState');
        final currentConn = state.connections[deviceToken];
        if (currentConn != null) {
          final isOpen = dcState == RTCDataChannelState.RTCDataChannelOpen;
          final nextStatus = isOpen ? WebRTCStatus.connected : currentConn.status;
          _updateConnection(
            deviceToken,
            currentConn.copyWith(
              dataChannel: dataChannel,
              isDataChannelOpen: isOpen,
              status: nextStatus,
            ),
          );
        }
      };

      _updateConnection(
        deviceToken,
        WebRTCConnection(
          status: WebRTCStatus.connecting,
          renderer: renderer,
          peerConnection: peerConnection,
          dataChannel: dataChannel,
          reconnectAttempt: attempt,
        ),
      );

      peerConnection.onDataChannel = (RTCDataChannel channel) {
        debugPrint('[WebRTC Client] Incoming remote DataChannel: ${channel.label}');
        channel.onDataChannelState = (RTCDataChannelState s) {
          final currentConn = state.connections[deviceToken];
          if (currentConn != null) {
            _updateConnection(
              deviceToken,
              currentConn.copyWith(
                dataChannel: channel,
                isDataChannelOpen: s == RTCDataChannelState.RTCDataChannelOpen,
              ),
            );
          }
        };
        final currentConn = state.connections[deviceToken];
        if (currentConn != null) {
          _updateConnection(deviceToken, currentConn.copyWith(dataChannel: channel));
        }
      };

      peerConnection.onTrack = (RTCTrackEvent event) {
        if (event.track.kind == 'video') {
          if (event.streams.isNotEmpty) {
            renderer.srcObject = event.streams.first;
          }
          _connectTimeoutTimers.remove(deviceToken)?.cancel();
          final currentConn = state.connections[deviceToken];
          if (currentConn != null) {
            _updateConnection(
              deviceToken,
              currentConn.copyWith(
                renderer: renderer,
                hasVideoStream: true,
                status: WebRTCStatus.connected,
                reconnectAttempt: 0,
              ),
            );
          }
        }
      };

      peerConnection.onAddTrack = (stream, track) {
        if (track.kind == 'video') {
          renderer.srcObject = stream;
          _connectTimeoutTimers.remove(deviceToken)?.cancel();
          final currentConn = state.connections[deviceToken];
          if (currentConn != null) {
            _updateConnection(
              deviceToken,
              currentConn.copyWith(
                renderer: renderer,
                hasVideoStream: true,
                status: WebRTCStatus.connected,
                reconnectAttempt: 0,
              ),
            );
          }
        }
      };

      peerConnection.onIceCandidate = (RTCIceCandidate candidate) {
        final candStr = candidate.candidate;
        if (candStr == null || candStr.isEmpty) return;
        unawaited(
          signalingRef
              .add({
                'type': 'caller_candidate',
                'session_id': sessionId,
                'candidate': candStr,
                'sdpMid': candidate.sdpMid,
                'sdpMLineIndex': candidate.sdpMLineIndex,
                'timestamp': FieldValue.serverTimestamp(),
              })
              .then((_) {})
              .catchError((Object e) {
                debugPrint('[WebRTC Client] ICE candidate publish notice: $e');
              }),
        );
      };

      peerConnection.onConnectionState = (RTCPeerConnectionState pcState) {
        final currentConn = state.connections[deviceToken];
        if (currentConn == null) return;
        if (pcState == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _connectTimeoutTimers.remove(deviceToken)?.cancel();
          _updateConnection(
            deviceToken,
            currentConn.copyWith(status: WebRTCStatus.connected, reconnectAttempt: 0),
          );
        } else if (pcState == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            pcState == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _updateConnection(
            deviceToken,
            currentConn.copyWith(
              status: WebRTCStatus.disconnected,
              hasVideoStream: false,
              isDataChannelOpen: false,
            ),
          );
          _scheduleAutoReconnect(deviceToken, attempt);
        } else if (pcState == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _updateConnection(
            deviceToken,
            currentConn.copyWith(
              status: WebRTCStatus.disconnected,
              hasVideoStream: false,
              isDataChannelOpen: false,
            ),
          );
        }
      };

      if (!controllerMode) {
        await peerConnection.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
      }

      bool remoteDescSet = false;
      final queuedCandidates = <RTCIceCandidate>[];
      final seenDocs = <String>{};

      _signalingSubs[deviceToken] = signalingRef.snapshots().listen((snapshot) async {
        for (final change in snapshot.docChanges) {
          if (change.type != DocumentChangeType.added) continue;
          if (!seenDocs.add(change.doc.id)) continue;

          final data = change.doc.data();
          if (data == null) continue;
          final docSession = data['session_id'] as String?;
          if (docSession != null && docSession != sessionId) continue;

          final type = data['type'] as String?;
          final currentPc = state.connections[deviceToken]?.peerConnection;
          if (currentPc == null) continue;

          if (type == 'answer' && !remoteDescSet) {
            final sdp = data['sdp'] as String?;
            if (sdp != null &&
                currentPc.signalingState != RTCSignalingState.RTCSignalingStateStable) {
              await currentPc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
              remoteDescSet = true;
              for (final c in queuedCandidates) {
                try {
                  await currentPc.addCandidate(c);
                } catch (_) {}
              }
              queuedCandidates.clear();
            }
          } else if (type == 'callee_candidate') {
            final candStr = data['candidate'] as String?;
            if (candStr != null && candStr.isNotEmpty) {
              final cand = RTCIceCandidate(
                candStr,
                data['sdpMid'] as String?,
                (data['sdpMLineIndex'] as num?)?.toInt(),
              );
              if (remoteDescSet) {
                try {
                  await currentPc.addCandidate(cand);
                } catch (_) {}
              } else {
                queuedCandidates.add(cand);
              }
            }
          }
        }
      });

      final offer = await peerConnection.createOffer();
      await peerConnection.setLocalDescription(offer);

      await signalingRef.add({
        'type': offer.type,
        'session_id': sessionId,
        'mode': mode,
        'sdp': offer.sdp,
        'timestamp': FieldValue.serverTimestamp(),
      });

      _connectTimeoutTimers[deviceToken] = Timer(_answerTimeout, () {
        final current = state.connections[deviceToken];
        if (current != null && current.status == WebRTCStatus.connecting) {
          _updateConnection(
            deviceToken,
            current.copyWith(
              status: WebRTCStatus.disconnected,
              errorMessage: 'Direct peer signaling timed out; using Cloud Frame Bridge.',
            ),
          );
          _scheduleAutoReconnect(deviceToken, attempt);
        }
      });
    } catch (e) {
      debugPrint('WebRTC Error: $e');
      _updateConnection(
        deviceToken,
        WebRTCConnection(
          status: WebRTCStatus.error,
          errorMessage: e.toString(),
          reconnectAttempt: attempt,
        ),
      );
      _scheduleAutoReconnect(deviceToken, attempt);
    }
  }

  bool sendControlPacket(String deviceToken, Map<String, dynamic> packet) {
    final connection = state.connections[deviceToken];
    final dc = connection?.dataChannel;
    if (dc != null && dc.state == RTCDataChannelState.RTCDataChannelOpen) {
      try {
        dc.send(RTCDataChannelMessage(jsonEncode(packet)));
        return true;
      } catch (e) {
        debugPrint('[WebRTC Client] Error sending data channel message: $e');
      }
    }
    return false;
  }

  /// Sends a high-rate packet (pointer / scroll deltas) on the unordered
  /// lane, falling back to the reliable channel when it is not open.
  bool sendFastPacket(String deviceToken, Map<String, dynamic> packet) {
    final fast = _fastChannels[deviceToken];
    if (fast != null && fast.state == RTCDataChannelState.RTCDataChannelOpen) {
      try {
        fast.send(RTCDataChannelMessage(jsonEncode(packet)));
        return true;
      } catch (_) {}
    }
    return sendControlPacket(deviceToken, packet);
  }

  void _updateConnection(String deviceToken, WebRTCConnection connection) {
    final updatedMap = Map<String, WebRTCConnection>.from(state.connections);
    updatedMap[deviceToken] = connection;
    state = state.copyWith(connections: updatedMap);
  }

  void _disposeConnectionResources(WebRTCConnection? connection) {
    if (connection == null) return;
    try {
      connection.dataChannel?.close();
    } catch (_) {}
    try {
      connection.peerConnection?.close();
    } catch (_) {}
    try {
      connection.renderer?.srcObject = null;
      connection.renderer?.dispose();
    } catch (_) {}
  }

  void disconnect(String deviceToken) {
    _manualDisconnects.add(deviceToken);
    _cleanupSession(deviceToken, _sessionIds.remove(deviceToken));
    _connectTimeoutTimers.remove(deviceToken)?.cancel();
    _reconnectTimers.remove(deviceToken)?.cancel();
    unawaited(_signalingSubs.remove(deviceToken)?.cancel());
    _closeFastChannel(deviceToken);
    _disposeConnectionResources(state.connections[deviceToken]);

    final updatedMap = Map<String, WebRTCConnection>.from(state.connections);
    updatedMap.remove(deviceToken);
    state = state.copyWith(connections: updatedMap);
  }

  void disconnectAll() {
    for (final timer in _connectTimeoutTimers.values) {
      timer.cancel();
    }
    _connectTimeoutTimers.clear();
    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    _reconnectTimers.clear();
    for (final sub in _signalingSubs.values) {
      unawaited(sub.cancel());
    }
    _signalingSubs.clear();
    for (final token in _fastChannels.keys.toList()) {
      _closeFastChannel(token);
    }
    state.connections.forEach((key, connection) {
      _disposeConnectionResources(connection);
    });
    state = WebRTCDesktopState();
  }
}

final webrtcDesktopProvider = NotifierProvider<WebRTCDesktopService, WebRTCDesktopState>(() {
  return WebRTCDesktopService();
});
