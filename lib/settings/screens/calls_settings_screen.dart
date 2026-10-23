import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/settings_kit.dart';

/// Auto-saves every toggle to `user_settings/{uid}.calls`.
class CallsSettingsScreen extends ConsumerWidget {
  const CallsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CompactSettingsScaffold(
      title: 'Calls',
      children: [
        SettingsAsyncBody(builder: (settings) {
          final data = settingsCategory(settings, 'calls');
          Widget toggle(IconData icon, String key, String label, String subtitle, {bool fallback = false}) {
            return SettingsSwitchTile(
              icon: icon,
              title: label,
              subtitle: subtitle,
              value: data[key] as bool? ?? fallback,
              onChanged: (v) =>
                  settingsWrite(ref, category: 'calls', current: data, key: key, value: v, label: label),
            );
          }

          return SettingsSection(
            label: 'When joining a call',
            children: [
              toggle(Icons.videocam_rounded, 'allowVideo', 'Camera on by default', 'Join calls with video enabled'),
              toggle(Icons.mic_rounded, 'allowMic', 'Mic on by default', 'Join calls unmuted', fallback: true),
              toggle(Icons.graphic_eq_rounded, 'noiseCancellation', 'Noise cancellation', 'Filter background noise', fallback: true),
            ],
          );
        }),
      ],
    );
  }
}
