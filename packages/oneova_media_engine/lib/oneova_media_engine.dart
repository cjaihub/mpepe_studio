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

/// One track found by [OneovaMediaEngine.inspect].
class MediaTrackInfo {
  final String mime;

  /// 'video', 'audio', 'image' or 'other'.
  final String kind;

  /// Whether this phone has a decoder for the track.
  final bool decodable;
  final int width;
  final int height;

  const MediaTrackInfo({required this.mime, required this.kind, required this.decodable, this.width = 0, this.height = 0});

  /// Short codec name for messages ("HEVC", "AV1", "Opus"...).
  String get codecName {
    final m = mime.toLowerCase();
    const names = {
      'video/avc': 'H.264',
      'video/hevc': 'HEVC (H.265)',
      'video/x-vnd.on2.vp8': 'VP8',
      'video/x-vnd.on2.vp9': 'VP9',
      'video/av01': 'AV1',
      'video/dolby-vision': 'Dolby Vision',
      'video/mp4v-es': 'MPEG-4',
      'video/3gpp': 'H.263',
      'video/mpeg2': 'MPEG-2',
      'audio/mp4a-latm': 'AAC',
      'audio/mpeg': 'MP3',
      'audio/opus': 'Opus',
      'audio/vorbis': 'Vorbis',
      'audio/flac': 'FLAC',
      'audio/raw': 'PCM',
      'audio/ac3': 'Dolby AC-3',
      'audio/eac3': 'Dolby E-AC-3',
      'audio/3gpp': 'AMR',
      'audio/amr-wb': 'AMR-WB',
    };
    return names[m] ?? mime.split('/').last.toUpperCase();
  }
}

/// Result of [OneovaMediaEngine.inspect].
class MediaInspection {
  /// The container could be opened by Android's extractor.
  final bool readable;
  final String? error;
  final List<MediaTrackInfo> tracks;

  const MediaInspection({required this.readable, this.error, this.tracks = const []});

  Iterable<MediaTrackInfo> get video => tracks.where((t) => t.kind == 'video');
  Iterable<MediaTrackInfo> get audio => tracks.where((t) => t.kind == 'audio');

  factory MediaInspection.fromMap(Map<dynamic, dynamic> m) => MediaInspection(
        readable: m['readable'] == true,
        error: m['error'] as String?,
        tracks: [
          for (final t in (m['tracks'] as List? ?? const []))
            MediaTrackInfo(
              mime: (t as Map)['mime'] as String? ?? '',
              kind: t['kind'] as String? ?? 'other',
              decodable: t['decodable'] == true,
              width: (t['width'] as num?)?.toInt() ?? 0,
              height: (t['height'] as num?)?.toInt() ?? 0,
            ),
        ],
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

  /// Exact frames at [timesMs] (long side at most [maxSide]); '' where a
  /// frame could not be read.
  static Future<List<String>> frames(String path, {required List<int> timesMs, required String outDir, int maxSide = 480}) async {
    final list = await _channel.invokeMethod<List<dynamic>>('frames', {
      'path': path,
      'times': timesMs,
      'outDir': outDir,
      'maxSide': maxSide,
    });
    return (list ?? const []).cast<String>();
  }

  static Future<T> _call<T>(String method, Map<String, Object?> args) async {
    try {
      return (await _channel.invokeMethod<T>(method, args)) as T;
    } on PlatformException catch (e) {
      throw MediaEngineException(e.code, e.message ?? e.code);
    }
  }

  /// Animated GIF -> silent MP4 (one loop). Returns (path, width, height, durationMs).
  /// Progress comes on [progress].
  static Future<(String, int, int, int)> gifToVideo(String path, {required String out, int maxSide = 1080}) async {
    final m = await _call<Map<dynamic, dynamic>>('gifToVideo', {'path': path, 'out': out, 'maxSide': maxSide});
    return (m['path'] as String, (m['width'] as num).toInt(), (m['height'] as num).toInt(), (m['durationMs'] as num).toInt());
  }

  /// [startMs, endMs] of [path] played backwards, silent MP4. Progress on [progress].
  static Future<String> reverse(String path, {required String out, required int startMs, required int endMs, int fps = 30, int maxSide = 1280}) =>
      _call<String>('reverse', {'path': path, 'out': out, 'startMs': startMs, 'endMs': endMs, 'fps': fps, 'maxSide': maxSide});

  /// Camera path of [startMs, endMs]: source times and cumulative shift (x, y
  /// as fractions of the frame). Progress on [progress].
  static Future<(List<int>, List<double>, List<double>)> motion(String path, {required int startMs, required int endMs, int fps = 8}) async {
    final m = await _call<Map<dynamic, dynamic>>('motion', {'path': path, 'startMs': startMs, 'endMs': endMs, 'fps': fps});
    List<double> d(String k) => (m[k] as List).map((e) => (e as num).toDouble()).toList();
    return ((m['timesMs'] as List).map((e) => (e as num).toInt()).toList(), d('x'), d('y'));
  }

  /// Beat times (ms) and tempo of the sound in [path].
  static Future<(List<int>, double)> beats(String path, {int maxMs = 600000}) async {
    final m = await _call<Map<dynamic, dynamic>>('beats', {'path': path, 'maxMs': maxMs});
    return ((m['beatsMs'] as List).map((e) => (e as num).toInt()).toList(), (m['bpm'] as num).toDouble());
  }

  static Future<EncoderCapabilities> capabilities() async {
    final m = await _channel.invokeMethod<Map<dynamic, dynamic>>('capabilities');
    return EncoderCapabilities(
      maxWidth: (m?['maxWidth'] as num?)?.toInt() ?? 1920,
      maxHeight: (m?['maxHeight'] as num?)?.toInt() ?? 1080,
      maxFps: (m?['maxFps'] as num?)?.toInt() ?? 30,
    );
  }

  /// Container and per-track decoder support for [path].
  static Future<MediaInspection> inspect(String path) async {
    final m = await _channel.invokeMethod<Map<dynamic, dynamic>>('inspect', {'path': path});
    return MediaInspection.fromMap(m ?? const {});
  }

  /// Decodes any image the phone supports (HEIC/HEIF, AVIF, GIF, BMP, WebP,
  /// very large photos), upright and at most [maxSide] px, into a JPEG (or a
  /// PNG when it has transparency). Returns (path, width, height).
  static Future<(String, int, int)> normalizeImage(String path, {required String out, int maxSide = 4096}) async {
    try {
      final m = await _channel.invokeMethod<Map<dynamic, dynamic>>('normalizeImage', {'path': path, 'out': out, 'maxSide': maxSide});
      return (m!['path'] as String, (m['width'] as num).toInt(), (m['height'] as num).toInt());
    } on PlatformException catch (e) {
      throw MediaEngineException(e.code, e.message ?? e.code);
    }
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
