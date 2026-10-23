import 'package:flutter/foundation.dart';

/// A deterministic representation of time on a timeline to prevent
/// floating-point drift accumulation during complex edits.
@immutable
class TimelineTime implements Comparable<TimelineTime> {
  final int frameIndex;
  final double frameRate;

  const TimelineTime._(this.frameIndex, this.frameRate);

  /// Creates a TimelineTime exactly at the specified frame index.
  factory TimelineTime.fromFrame(int frameIndex, double frameRate) {
    return TimelineTime._(frameIndex, frameRate);
  }

  /// Creates a TimelineTime from seconds, snapped to the nearest frame.
  factory TimelineTime.fromSeconds(double seconds, double frameRate) {
    final frame = (seconds * frameRate).round();
    return TimelineTime._(frame, frameRate);
  }

  static TimelineTime zero(double frameRate) => TimelineTime._(0, frameRate);

  double get toSeconds => frameIndex / frameRate;

  TimelineTime operator +(TimelineTime other) {
    assert(frameRate == other.frameRate, 'Cannot add times with different frame rates.');
    return TimelineTime._(frameIndex + other.frameIndex, frameRate);
  }

  TimelineTime operator -(TimelineTime other) {
    assert(frameRate == other.frameRate, 'Cannot subtract times with different frame rates.');
    return TimelineTime._(frameIndex - other.frameIndex, frameRate);
  }

  bool operator >(TimelineTime other) => frameIndex > other.frameIndex;
  bool operator <(TimelineTime other) => frameIndex < other.frameIndex;
  bool operator >=(TimelineTime other) => frameIndex >= other.frameIndex;
  bool operator <=(TimelineTime other) => frameIndex <= other.frameIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineTime &&
          runtimeType == other.runtimeType &&
          frameIndex == other.frameIndex &&
          frameRate == other.frameRate;

  @override
  int get hashCode => frameIndex.hashCode ^ frameRate.hashCode;

  @override
  int compareTo(TimelineTime other) {
    return frameIndex.compareTo(other.frameIndex);
  }

  @override
  String toString() {
    return 'TimelineTime(\${toSeconds.toStringAsFixed(3)}s, f:\$frameIndex)';
  }
}
