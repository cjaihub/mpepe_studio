import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import '../../providers/settings_provider.dart';
import '../commands/update_setting_command.dart';
import '../../shared/undo/undo_manager.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class PrivacySettingsScreen extends ConsumerWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: Text('Privacy Settings', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: AnimatedLoadingIndicator()),
        error: (e, s) => Center(child: Text('Error: $e', style: TextStyle(color: context.textSecondary))),
        data: (settings) {
          final categoryData = settings['privacy'] as Map<String, dynamic>? ?? {};

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildSwitch(context, ref, categoryData, 'profileVisibility', 'Profile Visibility', 'Make profile public to everyone'),
              _buildSwitch(context, ref, categoryData, 'readReceipts', 'Read Receipts', 'Let others know when you read their messages'),
              _buildSwitch(context, ref, categoryData, 'typingStatus', 'Typing Status', 'Show when you are typing'),
              _buildSwitch(context, ref, categoryData, 'aiAccess', 'AI Access', 'Allow Oneova AI to analyze your conversations for personalization'),
              _buildSwitch(context, ref, categoryData, 'dataRetention', 'Extended Data Retention', 'Keep messages forever instead of auto-deleting'),
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
        title: Text(title, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: TextStyle(color: context.textSecondary)),
        activeThumbColor: AppColors.brandBlue,
        onChanged: (newValue) {
          final newData = Map<String, dynamic>.from(currentData);
          newData[key] = newValue;
          final command = UpdateSettingCommand(
            ref: ref,
            category: 'privacy',
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
