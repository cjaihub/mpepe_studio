import 'package:flutter/foundation.dart';
import '../../models/oneova_look.dart';

/// Scope types available for GPU telemetry preview.
enum ScopeType {
  waveform,
  rgbParade,
  vectorscope,
  histogram,
}

/// Active editing mode in the Photo Grading Studio.
enum PhotoGradingMode {
  /// Streamlined creator view with preset catalog and essential macro sliders.
  simple,

  /// Full DaVinci/Lightroom-style grading deck with access to all Look graph nodes.
  pro,
}

/// Node tabs available in Pro grading mode.
enum PhotoProNodeTab {
  primary('Primary', 'Exposure, contrast & tonality'),
  wheels('Wheels', '3-Way Lift, Gamma, Gain & Offset'),
  color('Color', 'Temp, tint, vibrance & saturation'),
  curves('Curves', 'Custom RGB & Hue-vs-Sat curves'),
  hsl('HSL Mixer', '8-Band targeted hue, sat & lum'),
  film('Film Stock', 'Emulation, halation, grain & bloom'),
  detail('Detail', 'Sharpening, clarity & texture'),
  optics('Optics', 'Vignette, chromatic aberration & distortion'),
  boostBeauty('Boost Beauty', 'Skin, eyes, teeth & contouring'),
  background('Background', 'Depth blur, replace & green-screen'),
  masks('Masks', 'Semantic face, sky & subject masks');

  final String label;
  final String description;
  const PhotoProNodeTab(this.label, this.description);
}

/// Metadata and state of a photo asset being graded in the studio.
@immutable
class PhotoAssetMeta {
  final String path;
  final int width;
  final int height;
  final int orientationDegrees;
  final int bitDepth;
  final String colorSpace;
  final int fileSizeBytes;
  final Map<String, dynamic> exifTags;

  const PhotoAssetMeta({
    required this.path,
    this.width = 1920,
    this.height = 1080,
    this.orientationDegrees = 0,
    this.bitDepth = 8,
    this.colorSpace = 'sRGB',
    this.fileSizeBytes = 0,
    this.exifTags = const {},
  });

  PhotoAssetMeta copyWith({
    String? path,
    int? width,
    int? height,
    int? orientationDegrees,
    int? bitDepth,
    String? colorSpace,
    int? fileSizeBytes,
    Map<String, dynamic>? exifTags,
  }) {
    return PhotoAssetMeta(
      path: path ?? this.path,
      width: width ?? this.width,
      height: height ?? this.height,
      orientationDegrees: orientationDegrees ?? this.orientationDegrees,
      bitDepth: bitDepth ?? this.bitDepth,
      colorSpace: colorSpace ?? this.colorSpace,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      exifTags: exifTags ?? this.exifTags,
    );
  }
}

/// Comprehensive state of the Photo Grading session.
@immutable
class PhotoGradingState {
  final PhotoAssetMeta? activePhoto;
  final OneovaLook currentLook;
  final OneovaLook baselineLook;
  final PhotoGradingMode mode;
  final PhotoProNodeTab activeProTab;
  final bool isComparing;
  final bool isScopesVisible;
  final ScopeType activeScopeType;
  final List<String> batchQueue;
  final bool isExporting;
  final double exportProgress;
  final String? statusMessage;

  const PhotoGradingState({
    this.activePhoto,
    required this.currentLook,
    required this.baselineLook,
    this.mode = PhotoGradingMode.simple,
    this.activeProTab = PhotoProNodeTab.primary,
    this.isComparing = false,
    this.isScopesVisible = false,
    this.activeScopeType = ScopeType.waveform,
    this.batchQueue = const [],
    this.isExporting = false,
    this.exportProgress = 0.0,
    this.statusMessage,
  });

  bool get hasActivePhoto => activePhoto != null;
  bool get hasBatchQueue => batchQueue.isNotEmpty;

  PhotoGradingState copyWith({
    PhotoAssetMeta? activePhoto,
    OneovaLook? currentLook,
    OneovaLook? baselineLook,
    PhotoGradingMode? mode,
    PhotoProNodeTab? activeProTab,
    bool? isComparing,
    bool? isScopesVisible,
    ScopeType? activeScopeType,
    List<String>? batchQueue,
    bool? isExporting,
    double? exportProgress,
    String? statusMessage,
  }) {
    return PhotoGradingState(
      activePhoto: activePhoto ?? this.activePhoto,
      currentLook: currentLook ?? this.currentLook,
      baselineLook: baselineLook ?? this.baselineLook,
      mode: mode ?? this.mode,
      activeProTab: activeProTab ?? this.activeProTab,
      isComparing: isComparing ?? this.isComparing,
      isScopesVisible: isScopesVisible ?? this.isScopesVisible,
      activeScopeType: activeScopeType ?? this.activeScopeType,
      batchQueue: batchQueue ?? this.batchQueue,
      isExporting: isExporting ?? this.isExporting,
      exportProgress: exportProgress ?? this.exportProgress,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

/// Status of an individual item in a batch grading pipeline.
enum BatchItemStatus { pending, processing, completed, failed }

@immutable
class BatchGradingItem {
  final String sourcePath;
  final String? outputPath;
  final BatchItemStatus status;
  final String? errorMessage;
  final int durationMs;

  const BatchGradingItem({
    required this.sourcePath,
    this.outputPath,
    this.status = BatchItemStatus.pending,
    this.errorMessage,
    this.durationMs = 0,
  });

  BatchGradingItem copyWith({
    String? sourcePath,
    String? outputPath,
    BatchItemStatus? status,
    String? errorMessage,
    int? durationMs,
  }) {
    return BatchGradingItem(
      sourcePath: sourcePath ?? this.sourcePath,
      outputPath: outputPath ?? this.outputPath,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      durationMs: durationMs ?? this.durationMs,
    );
  }
}

/// Result of a completed batch grading operation.
@immutable
class BatchGradingReport {
  final int totalCount;
  final int successCount;
  final int failedCount;
  final List<BatchGradingItem> items;
  final Duration totalDuration;

  const BatchGradingReport({
    required this.totalCount,
    required this.successCount,
    required this.failedCount,
    required this.items,
    required this.totalDuration,
  });
}

/// Result of an original-resolution export operation.
@immutable
class PhotoExportResult {
  final String outputPath;
  final int outputWidth;
  final int outputHeight;
  final int fileSizeBytes;
  final Duration renderDuration;
  final bool exifPreserved;

  const PhotoExportResult({
    required this.outputPath,
    required this.outputWidth,
    required this.outputHeight,
    required this.fileSizeBytes,
    required this.renderDuration,
    required this.exifPreserved,
  });
}
