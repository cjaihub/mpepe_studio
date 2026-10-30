// Writes reference renders of 20 looks through the Flutter path so the
// native Metal path can be compared against them (ΔE2000):
//
//   ONEOVA_PARITY_OUT=/tmp/parity flutter test test/looks/native_parity_fixtures_test.dart
//   packages/oneova_camera_kit/tool/metal_parity/run.sh /tmp/parity
//
// Without ONEOVA_PARITY_OUT the test only checks that every look renders.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/looks/engine/cube_lut.dart';
import 'package:oneova/looks/engine/look_compiler.dart';
import 'package:oneova/looks/engine/look_shader_view.dart';
import 'package:oneova/looks/engine/native_look.dart';
import 'package:oneova/looks/models/oneova_look.dart';

const _w = 96, _h = 64;

/// Hue sweep across, value ramp down, with a neutral gray band on top.
Uint8List _pattern() {
  final px = Uint8List(_w * _h * 4);
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      final i = (y * _w + x) * 4;
      double r, g, b;
      if (y < 8) {
        r = g = b = x / (_w - 1);
      } else {
        final h = x / _w * 6.0;
        final v = 1.0 - (y - 8) / (_h - 8) * 0.9;
        final s = 0.85;
        final c = v * s, xx = c * (1 - ((h % 2) - 1).abs()), m = v - c;
        final (rr, gg, bb) = switch (h.floor()) {
          0 => (c, xx, 0.0),
          1 => (xx, c, 0.0),
          2 => (0.0, c, xx),
          3 => (0.0, xx, c),
          4 => (xx, 0.0, c),
          _ => (c, 0.0, xx),
        };
        r = rr + m;
        g = gg + m;
        b = bb + m;
      }
      px[i] = (r * 255).round();
      px[i + 1] = (g * 255).round();
      px[i + 2] = (b * 255).round();
      px[i + 3] = 255;
    }
  }
  return px;
}

String _cube(int n, List<double> Function(double r, double g, double b) f) {
  final sb = StringBuffer('LUT_3D_SIZE $n\n');
  for (var b = 0; b < n; b++) {
    for (var g = 0; g < n; g++) {
      for (var r = 0; r < n; r++) {
        final o = f(r / (n - 1), g / (n - 1), b / (n - 1));
        sb.writeln('${o[0]} ${o[1]} ${o[2]}');
      }
    }
  }
  return sb.toString();
}

