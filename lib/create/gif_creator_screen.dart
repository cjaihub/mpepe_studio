import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../shared/theme/app_theme.dart';
import '../backend/storage_service.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

// ──────────────────────────────────────────────────────────────────────────────
// State Machine
// ──────────────────────────────────────────────────────────────────────────────
enum GifCreatorState { camera, capturing, preview, encoding, uploading, done }

enum GifSpeed { slow, normal, fast }

extension GifSpeedExtension on GifSpeed {
  int get delayMs {
    switch (this) {
      case GifSpeed.slow:
        return 150;
      case GifSpeed.normal:
        return 100;
      case GifSpeed.fast:
        return 50;
    }
  }

  String get label {
    switch (this) {
      case GifSpeed.slow:
        return 'Slow';
      case GifSpeed.normal:
        return 'Normal';
      case GifSpeed.fast:
        return 'Fast';
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Isolate Encoder
// ──────────────────────────────────────────────────────────────────────────────
Future<Uint8List> _encodeGif(List<String> imagePaths, int frameDelay) async {
  return compute(_encodeGifInIsolate, {'paths': imagePaths, 'delay': frameDelay});
}

Uint8List _encodeGifInIsolate(Map<String, dynamic> args) {
  final paths = args['paths'] as List<dynamic>;
  final delay = args['delay'] as int;

  img.Image? animation;
  for (final path in paths) {
    final bytes = File(path as String).readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image != null) {
      final resized = img.copyResize(image, width: 480);
      if (animation == null) {
        animation = resized;
      } else {
        animation.addFrame(resized);
      }
    }
  }
  
  if (animation != null) {
    for (var f in animation.frames) {
      // image package expects frameDuration in ms
      f.frameDuration = delay;
    }
    return Uint8List.fromList(img.encodeGif(animation));
  }
  return Uint8List(0);
}

// ──────────────────────────────────────────────────────────────────────────────
// Screen
// ──────────────────────────────────────────────────────────────────────────────
class GifCreatorScreen extends ConsumerStatefulWidget {
  final Function(String gifUrl)? onGifCreated;

  const GifCreatorScreen({super.key, this.onGifCreated});

  @override
  ConsumerState<GifCreatorScreen> createState() => _GifCreatorScreenState();
}

class _GifCreatorScreenState extends ConsumerState<GifCreatorScreen>
    with TickerProviderStateMixin {
  // Camera
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _cameraReady = false;
  bool _isFrontCamera = false;

  // State
  GifCreatorState _state = GifCreatorState.camera;
  final int _totalFrames = 6;
  int _capturedFrames = 0;
  List<String> _framePaths = [];

  // Preview
  int _previewFrameIndex = 0;
  Timer? _previewTimer;
  GifSpeed _speed = GifSpeed.normal;

  // Upload
  double _uploadProgress = 0.0;
  String? _gifUrl;
  Uint8List? _gifBytes;

  // Animations
  late AnimationController _captureButtonPulse;
  late AnimationController _frameCounterPop;

  @override
  void initState() {
    super.initState();
    _captureButtonPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _frameCounterPop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      await _setupCamera(_cameras[0]);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _setupCamera(CameraDescription description) async {
    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _cameraController = controller;
    try {
      await controller.initialize();
      if (mounted) {
        setState(() => _cameraReady = true);
      }
    } catch (e) {
      debugPrint('Camera setup error: $e');
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2) return;
    setState(() {
      _cameraReady = false;
      _isFrontCamera = !_isFrontCamera;
    });
    await _cameraController?.dispose();
    await _setupCamera(
      _isFrontCamera ? _cameras[1] : _cameras[0],
    );
  }

  Future<void> _startBurstCapture() async {
    if (_state != GifCreatorState.camera) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    HapticFeedback.mediumImpact();

    setState(() {
      _state = GifCreatorState.capturing;
      _capturedFrames = 0;
      _framePaths = [];
    });

    final dir = await getTemporaryDirectory();
    for (int i = 0; i < _totalFrames; i++) {
      if (!mounted) return;
      try {
        final file = await _cameraController!.takePicture();
        final savedPath = '${dir.path}/gif_frame_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(file.path).copy(savedPath);
        setState(() {
          _capturedFrames = i + 1;
          _framePaths.add(savedPath);
        });
        // Pop animation on frame count update
        _frameCounterPop.forward(from: 0);
        HapticFeedback.lightImpact();
        if (i < _totalFrames - 1) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      } catch (e) {
        debugPrint('Frame capture error: $e');
      }
    }

    if (mounted && _framePaths.isNotEmpty) {
      setState(() => _state = GifCreatorState.preview);
      _startPreviewAnimation();
    }
  }

  void _startPreviewAnimation() {
    _previewTimer?.cancel();
    _previewTimer = Timer.periodic(
      Duration(milliseconds: _speed.delayMs + 50),
      (_) {
        if (mounted && _framePaths.isNotEmpty) {
          setState(() {
            _previewFrameIndex = (_previewFrameIndex + 1) % _framePaths.length;
          });
        }
      },
    );
  }

  void _changeSpeed(GifSpeed speed) {
    setState(() => _speed = speed);
    _previewTimer?.cancel();
    _startPreviewAnimation();
  }

  Future<void> _retake() async {
    _previewTimer?.cancel();
    for (final path in _framePaths) {
      try { File(path).deleteSync(); } catch (_) {}
    }
    setState(() {
      _framePaths = [];
      _capturedFrames = 0;
      _previewFrameIndex = 0;
      _state = GifCreatorState.camera;
    });
  }

  Future<void> _createAndShare() async {
    if (_framePaths.isEmpty) return;
    _previewTimer?.cancel();
    setState(() => _state = GifCreatorState.encoding);

    try {
      final gifBytes = await _encodeGif(_framePaths, _speed.delayMs);
      _gifBytes = gifBytes;

      setState(() => _state = GifCreatorState.uploading);

      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      final path = 'gifs/${DateTime.now().millisecondsSinceEpoch}_$uid.gif';

      final storageService = ref.read(storageServiceProvider);
      final url = await storageService.uploadBytes(
        gifBytes, path
      );

      if (mounted) {
        setState(() {
          _gifUrl = url;
          _state = GifCreatorState.done;
        });
      }
    } catch (e) {
      debugPrint('GIF encode/upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating GIF: $e',
                style: GoogleFonts.inter(color: Colors.white)),
            backgroundColor: Colors.red[900],
          ),
        );
        setState(() => _state = GifCreatorState.preview);
        _startPreviewAnimation();
      }
    }
  }

