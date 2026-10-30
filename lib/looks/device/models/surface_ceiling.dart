/// The surface context requesting quality ceilings.
enum SurfaceType {
  live,
  camera,
  editor;

  String get label => switch (this) {
        SurfaceType.live => 'Live Streaming',
        SurfaceType.camera => 'Camera Recording',
        SurfaceType.editor => 'Photo & Video Editor',
      };
}

/// The result of checking if a requested setting is within the safe ceiling.
class CeilingValidationResult {
  final bool isAllowed;
  final String? reason;
  final bool isOverridden;

  const CeilingValidationResult({
    required this.isAllowed,
    this.reason,
    this.isOverridden = false,
  });

  static const valid = CeilingValidationResult(isAllowed: true);
}

/// Safe hardware/thermal operating ceilings computed by the DeviceAdvisor for a surface.
class SurfaceCeiling {
  final SurfaceType surface;
  final int maxWidth;
  final int maxHeight;
  final int maxFps;
  final double maxBeautyLevel; // 0.0 to 1.0
  final int maxSegmentationFps;
  final bool allowHdr;
  final bool allowSharpen;
  final int maxLutSize;
  final int maxLutStack;
  final bool allowCloudOffload;
  final String reason;

  const SurfaceCeiling({
    required this.surface,
    required this.maxWidth,
    required this.maxHeight,
    required this.maxFps,
    required this.maxBeautyLevel,
    required this.maxSegmentationFps,
    required this.allowHdr,
    required this.allowSharpen,
    required this.maxLutSize,
    required this.maxLutStack,
    required this.allowCloudOffload,
    required this.reason,
  });

  /// Validates a requested resolution against this ceiling.
  CeilingValidationResult validateResolution({
    required int width,
    required int height,
    bool proOverride = false,
  }) {
    final requestedPixels = width * height;
    final maxPixels = maxWidth * maxHeight;

    if (requestedPixels > maxPixels) {
      if (proOverride) {
        return CeilingValidationResult(
          isAllowed: true,
          reason: 'Bypassed by Pro override: ${width}x$height exceeds recommended ${maxWidth}x$maxHeight',
          isOverridden: true,
        );
      }
      return CeilingValidationResult(
        isAllowed: false,
        reason: 'Resolution ${width}x$height exceeds safe ceiling ${maxWidth}x$maxHeight ($reason)',
      );
    }
    return CeilingValidationResult.valid;
  }

  /// Validates a requested FPS against this ceiling.
  CeilingValidationResult validateFps({
    required int fps,
    bool proOverride = false,
  }) {
    if (fps > maxFps) {
      if (proOverride) {
        return CeilingValidationResult(
          isAllowed: true,
          reason: 'Bypassed by Pro override: ${fps}fps exceeds recommended ${maxFps}fps',
          isOverridden: true,
        );
      }
      return CeilingValidationResult(
        isAllowed: false,
        reason: '${fps}fps exceeds safe ceiling of ${maxFps}fps ($reason)',
      );
    }
    return CeilingValidationResult.valid;
  }

  /// Validates beauty intensity level.
  CeilingValidationResult validateBeautyLevel({
    required double level,
    bool proOverride = false,
  }) {
    if (level > maxBeautyLevel) {
      if (proOverride) {
        return CeilingValidationResult(
          isAllowed: true,
          reason: 'Bypassed by Pro override: beauty level ${(level * 100).toInt()}% exceeds recommended ${(maxBeautyLevel * 100).toInt()}%',
          isOverridden: true,
        );
      }
      return CeilingValidationResult(
        isAllowed: false,
        reason: 'Beauty level ${(level * 100).toInt()}% exceeds safe ceiling of ${(maxBeautyLevel * 100).toInt()}% ($reason)',
      );
    }
    return CeilingValidationResult.valid;
  }

  Map<String, dynamic> toMap() => {
        'surface': surface.name,
        'maxWidth': maxWidth,
        'maxHeight': maxHeight,
        'maxFps': maxFps,
        'maxBeautyLevel': maxBeautyLevel,
        'maxSegmentationFps': maxSegmentationFps,
        'allowHdr': allowHdr,
        'allowSharpen': allowSharpen,
        'maxLutSize': maxLutSize,
        'maxLutStack': maxLutStack,
        'allowCloudOffload': allowCloudOffload,
        'reason': reason,
      };

  SurfaceCeiling copyWith({
    SurfaceType? surface,
    int? maxWidth,
    int? maxHeight,
    int? maxFps,
    double? maxBeautyLevel,
    int? maxSegmentationFps,
    bool? allowHdr,
    bool? allowSharpen,
    int? maxLutSize,
    int? maxLutStack,
    bool? allowCloudOffload,
    String? reason,
  }) {
    return SurfaceCeiling(
      surface: surface ?? this.surface,
      maxWidth: maxWidth ?? this.maxWidth,
      maxHeight: maxHeight ?? this.maxHeight,
      maxFps: maxFps ?? this.maxFps,
      maxBeautyLevel: maxBeautyLevel ?? this.maxBeautyLevel,
      maxSegmentationFps: maxSegmentationFps ?? this.maxSegmentationFps,
      allowHdr: allowHdr ?? this.allowHdr,
      allowSharpen: allowSharpen ?? this.allowSharpen,
      maxLutSize: maxLutSize ?? this.maxLutSize,
      maxLutStack: maxLutStack ?? this.maxLutStack,
      allowCloudOffload: allowCloudOffload ?? this.allowCloudOffload,
      reason: reason ?? this.reason,
    );
  }
}
