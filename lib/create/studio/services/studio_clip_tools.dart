import 'dart:math' as math;

import 'package:oneova_media_engine/oneova_media_engine.dart';

import '../models/studio_project.dart';
import 'studio_project_store.dart';

/// Clip operations that render new media on the device: reverse, beat
/// detection and cutting to the beat. Shared by the editor and Ova.
class StudioClipTools {
  StudioClipTools._();

  /// Longest clip that can be reversed (frames are decoded one by one).
  static const maxReverseMs = 60000;

  /// A backwards copy of [c]'s trimmed range, as a new clip with its edits kept
  /// (sound is dropped: reversed speech is rarely wanted).
  static Future<StudioClip> reverse(StudioClip c) async {
    if (c.isImage) throw const MediaEngineException('photo', 'Reverse works on video clips.');
    if (c.endMs - c.startMs > maxReverseMs) {
      throw const MediaEngineException('too_long', 'Trim the clip to 60 seconds or less to reverse it.');
    }
    final dir = await StudioProjectStore.dir('media');
    final fps = math.min(30, math.max(24, c.sourceFps.round()));
    final out = await OneovaMediaEngine.reverse(
      c.path,
      out: '${dir.path}/reversed_${DateTime.now().millisecondsSinceEpoch}.mp4',
      startMs: c.startMs,
      endMs: c.endMs,
      fps: fps,
      maxSide: math.min(1920, math.max(c.sourceWidth, c.sourceHeight)),
    );
    final probe = await OneovaMediaEngine.probe(out);
    final dur = probe.duration.inMilliseconds;
    return StudioClip.create(path: out, isImage: false, durationMs: dur, width: probe.width, height: probe.height, fps: fps.toDouble(), hasAudio: false)
        .copyWith(
      id: c.id,
      speed: c.speed,
      filterId: c.filterId,
      filterIntensity: c.filterIntensity,
      lookId: c.lookId,
      lookIntensity: c.lookIntensity,
      adjust: c.adjust,
      retouch: c.retouch,
      fill: c.fill,
      zoom: c.zoom,
    );
  }

  /// Finds beats in [a]'s source.
  static Future<StudioAudio> detectBeats(StudioAudio a) async {
    final (beats, bpm) = await OneovaMediaEngine.beats(a.path, maxMs: a.endMs + 1000);
    return a.copyWith(beatsMs: beats, bpm: bpm);
  }

  /// Re-times the clips so each cut lands on a beat of [a] (every beat, or
  /// every 2nd/4th when beats are very close). Video clips keep their start
  /// and get shorter or longer within their source; photos just change length.
  static StudioProject cutToBeats(StudioProject p, StudioAudio a) {
    var beats = a.timelineBeats.where((b) => b > 0).toList();
    if (beats.length < 2 || p.clips.isEmpty) return p;
    final gaps = [for (var i = 1; i < beats.length; i++) beats[i] - beats[i - 1]]..sort();
    final median = gaps[gaps.length ~/ 2];
    final every = median < 350 ? 4 : (median < 600 ? 2 : 1);
    beats = [for (var i = 0; i < beats.length; i += every) beats[i]];
    final clips = <StudioClip>[];
    var t = 0;
    var k = 0;
    for (final c in p.clips) {
      while (k < beats.length && beats[k] <= t + 300) {
        k++;
      }
      if (k >= beats.length) {
        clips.add(c);
        t += c.outDurationMs;
        continue;
      }
      final want = beats[k] - t;
      if (c.isImage) {
        clips.add(c.copyWith(imageDurationMs: want));
        t += want;
      } else {
        final srcEnd = math.min(c.sourceDurationMs, c.startMs + (want * c.speed).round());
        final next = c.copyWith(endMs: math.max(c.startMs + 300, srcEnd));
        clips.add(next);
        t += next.outDurationMs;
      }
      k++;
    }
    return p.copyWith(clips: clips);
  }
}
