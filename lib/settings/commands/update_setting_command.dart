import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/undo/action_command.dart';
import '../../providers/settings_provider.dart';

class UpdateSettingCommand implements ActionCommand {
  final WidgetRef ref;
  final String category;
  final Map<String, dynamic> undoData;
  final Map<String, dynamic> data;
  @override
  final String name;

  UpdateSettingCommand({
    required this.ref,
    required this.category,
    required this.undoData,
    required this.data,
    required this.name,
  });

  @override
  Future<void> execute() async {
    await ref.read(settingsProvider.notifier).updateCategory(category, data);
  }

  @override
  Future<void> undo() async {
    await ref.read(settingsProvider.notifier).updateCategory(category, undoData);
  }
}
