import 'dart:ui';
import 'render_context.dart';

enum RenderQuality {
  draft,
  balanced,
  high,
  full,
}

enum RenderIntent {
  preview,
  scrub,
  still,
  photo,
  export,
  proxyGeneration,
}

class RenderRequest {
  final String projectId;
  final String sequenceId;
  final Duration sequenceTime;
  final RenderQuality quality;
  final RenderIntent intent;
  
  // Optional constraints
  final Size? targetSize;
  final RenderContext? renderContext;
  
  // Cancellation token
  final bool Function()? isCancelled;

  const RenderRequest({
    required this.projectId,
    required this.sequenceId,
    required this.sequenceTime,
    this.quality = RenderQuality.balanced,
    this.intent = RenderIntent.preview,
    this.targetSize,
    this.renderContext,
    this.isCancelled,
  });
}
