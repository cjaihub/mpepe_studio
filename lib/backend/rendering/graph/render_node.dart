import 'dart:async';
import '../models/render_frame.dart';
import '../models/render_context.dart';

abstract class RenderNode {
  final String id;
  
  RenderNode({required this.id});

  /// Executes this node's rendering logic, taking an optional input frame from the previous node.
  Future<RenderFrame> execute(RenderContext context, {RenderFrame? inputFrame});
  
  void dispose();
}
