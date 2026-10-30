import 'package:flutter/foundation.dart';
import '../../models/oneova_look.dart';

/// Categories of technical color abnormalities detected by Scope Sentinel.
enum SentinelAlertType {
  crushedShadows,
  blownHighlights,
  skinToneCast,
  lowContrast,
  excessiveSaturation,
  gamutViolation,
  shotMismatch,
  colorTemperatureDrift;

  String get label => switch (this) {
        SentinelAlertType.crushedShadows => 'Crushed Shadows',
        SentinelAlertType.blownHighlights => 'Blown Highlights',
        SentinelAlertType.skinToneCast => 'Skin Tone Cast',
        SentinelAlertType.lowContrast => 'Low Dynamic Contrast',
        SentinelAlertType.excessiveSaturation => 'Oversaturation',
        SentinelAlertType.gamutViolation => 'Gamut Clipping',
        SentinelAlertType.shotMismatch => 'Shot Mismatch',
        SentinelAlertType.colorTemperatureDrift => 'WB Temperature Drift',
      };
}

enum SentinelSeverity {
  info,
  warning,
  critical;

  bool get isCritical => this == SentinelSeverity.critical;
}

/// Alert emitted by Scope Sentinel when real-time frame telemetry exceeds safe aesthetic/technical bounds.
@immutable
class ScopeSentinelAlert {
  final String id;
  final SentinelAlertType type;
  final SentinelSeverity severity;
  final String headline;
  final String description;
  final String suggestedFixLabel;
  final OneovaLook Function(OneovaLook currentLook) applyFix;
  final DateTime timestamp;

  const ScopeSentinelAlert({
    required this.id,
    required this.type,
    required this.severity,
    required this.headline,
    required this.description,
    required this.suggestedFixLabel,
    required this.applyFix,
    required this.timestamp,
  });

  @override
  String toString() =>
      'ScopeSentinelAlert(id: $id, type: ${type.name}, severity: ${severity.name}, headline: "$headline")';
}
