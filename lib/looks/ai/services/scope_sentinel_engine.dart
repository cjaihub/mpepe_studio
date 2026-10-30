import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/oneova_look.dart';
import '../models/scope_sentinel_alert.dart';
import '../scopes/models/scope_frame_data.dart';

/// Silent AI monitor analyzing scope metrics and popping contextual one-tap fixes.
class ScopeSentinelEngine {
  final StreamController<ScopeSentinelAlert?> _alertController =
      StreamController<ScopeSentinelAlert?>.broadcast();

  Stream<ScopeSentinelAlert?> get onAlert => _alertController.stream;
  ScopeSentinelAlert? _lastActiveAlert;
  ScopeSentinelAlert? get lastActiveAlert => _lastActiveAlert;

  DateTime _lastAlertTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _alertCooldown = Duration(seconds: 4);

  /// Evaluates telemetry and current look graph; emits alert if out of safe bounds.
  ScopeSentinelAlert? evaluateFrame({
    required ScopeFrameData data,
    required OneovaLook currentLook,
  }) {
    final now = DateTime.now();

    // 1. Blown Highlights Check (> 2.5% pixels clipped)
    if (data.highlightClippingPercent > 2.5) {
      final alert = ScopeSentinelAlert(
        id: 'highlight_clip_${now.millisecondsSinceEpoch}',
        type: SentinelAlertType.blownHighlights,
        severity: data.highlightClippingPercent > 10.0 ? SentinelSeverity.critical : SentinelSeverity.warning,
        headline: 'Highlight Clipping Detected',
        description: '${data.highlightClippingPercent.toStringAsFixed(1)}% of pixels exceed 100 IRE',
        suggestedFixLabel: 'Recover',
        applyFix: (look) {
          final curHigh = look.primary.highlights;
          final curExp = look.primary.exposure;
          return look.copyWith(
            primary: look.primary.copyWith(
              highlights: curHigh - 0.25,
              exposure: (curExp - 0.15).clamp(-3.0, 3.0),
            ),
          );
        },
        timestamp: now,
      );
      _postAlert(alert, now);
      return alert;
    }

    // 2. Crushed Shadows Check (> 3.5% pixels crushed)
    if (data.shadowClippingPercent > 3.5) {
      final alert = ScopeSentinelAlert(
        id: 'shadow_crush_${now.millisecondsSinceEpoch}',
        type: SentinelAlertType.crushedShadows,
        severity: data.shadowClippingPercent > 12.0 ? SentinelSeverity.critical : SentinelSeverity.warning,
        headline: 'Crushed Shadows',
        description: '${data.shadowClippingPercent.toStringAsFixed(1)}% of pixels crushed below 0 IRE',
        suggestedFixLabel: 'Lift',
        applyFix: (look) {
          final curShadows = look.primary.shadows;
          return look.copyWith(
            primary: look.primary.copyWith(
              shadows: curShadows + 0.3,
            ),
          );
        },
        timestamp: now,
      );
      _postAlert(alert, now);
      return alert;
    }

    // 3. Skin Tone Cast Alignment Check (divergence from 57° I-line)
    final skinDelta = (data.skinToneAngleDegrees - ScopeFrameData.skinToneTargetAngle).abs();
    if (skinDelta > 16.0) {
      final isCool = data.skinToneAngleDegrees < ScopeFrameData.skinToneTargetAngle;
      final alert = ScopeSentinelAlert(
        id: 'skin_cast_${now.millisecondsSinceEpoch}',
        type: SentinelAlertType.skinToneCast,
        severity: skinDelta > 28.0 ? SentinelSeverity.warning : SentinelSeverity.info,
        headline: isCool ? 'Cool Skin Cast' : 'Warm Skin Cast',
        description: 'Skin chroma angle shifted ${skinDelta.round()}° from 57° skin line',
        suggestedFixLabel: 'Balance',
        applyFix: (look) {
          final curTemp = look.color.temperature;
          final curTint = look.color.tint;
          final tempAdj = isCool ? 4.5 : -4.5;
          return look.copyWith(
            color: look.color.copyWith(
              temperature: curTemp + tempAdj,
              tint: (curTint * 0.5).clamp(-20.0, 20.0),
            ),
          );
        },
        timestamp: now,
      );
      _postAlert(alert, now);
      return alert;
    }

    // 4. Low Dynamic Contrast (< 5.5 stops)
    if (data.dynamicRangeStops < 5.5) {
      final alert = ScopeSentinelAlert(
        id: 'low_contrast_${now.millisecondsSinceEpoch}',
        type: SentinelAlertType.lowContrast,
        severity: SentinelSeverity.info,
        headline: 'Flat Dynamic Range',
        description: 'Image dynamic range compressed (${data.dynamicRangeStops.toStringAsFixed(1)} stops)',
        suggestedFixLabel: 'Pop',
        applyFix: (look) {
          final curContrast = look.primary.contrast;
          return look.copyWith(
            primary: look.primary.copyWith(
              contrast: (curContrast * 1.15).clamp(0.5, 2.0),
            ),
          );
        },
        timestamp: now,
      );
      _postAlert(alert, now);
      return alert;
    }

    // No anomalies
    if (_lastActiveAlert != null) {
      _lastActiveAlert = null;
      _alertController.add(null);
    }
    return null;
  }

  void _postAlert(ScopeSentinelAlert alert, DateTime now) {
    if (now.difference(_lastAlertTime) > _alertCooldown || _lastActiveAlert?.type != alert.type) {
      _lastActiveAlert = alert;
      _lastAlertTime = now;
      _alertController.add(alert);
    }
  }

  void dismissAlert() {
    _lastActiveAlert = null;
    _alertController.add(null);
  }

  void dispose() {
    _alertController.close();
  }
}

final scopeSentinelEngineProvider = Provider<ScopeSentinelEngine>((ref) {
  final engine = ScopeSentinelEngine();
  ref.onDispose(() => engine.dispose());
  return engine;
});
