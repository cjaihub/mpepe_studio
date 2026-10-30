import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:oneova_media_engine/oneova_media_engine.dart';

import '../models/studio_project.dart';
import '../screens/studio_media_picker_screen.dart';
import 'studio_project_store.dart';

bool studioIsImagePath(String path) {
  final p = path.toLowerCase();
  return p.endsWith('.jpg') || p.endsWith('.jpeg') || p.endsWith('.png') || p.endsWith('.webp') || p.endsWith('.heic');
}

class StudioMedia {
  StudioMedia._();

  /// Reads a file's real size/length/fps and wraps it as a clip.
  static Future<StudioClip> clipFromFile(String path, {bool? isImage, int startMs = 0, int? endMs}) async {
    final image = isImage ?? studioIsImagePath(path);
    if (image) {
      final size = await imageSize(path);
      return StudioClip.create(path: path, isImage: true, durationMs: 0, width: size.$1, height: size.$2);
    }
    final probe = await OneovaMediaEngine.probe(path);
    final dur = probe.duration.inMilliseconds;
    return StudioClip.create(
      path: path,
      isImage: false,
      durationMs: dur,
      width: probe.width,
      height: probe.height,
      fps: probe.fps > 0 ? probe.fps : 30,
      hasAudio: probe.hasAudio,
      startMs: startMs.clamp(0, dur),
      endMs: (endMs == null || endMs <= startMs) ? dur : math.min(endMs, dur),
    );
  }

  static Future<List<StudioClip>> clipsFromPicks(List<StudioPick> picks) async {
    final out = <StudioClip>[];
    for (final p in picks) {
      try {
        out.add(await clipFromFile(p.path, isImage: p.isImage, startMs: p.startMs, endMs: p.endMs));
      } catch (e) {
        debugPrint('[StudioMedia] skipping ${p.path}: $e');
      }
    }
    return out;
  }

  static Future<(int, int)> imageSize(String path) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(await File(path).readAsBytes());
    final desc = await ui.ImageDescriptor.encoded(buffer);
    final size = (desc.width, desc.height);
    desc.dispose();
    buffer.dispose();
    return size;
  }

  static final Map<String, Future<List<String>>> _thumbs = {};

  /// About one frame per second of the source (max 40), for the timeline strip.
  static Future<List<String>> thumbnails(StudioClip clip) {
    if (clip.isImage) return Future.value([clip.path]);
    return _thumbs[clip.path] ??= () async {
      final dir = await StudioProjectStore.dir('thumbs/strip');
      final count = (clip.sourceDurationMs / 1000).ceil().clamp(1, 40);
      try {
        return await OneovaMediaEngine.thumbnails(clip.path, outDir: dir.path, count: count, height: 120);
      } catch (e) {
        _thumbs.remove(clip.path);
        return <String>[];
      }
    }();
  }
}
