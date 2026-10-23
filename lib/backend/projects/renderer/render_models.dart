import 'dart:typed_data';
import 'dart:ui' as ui;
import '../editor/timeline_time.dart';

enum RenderTarget {
  livePreview,
  thumbnail,
  scope,
  export,
  cache,
}

enum PreviewQuality {
  draft,
  balanced,
  high,
  full,
}

class RenderRequest {
  final String projectId;
  final String sequenceId;
  final TimelineTime sequenceTime;
  final RenderTarget target;
  final PreviewQuality quality;
  final bool useProxy;
  final bool bypassEffects;
  final bool isPhotoRender;

  const RenderRequest({
    required this.projectId,
    required this.sequenceId,
    required this.sequenceTime,
    this.target = RenderTarget.livePreview,
    this.quality = PreviewQuality.balanced,
    this.useProxy = true,
    this.bypassEffects = false,
    this.isPhotoRender = false,
  });

  String get cacheKey => '\$projectId:\$sequenceId:\${sequenceTime.toSeconds}:\$target:\$quality:\$useProxy:\$bypassEffects';
}

class RenderFrame {
  final ui.Image? image; // SUPPORTED MODEL, RENDERER PENDING - actual pixel buffer
  final Uint8List? rawPixels;
  final int width;
  final int height;
  final double timestamp;
  final String colorSpace;

  const RenderFrame({
    this.image,
    this.rawPixels,
    required this.width,
    required this.height,
    required this.timestamp,
    required this.colorSpace,
  });
  
  void dispose() {
    image?.dispose();
  }
}

class RenderDiagnostic {
  final String code;
  final String message;
  final Exception? exception;

  const RenderDiagnostic(this.code, this.message, [this.exception]);

  static const missingSource = RenderDiagnostic('MISSING_SOURCE', 'Original media file not found.');
  static const missingProxy = RenderDiagnostic('MISSING_PROXY', 'Proxy media file not found.');
  static const unsupportedCodec = RenderDiagnostic('UNSUPPORTED_CODEC', 'The media codec is not supported.');
  static const missingLut = RenderDiagnostic('MISSING_LUT', 'A required LUT file is missing.');
  static const missingMask = RenderDiagnostic('MISSING_MASK', 'A referenced mask could not be resolved.');
  static const rendererUnsupported = RenderDiagnostic('RENDERER_UNSUPPORTED', 'Requested operation is not supported by the renderer.');
  static const insufficientMemory = RenderDiagnostic('INSUFFICIENT_MEMORY', 'Not enough memory to complete rendering.');
  static const invalidEffect = RenderDiagnostic('INVALID_EFFECT', 'Effect definition or parameters are invalid.');
  static const corruptFrame = RenderDiagnostic('CORRUPT_FRAME', 'The source frame data is corrupted.');
  static const exportEncoderFailure = RenderDiagnostic('EXPORT_ENCODER_FAILURE', 'The export encoder failed.');
}

class RenderResult {
  final RenderFrame? frame;
  final List<RenderDiagnostic> diagnostics;
  final bool isSuccess;
  final Duration renderTime;
  final Duration decodeTime;

  const RenderResult({
    this.frame,
    this.diagnostics = const [],
    required this.isSuccess,
    this.renderTime = Duration.zero,
    this.decodeTime = Duration.zero,
  });
}
