import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import '../../providers/settings_provider.dart';
import '../commands/update_setting_command.dart';
import '../../shared/undo/undo_manager.dart';
import 'ai_personalization/ai_memory_manager_screen.dart';
import 'ai_personalization/omni_assistant_preferences_screen.dart';
import 'ai_personalization/communication_style_screen.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class AiPersonalizationScreen extends ConsumerWidget {
  const AiPersonalizationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: Text('AI Personalization', style: Theme.of(context).textTheme.displayMedium?.copyWith(color: context.textPrimary) ?? TextStyle(color: context.textPrimary)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: AnimatedLoadingIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
        data: (settings) {
          final categoryData = settings['ai_personalization'] as Map<String, dynamic>? ?? {};

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildSwitch(context, ref, categoryData, 'memory', 'Infinite Memory', 'Allow AI to remember details from past conversations'),
              _buildSwitch(context, ref, categoryData, 'toneMatching', 'Tone Matching', 'AI replies will try to match your typing style'),
              _buildSwitch(context, ref, categoryData, 'proactive', 'Proactive Assistance', 'AI will suggest actions before you ask'),
              OnerovaCard(
                child: ListTile(
                  title: Text('Personal Communication Style', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
                  subtitle: Text('Let AI learn your tone, vocabulary, and phrasing from authorized messages', style: TextStyle(color: context.textSecondary)),
                  trailing: Icon(Icons.arrow_forward_ios, color: context.textMuted, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CommunicationStyleScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              OnerovaCard(
                child: ListTile(
                  title: Text('Omni Assistant Identity', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
                  subtitle: Text('Configure how Omni Command talks, its tone, language, and response depth', style: TextStyle(color: context.textSecondary)),
                  trailing: Icon(Icons.arrow_forward_ios, color: context.textMuted, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OmniAssistantPreferencesScreen()),
                    );
                  },
                ),
              ),
              OnerovaCard(
                child: ListTile(
                  title: Text('Manage AI Memory', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
                  subtitle: Text('View, edit, or delete what the AI has learned about your style', style: TextStyle(color: context.textSecondary)),
                  trailing: Icon(Icons.arrow_forward_ios, color: context.textMuted, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AiMemoryManagerScreen()),
                    );
                  },
                ),
              ),
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
            category: 'ai_personalization',
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
