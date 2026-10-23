import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/settings_kit.dart';

/// Auto-saves every toggle to `user_settings/{uid}.automation`.
class AutomationSettingsScreen extends ConsumerWidget {
  const AutomationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CompactSettingsScaffold(
      title: 'Automation',
      children: [
        SettingsAsyncBody(builder: (settings) {
          final data = settingsCategory(settings, 'automation');
          Widget toggle(IconData icon, String key, String label, String subtitle, {bool fallback = false}) {
            return SettingsSwitchTile(
              icon: icon,
              title: label,
              subtitle: subtitle,
              value: data[key] as bool? ?? fallback,
              onChanged: (v) =>
                  settingsWrite(ref, category: 'automation', current: data, key: key, value: v, label: label),
            );
          }

          return SettingsSection(
            label: 'Engine',
            children: [
              toggle(Icons.bolt_rounded, 'engineEnabled', 'Engine enabled', 'Master switch for all workflows'),
              toggle(Icons.receipt_long_rounded, 'logExecution', 'Log execution', 'Keep a history of workflow runs'),
              toggle(Icons.report_gmailerrorred_rounded, 'failureAlerts', 'Failure alerts', 'Notify me when a workflow fails'),
            ],
          );
        }),
      ],
    );
  }
}
