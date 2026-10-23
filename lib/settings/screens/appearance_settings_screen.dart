import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/theme_provider.dart';
import '../widgets/settings_kit.dart';

/// Theme, text size and motion. Theme mode saves on the device instantly;
/// everything else auto-saves to `user_settings/{uid}`.
class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return CompactSettingsScaffold(
      title: 'Appearance',
      children: [
        _ThemePicker(
          mode: themeMode,
          onChanged: (m) {
            HapticFeedback.selectionClick();
            ref.read(themeProvider.notifier).setThemeMode(m);
          },
        ),
        const SizedBox(height: 14),
        SettingsAsyncBody(builder: (settings) {
          final appearance = settingsCategory(settings, 'appearance');
          final accessibility = settingsCategory(settings, 'accessibility');
          final playback = settingsCategory(settings, 'playback');
          return Column(
            children: [
              SettingsSection(
                label: 'Text',
                children: [
                  SettingsChoiceTile<String>(
                    icon: Icons.format_size_rounded,
                    title: 'Text size',
                    options: const {'small': 'Small', 'default': 'Default', 'large': 'Large', 'xlarge': 'XL'},
                    value: appearance['textSize'] as String? ?? 'default',
                    onChanged: (v) => settingsWrite(ref,
                        category: 'appearance', current: appearance, key: 'textSize', value: v, label: 'Text size'),
                  ),
                  SettingsSwitchTile(
                    icon: Icons.format_bold_rounded,
                    title: 'Bold text',
                    subtitle: 'Heavier weight across the app',
                    value: appearance['boldText'] as bool? ?? false,
                    onChanged: (v) => settingsWrite(ref,
                        category: 'appearance', current: appearance, key: 'boldText', value: v, label: 'Bold text'),
                  ),
                ],
              ),
              SettingsSection(
                label: 'Reels',
                footer: 'Follow app: the Reels feed, its top bar and overlays switch with Light / Dark mode.',
                children: [
                  SettingsChoiceTile<String>(
                    icon: Icons.smart_display_rounded,
                    title: 'Reels theme',
                    accent: AppColors.brandPink,
                    options: const {'followApp': 'Follow app', 'dark': 'Always dark'},
                    value: playback['reelsTheme'] as String? ?? 'followApp',
                    onChanged: (v) => settingsWrite(ref,
                        category: 'playback', current: playback, key: 'reelsTheme', value: v, label: 'Reels theme'),
                  ),
                ],
              ),
              SettingsSection(
                label: 'Motion',
                children: [
                  SettingsSwitchTile(
                    icon: Icons.animation_rounded,
                    title: 'Reduce motion',
                    subtitle: 'Minimise animations and transitions',
                    value: accessibility['reduceMotion'] as bool? ?? false,
                    onChanged: (v) => settingsWrite(ref,
                        category: 'accessibility',
                        current: accessibility,
                        key: 'reduceMotion',
                        value: v,
                        label: 'Reduce motion'),
                  ),
                  SettingsNavTile(
                    icon: Icons.accessibility_new_rounded,
                    title: 'More accessibility',
                    subtitle: 'Contrast, focus highlights',
                    onTap: () => context.push('/settings/accessibility'),
                  ),
                ],
              ),
            ],
          );
        }),
      ],
    );
  }
}

class _ThemePicker extends StatelessWidget {
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;
  const _ThemePicker({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const items = [
      (ThemeMode.light, 'Light', Icons.light_mode_rounded),
      (ThemeMode.dark, 'Dark', Icons.dark_mode_rounded),
      (ThemeMode.system, 'System', Icons.brightness_auto_rounded),
    ];
    return Row(
      children: [
        for (final (m, label, icon) in items) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(m),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: context.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: mode == m ? AppColors.brandBlue : context.border,
                    width: mode == m ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  children: [
                    _Preview(mode: m),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 12, color: mode == m ? AppColors.brandBlue : context.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          label,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: mode == m ? AppColors.brandBlue : context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (m != ThemeMode.system) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

/// Miniature phone preview: a reel card plus nav strip in the target theme.
class _Preview extends StatelessWidget {
  final ThemeMode mode;
  const _Preview({required this.mode});

  Widget _half(bool dark) {
    final bg = dark ? AppColors.darkBackground : AppColors.lightBackground;
    final card = dark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight;
    final line = dark ? AppColors.outline : AppColors.lightBorder;
    return Container(
      color: bg,
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(4)),
              alignment: Alignment.bottomLeft,
              padding: const EdgeInsets.all(3),
              child: Container(width: 18, height: 3, color: line),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (int i = 0; i < 5; i++)
                Container(
                  width: i == 2 ? 8 : 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: i == 2 ? AppColors.brandBlue : line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(
        height: 64,
        child: switch (mode) {
          ThemeMode.light => _half(false),
          ThemeMode.dark => _half(true),
          ThemeMode.system => Row(children: [Expanded(child: _half(false)), Expanded(child: _half(true))]),
        },
      ),
    );
  }
}
