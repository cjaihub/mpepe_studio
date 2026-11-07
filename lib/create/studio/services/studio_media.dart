import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:oneova_media_engine/oneova_media_engine.dart';

import '../models/studio_project.dart';
import '../screens/studio_media_picker_screen.dart';
import 'studio_project_store.dart';
import 'studio_renderer.dart';

const _imageExts = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'avif', 'gif', 'bmp', 'dng', 'jfif'};

/// Image formats Flutter and Media3 both read directly; others are converted.
const _directImageExts = {'jpg', 'jpeg', 'png', 'webp', 'jfif'};

String _ext(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

bool studioIsImagePath(String path) => _imageExts.contains(_ext(path));

/// A file Studio can't open, with a message for the user.
class StudioMediaException implements Exception {
  final String message;
  const StudioMediaException(this.message);
  @override
  String toString() => message;
}

/// Clips that opened plus what happened to the others.
class StudioImportResult {
  final List<StudioClip> clips;

  /// Files that could not be opened, with the reason.
  final List<String> problems;

  /// Files that opened with a change worth knowing (converted, still frame).
  final List<String> notes;
  const StudioImportResult(this.clips, this.problems, this.notes);

  String? get message {
    final lines = [...problems, ...notes];
    if (lines.isEmpty) return null;
    return lines.length == 1 ? lines.first : '${lines.first} (+${lines.length - 1} more)';
  }
}

class StudioMedia {
  StudioMedia._();

  static String _name(String path) => path.split('/').last;

  /// Reads a file's real size/length/fps and wraps it as a clip. Images in
  /// formats the editor can't draw directly (HEIC/HEIF, AVIF, GIF, BMP, DNG,
  /// very large photos) are converted to an upright JPEG/PNG first. Videos in
  /// containers the player can't read are converted to MP4 with Media3.
  /// [notes] collects what changed. Throws [StudioMediaException].
  static Future<StudioClip> clipFromFile(
    String path, {
    bool? isImage,
    int startMs = 0,
    int? endMs,
    List<String>? notes,
    void Function(double progress)? onConvert,
    bool allowVideo = true,
  }) async {
    if (!await File(path).exists()) throw StudioMediaException('${_name(path)} is no longer on this phone.');
    final image = isImage ?? studioIsImagePath(path);
    if (image) return _imageClip(path, notes, allowVideo: allowVideo);

    final info = await OneovaMediaEngine.inspect(path);
    if (info.readable) {
      final video = info.video.toList();
      if (video.isEmpty) {
        if (info.audio.isNotEmpty) throw StudioMediaException('${_name(path)} is audio only. Add it from Audio.');
        throw StudioMediaException('${_name(path)} has no picture to edit.');
      }
      final bad = video.where((t) => !t.decodable).firstOrNull;
      if (bad != null && !await _canGrabFrame(path)) {
        throw StudioMediaException('${_name(path)} uses ${bad.codecName} video, which this phone can\'t decode.');
      }
      final badAudio = info.audio.where((t) => !t.decodable).firstOrNull;
      if (badAudio != null) notes?.add('${_name(path)}: ${badAudio.codecName} sound can\'t be played on this phone, so it was left out.');
      try {
        final probe = await OneovaMediaEngine.probe(path);
        if (probe.hasVideo && probe.width > 0 && probe.duration.inMilliseconds > 0) {
          return _videoClip(path, probe, startMs, endMs, keepAudio: badAudio == null);
        }
      } catch (e) {
        debugPrint('[StudioMedia] probe failed for $path: $e');
      }
    }

    // Containers Android's extractor can't read (AVI and friends, broken
    // metadata): let Media3's own extractors convert it to MP4.
    onConvert?.call(0);
    final String converted;
    try {
      converted = await StudioRenderer.transcodeForEditing(path, hasAudio: info.audio.every((t) => t.decodable));
    } on MediaEngineException catch (e) {
      debugPrint('[StudioMedia] convert failed for $path: ${e.code} ${e.message}');
      final why = e.code.contains('DECOD') ? 'this phone can\'t decode its video' : 'its file type isn\'t supported';
      throw StudioMediaException('Couldn\'t open ${_name(path)}: $why.');
    }
    final probe = await OneovaMediaEngine.probe(converted);
    notes?.add('${_name(path)} was converted to MP4 for editing.');
    return _videoClip(converted, probe, startMs, endMs);
  }

  /// Decoder lookups can miss profiles a decoder still handles, so a real
  /// frame decode has the last word.
  static Future<bool> _canGrabFrame(String path) async {
    try {
      final dir = await StudioProjectStore.dir('thumbs');
      final out = await OneovaMediaEngine.frame(path, ms: 0, out: '${dir.path}/probe_${DateTime.now().microsecondsSinceEpoch}.jpg', maxSide: 160);
      await File(out).delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  static StudioClip _videoClip(String path, MediaProbe probe, int startMs, int? endMs, {bool keepAudio = true}) {
    final dur = probe.duration.inMilliseconds;
    return StudioClip.create(
      path: path,
      isImage: false,
      durationMs: dur,
      width: probe.width,
      height: probe.height,
      fps: probe.fps > 0 ? probe.fps : 30,
      hasAudio: probe.hasAudio && keepAudio,
      startMs: startMs.clamp(0, dur),
      endMs: (endMs == null || endMs <= startMs) ? dur : math.min(endMs, dur),
    );
  }

  static Future<StudioClip> _imageClip(String path, List<String>? notes, {bool allowVideo = true}) async {
    final ext = _ext(path);
    if (ext == 'gif' && allowVideo) {
      // Animated GIFs become a silent video clip; single-frame ones stay photos.
      try {
        final dir = await StudioProjectStore.dir('media');
        final (out, w, h, dur) = await OneovaMediaEngine.gifToVideo(path, out: '${dir.path}/gif_${DateTime.now().microsecondsSinceEpoch}.mp4');
        return StudioClip.create(path: out, isImage: false, durationMs: dur, width: w, height: h, hasAudio: false);
      } on MediaEngineException catch (e) {
        if (e.message != 'static') debugPrint('[StudioMedia] GIF convert failed for $path: ${e.message}');
      }
    }
    if (_directImageExts.contains(ext)) {
      try {
        final size = await imageSize(path);
        if (math.max(size.$1, size.$2) <= 4096) {
          return StudioClip.create(path: path, isImage: true, durationMs: 0, width: size.$1, height: size.$2);
        }
      } catch (e) {
        debugPrint('[StudioMedia] direct decode failed for $path: $e');
      }
    }
    final dir = await StudioProjectStore.dir('media');
    try {
      final (out, w, h) = await OneovaMediaEngine.normalizeImage(
        path,
        out: '${dir.path}/photo_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      return StudioClip.create(path: out, isImage: true, durationMs: 0, width: w, height: h);
    } on MediaEngineException catch (e) {
      throw StudioMediaException('Couldn\'t open ${_name(path)}: ${e.message}');
    } catch (e) {
      throw StudioMediaException('Couldn\'t open ${_name(path)}: this phone can\'t read that image.');
    }
  }

  static Future<List<StudioClip>> clipsFromPicks(List<StudioPick> picks) async => (await importPicks(picks)).clips;

  /// Opens every pick it can; see [StudioImportResult].
  static Future<StudioImportResult> importPicks(List<StudioPick> picks, {void Function(double progress)? onConvert, bool allowVideo = true}) async {
    final out = <StudioClip>[];
    final problems = <String>[];
    final notes = <String>[];
    for (final p in picks) {
      try {
        out.add(await clipFromFile(p.path, isImage: p.isImage, startMs: p.startMs, endMs: p.endMs, notes: notes, onConvert: onConvert, allowVideo: allowVideo));
      } on StudioMediaException catch (e) {
        problems.add(e.message);
      } catch (e) {
        debugPrint('[StudioMedia] skipping ${p.path}: $e');
        problems.add('Couldn\'t open ${_name(p.path)}.');
      }
    }
    return StudioImportResult(out, problems, notes);
  }

  /// Reads an audio file for the audio track. Throws [StudioMediaException].
  static Future<MediaProbe> probeAudio(String path) async {
    final info = await OneovaMediaEngine.inspect(path);
    if (info.readable) {
      final bad = info.audio.where((t) => !t.decodable).firstOrNull;
      if (bad != null) throw StudioMediaException('${_name(path)} uses ${bad.codecName} sound, which this phone can\'t play.');
      if (info.audio.isEmpty) throw StudioMediaException('${_name(path)} has no sound.');
    }
    try {
      final probe = await OneovaMediaEngine.probe(path);
      if (probe.hasAudio && probe.duration.inMilliseconds > 0) return probe;
    } catch (_) {}
    throw StudioMediaException('Couldn\'t read the sound in ${_name(path)}.');
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
