import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the native tracker should run on the analysis stream.
@immutable
class ArCameraNeeds {
  final bool face;
  final bool mask;
  final bool body;

  const ArCameraNeeds({this.face = false, this.mask = false, this.body = false});

  Map<String, bool> toMap() => {'face': face, 'mask': mask, 'body': body};
}

/// An open native AR camera: its Flutter texture and upright preview size.
@immutable
class ArCameraInfo {
  final int textureId;
  final int width;
  final int height;
  final bool mirrored;

  const ArCameraInfo({
    required this.textureId,
    required this.width,
    required this.height,
    required this.mirrored,
  });
}

/// Native camera + AR pipeline (Android, CameraX + ML Kit + GLES).
///
/// The Preview stream runs at full resolution into [ArCameraInfo.textureId];
/// tracking runs natively on a small ImageAnalysis stream and arrives on
/// [frames] as plain maps:
///
/// ```
/// {type: 'frame', t, faces: [{a: Float32List(24), pose: Float32List(3),
///   c: {contourName: Float32List}}], body: Float32List(8)?,
///   mask: {w, h, c: Uint8List}?, trackMs, trackFps, previewFps}
/// ```
///
/// All coordinates are normalized to the preview and already mirrored for
/// the front camera. While recording, the native side composites the scene
/// set with [setScene] / [putImage] / [setBackground] / [setWorld] into the
/// video, so effects are baked into the file.
class OneovaArCamera {
  OneovaArCamera._();

  static final OneovaArCamera instance = OneovaArCamera._();

  static const _methods = MethodChannel('oneova_camera_kit/ar_camera');
  static const _events = EventChannel('oneova_camera_kit/ar_camera/frames');

  static bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Stream<Map<Object?, Object?>>? _frames;

  /// Tracking results and preview-size changes from the open session.
  Stream<Map<Object?, Object?>> get frames => _frames ??= _events
      .receiveBroadcastStream()
      .where((e) => e is Map)
      .cast<Map<Object?, Object?>>();

  Future<ArCameraInfo> open({required bool front, ArCameraNeeds needs = const ArCameraNeeds()}) async {
    final r = await _methods.invokeMapMethod<String, Object?>('open', {
      'front': front,
      'needs': needs.toMap(),
    });
    if (r == null) throw PlatformException(code: 'open_failed');
    return ArCameraInfo(
      textureId: (r['textureId'] as num).toInt(),
      width: (r['width'] as num).toInt(),
      height: (r['height'] as num).toInt(),
      mirrored: r['mirrored'] == true,
    );
  }

  Future<void> close() => _methods.invokeMethod<void>('close');

  Future<void> setNeeds(ArCameraNeeds needs) => _methods.invokeMethod<void>('setNeeds', needs.toMap());

  /// Effects and background mode the recorder composites (see `ArScene`).
  Future<void> setScene(Map<String, Object?> scene) => _methods.invokeMethod<void>('setScene', scene);

  /// A sprite's pixels: premultiplied RGBA (`ImageByteFormat.rawRgba`).
  Future<void> putImage(String id, int width, int height, Uint8List rgba) =>
      _methods.invokeMethod<void>('putImage', {
        'id': id,
        'image': {'w': width, 'h': height, 'rgba': rgba},
      });

  /// The replacement scene behind the person, or null to clear it.
  Future<void> setBackground(int? width, int? height, Uint8List? rgba) =>
      _methods.invokeMethod<void>('setBackground', {
        'image': rgba == null ? null : {'w': width, 'h': height, 'rgba': rgba},
      });

  /// World sticker placements: id → [x, y, scale, rotation].
  Future<void> setWorld(Map<String, List<double>> placements) =>
      _methods.invokeMethod<void>('setWorld', placements);

  Future<void> setTorch(bool on) => _methods.invokeMethod<void>('setTorch', {'on': on});

  /// 'off' | 'auto' | 'always' for stills.
  Future<void> setFlashMode(String mode) => _methods.invokeMethod<void>('setFlashMode', {'mode': mode});

  Future<void> setZoom(double ratio) => _methods.invokeMethod<void>('setZoom', {'ratio': ratio});

  /// Full-resolution still (front camera mirrored like the preview); returns its path.
  Future<String> takePicture() async => (await _methods.invokeMethod<String>('takePicture'))!;

  /// Starts recording the composited frames; returns the output path.
  Future<String> startRecording({String? path, bool audio = true}) async =>
      (await _methods.invokeMethod<String>('startRecording', {'path': path, 'audio': audio}))!;

  /// Finishes the file; returns its duration in milliseconds.
  Future<int> stopRecording() async => (await _methods.invokeMethod<int>('stopRecording'))!;

  Future<Map<String, Object?>> stats() async =>
      (await _methods.invokeMapMethod<String, Object?>('stats')) ?? const {};
}
