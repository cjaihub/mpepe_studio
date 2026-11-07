import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:oneova_media_engine/oneova_media_engine.dart';

import '../../../shared/theme/app_theme.dart';

import '../../../looks/models/oneova_look.dart';
import '../models/studio_project.dart';
import 'studio_color.dart';
import 'studio_effects.dart';
import 'studio_faces.dart';
import 'studio_looks.dart';
import 'studio_project_store.dart';
import 'studio_text_animator.dart';
import 'studio_text_painter.dart';

/// Video output picked in the export sheet.
class StudioVideoSettings {
  final int shortSide;
  final int fps;
  final int bitrate;
  const StudioVideoSettings({required this.shortSide, required this.fps, required this.bitrate});
}

/// Output size for a canvas aspect (w/h) and short side, kept even for the encoder.
Size studioCanvasSize(double aspect, int shortSide) {
  int even(double v) => (v / 2).round() * 2;
  if (aspect <= 1) return Size(shortSide.toDouble(), even(shortSide / aspect).toDouble());
  return Size(even(shortSide * aspect).toDouble(), shortSide.toDouble());
}

/// Bitmaps and keyframes of one text layer for the native overlay.
class _TextLayerRender {
  final List<String> frames;
  final double sampleMs;
  final Float32List? samples;
  const _TextLayerRender(this.frames, this.sampleMs, this.samples);
}

class StudioRenderer {
  StudioRenderer._();

  /// Most distinct bitmaps one animated layer may use (reveal steps, words).
  static const _maxFrames = 160;

  /// Renders [t]'s bitmaps and samples its animation every [sampleMs] of
  /// layer time with the same animator the preview uses.
  static Future<_TextLayerRender> _renderText(StudioText t, Size size, String dir, double sampleMs) async {
    final animated = StudioTextAnimator.isAnimated(t);
    if (!animated) {
      final png = await StudioTextPainter.toPng(t, size.width, '$dir/text_${t.id}.png');
      if (t.rotation == 0) return _TextLayerRender([png.path], 0, null);
      return _TextLayerRender([png.path], 1e9, Float32List.fromList([1, 1, 1, 0, 0, t.rotation, 0]));
    }
    final frames = <String>[];
    final index = <String, int>{};
    final int dur = math.max(1, t.endMs - t.startMs);
    final count = (dur / sampleMs).ceil() + 1;
    final samples = Float32List(count * 7);
    for (var i = 0; i < count; i++) {
      final int ms = t.startMs + math.min(dur, (i * sampleMs).round());
      final f = StudioTextAnimator.at(t, ms);
      final reveal = StudioTextReveal.of(t, ms, f);
      var idx = index[reveal.key];
      if (idx == null) {
        if (frames.length >= _maxFrames) {
          idx = frames.length - 1;
        } else {
          final png = await StudioTextPainter.toPng(t, size.width, '$dir/text_${t.id}_${frames.length}.png', reveal: reveal);
          frames.add(png.path);
          idx = frames.length - 1;
          index[reveal.key] = idx;
        }
      }
      final o = i * 7;
      samples[o] = f.alpha.clamp(0.0, 1.0);
      samples[o + 1] = f.sx;
      samples[o + 2] = f.sy;
      // Canvas fractions (y down) -> NDC (y up).
      samples[o + 3] = f.dx * 2;
      samples[o + 4] = -f.dy * 2;
      samples[o + 5] = f.rot;
      samples[o + 6] = idx.toDouble();
    }
    return _TextLayerRender(frames, sampleMs, samples);
  }

