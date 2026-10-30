import 'package:flutter/services.dart';

/// Instantaneous thermal and power snapshot from native OS sensors.
class ThermalHeadroomSnapshot {
  final double headroom;
  final double forecastHeadroom10s;
  final String thermalLevel; // "nominal", "fair", "serious", "critical"
  final bool isPowerSaveMode;
  final int batteryLevel;
  final bool isCharging;
  final DateTime timestamp;

  const ThermalHeadroomSnapshot({
    required this.headroom,
    required this.forecastHeadroom10s,
    required this.thermalLevel,
    required this.isPowerSaveMode,
    required this.batteryLevel,
    required this.isCharging,
    required this.timestamp,
  });

  factory ThermalHeadroomSnapshot.fromMap(Map<dynamic, dynamic> map) {
    final tsMs = (map['timestamp'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    return ThermalHeadroomSnapshot(
      headroom: (map['headroom'] as num?)?.toDouble() ?? 0.5,
      forecastHeadroom10s:
          (map['forecastHeadroom10s'] as num?)?.toDouble() ?? 0.5,
      thermalLevel: map['thermalLevel']?.toString() ?? 'nominal',
      isPowerSaveMode: map['isPowerSaveMode'] as bool? ?? false,
      batteryLevel: (map['batteryLevel'] as num?)?.toInt() ?? 100,
      isCharging: map['isCharging'] as bool? ?? false,
      timestamp: DateTime.fromMillisecondsSinceEpoch(tsMs),
    );
  }

  Map<String, dynamic> toMap() => {
        'headroom': headroom,
        'forecastHeadroom10s': forecastHeadroom10s,
        'thermalLevel': thermalLevel,
        'isPowerSaveMode': isPowerSaveMode,
        'batteryLevel': batteryLevel,
        'isCharging': isCharging,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  bool get isCritical =>
      thermalLevel == 'critical' || headroom >= 1.15;

  bool get isSerious =>
      thermalLevel == 'serious' || headroom >= 0.95;

  bool get isElevated =>
      thermalLevel != 'nominal' || headroom >= 0.75;
}

/// Native channel bridge for thermal headroom forecasting and ADPF hint sessions.
class ThermalProbe {
  static const MethodChannel _defaultChannel =
      MethodChannel('oneova_camera_kit/device');

  /// Forecasts thermal headroom for [forecastSeconds] into the future (0 to 60s).
  /// Android: calls PowerManager.getThermalHeadroom.
  /// iOS: maps ProcessInfo.thermalState.
  static Future<double> getThermalHeadroom({
    int forecastSeconds = 0,
    MethodChannel? channelOverride,
  }) async {
    final channel = channelOverride ?? _defaultChannel;
    try {
      final res = await channel.invokeMethod<num>(
        'getThermalHeadroom',
        {'forecastSeconds': forecastSeconds},
      );
      if (res != null) {
        return res.toDouble();
      }
    } catch (_) {}
    return 0.5;
  }

  /// Returns full snapshot of current thermal headroom, forecast, and battery state.
  static Future<ThermalHeadroomSnapshot> getThermalSnapshot({
    MethodChannel? channelOverride,
  }) async {
    final channel = channelOverride ?? _defaultChannel;
    try {
      final res = await channel.invokeMethod<Map<dynamic, dynamic>>(
        'getThermalSnapshot',
      );
      if (res != null) {
        return ThermalHeadroomSnapshot.fromMap(res);
      }
    } catch (_) {}

    return ThermalHeadroomSnapshot(
      headroom: 0.5,
      forecastHeadroom10s: 0.5,
      thermalLevel: 'nominal',
      isPowerSaveMode: false,
      batteryLevel: 100,
      isCharging: false,
      timestamp: DateTime.now(),
    );
  }

  /// Android ADPF: Creates a performance hint session for a target duration in nanoseconds.
  /// (Default: 16.66ms target for 60fps).
  static Future<bool> createHintSession({
    int targetDurationNanos = 16666666,
    MethodChannel? channelOverride,
  }) async {
    final channel = channelOverride ?? _defaultChannel;
    try {
      final res = await channel.invokeMethod<bool>(
        'createHintSession',
        {'targetDurationNanos': targetDurationNanos},
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Android ADPF: Reports actual frame render duration in nanoseconds.
  static Future<bool> reportActualDuration({
    required int actualDurationNanos,
    MethodChannel? channelOverride,
  }) async {
    final channel = channelOverride ?? _defaultChannel;
    try {
      final res = await channel.invokeMethod<bool>(
        'reportActualDuration',
        {'actualDurationNanos': actualDurationNanos},
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Closes active ADPF hint session.
  static Future<void> closeHintSession({
    MethodChannel? channelOverride,
  }) async {
    final channel = channelOverride ?? _defaultChannel;
    try {
      await channel.invokeMethod<void>('closeHintSession');
    } catch (_) {}
  }
}
