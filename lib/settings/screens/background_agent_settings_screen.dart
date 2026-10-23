import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/settings_kit.dart';

/// Auto-saves every toggle to `user_settings/{uid}.background_agent`.
class BackgroundAgentSettingsScreen extends ConsumerWidget {
  const BackgroundAgentSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CompactSettingsScaffold(
      title: 'Background Agent',
      children: [
        SettingsAsyncBody(builder: (settings) {
          final data = settingsCategory(settings, 'background_agent');
          Widget toggle(IconData icon, String key, String label, String subtitle, {bool fallback = false}) {
            return SettingsSwitchTile(
              icon: icon,
              title: label,
              subtitle: subtitle,
              value: data[key] as bool? ?? fallback,
              onChanged: (v) =>
                  settingsWrite(ref, category: 'background_agent', current: data, key: key, value: v, label: label),
            );
          }

          return SettingsSection(
            label: 'Agent',
            children: [
              toggle(Icons.smart_toy_rounded, 'autonomousMode', 'Autonomous mode', 'Let the agent act while you are offline'),
              toggle(Icons.verified_user_rounded, 'requireApproval', 'Require approval', 'Confirm before it sends messages'),
              toggle(Icons.speed_rounded, 'rateLimits', 'Strict rate limits', 'Prevent messaging too frequently'),
            ],
          );
        }),
      ],
    );
  }
}
