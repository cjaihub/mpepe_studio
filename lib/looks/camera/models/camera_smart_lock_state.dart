import 'package:flutter/foundation.dart';

/// Camera capture mode for the Snap-style creator camera.
enum CaptureMode {
  photo,
  video,
  fast,
  fastMotion,
  slowMotion,
  multiSnap,
  dualCamera,
  handsFree,
  night,
  pro;

  String get label => switch (this) {
        CaptureMode.photo => 'PHOTO',
        CaptureMode.video => 'VIDEO',
        CaptureMode.fast || CaptureMode.fastMotion => 'FAST',
        CaptureMode.slowMotion => 'SLOW-MO',
        CaptureMode.multiSnap => 'MULTI-SNAP',
        CaptureMode.dualCamera => 'DUAL CAM',
        CaptureMode.handsFree => 'HANDS-FREE',
        CaptureMode.night => 'NIGHT',
        CaptureMode.pro => 'PRO',
      };

  bool get isVideoType =>
      this == CaptureMode.video ||
      this == CaptureMode.fast ||
      this == CaptureMode.fastMotion ||
      this == CaptureMode.slowMotion ||
      this == CaptureMode.handsFree;
}

/// State of Camera Smart Lock (AE, AF, AWB automatic lock on record)
/// and manual Pro adjustments (EV bias, ISO, Shutter, Kelvin, Manual Focus).
@immutable
class CameraSmartLockState {
  final bool isSmartLockActive;
  final bool aeLocked;
  final bool afLocked;
  final bool awbLocked;
  final double exposureBias; // EV -3.0 to +3.0
  final int? iso; // null = Auto
  final double? shutterSeconds; // null = Auto, e.g. 1/125 = 0.008
  final String whiteBalanceMode; // 'auto', 'daylight', 'cloudy', 'tungsten', 'fluorescent', 'kelvin'
  final int kelvin; // 2500 - 9000
  final double? focusDistance; // null = Auto, 0.0 (near) to 1.0 (infinity)
  final bool isFocusPeakingEnabled;

  const CameraSmartLockState({
    this.isSmartLockActive = false,
    this.aeLocked = false,
    this.afLocked = false,
    this.awbLocked = false,
    this.exposureBias = 0.0,
    this.iso,
    this.shutterSeconds,
    this.whiteBalanceMode = 'auto',
    this.kelvin = 5600,
    this.focusDistance,
    this.isFocusPeakingEnabled = false,
  });

  bool get isAnyLockActive => aeLocked || afLocked || awbLocked;
  bool get isManualProActive =>
      exposureBias != 0.0 ||
      iso != null ||
      shutterSeconds != null ||
      whiteBalanceMode != 'auto' ||
      focusDistance != null;

  CameraSmartLockState copyWith({
    bool? isSmartLockActive,
    bool? aeLocked,
    bool? afLocked,
    bool? awbLocked,
    double? exposureBias,
    int? iso,
    bool clearIso = false,
    double? shutterSeconds,
    bool clearShutter = false,
    String? whiteBalanceMode,
    int? kelvin,
    double? focusDistance,
    bool clearFocusDistance = false,
    bool? isFocusPeakingEnabled,
  }) {
    return CameraSmartLockState(
      isSmartLockActive: isSmartLockActive ?? this.isSmartLockActive,
      aeLocked: aeLocked ?? this.aeLocked,
      afLocked: afLocked ?? this.afLocked,
      awbLocked: awbLocked ?? this.awbLocked,
      exposureBias: exposureBias ?? this.exposureBias,
      iso: clearIso ? null : (iso ?? this.iso),
      shutterSeconds: clearShutter ? null : (shutterSeconds ?? this.shutterSeconds),
      whiteBalanceMode: whiteBalanceMode ?? this.whiteBalanceMode,
      kelvin: kelvin ?? this.kelvin,
      focusDistance: clearFocusDistance ? null : (focusDistance ?? this.focusDistance),
      isFocusPeakingEnabled: isFocusPeakingEnabled ?? this.isFocusPeakingEnabled,
    );
  }

  Map<String, dynamic> toMap() => {
        'isSmartLockActive': isSmartLockActive,
        'aeLocked': aeLocked,
        'afLocked': afLocked,
        'awbLocked': awbLocked,
        'exposureBias': exposureBias,
        'iso': iso,
        'shutterSeconds': shutterSeconds,
        'whiteBalanceMode': whiteBalanceMode,
        'kelvin': kelvin,
        'focusDistance': focusDistance,
        'isFocusPeakingEnabled': isFocusPeakingEnabled,
      };

  factory CameraSmartLockState.fromMap(Map<String, dynamic> map) {
    return CameraSmartLockState(
      isSmartLockActive: map['isSmartLockActive'] as bool? ?? false,
      aeLocked: map['aeLocked'] as bool? ?? false,
      afLocked: map['afLocked'] as bool? ?? false,
      awbLocked: map['awbLocked'] as bool? ?? false,
      exposureBias: (map['exposureBias'] as num?)?.toDouble() ?? 0.0,
      iso: (map['iso'] as num?)?.toInt(),
      shutterSeconds: (map['shutterSeconds'] as num?)?.toDouble(),
      whiteBalanceMode: map['whiteBalanceMode'] as String? ?? 'auto',
      kelvin: (map['kelvin'] as num?)?.toInt() ?? 5600,
      focusDistance: (map['focusDistance'] as num?)?.toDouble(),
      isFocusPeakingEnabled: map['isFocusPeakingEnabled'] as bool? ?? false,
    );
  }
}
