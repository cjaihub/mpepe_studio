import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:oneova_camera_kit/oneova_camera_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../builtin/builtin_effects.dart';
import '../models/ar_effect.dart';
import '../render/ar_effect_painter.dart';
import '../services/ar_effect_repository.dart';
import '../tracking/ar_tracking_models.dart';
import '../tracking/ar_tracking_service.dart';
import '../tracking/native_ar_frames.dart';

enum ArBackgroundMode { none, blur, replace }

@immutable
class LiveArState {
  /// Active effects by slot, so a hat, glasses and a beard can stack.
  final Map<String, ArEffect> active;
  final Map<String, ui.Image> images;
  final ArBackgroundMode backgroundMode;
  final double blurSigma;

  /// Replacement scene: an effect's image or a photo the user picked.
  final ui.Image? backgroundImage;
  final String? backgroundLabel;

  /// "Add yourself": the cut-out can be moved and scaled inside the scene.
  final bool addYourself;
  final Offset personOffset;
  final double personScale;

  final Set<String> loading;
  final String? error;

  const LiveArState({
    this.active = const {},
    this.images = const {},
    this.backgroundMode = ArBackgroundMode.none,
    this.blurSigma = 14,
    this.backgroundImage,
    this.backgroundLabel,
    this.addYourself = false,
    this.personOffset = Offset.zero,
    this.personScale = 1,
    this.loading = const {},
    this.error,
    this.previewFace = false,
    this.outfitColor,
    this.outfitStrength = 0.8,
    this.transparentBackground = false,
    this.backgroundVideoPath,
    this.effectPerPerson = false,
    this.autoTrack = false,
  });

  /// Smart Auto-Track: keeps face & body tracking active and dynamically frames the subject.
  final bool autoTrack;

  /// With several people in frame, each gets a different face effect
  /// (person 1 the first one picked, person 2 the next…).
  final bool effectPerPerson;

  /// Background removed entirely: photos save as transparent PNGs; videos
  /// (no alpha in MP4) record on key green so an editor can key it out.
  final bool transparentBackground;

  /// A looping video from the phone behind the person (replace mode).
  final String? backgroundVideoPath;

  /// Outfit colour: clothes (person mask, below the neck, skin kept) are
  /// recoloured live and in captures; null = off.
  final Color? outfitColor;
  final double outfitStrength;
  bool get outfitOn => outfitColor != null && outfitStrength > 0;

  List<ArEffect> get effects => active.values.toList(growable: false);
  bool get hasAnything => active.isNotEmpty || backgroundMode != ArBackgroundMode.none || outfitOn;

  /// True while a tool (e.g. Makeup Studio) wants face tracking with nothing
  /// applied yet, so it can show whether a face is found.
  final bool previewFace;

  /// Whether the AR camera path should run at all.
  bool get usesAr => hasAnything || previewFace || autoTrack;
  bool isActive(String id) => active.values.any((e) => e.id == id);

  ArTrackingNeeds get needs => ArTrackingNeeds(
        face: previewFace || autoTrack || outfitOn || active.values.any((e) => e.needsFace),
        body: autoTrack || outfitOn || active.values.any((e) => e.needsBody),
        mask: backgroundMode != ArBackgroundMode.none || outfitOn,
      );

