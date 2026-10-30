import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova_camera_kit/oneova_camera_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('oneova_camera_kit/device');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'probeHardwareCapabilities') {
        return {
          'model': 'Pixel 8 Pro',
          'manufacturer': 'Google',
          'device': 'husky',
          'hardware': 'husky',
          'board': 'husky',
          'socModel': 'Google Tensor G3',
          'osVersion': '14',
          'sdkInt': 34,
          'hardwareTier': 'high',
          'memory': {
            'totalRamBytes': 12 * 1024 * 1024 * 1024,
            'availRamBytes': 8 * 1024 * 1024 * 1024,
            'lowMemory': false,
            'thresholdBytes': 1024 * 1024 * 1024,
          },
          'cameras': [
            {
              'id': '0',
              'facing': 'back',
              'resolutions': [
                {'width': 3840, 'height': 2160},
                {'width': 1920, 'height': 1080},
              ],
              'maxFps': 60,
              'is10BitSupported': true,
              'isHdrSupported': true,
            },
            {
              'id': '1',
              'facing': 'front',
              'resolutions': [
                {'width': 1920, 'height': 1080},
              ],
              'maxFps': 30,
              'is10BitSupported': false,
              'isHdrSupported': false,
            }
          ],
          'encoders': [
            {
              'name': 'c2.exynos.hevc.encoder',
              'codec': 'video/hevc',
              'isHardwareAccelerated': true,
              'maxWidth': 3840,
              'maxHeight': 2160,
              'maxBitrateBps': 120000000,
              'maxFps': 60,
              'supports10Bit': true,
              'profileLevels': [
                {'profile': 2, 'level': 52}
              ]
            }
          ],
          'gpu': {
            'glEsVersion': 'OpenGL ES 3.2 v1.r44p0',
            'reqGlEsVersion': 0x00030002,
            'hasVulkan': true,
            'hasUnifiedMemory': true,
            'name': 'Mali-G715',
          },
          'thermal': {
            'thermalHeadroom': 0.45,
            'isPowerSaveMode': false,
            'batteryLevel': 85,
            'isCharging': true,
          }
        };
      } else if (call.method == 'getThermalHeadroom') {
        final forecast = (call.arguments as Map?)?['forecastSeconds'] as int? ?? 0;
        return forecast > 0 ? 0.75 : 0.45;
      } else if (call.method == 'getThermalSnapshot') {
        return {
          'headroom': 0.42,
          'forecastHeadroom10s': 0.65,
          'thermalLevel': 'nominal',
          'isPowerSaveMode': false,
          'batteryLevel': 92,
          'isCharging': false,
          'timestamp': 1700000000000,
        };
      } else if (call.method == 'createHintSession') {
        return true;
      } else if (call.method == 'reportActualDuration') {
        return true;
      } else if (call.method == 'closeHintSession') {
        return null;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('DeviceCapabilityProbe', () {
    test('parses probed hardware capabilities correctly', () async {
      final caps = await DeviceCapabilityBridge.probe();
      expect(caps.model, 'Pixel 8 Pro');
      expect(caps.manufacturer, 'Google');
      expect(caps.hardwareTier, 'high');
      expect(caps.totalRamGb, closeTo(12.0, 0.1));
      expect(caps.cameras.length, 2);
      expect(caps.cameras.first.facing, 'back');
      expect(caps.cameras.first.supports4K, isTrue);
      expect(caps.cameras.first.is10BitSupported, isTrue);
      expect(caps.encoders.first.supports10Bit, isTrue);
      expect(caps.encoders.first.supports4K, isTrue);
      expect(caps.supports4KRecording, isTrue);
      expect(caps.supportsHevc10Bit, isTrue);
      expect(caps.gpu.hasVulkan, isTrue);
    });

    test('falls back gracefully when channel throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'UNAVAILABLE');
      });

      final caps = await DeviceCapabilityBridge.probe();
      expect(caps.model, isNotEmpty);
      expect(caps.hardwareTier, 'medium');
      expect(caps.cameras, isNotEmpty);
      expect(caps.encoders, isNotEmpty);
    });
  });

  group('ThermalProbe', () {
    test('gets thermal headroom and forecasts', () async {
      final headroom = await ThermalProbe.getThermalHeadroom(forecastSeconds: 0);
      expect(headroom, closeTo(0.45, 0.01));

      final forecast = await ThermalProbe.getThermalHeadroom(forecastSeconds: 10);
      expect(forecast, closeTo(0.75, 0.01));
    });

    test('gets thermal snapshot with battery info', () async {
      final snap = await ThermalProbe.getThermalSnapshot();
      expect(snap.headroom, closeTo(0.42, 0.01));
      expect(snap.forecastHeadroom10s, closeTo(0.65, 0.01));
      expect(snap.thermalLevel, 'nominal');
      expect(snap.isPowerSaveMode, isFalse);
      expect(snap.batteryLevel, 92);
      expect(snap.isCharging, isFalse);
      expect(snap.isCritical, isFalse);
      expect(snap.isSerious, isFalse);
    });

    test('handles ADPF hint sessions', () async {
      final created = await ThermalProbe.createHintSession(targetDurationNanos: 16666666);
      expect(created, isTrue);

      final reported = await ThermalProbe.reportActualDuration(actualDurationNanos: 12000000);
      expect(reported, isTrue);

      await ThermalProbe.closeHintSession();
      expect(calls.any((c) => c.method == 'closeHintSession'), isTrue);
    });
  });
}
