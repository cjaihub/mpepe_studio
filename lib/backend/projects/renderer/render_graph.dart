import 'render_context.dart';
import 'render_models.dart';
import '../models/pro_project_models.dart';
import '../models/effect_models.dart';
import '../../mask_engine/universal_mask_models.dart';

abstract class RenderNode {
  Future<RenderFrame?> execute(RenderContext context, RenderFrame? input);
}

class RenderGraph {
  final List<RenderNode> nodes;

  RenderGraph(this.nodes);

  Future<RenderFrame?> execute(RenderContext context, [RenderFrame? initialFrame]) async {
    RenderFrame? currentFrame = initialFrame ?? context.initialFrame;
    for (var node in nodes) {
      currentFrame = await node.execute(context, currentFrame);
    }
    return currentFrame;
  }
}

// =======================================================
// RENDERER PIPELINE STAGES - SUPPORTED MODEL RENDERER PENDING
// =======================================================

class DecodeNode implements RenderNode {
  final ClipRenderContext clipContext;
  final bool useProxy;

  DecodeNode(this.clipContext, {this.useProxy = true});

  @override
  Future<RenderFrame?> execute(RenderContext context, RenderFrame? input) async {
    // Decode the frame for clipContext.clip at clipContext.sourceTime
    // This node generates new pixels, so it typically ignores `input` unless it's a generator.
    return input; // Returning input as a stub for the MVP
  }
}

class InputTransformNode implements RenderNode {
  @override
  Future<RenderFrame?> execute(RenderContext context, RenderFrame? input) async {
    // Map to unified color space (e.g. ACES or linear)
    return input;
  }
}

class SpatialTransformNode implements RenderNode {
  final TransformState transform;
  SpatialTransformNode(this.transform);

  @override
  Future<RenderFrame?> execute(RenderContext context, RenderFrame? input) async {
    // Apply scale, position, rotation, anchor, crop
    return input;
  }
}

class MaskingNode implements RenderNode {
  final UniversalMask mask;
  MaskingNode(this.mask);

  @override
  Future<RenderFrame?> execute(RenderContext context, RenderFrame? input) async {
    // Execute mask generation (Subject, Depth, Luma, etc.)
    return input;
  }
}

class PrimaryColorNode implements RenderNode {
  final ColorState color;
  PrimaryColorNode(this.color);

  @override
  Future<RenderFrame?> execute(RenderContext context, RenderFrame? input) async {
    // Execute exposure, contrast, temperature, tint, shadows, highlights
    return input;
  }
}

class SecondaryColorNode implements RenderNode {
  final List<ColorState> secondaryColors;
  SecondaryColorNode(this.secondaryColors);

  @override
  Future<RenderFrame?> execute(RenderContext context, RenderFrame? input) async {
    // Apply masked secondary grades
    return input;
  }
}

class LutNode implements RenderNode {
  final String? lutId;
  final double intensity;
  LutNode({this.lutId, this.intensity = 1.0});

  @override
  Future<RenderFrame?> execute(RenderContext context, RenderFrame? input) async {
    if (lutId == null) return input;
    // Apply 3D LUT transformation
    return input;
  }
}

class EffectStackNode implements RenderNode {
  final List<EffectState> effects;
  EffectStackNode(this.effects);

  @override
  Future<RenderFrame?> execute(RenderContext context, RenderFrame? input) async {
    // Delegate to EffectGraph or execute specific renderer node per effect
    return input;
  }
}

class ClipPipelineNode implements RenderNode {
  final ClipRenderContext clipContext;
  final RenderGraph clipGraph;

  ClipPipelineNode(this.clipContext, this.clipGraph);

  @override
  Future<RenderFrame?> execute(RenderContext context, RenderFrame? accumulator) async {
    // 1. Process this individual clip to generate its isolated frame
    RenderFrame? clipFrame = await clipGraph.execute(context, null);
    
    // 2. Composite (Alpha Blend) this clip's frame OVER the accumulator
    if (accumulator == null) return clipFrame;
    if (clipFrame == null) return accumulator;
    
    // TODO: Perform real alpha blending based on clipContext.clip.opacity and blendMode
    return clipFrame; // MVP assumes topmost clip overwrites completely (opaque)
  }
}

class OutputTransformNode implements RenderNode {
  @override
  Future<RenderFrame?> execute(RenderContext context, RenderFrame? input) async {
    // Transform to target color space (Rec.709, Rec.2020)
    return input;
  }
}