  LiveArState copyWith({
    Map<String, ArEffect>? active,
    Map<String, ui.Image>? images,
    ArBackgroundMode? backgroundMode,
    double? blurSigma,
    ui.Image? Function()? backgroundImage,
    String? Function()? backgroundLabel,
    bool? addYourself,
    Offset? personOffset,
    double? personScale,
    Set<String>? loading,
    String? Function()? error,
    bool? previewFace,
    Color? Function()? outfitColor,
    double? outfitStrength,
    bool? transparentBackground,
    String? Function()? backgroundVideoPath,
    bool? effectPerPerson,
    bool? autoTrack,
  }) =>
      LiveArState(
        active: active ?? this.active,
        images: images ?? this.images,
        backgroundMode: backgroundMode ?? this.backgroundMode,
        blurSigma: blurSigma ?? this.blurSigma,
        backgroundImage: backgroundImage != null ? backgroundImage() : this.backgroundImage,
        backgroundLabel: backgroundLabel != null ? backgroundLabel() : this.backgroundLabel,
        addYourself: addYourself ?? this.addYourself,
        personOffset: personOffset ?? this.personOffset,
        personScale: personScale ?? this.personScale,
        loading: loading ?? this.loading,
        error: error != null ? error() : this.error,
        previewFace: previewFace ?? this.previewFace,
        outfitColor: outfitColor != null ? outfitColor() : this.outfitColor,
        outfitStrength: outfitStrength ?? this.outfitStrength,
        transparentBackground: transparentBackground ?? this.transparentBackground,
        backgroundVideoPath: backgroundVideoPath != null ? backgroundVideoPath() : this.backgroundVideoPath,
        effectPerPerson: effectPerPerson ?? this.effectPerPerson,
        autoTrack: autoTrack ?? this.autoTrack,
      );
}

/// Runs live AR effects for the camera: owns the frame stream into ML Kit,
/// the active effects and their decoded images, background modes and the
/// gyro-locked world stickers.
///
/// Two camera sources: the Flutter `camera` image stream (tracked here in
/// Dart; iOS and fallback), or the native AR camera on Android
/// ([attachNativeCamera]), which tracks natively and bakes the same scene
/// into recorded video — this controller then only mirrors its state there.
class LiveArController extends Notifier<LiveArState> {
  final ArTrackingService _tracker = ArTrackingService();

  /// Latest tracked frame; listened to by the viewfinder so the camera
  /// screen itself never rebuilds per frame.
  final ValueNotifier<ArFrame?> frame = ValueNotifier<ArFrame?>(null);

  /// World-anchored sticker placements (normalized), updated by the gyro.
  final ValueNotifier<Map<String, ArWorldPlacement>> world =
      ValueNotifier<Map<String, ArWorldPlacement>>(const {});

  CameraController? _camera;
  CameraDescription? _description;
  bool _streaming = false;
  StreamSubscription<GyroscopeEvent>? _gyro;
  DateTime? _lastGyro;
  ArFrame? _previous;

  // Native AR camera (Android).
  OneovaArCamera? _native;
  bool _nativeMirror = false;
  StreamSubscription<Map<Object?, Object?>>? _nativeSub;
  bool _decoding = false;
  int _nativeFrames = 0;
  final Set<String> _sentImages = {};

  /// Downloaded 3D models (effect id → .glb path) and those the camera has.
  final Map<String, String> _modelPaths = {};
  final Set<String> _sentModels = {};
  ui.Image? _sentBackground;
  String? _sentBackgroundVideo;
  ui.Image? _keyGreen;
  bool _syncingNative = false;
  bool _nativeDirty = false;
  Timer? _worldTimer;

  @override
  LiveArState build() {
    listenSelf((_, _) {
      if (_native != null) unawaited(_syncNative());
    });
    world.addListener(_onWorldChanged);
    ref.onDispose(() {
      _gyro?.cancel();
      _worldTimer?.cancel();
      _nativeSub?.cancel();
      _stopStream();
      _previous?.mask?.dispose();
      frame.value?.mask?.dispose();
      frame.dispose();
      world.dispose();
      _tracker.dispose();
    });
    return const LiveArState();
  }

  // ── Camera stream ───────────────────────────────────────────────────────

  /// Hooks the camera up; call again after the camera is re-created.
  Future<void> attachCamera(CameraController camera, CameraDescription description) async {
    if (_camera != camera) {
      _streaming = false;
      _tracker.reset();
    }
    _camera = camera;
    _description = description;
    await _syncStream();
  }

  void detachCamera() {
    _stopStream();
    _camera = null;
  }

  // ── Native AR camera (Android) ──────────────────────────────────────────

  bool get usesNativeCamera => _native != null;

