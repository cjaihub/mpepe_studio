import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/looks/engine/look_compiler.dart';
import 'package:oneova/looks/engine/native_look.dart';
import 'package:oneova/looks/models/look_param_ranges.dart';
import 'package:oneova/looks/models/oneova_look.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  OneovaLook look() => OneovaLook(
        id: 'native-1',
        name: 'n',
        intensity: 0.8,
        primary: const LookPrimary(exposure: 0.5, contrast: 1.2),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  test('uniformValues follows look_engine.frag declaration order', () async {
    final compiled = await LookCompiler.compile(look());
    final v = LookCompiler.uniformValues(compiled, const ui.Size(640, 480));
    // 61 floats: the count the generated native shaders expect.
    expect(v, hasLength(61));
    expect(v[0], 640); // uSize.x
    expect(v[1], 480); // uSize.y
    expect(v[2], closeTo(0.8, 1e-6)); // uMasterIntensity
    expect(v[3], closeTo(0.5, 1e-6)); // uExposure
    expect(v[4], closeTo(1.2, 1e-6)); // uContrast
    expect(v[34], compiled.lutSize.toDouble()); // uLutSize
  });

  test('toNative carries the exact textures the Flutter path binds', () async {
    final compiled = await LookCompiler.compile(look());
    final native = compiled.toNative();
    expect(native.id, 'native-1');
    expect(native.uniforms, hasLength(61));
    expect(native.lutSize, compiled.lutSize);
    expect(native.lutAtlasRgba.length, compiled.lutSize * compiled.lutSize * compiled.lutSize * 4);
    expect(native.curvesRgba.length, 256 * 2 * 4);
    expect(native.lutAtlasRgba.length, compiled.lutAtlas.width * compiled.lutAtlas.height * 4);
  });

  test('realtime budget reads crossFadeMs from Remote Config JSON', () {
    expect(const LookRealtimeBudget().crossFadeMs, 300);
    expect(LookRealtimeBudget.fromJsonString('{"crossFadeMs": 150}').crossFadeMs, 150);
    expect(LookRealtimeBudget.fromJsonString('not json').crossFadeMs, 300);
  });
}
