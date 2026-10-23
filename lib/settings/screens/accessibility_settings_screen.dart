import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/settings_kit.dart';

/// Auto-saves every toggle to `user_settings/{uid}.accessibility`.
class AccessibilitySettingsScreen extends ConsumerWidget {
  const AccessibilitySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CompactSettingsScaffold(
      title: 'Accessibility',
      children: [
        SettingsAsyncBody(builder: (settings) {
          final data = settingsCategory(settings, 'accessibility');
          Widget toggle(IconData icon, String key, String label, String subtitle, {bool fallback = false}) {
            return SettingsSwitchTile(
              icon: icon,
              title: label,
              subtitle: subtitle,
              value: data[key] as bool? ?? fallback,
              onChanged: (v) =>
                  settingsWrite(ref, category: 'accessibility', current: data, key: key, value: v, label: label),
            );
          }

          return SettingsSection(
            label: 'Display',
            children: [
              toggle(Icons.contrast_rounded, 'highContrast', 'High contrast', 'Stronger text and border contrast'),
              toggle(Icons.animation_rounded, 'reduceMotion', 'Reduce motion', 'Turns off non-essential animations'),
              toggle(Icons.text_increase_rounded, 'largeText', 'Large text', 'Scales text up across the app'),
              toggle(Icons.center_focus_strong_rounded, 'screenReaderFocus', 'Enhanced focus', 'Clearer screen-reader focus highlights'),
            ],
          );
        }),
      ],
    );
  }
}