  /// Switches tracking to the native camera; tracking results come back on
  /// its event stream and the active scene is mirrored to it for recording.
  Future<void> attachNativeCamera(OneovaArCamera camera, {required bool mirror}) async {
    detachCamera();
    await _nativeSub?.cancel();
    _native = camera;
    _nativeMirror = mirror;
    _sentImages.clear();
    _sentModels.clear();
    _sentBackground = null;
    _sentBackgroundVideo = null;
    _nativeFrames = 0;
    _nativeSub = camera.frames.listen(_onNativeEvent);
    await _syncNative();
    _pushWorld();
  }

  void detachNativeCamera() {
    _nativeSub?.cancel();
    _nativeSub = null;
    _native = null;
    _sentImages.clear();
    _sentModels.clear();
    _sentBackground = null;
    _sentBackgroundVideo = null;
    _setFrame(null);
  }

  Future<void> _onNativeEvent(Map<Object?, Object?> e) async {
    if (e['type'] != 'frame' || _native == null) return;
    // Drop frames while the previous mask image is still being built.
    if (_decoding) return;
    _decoding = true;
    try {
      final f = await decodeNativeArFrame(e);
      if (_native != null && state.needs.any) {
        _setFrame(f);
      } else {
        f.mask?.dispose();
      }
      if (kDebugMode && ++_nativeFrames % 90 == 0) {
        debugPrint('[AR native] track ${(e['trackFps'] as num?)?.toStringAsFixed(1)} fps '
            '(${(e['trackMs'] as num?)?.toStringAsFixed(1)} ms), '
            'preview ${(e['previewFps'] as num?)?.toStringAsFixed(1)} fps');
      }
    } catch (err) {
      debugPrint('AR native frame decode failed: $err');
    } finally {
      _decoding = false;
    }
  }

  /// Sends needs, the effect scene, new sprite pixels and the background
  /// image to the native camera. Coalesces bursts of state changes.
  Future<void> _syncNative() async {
    if (_syncingNative) {
      _nativeDirty = true;
      return;
    }
    _syncingNative = true;
    try {
      do {
        _nativeDirty = false;
        final cam = _native;
        if (cam == null) return;
        final s = state;
        final n = s.needs;
        await cam.setNeeds(ArCameraNeeds(face: n.face, mask: n.mask, body: n.body));
        if (!n.any) _setFrame(null);

        for (final e in s.effects) {
          final img = s.images[e.id];
          if (e.kind != ArEffectKind.sprite || img == null || _sentImages.contains(e.id)) continue;
          final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
          if (bytes == null || _native != cam) continue;
          await cam.putImage(e.id, img.width, img.height, bytes.buffer.asUint8List());
          _sentImages.add(e.id);
        }
        _sentImages.removeWhere((id) => !s.effects.any((e) => e.id == id));

        for (final e in s.effects) {
          final path = _modelPaths[e.id];
          if (!e.is3d || path == null || _sentModels.contains(e.id)) continue;
          try {
            await cam.putModel(e.id, path);
            _sentModels.add(e.id);
          } catch (err) {
            debugPrint('3D model ${e.id} failed: $err');
            if (_native == cam) {
              _sentModels.add(e.id);
              state = state.copyWith(error: () => 'Could not show "${e.name}" in 3D on this phone.');
            }
          }
        }
        _sentModels.removeWhere((id) => !s.effects.any((e) => e.id == id));

        // Videos have no alpha: a transparent background records on key green.
        final bg = s.backgroundMode != ArBackgroundMode.replace
            ? null
            : s.transparentBackground
                ? (_keyGreen ??= await _solidImage(const Color(0xFF00B140)))
                : s.backgroundImage;
        final video = s.backgroundMode == ArBackgroundMode.replace ? s.backgroundVideoPath : null;
        if (video != _sentBackgroundVideo) {
          await cam.setBackgroundVideo(video);
          _sentBackgroundVideo = video;
        }
        if (bg != _sentBackground) {
          if (bg == null) {
            await cam.setBackground(null, null, null);
          } else {
            final bytes = await bg.toByteData(format: ui.ImageByteFormat.rawRgba);
            if (bytes != null) await cam.setBackground(bg.width, bg.height, bytes.buffer.asUint8List());
          }
          _sentBackground = bg;
        }

        await cam.setScene({
          'effects': [
            for (final e in s.effects)
              if (e.kind != ArEffectKind.background)
                {
                  'id': e.id,
                  'kind': e.kind.name,
                  'anchor': e.anchor.name,
                  'scale': e.scale,
                  'offsetX': e.offsetX,
                  'offsetY': e.offsetY,
                  if (e.kind == ArEffectKind.makeup) 'makeup': _makeupMap(e.makeup),
                  if (e.is3d) 'model': e.modelFit.toMap(),
                },
          ],
          'backgroundMode': s.backgroundMode.index,
          'blurSigma': s.blurSigma,
          'addYourself': s.addYourself,
          'personOffsetX': s.personOffset.dx,
          'personOffsetY': s.personOffset.dy,
          'personScale': s.personScale,
          'perPerson': s.effectPerPerson,
          if (s.outfitOn)
            'outfit': [
              (s.outfitColor!.r).toDouble(),
              (s.outfitColor!.g).toDouble(),
              (s.outfitColor!.b).toDouble(),
              s.outfitStrength,
            ],
        });
      } while (_nativeDirty);
    } catch (e) {
      debugPrint('AR native sync failed: $e');
    } finally {
      _syncingNative = false;
    }
  }

