import 'effect_models.dart';
import 'keyframe_models.dart';
import '../../mask_engine/universal_mask_models.dart';

/// Represents a node in the effect processing chain.
class EffectNode {
  final EffectState state;
  final UniversalMask? activeMask;

  EffectNode({
    required this.state,
    this.activeMask,
  });
}

/// Manages the processing chain of effects for a single frame or context.
class EffectGraph {
  final List<EffectNode> _nodes = [];
  
  void buildFromClip(dynamic clip, List<UniversalMask> allMasks) {
    _nodes.clear();
    
    // Sort by order
    final sortedEffects = List<EffectState>.from(clip.effects)
      ..sort((a, b) => a.order.compareTo(b.order));
      
    for (final effect in sortedEffects) {
      if (!effect.enabled) continue;
      
      UniversalMask? mask;
      if (effect.maskId != null) {
        try {
          mask = allMasks.firstWhere((m) => m.id == effect.maskId);
        } catch (_) {
          // Mask not found
        }
      }
      
      _nodes.add(EffectNode(state: effect, activeMask: mask));
    }
  }

  /// Processes the effect graph using a generalized renderer context.
  /// Note: The actual rendering is delegated to the specific rendering engine 
  /// (e.g. Canvas, Shaders, FFMPEG), this just orchestrates the pipeline.
  void process(EffectRendererContext context) {
    for (final node in _nodes) {
      context.applyEffect(node);
    }
  }

  List<EffectNode> get activeNodes => List.unmodifiable(_nodes);
}

/// Abstract context that any renderer (Flutter Canvas, WebGL, FFmpeg) must implement
/// to support the EffectGraph.
abstract class EffectRendererContext {
  /// Applies a single effect node to the current render target.
  void applyEffect(EffectNode node);
  
  /// Gets the current frame time being rendered.
  double get currentFrameTime;
  
  /// Resolves a keyframed property value at the current frame time.
  double resolveKeyframedValue(String propertyId, double defaultValue, List<Keyframe> keyframes);
}
