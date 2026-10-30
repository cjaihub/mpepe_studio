import 'dart:io';
import 'package:flutter/services.dart';

/// Camera resolution pair (width x height).
class CameraResolution {
  final int width;
  final int height;

  const CameraResolution({required this.width, required this.height});

  factory CameraResolution.fromMap(Map<dynamic, dynamic> map) {
    return CameraResolution(
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, int> toMap() => {'width': width, 'height': height};

  @override
  String toString() => '${width}x$height';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraResolution &&
          runtimeType == other.runtimeType &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => width.hashCode ^ height.hashCode;
}

/// Dynamic camera format capabilities probed from native Camera2 / AVFoundation APIs.
class CameraFormatCapability {
  final String id;
  final String facing; // "front", "back", "external", "unknown"
  final List<CameraResolution> resolutions;
  final int maxFps;
  final bool is10BitSupported;
  final bool isHdrSupported;

  const CameraFormatCapability({
    required this.id,
    required this.facing,
    required this.resolutions,
    required this.maxFps,
    required this.is10BitSupported,
    required this.isHdrSupported,
  });

  factory CameraFormatCapability.fromMap(Map<dynamic, dynamic> map) {
    final rawRes = map['resolutions'] as List<dynamic>? ?? const [];
    final resList = rawRes
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => CameraResolution.fromMap(m))
        .toList();

    return CameraFormatCapability(
      id: map['id']?.toString() ?? '',
      facing: map['facing']?.toString() ?? 'unknown',
      resolutions: resList,
      maxFps: (map['maxFps'] as num?)?.toInt() ?? 30,
      is10BitSupported: map['is10BitSupported'] as bool? ?? false,
      isHdrSupported: map['isHdrSupported'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'facing': facing,
        'resolutions': resolutions.map((r) => r.toMap()).toList(),
        'maxFps': maxFps,
        'is10BitSupported': is10BitSupported,
        'isHdrSupported': isHdrSupported,
      };

  bool supportsResolution(int width, int height) {
    return resolutions.any((r) =>
        (r.width == width && r.height == height) ||
        (r.width == height && r.height == width));
  }

  bool get supports4K => resolutions.any((r) =>
      (r.width >= 3840 && r.height >= 2160) ||
      (r.width >= 2160 && r.height >= 3840));

  bool get supports1080p => resolutions.any((r) =>
      (r.width >= 1920 && r.height >= 1080) ||
      (r.width >= 1080 && r.height >= 1920));
}

/// Hardware video encoder profile capabilities probed from MediaCodec / VideoToolbox.
class EncoderProfileCapability {
  final String name;
  final String codec; // e.g. "video/avc", "video/hevc", "video/av01"
  final bool isHardwareAccelerated;
  final int maxWidth;
  final int maxHeight;
  final int maxBitrateBps;
  final int maxFps;
  final bool supports10Bit;
  final List<Map<String, int>> profileLevels;

  const EncoderProfileCapability({
    required this.name,
    required this.codec,
    required this.isHardwareAccelerated,
    required this.maxWidth,
    required this.maxHeight,
    required this.maxBitrateBps,
    required this.maxFps,
    required this.supports10Bit,
    required this.profileLevels,
  });

  factory EncoderProfileCapability.fromMap(Map<dynamic, dynamic> map) {
    final rawPl = map['profileLevels'] as List<dynamic>? ?? const [];
    final plList = rawPl
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => {
              'profile': (m['profile'] as num?)?.toInt() ?? 0,
              'level': (m['level'] as num?)?.toInt() ?? 0,
            })
        .toList();

    return EncoderProfileCapability(
      name: map['name']?.toString() ?? '',
      codec: map['codec']?.toString() ?? '',
      isHardwareAccelerated: map['isHardwareAccelerated'] as bool? ?? false,
      maxWidth: (map['maxWidth'] as num?)?.toInt() ?? 1920,
      maxHeight: (map['maxHeight'] as num?)?.toInt() ?? 1080,
      maxBitrateBps: (map['maxBitrateBps'] as num?)?.toInt() ?? 20000000,
      maxFps: (map['maxFps'] as num?)?.toInt() ?? 30,
      supports10Bit: map['supports10Bit'] as bool? ?? false,
      profileLevels: plList,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'codec': codec,
        'isHardwareAccelerated': isHardwareAccelerated,
        'maxWidth': maxWidth,
        'maxHeight': maxHeight,
        'maxBitrateBps': maxBitrateBps,
        'maxFps': maxFps,
        'supports10Bit': supports10Bit,
        'profileLevels': profileLevels,
      };

  bool get supports4K =>
      (maxWidth >= 3840 && maxHeight >= 2160) ||
      (maxWidth >= 2160 && maxHeight >= 3840);
}

/// GPU graphics and compute capabilities.
class GpuCapability {
  final String glEsVersion;
  final int reqGlEsVersion;
  final bool hasVulkan;
  final bool hasUnifiedMemory;
  final String? name;
  final int? maxWorkingSetBytes;

  const GpuCapability({
    required this.glEsVersion,
    required this.reqGlEsVersion,
    required this.hasVulkan,
    required this.hasUnifiedMemory,
    this.name,
    this.maxWorkingSetBytes,
  });

  factory GpuCapability.fromMap(Map<dynamic, dynamic> map) {
    return GpuCapability(
      glEsVersion: map['glEsVersion']?.toString() ?? '3.0',
      reqGlEsVersion: (map['reqGlEsVersion'] as num?)?.toInt() ?? 0x00030000,
      hasVulkan: map['hasVulkan'] as bool? ?? false,
      hasUnifiedMemory: map['hasUnifiedMemory'] as bool? ?? true,
      name: map['name']?.toString(),
      maxWorkingSetBytes: (map['maxWorkingSetBytes'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
        'glEsVersion': glEsVersion,
        'reqGlEsVersion': reqGlEsVersion,
        'hasVulkan': hasVulkan,
        'hasUnifiedMemory': hasUnifiedMemory,
        if (name != null) 'name': name,
        if (maxWorkingSetBytes != null) 'maxWorkingSetBytes': maxWorkingSetBytes,
      };
}

/// Comprehensive hardware capability snapshot probed dynamically from device APIs.
class HardwareCapabilities {
  final String model;
  final String manufacturer;
  final String device;
  final String hardware;
  final String board;
  final String socModel;
  final String osVersion;
  final int sdkInt;
  final String hardwareTier; // "high", "medium", "low"
  final int totalRamBytes;
  final int availRamBytes;
  final bool lowMemory;
  final List<CameraFormatCapability> cameras;
  final List<EncoderProfileCapability> encoders;
  final GpuCapability gpu;
  final Map<String, dynamic> rawMap;

  const HardwareCapabilities({
    required this.model,
    required this.manufacturer,
    required this.device,
    required this.hardware,
    required this.board,
    required this.socModel,
    required this.osVersion,
    required this.sdkInt,
    required this.hardwareTier,
    required this.totalRamBytes,
    required this.availRamBytes,
    required this.lowMemory,
    required this.cameras,
    required this.encoders,
    required this.gpu,
    required this.rawMap,
  });

  factory HardwareCapabilities.fromMap(Map<dynamic, dynamic> map) {
    final mem = (map['memory'] as Map<dynamic, dynamic>?) ?? const {};
    final cams = (map['cameras'] as List<dynamic>? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => CameraFormatCapability.fromMap(m))
        .toList();

    final encs = (map['encoders'] as List<dynamic>? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => EncoderProfileCapability.fromMap(m))
        .toList();

    final gpuMap = (map['gpu'] as Map<dynamic, dynamic>?) ?? const {};

    return HardwareCapabilities(
      model: map['model']?.toString() ?? 'Generic',
      manufacturer: map['manufacturer']?.toString() ?? 'Generic',
      device: map['device']?.toString() ?? 'Device',
      hardware: map['hardware']?.toString() ?? 'Hardware',
      board: map['board']?.toString() ?? 'Board',
      socModel: map['socModel']?.toString() ?? 'Chip',
      osVersion: map['osVersion']?.toString() ?? '',
      sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
      hardwareTier: map['hardwareTier']?.toString() ?? 'medium',
      totalRamBytes: (mem['totalRamBytes'] as num?)?.toInt() ?? 4 * 1024 * 1024 * 1024,
      availRamBytes: (mem['availRamBytes'] as num?)?.toInt() ?? 2 * 1024 * 1024 * 1024,
      lowMemory: mem['lowMemory'] as bool? ?? false,
      cameras: cams,
      encoders: encs,
      gpu: GpuCapability.fromMap(gpuMap),
      rawMap: Map<String, dynamic>.from(map),
    );
  }

  double get totalRamGb => totalRamBytes / (1024 * 1024 * 1024);
  double get availRamGb => availRamBytes / (1024 * 1024 * 1024);

  bool get supports4KRecording =>
      cameras.any((c) => c.supports4K) && encoders.any((e) => e.supports4K);

  bool get supportsHevc10Bit => encoders.any((e) =>
      e.codec == 'video/hevc' && e.supports10Bit && e.isHardwareAccelerated);

  bool get supportsHdrCapture => cameras.any((c) => c.isHdrSupported);

  Map<String, dynamic> toMap() => {
        'model': model,
        'manufacturer': manufacturer,
        'device': device,
        'hardware': hardware,
        'board': board,
        'socModel': socModel,
        'osVersion': osVersion,
        'sdkInt': sdkInt,
        'hardwareTier': hardwareTier,
        'memory': {
          'totalRamBytes': totalRamBytes,
          'availRamBytes': availRamBytes,
          'lowMemory': lowMemory,
        },
        'cameras': cameras.map((c) => c.toMap()).toList(),
        'encoders': encoders.map((e) => e.toMap()).toList(),
        'gpu': gpu.toMap(),
      };
}

/// Native channel bridge for probing hardware capabilities.
class DeviceCapabilityBridge {
  static const MethodChannel _defaultChannel =
      MethodChannel('oneova_camera_kit/device');

  /// Calls the native platform channel to probe device hardware.
  /// Falls back gracefully to system runtime metadata if platform call is unavailable.
  static Future<HardwareCapabilities> probe({
    MethodChannel? channelOverride,
  }) async {
    final channel = channelOverride ?? _defaultChannel;
    try {
      final res = await channel.invokeMethod<Map<dynamic, dynamic>>(
        'probeHardwareCapabilities',
      );
      if (res != null) {
        return HardwareCapabilities.fromMap(res);
      }
    } catch (_) {
      // Platform channel unavailable (e.g. running unit tests or unsupported host)
    }

    return _fallbackCapabilities();
  }

  static HardwareCapabilities _fallbackCapabilities() {
    final isApple = Platform.isIOS || Platform.isMacOS;
    final isAndroid = Platform.isAndroid;

    return HardwareCapabilities(
      model: isApple
          ? 'Apple Silicon'
          : (isAndroid ? 'Android Device' : 'Standard Host'),
      manufacturer: isApple ? 'Apple' : (isAndroid ? 'Google' : 'Generic'),
      device: 'oneova_device',
      hardware: 'host_hardware',
      board: 'host_board',
      socModel: 'host_soc',
      osVersion: Platform.operatingSystemVersion,
      sdkInt: isAndroid ? 34 : 0,
      hardwareTier: 'medium',
      totalRamBytes: 8 * 1024 * 1024 * 1024,
      availRamBytes: 4 * 1024 * 1024 * 1024,
      lowMemory: false,
      cameras: const [
        CameraFormatCapability(
          id: '0',
          facing: 'back',
          resolutions: [
            CameraResolution(width: 3840, height: 2160),
            CameraResolution(width: 1920, height: 1080),
            CameraResolution(width: 1280, height: 720),
          ],
          maxFps: 60,
          is10BitSupported: true,
          isHdrSupported: true,
        ),
        CameraFormatCapability(
          id: '1',
          facing: 'front',
          resolutions: [
            CameraResolution(width: 1920, height: 1080),
            CameraResolution(width: 1280, height: 720),
          ],
          maxFps: 30,
          is10BitSupported: false,
          isHdrSupported: false,
        ),
      ],
      encoders: const [
        EncoderProfileCapability(
          name: 'Hardware AVC',
          codec: 'video/avc',
          isHardwareAccelerated: true,
          maxWidth: 3840,
          maxHeight: 2160,
          maxBitrateBps: 50000000,
          maxFps: 60,
          supports10Bit: false,
          profileLevels: [],
        ),
        EncoderProfileCapability(
          name: 'Hardware HEVC',
          codec: 'video/hevc',
          isHardwareAccelerated: true,
          maxWidth: 3840,
          maxHeight: 2160,
          maxBitrateBps: 80000000,
          maxFps: 60,
          supports10Bit: true,
          profileLevels: [],
        ),
      ],
      gpu: const GpuCapability(
        glEsVersion: '3.2',
        reqGlEsVersion: 0x00030002,
        hasVulkan: true,
        hasUnifiedMemory: true,
      ),
      rawMap: const {},
    );
  }
}