  static Map<String, Object> _makeupMap(ArMakeup m) => m.toNative();

  /// World stickers move with the gyro at up to 60 Hz; the recorder only
  /// needs ~30 updates a second.
  void _onWorldChanged() {
    if (_native == null || _worldTimer != null) return;
    _worldTimer = Timer(const Duration(milliseconds: 33), () {
      _worldTimer = null;
      _pushWorld();
    });
  }

  void _pushWorld() {
    final cam = _native;
    if (cam == null) return;
    unawaited(cam.setWorld({
      for (final e in world.value.entries)
        e.key: [e.value.position.dx, e.value.position.dy, e.value.scale, e.value.rotation],
    }).catchError((Object _) {}));
  }

  Future<void> _syncStream() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    final want = state.needs.any;
    if (want && !_streaming && !cam.value.isStreamingImages) {
      _streaming = true;
      try {
        await cam.startImageStream(_onImage);
      } catch (e) {
        _streaming = false;
        debugPrint('AR image stream failed: $e');
      }
    } else if (!want && _streaming) {
      await _stopStream();
      _setFrame(null);
    }
  }

  Future<void> _stopStream() async {
    final cam = _camera;
    _streaming = false;
    if (cam != null && cam.value.isInitialized && cam.value.isStreamingImages) {
      try {
        await cam.stopImageStream();
      } catch (_) {}
    }
  }

  Future<void> _onImage(CameraImage image) async {
    final d = _description;
    if (d == null) return;
    final f = await _tracker.processCameraImage(image, d, state.needs);
    if (f != null && _streaming) _setFrame(f);
  }

  void _setFrame(ArFrame? f) {
    // Keep the previous mask alive one extra frame: it may still be on screen.
    _previous?.mask?.dispose();
    _previous = frame.value;
    frame.value = f;
  }

  // ── Effects ─────────────────────────────────────────────────────────────

  bool isActive(String effectId) => state.isActive(effectId);

  /// Turns an effect on (replacing whatever sat in the same slot) or off.
  Future<void> toggle(ArEffect effect) async {
    if (state.isActive(effect.id)) {
      remove(effect);
      return;
    }
    if (effect.is3d) {
      final url = effect.modelUrl;
      if (url == null || !OneovaArCamera.isSupported) {
        state = state.copyWith(error: () => url == null ? 'This 3D effect has no model yet.' : '3D effects need the Oneova camera on Android.');
        return;
      }
      state = state.copyWith(loading: {...state.loading, effect.id}, error: () => null);
      try {
        _modelPaths[effect.id] ??= await _downloadModel(effect.id, url);
      } catch (e) {
        state = state.copyWith(
          loading: {...state.loading}..remove(effect.id),
          error: () => 'Could not download "${effect.name}". Check your connection.',
        );
        return;
      }
    } else if (effect.kind != ArEffectKind.makeup) {
      final builtIn = BuiltInEffects.isBuiltIn(effect.id);
      final url = effect.assetUrl;
      if (url == null && !builtIn) {
        state = state.copyWith(error: () => 'This effect has no image yet.');
        return;
      }
      state = state.copyWith(loading: {...state.loading, effect.id}, error: () => null);
      try {
        final img = state.images[effect.id] ??
            (builtIn ? await BuiltInEffects.image(effect.id) : await _loadImage(url!));
        state = state.copyWith(images: {...state.images, effect.id: img});
      } catch (e) {
        state = state.copyWith(
          loading: {...state.loading}..remove(effect.id),
          error: () => 'Could not load "${effect.name}".',
        );
        return;
      }
    }

    final active = {...state.active, effect.slot: effect};
    var next = state.copyWith(active: active, loading: {...state.loading}..remove(effect.id));
    if (effect.kind == ArEffectKind.background) {
      next = next.copyWith(
        backgroundMode: ArBackgroundMode.replace,
        backgroundImage: () => next.images[effect.id],
        backgroundLabel: () => effect.name,
      );
    }
    state = next;
    if (effect.isWorld) {
      world.value = {...world.value, effect.id: const ArWorldPlacement()};
    }
    _syncGyro();
    unawaited(_syncStream());
    if (!BuiltInEffects.isBuiltIn(effect.id) && effect.source != 'custom') {
      unawaited(ref.read(arEffectRepositoryProvider).recordUse(effect.id));
    }
  }

  // ── Makeup Studio ───────────────────────────────────────────────────────

  static const customMakeupId = 'custom_makeup';

  /// The makeup currently on the face (built-in look, catalog look or the
  /// user's own edits), or null.
  ArMakeup? get activeMakeup => state.active['makeup']?.makeup;

  /// Keeps face tracking on while a tool is open, even with nothing applied.
  void setEffectPerPerson(bool on) {
    state = state.copyWith(effectPerPerson: on);
    unawaited(_syncStream());
  }

  /// Recolours clothes ([color] null turns it off).
  void setOutfit(Color? color, {double? strength}) {
    state = state.copyWith(outfitColor: () => color, outfitStrength: strength);
    unawaited(_syncStream());
  }

  void setPreviewFace(bool on) {
    if (state.previewFace == on) return;
    state = state.copyWith(previewFace: on);
    unawaited(_syncStream());
  }

  /// Toggles Smart Auto-Tracker (human face & body subject-follow framing).
  void setAutoTrack(bool on) {
    if (state.autoTrack == on) return;
    state = state.copyWith(autoTrack: on);
    unawaited(_syncStream());
  }

  /// Applies an edited makeup live; an empty makeup turns makeup off.
  void setMakeup(ArMakeup makeup, {String name = 'My makeup'}) {
    final active = {...state.active};
    if (makeup.isEmpty) {
      active.remove('makeup');
    } else {
      active['makeup'] = ArEffect(
        id: customMakeupId,
        name: name,
        kind: ArEffectKind.makeup,
        category: ArEffectCategory.makeup,
        anchor: ArAnchor.face,
        makeup: makeup,
        creatorUid: '',
        source: 'custom',
      );
    }
    state = state.copyWith(active: active);
    unawaited(_syncStream());
  }

  void remove(ArEffect effect) {
    final active = {...state.active}..removeWhere((_, e) => e.id == effect.id);
    var next = state.copyWith(active: active);
    if (effect.kind == ArEffectKind.background && state.backgroundLabel == effect.name) {
      next = next.copyWith(
        backgroundMode: ArBackgroundMode.none,
        backgroundImage: () => null,
        backgroundLabel: () => null,
        addYourself: false,
      );
    }
    state = next;
    if (effect.isWorld) world.value = {...world.value}..remove(effect.id);
    _syncGyro();
    unawaited(_syncStream());
  }

  void clearAll() {
    state = state.copyWith(
      active: const {},
      backgroundMode: ArBackgroundMode.none,
      backgroundImage: () => null,
      backgroundLabel: () => null,
      addYourself: false,
      personOffset: Offset.zero,
      personScale: 1,
      outfitColor: () => null,
      transparentBackground: false,
      backgroundVideoPath: () => null,
    );
    world.value = const {};
    _syncGyro();
    unawaited(_syncStream());
  }

  // ── Background ──────────────────────────────────────────────────────────

  void setBlur(bool on) {
    if (on) {
      final active = {...state.active}..remove('background');
      state = state.copyWith(
        active: active,
        backgroundMode: ArBackgroundMode.blur,
        backgroundImage: () => null,
        backgroundLabel: () => null,
        addYourself: false,
        transparentBackground: false,
        backgroundVideoPath: () => null,
      );
    } else if (state.backgroundMode == ArBackgroundMode.blur) {
      state = state.copyWith(backgroundMode: ArBackgroundMode.none);
    }
    unawaited(_syncStream());
  }

  /// Back to the real background (no blur, no scene).
  void clearBackground() {
    state = state.copyWith(
      active: {...state.active}..remove('background'),
      backgroundMode: ArBackgroundMode.none,
      backgroundImage: () => null,
      backgroundLabel: () => null,
      addYourself: false,
      personOffset: Offset.zero,
      personScale: 1,
      transparentBackground: false,
      backgroundVideoPath: () => null,
    );
    unawaited(_syncStream());
  }

  void setBlurSigma(double v) => state = state.copyWith(blurSigma: v.clamp(2.0, 40.0));

  /// A solid colour behind the person.
  Future<void> setBackgroundColor(Color color, {String label = 'Colour'}) async {
    final img = await _solidImage(color);
    state = state.copyWith(
      active: {...state.active}..remove('background'),
      backgroundMode: ArBackgroundMode.replace,
      backgroundImage: () => img,
      backgroundLabel: () => label,
      transparentBackground: false,
      backgroundVideoPath: () => null,
      addYourself: false,
      error: () => null,
    );
    unawaited(_syncStream());
  }

  /// Removes the background: transparent PNG photos, key-green videos. The
  /// preview shows a checkerboard.
  Future<void> setTransparentBackground() async {
    final img = await _checkerImage();
    state = state.copyWith(
      active: {...state.active}..remove('background'),
      backgroundMode: ArBackgroundMode.replace,
      backgroundImage: () => img,
      backgroundLabel: () => 'Transparent',
      transparentBackground: true,
      backgroundVideoPath: () => null,
      addYourself: false,
      error: () => null,
    );
    unawaited(_syncStream());
  }

  /// A looping video from the phone behind the person. Its first frame is
  /// the still used for photos.
  Future<void> setBackgroundVideo(String path, {ui.Image? firstFrame}) async {
    final still = firstFrame ?? await _solidImage(const Color(0xFF101014));
    state = state.copyWith(
      active: {...state.active}..remove('background'),
      backgroundMode: ArBackgroundMode.replace,
      backgroundImage: () => still,
      backgroundLabel: () => 'Your video',
      transparentBackground: false,
      backgroundVideoPath: () => path,
      addYourself: false,
      error: () => null,
    );
    unawaited(_syncStream());
  }

  static Future<ui.Image> _solidImage(Color c) {
    final rec = ui.PictureRecorder();
    Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = c);
    return rec.endRecording().toImage(8, 8);
  }

  static Future<ui.Image> _checkerImage() {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 9; x++) {
        canvas.drawRect(Rect.fromLTWH(x * 40.0, y * 40.0, 40, 40),
            Paint()..color = (x + y).isEven ? const Color(0xFFE6E6E6) : const Color(0xFFBDBDBD));
      }
    }
    return rec.endRecording().toImage(360, 640);
  }

  /// Uses a photo from the gallery as the scene behind the person.
  Future<void> setBackgroundFile(File file, {bool addYourself = false}) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1440);
      final img = (await codec.getNextFrame()).image;
      final active = {...state.active}..remove('background');
      state = state.copyWith(
        active: active,
        backgroundMode: ArBackgroundMode.replace,
        backgroundImage: () => img,
        backgroundLabel: () => 'Your photo',
        transparentBackground: false,
        backgroundVideoPath: () => null,
        addYourself: addYourself,
        personOffset: Offset.zero,
        personScale: addYourself ? 0.7 : 1,
        error: () => null,
      );
      unawaited(_syncStream());
    } catch (e) {
      state = state.copyWith(error: () => 'Could not open that photo.');
    }
  }

  void setAddYourself(bool on) {
    if (state.backgroundMode != ArBackgroundMode.replace) return;
    state = state.copyWith(
      addYourself: on,
      personOffset: Offset.zero,
      personScale: on ? 0.7 : 1,
    );
  }

  /// Pan/pinch from the viewfinder: moves the cut-out in "add yourself",
  /// otherwise the most recent world sticker.
  void onViewfinderGesture(Offset deltaNormalized, double scaleFactor, double rotation) {
    if (state.addYourself) {
      state = state.copyWith(
        personOffset: state.personOffset + deltaNormalized,
        personScale: (state.personScale * scaleFactor).clamp(0.25, 2.0),
      );
      return;
    }
    if (world.value.isEmpty) return;
    final id = world.value.keys.last;
    final p = world.value[id]!;
    world.value = {
      ...world.value,
      id: p.copyWith(
        position: p.position + deltaNormalized,
        scale: (p.scale * scaleFactor).clamp(0.2, 4.0),
        rotation: p.rotation + rotation,
      ),
    };
  }

  bool get handlesGestures => state.addYourself || world.value.isNotEmpty;

  // ── World tracking (3DoF from the gyroscope) ────────────────────────────

  void _syncGyro() {
    final want = state.active.values.any((e) => e.isWorld);
    if (want && _gyro == null) {
      _lastGyro = null;
      _gyro = gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval).listen(_onGyro);
    } else if (!want && _gyro != null) {
      _gyro?.cancel();
      _gyro = null;
    }
  }

  void _onGyro(GyroscopeEvent e) {
    final now = e.timestamp;
    final last = _lastGyro;
    _lastGyro = now;
    if (last == null || world.value.isEmpty) return;
    final dt = now.difference(last).inMicroseconds / 1e6;
    if (dt <= 0 || dt > 0.1) return;
    // Turning the phone moves the scene the other way across the screen:
    // yaw (device y axis) shifts x, pitch (device x axis) shifts y, roll
    // (z axis) spins it. Focal lengths are for a ~55° portrait field of view.
    const fx = 1.0;
    const fy = 0.56;
    final front = _native != null ? _nativeMirror : _description?.lensDirection == CameraLensDirection.front;
    final mirror = front ? -1.0 : 1.0;
    final dx = e.y * dt * fx * mirror;
    final dy = e.x * dt * fy;
    final dr = -e.z * dt;
    final c = math.cos(dr);
    final s = math.sin(dr);
    world.value = {
      for (final entry in world.value.entries)
        entry.key: () {
          final p = entry.value;
          final rel = p.position - const Offset(0.5, 0.5);
          final rotated = Offset(rel.dx * c - rel.dy * s, rel.dx * s + rel.dy * c);
          return p.copyWith(
            position: rotated + const Offset(0.5, 0.5) + Offset(dx, dy),
            rotation: p.rotation + dr,
          );
        }(),
    };
  }

  // ── Photo baking ────────────────────────────────────────────────────────

  /// Re-tracks the still photo and draws the active effects into it.
  /// Returns the new file's path, or null when nothing is active.
  Future<String?> bakePhoto(String path) async {
    if (!state.hasAnything) return null;
    final bytes = await File(path).readAsBytes();
    final photo = (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
    final size = Size(photo.width.toDouble(), photo.height.toDouble());
    final tracked = await _tracker.processFile(path, size, state.needs);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Offset.zero & size;
    final mask = tracked.mask;
    final s = state;

    /// Skin smoothing, same as the live viewfinder.
    void smoothSkin() {
      final amount = s.active['makeup']?.makeup.smoothing ?? 0;
      if (amount <= 0) return;
      final sigma = size.width / 360 * 1.6;
      for (final f in tracked.faces) {
        final skin = ArEffectPainter.skinPath(f, size);
        if (skin == null) continue;
        canvas.save();
        canvas.clipPath(skin);
        canvas.drawImage(
          photo,
          Offset.zero,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma)
            ..color = Color.fromRGBO(0, 0, 0, (amount * 0.8).clamp(0.0, 1.0)),
        );
        canvas.restore();
      }
    }

    void person() {
      if (s.addYourself) {
        canvas.save();
        canvas.translate(
          size.width * (0.5 + s.personOffset.dx),
          size.height * (0.5 + s.personOffset.dy),
        );
        canvas.scale(s.personScale);
        canvas.translate(-size.width / 2, -size.height / 2);
      }
      canvas.saveLayer(rect, Paint());
      canvas.drawImage(photo, Offset.zero, Paint());
      smoothSkin();
      canvas.drawImageRect(
        mask!.image,
        Rect.fromLTWH(0, 0, mask.width.toDouble(), mask.height.toDouble()),
        rect,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
      ArEffectPainter.paintEffects(canvas, size, tracked, s.effects, s.images, world.value, perPerson: s.effectPerPerson);
      if (s.addYourself) canvas.restore();
    }

    if (s.backgroundMode != ArBackgroundMode.none && mask != null) {
      if (s.backgroundMode == ArBackgroundMode.blur) {
        final sigma = s.blurSigma * size.width / 400;
        canvas.drawImage(
          photo,
          Offset.zero,
          Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        );
      } else if (s.transparentBackground) {
        // Nothing behind the person: the PNG keeps the transparency.
      } else if (s.backgroundImage != null) {
        _drawCover(canvas, s.backgroundImage!, rect);
      }
      person();
    } else {
      canvas.drawImage(photo, Offset.zero, Paint());
      smoothSkin();
      ArEffectPainter.paintEffects(canvas, size, tracked, s.effects, s.images, world.value, perPerson: s.effectPerPerson);
    }

    final out = await recorder.endRecording().toImage(photo.width, photo.height);
    final png = await out.toByteData(format: ui.ImageByteFormat.png);
    photo.dispose();
    out.dispose();
    mask?.dispose();
    if (png == null) return null;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/oneova_ar_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));
    return file.path;
  }

  static void _drawCover(Canvas canvas, ui.Image img, Rect dst) {
    final iw = img.width.toDouble();
    final ih = img.height.toDouble();
    final scale = math.max(dst.width / iw, dst.height / ih);
    final sw = dst.width / scale;
    final sh = dst.height / scale;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH((iw - sw) / 2, (ih - sh) / 2, sw, sh),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  /// Downloads a 3D model once and keeps it on the phone (by URL).
  static Future<String> _downloadModel(String id, String url) async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/ar_models');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File('${dir.path}/${safeId}_${url.hashCode.toUnsigned(32)}.glb');
    if (file.existsSync() && file.lengthSync() > 0) return file.path;
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    final bytes = res.bodyBytes;
    // glTF binaries start with "glTF"; refuse anything else (and huge files).
    if (bytes.length < 12 || bytes.length > 40 * 1024 * 1024 ||
        bytes[0] != 0x67 || bytes[1] != 0x6C || bytes[2] != 0x54 || bytes[3] != 0x46) {
      throw const FormatException('Not a glTF binary');
    }
    final tmp = File('${file.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
    return file.path;
  }

  static Future<ui.Image> _loadImage(String url) {
    final completer = Completer<ui.Image>();
    final stream = CachedNetworkImageProvider(url).resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        completer.complete(info.image.clone());
        stream.removeListener(listener);
      },
      onError: (e, st) {
        completer.completeError(e, st);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }
}

final liveArControllerProvider =
    NotifierProvider<LiveArController, LiveArState>(LiveArController.new);