  Future<void> _shareGif() async {
    if (_gifUrl == null && _gifBytes == null) return;
    try {
      if (_gifBytes != null) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/oneova_gif.gif');
        await file.writeAsBytes(_gifBytes!);
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Created with Oneova 🎬'));
      } else if (_gifUrl != null) {
        await SharePlus.instance.share(ShareParams(text: _gifUrl!));
      }
    } catch (e) {
      debugPrint('Share error: $e');
    }
  }

  void _onGifCreated() {
    if (_gifUrl != null) {
      widget.onGifCreated?.call(_gifUrl!);
      if (mounted) context.pop();
    }
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _captureButtonPulse.dispose();
    _frameCounterPop.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: _buildCurrentState(),
      ),
    );
  }

  Widget _buildCurrentState() {
    switch (_state) {
      case GifCreatorState.camera:
      case GifCreatorState.capturing:
        return _buildCameraView();
      case GifCreatorState.preview:
        return _buildPreviewView();
      case GifCreatorState.encoding:
        return _buildEncodingView();
      case GifCreatorState.uploading:
        return _buildUploadingView();
      case GifCreatorState.done:
        return _buildDoneView();
    }
  }

  // ─── Camera View ─────────────────────────────────────────────────────────

  Widget _buildCameraView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        if (_cameraReady && _cameraController != null)
          CameraPreview(_cameraController!)
        else
          Container(
            color: AppColors.darkBackground,
            child: const Center(
              child: AnimatedLoadingIndicator(color: AppColors.brandBlue),
            ),
          ),

        // Top bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildTopBar(),
        ),

        // Bottom controls
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildBottomControls(),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          // Back button
          _buildCircleButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => context.pop(),
          ),
          const Spacer(),
          // Title
          Text(
            'Create GIF',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          // Flip camera
          _buildCircleButton(
            icon: Icons.flip_camera_ios_outlined,
            onTap: _cameras.length > 1 ? _flipCamera : null,
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _buildBottomControls() {
    final isCapturing = _state == GifCreatorState.capturing;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Frame counter
          AnimatedBuilder(
            animation: _frameCounterPop,
            builder: (context, child) {
              final scale = 1.0 + (_frameCounterPop.value * 0.25);
              return Transform.scale(scale: scale, child: child);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isCapturing ? AppColors.brandBlue : Colors.black54,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isCapturing ? AppColors.brandBlue : Colors.white30,
                  width: 1.5,
                ),
              ),
              child: Text(
                '$_capturedFrames/$_totalFrames frames',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Capture button
          GestureDetector(
            onTap: isCapturing ? null : _startBurstCapture,
            child: AnimatedBuilder(
              animation: _captureButtonPulse,
              builder: (context, child) {
                final scale = isCapturing
                    ? 1.0 + (_captureButtonPulse.value * 0.08)
                    : 1.0;
                return Transform.scale(scale: scale, child: child);
              },
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCapturing ? AppColors.brandBlue : Colors.transparent,
                  border: Border.all(
                    color: isCapturing ? AppColors.brandBlue : Colors.white,
                    width: isCapturing ? 3 : 4,
                  ),
                  boxShadow: isCapturing
                      ? [
                          BoxShadow(
                            color: AppColors.brandBlue.withValues(alpha: 0.5),
                            blurRadius: 20,
                            spreadRadius: 4,
                          )
                        ]
                      : null,
                ),
                child: Center(
                  child: Container(
                    width: isCapturing ? 32 : 64,
                    height: isCapturing ? 32 : 64,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.brandBlue,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Label
          Text(
            isCapturing ? 'Capturing...' : 'Tap to capture burst',
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Preview View ─────────────────────────────────────────────────────────

  Widget _buildPreviewView() {
    return Column(
      children: [
        // Top bar
        _buildPreviewTopBar(),

        // Animated preview
        Expanded(
          child: _framePaths.isNotEmpty
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(_framePaths[_previewFrameIndex]),
                      fit: BoxFit.contain,
                    ),
                    // GIF label badge
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.brandBlue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'GIF',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),

        // Thumbnail strip
        _buildThumbnailStrip(),

        // Speed selector
        _buildSpeedSelector(),

        // Action buttons
        _buildPreviewActions(),
      ],
    );
  }

  Widget _buildPreviewTopBar() {
    return Container(
      color: AppColors.darkBackground,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: _retake,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white12),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Preview GIF',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailStrip() {
    return Container(
      height: 72,
      color: AppColors.darkSurface,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _framePaths.length,
        itemBuilder: (context, i) {
          final isSelected = i == _previewFrameIndex;
          return GestureDetector(
            onTap: () => setState(() => _previewFrameIndex = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? AppColors.brandBlue : Colors.white12,
                  width: isSelected ? 2.5 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.brandBlue.withValues(alpha: 0.35),
                          blurRadius: 8,
                        )
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(_framePaths[i]),
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSpeedSelector() {
    return Container(
      color: AppColors.darkBackground,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: GifSpeed.values.map((s) {
          final isSelected = _speed == s;
          return GestureDetector(
            onTap: () => _changeSpeed(s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.brandBlue : AppColors.darkSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppColors.brandBlue : Colors.white24,
                  width: 1.5,
                ),
              ),
              child: Text(
                s.label,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPreviewActions() {
    return Container(
      color: AppColors.darkBackground,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Row(
        children: [
          // Retake
          Expanded(
            child: _buildOutlineButton(
              label: 'Retake',
              icon: Icons.refresh_rounded,
              onTap: _retake,
            ),
          ),
          const SizedBox(width: 12),
          // Create & Share
          Expanded(
            flex: 2,
            child: _buildFilledButton(
              label: 'Create & Share',
              icon: Icons.auto_awesome_rounded,
              onTap: _createAndShare,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Encoding View ────────────────────────────────────────────────────────

  Widget _buildEncodingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandBlue.withValues(alpha: 0.3),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: const Center(
              child: AnimatedLoadingIndicator(
                color: AppColors.brandBlue,
                strokeWidth: 3,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Encoding GIF...',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Processing ${_framePaths.length} frames',
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Uploading View ───────────────────────────────────────────────────────

  Widget _buildUploadingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated upload icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandBlue.withValues(alpha: 0.25),
                    blurRadius: 25,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.cloud_upload_rounded,
                color: AppColors.brandBlue,
                size: 42,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Uploading GIF',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_uploadProgress * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.inter(
                color: AppColors.brandBlue,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: _uploadProgress,
                backgroundColor: AppColors.darkSurface,
                valueColor: const AlwaysStoppedAnimation(AppColors.brandBlue),
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Done View ────────────────────────────────────────────────────────────

  Widget _buildDoneView() {
    return Column(
      children: [
        // Top bar
        Container(
          color: AppColors.darkBackground,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => context.pop(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.darkSurface,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'GIF Ready!',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),

        // Success animation area
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 20),
                // Success badge
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.darkSurface,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brandBlue.withValues(alpha: 0.4),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.brandBlue,
                    size: 56,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Your GIF is live!',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Share it to comments or your feed',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),

                if (_gifUrl != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.darkSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.link_rounded,
                            color: AppColors.textSecondary, size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _gifUrl!,
                            style: GoogleFonts.inter(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: _gifUrl!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Link copied!',
                                    style: GoogleFonts.inter(
                                        color: Colors.white)),
                                backgroundColor: AppColors.brandBlue,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: const Icon(Icons.copy_rounded,
                              color: AppColors.textSecondary, size: 18),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 36),

                // Action buttons
                if (widget.onGifCreated != null)
                  _buildFilledButton(
                    label: 'Share to Comments',
                    icon: Icons.comment_rounded,
                    onTap: _onGifCreated,
                  ),

                const SizedBox(height: 12),

                _buildFilledButton(
                  label: 'Share to Feed',
                  icon: Icons.dynamic_feed_rounded,
                  onTap: () {
                    if (_gifUrl != null) {
                      context.push('/social_hub/feed');
                    }
                  },
                ),

                const SizedBox(height: 12),

                _buildOutlineButton(
                  label: 'Share Externally',
                  icon: Icons.share_rounded,
                  onTap: _shareGif,
                ),

                const SizedBox(height: 12),

                _buildOutlineButton(
                  label: 'Create Another',
                  icon: Icons.add_a_photo_rounded,
                  onTap: () {
                    _previewTimer?.cancel();
                    setState(() {
                      _framePaths = [];
                      _capturedFrames = 0;
                      _previewFrameIndex = 0;
                      _gifBytes = null;
                      _gifUrl = null;
                      _uploadProgress = 0;
                      _state = GifCreatorState.camera;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Shared Button Widgets ────────────────────────────────────────────────

  Widget _buildFilledButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.brandBlue,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandBlue.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutlineButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
