import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:oneova_media_engine/oneova_media_engine.dart';

import '../models/studio_project.dart';
import '../widgets/studio_export_sheet.dart';
import 'studio_project_store.dart';
import 'studio_renderer.dart';

/// Export add-ons on top of [StudioRenderer]: the corner watermark and GIF.
class StudioExportExtras {
  StudioExportExtras._();

  /// [project] with a small corner mark for its whole length.
  static StudioProject withWatermark(StudioProject project, {String? handle}) {
    final h = handle?.trim() ?? '';
    final mark = StudioText.create(
      text: h.isEmpty ? 'Oneova' : 'Oneova · $h',
      startMs: 0,
      endMs: math.max(1, project.durationMs),
      type: const StudioTypeStyle(
        weight: 800,
        color: 0xD9FFFFFF,
        shadowColor: 0x99000000,
        shadowBlur: 6,
        shadowDy: 1,
        letterSpacing: 0.4,
      ),
    ).copyWith(x: 0.62, y: 0.9, size: 0.034);
    return project.copyWith(texts: [...project.texts, mark]);
  }

  /// Renders a small MP4, samples frames and encodes a looping GIF.
  static Future<String> exportGif(
    StudioProject project,
    StudioGifSettings s, {
    void Function(double)? onProgress,
  }) async {
    final aspect = project.canvasAspect;
    final short = aspect >= 1 ? (s.longSide / aspect).round() : (s.longSide * aspect).round();
    final even = (math.max(160, short) ~/ 2) * 2;
    final mp4 = await StudioRenderer.exportVideo(
      project,
      StudioVideoSettings(shortSide: even, fps: 30, bitrate: 2500000),
    );
    onProgress?.call(0.6);
    final ms = math.min(project.durationMs, StudioGifSettings.maxMs);
    final step = 1000 / s.fps;
    final times = [for (var t = 0.0; t < ms; t += step) t.round()];
    final dir = await StudioProjectStore.dir('exports');
    final frameDir = Directory('${dir.path}/gif_${DateTime.now().millisecondsSinceEpoch}')..createSync(recursive: true);
    final frames = await OneovaMediaEngine.frames(mp4, timesMs: times, outDir: frameDir.path, maxSide: s.longSide);
    onProgress?.call(0.75);
    final out = '${dir.path}/Oneova_${DateTime.now().millisecondsSinceEpoch}.gif';
    final delayCs = (100 / s.fps).round();
    await Isolate.run(() {
      final enc = img.GifEncoder(repeat: 0, samplingFactor: 10);
      for (final f in frames) {
        if (f.isEmpty) continue;
        final im = img.decodeJpg(File(f).readAsBytesSync());
        if (im == null) continue;
        enc.addFrame(im, duration: delayCs);
      }
      final bytes = enc.finish();
      if (bytes == null) throw StateError('No frames to encode');
      File(out).writeAsBytesSync(bytes);
    });
    try {
      frameDir.deleteSync(recursive: true);
      File(mp4).deleteSync();
    } catch (_) {}
    onProgress?.call(1);
    return out;
  }
}
