import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'action_command.dart';

final undoManagerProvider = NotifierProvider<UndoManager, UndoState>(() {
  return UndoManager();
});

class UndoState {
  final List<ActionCommand> undoStack;
  final List<ActionCommand> redoStack;

  UndoState({this.undoStack = const [], this.redoStack = const []});

  UndoState copyWith({
    List<ActionCommand>? undoStack,
    List<ActionCommand>? redoStack,
  }) {
    return UndoState(
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
    );
  }
}

class UndoManager extends Notifier<UndoState> {
  @override
  UndoState build() {
    return UndoState();
  }

  Future<void> executeAndRegister(ActionCommand command) async {
    await command.execute();
    state = state.copyWith(
      undoStack: List.from(state.undoStack)..add(command),
      redoStack: [], // Clear redo stack on new action
    );
  }

  Future<void> undo() async {
    if (state.undoStack.isEmpty) return;

    final command = state.undoStack.last;
    final newUndoStack = List<ActionCommand>.from(state.undoStack)..removeLast();

    await command.undo();

    state = state.copyWith(
      undoStack: newUndoStack,
      redoStack: List.from(state.redoStack)..add(command),
    );
  }

  Future<void> redo() async {
    if (state.redoStack.isEmpty) return;

    final command = state.redoStack.last;
    final newRedoStack = List<ActionCommand>.from(state.redoStack)..removeLast();

    await command.execute();

    state = state.copyWith(
      undoStack: List.from(state.undoStack)..add(command),
      redoStack: newRedoStack,
    );
  }

  void clear() {
    state = UndoState();
  }
}