  /// Renders a video project to an MP4 and returns its path.
  static Future<String> exportVideo(StudioProject project, StudioVideoSettings s) async {
    final work = await StudioProjectStore.dir('render/${project.id}');
    final size = studioCanvasSize(project.canvasAspect, s.shortSide);
    await StudioTextPainter.ensureFonts(project.texts);
    final sampleMs = 1000 / math.max(30, s.fps > 0 ? s.fps : 30);
    final layers = <String, _TextLayerRender>{};
    for (final t in project.texts) {
      layers[t.id] = await _renderText(t, size, work.path, sampleMs);
    }

    final lookSpecs = <String, Map<String, Object?>>{};
    final clips = <Map<String, Object?>>[];
    var clipStart = 0;
    for (final c in project.clips) {
      final clipEnd = clipStart + c.outDurationMs;
      final overlays = <Map<String, Object?>>[];
      for (final t in project.texts) {
        if (t.endMs <= clipStart || t.startMs >= clipEnd) continue;
        final layer = StudioTextPainter.measure(t, size.width);
        final xMax = (1 - layer.width / size.width).clamp(0.0, 1.0);
        final yMax = (1 - layer.height / size.height).clamp(0.0, 1.0);
        final r = layers[t.id]!;
        overlays.add({
          'frames': r.frames,
          // Layer center in NDC (y up), kept fully on the frame like the preview.
          'x': t.x.clamp(-xMax, xMax),
          'y': -t.y.clamp(-yMax, yMax),
          'startMs': math.max(0, t.startMs - clipStart),
          'endMs': math.min(t.endMs, clipEnd) - clipStart,
          'layerOffsetMs': clipStart - t.startMs,
          if (r.samples != null) 'sampleMs': r.sampleMs,
          if (r.samples != null) 'samples': r.samples,
        });
      }
      final matrix = StudioColor.clipMatrix(c);
      Map<String, Object?>? retouch;
      if (!c.retouch.isIdentity) {
        StudioFaceTrack? track;
        try {
          track = await StudioFaceTracker.track(c);
        } catch (e) {
          debugPrint('[StudioRenderer] face tracking failed: $e');
        }
        retouch = StudioFaceTracker.exportSpec(c, track);
      }
      final look = StudioLooks.forClip(c);
      Map<String, Object?>? lookSpec;
      if (look != null) lookSpec = lookSpecs[look.id] ??= await StudioLooks.exportSpec(look);
      clips.add({
        'path': c.path,
        'image': c.isImage,
        'hasAudio': c.hasAudio,
        'startMs': c.startMs,
        'endMs': c.endMs,
        'durationMs': c.imageDurationMs,
        'speed': c.speed,
        'volume': c.volume,
        'mute': c.muted || !c.hasAudio,
        if (c.voiceClean > 0) 'voiceClean': c.voiceClean,
        if (!StudioColor.isIdentity(matrix)) 'matrix': matrix,
        'look': ?lookSpec,
        'retouch': ?retouch,
        if (!c.crop.isFull) 'crop': c.crop.toJson(),
        'rotation': c.rotation,
        'flipH': c.flipH,
        'flipV': c.flipV,
        'zoom': c.zoom,
        'fill': c.fill,
        'fxPasses': StudioEffects.exportPasses(project.effects, clipStart, clipEnd),
        'overlays': overlays,
      });
      clipStart = clipEnd;
    }

    final total = project.durationMs;
    final audio = [
      for (final a in project.audios)
        if (a.offsetMs < total)
          {
            'path': a.path,
            'startMs': a.startMs,
            'endMs': a.startMs + math.min(a.durationMs, total - a.offsetMs),
            'offsetMs': a.offsetMs,
            'volume': a.volume,
          },
    ];

    final exports = await StudioProjectStore.dir('exports');
    return OneovaMediaEngine.export({
      'output': '${exports.path}/oneova_${DateTime.now().millisecondsSinceEpoch}.mp4',
      'width': size.width.toInt(),
      'height': size.height.toInt(),
      'fps': s.fps,
      'bitrate': s.bitrate,
      'clips': clips,
      'audio': audio,
    });
  }

  /// Writes the timeline's clip audio (trims and speed applied, photos as
  /// silence) as mono 16 kHz AAC for speech recognition.
  static Future<String> exportSpeechAudio(StudioProject project) async {
    final dir = await StudioProjectStore.dir('speech');
    return OneovaMediaEngine.export({
      'output': '${dir.path}/speech_${project.id}_${DateTime.now().millisecondsSinceEpoch}.m4a',
      'audioOnly': true,
      'width': 0,
      'height': 0,
      'fps': 0,
      'bitrate': 0,
      'clips': [
        for (final c in project.clips)
          {
            'path': c.path,
            'image': c.isImage,
            'hasAudio': c.hasAudio,
            'startMs': c.startMs,
            'endMs': c.endMs,
            'durationMs': c.imageDurationMs,
            'speed': c.speed,
          },
      ],
      'audio': const [],
    });
  }

  /// Converts a video the preview player can't open into H.264/AAC MP4 at its
  /// own size (Media3 has wider container support than the platform player).
  static Future<String> transcodeForEditing(String path, {bool hasAudio = true}) async {
    final dir = await StudioProjectStore.dir('media');
    return OneovaMediaEngine.export({
      'output': '${dir.path}/converted_${DateTime.now().millisecondsSinceEpoch}.mp4',
      'width': 0,
      'height': 0,
      'fps': 0,
      'bitrate': 0,
      'clips': [
        {'path': path, 'image': false, 'startMs': 0, 'endMs': 0, 'speed': 1.0, 'volume': 1.0, 'mute': !hasAudio, 'overlays': const []},
      ],
      'audio': const [],
    });
  }

