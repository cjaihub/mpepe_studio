import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import '../../providers/settings_provider.dart';
import '../../settings/commands/update_setting_command.dart';
import '../../shared/undo/undo_manager.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class AutoModeSettingsScreen extends ConsumerWidget {
  const AutoModeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: Text('Auto Mode', style: Theme.of(context).textTheme.displayMedium!),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.pop(),
        ),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: AnimatedLoadingIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
        data: (settings) {
          final categoryData = settings['auto_mode'] as Map<String, dynamic>? ?? {};

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildSwitch(context, ref, categoryData, 'enabled', 'Auto Mode Enabled', 'AI replies to messages while you are asleep'),
              _buildSwitch(context, ref, categoryData, 'sendAutomatically', 'Send Automatically', 'Do not ask for approval before sending'),
              _buildSwitch(context, ref, categoryData, 'fallbackToHuman', 'Fallback to Human', 'Wait for human response if AI is unsure'),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSwitch(BuildContext context, WidgetRef ref, Map<String, dynamic> currentData, String key, String title, String subtitle) {
    final value = currentData[key] as bool? ?? false;
    return OnerovaCard(
      child: SwitchListTile(
        value: value,
        title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textSecondary)),
        activeThumbColor: AppColors.brandBlue,
        onChanged: (newValue) {
          final newData = Map<String, dynamic>.from(currentData);
          newData[key] = newValue;
          final command = UpdateSettingCommand(
            ref: ref,
            category: 'auto_mode',
            undoData: currentData,
            data: newData,
            name: 'Update $title',
          );
          ref.read(undoManagerProvider.notifier).executeAndRegister(command);
        },
      ),
    );
  }
}
