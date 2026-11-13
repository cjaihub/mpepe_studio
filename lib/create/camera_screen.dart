import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' show Media, Player;
import 'package:screen_brightness/screen_brightness.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../backend/social/repositories/audio_track_repository.dart';
import '../backend/social/models/audio_track.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'models/host_shorts_session.dart';
import 'services/host_shorts_multicam_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:oneova_camera_kit/oneova_camera_kit.dart';
import 'studio/models/studio_project.dart';
import 'studio/screens/studio_editor_screen.dart';
import 'studio/services/studio_media.dart';
import 'studio/services/studio_project_store.dart';
import 'studio/services/studio_color.dart';
import 'studio/services/studio_looks.dart';
import 'studio/screens/studio_media_picker_screen.dart';
import 'widgets/phone_music_sheet.dart';
import '../looks/filters/filter_browser.dart';
import '../looks/engine/look_compiler.dart';
import '../looks/engine/native_look.dart';
import '../looks/live/live_looks_controller.dart';
import '../looks/models/oneova_look.dart';
import '../looks/filters/oneova_presets.dart';
import '../looks/filters/preset_strip.dart';
import '../looks/ar/models/ar_effect.dart';
import '../shared/theme/app_theme.dart';
import '../looks/camera/camera_looks_controller.dart';
import '../looks/camera/models/camera_smart_lock_state.dart';
import '../looks/camera/widgets/camera_smart_lock_hud.dart';
import '../looks/camera/widgets/camera_pro_controls_deck.dart';
import '../looks/camera/services/camera_quick_access_service.dart';
import '../looks/camera/services/camera_voice_command_parser.dart';
import '../looks/ar/controllers/live_ar_controller.dart';
import '../looks/ar/render/ar_viewfinder.dart';
import '../looks/ar/widgets/ar_effects_sheet.dart';
import '../looks/ar/widgets/ar_makeup_studio_sheet.dart';
import '../shared/audio/speech_hub.dart';

