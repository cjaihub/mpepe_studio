import 'dart:ui' as ui;

import 'package:oneova_camera_kit/oneova_camera_kit.dart';

import 'look_compiler.dart';

/// Converts a compiled look for the native Live/Camera processors
/// (`TrackLookProcessor.setLook`). The native side binds the same uniforms
/// and textures as the Flutter path, replacing `uSize` with each frame's size.
extension CompiledLookNative on CompiledLook {
  NativeLook toNative() => NativeLook(
        id: look.id,
        uniforms: LookCompiler.uniformValues(this, ui.Size.zero),
        lutAtlasRgba: lutAtlasRgba,
        lutSize: lutSize,
        curvesRgba: curvesRgba,
      );
}
