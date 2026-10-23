import '../../projects/models/pro_project_models.dart';

class TimelineMapper {
  /// Resolves the sequence time to a specific clip's source time.
  /// Returns null if the clip is not active at the given sequence time.
  static Duration? getSourceTimeForClip({
    required Clip clip,
    required Duration sequenceTime,
  }) {
    final double seqTimeSeconds = sequenceTime.inMilliseconds / 1000.0;
    
    // Check if the sequence time falls within the clip's timeline bounds
    if (seqTimeSeconds < clip.startTime || seqTimeSeconds >= clip.startTime + clip.duration) {
      return null;
    }
    
    // Calculate how far into the clip the sequence time is
    final double clipOffset = seqTimeSeconds - clip.startTime;
    
    // Calculate the source time by adding the offset to the source start
    final double sourceTimeSeconds = clip.sourceStart + clipOffset;
    
    return Duration(milliseconds: (sourceTimeSeconds * 1000).round());
  }
  
  /// Gets all active clips across all tracks at a specific sequence time.
  /// Returns them in rendering order (bottom to top).
  static List<Clip> getActiveClipsAtTime({
    required Sequence sequence,
    required Duration sequenceTime,
  }) {
    final activeClips = <Clip>[];
    final double seqTimeSeconds = sequenceTime.inMilliseconds / 1000.0;
    
    for (final track in sequence.tracks) {
      if (track.isHidden) continue;
      
      for (final clip in track.clips) {
        if (seqTimeSeconds >= clip.startTime && seqTimeSeconds < clip.startTime + clip.duration) {
          activeClips.add(clip);
        }
      }
    }
    
    // Assuming tracks are ordered bottom to top in sequence.tracks
    return activeClips;
  }
}
