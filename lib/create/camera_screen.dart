import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../backend/social/repositories/audio_track_repository.dart';
import '../backend/social/models/audio_track.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';

import 'models/cinema_preset.dart';
import 'services/blackmagic_color_converter.dart';
import 'services/cinema_preset_service.dart';
import 'models/host_shorts_session.dart';
import 'services/host_shorts_multicam_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'studio/models/studio_project.dart';
import 'studio/screens/studio_editor_screen.dart';
import 'studio/services/studio_media.dart';
import 'studio/services/studio_project_store.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/oneova_file_picker.dart';
import '../looks/camera/camera_looks_controller.dart';
import '../looks/camera/models/camera_smart_lock_state.dart';
import '../looks/camera/widgets/camera_smart_lock_hud.dart';
import '../looks/camera/widgets/camera_pro_controls_deck.dart';
import '../looks/camera/widgets/camera_looks_dock.dart';
import '../looks/camera/services/camera_quick_access_service.dart';
import '../looks/ar/controllers/live_ar_controller.dart';
import '../looks/ar/render/ar_viewfinder.dart';
import '../looks/ar/widgets/ar_effects_sheet.dart';

/// OneOva Pro — Camera & Story Creator Studio
/// Obsidian Telemetry Theme (#08080A, #FF2D75, #00F2FE)
/// With Built-in Blackmagic Color Science, RAW Log Sync, AI Auto-Grade & Preset Creator.
class CameraScreen extends ConsumerStatefulWidget {
  final String? initialMode;
  const CameraScreen({super.key, this.initialMode});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isInitialized = false;
  bool _isRecording = false;
  FlashMode _flashMode = FlashMode.off;

  // Creator Studio State
  String _activeDurationMode = 'PHOTO'; // 10m, 60s, 15s, PHOTO, TEXT, TEMPLATE
  String _activeBroadcastMode = 'POST'; // LIVE, POST, CREATE, STORY
  String? _selectedSoundTitle;
  bool _showGrid = true;
  bool _isBeautyRetouchOn = true;
  int _timerSeconds = 0; // 0 (off), 3, 10
  // Live AR effects run ML Kit on the preview stream; at 4K the frames are
  // too heavy to track, so the camera drops to 720p while effects are on.
  bool _arResolution = false;
  ProviderSubscription<LiveArState>? _arSub;
  late final LiveArController _ar;
  int _recordingSecondsElapsed = 0;
  Timer? _recordingTimer;

  // Professional Cinema & Color Science State
  CinemaPreset _activePreset = CinemaPresetService.defaultPresets[0]; // BMD Gen5 Film
  bool _isAiAutoGradeActive = true;
  bool _showFalseColor = false;
  bool _showProTelemetryDeck = false;
  bool _showLooksDock = false;
  StreamSubscription? _quickAccessSub;
  bool _isFocusPeakingOn = false;
  int _selectedIso = 200; // Auto, 100, 200, 400, 800, 1600, 3200

  // Host Shorts Multi-Cam State
  bool _isHostShortsSwapped = false;
  Offset _pipOffset = const Offset(16, 140);
  final TextEditingController _pairCodeController = TextEditingController();

  // OneOva Studio Theme Colors (Strict: Blue Dominant, Pink Secondary Accent)
  static const Color obsidianDark = Color(0xFF08080A);
  static const Color glassSurface = Color(0x9E121218);
  static const Color brandBlue = AppColors.brandBlue; // #007AFF DOMINANT
  static const Color brandPink = AppColors.brandPink; // #FF2D87 SECONDARY ACCENT ONLY
  static const Color brandCyan = AppColors.brandBlue; // Replaced rogue cyan with brandBlue
  static const Color brandGold = Color(0xFFFFB300);

