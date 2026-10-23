import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/video_project_models.dart';

final videoProjectServiceProvider = Provider<VideoProjectService>((ref) {
  return VideoProjectService();
});

class VideoProjectService {
  VideoProject? _currentProject;
  
  // Undo/Redo stack for the Timeline
  final List<Timeline> _history = [];
  int _historyIndex = -1;

  VideoProject? get currentProject => _currentProject;
  bool get canUndo => _historyIndex > 0;
  bool get canRedo => _historyIndex < _history.length - 1;

  Future<void> loadProject(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('video_project_$projectId');
    if (jsonString != null) {
      _currentProject = VideoProject.fromMap(jsonDecode(jsonString));
      _history.clear();
      _history.add(_currentProject!.timeline);
      _historyIndex = 0;
    }
  }

  Future<void> createProject(String ownerId, String name) async {
    _currentProject = VideoProject(ownerId: ownerId, name: name);
    _history.clear();
    _history.add(_currentProject!.timeline);
    _historyIndex = 0;
    await _saveIncremental();
  }

  Future<void> _saveIncremental() async {
    if (_currentProject == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'video_project_${_currentProject!.id}',
      jsonEncode(_currentProject!.toMap()),
    );
  }

  void _pushHistory(Timeline newTimeline) {
    if (_currentProject == null) return;

    // Discard redo stack if we make a new edit
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(newTimeline);
    _historyIndex++;
    
    _currentProject = _currentProject!.copyWith(timeline: newTimeline);
    _saveIncremental();
  }

  void undo() {
    if (canUndo) {
      _historyIndex--;
      _currentProject = _currentProject!.copyWith(timeline: _history[_historyIndex]);
      _saveIncremental();
    }
  }

  void redo() {
    if (canRedo) {
      _historyIndex++;
      _currentProject = _currentProject!.copyWith(timeline: _history[_historyIndex]);
      _saveIncremental();
    }
  }

  // --- Operations ---

  void addTrack(Track track) {
    if (_currentProject == null) return;
    final timeline = _currentProject!.timeline;
    final newTracks = List<Track>.from(timeline.tracks)..add(track);
    _pushHistory(timeline.copyWith(tracks: newTracks));
  }

  void addClip(String trackId, Clip clip) {
    if (_currentProject == null) return;
    final timeline = _currentProject!.timeline;
    final newTracks = timeline.tracks.map((t) {
      if (t.id == trackId) {
        return t.copyWith(clips: List.from(t.clips)..add(clip));
      }
      return t;
    }).toList();
    _pushHistory(timeline.copyWith(tracks: newTracks));
  }

  void trimClip(String trackId, String clipId, Duration newStart, Duration newEnd) {
    if (_currentProject == null) return;
    
    // Never modify original media destructively - we only adjust source start/end
    final timeline = _currentProject!.timeline;
    final newTracks = timeline.tracks.map((t) {
      if (t.id == trackId) {
        final newClips = t.clips.map((c) {
          if (c.id == clipId) {
            return c.copyWith(sourceStartTime: newStart, sourceEndTime: newEnd);
          }
          return c;
        }).toList();
        return t.copyWith(clips: newClips);
      }
      return t;
    }).toList();
    _pushHistory(timeline.copyWith(tracks: newTracks));
  }

  void splitClip(String trackId, String clipId, Duration splitAtSourceTime) {
    if (_currentProject == null) return;
    final timeline = _currentProject!.timeline;
    
    final newTracks = timeline.tracks.map((t) {
      if (t.id == trackId) {
        final clipIndex = t.clips.indexWhere((c) => c.id == clipId);
        if (clipIndex != -1) {
          final c = t.clips[clipIndex];
          if (splitAtSourceTime > c.sourceStartTime && splitAtSourceTime < c.sourceEndTime) {
            final part1 = c.copyWith(
              sourceEndTime: splitAtSourceTime,
            );
            // The second part continues from the split
            final timelineOffsetForPart2 = c.timelineStartTime + (splitAtSourceTime - c.sourceStartTime) * (1 / c.transform.speed);
            final part2 = c.copyWith(
              id: null, // generates new id
              sourceStartTime: splitAtSourceTime,
              timelineStartTime: timelineOffsetForPart2,
            );
            
            final newClips = List<Clip>.from(t.clips);
            newClips[clipIndex] = part1;
            newClips.insert(clipIndex + 1, part2);
            return t.copyWith(clips: newClips);
          }
        }
      }
      return t;
    }).toList();
    _pushHistory(timeline.copyWith(tracks: newTracks));
  }

  void updateClipTransform(String trackId, String clipId, ClipTransform newTransform) {
    if (_currentProject == null) return;
    final timeline = _currentProject!.timeline;
    final newTracks = timeline.tracks.map((t) {
      if (t.id == trackId) {
        final newClips = t.clips.map((c) {
          if (c.id == clipId) {
            return c.copyWith(transform: newTransform);
          }
          return c;
        }).toList();
        return t.copyWith(clips: newClips);
      }
      return t;
    }).toList();
    _pushHistory(timeline.copyWith(tracks: newTracks));
  }
}
