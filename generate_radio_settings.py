import os

TEMPLATE = """import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import '../../providers/settings_provider.dart';
import '../commands/update_setting_command.dart';
import '../../shared/undo/undo_manager.dart';

class LanguageSettingsScreen extends ConsumerWidget {
  const LanguageSettingsScreen({super.key});

  static const _languages = [
    {'code': 'en', 'name': 'English', 'native': 'English'},
    {'code': 'es', 'name': 'Spanish', 'native': 'Español'},
    {'code': 'fr', 'name': 'French', 'native': 'Français'},
    {'code': 'de', 'name': 'German', 'native': 'Deutsch'},
    {'code': 'ja', 'name': 'Japanese', 'native': '日本語'},
    {'code': 'ko', 'name': 'Korean', 'native': '한국어'},
    {'code': 'zh', 'name': 'Chinese', 'native': '中文'},
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: Text('Language', style: Theme.of(context).textTheme.displayMedium!),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.pop(),
        ),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
        data: (settings) {
          final categoryData = settings['language'] as Map<String, dynamic>? ?? {};
          final currentLang = categoryData['code'] as String? ?? 'en';

          return ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: _languages.length,
            itemBuilder: (context, index) {
              final lang = _languages[index];
              final isSelected = currentLang == lang['code'];
              
              return MpepeCard(
                margin: const EdgeInsets.only(bottom: 16),
                child: RadioListTile<String>(
                  value: lang['code']!,
                  groupValue: currentLang,
                  title: Text(lang['native']!, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                  subtitle: Text(lang['name']!, style: const TextStyle(color: AppColors.textSecondary)),
                  activeColor: AppColors.mpepeMaroon,
                  onChanged: (newValue) {
                    if (newValue == null) return;
                    final newData = Map<String, dynamic>.from(categoryData);
                    newData['code'] = newValue;
                    final command = UpdateSettingCommand(
                      ref: ref,
                      category: 'language',
                      undoData: categoryData,
                      data: newData,
                      name: 'Update Language',
                    );
                    ref.read(undoManagerProvider.notifier).executeAndRegister(command);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
"""

with open("lib/settings/screens/language_settings_screen.dart", "w") as f:
    f.write(TEMPLATE)

print("Generated LanguageSettingsScreen")
