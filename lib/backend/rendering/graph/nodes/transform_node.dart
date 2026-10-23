import 'dart:async';
import '../render_node.dart';
import '../../models/render_frame.dart';
import '../../models/render_context.dart';
import '../../../projects/models/pro_project_models.dart';
import '../../../projects/models/keyframe_models.dart';

class TransformNode extends RenderNode {
  final TransformState baseTransform;
  final List<Keyframe> keyframes;
  final Duration sequenceTime;

  TransformNode({
    required super.id,
    required this.baseTransform,
    this.keyframes = const [],
    required this.sequenceTime,
  });

  @override
  Future<RenderFrame> execute(RenderContext context, {RenderFrame? inputFrame}) async {
    if (inputFrame == null) return throw Exception("TransformNode requires an input frame");

    // 1. Evaluate keyframes at sequenceTime
    final evaluatedTransform = _evaluateKeyframes(baseTransform, keyframes, sequenceTime);

    // 2. Transform Order: Anchor -> Scale -> Rotation -> Translation -> Crop -> Flip / Mirror -> Opacity
    // Here we would construct the matrix or shader parameters for the GPU pipeline.

    // 3. Coordinate Space: Ensure we respect the sequence vs source aspect ratios.
    // Normalized space or pixel space coordinates must be applied here.

    // Return the mathematically transformed frame (mocked for architectural representation)
    return inputFrame;
  }

  TransformState _evaluateKeyframes(TransformState base, List<Keyframe> frames, Duration time) {
    if (frames.isEmpty) return base;

    // TODO: Implement actual keyframe interpolation based on supported modes 
    // (linear, bezier, hold).
    // Extract interpolated values for position, scale, rotation, opacity, etc.

    return base;
  }
  
  @override
  void dispose() {
    // Cleanup any native buffers or textures
  }
}