  /// Renders the first clip of a photo project (crop, rotate, color, canvas,
  /// text) to a JPEG with its long side at most [maxLongSide].
  static Future<String> exportPhoto(StudioProject project, {int maxLongSide = 2160, int quality = 92}) async {
    final clip = project.clips.first;
    final bytes = await File(clip.path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final src = frame.image;

    final aspect = project.canvasAspect;
    final srcLong = math.max(src.width * (clip.crop.r - clip.crop.l), src.height * (clip.crop.b - clip.crop.t));
    final long = math.min(maxLongSide.toDouble(), srcLong).roundToDouble();
    final size = aspect >= 1 ? Size(long, (long / aspect).roundToDouble()) : Size((long * aspect).roundToDouble(), long);

    await StudioTextPainter.ensureFonts(project.texts);
    final look = StudioLooks.forClip(clip);
    final lookProgram = look == null ? null : await StudioLooks.program();
    final fxProgram = project.effects.isEmpty ? null : await StudioEffects.program();
    final shaders = ui.ImageFilter.isShaderFilterSupported;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & size);
    final fx = [
      for (final e in project.effects)
        if (StudioEffects.byId(e.effectId) != null && e.amount > 0) e,
    ];
    final fxLayers = <ui.FragmentShader>[];
    if (shaders && fxProgram != null) {
      for (final e in fx.reversed) {
        final shader = fxProgram.fragmentShader()
          ..setFloat(2, StudioEffects.byId(e.effectId)!.type.toDouble())
          ..setFloat(3, e.amount)
          ..setFloat(4, 0)
          ..setFloat(5, 1);
        fxLayers.add(shader);
        canvas.saveLayer(Offset.zero & size, Paint()..imageFilter = ui.ImageFilter.shader(shader));
      }
    }
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.brandBlack);
    await _paintGraded(canvas, size, clip, src, look, shaders ? lookProgram : null);
    for (var i = 0; i < fxLayers.length; i++) {
      canvas.restore();
    }
    for (final t in project.texts) {
      final layer = StudioTextPainter.measure(t, size.width);
      final cx = (t.x + 1) / 2 * size.width;
      final cy = (t.y + 1) / 2 * size.height;
      final left = (cx - layer.width / 2).clamp(0.0, math.max(0.0, size.width - layer.width));
      final top = (cy - layer.height / 2).clamp(0.0, math.max(0.0, size.height - layer.height));
      canvas.save();
      canvas.translate(left + layer.width / 2, top + layer.height / 2);
      if (t.rotation != 0) canvas.rotate(t.rotation * math.pi / 180);
      canvas.translate(-layer.width / 2, -layer.height / 2);
      StudioTextPainter.paint(canvas, t, size.width);
      canvas.restore();
    }
    final picture = recorder.endRecording();
    final out = await picture.toImage(size.width.toInt(), size.height.toInt());
    final rgba = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = out.width, h = out.height;
    out.dispose();
    picture.dispose();
    src.dispose();

    final jpg = await compute(_encodeJpg, _JpgJob(rgba!.buffer.asUint8List(), w, h, quality));
    final exports = await StudioProjectStore.dir('exports');
    final file = File('${exports.path}/oneova_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await file.writeAsBytes(jpg, flush: true);
    return file.path;
  }

  /// [paintClipFrame] through the clip's Look (same shader as the preview).
  static Future<void> _paintGraded(
    Canvas canvas,
    Size size,
    StudioClip clip,
    ui.Image image,
    OneovaLook? look,
    ui.FragmentProgram? program,
  ) async {
    if (!clip.retouch.isIdentity && ui.ImageFilter.isShaderFilterSupported) {
      final rp = await StudioFaceTracker.program();
      if (rp != null) {
        StudioFaceTrack? track;
        try {
          track = await StudioFaceTracker.track(clip);
        } catch (_) {}
        final rs = rp.fragmentShader();
        StudioFaceTracker.bind(rs, clip.retouch, _facesOnCanvas(StudioFaceTracker.shaderAt(clip, track, 0), clip, image, size));
        // The retouch sits under the Look, like in the preview.
        canvas.saveLayer(Offset.zero & size, Paint()..imageFilter = ui.ImageFilter.shader(rs));
        await _paintGraded(canvas, size, clip.copyWith(retouch: const StudioRetouch()), image, look, program);
        canvas.restore();
        return;
      }
    }
    if (look == null || program == null) {
      paintClipFrame(canvas, size, clip, image);
      return;
    }
    final spec = await StudioLooks.exportSpec(look);
    final values = spec['uniforms'] as Float32List;
    final compiled = await StudioLooks.compiled(look);
    final shader = program.fragmentShader();
    for (var i = 2; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }
    shader.setImageSampler(1, compiled.lutAtlas);
    shader.setImageSampler(2, compiled.curves);
    canvas.saveLayer(Offset.zero & size, Paint()..imageFilter = ui.ImageFilter.shader(shader));
    paintClipFrame(canvas, size, clip, image);
    canvas.restore();
  }

