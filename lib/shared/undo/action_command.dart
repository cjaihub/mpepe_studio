abstract class ActionCommand {
  String get name;
  Future<void> execute();
  Future<void> undo();
}
