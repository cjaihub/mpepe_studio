import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova_camera_kit/oneova_camera_kit.dart';

NativeLook _look({int lutSize = 2, int? lutBytes, int curveBytes = 256 * 2 * 4}) => NativeLook(
      id: 'l1',
      uniforms: Float32List(61),
      lutAtlasRgba: Uint8List(lutBytes ?? lutSize * lutSize * lutSize * 4),
      lutSize: lutSize,
      curvesRgba: Uint8List(curveBytes),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('oneova_camera_kit/look_processor');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      if (call.method == 'stats') {
        return {
          'framesGraded': 120,
          'framesPassedThrough': 3,
          'lastPassThroughReason': 'no_look',
          'averageFrameMs': 1.5,
          'p95FrameMs': 2.25,
          'width': 1280,
          'height': 720,
          'lookId': 'l1',
        };
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  group('NativeLook', () {
    test('accepts consistent texture sizes', () {
      expect(_look(lutSize: 33).lutSize, 33);
    });

    test('rejects a LUT atlas of the wrong size', () {
      expect(() => _look(lutSize: 17, lutBytes: 100), throwsArgumentError);
      expect(() => _look(lutSize: 1), throwsArgumentError);
    });

    test('rejects a curve texture of the wrong size', () {
      expect(() => _look(curveBytes: 256 * 4), throwsArgumentError);
    });
  });

  group('TrackLookProcessor', () {
    test('sends attach, setLook, stats and detach for its track', () async {
      final p = await TrackLookProcessor.attach('track-1', maxInFlightFrames: 3);
      final look = _look();
      await p.setLook(look, crossFade: const Duration(milliseconds: 300));
      final stats = await p.stats();
      await p.setLook(null, crossFade: Duration.zero);
      await p.detach();

      expect(calls.map((c) => c.method), ['attach', 'setLook', 'stats', 'setLook', 'detach']);
      expect(calls[0].arguments, {'trackId': 'track-1', 'maxInFlightFrames': 3});
      final setArgs = calls[1].arguments as Map;
      expect(setArgs['trackId'], 'track-1');
      expect(setArgs['crossFadeMs'], 300);
      expect((setArgs['look'] as Map)['id'], 'l1');
      expect((setArgs['look'] as Map)['uniforms'], isA<Float32List>());
      expect((calls[3].arguments as Map)['look'], isNull);

      expect(stats.framesGraded, 120);
      expect(stats.framesPassedThrough, 3);
      expect(stats.lastPassThroughReason, 'no_look');
      expect(stats.p95FrameMs, 2.25);
      expect(stats.width, 1280);
      expect(stats.lookId, 'l1');
    });

    test('refuses calls after detach', () async {
      final p = await TrackLookProcessor.attach('track-2');
      await p.detach();
      expect(p.isAttached, isFalse);
      expect(() => p.setLook(null, crossFade: Duration.zero), throwsStateError);
      await p.detach();
      expect(calls.where((c) => c.method == 'detach'), hasLength(1));
    });
  });

  group('generated native shaders', () {
    final inPackage = Directory.current.path.endsWith('oneova_camera_kit');
    final pkg = inPackage ? Directory.current.path : '${Directory.current.path}/packages/oneova_camera_kit';
    final repoRoot = inPackage ? '${Directory.current.path}/../..' : Directory.current.path;
    final source = File('$repoRoot/shaders/look_engine.frag');
    final hash = shaderSourceHash(source.readAsBytesSync());

    test('are up to date with shaders/look_engine.frag (run tool/generate_shaders.dart)', () {
      final kotlin =
          File('$pkg/android/src/main/kotlin/com/oneova/camerakit/LookEngineShader.kt').readAsStringSync();
      final swift = File('$pkg/ios/Classes/LookEngineShader.swift').readAsStringSync();
      expect(kotlin, contains('SOURCE_HASH = "$hash"'));
      expect(swift, contains('sourceHash = "$hash"'));
    });

    test('declare the 61 floats LookCompiler sends', () {
      final kotlin =
          File('$pkg/android/src/main/kotlin/com/oneova/camerakit/LookEngineShader.kt').readAsStringSync();
      expect(kotlin, contains('FLOAT_COUNT = 61'));
    });
  });

  test('shaderSourceHash is FNV-1a 64', () {
    // Reference values of the 64-bit FNV-1a function.
    expect(shaderSourceHash(const []), 'cbf29ce484222325');
    expect(shaderSourceHash('a'.codeUnits), 'af63dc4c8601ec8c');
    expect(shaderSourceHash('foobar'.codeUnits), '85944171f73967e8');
  });
}
