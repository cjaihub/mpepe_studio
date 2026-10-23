import os

TEMPLATE = """import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import '../../providers/settings_provider.dart';
import '../commands/update_setting_command.dart';
import '../../shared/undo/undo_manager.dart';

class {className} extends ConsumerWidget {
  const {className}({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: Text('{title}', style: Theme.of(context).textTheme.displayMedium!),
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
          final categoryData = settings['{categoryKey}'] as Map<String, dynamic>? ?? {};

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
{widgets}
            ],
          );
        },
      ),
    );
  }

  Widget _buildSwitch(BuildContext context, WidgetRef ref, Map<String, dynamic> currentData, String key, String title, String subtitle) {
    final value = currentData[key] as bool? ?? false;
    return MpepeCard(
      margin: const EdgeInsets.only(bottom: 16),
      child: SwitchListTile(
        value: value,
        title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textSecondary)),
        activeColor: AppColors.mpepeMaroon,
        onChanged: (newValue) {
          final newData = Map<String, dynamic>.from(currentData);
          newData[key] = newValue;
          final command = UpdateSettingCommand(
            ref: ref,
            category: '{categoryKey}',
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
"""

def build_switch(key, title, subtitle):
    return f"              _buildSwitch(context, ref, categoryData, '{key}', '{title}', '{subtitle}'),"

screens = [
    {
        "file": "privacy_settings_screen.dart",
        "className": "PrivacySettingsScreen",
        "title": "Privacy Settings",
        "categoryKey": "privacy",
        "widgets": [
            build_switch("profileVisibility", "Profile Visibility", "Make profile public to everyone"),
            build_switch("readReceipts", "Read Receipts", "Let others know when you read their messages"),
            build_switch("typingStatus", "Typing Status", "Show when you are typing"),
            build_switch("aiAccess", "AI Access", "Allow MPEPE AI to analyze your conversations for personalization"),
            build_switch("dataRetention", "Extended Data Retention", "Keep messages forever instead of auto-deleting"),
        ]
    },
    {
        "file": "security_settings_screen.dart",
        "className": "SecuritySettingsScreen",
        "title": "Security Settings",
        "categoryKey": "security",
        "widgets": [
            build_switch("twoFactorAuth", "Two-Factor Authentication", "Require a 2FA code to login"),
            build_switch("passkeys", "Passkeys", "Allow login with FaceID / TouchID"),
            build_switch("loginAlerts", "Login Alerts", "Get notified of new logins from unrecognized devices"),
        ]
    }
]

for s in screens:
    content = TEMPLATE.replace("{className}", s["className"]) \
                      .replace("{title}", s["title"]) \
                      .replace("{categoryKey}", s["categoryKey"]) \
                      .replace("{widgets}", "\n".join(s["widgets"]))
    with open(f"lib/settings/screens/{s['file']}", "w") as f:
        f.write(content)

print("Generated privacy and security")
