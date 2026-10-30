import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:oneova_media_engine/oneova_media_engine.dart';

import '../models/studio_project.dart';
import 'studio_color.dart';
import 'studio_project_store.dart';
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

class StudioRenderer {
  StudioRenderer._();

  /// Renders a video project to an MP4 and returns its path.
  static Future<String> exportVideo(StudioProject project, StudioVideoSettings s) async {
    final work = await StudioProjectStore.dir('render/${project.id}');
    final size = studioCanvasSize(project.canvasAspect, s.shortSide);
    final pngs = <String, String>{};
    for (final t in project.texts) {
      pngs[t.id] = (await StudioTextPainter.toPng(t, size.width, '${work.path}/text_${t.id}.png')).path;
    }

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
        overlays.add({
          'png': pngs[t.id],
          // Layer center in NDC (y up), kept fully on the frame like the preview.
          'x': t.x.clamp(-xMax, xMax),
          'y': -t.y.clamp(-yMax, yMax),
          'startMs': math.max(0, t.startMs - clipStart),
          'endMs': math.min(t.endMs, clipEnd) - clipStart,
        });
      }
      final matrix = StudioColor.clipMatrix(c);
      clips.add({
        'path': c.path,
        'image': c.isImage,
        'startMs': c.startMs,
        'endMs': c.endMs,
        'durationMs': c.imageDurationMs,
        'speed': c.speed,
        'volume': c.volume,
        'mute': c.muted || !c.hasAudio,
        if (!StudioColor.isIdentity(matrix)) 'matrix': matrix,
        if (!c.crop.isFull) 'crop': c.crop.toJson(),
        'rotation': c.rotation,
        'flipH': c.flipH,
        'flipV': c.flipV,
        'zoom': c.zoom,
        'fill': c.fill,
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

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    paintClipFrame(canvas, size, clip, src);
    for (final t in project.texts) {
      final layer = StudioTextPainter.measure(t, size.width);
      final cx = (t.x + 1) / 2 * size.width;
      final cy = (t.y + 1) / 2 * size.height;
      canvas.save();
      canvas.translate(
        (cx - layer.width / 2).clamp(0.0, math.max(0.0, size.width - layer.width)),
        (cy - layer.height / 2).clamp(0.0, math.max(0.0, size.height - layer.height)),
      );
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