/// Oneova — Camera & Story Creator Studio
/// Brand Core: AppColors.brandBlue (#0C4FA8) & AppColors.brandPink (#FF2D87)
/// Live AR effects, Makeup Studio, Smart Auto-Track, background tools and dual-cam capture.
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
  bool _showGrid = false;
  int _timerSeconds = 0; // 0 (off), 3, 10
  // Live AR effects. On Android they run on the native AR camera (CameraX:
  // full-resolution preview + recording, small analysis stream tracked
  // natively, effects baked into videos). Elsewhere, or if the native camera
  // fails, ML Kit runs on the Flutter camera stream, which is too heavy at
  // 4K, so that path drops to 720p while effects are on.
  bool _arResolution = false;
  OneovaArCamera? _nativeCam;
  ArCameraInfo? _nativeInfo;
  bool _nativeFailed = false;
  String? _nativeRecordingPath;
  bool _releasedInBackground = false;
  bool _switchingCamera = false;
  ProviderSubscription<LiveArState>? _arSub;
  late final LiveArController _ar;
  int _recordingSecondsElapsed = 0;
  Timer? _recordingTimer;

  // Filters + enhance: graded live on the preview with the same Look engine
  // as the editor, then carried into the editor as the clip's Look (so the
  // grade stays editable and is baked on export).
  String _filterId = 'none';
  double _filterIntensity = 1.0;
  String? _heldFilterId;
  bool _showFilters = false;
  bool _showEnhance = false;
  double _brightness = 0;
  double _contrast = 0;
  double _beauty = 0;

  // Presets: filter + adjustments + beauty in one tap.
  String? _presetId;
  StudioAdjust _presetAdjust = const StudioAdjust();
  OneovaPreset? _heldPreset;
  bool _presetsTab = false;

  // The grade baked natively into captures (Android camera engine).
  String? _gradeKeyPending;
  String? _gradeKeySent;
  Timer? _gradeTimer;

  // Tap to focus / long-press AE-AF lock / exposure slider.
  Offset? _focusTap;
  bool _focusLocked = false;
  bool _showFocusUi = false;
  Timer? _focusHideTimer;
  double _ev = 0;
  double _evMin = -2;
  double _evMax = 2;
  bool _evBusy = false;
  double? _evPending;
  Map<String, Object?> _manualCaps = const {};

  // Dual camera (front + back at once, native concurrent cameras).
  bool _dualOn = false;
  ArDualLayout _dualLayout = const ArDualLayout();

  // Countdown shown over the viewfinder.
  int _countdown = 0;

  // Sound picked for this take: plays while recording, added to the project.
  String? _soundSource; // URL or local path
  int _soundDurationMs = 0;
  Player? _soundPlayer;
  bool _soundUsed = false;

  // Capture settings (kept on the phone).
  bool _recordAudio = true;
  bool _autoStabilize = false;
  bool _cleanVoice = false;
  bool _lowLight = false;
  Timer? _darkTimer;

  /// Video quality: '1080p30' (default), '1080p60', '4k30'.
  String _videoQuality = '1080p30';
  bool _openedAspect43 = false;
  String _openedQuality = '1080p30';
  bool get _wantsAspect43 => _activeDurationMode == 'PHOTO';
  bool _shutterBlink = false;
  StreamSubscription? _sizeSub;
  bool _heatWarned = false;
  int _deviceRotation = 0;
  StreamSubscription? _tiltSub;

  /// Photo mode uses a 4:3 picture, video 16:9 (and the chosen quality):
  /// reopen the camera when that changes.
  void _matchCameraFormat() {
    if (_nativeCam == null || _isRecording || _dualOn) return;
    if (_openedAspect43 != _wantsAspect43 || (!_wantsAspect43 && _openedQuality != _videoQuality)) {
      unawaited(_reinitCamera());
    }
  }

  /// Landscape saving: tells the camera which way the phone is held.
  void _watchTilt() {
    _tiltSub?.cancel();
    _sizeSub?.cancel();
    _tiltSub = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen((e) {
      final rot = e.x.abs() > e.y.abs() && e.x.abs() > 6.5 ? (e.x > 0 ? 1 : 3) : (e.y < -6.5 ? 2 : 0);
      if (rot == _deviceRotation) return;
      _deviceRotation = rot;
      unawaited(_nativeCam?.setDeviceRotation(rot).catchError((_) {}));
    });
  }

  // Professional Cinema & Color Science State
  bool _showProTelemetryDeck = false;
  bool _toolbarExpanded = false;
  bool _voiceShutterOn = false;
  final CameraVoiceCommandParser _voiceParser = const CameraVoiceCommandParser();
  StreamSubscription? _quickAccessSub;

  // Host Shorts Multi-Cam State
  /// This phone is Cam B: its camera streams to a host phone.
  bool _camB = false;
  String? _pendingAnglePath;
  Offset _pipOffset = const Offset(16, 140);
  final TextEditingController _pairCodeController = TextEditingController();

  // OneOva Studio Theme Colors (Strict: Blue Dominant, Pink Secondary Accent)
  static const Color obsidianDark = Color(0xFF08080A);
  static const Color glassSurface = Color(0x9E121218);
  static const Color brandBlue = AppColors.brandBlue; // #007AFF DOMINANT
  static const Color brandPink = AppColors.brandPink; // #FF2D87 SECONDARY ACCENT ONLY
  static const Color brandCyan = AppColors.brandBlue; // Replaced rogue cyan with brandBlue

  final List<String> _durationModes = const ['PHOTO', '15s', '60s', '10m', 'DUAL CAM'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Take exclusive control of the microphone from any background speech listener.
    unawaited(SpeechHub.instance.preemptAll());
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
      if (!mounted) return;
      if (_nativeArAvailable) {
        // The native camera stays open; effects only change what it tracks.
        return;
      }
      if (!next.needs.any) return;
      if (!_arResolution) {
        _arResolution = true;
        _reinitCamera();
      } else {
        _attachAr();
      }
    });
    _ar = ref.read(liveArControllerProvider.notifier);
    // Open clean: nothing from a previous session is applied until picked.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ar.clearAll();
    });
    _arResolution = !_nativeArAvailable && ref.read(liveArControllerProvider).needs.any;
    _beauty = 0;
    _loadCaptureSettings();
    _initCamera();
  }

  Future<void> _loadCaptureSettings() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _recordAudio = p.getBool('camera_record_audio') ?? true;
        _autoStabilize = p.getBool('camera_auto_stabilize') ?? false;
        _cleanVoice = p.getBool('camera_clean_voice') ?? false;
        _lowLight = p.getBool('camera_low_light') ?? false;
        _videoQuality = p.getString('camera_video_quality') ?? '1080p30';
        // The camera always opens clean (no filter) — exactly what the lens sees.
        _showGrid = p.getBool('camera_grid') ?? false;
      });
    } catch (_) {}
  }

  Future<void> _saveSetting(String key, Object value) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (value is bool) await p.setBool(key, value);
      if (value is String) await p.setString(key, value);
      if (value is double) await p.setDouble(key, value);
    } catch (_) {}
  }

  bool get _nativeArAvailable => OneovaArCamera.isSupported && !_nativeFailed;

  /// Releases whichever camera is open (Flutter or native AR).
  Future<void> _releaseCamera() async {
    _ar.detachCamera();
    final native = _nativeCam;
    if (native != null) {
      _ar.detachNativeCamera();
      _nativeCam = null;
      _nativeInfo = null;
      await native.close();
    }
    final old = _cameraController;
    _cameraController = null;
    await old?.dispose();
  }

  Future<void> _openNativeCamera(CameraDescription camera) async {
    final cam = OneovaArCamera.instance;
    try {
      _openedAspect43 = _wantsAspect43;
      _openedQuality = _videoQuality;
      final info = await cam.open(
        front: camera.lensDirection == CameraLensDirection.front,
        aspect43: _openedAspect43,
        quality: _openedAspect43 ? '1080p30' : _videoQuality,
      );
      if (!mounted) {
        await cam.close();
        return;
      }
      _nativeCam = cam;
      _nativeInfo = info;
      _gradeKeyPending = null;
      _gradeKeySent = null;
      setState(() => _isInitialized = true);
      await _ar.attachNativeCamera(cam, mirror: info.mirrored);
      // The camera can correct its picture size after opening (rotation known
      // later): keep the on-screen box at the picture's true shape.
      _sizeSub?.cancel();
      _sizeSub = cam.frames.where((e) => e['type'] == 'previewSize').listen((e) {
        final w = (e['width'] as num?)?.toInt();
        final h = (e['height'] as num?)?.toInt();
        final cur = _nativeInfo;
        if (!mounted || w == null || h == null || cur == null || _nativeCam != cam) return;
        setState(() => _nativeInfo = ArCameraInfo(textureId: cur.textureId, width: w, height: h, mirrored: cur.mirrored));
      });
      if (_flashMode != FlashMode.off) await _applyFlash(_flashMode);
      if (_lowLight) await cam.setLowLight(true);
      await cam.setDeviceRotation(_deviceRotation);
      _watchDarkness();
      _watchTilt();
      await _readExposureRange();
      await _readZoomRange();
      unawaited(_applyCaptureMode(_captureMode, announce: false));
      if (_activeDurationMode == 'DUAL CAM') unawaited(_setDual(true));
    } catch (e) {
      debugPrint('Native AR camera failed, using the Flutter camera: $e');
      _nativeFailed = true;
      _nativeCam = null;
      _nativeInfo = null;
      _arResolution = ref.read(liveArControllerProvider).needs.any;
      await _initCamera();
    }
  }

  void _attachAr() {
    final c = _cameraController;
    if (c == null || !c.value.isInitialized || _cameras.isEmpty) return;
    ref
        .read(liveArControllerProvider.notifier)
        .attachCamera(c, _cameras[_selectedCameraIndex.clamp(0, _cameras.length - 1)]);
  }

  Future<void> _reinitCamera() async {
    if (_isRecording || _switchingCamera) return;
    _switchingCamera = true;
    try {
      if (mounted) setState(() => _isInitialized = false);
      await _releaseCamera();
      await _initCamera();
    } finally {
      _switchingCamera = false;
    }
    // The camera may have been needed again while it was switching.
    if (mounted && _nativeArAvailable && _nativeCam == null && !_isInitialized) {
      unawaited(_reinitCamera());
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _isInitialized = false);
        return;
      }

      final camera = _cameras[_selectedCameraIndex.clamp(0, _cameras.length - 1)];
      // Android: the native Oneova camera (CameraX) for real focus,
      // exposure, manual controls, dual camera and effects baked in video.
      if (_nativeArAvailable) {
        await _openNativeCamera(camera);
        return;
      }
      _cameraController = CameraController(
        camera,
        _arResolution ? ResolutionPreset.high : ResolutionPreset.ultraHigh,
        enableAudio: _recordAudio,
        // NV21 is what ML Kit reads on Android (only the AR frame stream uses it).
        imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
      );


      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        _attachAr();
        await _readExposureRange();
        await _readZoomRange();
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
      if (mounted) setState(() => _isInitialized = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(SpeechHub.instance.cancel(this));
    _quickAccessSub?.cancel();
    _recordingTimer?.cancel();
    _focusHideTimer?.cancel();
    _gradeTimer?.cancel();
    _darkTimer?.cancel();
    _zoomHideTimer?.cancel();
    _tiltSub?.cancel();
    if (_screenLight) unawaited(_setScreenBright(false));
    _soundPlayer?.dispose();
    _arSub?.close();
    unawaited(_releaseCamera());
    _pairCodeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cameraController = _cameraController;
    final open = _nativeCam != null || (cameraController != null && cameraController.value.isInitialized);
    if (state == AppLifecycleState.inactive) {
      if (!open) return;
      if (_isRecording && _nativeCam != null) _stopVideoRecording();
      _releasedInBackground = true;
      _releaseCamera();
    } else if (state == AppLifecycleState.resumed && _releasedInBackground) {
      _releasedInBackground = false;
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

    final nativeCam = _nativeCam;
    if ((nativeCam != null || (_cameraController != null && _cameraController!.value.isInitialized)) &&
        !_isRecording) {
      try {
        final shot = await _withScreenFlash(() async {
          // Shutter feedback: sound + a quick blink of the picture.
          unawaited(nativeCam?.playSound('shutter').catchError((_) {}));
          setState(() => _shutterBlink = true);
          Future.delayed(const Duration(milliseconds: 90), () {
            if (mounted) setState(() => _shutterBlink = false);
          });
          return nativeCam != null ? await nativeCam.takePicture() : (await _cameraController!.takePicture()).path;
        });
        var path = shot;
        if (ref.read(liveArControllerProvider).hasAnything) {
          try {
            path = await ref.read(liveArControllerProvider.notifier).bakePhoto(shot) ?? path;
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

    // Release any in-app speech recognizer before opening the hardware audio recorder.
    await SpeechHub.instance.preemptAll();

    // Focus and exposure keep following the scene while recording unless the
    // user locked them (long-press); a lock set before recording stays.

    // Trigger Host Shorts multi-cam synchronized recording across paired devices
    final hostSession = ref.read(hostShortsServiceProvider);
    if (hostSession != null && hostSession.isConnected) {
      final share = ref.read(hostShortsServiceProvider.notifier);
      share.triggerSyncRecord(true);
      // Angle B is recorded on this phone next to the main take.
      if (hostSession.layout != HostShortsLayout.soloCamA) unawaited(share.startAngleRecording());
    }

    final nativeCam = _nativeCam;
    if (nativeCam != null) {
      // The native AR camera bakes the live effects into the video.
      var withAudio = _recordAudio;
      if (withAudio && await nativeCam.micBusy() && mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: ctx.surface,
            title: Text('Microphone is busy', style: TextStyle(color: ctx.textPrimary, fontWeight: FontWeight.w800)),
            content: Text(
              'Another app is using the microphone (a call, a voice assistant or a recorder), so the video would have no sound. Close that app and try again, or record without sound.',
              style: TextStyle(color: ctx.textSecondary),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Record without sound')),
            ],
          ),
        );
        if (go != true) {
          final host = ref.read(hostShortsServiceProvider);
          if (host != null && host.isConnected) ref.read(hostShortsServiceProvider.notifier).triggerSyncRecord(false);
          return;
        }
        withAudio = false;
      }
      try {
        unawaited(nativeCam.playSound('start').catchError((_) {}));
        _nativeRecordingPath = await nativeCam.startRecording(audio: withAudio);
        if (withAudio) unawaited(_warnIfMicBusy(nativeCam));
      } catch (e) {
        debugPrint('Start recording error: $e');
      }
    } else if (_cameraController != null && _cameraController!.value.isInitialized) {
      if (ref.read(liveArControllerProvider).hasAnything && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Effects are saved into photos. Videos record without them on this device.')),
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
    unawaited(_playSound());

    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _recordingSecondsElapsed++);
      // 15s / 60s / 10m stop on their own.
      final limit = _limitSeconds;
      if (limit != null && _recordingSecondsElapsed >= limit && _isRecording) _stopVideoRecording();
    });
  }

  /// Android mutes our microphone while another app records (a call, a
  /// voice assistant); say so instead of saving a silent video unnoticed.
  Future<void> _warnIfMicBusy(OneovaArCamera cam) async {
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted || !_isRecording) return;
    try {
      if ((await cam.stats())['micSilenced'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 5),
          backgroundColor: AppColors.brandPink,
          content: Text('Another app is using the microphone, so this video has no sound. Close that app (or end its call) and record again.'),
        ));
      }
    } catch (_) {}
  }

  /// Length limit of the selected mode, in seconds.
  int? get _limitSeconds => switch (_activeDurationMode) {
        '15s' => 15,
        '60s' => 60,
        '10m' => 600,
        _ => null,
      };

  Future<void> _playSound() async {
    final src = _soundSource;
    if (src == null) return;
    try {
      final player = _soundPlayer ??= Player();
      await player.open(Media(src), play: false);
      await player.seek(Duration.zero);
      await player.play();
      _soundUsed = true;
    } catch (e) {
      debugPrint('[Camera] sound playback failed: $e');
    }
  }

  Future<void> _stopVideoRecording() async {
    HapticFeedback.lightImpact();
    _recordingTimer?.cancel();
    unawaited(_soundPlayer?.pause());

    // Stop synchronized recording on secondary paired camera
    final hostSession = ref.read(hostShortsServiceProvider);
    if (hostSession != null && hostSession.isConnected) {
      final share = ref.read(hostShortsServiceProvider.notifier);
      share.triggerSyncRecord(false);
      _pendingAnglePath = await share.stopAngleRecording();
    }

    final nativeCam = _nativeCam;
    final nativePath = _nativeRecordingPath;
    _nativeRecordingPath = null;
    if (nativeCam != null && nativePath != null) {
      try {
        await nativeCam.stopRecording();
        unawaited(nativeCam.playSound('stop').catchError((_) {}));
        setState(() => _isRecording = false);
        if (mounted) {
          _navigateToPreview(nativePath, isVideo: true);
        }
        return;
      } catch (e) {
        debugPrint('Stop recording error: $e');
      }
    } else if (_cameraController != null && _cameraController!.value.isRecordingVideo) {
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
      setState(() => _countdown = count);
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) break;
      count--;
    }
    if (mounted) setState(() => _countdown = 0);
  }

  Future<void> _toggleFlipCamera() async {
    HapticFeedback.lightImpact();
    if (_dualOn) {
      _updateDualLayout(_dualLayout.copyWith(swap: !_dualLayout.swap));
      return;
    }
    if (_cameras.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No secondary camera available on this device.')),
      );
      return;
    }
    if (_isRecording) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    setState(() => _isInitialized = false);
    await _releaseCamera();
    await _initCamera();
  }

  bool get _isFront {
    if (_cameras.isEmpty) return false;
    return _cameras[_selectedCameraIndex.clamp(0, _cameras.length - 1)].lensDirection == CameraLensDirection.front;
  }

  /// Off → Auto → On (fires for the photo) → Torch (stays on, for video).
  /// The front camera has no flash: Auto/On light the screen instead.
  Future<void> _toggleFlash() async {
    HapticFeedback.lightImpact();
    if (_cameraController == null && _nativeCam == null) return;
    final nextMode = switch (_flashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      FlashMode.always => FlashMode.torch,
      FlashMode.torch => FlashMode.off,
    };
    try {
      await _applyFlash(nextMode);
      setState(() => _flashMode = nextMode);
      final label = switch (nextMode) {
        FlashMode.off => 'Flash off',
        FlashMode.auto => _isFront ? 'Screen flash: auto in the dark' : 'Flash: auto',
        FlashMode.always => _isFront ? 'Screen flash on' : 'Flash on',
        FlashMode.torch => _isFront ? 'Screen light on' : 'Torch on',
      };
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(label), duration: const Duration(milliseconds: 900)));
      }
    } catch (e) {
      debugPrint('Set flash mode error: $e');
    }
  }

  Future<void> _applyFlash(FlashMode mode) async {
    final native = _nativeCam;
    if (native != null) {
      await native.setTorch(mode == FlashMode.torch && !_isFront);
      await native.setFlashMode(switch (mode) {
        FlashMode.auto => 'auto',
        FlashMode.always => 'always',
        _ => 'off',
      });
    } else {
      await _cameraController?.setFlashMode(_isFront && mode == FlashMode.torch ? FlashMode.off : mode);
    }
    // Front "torch": keep the screen bright and lit while recording selfies.
    if (_isFront) {
      setState(() => _screenLight = mode == FlashMode.torch);
      await _setScreenBright(mode == FlashMode.torch);
    }
  }

  bool _screenLight = false;
  bool _screenFlash = false;

  Future<void> _setScreenBright(bool on) async {
    try {
      if (on) {
        await ScreenBrightness.instance.setApplicationScreenBrightness(1.0);
      } else {
        await ScreenBrightness.instance.resetApplicationScreenBrightness();
      }
    } catch (_) {}
  }

  /// Front camera flash: the screen turns full-bright white for the shot.
  Future<T> _withScreenFlash<T>(Future<T> Function() shoot) async {
    final want = _isFront && (_flashMode == FlashMode.always || (_flashMode == FlashMode.auto && _ev <= 0 && _looksDark));
    if (!want) return shoot();
    setState(() => _screenFlash = true);
    await _setScreenBright(true);
    // Let the camera's auto exposure settle on the lit face.
    await Future.delayed(const Duration(milliseconds: 380));
    try {
      return await shoot();
    } finally {
      if (mounted) setState(() => _screenFlash = false);
      if (!_screenLight) await _setScreenBright(false);
    }
  }

  /// Dark scene, from the camera's own frame rate (auto exposure slows the
  /// sensor down in low light).
  bool _looksDark = false;

  void _watchDarkness() {
    _darkTimer?.cancel();
    _darkTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final n = _nativeCam;
      if (n == null || !mounted) return;
      try {
        final fps = ((await n.stats())['previewFps'] as num?)?.toDouble() ?? 30;
        _looksDark = fps > 0 && fps < (_lowLight ? 14 : 23);
        // Heat guard: from "moderate" on, tracking runs lighter.
        final heat = await n.thermalStatus();
        await n.setThrottle(heat >= 2);
        if (heat >= 2 && !_heatWarned && mounted) {
          _heatWarned = true;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Your phone is warm, so effects now run lighter to keep it cool.'),
            duration: Duration(seconds: 3),
          ));
        }
      } catch (_) {}
    });
  }

  /// Photos and videos from the gallery or any file on the phone (several
  /// at once, in pick order) straight into the editor.
  Future<void> _pickFromGallery() async {
    HapticFeedback.lightImpact();
    final res = await _awayFromCamera(() => context.push<StudioPickResult>('/create/studio/picker?mode=any&multi=1'));
    if (res == null || res.picks.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final clips = <StudioClip>[];
      for (final pick in res.picks) {
        var clip = await StudioMedia.clipFromFile(pick.path, isImage: pick.isImage);
        if (!pick.isImage && pick.endMs > pick.startMs && pick.endMs > 0) {
          clip = clip.copyWith(
            startMs: pick.startMs.clamp(0, clip.sourceDurationMs),
            endMs: pick.endMs.clamp(0, clip.sourceDurationMs),
          );
        }
        clips.add(clip);
      }
      await _openEditor(clips, isPhoto: clips.length == 1 && clips.first.isImage, hd: res.hd);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open that media: $e'), backgroundColor: AppColors.brandPink));
    }
  }

  Future<void> _navigateToPreview(
    String path, {
    required bool isVideo,
    double trimStartSeconds = 0.0,
    double trimEndSeconds = 0.0,
    double speedMultiplier = 1.0,
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
      await _openEditor([_withCameraGrade(clip)], isPhoto: !isVideo, withSound: isVideo);
    } catch (e) {
      debugPrint('[CameraScreen] opening editor failed: $e');
      messenger.showSnackBar(SnackBar(content: Text('Could not open the editor: $e'), backgroundColor: AppColors.brandPink));
    }
  }

  /// The camera's filter, enhance and capture settings on a captured clip.
  StudioClip _withCameraGrade(StudioClip c) {
    // Already baked by the native camera: keep it, nothing to apply twice.
    if (_gradeIsBaked) {
      return c.copyWith(
        stabilize: !c.isImage && _autoStabilize ? 0.5 : null,
        voiceClean: !c.isImage && _cleanVoice && _recordAudio ? 0.6 : null,
        muted: !c.isImage && _soundUsed ? true : null,
      );
    }
    var adjust = c.adjust;
    final cam = _camAdjust.toJson();
    for (final k in StudioAdjust.keys) {
      final v = (cam[k] as num?)?.toDouble() ?? 0;
      if (v != 0) adjust = adjust.withValue(k, v);
    }
    return c.copyWith(
      lookId: _filterId,
      lookIntensity: _filterIntensity,
      adjust: adjust,
      stabilize: !c.isImage && _autoStabilize ? 0.5 : null,
      voiceClean: !c.isImage && _cleanVoice && _recordAudio ? 0.6 : null,
      // With a sound playing, the take is about the sound: the mic starts
      // muted (turn it back up in the editor).
      muted: !c.isImage && _soundUsed ? true : null,
    );
  }

  Future<void> _openEditor(List<StudioClip> clips, {required bool isPhoto, bool withSound = false, bool hd = false}) async {
    var project = StudioProject.create(isPhoto: isPhoto, clips: clips);
    final angle = _pendingAnglePath;
    _pendingAnglePath = null;
    if (angle != null && !isPhoto) project = await _withAngleB(project, angle);
    if (withSound && _soundUsed && _soundSource != null && !isPhoto) {
      final audio = await _soundAsAudio(project.durationMs);
      if (audio != null) project = project.copyWith(audios: [audio]);
    }
    _soundUsed = false;
    // Every take is a Studio draft from the start, so nothing is lost if
    // the editor is closed or the app is stopped.
    try {
      project = await ref.read(studioProjectStoreProvider.notifier).save(project);
    } catch (e) {
      debugPrint('[Camera] draft save failed: $e');
    }
    // STORY mode posts to stories; every other mode publishes a post.
    final target = _activeBroadcastMode == 'STORY' ? StudioTarget.story : StudioTarget.post;
    if (!mounted) return;
    await _awayFromCamera(() => context.push('/create/studio/editor', extra: StudioEditorArgs(project: project, target: target)));
  }

  /// Camera share: Angle B as a picture-in-picture overlay (PiP / split
  /// layouts) or as the main shot (Cam B solo), synced from the start.
  Future<StudioProject> _withAngleB(StudioProject p, String path) async {
    try {
      final kept = await StudioProjectStore.keepFile(path);
      final b = await StudioMedia.clipFromFile(kept, isImage: false);
      final layout = ref.read(hostShortsServiceProvider)?.layout ?? HostShortsLayout.pip;
      switch (layout) {
        case HostShortsLayout.soloCamB:
          return p.copyWith(clips: [b.copyWith(muted: true), ...p.clips.skip(1)]);
        case HostShortsLayout.splitVertical:
        case HostShortsLayout.splitHorizontal:
          final o = StudioOverlay.fromClip(b, offsetMs: 0, maxMs: p.durationMs);
          return p.copyWith(overlays: [o.copyWith(x: 0, y: -0.5, scale: 1, muted: true)]);
        case HostShortsLayout.pip:
        case HostShortsLayout.soloCamA:
          final o = StudioOverlay.fromClip(b, offsetMs: 0, maxMs: p.durationMs);
          return p.copyWith(overlays: [o.copyWith(x: 0.55, y: -0.55, scale: 0.36, muted: true)]);
      }
    } catch (e) {
      debugPrint('[Camera] Angle B could not be added: $e');
      return p;
    }
  }

  /// This phone becomes Cam B: free the camera, stream it to the host.
  Future<void> _joinAsCamB(String code) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _camB = true;
      _isInitialized = false;
    });
    await _releaseCamera();
    final share = ref.read(hostShortsServiceProvider.notifier);
    final ok = await share.joinAsCamB(code);
    if (!mounted) return;
    if (!ok) {
      setState(() => _camB = false);
      messenger.showSnackBar(SnackBar(content: Text(share.lastError ?? 'Could not join.'), backgroundColor: AppColors.brandPink));
      await _initCamera();
    } else {
      setState(() {});
    }
  }

  Future<void> _leaveCamB() async {
    await ref.read(hostShortsServiceProvider.notifier).disconnectSession();
    if (!mounted) return;
    setState(() => _camB = false);
    await _initCamera();
  }

  Widget _buildCamBView(HostShortsSession? session) {
    final share = ref.read(hostShortsServiceProvider.notifier);
    final streaming = session?.status == HostShortsStatus.streaming;
    final rec = session?.isSyncedRecording == true;
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: obsidianDark),
        RTCVideoView(share.localRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: rec ? brandPink : glassSurface, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(rec ? Icons.fiber_manual_record_rounded : Icons.cell_tower_rounded, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    rec
                        ? 'Host is recording'
                        : streaming
                            ? 'Streaming to host · ${session?.remoteDevice?.resolution ?? ''} · ${session?.remoteDevice?.latencyMs ?? 0} ms'
                            : 'Connecting to ${session?.pairCode ?? ''}…',
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandPink,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  onPressed: _leaveCamB,
                  icon: const Icon(Icons.link_off_rounded, color: Colors.white),
                  label: Text('Stop sharing', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The picked sound as a project audio track (downloaded when remote).
  Future<StudioAudio?> _soundAsAudio(int takeMs) async {
    final src = _soundSource;
    if (src == null) return null;
    try {
      var path = src;
      if (src.startsWith('http')) {
        final dir = await StudioProjectStore.dir('sounds');
        final file = File('${dir.path}/sound_${src.hashCode.abs()}.m4a');
        if (!await file.exists() || await file.length() == 0) {
          final req = await HttpClient().getUrl(Uri.parse(src));
          final resp = await req.close();
          if (resp.statusCode != 200) return null;
          await resp.pipe(file.openWrite());
        }
        path = file.path;
      }
      final probe = await StudioMedia.probeAudio(path);
      final dur = probe.duration.inMilliseconds > 0 ? probe.duration.inMilliseconds : _soundDurationMs;
      return StudioAudio.create(
        path: path,
        title: _selectedSoundTitle ?? 'Sound',
        durationMs: dur,
        endMs: math.min(dur, math.max(1000, takeMs)),
      );
    } catch (e) {
      debugPrint('[Camera] sound could not be added: $e');
      return null;
    }
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
  // Focus, exposure, zoom, dual camera, manual controls
  // ────────────────────────────────────────────────────────────────────────

  /// Pixel size of the upright preview (what BoxFit.cover scales).
  Size? get _previewPixelSize {
    final n = _nativeInfo;
    if (_nativeCam != null && n != null) return Size(n.width.toDouble(), n.height.toDouble());
    final c = _cameraController;
    final ps = c?.value.previewSize;
    if (c == null || !c.value.isInitialized || ps == null) return null;
    return Size(ps.height, ps.width);
  }

  Future<void> _readExposureRange() async {
    try {
      final n = _nativeCam;
      if (n != null) {
        final info = await n.exposureInfo();
        _manualCaps = await n.manualInfo();
        if (!mounted) return;
        setState(() {
          _evMin = (info['minEv'] as num?)?.toDouble() ?? -2;
          _evMax = (info['maxEv'] as num?)?.toDouble() ?? 2;
          _ev = 0;
        });
        return;
      }
      final c = _cameraController;
      if (c == null || !c.value.isInitialized) return;
      final lo = await c.getMinExposureOffset();
      final hi = await c.getMaxExposureOffset();
      if (!mounted) return;
      setState(() {
        _evMin = lo;
        _evMax = hi;
        _ev = 0;
      });
    } catch (e) {
      debugPrint('[Camera] exposure range unavailable: $e');
    }
  }

  /// Tap: focus + meter there. Long-press: lock AE/AF there.
  /// Where the camera picture sits on screen: its true aspect, never
  /// cropped or stretched (black bars like the stock camera). 4:3 photos sit
  /// under the top bar; 16:9 video is centred.
  Rect _previewRect(Size screen) {
    final pv = _previewPixelSize ?? Size(1080, _activeDurationMode == 'PHOTO' ? 1440 : 1920);
    final aspect = pv.width / pv.height;
    var w = screen.width;
    var h = w / aspect;
    if (h > screen.height) {
      h = screen.height;
      w = h * aspect;
    }
    final top = aspect > 0.7
        ? math.min(MediaQuery.of(context).padding.top + 64, screen.height - h)
        : (screen.height - h) / 2;
    return Rect.fromLTWH((screen.width - w) / 2, math.max(0, top), w, h);
  }

  Rect _lastPreviewRect = Rect.zero;

  Future<void> _onViewfinderTap(Offset local, Size box, {required bool lock}) async {
    if (_showFilters || _showEnhance) {
      setState(() {
        _showFilters = false;
        _showEnhance = false;
      });
      return;
    }
    // [local] is relative to the picture itself ([box] is its size).
    if (box.width <= 0 || box.height <= 0) return;
    final nx = (local.dx / box.width).clamp(0.0, 1.0);
    final ny = (local.dy / box.height).clamp(0.0, 1.0);
    lock ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
    setState(() {
      _focusTap = _lastPreviewRect.topLeft + local;
      _focusLocked = lock;
      _showFocusUi = true;
      _ev = 0;
    });
    _scheduleFocusHide();
    final looks = ref.read(cameraLooksControllerProvider.notifier);
    try {
      final native = _nativeCam;
      if (native != null) {
        await native.setExposure(0);
        await native.focusAt(nx, ny, lock: lock);
      } else {
        final c = _cameraController;
        if (c == null || !c.value.isInitialized) return;
        final pt = Offset(nx, ny);
        await c.setFocusMode(FocusMode.auto);
        await c.setExposureMode(ExposureMode.auto);
        await c.setExposureOffset(0);
        if (c.value.focusPointSupported) await c.setFocusPoint(pt);
        if (c.value.exposurePointSupported) await c.setExposurePoint(pt);
        if (lock) {
          await c.setFocusMode(FocusMode.locked);
          await c.setExposureMode(ExposureMode.locked);
        }
      }
      if (lock) {
        await looks.engageSmartLock();
      } else if (ref.read(cameraLooksControllerProvider).smartLock.isSmartLockActive && !_isRecording) {
        await looks.releaseSmartLock();
      }
    } catch (e) {
      debugPrint('[Camera] focus failed: $e');
    }
  }

  Future<void> _unlockFocus() async {
    HapticFeedback.lightImpact();
    setState(() {
      _focusLocked = false;
      _showFocusUi = false;
    });
    try {
      await _nativeCam?.unlockFocus();
    } catch (_) {}
    await ref.read(cameraLooksControllerProvider.notifier).releaseSmartLock(_cameraController);
  }

  void _scheduleFocusHide() {
    _focusHideTimer?.cancel();
    _focusHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showFocusUi = false);
    });
  }

  /// Exposure compensation, throttled to one camera call at a time.
  Future<void> _setEv(double v) async {
    final ev = v.clamp(_evMin, _evMax).toDouble();
    setState(() => _ev = ev);
    _scheduleFocusHide();
    if (_evBusy) {
      _evPending = ev;
      return;
    }
    _evBusy = true;
    try {
      double? next = ev;
      while (next != null) {
        _evPending = null;
        final n = _nativeCam;
        if (n != null) {
          await n.setExposure(next);
        } else {
          await _cameraController?.setExposureOffset(next);
        }
        next = _evPending;
      }
    } catch (e) {
      debugPrint('[Camera] exposure failed: $e');
    } finally {
      _evBusy = false;
    }
  }

  double _zoom = 1;
  double _zoomAtStart = 1;
  double _minZoom = 1;
  double _maxZoom = 8;
  bool _showZoomSlider = false;
  Timer? _zoomHideTimer;

  /// Reads the lens range (min < 1 = ultra-wide) and starts at 1x.
  Future<void> _readZoomRange() async {
    try {
      final n = _nativeCam;
      if (n != null) {
        final z = await n.zoomInfo();
        _minZoom = ((z['min'] as num?)?.toDouble() ?? 1).clamp(0.3, 1.0);
        _maxZoom = math.min(10, (z['max'] as num?)?.toDouble() ?? 8);
      } else {
        final c = _cameraController;
        if (c == null || !c.value.isInitialized) return;
        _minZoom = (await c.getMinZoomLevel()).clamp(0.3, 1.0);
        _maxZoom = math.min(10, await c.getMaxZoomLevel());
      }
      if (mounted) setState(() => _zoom = 1);
    } catch (_) {}
  }

  void _revealZoomSlider() {
    _zoomHideTimer?.cancel();
    if (!_showZoomSlider) setState(() => _showZoomSlider = true);
    _zoomHideTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _showZoomSlider = false);
    });
  }

  Future<void> _setZoom(double z) async {
    final zoom = z.clamp(_minZoom, _maxZoom).toDouble();
    _revealZoomSlider();
    if ((zoom - _zoom).abs() < 0.02) return;
    setState(() => _zoom = zoom);
    try {
      final n = _nativeCam;
      if (n != null) {
        await n.setZoom(zoom);
      } else {
        final c = _cameraController;
        if (c == null || !c.value.isInitialized) return;
        await c.setZoomLevel(zoom);
      }
    } catch (_) {}
  }

  Future<void> _setDual(bool on) async {
    final n = _nativeCam;
    final messenger = ScaffoldMessenger.of(context);
    if (!on) {
      if (!_dualOn) return;
      setState(() => _dualOn = false);
      try {
        await n?.setDual(false);
      } catch (_) {}
      return;
    }
    if (n == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Dual camera needs the Oneova camera engine on Android.')));
      setState(() => _activeDurationMode = '60s');
      return;
    }
    try {
      await n.setDual(true, layout: _dualLayout);
      if (mounted) setState(() => _dualOn = true);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _activeDurationMode = '60s');
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 5),
        content: Text(e.code == 'dual_unsupported'
            ? 'This phone can\'t run the front and back cameras at the same time. Use Camera share (HOST SHORTS) to film a second angle with another phone.'
            : 'Dual camera could not start on this phone.'),
      ));
    }
  }

  void _updateDualLayout(ArDualLayout layout) {
    setState(() => _dualLayout = layout);
    unawaited(_nativeCam?.setDualLayout(layout).catchError((_) {}));
  }

  bool _manualWarned = false;

  /// Sends the Pro deck's ISO / shutter / white balance / focus to the camera.
  void _applyManual() {
    final st = ref.read(cameraLooksControllerProvider).smartLock;
    final n = _nativeCam;
    void warn(String msg) {
      if (_manualWarned) return;
      _manualWarned = true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }

    if (n == null) {
      warn('ISO, shutter, white balance and manual focus need the Oneova camera engine (Android). Exposure works here.');
      return;
    }
    final manualSensor = _manualCaps['manualSensor'] == true;
    int? iso = st.iso;
    int? ns = st.shutterSeconds == null ? null : (st.shutterSeconds! * 1e9).round();
    if (iso != null || ns != null) {
      if (!manualSensor) {
        warn('This camera does not allow manual ISO or shutter.');
        iso = null;
        ns = null;
      } else {
        iso ??= 400;
        ns ??= 16666667;
        final lo = (_manualCaps['isoMin'] as num?)?.toInt();
        final hi = (_manualCaps['isoMax'] as num?)?.toInt();
        if (lo != null && hi != null) iso = iso.clamp(lo, hi);
        final nlo = (_manualCaps['exposureMinNs'] as num?)?.toInt();
        final nhi = (_manualCaps['exposureMaxNs'] as num?)?.toInt();
        if (nlo != null && nhi != null) ns = ns.clamp(nlo, nhi);
      }
    }
    // Camera2 CONTROL_AWB_MODE values.
    final awb = switch (st.whiteBalanceMode) {
      'daylight' => 5,
      'cloudy' => 6,
      'tungsten' => 2,
      'fluorescent' => 3,
      _ => null,
    };
    double? focus;
    if (st.focusDistance != null) {
      if (_manualCaps['manualFocus'] == true) {
        focus = 1 - st.focusDistance!; // deck: 0 near … 1 far; camera: 0 far … 1 near
      } else {
        warn('This camera has a fixed-focus lens.');
      }
    }
    unawaited(n.setManual(iso: iso, exposureNs: ns, awb: awb, focus: focus).catchError((_) {}));
  }

  Future<void> _setBeauty(double v) async {
    setState(() => _beauty = v);
    final current = ref.read(liveArControllerProvider).active['makeup']?.makeup ?? const ArMakeup();
    ref.read(liveArControllerProvider.notifier).setMakeup(current.copyWith(smoothing: v));
  }

  /// Capture mode tuning (StudioAdjust keys), on top of any preset; the
  /// Enhance sliders add to it. Baked into captures like a filter.
  static const _modeAdjust = <String, Map<String, double>>{
    'vivid': {'vibrance': 0.35, 'saturation': 0.15, 'contrast': 0.08},
    'contrast': {'contrast': 0.3, 'blacks': -0.12, 'whites': 0.08, 'vibrance': 0.08},
    'hdr': {'highlights': -0.45, 'shadows': 0.4, 'vibrance': 0.12, 'contrast': 0.04},
    'night': {'exposure': 0.2, 'shadows': 0.35, 'highlights': -0.15},
    'portrait': {'contrast': 0.05, 'vibrance': 0.05},
  };

  String _captureMode = 'auto';
  bool _portraitBlurOn = false;

  /// Preset + capture mode + the Enhance sliders.
  StudioAdjust get _camAdjust {
    var a = _presetAdjust;
    final j = a.toJson();
    for (final e in (_modeAdjust[_captureMode] ?? const <String, double>{}).entries) {
      a = a.withValue(e.key, (((j[e.key] as num?)?.toDouble() ?? 0) + e.value).clamp(-1.0, 1.0));
    }
    final modeContrast = (a.toJson()['contrast'] as num?)?.toDouble() ?? 0;
    return a.withValue('brightness', _brightness).withValue('contrast', (modeContrast + _contrast).clamp(-1.0, 1.0));
  }

  /// Auto (natural) · Vivid · Contrast · HDR · Night · Portrait.
  Future<void> _applyCaptureMode(String mode, {bool announce = true}) async {
    final prev = _captureMode;
    setState(() => _captureMode = mode);
    final n = _nativeCam;
    try {
      await n?.setSceneMode(mode == 'hdr' || mode == 'night' ? mode : 'auto');
      await n?.setLowLight(mode == 'night' || _lowLight);
    } catch (_) {}
    final ar = ref.read(liveArControllerProvider.notifier);
    if (mode == 'portrait' && ref.read(liveArControllerProvider).backgroundMode == ArBackgroundMode.none) {
      ar.setBlur(true);
      ar.setBlurSigma(10);
      _portraitBlurOn = true;
    } else if (prev == 'portrait' && mode != 'portrait' && _portraitBlurOn) {
      ar.setBlur(false);
      _portraitBlurOn = false;
    }
    if (announce && mounted) {
      final scenes = (_manualCaps['sceneModes'] as List?)?.cast<num>() ?? const [];
      final text = switch (mode) {
        'vivid' => 'Vivid: richer colour',
        'contrast' => 'Contrast: deeper blacks, punchier light',
        'hdr' => scenes.contains(18) ? 'HDR: camera HDR + balanced highlights' : 'HDR: balanced highlights and shadows',
        'night' => scenes.contains(5) ? 'Night: camera night mode + brighter shadows' : 'Night: longer exposure + brighter shadows',
        'portrait' => 'Portrait: background blur',
        _ => 'Auto: natural, as the camera sees',
      };
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(milliseconds: 1200)));
    }
  }

  Widget _buildCaptureModeRow() {
    const modes = [('auto', 'Auto'), ('vivid', 'Vivid'), ('contrast', 'Contrast'), ('hdr', 'HDR'), ('night', 'Night'), ('portrait', 'Portrait')];
    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          for (final m in modes)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                if (!_isRecording) _applyCaptureMode(m.$1);
              },
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _captureMode == m.$1 ? brandBlue : Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white.withValues(alpha: _captureMode == m.$1 ? 0 : 0.18)),
                ),
                child: Text(m.$2,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 11.5, fontWeight: _captureMode == m.$1 ? FontWeight.w800 : FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
  }

  void _applyPreset(OneovaPreset p) {
    setState(() {
      _presetId = p.id;
      _filterId = p.filterId;
      _filterIntensity = p.intensity;
      _presetAdjust = p.applyTo(const StudioAdjust());
      _brightness = p.adjust['brightness'] ?? 0;
      _contrast = p.adjust['contrast'] ?? 0;
      _heldPreset = null;
      _heldFilterId = null;
    });
    _setBeauty(p.beauty);
    _saveSetting('camera_filter_id', p.filterId);
    _saveSetting('camera_filter_intensity', p.intensity);
  }

  String get _gradeKey => '${_filterId}_${_filterIntensity.toStringAsFixed(2)}_${_camAdjust.toJson().values.join(',')}';

  /// Whether captures from the open camera already carry the current grade.
  bool get _gradeIsBaked => _nativeCam != null && _gradeKeySent == _gradeKey;

  /// Sends the applied filter + brightness/contrast to the native camera so
  /// photos and videos come out graded (debounced while sliders move).
  void _syncNativeGrade() {
    final n = _nativeCam;
    if (n == null) return;
    final key = _gradeKey;
    if (key == _gradeKeyPending) return;
    _gradeKeyPending = key;
    _gradeTimer?.cancel();
    _gradeTimer = Timer(const Duration(milliseconds: 180), () async {
      final adjust = _camAdjust;
      final look = StudioLooks.forLook(_filterId, _filterIntensity, adjust);
      final m = StudioColor.adjustMatrix(adjust);
      try {
        Map<String, Object>? lookMap;
        if (look != null) lookMap = (await LookCompiler.compile(look, maxLutSize: 33)).toNative().toMap();
        if (!mounted || _nativeCam != n || _gradeKeyPending != key) return;
        await n.setGrade(look: lookMap, matrix: StudioColor.isIdentity(m) ? null : m);
        _gradeKeySent = key;
      } catch (e) {
        debugPrint('[Camera] native grade failed, the editor will apply it: $e');
      }
    });
  }

  /// The live grade: Flutter shader over the camera texture, same engine as
  /// the Studio preview and export.
  Widget _graded(Widget preview) {
    if (_nativeCam != null && _gradeKey != _gradeKeyPending) scheduleMicrotask(_syncNativeGrade);
    final hp = _heldPreset;
    final adjust = hp != null ? hp.applyTo(const StudioAdjust()) : _camAdjust;
    final m = StudioColor.adjustMatrix(adjust);
    if (!StudioColor.isIdentity(m)) preview = ColorFiltered(colorFilter: ColorFilter.matrix(m), child: preview);
    final held = _heldFilterId;
    final look = hp != null
        ? StudioLooks.forLook(hp.filterId, hp.intensity, adjust)
        : StudioLooks.forLook(held ?? _filterId, held != null ? 1.0 : _filterIntensity, adjust);
    if (look != null) preview = StudioLookFilter(look: look, child: preview);
    return preview;
  }

  // ────────────────────────────────────────────────────────────────────────
  // Build Screen
  // ────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hostSession = ref.watch(hostShortsServiceProvider);
    final isHostShortsActive = _activeBroadcastMode == 'HOST SHORTS' || (hostSession != null && hostSession.isConnected);
    final cameraLooksState = ref.watch(cameraLooksControllerProvider);
    if (_camB) {
      return Scaffold(backgroundColor: Colors.black, body: _buildCamBView(hostSession));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Live viewfinder: tap to focus, long-press to lock AE/AF, pinch to zoom.
          Positioned.fill(
            child: LayoutBuilder(builder: (ctx, box) {
              final r = _previewRect(box.biggest);
              _lastPreviewRect = r;
              return Stack(children: [
                // Taps on the black bars close panels; pinch zooms anywhere.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() {
                      _showFilters = false;
                      _showEnhance = false;
                    }),
                    onScaleStart: (_) => _zoomAtStart = _zoom,
                    onScaleUpdate: (d) {
                      if (d.pointerCount >= 2) _setZoom(_zoomAtStart * d.scale);
                    },
                  ),
                ),
                Positioned.fromRect(
                  rect: r,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _onViewfinderTap(d.localPosition, r.size, lock: false),
                    onLongPressStart: (d) => _onViewfinderTap(d.localPosition, r.size, lock: true),
                    onScaleStart: (_) => _zoomAtStart = _zoom,
                    onScaleUpdate: (d) {
                      if (d.pointerCount >= 2) _setZoom(_zoomAtStart * d.scale);
                    },
                    child: Stack(fit: StackFit.expand, children: [
                      _buildCameraViewfinder(),
                      // 2. Viewfinder guides, on the picture only.
                      if (_showGrid) _buildRuleOfThirdsGrid(),
                      if (_shutterBlink) const IgnorePointer(child: ColoredBox(color: Colors.black)),
                    ]),
                  ),
                ),
              ]);
            }),
          ),

          // 3. Vignette & Cinematic Gradient
          _buildCinematicVignette(),

          // 4. Focus box, AE/AF lock and exposure slider
          ..._buildFocusOverlay(),
          if (_dualOn && _dualLayout.layout == 'pip') _buildDualPipHandle(),
          if (_screenFlash)
            const Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Colors.white))),
          if (_screenLight && !_screenFlash)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(border: Border.all(color: Colors.white.withValues(alpha: 0.92), width: 46)),
                ),
              ),
            ),
          if (_countdown > 0)
            IgnorePointer(
              child: Center(
                child: Text(
                  '$_countdown',
                  style: GoogleFonts.inter(
                    fontSize: 96,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    shadows: const [Shadow(color: Colors.black54, blurRadius: 18)],
                  ),
                ).animate(key: ValueKey(_countdown)).scale(begin: const Offset(1.4, 1.4), end: const Offset(1, 1), duration: 300.ms).fadeIn(),
              ),
            ),

          // 5. Host Shorts Wireless Multi-Cam Secondary Angle (PiP or Split Screen)
          if (isHostShortsActive) _buildHostShortsOverlay(hostSession),

          // 6. Main Foreground UI
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Navigation & Studio Telemetry Header
                _buildTopStudioHeader(),
                if (_dualOn) _buildDualControls(),

                // Smart Lock Status HUD
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: CameraSmartLockHud(
                    smartLock: cameraLooksState.smartLockState,
                    onUnlockTap: _unlockFocus,
                  ),
                ),

                // Center Pro Telemetry Deck (when toggled)
                if (_showProTelemetryDeck)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: CameraProControlsDeck(
                      state: cameraLooksState.smartLockState,
                      cameraController: _cameraController,
                      onEvChanged: (ev) {
                        final v = ev.clamp(_evMin, _evMax).toDouble();
                        ref.read(cameraLooksControllerProvider.notifier).setExposureBias(v);
                        _setEv(v);
                      },
                      onIsoChanged: (iso) {
                        ref.read(cameraLooksControllerProvider.notifier).setIso(iso);
                        _applyManual();
                      },
                      onShutterChanged: (shutter) {
                        ref.read(cameraLooksControllerProvider.notifier).setShutterSpeed(shutter);
                        _applyManual();
                      },
                      onWbChanged: (mode, {kelvin}) {
                        ref.read(cameraLooksControllerProvider.notifier).setWhiteBalance(mode, kelvin: kelvin);
                        _applyManual();
                      },
                      onFocusChanged: (dist) async {
                        await ref.read(cameraLooksControllerProvider.notifier).setManualFocus(dist, _cameraController);
                        _applyManual();
                      },
                      onClose: () => setState(() => _showProTelemetryDeck = false),
                    ),
                  ),

                const Spacer(),

                // Bottom: filters / enhance panel, or the creator console
                if (_showFilters)
                  _buildFiltersPanel()
                else if (_showEnhance)
                  _buildEnhancePanel()
                else
                  _buildBottomCreatorConsole(),
              ],
            ),
          ),

          // 7. Right Creative Quick Tools Toolbar (hidden under the look panels or while recording)
          if (!_showFilters && !_showEnhance && !_isRecording)
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
  // 1. Camera Viewfinder (live AR effects over the preview)
  // ────────────────────────────────────────────────────────────────────────
  Widget _buildCameraViewfinder() {
    final nativeInfo = _nativeInfo;
    if (_isInitialized && _nativeCam != null && nativeInfo != null) {
      // Native AR camera: already upright and mirrored at full resolution.
      Widget preview = Texture(textureId: nativeInfo.textureId);
      preview = ArViewfinder(preview: preview);
      return SizedBox.expand(
        child: _graded(FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: nativeInfo.width.toDouble(),
            height: nativeInfo.height.toDouble(),
            child: preview,
          ),
        )),
      );
    }

    if (_isInitialized && _cameraController != null && _cameraController!.value.isInitialized) {
      Widget preview = CameraPreview(_cameraController!);
      preview = ArViewfinder(preview: preview);

      return SizedBox.expand(
        child: _graded(FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: _cameraController!.value.previewSize?.height ?? 1080,
            height: _cameraController!.value.previewSize?.width ?? 1920,
            child: preview,
          ),
        )),
      );
    }

    // Camera not ready yet (starting, or permission still pending).
    return Container(
      color: obsidianDark,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_rounded, color: Colors.white38, size: 36),
          const SizedBox(height: 12),
          Text(
            'Starting camera…',
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
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

  Widget _buildCinematicVignette() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.35),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.45),
            ],
            stops: const [0.0, 0.12, 0.8, 1.0],
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
          // Recording time (only while recording; Flip lives in the toolbar).
          if (_isRecording)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: brandPink, borderRadius: BorderRadius.circular(16)),
                child: Text(
                  'REC ${(_recordingSecondsElapsed ~/ 60).toString().padLeft(2, '0')}:${(_recordingSecondsElapsed % 60).toString().padLeft(2, '0')}'
                  '${_limitSeconds != null ? ' / ${_limitSeconds! >= 60 ? '${_limitSeconds! ~/ 60}m' : '${_limitSeconds}s'}' : ''}',
                  style: GoogleFonts.firaCode(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1),
                ),
              ),
            ),


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
                  // Real capture format (tap for details)
                  GestureDetector(
                    onTap: _showFormatInfo,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: glassSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: brandCyan.withValues(alpha: 0.4)),
                        boxShadow: [BoxShadow(color: brandCyan.withValues(alpha: 0.2), blurRadius: 10)],
                      ),
                      child: Text(
                        _formatLabel,
                        style: GoogleFonts.firaCode(color: brandCyan, fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Flash Toggle
                  _buildGlassIconButton(
                    icon: switch (_flashMode) {
                      FlashMode.off => Icons.flash_off_rounded,
                      FlashMode.auto => Icons.flash_auto_rounded,
                      FlashMode.always => Icons.flash_on_rounded,
                      FlashMode.torch => _isFront ? Icons.light_mode_rounded : Icons.highlight_rounded,
                    },
                    iconColor: _flashMode != FlashMode.off ? const Color(0xFFFACC15) : Colors.white,
                    onTap: _toggleFlash,
                  ),
                ],
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
  // Focus / exposure overlay, dual camera, filters and enhance panels
  // ────────────────────────────────────────────────────────────────────────
  List<Widget> _buildFocusOverlay() {
    final tap = _focusTap;
    final out = <Widget>[];
    // The lock itself is shown by the Smart Lock HUD (its ✕ unlocks).
    if (tap == null || !_showFocusUi) return out;
    final color = _focusLocked ? AppColors.brandPink : const Color(0xFFFACC15);
    out.add(Positioned(
      left: tap.dx - 36,
      top: tap.dy - 36,
      child: IgnorePointer(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(border: Border.all(color: color, width: 1.5), borderRadius: BorderRadius.circular(6)),
        ).animate(key: ValueKey('${tap.dx}_${tap.dy}_$_focusLocked')).scale(
              begin: const Offset(1.35, 1.35),
              end: const Offset(1, 1),
              duration: 220.ms,
            ),
      ),
    ));
    // Exposure: drag the sun up or down.
    final screenW = MediaQuery.of(context).size.width;
    final left = tap.dx + 44 > screenW - 40 ? tap.dx - 80 : tap.dx + 44;
    out.add(Positioned(
      left: left,
      top: tap.dy - 80,
      width: 36,
      height: 160,
      child: Column(
        children: [
          Icon(Icons.wb_sunny_rounded, size: 16, color: color),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 1.5,
                  activeTrackColor: color,
                  inactiveTrackColor: Colors.white38,
                  thumbColor: color,
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: Slider(
                  value: _ev.clamp(_evMin, _evMax).toDouble(),
                  min: _evMin,
                  max: _evMax,
                  onChanged: _setEv,
                ),
              ),
            ),
          ),
          Text('${_ev >= 0 ? '+' : ''}${_ev.toStringAsFixed(1)}',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, shadows: const [Shadow(blurRadius: 4)])),
        ],
      ),
    ));
    return out;
  }

  /// Drag area over the second camera's window (drawn natively).
  Widget _buildDualPipHandle() {
    final r = _lastPreviewRect;
    final dw = r.width, dh = r.height;
    final ox = r.left, oy = r.top;
    final l = _dualLayout;
    return Positioned(
      left: ox + l.x * dw,
      top: oy + l.y * dh,
      width: l.w * dw,
      height: l.h * dh,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => _updateDualLayout(l.copyWith(swap: !l.swap)),
        onPanUpdate: (d) => _updateDualLayout(_dualLayout.copyWith(
          x: (_dualLayout.x + d.delta.dx / dw).clamp(0.0, 1 - _dualLayout.w).toDouble(),
          y: (_dualLayout.y + d.delta.dy / dh).clamp(0.0, 1 - _dualLayout.h).toDouble(),
        )),
      ),
    );
  }

  Widget _buildDualControls() {
    Widget chip(String label, IconData icon, bool on, VoidCallback onTap) => GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: on ? brandBlue : glassSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 13, color: Colors.white),
              const SizedBox(width: 4),
              Text(label, style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
        );
    final l = _dualLayout;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          chip('PiP', Icons.picture_in_picture_alt_rounded, l.layout == 'pip', () => _updateDualLayout(l.copyWith(layout: 'pip'))),
          chip('Split', Icons.view_agenda_rounded, l.layout == 'split', () => _updateDualLayout(l.copyWith(layout: 'split'))),
          chip('Swap', Icons.swap_vert_rounded, l.swap, () => _updateDualLayout(l.copyWith(swap: !l.swap))),
        ],
      ),
    );
  }

  Widget _panelShell({required String title, required Widget child, Widget? action}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
                child: Row(
                  children: [
                    Text(title, style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    ?action,
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                      onPressed: () => setState(() {
                        _showFilters = false;
                        _showEnhance = false;
                        _heldFilterId = null;
                        _heldPreset = null;
                      }),
                    ),
                  ],
                ),
              ),
              child,
            ],
          ),
        ),
        _buildShutterAndLensDeck(),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildFiltersPanel() {
    final name = _filterId == 'none' ? null : filterItemFor(_filterId).name;
    Widget tab(String label, bool on) => GestureDetector(
          onTap: () => setState(() => _presetsTab = label == 'Presets'),
          child: Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: on ? brandBlue : Colors.white12, borderRadius: BorderRadius.circular(12)),
            child: Text(label, style: GoogleFonts.inter(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
        );
    return _panelShell(
      title: name ?? 'Look',
      action: Row(mainAxisSize: MainAxisSize.min, children: [tab('Filters', !_presetsTab), tab('Presets', _presetsTab)]),
      child: _presetsTab
          ? OneovaPresetStrip(
              overCamera: true,
              selectedId: _presetId,
              onApply: _applyPreset,
              onPreview: (p) => setState(() => _heldPreset = p),
              onSaveCurrent: (n) => OneovaPresets.instance.save(
                name: n,
                filterId: _filterId,
                intensity: _filterIntensity,
                adjust: _camAdjust,
                beauty: _beauty,
              ),
            )
          : OneovaFilterBrowser(
        overCamera: true,
        selectedId: _filterId,
        intensity: _filterIntensity,
        onPick: (id) {
          setState(() {
            _filterId = id;
            _heldFilterId = null;
            _presetId = null;
            if (id != 'none') _filterIntensity = 1.0;
          });
          _saveSetting('camera_filter_id', id);
          _saveSetting('camera_filter_intensity', _filterIntensity);
        },
        onPreview: (id) => setState(() => _heldFilterId = id),
        onIntensity: (v) => setState(() => _filterIntensity = v),
        onIntensityEnd: (v) => _saveSetting('camera_filter_intensity', v),
      ),
    );
  }

  Widget _buildEnhancePanel() {
    Widget row(String label, double value, double min, double max, ValueChanged<double> onChanged) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              SizedBox(
                width: 78,
                child: Text(label, style: GoogleFonts.inter(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.5,
                    activeTrackColor: brandBlue,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  ),
                  child: Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, onChanged: onChanged),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text('${(value * 100).round()}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
    final touched = _brightness != 0 || _contrast != 0 || _beauty != 0 || ref.watch(liveArControllerProvider).outfitOn;
    return _panelShell(
      title: 'Enhance',
      action: touched
          ? TextButton(
              onPressed: () {
                setState(() {
                  _brightness = 0;
                  _contrast = 0;
                  _presetAdjust = const StudioAdjust();
                  _presetId = null;
                });
                _setBeauty(0);
                ref.read(liveArControllerProvider.notifier).setOutfit(null);
              },
              child: Text('Reset', style: GoogleFonts.inter(color: brandPink, fontWeight: FontWeight.w700)),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row('Brightness', _brightness, -1, 1, (v) => setState(() => _brightness = v)),
          row('Contrast', _contrast, -1, 1, (v) => setState(() => _contrast = v)),
          row('Beauty', _beauty, 0, 1, _setBeauty),
          _buildOutfitRow(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: Text(
              'Beauty smooths skin only and is saved into photos and videos. Brightness and contrast go to the editor, where you can still change them.',
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }

  /// Fabric colours for Outfit (content choices, not brand colours).
  static const _outfitColors = <Color>[
    Color(0xFF16161A), Color(0xFFF2F2F2), Color(0xFFD7263D), AppColors.brandPink, AppColors.brandBlue,
    Color(0xFF0FA3B1), Color(0xFF2E8B57), Color(0xFFF4C430), Color(0xFF7B2CBF), Color(0xFFF77F00), Color(0xFF8B5A2B),
  ];

  /// Outfit colour: clothes recoloured live (person + body + face tracking,
  /// skin kept) and baked into photos and videos.
  Widget _buildOutfitRow() {
    final ar = ref.watch(liveArControllerProvider);
    final current = ar.outfitColor;
    final ctrl = ref.read(liveArControllerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Outfit colour', style: GoogleFonts.inter(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                GestureDetector(
                  onTap: () => ctrl.setOutfit(null),
                  child: Container(
                    width: 30,
                    height: 30,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: current == null ? brandBlue : Colors.white38, width: 2),
                    ),
                    child: const Icon(Icons.block_rounded, size: 16, color: Colors.white70),
                  ),
                ),
                for (final c in _outfitColors)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ctrl.setOutfit(c);
                    },
                    child: Container(
                      width: 30,
                      height: 30,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: current == c ? Colors.white : Colors.white24, width: current == c ? 2.5 : 1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (current != null)
            Row(children: [
              Text('Strength', style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
              Expanded(
                child: Slider(
                  value: ar.outfitStrength,
                  activeColor: brandBlue,
                  inactiveColor: Colors.white24,
                  onChanged: (v) => ctrl.setOutfit(current, strength: v),
                ),
              ),
            ]),
          if (current != null)
            Text('Recolours clothes below the neck and keeps skin natural. Saved into photos and videos.',
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 10.5)),
        ],
      ),
    );
  }

  String get _formatLabel {
    final pv = _previewPixelSize;
    if (pv == null) return '—';
    if (_activeDurationMode == 'PHOTO') return '4:3';
    if (_nativeCam != null) return switch (_videoQuality) { '1080p60' => '1080p 60', '4k30' => '4K 30', _ => '1080p 30' };
    final short = math.min(pv.width, pv.height).round();
    final p = short >= 2100 ? '4K' : short >= 1400 ? '1440p' : short >= 1000 ? '1080p' : short >= 700 ? '720p' : '${short}p';
    return _nativeCam != null ? '$p 30' : p;
  }

  Future<void> _showFormatInfo() async {
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.of(context);
    var text = 'Preview ${_previewPixelSize?.width.round() ?? 0}×${_previewPixelSize?.height.round() ?? 0}';
    final n = _nativeCam;
    if (n != null) {
      try {
        final st = await n.stats();
        final fps = (st['previewFps'] as num?)?.toDouble() ?? 0;
        text = 'Recording ${st['previewWidth']}×${st['previewHeight']} at ${fps.round()} fps'
            '${st['dual'] == true ? ' · dual camera' : ''}${st['stillCapture'] == true ? ' · full-res photos' : ''}';
      } catch (_) {}
    }
    messenger.showSnackBar(SnackBar(content: Text(text, style: GoogleFonts.inter()), duration: const Duration(seconds: 2)));
  }

  // ────────────────────────────────────────────────────────────────────────
  // 4. Right Creative Quick Tools Toolbar
  // ────────────────────────────────────────────────────────────────────────
  bool get _hasMakeup => ref.watch(liveArControllerProvider.select((s) => s.active.containsKey('makeup')));

  /// A still from whichever camera is open (for AI "Match my face").
  Future<String?> _captureStill() async {
    try {
      final nativeCam = _nativeCam;
      if (nativeCam != null) return await nativeCam.takePicture();
      final c = _cameraController;
      if (c != null && c.value.isInitialized && !c.value.isTakingPicture) return (await c.takePicture()).path;
    } catch (e) {
      debugPrint('Still capture failed: $e');
    }
    return null;
  }

  void _openEffects() => showArEffectsSheet(context, captureStill: _captureStill);

  void _openMakeupStudio() => showArMakeupStudio(context, captureStill: _captureStill);

  Future<void> _toggleVoiceShutter() async {
    HapticFeedback.selectionClick();
    final next = !_voiceShutterOn;
    setState(() => _voiceShutterOn = next);
    if (!next) {
      await SpeechHub.instance.cancel(this);
      return;
    }
    final ok = await SpeechHub.instance.listen(
      owner: this,
      onResult: (res) {
        if (!mounted || !_voiceShutterOn || !res.finalResult) return;
        final intent = _voiceParser.parse(res.recognizedWords);
        switch (intent) {
          case CapturePhotoIntent():
            _takePhoto();
          case StartRecordingIntent():
            if (!_isRecording) _startVideoRecording();
          case StopRecordingIntent():
            if (_isRecording) _stopVideoRecording();
          case SwitchCameraIntent():
            _toggleFlipCamera();
          default:
            break;
        }
      },
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') && mounted && _voiceShutterOn && !_isRecording) {
          Future.delayed(const Duration(milliseconds: 350), () {
            if (mounted && _voiceShutterOn && !_isRecording) _restartVoiceListen();
          });
        }
      },
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _voiceShutterOn = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice control is unavailable on this device.')),
      );
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 2),
            content: Text('Voice control on: say "Cheese", "Take photo", "Start recording" or "Flip camera".'),
          ),
        );
    }
  }

  Future<void> _restartVoiceListen() async {
    if (!_voiceShutterOn || _isRecording || !mounted) return;
    await SpeechHub.instance.listen(
      owner: this,
      onResult: (res) {
        if (!mounted || !_voiceShutterOn || !res.finalResult) return;
        final intent = _voiceParser.parse(res.recognizedWords);
        switch (intent) {
          case CapturePhotoIntent():
            _takePhoto();
          case StartRecordingIntent():
            if (!_isRecording) _startVideoRecording();
          case StopRecordingIntent():
            if (_isRecording) _stopVideoRecording();
          case SwitchCameraIntent():
            _toggleFlipCamera();
          default:
            break;
        }
      },
    );
  }

  Widget _buildRightCreativeToolbar() {
    final autoTrackOn = ref.watch(liveArControllerProvider.select((s) => s.autoTrack));
    final hasEffects = ref.watch(liveArControllerProvider.select((s) => s.active.isNotEmpty));
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
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
            // 1. Flip Camera (swaps the cameras in dual mode)
            _buildToolbarButton(icon: Icons.flip_camera_ios_rounded, onTap: _toggleFlipCamera, tooltip: 'Flip Camera', caption: 'Flip'),
            const SizedBox(height: 4),

            // 2. AR Face / Body & VFX Effects
            _buildToolbarButton(
              icon: Icons.face_retouching_natural,
              color: hasEffects ? brandPink : Colors.white,
              hasCheckBadge: hasEffects,
              onTap: _openEffects,
              tooltip: 'Effects & VFX', caption: 'Effects',
            ),
            const SizedBox(height: 4),

            // 3. Filters (Oneova colour grades)
            _buildToolbarButton(
              icon: Icons.filter_vintage_rounded,
              color: _filterId != 'none' || _showFilters ? brandPink : Colors.white,
              hasCheckBadge: _filterId != 'none',
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _showFilters = !_showFilters;
                  _showEnhance = false;
                });
              },
              tooltip: 'Filters', caption: 'Filters',
            ),
            const SizedBox(height: 4),

            // 4. Enhance: brightness, contrast, skin beauty & outfit
            _buildToolbarButton(
              icon: Icons.auto_fix_high_rounded,
              color: _brightness != 0 || _contrast != 0 || _beauty != 0 || _showEnhance ? brandPink : Colors.white,
              hasBadge: _brightness != 0 || _contrast != 0 || _beauty != 0,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _showEnhance = !_showEnhance;
                  _showFilters = false;
                });
              },
              tooltip: 'Enhance & Beauty', caption: 'Enhance',
            ),
            const SizedBox(height: 4),

            // 5. Smart Auto-Tracker (human face & body subject framing)
            _buildToolbarButton(
              icon: autoTrackOn ? Icons.person_pin_circle_rounded : Icons.center_focus_weak_rounded,
              color: autoTrackOn ? brandBlue : Colors.white,
              hasBadge: autoTrackOn,
              onTap: () {
                HapticFeedback.selectionClick();
                final next = !autoTrackOn;
                ref.read(liveArControllerProvider.notifier).setAutoTrack(next);
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                    duration: const Duration(milliseconds: 1400),
                    content: Text(next ? 'Auto-Track on: camera follows your face & body' : 'Auto-Track off'),
                  ));
              },
              tooltip: 'Auto-Track Subject', caption: 'Track',
            ),
            const SizedBox(height: 4),

            // Expanded secondary tools (keeps default view clean & distraction-free)
            if (_toolbarExpanded) ...[
              // 6. Makeup Studio
              _buildToolbarButton(
                icon: Icons.brush_rounded,
                color: _hasMakeup ? brandPink : Colors.white,
                hasBadge: _hasMakeup,
                onTap: _openMakeupStudio,
                tooltip: 'Makeup Studio', caption: 'Makeup',
              ),
              const SizedBox(height: 4),

              // 7. Timer
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
                tooltip: 'Timer', caption: 'Timer',
              ),
              const SizedBox(height: 4),

              // 8. Hands-Free Voice Control
              _buildToolbarButton(
                icon: _voiceShutterOn ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: _voiceShutterOn ? brandPink : Colors.white,
                hasBadge: _voiceShutterOn,
                onTap: _toggleVoiceShutter,
                tooltip: 'Voice Control', caption: 'Voice',
              ),
              const SizedBox(height: 4),

              // 9. Camera Controls (Brightness, Light, Speed, Tone, Focus)
              _buildToolbarButton(
                icon: Icons.tune_rounded,
                color: _showProTelemetryDeck ? brandBlue : Colors.white,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _showProTelemetryDeck = !_showProTelemetryDeck);
                },
                tooltip: 'Camera Controls', caption: 'Adjust',
              ),
              const SizedBox(height: 4),

              // 10. All Camera Settings Sheet
              _buildToolbarButton(
                icon: Icons.settings_outlined,
                color: Colors.white,
                onTap: () {
                  HapticFeedback.selectionClick();
                  _showMoreSettingsMenu();
                },
                tooltip: 'Camera Options', caption: 'Options',
              ),
              const SizedBox(height: 4),
            ],

            // Expand / Collapse Toggle
            _buildToolbarButton(
              icon: _toolbarExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              color: Colors.white70,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _toolbarExpanded = !_toolbarExpanded);
              },
              tooltip: _toolbarExpanded ? 'Show fewer tools' : 'Show more tools',
              caption: _toolbarExpanded ? 'Less' : 'More',
            ),
          ],
        ),
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
    String? caption,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Column(mainAxisSize: MainAxisSize.min, children: [Container(
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
          if (caption != null)
            Text(caption,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  shadows: const [Shadow(color: Colors.black87, blurRadius: 4)],
                )),
        ]),
      ),
    );
  }



  // ────────────────────────────────────────────────────────────────────────
  // 5. Bottom Creator Console & Capture Deck
  // ────────────────────────────────────────────────────────────────────────
  /// 0.5x (ultra-wide, where the phone has one) · 1x · 2x · 5x, and a
  /// slider while zooming. Default 1x: the camera exactly as it sees.
  Widget _buildZoomRow() {
    final stops = <double>[
      if (_minZoom < 0.95) _minZoom,
      1,
      if (_maxZoom >= 2) 2,
      if (_maxZoom >= 5) 5,
    ];
    String label(double z) => z < 1 ? '${(z * 10).round() / 10}'.replaceAll('.0', '') : '${z.round()}';
    final nearest = stops.reduce((a, b) => (a - _zoom).abs() < (b - _zoom).abs() ? a : b);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showZoomSlider)
          SizedBox(
            width: 260,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white30,
                thumbColor: Colors.white,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              // Log scale so 1x–2x gets as much travel as 5x–10x.
              child: Slider(
                value: math.log(_zoom.clamp(_minZoom, _maxZoom)),
                min: math.log(_minZoom),
                max: math.log(_maxZoom),
                onChanged: (v) => _setZoom(math.exp(v)),
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(20)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final z in stops)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _setZoom(z.toDouble());
                  },
                  child: Container(
                    width: 38,
                    height: 30,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: z == nearest ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      z == nearest && (_zoom - z).abs() > 0.05 ? '${_zoom.toStringAsFixed(1)}×' : '${label(z.toDouble())}×',
                      style: GoogleFonts.inter(
                        color: z == nearest ? const Color(0xFFFACC15) : Colors.white,
                        fontSize: z == nearest ? 11.5 : 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomCreatorConsole() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildZoomRow(),
        const SizedBox(height: 8),
        _buildCaptureModeRow(),
        const SizedBox(height: 6),
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
                if (_isRecording) return;
                setState(() => _activeDurationMode = mode);
                _matchCameraFormat();
                if (mode == 'DUAL CAM') {
                  _setDual(true);
                } else if (_dualOn) {
                  _setDual(false);
                }
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
            onLongPress: _activeDurationMode == 'PHOTO' ? null : _startVideoRecording,
            onLongPressUp: _activeDurationMode == 'PHOTO' ? null : _stopVideoRecording,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_isRecording && _limitSeconds != null)
                  SizedBox(
                    width: 92,
                    height: 92,
                    child: CircularProgressIndicator(
                      value: (_recordingSecondsElapsed / _limitSeconds!).clamp(0.0, 1.0),
                      strokeWidth: 4,
                      color: brandPink,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                Container(
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
              ],
            ),
          ),

          // Right Side: Quick Filters & Beauty Retouch
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Filters
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _showFilters = !_showFilters;
                    _showEnhance = false;
                  });
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: (_filterId != 'none' ? brandPink : brandBlue).withValues(alpha: 0.8), width: 1.5),
                    color: glassSurface,
                    boxShadow: [
                      BoxShadow(color: brandBlue.withValues(alpha: 0.25), blurRadius: 8),
                    ],
                  ),
                  child: Center(
                    child: Icon(Icons.filter_vintage_rounded, size: 20, color: _filterId != 'none' ? brandPink : Colors.white),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Makeup Studio (AI)
              GestureDetector(
                onTap: _openMakeupStudio,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: glassSurface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _hasMakeup ? brandPink : Colors.white24,
                      width: 1.5,
                    ),
                    boxShadow: [
                      if (_hasMakeup)
                        BoxShadow(color: brandPink.withValues(alpha: 0.3), blurRadius: 10),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: _hasMakeup ? brandPink : Colors.white,
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

  /// Go Live with the camera's look: the filter + adjustments carry into
  /// the live stream (Live Looks processor), and the camera is released so
  /// Live can open it (holding it made the live camera fail).
  Future<void> _goLive() async {
    if (_isRecording) return;
    final look = StudioLooks.forLook(_filterId, _filterIntensity, _camAdjust);
    try {
      await ref.read(liveLooksControllerProvider.notifier).applyLook(look ?? const OneovaLook(name: 'Neutral Live'));
    } catch (e) {
      debugPrint('[Camera] live look not applied: $e');
    }
    await _awayFromCamera(() => context.push('/live/setup'));
  }

  /// Frees the camera (and its tracking / GL work) while another screen is
  /// on top, then reopens it: running it hidden drained memory and heat.
  Future<T?> _awayFromCamera<T>(Future<T?> Function() open) async {
    if (mounted) setState(() => _isInitialized = false);
    await _releaseCamera();
    try {
      return await open();
    } finally {
      if (mounted && !_camB && _cameraController == null && _nativeCam == null) unawaited(_initCamera());
    }
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
                    _goLive();
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: brandPink.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: brandPink.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.library_music_rounded, color: brandPink),
            ),
            title: Text('My music', style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text('Songs saved on this phone', style: GoogleFonts.inter(color: context.textMuted, fontSize: 12)),
            onTap: () async {
              final song = await showPhoneMusicSheet(context);
              if (song == null) return;
              setState(() {
                _selectedSoundTitle = song.title;
                _soundSource = song.path;
                _soundDurationMs = song.durationMs;
              });
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: brandBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: brandBlue.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.folder_open_rounded, color: brandBlue),
            ),
            title: Text('From my files', style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text('Any song or audio on this phone', style: GoogleFonts.inter(color: context.textMuted, fontSize: 12)),
            onTap: () async {
              final file = await FilePicker.pickFile(type: FileType.audio);
              final path = file?.path;
              if (path == null) return;
              setState(() {
                _selectedSoundTitle = file!.name.replaceAll(RegExp(r'\.[^.]+$'), '');
                _soundSource = path;
                _soundDurationMs = 0;
              });
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
          if (_soundSource != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.music_off_rounded, color: context.textSecondary),
              title: Text('No sound', style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
              onTap: () {
                setState(() {
                  _selectedSoundTitle = null;
                  _soundSource = null;
                });
                Navigator.pop(ctx);
              },
            ),
          const SizedBox(height: 8),
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
                        setState(() {
                          _selectedSoundTitle = sound.title;
                          _soundSource = sound.contentUrl.isEmpty ? null : sound.contentUrl;
                          _soundDurationMs = sound.durationMs;
                        });
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
    final latency = session?.remoteDevice?.latencyMs ?? 0;
    final layout = session?.layout ?? HostShortsLayout.pip;
    if (layout == HostShortsLayout.soloCamA && isStreaming) return const SizedBox.shrink();
    if (isStreaming && layout != HostShortsLayout.pip) {
      // Cam B solo: full frame; splits: top half (left half side by side).
      final size = MediaQuery.of(context).size;
      final full = layout == HostShortsLayout.soloCamB;
      final side = layout == HostShortsLayout.splitHorizontal;
      return Positioned(
        left: 0,
        top: 0,
        width: full || !side ? size.width : size.width / 2,
        height: full || side ? size.height : size.height / 2,
        child: IgnorePointer(
          child: RTCVideoView(
            ref.read(hostShortsServiceProvider.notifier).remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
      );
    }

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
                        Text(session?.pairCode != null ? 'Code ${session!.pairCode}' : 'Waiting for Cam B',
                            style: GoogleFonts.inter(color: brandBlue, fontSize: 9, fontWeight: FontWeight.w700)),
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
                      child: Text(latency > 0 ? '${latency}ms' : '—', style: GoogleFonts.firaCode(fontSize: 8, fontWeight: FontWeight.w700, color: const Color(0xFF34D399))),
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
                    ref.read(hostShortsServiceProvider.notifier).switchLayout(HostShortsLayout.soloCamB);
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
                              Text('Use a second phone as another camera angle', style: GoogleFonts.inter(color: context.textMuted, fontSize: 11)),
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
                                    ? 'Cam B connected · ${session.remoteDevice?.resolution ?? ''} ${session.remoteDevice?.fps ?? 0} fps · ${session.remoteDevice?.latencyMs ?? 0} ms'
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
                                final share = ref.read(hostShortsServiceProvider.notifier);
                                final code = await share.startHostingSession();
                                if (code == null && ctx.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(share.lastError ?? 'Could not start.')));
                                }
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
                                final code = _pairCodeController.text.trim();
                                if (code.isNotEmpty) {
                                  HapticFeedback.selectionClick();
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  await _joinAsCamB(code);
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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget toggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(title, style: GoogleFonts.inter(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text(subtitle, style: GoogleFonts.inter(color: context.textMuted, fontSize: 12)),
                value: value,
                activeThumbColor: brandBlue,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  onChanged(v);
                  setSheet(() {});
                },
              );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Camera settings', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  toggle('Record sound', 'Use the microphone in videos', _recordAudio, (v) {
                    setState(() => _recordAudio = v);
                    _saveSetting('camera_record_audio', v);
                    // The Flutter camera sets audio when it opens.
                    if (_nativeCam == null && !_isRecording) _reinitCamera();
                  }),
                  toggle('Stabilize videos', 'Smooth shaky takes in the editor (crops slightly)', _autoStabilize, (v) {
                    setState(() => _autoStabilize = v);
                    _saveSetting('camera_auto_stabilize', v);
                  }),
                  toggle('Clean voice', 'Cut background noise from speech in the editor', _cleanVoice, (v) {
                    setState(() => _cleanVoice = v);
                    _saveSetting('camera_clean_voice', v);
                  }),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('Video quality',
                              style: GoogleFonts.inter(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                        for (final q in const [('1080p30', '1080p'), ('1080p60', '60 fps'), ('4k30', '4K')])
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: ChoiceChip(
                              label: Text(q.$2),
                              selected: _videoQuality == q.$1,
                              selectedColor: brandBlue,
                              labelStyle: GoogleFonts.inter(
                                color: _videoQuality == q.$1 ? Colors.white : context.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              onSelected: (_) {
                                setState(() => _videoQuality = q.$1);
                                setSheet(() {});
                                _saveSetting('camera_video_quality', q.$1);
                                _matchCameraFormat();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  toggle('Low-light boost', 'Brighter picture in the dark (smoother at 30 fps when off)', _lowLight, (v) {
                    setState(() => _lowLight = v);
                    _saveSetting('camera_low_light', v);
                    unawaited(_nativeCam?.setLowLight(v).catchError((_) {}));
                  }),
                  toggle('Grid', 'Rule-of-thirds guides', _showGrid, (v) {
                    setState(() => _showGrid = v);
                    _saveSetting('camera_grid', v);
                  }),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.wallpaper_rounded, color: brandBlue),
                    title: Text('Green screen & background', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text('Blur, replace or remove what is behind you', style: GoogleFonts.inter(color: context.textMuted, fontSize: 12)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openEffects();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