  /// Moves face data from the clip's frame onto the export canvas (same fit,
  /// fill and zoom as [paintClipFrame]).
  static List<double> _facesOnCanvas(List<double> f, StudioClip clip, ui.Image image, Size canvas) {
    final cw = image.width * (clip.crop.r - clip.crop.l), ch = image.height * (clip.crop.b - clip.crop.t);
    final turned = clip.rotation % 180 != 0;
    final w = turned ? ch : cw, h = turned ? cw : ch;
    final fit = clip.fill ? math.max(canvas.width / w, canvas.height / h) : math.min(canvas.width / w, canvas.height / h);
    final sw = w * fit * clip.zoom, sh = h * fit * clip.zoom;
    final left = (canvas.width - sw) / 2, top = (canvas.height - sh) / 2;
    double x(double v) => (left + v * sw) / canvas.width;
    double y(double v) => (top + v * sh) / canvas.height;
    final out = [...f];
    for (var b = 0; b < 32; b += 16) {
      if (out[b] < 0.5) continue;
      // [valid, cx, cy, rx] [ry, lex, ley, rex] [rey, nx, ny, mx] [my, mw, 0, 0]
      out[b + 1] = x(f[b + 1]);
      out[b + 2] = y(f[b + 2]);
      out[b + 3] = f[b + 3] * sw / canvas.width;
      out[b + 4] = f[b + 4] * sh / canvas.height;
      out[b + 5] = x(f[b + 5]);
      out[b + 6] = y(f[b + 6]);
      out[b + 7] = x(f[b + 7]);
      out[b + 8] = y(f[b + 8]);
      out[b + 9] = x(f[b + 9]);
      out[b + 10] = y(f[b + 10]);
      out[b + 11] = x(f[b + 11]);
      out[b + 12] = y(f[b + 12]);
      out[b + 13] = f[b + 13] * sw / canvas.width;
    }
    return out;
  }

  /// Draws [image] the way the preview shows [clip]: crop, rotate/flip,
  /// color, then fit or fill into [canvas], then zoom.
  static void paintClipFrame(Canvas canvas, Size canvasSize, StudioClip clip, ui.Image image) {
    final crop = Rect.fromLTRB(
      clip.crop.l * image.width,
      clip.crop.t * image.height,
      clip.crop.r * image.width,
      clip.crop.b * image.height,
    );
    final turned = clip.rotation % 180 != 0;
    final contentW = turned ? crop.height : crop.width;
    final contentH = turned ? crop.width : crop.height;
    final fit = clip.fill
        ? math.max(canvasSize.width / contentW, canvasSize.height / contentH)
        : math.min(canvasSize.width / contentW, canvasSize.height / contentH);
    final scale = fit * clip.zoom;

    canvas.save();
    canvas.clipRect(Offset.zero & canvasSize);
    canvas.translate(canvasSize.width / 2, canvasSize.height / 2);
    canvas.scale(scale);
    canvas.rotate(clip.rotation * math.pi / 180);
    canvas.scale(clip.flipH ? -1 : 1, clip.flipV ? -1 : 1);
    final matrix = StudioColor.clipMatrix(clip);
    final paint = Paint()..filterQuality = FilterQuality.high;
    if (!StudioColor.isIdentity(matrix)) paint.colorFilter = ColorFilter.matrix(matrix);
    canvas.drawImageRect(image, crop, Rect.fromCenter(center: Offset.zero, width: crop.width, height: crop.height), paint);
    canvas.restore();
  }
}

class _JpgJob {
  final Uint8List rgba;
  final int width;
  final int height;
  final int quality;
  const _JpgJob(this.rgba, this.width, this.height, this.quality);
}

Uint8List _encodeJpg(_JpgJob job) {
  final image = img.Image.fromBytes(
    width: job.width,
    height: job.height,
    bytes: job.rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: job.quality);
}
