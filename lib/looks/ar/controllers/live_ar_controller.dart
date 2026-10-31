import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/ar_effect.dart';
import '../render/ar_effect_painter.dart';
import '../services/ar_effect_repository.dart';
import '../tracking/ar_tracking_models.dart';
import '../tracking/ar_tracking_service.dart';

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
  });

  List<ArEffect> get effects => active.values.toList(growable: false);
  bool get hasAnything => active.isNotEmpty || backgroundMode != ArBackgroundMode.none;
  bool isActive(String id) => active.values.any((e) => e.id == id);

  ArTrackingNeeds get needs => ArTrackingNeeds(
        face: active.values.any((e) => e.needsFace),
        body: active.values.any((e) => e.needsBody),
        mask: backgroundMode != ArBackgroundMode.none,
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
      );
}

/// Runs live AR effects for the camera: owns the frame stream into ML Kit,
/// the active effects and their decoded images, background modes and the
/// gyro-locked world stickers.
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

  @override
  LiveArState build() {
    ref.onDispose(() {
      _gyro?.cancel();
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
    if (effect.kind != ArEffectKind.makeup) {
      final url = effect.assetUrl;
      if (url == null) {
        state = state.copyWith(error: () => 'This effect has no image yet.');
        return;
      }
      state = state.copyWith(loading: {...state.loading, effect.id}, error: () => null);
      try {
        final img = state.images[effect.id] ?? await _loadImage(url);
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
    unawaited(ref.read(arEffectRepositoryProvider).recordUse(effect.id));
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
    );
    unawaited(_syncStream());
  }

  void setBlurSigma(double v) => state = state.copyWith(blurSigma: v.clamp(2.0, 40.0));

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
    final mirror = _description?.lensDirection == CameraLensDirection.front ? -1.0 : 1.0;
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
      canvas.drawImageRect(
        mask!.image,
        Rect.fromLTWH(0, 0, mask.width.toDouble(), mask.height.toDouble()),
        rect,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
      ArEffectPainter.paintEffects(canvas, size, tracked, s.effects, s.images, world.value);
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
      } else if (s.backgroundImage != null) {
        _drawCover(canvas, s.backgroundImage!, rect);
      }
      person();
    } else {
      canvas.drawImage(photo, Offset.zero, Paint());
      ArEffectPainter.paintEffects(canvas, size, tracked, s.effects, s.images, world.value);
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
