import '../../models/pro_project_models.dart';
import 'timeline_command.dart';

class MoveClipCommand implements TimelineCommand {
  final String clipId;
  final String sourceTrackId;
  final String targetTrackId;
  final double oldStartTime;
  final double newStartTime;

  MoveClipCommand({
    required this.clipId,
    required this.sourceTrackId,
    required this.targetTrackId,
    required this.oldStartTime,
    required this.newStartTime,
  });

  @override
  void execute(Sequence sequence) {
    _move(sequence, sourceTrackId, targetTrackId, newStartTime);
  }

  @override
  void undo(Sequence sequence) {
    _move(sequence, targetTrackId, sourceTrackId, oldStartTime);
  }

  @override
  void redo(Sequence sequence) => execute(sequence);

  void _move(Sequence sequence, String fromTrackId, String toTrackId, double time) {
    final fromTrack = sequence.tracks.firstWhere((t) => t.id == fromTrackId);
    final clipIndex = fromTrack.clips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) return;
    
    final clip = fromTrack.clips.removeAt(clipIndex);
    clip.startTime = time;

    final toTrack = sequence.tracks.firstWhere((t) => t.id == toTrackId);
    toTrack.clips.add(clip);
    toTrack.clips.sort((a, b) => a.startTime.compareTo(b.startTime));
  }
}

class TrimClipCommand implements TimelineCommand {
  final String trackId;
  final String clipId;
  final double oldStartTime;
  final double newStartTime;
  final double oldDuration;
  final double newDuration;
  final double oldSourceStart;
  final double newSourceStart;

  TrimClipCommand({
    required this.trackId,
    required this.clipId,
    required this.oldStartTime,
    required this.newStartTime,
    required this.oldDuration,
    required this.newDuration,
    required this.oldSourceStart,
    required this.newSourceStart,
  });

  @override
  void execute(Sequence sequence) {
    _apply(sequence, newStartTime, newDuration, newSourceStart);
  }

  @override
  void undo(Sequence sequence) {
    _apply(sequence, oldStartTime, oldDuration, oldSourceStart);
  }

  @override
  void redo(Sequence sequence) => execute(sequence);

  void _apply(Sequence sequence, double start, double dur, double srcStart) {
    final track = sequence.tracks.firstWhere((t) => t.id == trackId);
    final clip = track.clips.firstWhere((c) => c.id == clipId);
    clip.startTime = start;
    clip.duration = dur;
    clip.sourceStart = srcStart;
  }
}

class DeleteClipCommand implements TimelineCommand {
  final String trackId;
  final Clip deletedClip;
  
  DeleteClipCommand({
    required this.trackId,
    required this.deletedClip,
  });

  @override
  void execute(Sequence sequence) {
    final track = sequence.tracks.firstWhere((t) => t.id == trackId);
    track.clips.removeWhere((c) => c.id == deletedClip.id);
  }

  @override
  void undo(Sequence sequence) {
    final track = sequence.tracks.firstWhere((t) => t.id == trackId);
    track.clips.add(deletedClip);
    track.clips.sort((a, b) => a.startTime.compareTo(b.startTime));
  }
  
  @override
  void redo(Sequence sequence) => execute(sequence);
}
