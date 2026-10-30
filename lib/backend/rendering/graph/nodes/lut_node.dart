import 'dart:async';
import '../render_node.dart';
import '../../models/render_frame.dart';
import '../../models/render_context.dart';
import '../../../projects/models/pro_project_models.dart';
import '../../../../looks/engine/look_shader_view.dart';
import '../../../../looks/models/oneova_look.dart';

/// Applies 1D or 3D Lookup Tables (LUTs) to a frame using the GPU Look Engine.
class LutNode extends RenderNode {
  final LutStage lutStage;
  final RenderFrame? matte;

  LutNode({
    required super.id,
    required this.lutStage,
    this.matte,
  });

  @override
  Future<RenderFrame> execute(RenderContext context, {RenderFrame? inputFrame}) async {
    if (inputFrame == null) throw Exception("LutNode requires an input frame");
    if (!lutStage.isEnabled || lutStage.path.isEmpty) return inputFrame;

    final image = inputFrame.image;
    if (image == null) return inputFrame;

    final look = OneovaLook(
      id: 'node_lut_${lutStage.id}',
      name: lutStage.name.isNotEmpty ? lutStage.name : 'LUT',
      intensity: lutStage.intensity.clamp(0.0, 1.0),
      lutStack: [
        LutItem(
          id: lutStage.id,
          name: lutStage.name,
          pathOrUrl: lutStage.path,
          intensity: lutStage.intensity.clamp(0.0, 1.0),
        ),
      ],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final gradedImage = await LookImageRenderer.renderGradedImage(
      inputImage: image,
      look: look,
    );

    return RenderFrame(
      image: gradedImage,
      width: inputFrame.width,
      height: inputFrame.height,
      timestamp: inputFrame.timestamp,
    );
  }

  @override
  void dispose() {
    // Resources freed
  }
}
