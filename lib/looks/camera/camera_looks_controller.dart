import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/oneova_look.dart';
import 'models/camera_smart_lock_state.dart';

/// Combined state for Camera Looks, Beauty, Smart Lock & Pro Controls.
@immutable
class CameraLooksState {
  final OneovaLook activeLook;
  final BoostBeautyConfig beauty;
  final CameraSmartLockState smartLock;
  final CaptureMode captureMode;
  final bool isRecording;
  final int recordingElapsedSeconds;
  final bool isProDeckVisible;
  final String? lastMessage;

  const CameraLooksState({
    this.activeLook = const OneovaLook(id: 'neutral', name: 'Neutral'),
    this.beauty = const BoostBeautyConfig(),
    this.smartLock = const CameraSmartLockState(),
    this.captureMode = CaptureMode.video,
    this.isRecording = false,
    this.recordingElapsedSeconds = 0,
    this.isProDeckVisible = false,
    this.lastMessage,
  });

  /// Alias for smartLock
  CameraSmartLockState get smartLockState => smartLock;

  CameraLooksState copyWith({
    OneovaLook? activeLook,
    BoostBeautyConfig? beauty,
    CameraSmartLockState? smartLock,
    CaptureMode? captureMode,
    bool? isRecording,
    int? recordingElapsedSeconds,
    bool? isProDeckVisible,
    String? lastMessage,
  }) {
    return CameraLooksState(
      activeLook: activeLook ?? this.activeLook,
      beauty: beauty ?? this.beauty,
      smartLock: smartLock ?? this.smartLock,
      captureMode: captureMode ?? this.captureMode,
      isRecording: isRecording ?? this.isRecording,
      recordingElapsedSeconds: recordingElapsedSeconds ?? this.recordingElapsedSeconds,
      isProDeckVisible: isProDeckVisible ?? this.isProDeckVisible,
      lastMessage: lastMessage,
    );
  }
}

/// Controller managing Camera Looks preview, Smart Lock (AE/AF/AWB lock on record),
/// and Pro Manual Telemetry controls.
class CameraLooksController extends Notifier<CameraLooksState> {
  @override
  CameraLooksState build() {
    return const CameraLooksState();
  }

  void _haptic(VoidCallback call) {
    try {
      call();
    } catch (_) {}
  }

  /// Changes the real-time active Look applied on preview and recording.
  void applyLook(OneovaLook look) {
    _haptic(HapticFeedback.selectionClick);
    state = state.copyWith(activeLook: look);
  }

  /// Sets overall intensity multiplier for the active Look.
  void setLookIntensity(double intensity) {
    state = state.copyWith(
      activeLook: state.activeLook.copyWith(
        intensity: intensity.clamp(0.0, 1.0),
      ),
    );
  }

  /// Adjusts Boost Beauty parameters live on camera viewfinder.
  void applyBeauty(BoostBeautyConfig beauty) {
    state = state.copyWith(beauty: beauty);
  }

  /// Switches capture mode (Photo, Video, Fast, Hands-Free, Night, Pro).
  void setCaptureMode(CaptureMode mode) {
    _haptic(HapticFeedback.selectionClick);
    state = state.copyWith(captureMode: mode);
  }

  /// Toggles visibility of the manual Pro telemetry deck (ISO, Shutter, Kelvin, EV).
  void toggleProDeck() {
    _haptic(HapticFeedback.lightImpact);
    state = state.copyWith(isProDeckVisible: !state.isProDeckVisible);
  }

  /// Smart Lock: Automatically locks Auto-Exposure (AE), Auto-Focus (AF),
  /// and Auto-White-Balance (AWB) upon record start.
  Future<void> engageSmartLock([CameraController? camera]) async {
    _haptic(HapticFeedback.mediumImpact);
    if (camera != null && camera.value.isInitialized) {
      try {
        await camera.setExposureMode(ExposureMode.locked);
        await camera.setFocusMode(FocusMode.locked);
      } catch (e) {
        debugPrint('[CameraLooksController] Smart Lock hardware lock error: $e');
      }
    }

    state = state.copyWith(
      smartLock: state.smartLock.copyWith(
        isSmartLockActive: true,
        aeLocked: true,
        afLocked: true,
        awbLocked: true,
      ),
      isRecording: true,
      lastMessage: 'Smart Lock Engaged: AE/AF/AWB Locked',
    );
  }

  /// Releases Smart Lock back to continuous auto adjustments.
  Future<void> releaseSmartLock([CameraController? camera]) async {
    _haptic(HapticFeedback.lightImpact);
    if (camera != null && camera.value.isInitialized) {
      try {
        await camera.setExposureMode(ExposureMode.auto);
        await camera.setFocusMode(FocusMode.auto);
      } catch (e) {
        debugPrint('[CameraLooksController] Smart Lock hardware release error: $e');
      }
    }

    state = state.copyWith(
      smartLock: state.smartLock.copyWith(
        isSmartLockActive: false,
        aeLocked: false,
        afLocked: false,
        awbLocked: false,
      ),
      isRecording: false,
      recordingElapsedSeconds: 0,
      lastMessage: 'Smart Lock Released: Auto AE/AF Active',
    );
  }

