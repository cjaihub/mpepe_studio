import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import '../../providers/settings_provider.dart';
import '../commands/update_setting_command.dart';
import '../../shared/undo/undo_manager.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

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
      backgroundColor: context.bg,
      appBar: AppBar(
        title: Text('Language', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
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
          final categoryData = settings['language'] as Map<String, dynamic>? ?? {};
          final currentLang = categoryData['code'] as String? ?? 'en';

          return ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: _languages.length,
            itemBuilder: (context, index) {
              final lang = _languages[index];
              // ignore: unused_local_variable
              final isSelected = currentLang == lang['code'];
              
              return OnerovaCard(
                // ignore: deprecated_member_use
                child: RadioListTile<String>(
                  value: lang['code']!,
                  // ignore: deprecated_member_use
                  groupValue: currentLang,
                  title: Text(lang['native']!, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
                  subtitle: Text(lang['name']!, style: TextStyle(color: context.textSecondary)),
                  activeColor: AppColors.brandBlue,
                  // ignore: deprecated_member_use
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
