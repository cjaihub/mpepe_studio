import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A look compiled for the native processors: the exact inputs the Flutter
/// path binds to `shaders/look_engine.frag` (see `LookCompiler`).
@immutable
class NativeLook {
  /// Identifies the look in stats and logs.
  final String id;

  /// `LookCompiler.uniformValues`, declaration order (the native side
  /// replaces the leading `uSize` with each frame's size).
  final Float32List uniforms;

  /// RGBA8 LUT atlas, `lutSize²` × `lutSize`.
  final Uint8List lutAtlasRgba;
  final int lutSize;

  /// RGBA8 curve texture, 256 × 2.
  final Uint8List curvesRgba;

  static const int curvesWidth = 256;
  static const int curvesHeight = 2;

  NativeLook({
    required this.id,
    required this.uniforms,
    required this.lutAtlasRgba,
    required this.lutSize,
    required this.curvesRgba,
  }) {
    if (lutSize < 2) throw ArgumentError.value(lutSize, 'lutSize', 'must be at least 2');
    final lutBytes = lutSize * lutSize * lutSize * 4;
    if (lutAtlasRgba.length != lutBytes) {
      throw ArgumentError('lutAtlasRgba has ${lutAtlasRgba.length} bytes, expected $lutBytes');
    }
    const curveBytes = curvesWidth * curvesHeight * 4;
    if (curvesRgba.length != curveBytes) {
      throw ArgumentError('curvesRgba has ${curvesRgba.length} bytes, expected $curveBytes');
    }
  }

  Map<String, Object> toMap() => {
        'id': id,
        'uniforms': uniforms,
        'lutAtlas': lutAtlasRgba,
        'lutSize': lutSize,
        'curves': curvesRgba,
      };
}

/// Frame-time and throughput counters of one attached track.
@immutable
class LookProcessorStats {
  final int framesGraded;
  final int framesPassedThrough;

  /// Why the latest ungraded frame was passed through (`no_look`,
  /// `cpu_buffer`, `unsupported_format`, `no_gl_context`,
  /// `output_pool_exhausted`, `render_error`), or null.
  final String? lastPassThroughReason;

  /// GPU time per graded frame, including the wait for completion.
  final double averageFrameMs;
  final double p95FrameMs;
  final int width;
  final int height;
  final String? lookId;

  const LookProcessorStats({
    required this.framesGraded,
    required this.framesPassedThrough,
    required this.lastPassThroughReason,
    required this.averageFrameMs,
    required this.p95FrameMs,
    required this.width,
    required this.height,
    required this.lookId,
  });

  factory LookProcessorStats.fromMap(Map<Object?, Object?> m) => LookProcessorStats(
        framesGraded: (m['framesGraded'] as num?)?.toInt() ?? 0,
        framesPassedThrough: (m['framesPassedThrough'] as num?)?.toInt() ?? 0,
        lastPassThroughReason: m['lastPassThroughReason'] as String?,
        averageFrameMs: (m['averageFrameMs'] as num?)?.toDouble() ?? 0,
        p95FrameMs: (m['p95FrameMs'] as num?)?.toDouble() ?? 0,
        width: (m['width'] as num?)?.toInt() ?? 0,
        height: (m['height'] as num?)?.toInt() ?? 0,
        lookId: m['lookId'] as String?,
      );
}

/// Grades the frames of a local flutter_webrtc / LiveKit video track on the
/// GPU before they reach the encoder and local preview.
///
/// Android renders with GLES 3 on the capturer's texture thread; iOS renders
/// with Metal on the capture queue. Frames never leave the GPU.
class TrackLookProcessor {
  static const MethodChannel _channel = MethodChannel('oneova_camera_kit/look_processor');

  /// The flutter_webrtc track id (`MediaStreamTrack.id`; for LiveKit,
  /// `localVideoTrack.mediaStreamTrack.id`).
  final String trackId;
  bool _attached = true;

  TrackLookProcessor._(this.trackId);

  bool get isAttached => _attached;

  /// Installs the processor on [trackId]. Throws a [PlatformException] with
  /// code `track_not_found` when the track is not a local video track.
  /// Use the primary camera track: on Android, secondary tracks sharing its
  /// source never receive frames through their own processor.
  ///
  /// [maxInFlightFrames] bounds the graded frames held at once by the
  /// encoder and local renderers; when they are all busy the original frame
  /// is sent instead of stalling capture.
  static Future<TrackLookProcessor> attach(String trackId, {int maxInFlightFrames = 4}) async {
    await _channel.invokeMethod<void>('attach', {
      'trackId': trackId,
      'maxInFlightFrames': maxInFlightFrames,
    });
    return TrackLookProcessor._(trackId);
  }

  /// Switches to [look] (null sends the original frames), cross-fading for
  /// [crossFade].
  Future<void> setLook(NativeLook? look, {required Duration crossFade}) {
    _ensureAttached();
    return _channel.invokeMethod<void>('setLook', {
      'trackId': trackId,
      'look': look?.toMap(),
      'crossFadeMs': crossFade.inMilliseconds,
    });
  }

  Future<LookProcessorStats> stats() async {
    _ensureAttached();
    final m = await _channel.invokeMapMethod<Object?, Object?>('stats', {'trackId': trackId});
    return LookProcessorStats.fromMap(m ?? const {});
  }

  /// Removes the processor; GPU resources are freed once in-flight frames
  /// are released.
  Future<void> detach() async {
    if (!_attached) return;
    _attached = false;
    await _channel.invokeMethod<void>('detach', {'trackId': trackId});
  }

  void _ensureAttached() {
    if (!_attached) throw StateError('TrackLookProcessor for $trackId is detached');
  }
}
