import 'dart:async';

import 'package:flutter/services.dart';

/// Facts about a media file read on-device.
class MediaProbe {
  final int width;
  final int height;
  final Duration duration;
  final int bitrate;
  final double fps;
  final bool hasVideo;
  final bool hasAudio;
  final int sizeBytes;

  const MediaProbe({
    required this.width,
    required this.height,
    required this.duration,
    required this.bitrate,
    required this.fps,
    required this.hasVideo,
    required this.hasAudio,
    required this.sizeBytes,
  });

  factory MediaProbe.fromMap(Map<dynamic, dynamic> m) => MediaProbe(
        width: (m['width'] as num?)?.toInt() ?? 0,
        height: (m['height'] as num?)?.toInt() ?? 0,
        duration: Duration(milliseconds: (m['durationMs'] as num?)?.toInt() ?? 0),
        bitrate: (m['bitrate'] as num?)?.toInt() ?? 0,
        fps: (m['fps'] as num?)?.toDouble() ?? 0,
        hasVideo: m['hasVideo'] == true,
        hasAudio: m['hasAudio'] == true,
        sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
      );
}

/// What the device's H.264 encoder can produce.
class EncoderCapabilities {
  final int maxWidth;
  final int maxHeight;
  final int maxFps;

  const EncoderCapabilities({required this.maxWidth, required this.maxHeight, required this.maxFps});

  /// Long side x short side the encoder can take, in either orientation.
  bool supports(int longSide, int shortSide) {
    final long = maxWidth > maxHeight ? maxWidth : maxHeight;
    final short = maxWidth > maxHeight ? maxHeight : maxWidth;
    return longSide <= long && shortSide <= short;
  }
}

/// Thrown when an export fails or is cancelled.
class MediaEngineException implements Exception {
  final String code;
  final String message;
  const MediaEngineException(this.code, this.message);

  bool get cancelled => code == 'cancelled';

  @override
  String toString() => message;
}

/// On-device media processing (Android, Media3 Transformer).
class OneovaMediaEngine {
  OneovaMediaEngine._();

  static const _channel = MethodChannel('oneova_media_engine');
  static const _progress = EventChannel('oneova_media_engine/progress');

  static Stream<double>? _progressStream;

  /// Export progress 0..1 for the running export.
  static Stream<double> get progress => _progressStream ??= _progress
      .receiveBroadcastStream()
      .map((e) => ((e as Map)['progress'] as num).toDouble())
      .asBroadcastStream();

  static Future<MediaProbe> probe(String path) async {
    final m = await _channel.invokeMethod<Map<dynamic, dynamic>>('probe', {'path': path});
    return MediaProbe.fromMap(m ?? const {});
  }

  static Future<List<String>> thumbnails(
    String path, {
    required String outDir,
    int count = 8,
    int startMs = 0,
    int endMs = 0,
    int height = 120,
  }) async {
    final list = await _channel.invokeMethod<List<dynamic>>('thumbnails', {
      'path': path,
      'outDir': outDir,
      'count': count,
      'startMs': startMs,
      'endMs': endMs,
      'height': height,
    });
    return (list ?? const []).cast<String>();
  }

  /// Writes the frame at [ms] to [out] as JPEG and returns [out].
  static Future<String> frame(String path, {required int ms, required String out, int maxSide = 1920}) async {
    final r = await _channel.invokeMethod<String>('frame', {'path': path, 'ms': ms, 'out': out, 'maxSide': maxSide});
    return r ?? out;
  }

  static Future<EncoderCapabilities> capabilities() async {
    final m = await _channel.invokeMethod<Map<dynamic, dynamic>>('capabilities');
    return EncoderCapabilities(
      maxWidth: (m?['maxWidth'] as num?)?.toInt() ?? 1920,
      maxHeight: (m?['maxHeight'] as num?)?.toInt() ?? 1080,
      maxFps: (m?['maxFps'] as num?)?.toInt() ?? 30,
    );
  }

  /// Renders [spec] (see TimelineExporter.kt) and returns the output path.
  static Future<String> export(Map<String, Object?> spec) async {
    try {
      final r = await _channel.invokeMethod<String>('export', spec);
      return r!;
    } on PlatformException catch (e) {
      throw MediaEngineException(e.code, e.message ?? e.code);
    }
  }

  static Future<void> cancel() => _channel.invokeMethod('cancel');
}
