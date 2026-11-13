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

  /// [aspect43]: 4:3 preview like the stock photo mode (else 16:9).
  /// [quality]: '1080p30', '1080p60' or '4k30' for video.
  Future<ArCameraInfo> open({
    required bool front,
    ArCameraNeeds needs = const ArCameraNeeds(),
    bool aspect43 = false,
    String quality = '1080p30',
  }) async {
    final r = await _methods.invokeMapMethod<String, Object?>('open', {
      'front': front,
      'needs': needs.toMap(),
      'aspect43': aspect43,
      'quality': quality,
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

  /// A glTF binary (.glb) on disk for the 3D effect [id] in the scene.
  /// Throws a [PlatformException] when the model cannot be loaded.
  Future<void> putModel(String id, String path) => _methods.invokeMethod<void>('putModel', {'id': id, 'path': path});

  /// The replacement scene behind the person, or null to clear it.
  Future<void> setBackground(int? width, int? height, Uint8List? rgba) =>
      _methods.invokeMethod<void>('setBackground', {
        'image': rgba == null ? null : {'w': width, 'h': height, 'rgba': rgba},
      });

  /// A looping video file behind the person (replace mode), or null.
  Future<void> setBackgroundVideo(String? path) => _methods.invokeMethod<void>('setBackgroundVideo', {'path': path});

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

  /// Focus and meter at ([x], [y]) in the displayed preview (0..1). With
  /// [lock], AF/AE/AWB stay locked there until [unlockFocus]. Returns
  /// whether focus was reached.
  Future<bool> focusAt(double x, double y, {bool lock = false}) async =>
      (await _methods.invokeMethod<bool>('focusAt', {'x': x, 'y': y, 'lock': lock})) ?? false;

  Future<void> unlockFocus() => _methods.invokeMethod<void>('unlockFocus');

  /// `{supported, minEv, maxEv, stepEv, ev}` for exposure compensation.
  Future<Map<String, Object?>> exposureInfo() async =>
      (await _methods.invokeMapMethod<String, Object?>('exposureInfo')) ?? const {};

  /// Sets exposure compensation; returns the EV actually applied.
  Future<double> setExposure(double ev) async =>
      (await _methods.invokeMethod<num>('setExposure', {'ev': ev}))?.toDouble() ?? 0;

  /// `{manualSensor, isoMin, isoMax, exposureMinNs, exposureMaxNs, manualFocus, awbModes}`.
  Future<Map<String, Object?>> manualInfo() async =>
      (await _methods.invokeMapMethod<String, Object?>('manualInfo')) ?? const {};

  /// Manual ISO + shutter (both or neither), white balance preset
  /// (Camera2 `CONTROL_AWB_MODE_*`) and focus (0 = far … 1 = closest).
  /// Null values return to automatic.
  Future<void> setManual({int? iso, int? exposureNs, int? awb, double? focus}) =>
      _methods.invokeMethod<void>('setManual', {'iso': iso, 'exposureNs': exposureNs, 'awb': awb, 'focus': focus});

  /// Bakes a colour grade into recordings and photos: [look] is a compiled
  /// Oneova Look (`NativeLook.toMap()`), [matrix] a 4×5 colour matrix
  /// (Flutter `ColorFilter.matrix` layout) applied before it. Nulls clear.
  Future<void> setGrade({Map<String, Object>? look, List<double>? matrix}) =>
      _methods.invokeMethod<void>('setGrade', {'look': look, 'matrix': matrix});

  /// Low-light boost: lets auto exposure slow to 10 fps in the dark.
  Future<void> setLowLight(bool on) => _methods.invokeMethod<void>('setLowLight', {'on': on});

  /// `{min, max, ratio}` zoom range (min < 1: ultra-wide available).
  Future<Map<String, Object?>> zoomInfo() async =>
      (await _methods.invokeMapMethod<String, Object?>('zoomInfo')) ?? const {};

  /// Camera scene mode: 'auto', 'hdr' or 'night' (ignored where unsupported).
  Future<void> setSceneMode(String mode) => _methods.invokeMethod<void>('setSceneMode', {'mode': mode});

  /// Surface rotation (0..3) of the phone, so landscape takes save landscape.
  Future<void> setDeviceRotation(int rotation) => _methods.invokeMethod<void>('setDeviceRotation', {'rotation': rotation});

  /// True while another app records from the microphone.
  Future<bool> micBusy() async => (await _methods.invokeMethod<bool>('micBusy')) ?? false;

  /// Android thermal status (0 none, 1 light, 2 moderate, 3 severe …; -1 unknown).
  Future<int> thermalStatus() async => (await _methods.invokeMethod<int>('thermalStatus')) ?? -1;

  /// System camera sounds: 'shutter', 'start', 'stop'.
  Future<void> playSound(String kind) => _methods.invokeMethod<void>('playSound', {'kind': kind});

  /// Heat guard: run heavy tracking on alternate frames.
  Future<void> setThrottle(bool on) => _methods.invokeMethod<void>('setThrottle', {'on': on});

  /// Whether this phone can run the front and back cameras at once.
  Future<bool> dualSupported() async => (await _methods.invokeMethod<bool>('dualSupported')) ?? false;

  /// Turns dual camera on or off. Throws a [PlatformException] with code
  /// `dual_unsupported` on phones without concurrent cameras.
  Future<void> setDual(bool on, {ArDualLayout layout = const ArDualLayout()}) =>
      _methods.invokeMethod<void>('setDual', {'on': on, ...layout.toMap()});

  Future<void> setDualLayout(ArDualLayout layout) => _methods.invokeMethod<void>('setDualLayout', layout.toMap());
}

/// Where the second camera goes in dual mode, in preview uv (top-left origin).
@immutable
class ArDualLayout {
  /// `pip` (rounded window at x/y/w/h) or `split` (second camera on top).
  final String layout;
  final double x, y, w, h;

  /// Puts the second camera full frame (or on the bottom in split).
  final bool swap;

  const ArDualLayout({this.layout = 'pip', this.x = 0.62, this.y = 0.12, this.w = 0.32, this.h = 0.3, this.swap = false});

  ArDualLayout copyWith({String? layout, double? x, double? y, bool? swap}) =>
      ArDualLayout(layout: layout ?? this.layout, x: x ?? this.x, y: y ?? this.y, w: w, h: h, swap: swap ?? this.swap);

  Map<String, Object?> toMap() => {'layout': layout, 'x': x, 'y': y, 'w': w, 'h': h, 'swap': swap};
}
