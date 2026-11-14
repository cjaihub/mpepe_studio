import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/compact/compact.dart';
import '../../shared/language/language_detector.dart';
import '../../shared/language/world_languages.dart';
import '../../providers/settings_provider.dart';
import '../commands/update_setting_command.dart';
import '../../shared/undo/undo_manager.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

/// Settings → Language: the language reels and captions are translated into
/// (searchable, world and local languages), auto-translate on/off, and the app
/// language. Stored in `user_settings/{uid}.language`.
class LanguageSettingsScreen extends ConsumerWidget {
  const LanguageSettingsScreen({super.key});

  static const _appLanguages = [
    {'code': 'en', 'name': 'English', 'native': 'English'},
    {'code': 'es', 'name': 'Spanish', 'native': 'Español'},
    {'code': 'fr', 'name': 'French', 'native': 'Français'},
    {'code': 'de', 'name': 'German', 'native': 'Deutsch'},
    {'code': 'ja', 'name': 'Japanese', 'native': '日本語'},
    {'code': 'ko', 'name': 'Korean', 'native': '한국어'},
    {'code': 'zh', 'name': 'Chinese', 'native': '中文'},
  ];

  void _save(WidgetRef ref, Map<String, dynamic> current, Map<String, dynamic> changes, String name) {
    final next = Map<String, dynamic>.from(current)..addAll(changes);
    ref.read(undoManagerProvider.notifier).executeAndRegister(UpdateSettingCommand(
          ref: ref,
          category: 'language',
          undoData: current,
          data: next,
          name: name,
        ));
  }

  static String _labelFor(String? code) {
    if (code == null || code.isEmpty) {
      final phone = LanguageDetector.phoneLanguage();
      return 'Phone language (${WorldLanguages.nameOf(phone) ?? LanguageDetector.nameOf(phone)})';
    }
    final l = WorldLanguages.byCode(code);
    return l == null ? LanguageDetector.nameOf(code) : l.name;
  }

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
        error: (e, s) => Center(child: Text('Could not load your settings.', style: TextStyle(color: context.textSecondary))),
        data: (settings) {
          final data = Map<String, dynamic>.from(settings['language'] as Map? ?? const {});
          final currentLang = data['code'] as String? ?? 'en';
          final translateTo = data['translateTo'] as String?;
          final auto = data['autoTranslateReels'] != false;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              CompactGroup(
                title: 'Translations',
                children: [
                  CompactRow(
                    icon: Icons.translate_rounded,
                    title: 'Translate reels automatically',
                    subtitle: 'Captions in other languages show in yours',
                    trailing: Switch.adaptive(
                      value: auto,
                      activeTrackColor: AppColors.brandBlue,
                      onChanged: (v) => _save(ref, data, {'autoTranslateReels': v}, 'Auto-translate reels'),
                    ),
                    onTap: () => _save(ref, data, {'autoTranslateReels': !auto}, 'Auto-translate reels'),
                  ),
                  CompactRow(
                    icon: Icons.language_rounded,
                    title: 'Translate into',
                    value: _labelFor(translateTo),
                    onTap: () async {
                      final picked = await showWorldLanguagePicker(context, selected: translateTo);
                      if (picked == null) return;
                      _save(ref, data, {'translateTo': picked}, 'Translation language');
                    },
                  ),
                ],
              ),
              CompactGroup(
                title: 'App language',
                children: [
                  for (final lang in _appLanguages)
                    CompactRow(
                      icon: currentLang == lang['code'] ? Icons.check_circle_rounded : Icons.circle_outlined,
                      title: lang['native']!,
                      subtitle: lang['name'],
                      showChevron: false,
                      onTap: currentLang == lang['code']
                          ? null
                          : () => _save(ref, data, {'code': lang['code']}, 'Update Language'),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Searchable list of world and local languages. Returns the picked code, or
/// '' for "Phone language", or null when dismissed.
Future<String?> showWorldLanguagePicker(BuildContext context, {String? selected}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
    builder: (_) => _WorldLanguagePicker(selected: selected),
  );
}

class _WorldLanguagePicker extends StatefulWidget {
  final String? selected;
  const _WorldLanguagePicker({this.selected});

  @override
  State<_WorldLanguagePicker> createState() => _WorldLanguagePickerState();
}

class _WorldLanguagePickerState extends State<_WorldLanguagePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final results = WorldLanguages.search(_query);
    final sel = widget.selected ?? '';
    final phone = LanguageDetector.phoneLanguage();
    final showPhone = _query.trim().isEmpty;

    Widget row({required String code, required String title, String? subtitle}) {
      final isSel = code == sel;
      return CompactRow(
        icon: isSel ? Icons.check_circle_rounded : Icons.circle_outlined,
        title: title,
        subtitle: subtitle,
        showChevron: false,
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).pop(code);
        },
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(AppRadius.full)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              style: AppTypography.bodyMedium(context.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search languages',
                prefixIcon: Icon(Icons.search_rounded, size: 20, color: context.textMuted),
                isDense: true,
                filled: true,
                fillColor: context.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: context.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: context.border),
                ),
              ),
            ),
          ),
          Expanded(
            child: results.isEmpty && !showPhone
                ? Center(child: Text('No language found', style: AppTypography.caption(context.textMuted)))
                : ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                    itemCount: results.length + (showPhone ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (showPhone && i == 0) {
                        return row(
                          code: '',
                          title: 'Phone language',
                          subtitle: WorldLanguages.nameOf(phone) ?? LanguageDetector.nameOf(phone),
                        );
                      }
                      final l = results[i - (showPhone ? 1 : 0)];
                      return row(code: l.code, title: l.native, subtitle: l.native == l.name ? null : l.name);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
