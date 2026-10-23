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
        "file": "notification_settings_screen.dart",
        "className": "NotificationSettingsScreen",
        "title": "Notifications",
        "categoryKey": "notifications",
        "widgets": [
            build_switch("push", "Push Notifications", "Receive push alerts for new messages"),
            build_switch("email", "Email Alerts", "Receive a daily digest of unread messages via email"),
            build_switch("inApp", "In-App Banners", "Show banners when the app is open"),
            build_switch("sounds", "Notification Sounds", "Play a sound on new messages"),
        ]
    },
    {
        "file": "calls_settings_screen.dart",
        "className": "CallsSettingsScreen",
        "title": "Calls Settings",
        "categoryKey": "calls",
        "widgets": [
            build_switch("allowVideo", "Allow Video by Default", "Automatically turn on camera when joining calls"),
            build_switch("allowMic", "Allow Mic by Default", "Automatically unmute when joining calls"),
            build_switch("noiseCancellation", "Noise Cancellation", "Filter out background noise automatically"),
        ]
    },
    {
        "file": "ai_settings_screen.dart",
        "className": "AiSettingsScreen",
        "title": "AI Settings",
        "categoryKey": "ai",
        "widgets": [
            build_switch("aiEnabled", "Enable MPEPE AI", "Allow AI to run in the background for your account"),
            build_switch("smartReplies", "Smart Replies", "Show AI-generated quick reply suggestions"),
            build_switch("summaries", "Thread Summaries", "Automatically summarize long message threads"),
        ]
    },
    {
        "file": "ai_personalization_screen.dart",
        "className": "AiPersonalizationScreen",
        "title": "AI Personalization",
        "categoryKey": "ai_personalization",
        "widgets": [
            build_switch("memory", "Infinite Memory", "Allow AI to remember details from past conversations"),
            build_switch("toneMatching", "Tone Matching", "AI replies will try to match your typing style"),
            build_switch("proactive", "Proactive Assistance", "AI will suggest actions before you ask"),
        ]
    },
    {
        "file": "background_agent_settings_screen.dart",
        "className": "BackgroundAgentSettingsScreen",
        "title": "Background Agent",
        "categoryKey": "background_agent",
        "widgets": [
            build_switch("autonomousMode", "Autonomous Mode", "Allow the agent to take actions while you are offline"),
            build_switch("requireApproval", "Require Approval", "Ask for confirmation before sending messages"),
            build_switch("rateLimits", "Strict Rate Limits", "Prevent the agent from messaging too frequently"),
        ]
    },
    {
        "file": "automation_settings_screen.dart",
        "className": "AutomationSettingsScreen",
        "title": "Automation Engine",
        "categoryKey": "automation",
        "widgets": [
            build_switch("engineEnabled", "Engine Enabled", "Master toggle for all your workflows"),
            build_switch("logExecution", "Log Execution", "Keep a detailed history of all workflow triggers"),
            build_switch("failureAlerts", "Failure Alerts", "Notify me when a workflow fails to run"),
        ]
    },
    {
        "file": "storage_settings_screen.dart",
        "className": "StorageSettingsScreen",
        "title": "Storage & Data",
        "categoryKey": "storage",
        "widgets": [
            build_switch("autoDownloadWifi", "Auto-download on Wi-Fi", "Automatically download photos and videos"),
            build_switch("autoDownloadCellular", "Auto-download on Cellular", "May consume significant data"),
            build_switch("saveToGallery", "Save to Gallery", "Automatically save incoming media to device gallery"),
        ]
    },
    {
        "file": "app_settings_screen.dart",
        "className": "AppSettingsScreen",
        "title": "App Settings",
        "categoryKey": "app",
        "widgets": [
            build_switch("analytics", "Share Analytics", "Help us improve MPEPE by sharing anonymous usage data"),
            build_switch("crashReports", "Crash Reports", "Send crash reports to developers"),
            build_switch("developerMode", "Developer Mode", "Enable advanced debugging features"),
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

print("Generated more settings")
