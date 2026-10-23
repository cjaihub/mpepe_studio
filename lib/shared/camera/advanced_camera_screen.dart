import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class AdvancedCameraScreen extends ConsumerStatefulWidget {
  const AdvancedCameraScreen({super.key});

  @override
  ConsumerState<AdvancedCameraScreen> createState() => _AdvancedCameraScreenState();
}

class _AdvancedCameraScreenState extends ConsumerState<AdvancedCameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isRecording = false;
  int _selectedCameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        _setCamera(_selectedCameraIndex);
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: context.surface,
            title: Text('Permissions Required', style: TextStyle(color: context.textPrimary)),
            content: Text('Camera and microphone permissions are required to use this feature: $e', style: TextStyle(color: context.textSecondary)),
            actions: [
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('OK', style: TextStyle(color: AppColors.brandBlue)),
              )
            ],
          ),
        );
      }
    }
  }

  Future<void> _setCamera(int index) async {
    if (_controller != null) {
      await _controller!.dispose();
    }

    _controller = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: true,
    );

    try {
      await _controller!.initialize();
      await _controller!.setFlashMode(_flashMode);
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _selectedCameraIndex = index;
        });
      }
    } catch (e) {
      print('Camera init error: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _setCamera(_selectedCameraIndex);
    }
  }

  void _switchCamera() {
    if (_cameras.length < 2) return;
    final newIndex = (_selectedCameraIndex + 1) % _cameras.length;
    _setCamera(newIndex);
  }

  void _toggleFlash() async {
    if (_controller == null) return;
    final newMode = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    await _controller!.setFlashMode(newMode);
    setState(() {
      _flashMode = newMode;
    });
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized || _controller!.value.isTakingPicture) {
      return;
    }
    try {
      final file = await _controller!.takePicture();
      _showMediaPreview(file.path, isVideo: false);
    } catch (e) {
      print('Error taking picture: $e');
    }
  }

  Future<void> _startVideoRecording() async {
    if (_controller == null || !_controller!.value.isInitialized || _controller!.value.isRecordingVideo) {
      return;
    }
    try {
      await _controller!.startVideoRecording();
      setState(() {
        _isRecording = true;
      });
    } catch (e) {
      print('Error starting video: $e');
    }
  }

  Future<void> _stopVideoRecording() async {
    if (_controller == null || !_controller!.value.isRecordingVideo) {
      return;
    }
    try {
      final file = await _controller!.stopVideoRecording();
      setState(() {
        _isRecording = false;
      });
      _showMediaPreview(file.path, isVideo: true);
    } catch (e) {
      print('Error stopping video: $e');
    }
  }

  void _showMediaPreview(String path, {required bool isVideo}) {
    // For now, just a dialog confirming the media is captured.
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(isVideo ? 'Video Recorded' : 'Photo Captured', style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: context.textPrimary)),
        content: Text('Media saved at:\n$path', style: GoogleFonts.inter(color: context.textSecondary)),
        actions: [
          TextButton(
            onPressed: () {
              context.pop();
              context.pop(); // Go back to feed
            },
            child: const Text('Confirm', style: TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => context.pop(),
            child: Text('Discard', style: TextStyle(color: context.textMuted)),
          ),
        ],
      ),
    );
  }

  Future<bool> _onWillPop() async {
    if (_isRecording) {
      final shouldPop = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: context.surface,
          title: Text('Cancel Recording?', style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.bold)),
          content: Text('Are you sure you want to cancel the current recording?', style: GoogleFonts.inter(color: context.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => context.pop(false),
              child: Text('No', style: TextStyle(color: context.textMuted)),
            ),
            TextButton(
              onPressed: () => context.pop(true),
              child: const Text('Yes', style: TextStyle(color: AppColors.brandBlue)),
            ),
          ],
        ),
      );
      return shouldPop ?? false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isRecording,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final shouldPop = await _onWillPop();
        if (shouldPop) {
          navigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: Stack(
          children: [
            if (_isInitialized)
              Positioned.fill(
                child: CameraPreview(_controller!),
              )
            else
              const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),

            // Top Actions
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        onPressed: () async {
                          final navigator = Navigator.of(context);
                          if (await _onWillPop()) {
                            navigator.pop();
                          }
                        },
                      ),
                      IconButton(
                        icon: Icon(_flashMode == FlashMode.off ? Icons.flash_off : Icons.flash_on, color: Colors.white, size: 28),
                        onPressed: _toggleFlash,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom Controls
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.image, color: Colors.white, size: 28),
                          onPressed: () {},
                        ),
                        GestureDetector(
                          onTap: _takePicture,
                          onLongPress: _startVideoRecording,
                          onLongPressUp: _stopVideoRecording,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: _isRecording ? 100 : 80,
                            height: _isRecording ? 100 : 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: _isRecording ? 40 : 64,
                                height: _isRecording ? 40 : 64,
                                decoration: BoxDecoration(
                                  color: AppColors.brandBlue,
                                  borderRadius: BorderRadius.circular(_isRecording ? 8 : 40),
                                ),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.flip_camera_android, color: Colors.white, size: 28),
                          onPressed: _switchCamera,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Tap for photo, hold for video',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ).animate().fadeIn(duration: 400.ms),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