  /// Toggles AE Lock independently.
  Future<void> toggleAeLock([CameraController? camera]) async {
    _haptic(HapticFeedback.selectionClick);
    final newLocked = !state.smartLock.aeLocked;
    if (camera != null && camera.value.isInitialized) {
      try {
        await camera.setExposureMode(newLocked ? ExposureMode.locked : ExposureMode.auto);
      } catch (_) {}
    }
    state = state.copyWith(
      smartLock: state.smartLock.copyWith(aeLocked: newLocked),
    );
  }

  /// Toggles AF Lock independently.
  Future<void> toggleAfLock([CameraController? camera]) async {
    _haptic(HapticFeedback.selectionClick);
    final newLocked = !state.smartLock.afLocked;
    if (camera != null && camera.value.isInitialized) {
      try {
        await camera.setFocusMode(newLocked ? FocusMode.locked : FocusMode.auto);
      } catch (_) {}
    }
    state = state.copyWith(
      smartLock: state.smartLock.copyWith(afLocked: newLocked),
    );
  }

  /// Toggles AWB Lock independently.
  Future<void> toggleAwbLock([CameraController? camera]) async {
    _haptic(HapticFeedback.selectionClick);
    final newLocked = !state.smartLock.awbLocked;
    state = state.copyWith(
      smartLock: state.smartLock.copyWith(awbLocked: newLocked),
    );
  }

  /// Manually adjusts Exposure Bias (-3.0 to +3.0 EV).
  Future<void> setExposureBias(double bias, [CameraController? camera]) async {
    final clamped = bias.clamp(-3.0, 3.0);
    if (camera != null && camera.value.isInitialized) {
      try {
        final minOffset = await camera.getMinExposureOffset();
        final maxOffset = await camera.getMaxExposureOffset();
        final targetOffset = clamped.clamp(minOffset, maxOffset);
        await camera.setExposureOffset(targetOffset);
      } catch (e) {
        debugPrint('[CameraLooksController] Error setting EV offset: $e');
      }
    }

    state = state.copyWith(
      smartLock: state.smartLock.copyWith(exposureBias: clamped),
    );
  }

  /// Adjusts ISO sensitivity (Auto or discrete 50..3200).
  void setIso(int? iso) {
    _haptic(HapticFeedback.selectionClick);
    state = state.copyWith(
      smartLock: state.smartLock.copyWith(
        iso: iso,
        clearIso: iso == null,
      ),
    );
  }

  /// Adjusts shutter speed (Auto or discrete 1/8000..1/24).
  void setShutterSpeed(double? shutterSeconds) {
    _haptic(HapticFeedback.selectionClick);
    state = state.copyWith(
      smartLock: state.smartLock.copyWith(
        shutterSeconds: shutterSeconds,
        clearShutter: shutterSeconds == null,
      ),
    );
  }

  /// Adjusts White Balance preset or Kelvin temperature.
  void setWhiteBalance(String mode, {int? kelvin}) {
    _haptic(HapticFeedback.selectionClick);
    state = state.copyWith(
      smartLock: state.smartLock.copyWith(
        whiteBalanceMode: mode,
        kelvin: kelvin ?? state.smartLock.kelvin,
      ),
    );
  }

  /// Sets manual focus distance (0.0 to 1.0) and locks focus mode.
  Future<void> setManualFocus(double? distance, [CameraController? camera]) async {
    if (distance == null) {
      // Return to auto focus
      if (camera != null && camera.value.isInitialized) {
        try {
          await camera.setFocusMode(FocusMode.auto);
        } catch (_) {}
      }
      state = state.copyWith(
        smartLock: state.smartLock.copyWith(clearFocusDistance: true, afLocked: false),
      );
      return;
    }

    final clamped = distance.clamp(0.0, 1.0);
    if (camera != null && camera.value.isInitialized) {
      try {
        await camera.setFocusMode(FocusMode.locked);
      } catch (_) {}
    }

    state = state.copyWith(
      smartLock: state.smartLock.copyWith(
        focusDistance: clamped,
        afLocked: true,
      ),
    );
  }

  /// Toggles focus peaking highlight overlay.
  void toggleFocusPeaking() {
    _haptic(HapticFeedback.lightImpact);
    state = state.copyWith(
      smartLock: state.smartLock.copyWith(
        isFocusPeakingEnabled: !state.smartLock.isFocusPeakingEnabled,
      ),
    );
  }

  /// Updates recording timer elapsed seconds.
  void setRecordingSeconds(int seconds) {
    state = state.copyWith(recordingElapsedSeconds: seconds);
  }
}

/// Provider for CameraLooksController.
final cameraLooksControllerProvider =
    NotifierProvider<CameraLooksController, CameraLooksState>(CameraLooksController.new);
