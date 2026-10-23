import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../backend/remote_connect_service.dart';
import '../shared/theme/app_theme.dart';

class RemoteMonitorScreen extends ConsumerStatefulWidget {
  const RemoteMonitorScreen({super.key});

  @override
  ConsumerState<RemoteMonitorScreen> createState() => _RemoteMonitorScreenState();
}

class _RemoteMonitorScreenState extends ConsumerState<RemoteMonitorScreen> {
  RTCPeerConnection? _peerConnection;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final TransformationController _transformationController = TransformationController();
  Offset? _doubleTapPosition;
  StreamSubscription? _signalingSubscription;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _initRenderer();
    _createPeerConnection();
  }

  Future<void> _initRenderer() async {
    await _localRenderer.initialize();
  }

  Future<void> _createPeerConnection() async {
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    };

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'video') {
        _localRenderer.srcObject = event.streams[0];
        setState(() {
          _isConnected = true;
        });
      }
    };

    _peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('WebRTC state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed || 
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        if (mounted) {
          setState(() {
            _isConnected = false;
          });
        }
      }
    };

    final activeComputerId = ref.read(remoteConnectProvider).activeComputerId;
    if (activeComputerId == null) return;

    // Create Offer
    _peerConnection!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );

    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    // Send Offer via Firebase
    final signalingRef = FirebaseFirestore.instance
        .collection('registered_computers')
        .doc(activeComputerId)
        .collection('webrtc_signaling');

    await signalingRef.add({
      'type': 'offer',
      'sdp': offer.sdp,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Listen for Answer
    _signalingSubscription = signalingRef
        .where('type', isEqualTo: 'answer')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null && data['sdp'] != null) {
            final answer = RTCSessionDescription(data['sdp'], data['type']);
            _peerConnection?.setRemoteDescription(answer);
          }
        }
      }
    });
  }

  void _onDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.1) {
      _transformationController.value = Matrix4.identity();
    } else {
      final pos = _doubleTapPosition ?? Offset.zero;
      final x = -pos.dx * 1.5;
      final y = -pos.dy * 1.5;
      _transformationController.value = Matrix4.diagonal3Values(2.5, 2.5, 1.0)
        ..setTranslationRaw(x, y, 0.0);
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _signalingSubscription?.cancel();
    _localRenderer.dispose();
    _peerConnection?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        elevation: 0,
        title: Text(
          'Screen Monitor',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: Center(
        child: _isConnected
            ? GestureDetector(
                onDoubleTapDown: (d) => _doubleTapPosition = d.localPosition,
                onDoubleTap: _onDoubleTap,
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 0.8,
                  maxScale: 5.0,
                  boundaryMargin: const EdgeInsets.all(100),
                  child: Center(
                    child: RTCVideoView(
                      _localRenderer,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                    ),
                  ),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: AppColors.brandBlue),
                  const SizedBox(height: 16),
                  Text(
                    'Connecting to desktop...',
                    style: GoogleFonts.inter(color: Colors.white70),
                  ),
                ],
              ),
      ),
    );
  }
}
