import 'dart:math';
import 'timeline_time.dart';
import '../models/pro_project_models.dart';

/// Handles bidirectional conversion between timeline time and viewport pixels,
/// and calculates which clips are visible within a given scroll offset.
class TimelineLayout {
  final double pixelsPerSecond;
  final double frameRate;

  const TimelineLayout({
    required this.pixelsPerSecond,
    required this.frameRate,
  });

  /// Converts a TimelineTime to a pixel offset.
  double timeToPixels(TimelineTime time) {
    return time.toSeconds * pixelsPerSecond;
  }

  /// Converts seconds to a pixel offset.
  double secondsToPixels(double seconds) {
    return seconds * pixelsPerSecond;
  }

  /// Converts a pixel offset to a TimelineTime, snapped to the nearest frame.
  TimelineTime pixelsToTime(double pixels) {
    final seconds = max(0.0, pixels / pixelsPerSecond);
    return TimelineTime.fromSeconds(seconds, frameRate);
  }

  /// Returns the clips from a track that intersect the viewport.
  /// [viewportStart] and [viewportEnd] are in pixels.
  List<Clip> getVisibleClips(Track track, double viewportStart, double viewportEnd) {
    final startSeconds = max(0.0, viewportStart / pixelsPerSecond);
    final endSeconds = max(0.0, viewportEnd / pixelsPerSecond);

    return track.clips.where((clip) {
      final clipStart = clip.startTime;
      final clipEnd = clip.startTime + clip.duration;
      return clipEnd > startSeconds && clipStart < endSeconds;
    }).toList();
  }
}