Map<String, OneovaLook> _looks(String tealOrange, String bleach) {
  OneovaLook l(
    String id, {
    double intensity = 1,
    LookPrimary primary = const LookPrimary(),
    LookColor color = const LookColor(),
    LookWheels wheels = const LookWheels(),
    LookCurves curves = const LookCurves(),
    LookHsl hsl = const LookHsl(),
    List<LutItem> luts = const [],
    LookFilm film = const LookFilm(),
    LookDetail detail = const LookDetail(),
    LookOptics optics = const LookOptics(),
  }) =>
      OneovaLook(
        id: id,
        name: id,
        intensity: intensity,
        primary: primary,
        color: color,
        wheels: wheels,
        curves: curves,
        hsl: hsl,
        lutStack: luts,
        film: film,
        detail: detail,
        optics: optics,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
  final scurve = const LookCurves(master: [
    CurvePoint(0, 0),
    CurvePoint(0.25, 0.18),
    CurvePoint(0.75, 0.84),
    CurvePoint(1, 1),
  ]);
  return {
    for (final look in [
      l('neutral'),
      l('exposure_up', primary: const LookPrimary(exposure: 0.7)),
      l('exposure_down', primary: const LookPrimary(exposure: -0.8)),
      l('contrast', primary: const LookPrimary(contrast: 1.4, pivot: 0.45)),
      l('highlights_shadows', primary: const LookPrimary(highlights: -0.6, shadows: 0.5)),
      l('whites_blacks', primary: const LookPrimary(whites: 0.7, blacks: -0.6)),
      l('warm_tint', color: const LookColor(temperature: 40, tint: -20)),
      l('vibrance_sat', color: const LookColor(vibrance: 0.5, saturation: 1.3)),
      l('desaturate', color: const LookColor(saturation: 0.4)),
      l('wheels', wheels: const LookWheels(
        lift: ColorWheel(b: 0.06),
        gamma: ColorWheel(r: 0.08, lum: -0.05),
        gain: ColorWheel(r: 0.05, g: 0.02),
        offset: ColorWheel(g: -0.02),
      )),
      l('s_curve', curves: scurve),
      l('rgb_curves', curves: const LookCurves(
        red: [CurvePoint(0, 0.05), CurvePoint(1, 0.95)],
        blue: [CurvePoint(0, 0), CurvePoint(0.5, 0.42), CurvePoint(1, 1)],
      )),
      l('hsl', hsl: const LookHsl(
        orange: HslBand(hue: -8, sat: 0.2),
        green: HslBand(hue: 25, sat: -0.5, lum: -0.3),
        blue: HslBand(hue: -15, sat: 0.3, lum: 0.2),
      )),
      l('lut_teal_orange', luts: [LutItem(id: 'to', name: 'to', pathOrUrl: tealOrange, size: 17)]),
      l('lut_half', luts: [LutItem(id: 'bb', name: 'bb', pathOrUrl: bleach, size: 9, intensity: 0.5)]),
      l('lut_stack', luts: [
        LutItem(id: 'to', name: 'to', pathOrUrl: tealOrange, size: 17, intensity: 0.7),
        LutItem(id: 'bb', name: 'bb', pathOrUrl: bleach, size: 9, intensity: 0.6),
      ]),
      l('fade_vignette', film: const LookFilm(fade: 0.5), optics: const LookOptics(vignette: 0.6)),
      l('grain', film: const LookFilm(grain: 0.5)),
      l('sharpen', detail: const LookDetail(sharpen: 0.7)),
      l('cinematic_mix',
          intensity: 0.75,
          primary: const LookPrimary(exposure: 0.2, contrast: 1.15, shadows: 0.2),
          color: const LookColor(temperature: -15, vibrance: 0.2),
          curves: scurve,
          luts: [LutItem(id: 'to', name: 'to', pathOrUrl: tealOrange, size: 17, intensity: 0.8)],
          optics: const LookOptics(vignette: 0.3)),
    ])
      look.id: look,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('20 reference looks render through the Flutter path', () async {
    final tmp = Directory.systemTemp.createTempSync('oneova_parity_luts');
    final tealOrange = File('${tmp.path}/teal_orange.cube')
      ..writeAsStringSync(_cube(17, (r, g, b) {
        final l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        return [
          (r + (l - 0.5) * 0.15).clamp(0.0, 1.0),
          g,
          (b - (l - 0.5) * 0.2 + 0.03).clamp(0.0, 1.0),
        ];
      }));
    final bleach = File('${tmp.path}/bleach.cube')
      ..writeAsStringSync(_cube(9, (r, g, b) {
        final l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        final c = (l - 0.5) * 1.3 + 0.5;
        return [math.max(0.0, (r + c) / 2), math.max(0.0, (g + c) / 2), math.max(0.0, (b + c) / 2)];
      }));

    final looks = _looks(tealOrange.path, bleach.path);
    expect(looks, hasLength(20));
    final pattern = _pattern();
    final input = await decodeRgbaImage(pattern, _w, _h);
    final outRoot = Platform.environment['ONEOVA_PARITY_OUT'];

    for (final MapEntry(key: name, value: look) in looks.entries) {
      final graded = await LookImageRenderer.renderGradedImage(inputImage: input, look: look);
      final bytes = (await graded.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
      expect(bytes.lengthInBytes, _w * _h * 4, reason: name);
      if (outRoot == null) continue;

      final native = (await LookCompiler.compile(look)).toNative();
      final dir = Directory('$outRoot/$name')..createSync(recursive: true);
      File('${dir.path}/input.rgba').writeAsBytesSync(pattern);
      File('${dir.path}/expected.rgba').writeAsBytesSync(bytes.buffer.asUint8List());
      File('${dir.path}/uniforms.f32').writeAsBytesSync(native.uniforms.buffer.asUint8List());
      File('${dir.path}/lut.rgba').writeAsBytesSync(native.lutAtlasRgba);
      File('${dir.path}/curves.rgba').writeAsBytesSync(native.curvesRgba);
      File('${dir.path}/meta.json')
          .writeAsStringSync(jsonEncode({'width': _w, 'height': _h, 'lutSize': native.lutSize}));
    }
    tmp.deleteSync(recursive: true);
  });
}
