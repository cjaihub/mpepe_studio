import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../desktop_agent/macos_mouse_ffi.dart';

final webrtcDesktopHostProvider =
    NotifierProvider<WebRTCDesktopHostNotifier, WebRTCDesktopHostState>(() {
  return WebRTCDesktopHostNotifier();
});

class WebRTCDesktopHostState {
  final bool isStreaming;
  final String? errorMessage;
  WebRTCDesktopHostState({this.isStreaming = false, this.errorMessage});

  WebRTCDesktopHostState copyWith({bool? isStreaming, String? errorMessage}) {
    return WebRTCDesktopHostState(
      isStreaming: isStreaming ?? this.isStreaming,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class WebRTCDesktopHostNotifier extends Notifier<WebRTCDesktopHostState> {
  @override
  WebRTCDesktopHostState build() {
    return WebRTCDesktopHostState();
  }

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  StreamSubscription? _signalingSubscription;
  CollectionReference? _signalingRef;

  Future<void> startListening(CollectionReference signalingRef) async {
    await stop();
    _signalingRef = signalingRef;
    
    // Listen for incoming offers from the mobile client
    _signalingSubscription = _signalingRef!.snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>?;
          if (data == null) continue;

          // Ignore our own messages
          if (data['origin'] == 'desktop') continue;

          final type = data['type'];
          if (type == 'offer') {
            _handleOffer(data, change.doc.id);
          } else if (type == 'candidate' && _peerConnection != null) {
            _handleRemoteCandidate(data);
          }
        }
      }
    });
  }

  Future<void> _handleOffer(Map<String, dynamic> offerData, String docId) async {
    try {
      debugPrint('[WebRTC Host] Processing incoming offer...');
      
      final configuration = {
        'iceServers': [
          {'url': 'stun:stun.l.google.com:19302'},
          {'url': 'stun:stun1.l.google.com:19302'},
        ]
      };

      _peerConnection = await createPeerConnection(configuration);

      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        _signalingRef?.add({
          'type': 'candidate',
          'origin': 'desktop',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'timestamp': FieldValue.serverTimestamp(),
        });
      };

      _peerConnection!.onConnectionState = (RTCPeerConnectionState connectionState) {
        debugPrint('[WebRTC Host] Connection state change: \$connectionState');
        if (connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          state = state.copyWith(isStreaming: true, errorMessage: null);
        } else if (connectionState == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
                   connectionState == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          stop();
        }
      };

      _peerConnection!.onDataChannel = (RTCDataChannel channel) {
        debugPrint('[WebRTC Host] Data channel received: \${channel.label}');
        if (channel.label == 'mouse_control') {
          channel.onMessage = (RTCDataChannelMessage message) {
            _handleMouseControlMessage(message.text);
          };
        }
      };

      // Capture desktop screen with strict constraints to prevent CPU overload and overheating
      final mediaConstraints = <String, dynamic>{
        'audio': false,
        'video': {
          'mandatory': {
            'minWidth': '1280',
            'minHeight': '720',
            'maxWidth': '1920', // Cap resolution at 1080p
            'maxHeight': '1080',
            'minFrameRate': '15',
            'maxFrameRate': '30', // Cap at 30 FPS
          },
          'optional': []
        }
      };

      try {
        _localStream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
        for (final track in _localStream!.getTracks()) {
          await _peerConnection!.addTrack(track, _localStream!);
        }
      } catch (e) {
        debugPrint('[WebRTC Host] Failed to get display media: \$e');
        state = state.copyWith(errorMessage: 'Failed to capture screen: \$e');
        return;
      }

      // Set remote description
      final sdp = offerData['sdp'];
      final type = offerData['type'];
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(sdp, type),
      );

      // Create answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      // Send answer back to mobile
      await _signalingRef?.add({
        'type': 'answer',
        'origin': 'desktop',
        'sdp': answer.sdp,
        'timestamp': FieldValue.serverTimestamp(),
      });
      
      debugPrint('[WebRTC Host] Answer sent.');

    } catch (e) {
      debugPrint('[WebRTC Host] Error handling offer: \$e');
      state = state.copyWith(errorMessage: e.toString());
      stop();
    }
  }

  Future<void> _handleRemoteCandidate(Map<String, dynamic> candidateData) async {
    try {
      final candidate = RTCIceCandidate(
        candidateData['candidate'],
        candidateData['sdpMid'],
        candidateData['sdpMLineIndex'],
      );
      await _peerConnection?.addCandidate(candidate);
    } catch (e) {
      debugPrint('[WebRTC Host] Failed to add remote candidate: \$e');
    }
  }

  void _handleMouseControlMessage(String text) {
    try {
      final payload = jsonDecode(text) as Map<String, dynamic>;
      final action = payload['action'];

      switch (action) {
        case 'mouse_move':
          final dx = payload['dx']?.toDouble() ?? 0.0;
          final dy = payload['dy']?.toDouble() ?? 0.0;
          MacOSMouseController.moveBy(dx, dy);
          break;
        case 'mouse_scroll':
          final dy = payload['dy']?.toDouble() ?? 0.0;
          MacOSMouseController.scroll(dy);
          break;
        case 'mouse_left_click':
          MacOSMouseController.click();
          break;
        case 'mouse_right_click':
          MacOSMouseController.rightClick();
          break;
        case 'mouse_double_click':
          MacOSMouseController.doubleClick();
          break;
        case 'mouse_left_down':
          MacOSMouseController.leftClickDown();
          break;
        case 'mouse_left_up':
          MacOSMouseController.leftClickUp();
          break;
        case 'key_tap':
          final key = payload['key']?.toString() ?? '';
          MacOSMouseController.tapKey(key);
          break;
        case 'key_combination':
          final combo = payload['combo']?.toString() ?? '';
          MacOSMouseController.sendHotkey(combo);
          break;
        case 'type_text':
          final textStr = payload['text']?.toString() ?? '';
          MacOSMouseController.typeString(textStr);
          break;
        case 'wake_and_unlock':
          final passkey = payload['passkey']?.toString() ?? '';
          MacOSMouseController.wakeAndUnlock(passkey);
          break;
        default:
          debugPrint('[WebRTC Host] Unknown mouse/control action: $action');
      }
    } catch (e) {
      debugPrint('[WebRTC Host] Error parsing mouse message: $e');
    }
  }

  Future<void> stop() async {
    _signalingSubscription?.cancel();
    _signalingSubscription = null;
    
    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }
    
    if (_peerConnection != null) {
      await _peerConnection!.close();
      await _peerConnection!.dispose();
      _peerConnection = null;
    }

    _signalingRef = null;
    
    state = WebRTCDesktopHostState(isStreaming: false);
  }
}
