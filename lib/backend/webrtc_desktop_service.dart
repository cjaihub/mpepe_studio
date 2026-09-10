import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum WebRTCStatus { disconnected, connecting, connected, error }

class WebRTCConnection {
  final WebRTCStatus status;
  final RTCVideoRenderer? renderer;
  final RTCPeerConnection? peerConnection;
  final String? errorMessage;

  WebRTCConnection({
    this.status = WebRTCStatus.disconnected,
    this.renderer,
    this.peerConnection,
    this.errorMessage,
  });

  WebRTCConnection copyWith({
    WebRTCStatus? status,
    RTCVideoRenderer? renderer,
    RTCPeerConnection? peerConnection,
    String? errorMessage,
  }) {
    return WebRTCConnection(
      status: status ?? this.status,
      renderer: renderer ?? this.renderer,
      peerConnection: peerConnection ?? this.peerConnection,
      errorMessage: errorMessage ?? this.errorMessage,
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

  @override
  WebRTCDesktopState build() {
    return WebRTCDesktopState();
  }

  Future<void> connect(String deviceToken) async {
    if (state.connections[deviceToken]?.status == WebRTCStatus.connecting || 
        state.connections[deviceToken]?.status == WebRTCStatus.connected) {
      return;
    }

    _updateConnection(deviceToken, WebRTCConnection(status: WebRTCStatus.connecting));

    try {
      final renderer = RTCVideoRenderer();
      await renderer.initialize();

      final peerConnection = await createPeerConnection({
        'iceServers': [
          {'url': 'stun:stun.l.google.com:19302'},
        ]
      });

      _updateConnection(deviceToken, WebRTCConnection(
        status: WebRTCStatus.connecting,
        renderer: renderer,
        peerConnection: peerConnection
      ));

      peerConnection.onAddTrack = (stream, track) {
        if (track.kind == 'video') {
          renderer.srcObject = stream;
          _updateConnection(deviceToken, state.connections[deviceToken]!.copyWith(renderer: renderer));
        }
      };

      peerConnection.onConnectionState = (RTCPeerConnectionState pcState) {
        if (pcState == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _updateConnection(deviceToken, state.connections[deviceToken]!.copyWith(status: WebRTCStatus.connected));
        } else if (pcState == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
                   pcState == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _updateConnection(deviceToken, state.connections[deviceToken]!.copyWith(status: WebRTCStatus.disconnected));
        }
      };

      await peerConnection.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly)
      );

      RTCSessionDescription offer = await peerConnection.createOffer();
      await peerConnection.setLocalDescription(offer);

      final deviceRef = _firestore.collection('registered_computers').doc(deviceToken);
      
      await deviceRef.collection('webrtc_signaling').add({
        'type': offer.type,
        'sdp': offer.sdp,
        'timestamp': FieldValue.serverTimestamp(),
      });

      deviceRef.collection('webrtc_signaling').snapshots().listen((snapshot) async {
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final data = change.doc.data();
            if (data != null && data['type'] == 'answer') {
              final answer = RTCSessionDescription(data['sdp'], data['type']);
              final currentPc = state.connections[deviceToken]?.peerConnection;
              if (currentPc != null && currentPc.signalingState != RTCSignalingState.RTCSignalingStateStable) {
                await currentPc.setRemoteDescription(answer);
              }
            }
          }
        }
      });
      
    } catch (e) {
      debugPrint('WebRTC Error: $e');
      _updateConnection(deviceToken, WebRTCConnection(status: WebRTCStatus.error, errorMessage: e.toString()));
    }
  }

  void _updateConnection(String deviceToken, WebRTCConnection connection) {
    final updatedMap = Map<String, WebRTCConnection>.from(state.connections);
    updatedMap[deviceToken] = connection;
    state = state.copyWith(connections: updatedMap);
  }

  void disconnect(String deviceToken) {
    final connection = state.connections[deviceToken];
    connection?.peerConnection?.close();
    connection?.renderer?.dispose();

    final updatedMap = Map<String, WebRTCConnection>.from(state.connections);
    updatedMap.remove(deviceToken);
    state = state.copyWith(connections: updatedMap);
  }

  void disconnectAll() {
    state.connections.forEach((key, connection) {
      connection.peerConnection?.close();
      connection.renderer?.dispose();
    });
    state = WebRTCDesktopState();
  }
}

final webrtcDesktopProvider = NotifierProvider<WebRTCDesktopService, WebRTCDesktopState>(() {
  return WebRTCDesktopService();
});
