import 'dart:async';
import 'package:flutter/rendering.dart'; // For BlendMode
import '../render_node.dart';
import '../../models/render_frame.dart';
import '../../models/render_context.dart';

class CompositingNode extends RenderNode {
  final List<RenderFrame> layerFrames;
  final BlendMode blendMode;
  final double opacity;
  
  CompositingNode({
    required super.id,
    required this.layerFrames,
    this.blendMode = BlendMode.srcOver,
    this.opacity = 1.0,
  });
  
  @override
  Future<RenderFrame> execute(RenderContext context, {RenderFrame? inputFrame}) async {
    // If there is a base frame to composite onto, use it, otherwise create an empty frame
    // This node takes multiple frames and blends them according to ONEROVA layer order:
    // Background -> Tracks -> Graphics -> Text -> Adjustment Layers
    
    // In a real GPU-accelerated implementation, this would compile a shader
    // or draw to an offscreen texture using Canvas/OpenGL/Metal.
    // We mock the interface but enforce the API structure here.
    
    // The final frame is computed by iterating and blending
    // For now we just return the input or first layer as a placeholder for the architecture.
    final finalFrame = inputFrame ?? (layerFrames.isNotEmpty ? layerFrames.first : throw Exception("No frames to composite"));
    
    return finalFrame;
  }
  
  @override
  void dispose() {
    // Cleanup layer frames or textures
  }
}
