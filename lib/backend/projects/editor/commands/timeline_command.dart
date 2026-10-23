
import '../../models/pro_project_models.dart';

/// Base interface for any mutating operation on the Timeline.
/// All actions must implement this to support Undo/Redo.
abstract class TimelineCommand {
  /// Executes the mutation.
  void execute(Sequence sequence);

  /// Reverts the mutation exactly to the prior state.
  void undo(Sequence sequence);
  
  /// Re-applies the mutation after an undo.
  void redo(Sequence sequence) => execute(sequence);
}

/// A command that groups multiple commands into a single undoable transaction.
class CompoundTimelineCommand implements TimelineCommand {
  final List<TimelineCommand> commands;

  CompoundTimelineCommand(this.commands);

  @override
  void execute(Sequence sequence) {
    for (var cmd in commands) {
      cmd.execute(sequence);
    }
  }

  @override
  void undo(Sequence sequence) {
    // Undo in reverse order
    for (var cmd in commands.reversed) {
      cmd.undo(sequence);
    }
  }

  @override
  void redo(Sequence sequence) {
    for (var cmd in commands) {
      cmd.redo(sequence);
    }
  }
}
