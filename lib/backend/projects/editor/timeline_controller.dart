import 'package:flutter/foundation.dart';
import '../models/pro_project_models.dart';
import 'commands/timeline_command.dart';

/// The authoritative controller for the editing timeline.
/// It wraps the Sequence domain model and processes all editing commands
/// through an Undo/Redo stack.
class TimelineController extends ChangeNotifier {
  final Sequence sequence;
  
  final List<TimelineCommand> _undoStack = [];
  final List<TimelineCommand> _redoStack = [];

  TimelineController(this.sequence);

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Execute an editorial command, pushing it to the undo stack.
  void execute(TimelineCommand command) {
    command.execute(sequence);
    _undoStack.add(command);
    _redoStack.clear(); // Any new action invalidates redo history
    notifyListeners();
  }

  /// Undo the last operation
  void undo() {
    if (!canUndo) return;
    final command = _undoStack.removeLast();
    command.undo(sequence);
    _redoStack.add(command);
    notifyListeners();
  }

  /// Redo the previously undone operation
  void redo() {
    if (!canRedo) return;
    final command = _redoStack.removeLast();
    command.redo(sequence);
    _undoStack.add(command);
    notifyListeners();
  }

  /// Checks if a move operation is valid without overlaps.
  bool canMoveClip(String trackId, String clipId, double newStartTime) {
    final track = sequence.tracks.firstWhere((t) => t.id == trackId);
    final clip = track.clips.firstWhere((c) => c.id == clipId);
    
    // Check collisions with other clips on the same track
    for (var other in track.clips) {
      if (other.id == clip.id) continue;
      
      final overlaps = (newStartTime < other.startTime + other.duration) &&
                       (newStartTime + clip.duration > other.startTime);
      if (overlaps) return false;
    }
    return true;
  }
}
