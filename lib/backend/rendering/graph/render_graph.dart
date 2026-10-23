import 'dart:async';
import 'render_node.dart';
import '../models/render_context.dart';
import '../models/render_frame.dart';

class RenderGraph {
  final List<RenderNode> _nodes = [];
  
  void addNode(RenderNode node) {
    _nodes.add(node);
  }
  
  void clear() {
    _nodes.clear();
  }

  Future<RenderFrame?> execute(RenderContext context) async {
    RenderFrame? currentFrame;
    
    for (final node in _nodes) {
      currentFrame = await node.execute(context, inputFrame: currentFrame);
    }
    
    return currentFrame;
  }
  
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    _nodes.clear();
  }
}
