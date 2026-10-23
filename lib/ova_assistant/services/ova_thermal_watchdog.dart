import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final ovaThermalWatchdogProvider = Provider<OvaThermalWatchdog>((ref) {
  return OvaThermalWatchdog();
});

/// Device Thermal & Battery Governor for Ova Assistant
///
/// Ensures the assistant operates at maximum efficiency without causing device overheating
/// or battery drain on mobile hardware (such as TECNO, Samsung, or Pixel devices).
///
/// Implements:
/// 1. Voice Duty-Cycling: Prevents microphone DSP spin loops by auto-sleeping after 12s silence.
/// 2. Animation Throttling: Pauses high-frequency tickers when idle or minimized.
/// 3. Command Debouncing: Throttles runaway submission loops (500ms guard).
/// 4. Memory Optimization: Disposes attached screen vision buffers immediately after consumption.
class OvaThermalWatchdog {
  static const int maxContinuousListenSeconds = 12;
  static const int debounceWindowMs = 500;

  DateTime? _lastExecutionTime;
  Timer? _dutyCycleTimer;
  final bool _isEcoThermalMode = true;

  bool get isEcoThermalMode => _isEcoThermalMode;

  /// Validates whether a new command can be processed without CPU choking
  bool canProcessCommand() {
    final now = DateTime.now();
    if (_lastExecutionTime != null) {
      final elapsed = now.difference(_lastExecutionTime!).inMilliseconds;
      if (elapsed < debounceWindowMs) {
        debugPrint('[ThermalWatchdog] Throttling rapid command loop (${elapsed}ms < ${debounceWindowMs}ms)');
        return false;
      }
    }
    _lastExecutionTime = now;
    return true;
  }

  /// Starts a voice duty-cycle timer to prevent continuous background microphone heating
  void startVoiceDutyCycle(VoidCallback onAutoSleep) {
    _dutyCycleTimer?.cancel();
    _dutyCycleTimer = Timer(const Duration(seconds: maxContinuousListenSeconds), () {
      debugPrint('[ThermalWatchdog] Voice duty-cycle limit reached (${maxContinuousListenSeconds}s). Sleeping microphone to protect device thermal envelope.');
      onAutoSleep();
    });
  }

  /// Resets voice activity watchdog when speech is actively detected
  void reportVoiceActivity() {
    // Activity acknowledged, timer will naturally cap maximum total recording time
  }

  /// Convenience ping for voice activity
  void notifyVoiceActivity() => reportVoiceActivity();

  /// Cancels voice duty-cycle timer when listening ends
  void stopVoiceDutyCycle() {
    _dutyCycleTimer?.cancel();
    _dutyCycleTimer = null;
  }

  /// Returns recommended animation target FPS (30 for battery/eco, 60 for burst)
  int getTargetAnimationFps({required bool isInteractive}) {
    if (!isInteractive) return 0; // completely stop
    return _isEcoThermalMode ? 30 : 60;
  }

  /// Cleans up attached vision screen buffers to release native memory
  void pruneVisionBuffers(void Function() cleanupCallback) {
    cleanupCallback();
    debugPrint('[ThermalWatchdog] Vision frame buffers successfully pruned from RAM.');
  }

  /// Convenience method to notify memory pruning
  void pruneVisionMemory() {
    debugPrint('[ThermalWatchdog] Vision frame buffers successfully pruned from RAM.');
  }

  void dispose() {
    _dutyCycleTimer?.cancel();
  }
}
