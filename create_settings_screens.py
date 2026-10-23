import os

screens = [
    ('account_settings_screen.dart', 'AccountSettingsScreen', 'Account Settings'),
    ('language_settings_screen.dart', 'LanguageSettingsScreen', 'Language'),
    ('appearance_settings_screen.dart', 'AppearanceSettingsScreen', 'Appearance'),
    ('accessibility_settings_screen.dart', 'AccessibilitySettingsScreen', 'Accessibility'),
    ('security_settings_screen.dart', 'SecuritySettingsScreen', 'Security'),
    ('sessions_screen.dart', 'SessionsScreen', 'Active Sessions'),
    ('blocked_users_screen.dart', 'BlockedUsersScreen', 'Blocked Users'),
    ('connected_channels_screen.dart', 'ConnectedChannelsScreen', 'Connected Channels'),
    ('calls_settings_screen.dart', 'CallsSettingsScreen', 'Calls'),
    ('ai_personalization_screen.dart', 'AiPersonalizationScreen', 'AI Personalization'),
    ('automation_settings_screen.dart', 'AutomationSettingsScreen', 'Automation'),
    ('storage_settings_screen.dart', 'StorageSettingsScreen', 'Storage & Data'),
    ('data_export_screen.dart', 'DataExportScreen', 'Data & Export'),
    ('help_support_screen.dart', 'HelpSupportScreen', 'Help & Support'),
    ('about_screen.dart', 'AboutScreen', 'About'),
]

template = """import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../shared/theme/app_theme.dart';

class {class_name} extends ConsumerWidget {{
  const {class_name}({{super.key}});

  @override
  Widget build(BuildContext context, WidgetRef ref) {{
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          '{title}',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.settings, color: AppColors.textSecondary, size: 64),
            const SizedBox(height: 24),
            const Text(
              '{title} Coming Soon',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Configuration for {title} will appear here.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }}
}}
"""

os.makedirs('lib/settings/screens', exist_ok=True)
for filename, class_name, title in screens:
    filepath = os.path.join('lib/settings/screens', filename)
    if not os.path.exists(filepath):
        with open(filepath, 'w') as f:
            f.write(template.format(class_name=class_name, title=title))
            print(f'Created {filepath}')
