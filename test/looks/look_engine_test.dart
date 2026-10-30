import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/photo_studio/photo_studio_models.dart';
import 'package:oneova/looks/adapters/legacy_look_adapters.dart';
import 'package:oneova/looks/engine/cube_lut.dart';
import 'package:oneova/looks/engine/curve_baker.dart';
import 'package:oneova/looks/engine/look_compiler.dart';
import 'package:oneova/looks/engine/look_shader_view.dart';
import 'package:oneova/looks/engine/pixel_sampler.dart';
import 'package:oneova/looks/models/look_param_ranges.dart';
import 'package:oneova/looks/models/oneova_look.dart';

String _cube(int n, List<double> Function(double r, double g, double b) f, {String header = ''}) {
  final sb = StringBuffer('TITLE "test"\n$header LUT_3D_SIZE $n\n');
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

OneovaLook _look({
  LookPrimary primary = const LookPrimary(),
  List<LutItem> luts = const [],
  LookCurves curves = const LookCurves(),
  LookHsl hsl = const LookHsl(),
}) =>
    OneovaLook(
      id: 't',
      name: 't',
      primary: primary,
      lutStack: luts,
      curves: curves,
      hsl: hsl,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Future<ui.Image> _solid(int r, int g, int b, {int w = 8, int h = 8}) {
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < px.length; i += 4) {
    px[i] = r;
    px[i + 1] = g;
    px[i + 2] = b;
    px[i + 3] = 255;
  }
  return decodeRgbaImage(px, w, h);
}

Future<List<int>> _centerPixel(ui.Image img) async {
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
  final i = ((img.height ~/ 2) * img.width + img.width ~/ 2) * 4;
  return [data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2)];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CubeLut', () {
    test('parses size, domain and rows', () {
      final lut = CubeLut.parse(_cube(3, (r, g, b) => [r * 2, g * 2, b * 2],
          header: 'DOMAIN_MIN 0 0 0\nDOMAIN_MAX 2 2 2\n'));
      expect(lut.size, 3);
      final (r, g, b) = lut.sample(0.25, 0.5, 0.75);
      expect(r, closeTo(0.25, 1e-6));
      expect(g, closeTo(0.5, 1e-6));
      expect(b, closeTo(0.75, 1e-6));
    });

    test('rejects truncated files and 1D LUTs', () {
      expect(() => CubeLut.parse('LUT_3D_SIZE 2\n0 0 0\n'), throwsFormatException);
      expect(() => CubeLut.parse('LUT_1D_SIZE 4\n'), throwsFormatException);
    });

    test('identity is exact under trilinear sampling', () {
      final (r, g, b) = CubeLut.identity().sample(0.1, 0.6, 0.9);
      expect([r, g, b], [closeTo(0.1, 1e-6), closeTo(0.6, 1e-6), closeTo(0.9, 1e-6)]);
    });

    test('compose applies stack in order with intensity', () {
      final invert = CubeLut.parse(_cube(5, (r, g, b) => [1 - r, 1 - g, 1 - b]));
      final both = CubeLut.compose([(invert, 1.0), (invert, 1.0)], size: 5);
      expect(both.sample(0.3, 0.3, 0.3).$1, closeTo(0.3, 1e-6));
      final half = CubeLut.compose([(invert, 0.5)], size: 5);
      expect(half.sample(0.2, 0.2, 0.2).$1, closeTo(0.5, 1e-6));
    });

    test('atlas layout: x = b·N + r, y = g', () {
      final lut = CubeLut.parse(_cube(2, (r, g, b) => [r, g, b]));
      final px = lut.toAtlasRgba();
      // r=1, g=0, b=1 → x = 1·2 + 1 = 3, y = 0
      expect(px.sublist(3 * 4, 3 * 4 + 4), [255, 0, 255, 255]);
      // r=0, g=1, b=0 → x = 0, y = 1 (row width 4)
      expect(px.sublist(4 * 4, 4 * 4 + 4), [0, 255, 0, 255]);
    });
  });

  group('CurveBaker', () {
    test('identity curve maps i → i', () {
      final v = CurveBaker.evaluate(const [CurvePoint(0, 0), CurvePoint(1, 1)]);
      expect(v[0], 0);
      expect(v[128], closeTo(128 / 255, 1e-9));
      expect(v[255], 1);
    });

    test('monotone: an S-curve never overshoots or reverses', () {
      final v = CurveBaker.evaluate(const [
        CurvePoint(0, 0),
        CurvePoint(0.25, 0.15),
        CurvePoint(0.75, 0.85),
        CurvePoint(1, 1),
      ]);
      for (var i = 1; i < v.length; i++) {
        expect(v[i], greaterThanOrEqualTo(v[i - 1]));
      }
      expect(v[64], closeTo(0.15, 0.01));
    });
  });

  group('PixelSampler', () {
    test('neutral gray reads as D65 with unit gains', () {
      final wb = PixelSampler.whiteBalanceFor((r: 0.5, g: 0.5, b: 0.5));
      expect(wb['temperature']!, closeTo(6504, 30));
      // D65 sits 0.0032 Duv above the Planckian locus.
      expect(wb['tint']!, closeTo(3.2, 0.3));
      expect(wb['rGain']!, closeTo(1, 0.01));
      expect(wb['bGain']!, closeTo(1, 0.01));
    });

    test('a warm sample reads as a lower CCT and needs more blue', () {
      final wb = PixelSampler.whiteBalanceFor((r: 0.8, g: 0.6, b: 0.4));
      expect(wb['temperature']!, lessThan(4500));
      expect(wb['bGain']!, greaterThan(wb['rGain']!));
    });

    test('HSL of pure colors', () {
      expect(PixelSampler.toHsl((r: 1, g: 0, b: 0)).hue, 0);
      expect(PixelSampler.toHsl((r: 0, g: 1, b: 0)).hue, 120);
      expect(PixelSampler.toHsl((r: 0, g: 0, b: 1)).hue, 240);
      expect(PixelSampler.toHsl((r: 0.5, g: 0.5, b: 0.5)).saturation, 0);
    });

    test('averageRgba weights by alpha', () {
      final avg = PixelSampler.averageRgba(Uint8List.fromList([255, 0, 0, 255, 0, 0, 255, 0]));
      expect(avg.r, 1);
      expect(avg.b, 0);
    });
  });

  group('LookParamRanges', () {
    test('flags and clamps out-of-range values', () {
      final bad = _look(primary: const LookPrimary(exposure: 5, contrast: 0.1));
      expect(bad.validate(), hasLength(2));
      final fixed = bad.clampedTo();
      expect(fixed.validate(), isEmpty);
      expect(fixed.primary.exposure, 2);
    });

    test('Remote Config JSON overrides only the given keys', () {
      final r = LookParamRanges.fromJsonString('{"primary.exposure": [-4, 4]}');
      expect(r['primary.exposure'].max, 4);
      expect(r['primary.contrast'].max, 2);
      expect(LookParamRanges.fromJsonString('not json')['primary.exposure'].max, 2);
    });

    test('realtime budget limits LUT stack and size', () {
      final luts = [
        for (var i = 0; i < 3; i++) LutItem(id: '$i', name: '$i', pathOrUrl: 'x', size: 33),
      ];
      expect(_look(luts: luts).isRealtimeCompatibleWith(const LookRealtimeBudget(maxLutStack: 2)), isFalse);
      expect(_look(luts: luts).isRealtimeCompatible, isTrue);
      expect(
        _look(luts: [const LutItem(id: 'a', name: 'a', pathOrUrl: 'x', size: 65)]).isRealtimeCompatible,
        isFalse,
      );
    });
  });

  group('EditGraph adapter', () {
    test('maps sliders, wheels, HSL and curves', () {
      final graph = EditGraph(layers: [
        PhotoLayer(id: 'g', name: 'Global', adjustments: [
          PhotoAdjustment(id: 'e', type: AdjustmentType.EXPOSURE, parameters: {'value': 0.5}),
          PhotoAdjustment(id: 's', type: AdjustmentType.SATURATION, parameters: {'value': -0.5}),
          PhotoAdjustment(id: 't', type: AdjustmentType.TEMPERATURE, parameters: {'value': 0.2}),
          PhotoAdjustment(
              id: 'w',
              type: AdjustmentType.COLOR_WHEELS_SHADOWS,
              parameters: {'hue': 0.0, 'saturation': 1.0, 'luminance': 0.0}),
          PhotoAdjustment(
              id: 'h',
              type: AdjustmentType.HSL,
              parameters: {'channel': 'cyan', 'hue': 100, 'saturation': -50, 'luminance': 0}),
          PhotoAdjustment(id: 'c', type: AdjustmentType.CURVES_RGB, parameters: {
            'points': [
              [0.0, 0.1],
              [1.0, 0.9],
            ]
          }),
        ]),
      ]);
      final look = LegacyLookAdapters.fromEditGraph(graph);
      expect(look.primary.exposure, 0.5);
      expect(look.color.saturation, 0.5);
      expect(look.color.temperature, closeTo(20, 1e-9));
      expect(look.wheels.lift.r, closeTo(0.25, 1e-9));
      expect(look.hsl.aqua.hue, 30);
      expect(look.hsl.aqua.sat, -0.5);
      expect(look.curves.master.first.y, 0.1);
      expect(look.validate(), isEmpty);
    });
  });

  group('GPU look engine (shader)', () {
    setUp(LookCompiler.clearCache);

    testWidgets('neutral look leaves pixels unchanged', (tester) async {
      await tester.runAsync(() async {
        final src = await _solid(120, 60, 200);
        final out = await LookImageRenderer.renderGradedImage(inputImage: src, look: _look());
        final px = await _centerPixel(out);
        for (var c = 0; c < 3; c++) {
          expect((px[c] - [120, 60, 200][c]).abs(), lessThanOrEqualTo(1), reason: 'channel $c: $px');
        }
      });
    });

    testWidgets('exposure +1 EV doubles linear values', (tester) async {
      await tester.runAsync(() async {
        final src = await _solid(50, 50, 50);
        final out = await LookImageRenderer.renderGradedImage(
            inputImage: src, look: _look(primary: const LookPrimary(exposure: 1)));
        expect((await _centerPixel(out))[0], closeTo(100, 2));
      });
    });

    testWidgets('a LUT from a file is applied (invert)', (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('lut');
        final f = File('${dir.path}/invert.cube')
          ..writeAsStringSync(_cube(17, (r, g, b) => [1 - r, 1 - g, 1 - b]));
        final src = await _solid(40, 128, 220);
        final out = await LookImageRenderer.renderGradedImage(
          inputImage: src,
          look: _look(luts: [LutItem(id: 'inv', name: 'Invert', pathOrUrl: f.path, size: 17)]),
        );
        final px = await _centerPixel(out);
        expect(px[0], closeTo(215, 2));
        expect(px[1], closeTo(127, 2));
        expect(px[2], closeTo(35, 2));
        await dir.delete(recursive: true);
      });
    });

    testWidgets('master curve is applied', (tester) async {
      await tester.runAsync(() async {
        final src = await _solid(128, 128, 128);
        final out = await LookImageRenderer.renderGradedImage(
          inputImage: src,
          look: _look(curves: const LookCurves(master: [CurvePoint(0, 0.2), CurvePoint(1, 1)])),
        );
        // y = 0.2 + 0.8·x → 0.2 + 0.8·0.502 ≈ 0.602 → 153
        expect((await _centerPixel(out))[0], closeTo(153, 2));
      });
    });

    testWidgets('HSL saturation only affects its band', (tester) async {
      await tester.runAsync(() async {
        final look = _look(hsl: const LookHsl(blue: HslBand(sat: -1)));
        final blue = await _centerPixel(
            await LookImageRenderer.renderGradedImage(inputImage: await _solid(30, 30, 220), look: look));
        expect((blue[0] - blue[2]).abs(), lessThan(10), reason: 'blue desaturated: $blue');
        final red = await _centerPixel(
            await LookImageRenderer.renderGradedImage(inputImage: await _solid(220, 40, 30), look: look));
        expect(red[0], closeTo(220, 2));
        expect(red[1], closeTo(40, 2));
      });
    });
  });
}
