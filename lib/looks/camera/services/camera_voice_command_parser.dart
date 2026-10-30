import 'package:flutter/foundation.dart';

/// Represents recognized user intents from Ova Assistant voice commands in camera mode.
@immutable
sealed class CameraVoiceIntent {
  const CameraVoiceIntent();
}

class CapturePhotoIntent extends CameraVoiceIntent {
  final int timerSeconds;
  const CapturePhotoIntent({this.timerSeconds = 0});

  @override
  String toString() => 'CapturePhotoIntent(timer: ${timerSeconds}s)';
}

class StartRecordingIntent extends CameraVoiceIntent {
  const StartRecordingIntent();

  @override
  String toString() => 'StartRecordingIntent()';
}

class StopRecordingIntent extends CameraVoiceIntent {
  const StopRecordingIntent();

  @override
  String toString() => 'StopRecordingIntent()';
}

class SwitchCameraIntent extends CameraVoiceIntent {
  final bool? front; // true for front/selfie, false for rear/back, null for toggle
  const SwitchCameraIntent({this.front});

  @override
  String toString() => 'SwitchCameraIntent(front: $front)';
}

class ApplyLookIntent extends CameraVoiceIntent {
  final String lookQuery;
  const ApplyLookIntent(this.lookQuery);

  @override
  String toString() => 'ApplyLookIntent(query: "$lookQuery")';
}

class SetBeautyIntent extends CameraVoiceIntent {
  final double intensity; // 0.0 to 1.0
  const SetBeautyIntent(this.intensity);

  @override
  String toString() => 'SetBeautyIntent(intensity: ${(intensity * 100).round()}%)';
}

class ToggleSmartLockIntent extends CameraVoiceIntent {
  final bool enable;
  const ToggleSmartLockIntent(this.enable);

  @override
  String toString() => 'ToggleSmartLockIntent(enable: $enable)';
}

class SetExposureIntent extends CameraVoiceIntent {
  final double evBias;
  const SetExposureIntent(this.evBias);

  @override
  String toString() => 'SetExposureIntent(ev: $evBias)';
}

class UnknownCameraVoiceIntent extends CameraVoiceIntent {
  final String rawInput;
  const UnknownCameraVoiceIntent(this.rawInput);

  @override
  String toString() => 'UnknownCameraVoiceIntent("$rawInput")';
}

/// Natural language voice intent parser for Ova Assistant camera controls.
class CameraVoiceCommandParser {
  const CameraVoiceCommandParser();

  /// Parses spoken user utterance into a strongly-typed [CameraVoiceIntent].
  CameraVoiceIntent parse(String rawUtterance) {
    final query = rawUtterance.trim().toLowerCase();
    if (query.isEmpty) {
      return const UnknownCameraVoiceIntent('');
    }

    // Photo capture intents
    if (_matches(query, [
      'take photo',
      'take a photo',
      'take a picture',
      'snap photo',
      'snap a photo',
      'snap picture',
      'capture photo',
      'take selfie',
      'snap selfie',
      'cheese',
      'click photo',
    ])) {
      final timerMatch = RegExp(r'in (\d+)\s*(?:seconds?|s)').firstMatch(query);
      final timerSecs = timerMatch != null ? int.tryParse(timerMatch.group(1) ?? '0') ?? 0 : 0;
      return CapturePhotoIntent(timerSeconds: timerSecs);
    }

    // Video record start intents
    if (_matches(query, [
      'start recording',
      'record video',
      'start video',
      'shoot video',
      'record a video',
      'begin recording',
      'start rolling',
      'record now',
    ])) {
      return const StartRecordingIntent();
    }

    // Video record stop intents
    if (_matches(query, [
      'stop recording',
      'stop video',
      'end recording',
      'finish recording',
      'cut',
      'pause recording',
      'stop rolling',
    ])) {
      return const StopRecordingIntent();
    }

    // Camera flip / switch intents
    if (_matches(query, [
      'switch camera',
      'flip camera',
      'turn camera',
      'reverse camera',
      'switch to front',
      'switch to back',
      'front camera',
      'rear camera',
      'selfie mode',
    ])) {
      if (query.contains('front') || query.contains('selfie')) {
        return const SwitchCameraIntent(front: true);
      } else if (query.contains('back') || query.contains('rear')) {
        return const SwitchCameraIntent(front: false);
      }
      return const SwitchCameraIntent(front: null);
    }

    // Smart lock toggle
    if (query.contains('smart lock') || query.contains('lock exposure') || query.contains('lock focus')) {
      final isUnlock = query.contains('off') || query.contains('unlock') || query.contains('disable');
      return ToggleSmartLockIntent(!isUnlock);
    }

    // Boost Beauty adjustments: "set beauty to 80%", "beauty 50", "turn off beauty"
    if (query.contains('beauty')) {
      if (query.contains('off') || query.contains('disable') || query.contains('zero')) {
        return const SetBeautyIntent(0.0);
      }
      final percentMatch = RegExp(r'(\d+)\s*(?:%|percent)?').firstMatch(query);
      if (percentMatch != null) {
        final val = double.tryParse(percentMatch.group(1) ?? '') ?? 50.0;
        final clamped = (val / 100.0).clamp(0.0, 1.0);
        return SetBeautyIntent(clamped);
      }
      return const SetBeautyIntent(0.7); // default beauty preset
    }

    // Exposure adjustments: "exposure plus 1", "brighter", "darker"
    if (query.contains('brighter') || query.contains('brighten')) {
      return const SetExposureIntent(1.0);
    }
    if (query.contains('darker')) {
      return const SetExposureIntent(-1.0);
    }
    if (query.contains('exposure')) {
      final evMatch = RegExp(r'([+-]?\d+(?:\.\d+)?)').firstMatch(query);
      if (evMatch != null) {
        final ev = double.tryParse(evMatch.group(1) ?? '0.0') ?? 0.0;
        return SetExposureIntent(ev.clamp(-3.0, 3.0));
      }
    }

    // Apply look / filter intents: "apply cinematic look", "set filter noir", "look vibrant"
    if (query.contains('look') || query.contains('filter') || query.contains('preset')) {
      final cleaned = query
          .replaceAll(RegExp(r'^(?:apply|set|switch to|put on|use)\s+'), '')
          .replaceAll(RegExp(r'^(?:look|filter|preset|style)\s+'), '')
          .replaceAll(RegExp(r'\s+(?:look|filter|preset|style)$'), '')
          .trim();
      if (cleaned.isNotEmpty) {
        return ApplyLookIntent(cleaned);
      }
    }

    return UnknownCameraVoiceIntent(rawUtterance);
  }

  bool _matches(String query, List<String> phrases) {
    for (final phrase in phrases) {
      if (query.contains(phrase)) return true;
    }
    return false;
  }
}