  final List<String> _durationModes = const ['PHOTO', '15s', '60s', '10m', 'DUAL CAM'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialMode == 'video') {
      _activeDurationMode = '60s';
      _activeBroadcastMode = 'POST';
    } else if (widget.initialMode == 'photo') {
      _activeDurationMode = 'PHOTO';
      _activeBroadcastMode = 'POST';
    } else if (widget.initialMode == 'pip' || widget.initialMode == 'host_shorts') {
      _activeDurationMode = 'DUAL CAM';
      _activeBroadcastMode = 'HOST SHORTS';
    }
    _quickAccessSub = ref.read(cameraQuickAccessServiceProvider).onQuickLaunch.listen((launch) {
      if (!mounted) return;
      setState(() {
        switch (launch.initialMode) {
          case CaptureMode.photo:
            _activeDurationMode = 'PHOTO';
            break;
          case CaptureMode.dualCamera:
            _activeDurationMode = 'DUAL CAM';
            break;
          default:
            _activeDurationMode = '60s';
            break;
        }
      });
      if (launch.autoRecord) {
        _startVideoRecording();
      }
    });
    _arSub = ref.listenManual<LiveArState>(liveArControllerProvider, (prev, next) {
      if (!next.needs.any || !mounted) return;
      if (!_arResolution) {
        _arResolution = true;
        _reinitCamera();
      } else {
        _attachAr();
      }
    });
    _ar = ref.read(liveArControllerProvider.notifier);
    _arResolution = ref.read(liveArControllerProvider).needs.any;
    _initCamera();
  }

  void _attachAr() {
    final c = _cameraController;
    if (c == null || !c.value.isInitialized || _cameras.isEmpty) return;
    ref
        .read(liveArControllerProvider.notifier)
        .attachCamera(c, _cameras[_selectedCameraIndex.clamp(0, _cameras.length - 1)]);
  }

  Future<void> _reinitCamera() async {
    if (_isRecording) return;
    ref.read(liveArControllerProvider.notifier).detachCamera();
    final old = _cameraController;
    _cameraController = null;
    if (mounted) setState(() => _isInitialized = false);
    await old?.dispose();
    await _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _isInitialized = false);
        return;
      }

      final camera = _cameras[_selectedCameraIndex.clamp(0, _cameras.length - 1)];
      _cameraController = CameraController(
        camera,
        _arResolution ? ResolutionPreset.high : ResolutionPreset.ultraHigh,
        enableAudio: true,
        // NV21 is what ML Kit reads on Android (only the AR frame stream uses it).
        imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        _attachAr();
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
      if (mounted) setState(() => _isInitialized = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _quickAccessSub?.cancel();
    _recordingTimer?.cancel();
    _arSub?.close();
    _ar.detachCamera();
    _cameraController?.dispose();
    _pairCodeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cameraController = _cameraController;
    if (cameraController == null || !cameraController.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      _ar.detachCamera();
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // Capture Actions
  // ────────────────────────────────────────────────────────────────────────
  Future<void> _takePhoto() async {
    HapticFeedback.mediumImpact();
    if (_timerSeconds > 0) {
      await _runCountdownTimer();
    }

    if (_cameraController != null && _cameraController!.value.isInitialized && !_isRecording) {
      try {
        final XFile photo = await _cameraController!.takePicture();
        var path = photo.path;
        if (ref.read(liveArControllerProvider).hasAnything) {
          try {
            path = await ref.read(liveArControllerProvider.notifier).bakePhoto(photo.path) ?? path;
          } catch (e) {
            debugPrint('AR photo bake failed: $e');
          }
        }
        if (mounted) {
          _navigateToPreview(path, isVideo: false);
        }
        return;
      } catch (e) {
        debugPrint('Take photo error: $e');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The camera is not ready yet.'), backgroundColor: AppColors.brandPink),
      );
    }
  }

  Future<void> _startVideoRecording() async {
    HapticFeedback.heavyImpact();
    if (_isRecording) return;

    // Auto-engage Smart Lock (AE / AF / AWB) for shake/flicker-free capture
    ref.read(cameraLooksControllerProvider.notifier).engageSmartLock();

    // Trigger Host Shorts multi-cam synchronized recording across paired devices
    final hostSession = ref.read(hostShortsServiceProvider);
    if (hostSession != null && hostSession.isConnected) {
      ref.read(hostShortsServiceProvider.notifier).triggerSyncRecord(true);
    }

    if (_cameraController != null && _cameraController!.value.isInitialized) {
      if (ref.read(liveArControllerProvider).hasAnything && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Effects are saved into photos. Videos record without them for now.')),
        );
      }
      try {
        await _cameraController!.startVideoRecording();
      } catch (e) {
        debugPrint('Start recording error: $e');
      }
    }

    setState(() {
      _isRecording = true;
      _recordingSecondsElapsed = 0;
    });

    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _recordingSecondsElapsed++);
      }
    });
  }

  Future<void> _stopVideoRecording() async {
    HapticFeedback.lightImpact();
    _recordingTimer?.cancel();
    ref.read(cameraLooksControllerProvider.notifier).releaseSmartLock();

    // Stop synchronized recording on secondary paired camera
    final hostSession = ref.read(hostShortsServiceProvider);
    if (hostSession != null && hostSession.isConnected) {
      ref.read(hostShortsServiceProvider.notifier).triggerSyncRecord(false);
    }

    if (_cameraController != null && _cameraController!.value.isRecordingVideo) {
      try {
        final XFile video = await _cameraController!.stopVideoRecording();
        setState(() => _isRecording = false);
        if (mounted) {
          _navigateToPreview(video.path, isVideo: true);
        }
        return;
      } catch (e) {
        debugPrint('Stop recording error: $e');
      }
    }

    setState(() => _isRecording = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recording failed. Try again.'), backgroundColor: AppColors.brandPink),
      );
    }
  }

  Future<void> _runCountdownTimer() async {
    int count = _timerSeconds;
    while (count > 0 && mounted) {
      HapticFeedback.selectionClick();
      if (!mounted) break;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Center(
            child: Text(
              '$count',
              style: GoogleFonts.inter(fontSize: 48, fontWeight: FontWeight.w900, color: brandPink),
            ),
          ),
          duration: const Duration(milliseconds: 700),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      );
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) break;
      count--;
    }
  }

  Future<void> _toggleFlipCamera() async {
    HapticFeedback.lightImpact();
    if (_cameras.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No secondary camera available on this device.')),
      );
      return;
    }
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    ref.read(liveArControllerProvider.notifier).detachCamera();
    await _cameraController?.dispose();
    setState(() => _isInitialized = false);
    await _initCamera();
  }

  Future<void> _toggleFlash() async {
    HapticFeedback.lightImpact();
    if (_cameraController == null) return;
    FlashMode nextMode;
    switch (_flashMode) {
      case FlashMode.off:
        nextMode = FlashMode.torch;
        break;
      case FlashMode.torch:
        nextMode = FlashMode.auto;
        break;
      default:
        nextMode = FlashMode.off;
        break;
    }
    try {
      await _cameraController!.setFlashMode(nextMode);
      setState(() => _flashMode = nextMode);
    } catch (e) {
      debugPrint('Set flash mode error: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    HapticFeedback.lightImpact();
    try {
      if (_activeDurationMode == 'PHOTO') {
        final picked = await OneovaFilePicker.pickSingleFile(
          context,
          mode: OneovaFilePickerMode.photos,
          title: 'Select Photo',
        );
        if (picked != null && mounted) {
          _navigateToPreview(picked.path, isVideo: false);
        }
      } else {
        // Video mode: Pick clip and let user trim length before importing into timeline
        final clip = await OneovaFilePicker.pickSingleClip(
          context,
          mode: OneovaFilePickerMode.videos,
          title: 'Select & Trim Clip',
          actionLabel: 'Import to Timeline',
        );
        if (clip != null && mounted) {
          _navigateToPreview(
            clip.file.path,
            isVideo: true,
            trimStartSeconds: clip.startSeconds,
            trimEndSeconds: clip.endSeconds,
            speedMultiplier: clip.speed,
            aspectRatio: clip.aspectRatio,
            durationSeconds: clip.totalDurationSeconds,
          );
        }
      }
    } catch (e) {
      debugPrint('OneovaFilePicker error: $e');
    }
  }

  Future<void> _navigateToPreview(
    String path, {
    required bool isVideo,
    double trimStartSeconds = 0.0,
    double trimEndSeconds = 0.0,
    double speedMultiplier = 1.0,
    double aspectRatio = 9 / 16,
    double durationSeconds = 0.0,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await File(path).exists()) {
      messenger.showSnackBar(SnackBar(
        content: Text(isVideo ? 'Nothing was recorded. Try again.' : 'The photo was not captured. Try again.'),
        backgroundColor: AppColors.brandPink,
      ));
      return;
    }
    try {
      // Camera files live in cache; keep a copy so the project survives.
      final kept = await StudioProjectStore.keepFile(path);
      var clip = await StudioMedia.clipFromFile(kept, isImage: !isVideo);
      if (isVideo && trimEndSeconds > trimStartSeconds) {
        clip = clip.copyWith(
          startMs: (trimStartSeconds * 1000).round().clamp(0, clip.sourceDurationMs),
          endMs: (trimEndSeconds * 1000).round().clamp(0, clip.sourceDurationMs),
        );
      }
      if (isVideo && speedMultiplier > 0 && speedMultiplier != 1.0) clip = clip.copyWith(speed: speedMultiplier);
      final project = StudioProject.create(isPhoto: !isVideo, clips: [clip]);
      // STORY mode posts to stories; every other mode publishes a post.
      final target = _activeBroadcastMode == 'STORY' ? StudioTarget.story : StudioTarget.post;
      if (!mounted) return;
      await context.push('/create/studio/editor', extra: StudioEditorArgs(project: project, target: target));
    } catch (e) {
      debugPrint('[CameraScreen] opening editor failed: $e');
      messenger.showSnackBar(SnackBar(content: Text('Could not open the editor: $e'), backgroundColor: AppColors.brandPink));
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // Color Science, AI Auto-Grade & Preset Modals
  // ────────────────────────────────────────────────────────────────────────
  void _toggleAiAutoGrade() {
    HapticFeedback.heavyImpact();
    setState(() {
      _isAiAutoGradeActive = !_isAiAutoGradeActive;
      if (_isAiAutoGradeActive) {
        _activePreset = BlackmagicColorConverter.generateAiAutoGrade(
          currentSceneName: _activePreset.name,
          isLowLight: _selectedIso >= 800,
        );
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.auto_awesome, color: brandPink, size: 18),
            const SizedBox(width: 8),
            Text(
              _isAiAutoGradeActive ? 'AI Auto-Grade Applied: ${_activePreset.name}' : 'AI Auto-Grade Disabled',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF141419),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showColorSciencePicker() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _buildColorScienceSheet(ctx),
    );
  }

  void _showPresetDrawer() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _buildPresetDrawer(ctx),
    );
  }

  void _showCreatePresetDialog() {
    HapticFeedback.lightImpact();
    final nameController = TextEditingController(text: '${_activePreset.name} (Custom)');
    int tempKelvin = _activePreset.kelvin;
    double tempTint = _activePreset.tint;
    double tempContrast = _activePreset.contrast;
    double tempSaturation = _activePreset.saturation;
    double tempGrain = _activePreset.filmGrain;
    ColorScienceStandard tempStandard = _activePreset.colorScience;

    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.tune_rounded, color: brandPink, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Create Cinema Preset',
                            style: GoogleFonts.inter(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: context.textSecondary),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      labelText: 'Preset Name',
                      labelStyle: GoogleFonts.inter(color: context.textMuted),
                      filled: true,
                      fillColor: context.surfaceMid,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Color Science Standard', style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ColorScienceStandard>(
                    initialValue: tempStandard,
                    dropdownColor: context.surfaceMid,
                    style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: context.surfaceMid,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                    items: ColorScienceStandard.values.map((std) {
                      return DropdownMenuItem(
                        value: std,
                        child: Text(std.displayName),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => tempStandard = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildSliderRow('Kelvin Temp', '${tempKelvin}K', tempKelvin.toDouble(), 3200, 8000, (v) {
                    setModalState(() => tempKelvin = v.toInt());
                  }),
                  _buildSliderRow('Tint', tempTint.toStringAsFixed(1), tempTint, -10, 10, (v) {
                    setModalState(() => tempTint = v);
                  }),
                  _buildSliderRow('Contrast', tempContrast.toStringAsFixed(2), tempContrast, 0.6, 1.6, (v) {
                    setModalState(() => tempContrast = v);
                  }),
                  _buildSliderRow('Saturation', tempSaturation.toStringAsFixed(2), tempSaturation, 0.0, 2.0, (v) {
                    setModalState(() => tempSaturation = v);
                  }),
                  _buildSliderRow('Film Grain', '${(tempGrain * 100).toInt()}%', tempGrain, 0.0, 1.0, (v) {
                    setModalState(() => tempGrain = v);
                  }),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandPink,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.save_rounded, color: Colors.white),
                      label: Text('Save Cinema Preset', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                      onPressed: () async {
                        final navigator = Navigator.of(ctx);
                        final messenger = ScaffoldMessenger.of(context);
                        final newPreset = CinemaPreset(
                          id: const Uuid().v4(),
                          name: nameController.text.trim().isEmpty ? 'Custom Cine Preset' : nameController.text.trim(),
                          colorScience: tempStandard,
                          kelvin: tempKelvin,
                          tint: tempTint,
                          contrast: tempContrast,
                          saturation: tempSaturation,
                          filmGrain: tempGrain,
                          isAiEnhanced: true,
                          aiPrompt: 'Custom user cinema grade profile.',
                          isUserCustom: true,
                          createdAt: DateTime.now(),
                        );
                        await ref.read(cinemaPresetsListProvider.notifier).saveCustomPreset(newPreset);
                        if (!mounted) return;
                        setState(() {
                          _activePreset = newPreset;
                        });
                        navigator.pop();
                        messenger.showSnackBar(
                          SnackBar(content: Text('Preset "${newPreset.name}" saved!')),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSliderRow(String label, String valueStr, double val, double min, double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            Text(valueStr, style: GoogleFonts.firaCode(color: brandPink, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
        Slider(
          value: val.clamp(min, max),
          min: min,
          max: max,
          activeColor: brandPink,
          inactiveColor: context.border,
          onChanged: onChanged,
        ),
      ],
    );
  }

  void _showSoundSelector() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _buildSoundModal(ctx),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Build Screen
  // ────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hostSession = ref.watch(hostShortsServiceProvider);
    final isHostShortsActive = _activeBroadcastMode == 'HOST SHORTS' || (hostSession != null && hostSession.isConnected);
    final cameraLooksState = ref.watch(cameraLooksControllerProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Live Viewfinder Background (with Blackmagic Color Converter applied live)
          _buildCameraViewfinder(),

          // 2. Viewfinder Guides & Precision Reticles
          if (_showGrid) _buildRuleOfThirdsGrid(),
          _buildFramingBrackets(),
          _buildAutofocusReticle(),

          // 3. Focus Peaking & Exposure Overlays
          if (_isFocusPeakingOn) _buildFocusPeakingOverlay(),

          // 4. Vignette & Cinematic Gradient
          _buildCinematicVignette(),

          // 5. Host Shorts Wireless Multi-Cam Secondary Angle (PiP or Split Screen)
          if (isHostShortsActive) _buildHostShortsOverlay(hostSession),

          // 6. Main Foreground UI
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Navigation & Studio Telemetry Header
                _buildTopStudioHeader(),

                // Smart Lock Status HUD
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: CameraSmartLockHud(
                    smartLock: cameraLooksState.smartLockState,
                    onUnlockTap: () => ref.read(cameraLooksControllerProvider.notifier).releaseSmartLock(_cameraController),
                  ),
                ),

                // Center Pro Telemetry Deck (when toggled)
                if (_showProTelemetryDeck)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: CameraProControlsDeck(
                      state: cameraLooksState.smartLockState,
                      cameraController: _cameraController,
                      onEvChanged: (ev) => ref.read(cameraLooksControllerProvider.notifier).setExposureBias(ev),
                      onIsoChanged: (iso) => ref.read(cameraLooksControllerProvider.notifier).setIso(iso),
                      onShutterChanged: (shutter) => ref.read(cameraLooksControllerProvider.notifier).setShutterSpeed(shutter),
                      onWbChanged: (mode, {kelvin}) => ref.read(cameraLooksControllerProvider.notifier).setWhiteBalance(mode, kelvin: kelvin),
                      onFocusChanged: (dist) => ref.read(cameraLooksControllerProvider.notifier).setManualFocus(dist),
                      onTogglePeaking: () => ref.read(cameraLooksControllerProvider.notifier).toggleFocusPeaking(),
                      onClose: () => setState(() => _showProTelemetryDeck = false),
                    ),
                  ),

                const Spacer(),

                // Snap-Style Looks Carousel Dock (when toggled)
                if (_showLooksDock)
                  CameraLooksDock(
                    activeLook: cameraLooksState.activeLook,
                    onLookSelected: (look) => ref.read(cameraLooksControllerProvider.notifier).applyLook(look),
                    onIntensityChanged: (val) => ref.read(cameraLooksControllerProvider.notifier).setLookIntensity(val),
                    onOpenCatalog: _showPresetDrawer,
                    onClose: () => setState(() => _showLooksDock = false),
                  ),

                // Bottom Creator Console & Capture Deck
                _buildBottomCreatorConsole(),
              ],
            ),
          ),

          // 7. Right Creative Quick Tools Toolbar
          Positioned(
            right: 14,
            top: MediaQuery.of(context).padding.top + 76,
            child: _buildRightCreativeToolbar(),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // 1. Camera Viewfinder with Blackmagic Color Science Engine
  // ────────────────────────────────────────────────────────────────────────
  Widget _buildCameraViewfinder() {
    // Dynamically compute authentic color filter matrix
    final colorFilter = BlackmagicColorConverter.createColorFilter(
      _activePreset,
      falseColorActive: _showFalseColor,
    );

    if (_isInitialized && _cameraController != null && _cameraController!.value.isInitialized) {
      Widget preview = CameraPreview(_cameraController!);
      preview = ColorFiltered(colorFilter: colorFilter, child: preview);
      preview = ArViewfinder(preview: preview);

      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _cameraController!.value.previewSize?.height ?? 1080,
            height: _cameraController!.value.previewSize?.width ?? 1920,
            child: preview,
          ),
        ),
      );
    }

    // High-fidelity simulator viewfinder backdrop
    return ColorFiltered(
      colorFilter: colorFilter,
      child: Container(
        decoration: const BoxDecoration(
          color: obsidianDark,
          gradient: RadialGradient(
            center: Alignment(0.0, -0.2),
            radius: 1.2,
            colors: [Color(0xFF191924), Color(0xFF0F0F14), Color(0xFF070709)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: const Icon(Icons.videocam_rounded, color: Colors.white38, size: 40),
              ),
              const SizedBox(height: 16),
              Text(
                'Oneova Pro Optical Engine',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '${_activePreset.colorScience.displayName} · Active',
                style: GoogleFonts.inter(color: brandPink, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // 2. Viewfinder Reticles & Guides
  // ────────────────────────────────────────────────────────────────────────
  Widget _buildRuleOfThirdsGrid() {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return Stack(
            children: [
              Positioned(left: w / 3, top: 0, bottom: 0, child: Container(width: 0.7, color: Colors.white.withValues(alpha: 0.15))),
              Positioned(left: (2 * w) / 3, top: 0, bottom: 0, child: Container(width: 0.7, color: Colors.white.withValues(alpha: 0.15))),
              Positioned(top: h / 3, left: 0, right: 0, child: Container(height: 0.7, color: Colors.white.withValues(alpha: 0.15))),
              Positioned(top: (2 * h) / 3, left: 0, right: 0, child: Container(height: 0.7, color: Colors.white.withValues(alpha: 0.15))),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFramingBrackets() {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(top: 90, left: 20, child: _cornerBracket(top: true, left: true)),
          Positioned(top: 90, right: 20, child: _cornerBracket(top: true, left: false)),
          Positioned(bottom: 230, left: 20, child: _cornerBracket(top: false, left: true)),
          Positioned(bottom: 230, right: 20, child: _cornerBracket(top: false, left: false)),
        ],
      ),
    );
  }

  Widget _cornerBracket({required bool top, required bool left}) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        border: Border(
          top: top ? BorderSide(color: Colors.white.withValues(alpha: 0.4), width: 2) : BorderSide.none,
          bottom: !top ? BorderSide(color: Colors.white.withValues(alpha: 0.4), width: 2) : BorderSide.none,
          left: left ? BorderSide(color: Colors.white.withValues(alpha: 0.4), width: 2) : BorderSide.none,
          right: !left ? BorderSide(color: Colors.white.withValues(alpha: 0.4), width: 2) : BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildAutofocusReticle() {
    return IgnorePointer(
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: brandBlue.withValues(alpha: 0.85), width: 1.5),
                boxShadow: [
                  BoxShadow(color: brandBlue.withValues(alpha: 0.25), blurRadius: 10),
                ],
              ),
              child: Center(
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(color: brandBlue, shape: BoxShape.circle),
                ),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
                  begin: const Offset(0.95, 0.95),
                  end: const Offset(1.05, 1.05),
                  duration: 1200.ms,
                ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wb_sunny_rounded, size: 12, color: brandBlue),
                const SizedBox(height: 1),
                Text(
                  '+${_activePreset.exposure >= 0 ? _activePreset.exposure.toStringAsFixed(1) : _activePreset.exposure.toStringAsFixed(1)}',
                  style: GoogleFonts.firaCode(fontSize: 9, color: brandBlue, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusPeakingOverlay() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: brandPink.withValues(alpha: 0.35), width: 2),
        ),
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(40.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: brandPink, borderRadius: BorderRadius.circular(8)),
              child: Text('PEAKING ON', style: GoogleFonts.firaCode(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCinematicVignette() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.65),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.88),
            ],
            stops: const [0.0, 0.22, 0.68, 1.0],
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // 3. Top Navigation & Studio Header
  // ────────────────────────────────────────────────────────────────────────
  Widget _buildTopStudioHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dynamic Notch & Stereo VU Meter Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Keeps the camera notch centred (no live audio meter: the
                // camera plugin exposes no input levels).
                const SizedBox(width: 56),

                // Center Camera Notch Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _isRecording ? brandPink : brandBlue,
                          shape: BoxShape.circle,
                        ),
                      ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
                            begin: const Offset(0.8, 0.8),
                            end: const Offset(1.2, 1.2),
                            duration: 900.ms,
                          ),
                      const SizedBox(width: 6),
                      Text(
                        _isRecording
                            ? 'REC ${(_recordingSecondsElapsed ~/ 60).toString().padLeft(2, '0')}:${(_recordingSecondsElapsed % 60).toString().padLeft(2, '0')}'
                            : 'ONEOVA CAM',
                        style: GoogleFonts.firaCode(
                          color: _isRecording ? brandPink : Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),

                // Right Quick Flip Camera Action
                GestureDetector(
                  onTap: _toggleFlipCamera,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.flip_camera_ios_rounded, color: Colors.white70, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          'FLIP',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Main Header Action Bar (Exit · Add Sound · Color Science · Flash)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Exit Camera Button
              _buildGlassIconButton(
                icon: Icons.close_rounded,
                onTap: () => context.pop(),
              ),

              // Centered Add Sound Glass Pill
              GestureDetector(
                onTap: _showSoundSelector,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: glassSurface,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    boxShadow: [
                      BoxShadow(color: brandPink.withValues(alpha: 0.15), blurRadius: 16),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildBouncingSoundWaves(),
                      const SizedBox(width: 8),
                      Text(
                        _selectedSoundTitle ?? 'Add Sound',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white60, size: 16),
                    ],
                  ),
                ),
              ),

              // Right Quick Badges
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 4K 60 Telemetry Badge
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Sensor Mode: 4K 60fps ProRes RAW Enabled', style: GoogleFonts.inter()),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: glassSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: brandCyan.withValues(alpha: 0.4)),
                        boxShadow: [BoxShadow(color: brandCyan.withValues(alpha: 0.2), blurRadius: 10)],
                      ),
                      child: Text(
                        '4K 60',
                        style: GoogleFonts.firaCode(color: brandCyan, fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Flash Toggle
                  _buildGlassIconButton(
                    icon: _flashMode == FlashMode.off
                        ? Icons.flash_off_rounded
                        : (_flashMode == FlashMode.torch ? Icons.flash_on_rounded : Icons.flash_auto_rounded),
                    iconColor: _flashMode != FlashMode.off ? const Color(0xFFFACC15) : Colors.white,
                    onTap: _toggleFlash,
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Pro Color Science & AI Auto-Grade Pill Row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Blackmagic / Cinema Color Science Tag
              GestureDetector(
                onTap: _showColorSciencePicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: brandGold.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 5, height: 5, decoration: const BoxDecoration(color: brandGold, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(
                        _activePreset.colorScience.shortTag,
                        style: GoogleFonts.firaCode(
                          color: brandGold,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '· ${_activePreset.name.toUpperCase()}',
                        style: GoogleFonts.inter(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // AI Auto-Grade Pill Toggle
              GestureDetector(
                onTap: _toggleAiAutoGrade,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isAiAutoGradeActive ? brandPink.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isAiAutoGradeActive ? brandPink : Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 10,
                        color: _isAiAutoGradeActive ? brandPink : Colors.white54,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'AI AUTO',
                        style: GoogleFonts.inter(
                          color: _isAiAutoGradeActive ? Colors.white : Colors.white54,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBouncingSoundWaves() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildWaveBar(h: 8, delay: 0),
        const SizedBox(width: 2),
        _buildWaveBar(h: 14, delay: 150),
        const SizedBox(width: 2),
        _buildWaveBar(h: 6, delay: 300),
      ],
    );
  }

  Widget _buildWaveBar({required double h, required int delay}) {
    return Container(
      width: 2.5,
      height: h,
      decoration: BoxDecoration(color: brandPink, borderRadius: BorderRadius.circular(2)),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleY(
          begin: 0.4,
          end: 1.2,
          delay: Duration(milliseconds: delay),
          duration: 400.ms,
        );
  }

  // ────────────────────────────────────────────────────────────────────────
  // 4. Right Creative Quick Tools Toolbar
  // ────────────────────────────────────────────────────────────────────────
  bool get _isGreenScreenOn =>
      ref.watch(liveArControllerProvider.select((s) => s.backgroundMode != ArBackgroundMode.none));

  Widget _buildRightCreativeToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 5),
      decoration: BoxDecoration(
        color: glassSurface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20, spreadRadius: 2)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Flip Camera
          _buildToolbarButton(icon: Icons.flip_camera_ios_rounded, onTap: _toggleFlipCamera, tooltip: 'Flip Camera'),
          const SizedBox(height: 10),

          // AR face / body effects
          _buildToolbarButton(
            icon: Icons.face_retouching_natural,
            color: ref.watch(liveArControllerProvider.select((s) => s.active.isNotEmpty)) ? brandPink : Colors.white,
            hasCheckBadge: ref.watch(liveArControllerProvider.select((s) => s.active.isNotEmpty)),
            onTap: () => showArEffectsSheet(context),
            tooltip: 'Effects',
          ),
          const SizedBox(height: 10),

          // 2. Preset Drawer ("PRESETS")
          _buildToolbarButton(
            icon: Icons.palette_outlined,
            color: brandGold,
            hasBadge: true,
            onTap: _showPresetDrawer,
            tooltip: 'Presets Studio',
          ),
          const SizedBox(height: 10),

          // 3. Pro Telemetry / False Color & Exposure Tool
          _buildToolbarButton(
            icon: Icons.tune_rounded,
            color: _showProTelemetryDeck ? brandPink : Colors.white,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _showProTelemetryDeck = !_showProTelemetryDeck);
            },
            tooltip: 'Pro Controls (ISO/WB/Shutter)',
          ),
          const SizedBox(height: 10),

          // 4. Beauty & Retouch Filter
          _buildToolbarButton(
            icon: Icons.auto_fix_high_rounded,
            color: _isBeautyRetouchOn ? brandPink : Colors.white70,
            hasBadge: _isBeautyRetouchOn,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _isBeautyRetouchOn = !_isBeautyRetouchOn);
            },
            tooltip: 'Retouch',
          ),
          const SizedBox(height: 10),

          // 5. Studio Timer
          _buildToolbarButton(
            icon: Icons.timer_outlined,
            label: _timerSeconds > 0 ? '${_timerSeconds}s' : null,
            color: _timerSeconds > 0 ? brandPink : Colors.white,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (_timerSeconds == 0) {
                  _timerSeconds = 3;
                } else if (_timerSeconds == 3) {
                  _timerSeconds = 10;
                } else {
                  _timerSeconds = 0;
                }
              });
            },
            tooltip: 'Timer',
          ),
          const SizedBox(height: 10),

          // 6. Multi-Grid
          _buildToolbarButton(
            icon: Icons.grid_view_rounded,
            color: _showGrid ? brandPink : Colors.white70,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _showGrid = !_showGrid);
            },
            tooltip: 'Grid',
          ),
          const SizedBox(height: 10),

          // 7. AR Green Screen
          _buildToolbarButton(
            icon: Icons.wallpaper_rounded,
            color: _isGreenScreenOn ? brandPink : Colors.white,
            hasCheckBadge: _isGreenScreenOn,
            onTap: () {
              HapticFeedback.selectionClick();
              // Real person segmentation: off if a background is on, else
              // open Effects where blur / scene / "add yourself" live.
              if (_isGreenScreenOn) {
                ref.read(liveArControllerProvider.notifier).clearBackground();
              } else {
                showArEffectsSheet(context);
              }
            },
            tooltip: 'Green Screen',
          ),
          const SizedBox(height: 10),

          // 8. More Settings
          _buildToolbarButton(
            icon: Icons.keyboard_arrow_down_rounded,
            color: Colors.white70,
            onTap: () {
              HapticFeedback.selectionClick();
              _showMoreSettingsMenu();
            },
            tooltip: 'More Camera Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    IconData? icon,
    String? label,
    Color color = Colors.white,
    bool hasBadge = false,
    bool hasCheckBadge = false,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(shape: BoxShape.circle),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (icon != null)
                Icon(icon, color: color, size: 20)
              else if (label != null)
                Text(label, style: GoogleFonts.firaCode(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
              if (hasBadge)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(color: brandPink, shape: BoxShape.circle),
                  ),
                ),
              if (hasCheckBadge)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(color: brandPink, shape: BoxShape.circle),
                    child: const Center(child: Icon(Icons.check, size: 8, color: Colors.black)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }



  // ────────────────────────────────────────────────────────────────────────
  // 5. Bottom Creator Console & Capture Deck
  // ────────────────────────────────────────────────────────────────────────
  Widget _buildBottomCreatorConsole() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Duration & Format Carousel
        _buildDurationModeCarousel(),

        const SizedBox(height: 8),

        // Shutter & AR Lens Deck
        _buildShutterAndLensDeck(),

        const SizedBox(height: 10),

        // Broadcast Mode Switcher (LIVE | POST | CREATE | STORY)
        _buildBroadcastModeNavigation(),

        // Native iOS Home Indicator
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 130,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildDurationModeCarousel() {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: _durationModes.length,
        separatorBuilder: (_, index) => const SizedBox(width: 18),
        itemBuilder: (context, index) {
          final mode = _durationModes[index];
          final isSelected = mode == _activeDurationMode;

          if (isSelected) {
            return Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.white.withValues(alpha: 0.25), blurRadius: 10),
                    BoxShadow(color: brandPink.withValues(alpha: 0.35), blurRadius: 14),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 5, height: 5, decoration: const BoxDecoration(color: brandPink, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(
                      mode,
                      style: GoogleFonts.inter(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                    ),
                  ],
                ),
              ),
            );
          }

          return Center(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _activeDurationMode = mode);
              },
              child: Text(
                mode,
                style: GoogleFonts.inter(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildShutterAndLensDeck() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left Side: Oneova File Picker Button
          GestureDetector(
            onTap: _pickFromGallery,
            child: Container(
              width: 50,
              height: 50,
              padding: const EdgeInsets.all(2.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [brandBlue, brandPink],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: brandBlue.withValues(alpha: 0.35),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF101014),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.photo_library_rounded, color: Colors.white, size: 22),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: brandPink,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Center: Primary Shutter Trigger Ring
          GestureDetector(
            onTap: () {
              if (_activeDurationMode == 'PHOTO') {
                _takePhoto();
              } else {
                if (_isRecording) {
                  _stopVideoRecording();
                } else {
                  _startVideoRecording();
                }
              }
            },
            onLongPress: _startVideoRecording,
            onLongPressUp: _stopVideoRecording,
            child: Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: (_isRecording ? brandPink : brandBlue).withValues(alpha: _isRecording ? 0.7 : 0.35),
                    blurRadius: _isRecording ? 30 : 16,
                    spreadRadius: _isRecording ? 2 : 0,
                  ),
                ],
              ),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _isRecording ? 34 : 66,
                  height: _isRecording ? 34 : 66,
                  decoration: BoxDecoration(
                    color: _isRecording ? brandPink : Colors.white,
                    borderRadius: BorderRadius.circular(_isRecording ? 8 : 36),
                  ),
                  child: _isRecording
                      ? null
                      : Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _activeDurationMode == 'PHOTO' ? brandBlue : brandPink,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),

          // Right Side: Quick Filters & Beauty Retouch
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Presets Studio Drawer / Snap Looks Dock
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _showLooksDock = !_showLooksDock);
                },
                onLongPress: _showPresetDrawer,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: brandBlue.withValues(alpha: 0.8), width: 1.5),
                    color: glassSurface,
                    boxShadow: [
                      BoxShadow(color: brandBlue.withValues(alpha: 0.25), blurRadius: 8),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.palette_outlined, size: 20, color: Colors.white),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // AI Magic Retouch
              GestureDetector(
                onTap: _toggleAiAutoGrade,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: glassSurface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isAiAutoGradeActive ? brandPink : Colors.white24,
                      width: 1.5,
                    ),
                    boxShadow: [
                      if (_isAiAutoGradeActive)
                        BoxShadow(color: brandPink.withValues(alpha: 0.3), blurRadius: 10),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: _isAiAutoGradeActive ? brandPink : Colors.white,
                        size: 20,
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(color: brandPink, borderRadius: BorderRadius.circular(6)),
                          child: Text('AI', style: GoogleFonts.firaCode(fontSize: 7, fontWeight: FontWeight.w900, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBroadcastModeNavigation() {
    final modes = ['LIVE', 'POST', 'CREATE', 'STORY', 'HOST SHORTS'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: modes.map((mode) {
            final isSelected = mode == _activeBroadcastMode;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  if (mode == 'LIVE') {
                    context.push('/live/setup');
                    return;
                  }
                  setState(() => _activeBroadcastMode = mode);
                  if (mode == 'HOST SHORTS') {
                    _showHostShortsModal(context);
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (mode == 'LIVE') ...[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(color: brandPink, shape: BoxShape.circle),
                          ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
                                begin: const Offset(0.7, 0.7),
                                end: const Offset(1.3, 1.3),
                                duration: 800.ms,
                              ),
                          const SizedBox(width: 5),
                        ] else if (mode == 'HOST SHORTS') ...[
                          Icon(Icons.cell_tower_rounded, size: 12, color: isSelected ? brandBlue : Colors.white60),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          mode,
                          style: GoogleFonts.inter(
                            color: isSelected ? Colors.white : Colors.white54,
                            fontSize: isSelected ? 13 : 11,
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    if (isSelected)
                      Container(
                        width: 20,
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: brandBlue,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [BoxShadow(color: brandBlue.withValues(alpha: 0.6), blurRadius: 6)],
                        ),
                      )
                    else
                      const SizedBox(height: 2.5),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildGlassIconButton({
    required IconData icon,
    Color iconColor = Colors.white,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: glassSurface,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10)],
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Color Science & Preset Modals
  // ────────────────────────────────────────────────────────────────────────
  Widget _buildColorScienceSheet(BuildContext ctx) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: context.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.camera_rounded, color: brandGold, size: 22),
                  const SizedBox(width: 8),
                  Text('Color Science Standards', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                ],
              ),
              IconButton(icon: Icon(Icons.close, color: context.textSecondary), onPressed: () => Navigator.pop(ctx)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Select cinema digital film curve and color space transform engine.',
            style: GoogleFonts.inter(color: context.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ...ColorScienceStandard.values.map((std) {
            final isChosen = _activePreset.colorScience == std;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isChosen ? brandGold.withValues(alpha: 0.2) : context.border,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isChosen ? brandGold : context.border),
                ),
                child: Center(
                  child: Text(std.shortTag, style: GoogleFonts.firaCode(fontSize: 9, fontWeight: FontWeight.w800, color: isChosen ? brandGold : context.textSecondary)),
                ),
              ),
              title: Text(std.displayName, style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: Text(std.description, style: GoogleFonts.inter(color: context.textMuted, fontSize: 11)),
              trailing: isChosen
                  ? const Icon(Icons.check_circle_rounded, color: brandGold)
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: context.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        setState(() {
                          _activePreset = _activePreset.copyWith(colorScience: std);
                        });
                        Navigator.pop(ctx);
                      },
                      child: Text('Apply', style: GoogleFonts.inter(color: context.textPrimary)),
                    ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPresetDrawer(BuildContext ctx) {
    final presetsAsync = ref.watch(cinemaPresetsListProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: context.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_motion_rounded, color: brandPink, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cinema Presets',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(color: context.textPrimary, fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: brandPink,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.add, size: 16, color: Colors.white),
                label: Text('New Preset', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showCreatePresetDialog();
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: presetsAsync.when(
              data: (presets) {
                return ListView.separated(
                  itemCount: presets.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final preset = presets[index];
                    final isActive = _activePreset.id == preset.id;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isActive ? brandPink.withValues(alpha: 0.12) : context.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isActive ? brandPink : context.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              gradient: LinearGradient(
                                colors: [
                                  isActive ? brandPink : brandGold,
                                  brandCyan,
                                ],
                              ),
                            ),
                            child: Center(
                              child: Text(
                                preset.colorScience.shortTag,
                                style: GoogleFonts.firaCode(fontSize: 8, fontWeight: FontWeight.w900, color: context.bg),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(preset.name, style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
                                    if (preset.isUserCustom) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(color: brandPink, borderRadius: BorderRadius.circular(6)),
                                        child: Text('CUSTOM', style: GoogleFonts.firaCode(fontSize: 7, fontWeight: FontWeight.w900, color: Colors.white)),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${preset.kelvin}K · WB Tint ${preset.tint >= 0 ? '+' : ''}${preset.tint.toStringAsFixed(1)} · Sat ${preset.saturation}x',
                                  style: GoogleFonts.firaCode(color: context.textMuted, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                          if (isActive)
                            const Icon(Icons.check_circle_rounded, color: brandPink)
                          else
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: context.surfaceMid,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setState(() => _activePreset = preset);
                                Navigator.pop(ctx);
                              },
                              child: Text('Apply', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 12)),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: brandPink)),
              error: (err, st) => Center(child: Text('Error loading presets', style: GoogleFonts.inter(color: context.textSecondary))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoundModal(BuildContext ctx) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: context.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Sound Selector', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
              IconButton(icon: Icon(Icons.close, color: context.textSecondary), onPressed: () => Navigator.pop(ctx)),
            ],
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<AudioTrack>>(
            stream: ref.read(audioTrackRepositoryProvider).watchAvailableTracks(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: brandBlue))),
                );
              }
              final sounds = snap.data!;
              if (sounds.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No sounds available yet', style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12.5)),
                  ),
                );
              }
              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: ListView(
                  shrinkWrap: true,
                  children: sounds.map((sound) {
            final isChosen = _selectedSoundTitle == sound.title;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: brandPink.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: brandPink.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.music_note_rounded, color: brandPink),
              ),
              title: Text(sound.title, style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: Text('${sound.ownerName}${sound.durationMs > 0 ? ' · ${sound.durationMs ~/ 1000}s' : ''}', style: GoogleFonts.inter(color: context.textMuted, fontSize: 12)),
              trailing: isChosen
                  ? const Icon(Icons.check_circle_rounded, color: brandPink)
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: context.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedSoundTitle = sound.title);
                        Navigator.pop(ctx);
                      },
                      child: Text('Select', style: GoogleFonts.inter(color: context.textPrimary)),
                    ),
            );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Host Shorts Multi-Cam Wireless View & Pairing Engine
  // ────────────────────────────────────────────────────────────────────────
  Widget _buildHostShortsOverlay(HostShortsSession? session) {
    final isStreaming = session?.status == HostShortsStatus.streaming;
    final latency = session?.remoteDevice?.latencyMs ?? 18;

    return Positioned(
      left: _pipOffset.dx,
      top: _pipOffset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _pipOffset += details.delta;
          });
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 130,
            height: 195,
            decoration: BoxDecoration(
              color: const Color(0xFF14141E),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: brandBlue, width: 2),
              boxShadow: [
                BoxShadow(
                  color: brandBlue.withValues(alpha: 0.45),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Stack(
            fit: StackFit.expand,
            children: [
              // Secondary Camera Stream or Radar Broadcast Animation
              if (isStreaming)
                RTCVideoView(
                  ref.read(hostShortsServiceProvider.notifier).remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              else
                Container(
                  color: const Color(0xFF0C0C12),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cell_tower_rounded, color: brandBlue, size: 28)
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .scale(begin: const Offset(0.85, 0.85), end: const Offset(1.15, 1.15)),
                        const SizedBox(height: 8),
                        Text('HOST SHORTS', style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text('Pairing Cam B...', style: GoogleFonts.inter(color: brandBlue, fontSize: 9, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),

              // Top Cam B Status Header
              Positioned(
                top: 6,
                left: 6,
                right: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: brandBlue, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 4, height: 4, decoration: const BoxDecoration(color: brandPink, shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          Text('CAM B', style: GoogleFonts.firaCode(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                      child: Text('${latency}ms', style: GoogleFonts.firaCode(fontSize: 8, fontWeight: FontWeight.w700, color: const Color(0xFF34D399))),
                    ),
                  ],
                ),
              ),

              // Bottom Swap Shutter Control
              Positioned(
                bottom: 6,
                right: 6,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _isHostShortsSwapped = !_isHostShortsSwapped);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: brandBlue,
                      shape: BoxShape.circle,
                      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
                    ),
                    child: const Icon(Icons.swap_horiz_rounded, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  void _showHostShortsModal(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (modalContext, setModalState) {
          final session = ref.watch(hostShortsServiceProvider);
          final isHosting = session != null && session.status != HostShortsStatus.idle;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(top: BorderSide(color: context.border)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: brandBlue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: brandBlue.withValues(alpha: 0.3)),
                            ),
                            child: const Icon(Icons.cell_tower_rounded, color: brandBlue, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Host Shorts Wireless Multi-Cam', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
                              Text('Zero-Latency P2P Second Camera Link', style: GoogleFonts.inter(color: context.textMuted, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: context.textSecondary),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Host Director Mode Section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.surfaceMid,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: isHosting ? brandBlue : context.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.videocam_rounded, color: brandBlue, size: 20),
                                const SizedBox(width: 8),
                                Text('Director Mode (Cam A - Master)', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                              ],
                            ),
                            if (isHosting)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: brandBlue, borderRadius: BorderRadius.circular(12)),
                                child: Text('ACTIVE HOST', style: GoogleFonts.firaCode(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Broadcast your recording session code to pair a second phone camera wirelessly as your Angle B.',
                          style: GoogleFonts.inter(color: context.textMuted, fontSize: 12),
                        ),
                        const SizedBox(height: 14),
                        if (session?.pairCode != null) ...[
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                              decoration: BoxDecoration(
                                color: context.bg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: brandBlue, width: 1.5),
                              ),
                              child: Text(
                                session!.pairCode,
                                style: GoogleFonts.firaCode(color: brandBlue, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                session.status == HostShortsStatus.streaming
                                    ? 'Cam B Connected · 1080p60 Live Feed'
                                    : 'Waiting for secondary camera to connect...',
                                style: GoogleFonts.inter(color: session.status == HostShortsStatus.streaming ? AppColors.brandBlue : context.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ] else ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: brandBlue,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              icon: const Icon(Icons.wifi_tethering_rounded, color: Colors.white),
                              label: Text('Start Hosting (Generate Pair Code)', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800)),
                              onPressed: () async {
                                HapticFeedback.mediumImpact();
                                await ref.read(hostShortsServiceProvider.notifier).startHostingSession();
                                setModalState(() {});
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Connect as Secondary Camera (Cam B)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.surfaceMid,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: context.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.linked_camera_rounded, color: brandBlue, size: 20),
                            const SizedBox(width: 8),
                            Text('Connect as Angle B (Secondary Camera)', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text('Enter the 6-digit Host Code from the director phone:', style: GoogleFonts.inter(color: context.textMuted, fontSize: 12)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _pairCodeController,
                                keyboardType: TextInputType.number,
                                style: GoogleFonts.firaCode(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 2),
                                decoration: InputDecoration(
                                  hintText: 'e.g. 849201',
                                  hintStyle: GoogleFonts.firaCode(color: context.border, fontSize: 16),
                                  filled: true,
                                  fillColor: context.bg,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: brandBlue,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () async {
                                if (_pairCodeController.text.trim().isNotEmpty) {
                                  HapticFeedback.selectionClick();
                                  await ref.read(hostShortsServiceProvider.notifier).joinAsCamB(_pairCodeController.text.trim());
                                  if (ctx.mounted) Navigator.pop(ctx);
                                }
                              },
                              child: Text('Join', style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Multi-Cam Layout Modes Switcher
                  Text('Multi-Camera View Layout', style: GoogleFonts.inter(color: context.textSecondary, fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildLayoutChip(HostShortsLayout.pip, 'PiP Floating', Icons.picture_in_picture_alt_rounded, session?.layout == HostShortsLayout.pip),
                      const SizedBox(width: 8),
                      _buildLayoutChip(HostShortsLayout.splitVertical, 'Split 50/50', Icons.vertical_split_rounded, session?.layout == HostShortsLayout.splitVertical),
                      const SizedBox(width: 8),
                      _buildLayoutChip(HostShortsLayout.soloCamA, 'Cam A Solo', Icons.crop_portrait_rounded, session?.layout == HostShortsLayout.soloCamA),
                      const SizedBox(width: 8),
                      _buildLayoutChip(HostShortsLayout.soloCamB, 'Cam B Solo', Icons.filter_none_rounded, session?.layout == HostShortsLayout.soloCamB),
                    ],
                  ),

                  if (isHosting) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.brandPink),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: Icon(Icons.link_off_rounded, color: AppColors.brandPink),
                        label: Text('Disconnect Multi-Cam Session', style: GoogleFonts.inter(color: AppColors.brandPink, fontWeight: FontWeight.w700)),
                        onPressed: () async {
                          HapticFeedback.mediumImpact();
                          await ref.read(hostShortsServiceProvider.notifier).disconnectSession();
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLayoutChip(HostShortsLayout layout, String label, IconData icon, bool isSelected) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          ref.read(hostShortsServiceProvider.notifier).switchLayout(layout);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? brandBlue : context.surfaceMid,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? brandBlue : context.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: isSelected ? Colors.white : context.textMuted),
              const SizedBox(height: 4),
              Text(label, style: GoogleFonts.inter(color: isSelected ? Colors.white : context.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  void _showMoreSettingsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Advanced Cinema Hardware Settings', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text('Stabilization (Gimbal Mode)', style: GoogleFonts.inter(color: context.textPrimary)),
              value: true,
              activeThumbColor: brandBlue,
              onChanged: (v) {},
            ),
            SwitchListTile(
              title: Text('Audio Noise Suppression (Dual-Mic)', style: GoogleFonts.inter(color: context.textPrimary)),
              value: true,
              activeThumbColor: brandBlue,
              onChanged: (v) {},
            ),
            SwitchListTile(
              title: Text('RAW Sync Telemetry Metadata', style: GoogleFonts.inter(color: context.textPrimary)),
              value: true,
              activeThumbColor: brandBlue,
              onChanged: (v) {},
            ),
          ],
        ),
      ),
    );
  }
}
