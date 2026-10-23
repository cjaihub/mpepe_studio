import os

TEMPLATE = """import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';

class {className} extends StatelessWidget {
  const {className}({super.key});

  @override
  Widget build(BuildContext context) {
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
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          MpepeCard(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.{icon}, size: 64, color: AppColors.mpepeMaroon),
                const SizedBox(height: 16),
                Text('{emptyTitle}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('{emptySubtitle}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.mpepeMaroon,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: const Text('{buttonText}', style: TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
"""

screens = [
    {
        "file": "sessions_screen.dart",
        "className": "SessionsScreen",
        "title": "Active Sessions",
        "icon": "devices",
        "emptyTitle": "1 Active Session",
        "emptySubtitle": "You are currently logged in only on this device.",
        "buttonText": "Revoke All Other Sessions"
    },
    {
        "file": "blocked_users_screen.dart",
        "className": "BlockedUsersScreen",
        "title": "Blocked Users",
        "icon": "person_off",
        "emptyTitle": "No Blocked Users",
        "emptySubtitle": "When you block someone, they won't be able to message you or see your profile.",
        "buttonText": "Add User"
    },
    {
        "file": "security_devices_screen.dart",
        "className": "SecurityDevicesScreen",
        "title": "Trusted Devices",
        "icon": "security",
        "emptyTitle": "No Trusted Devices",
        "emptySubtitle": "Add a device to bypass 2FA when logging in.",
        "buttonText": "Add Current Device"
    },
    {
        "file": "connected_channels_screen.dart",
        "className": "ConnectedChannelsScreen",
        "title": "Connected Channels",
        "icon": "link",
        "emptyTitle": "No Connected Channels",
        "emptySubtitle": "Connect your YouTube, Meta, or TikTok accounts to sync messages and streams.",
        "buttonText": "Connect Account"
    },
    {
        "file": "data_export_screen.dart",
        "className": "DataExportScreen",
        "title": "Data Export",
        "icon": "cloud_download",
        "emptyTitle": "Export Your Data",
        "emptySubtitle": "Request a copy of your messages, settings, and profile data (GDPR compliant).",
        "buttonText": "Request Export"
    },
    {
        "file": "help_support_screen.dart",
        "className": "HelpSupportScreen",
        "title": "Help & Support",
        "icon": "support_agent",
        "emptyTitle": "How can we help?",
        "emptySubtitle": "Reach out to our support team or view our FAQ.",
        "buttonText": "Contact Support"
    },
    {
        "file": "about_screen.dart",
        "className": "AboutScreen",
        "title": "About",
        "icon": "info",
        "emptyTitle": "MPEPE STUDIO",
        "emptySubtitle": "Version 1.0.0\\n\\nBuilt with ❤️ by the MPEPE Team.",
        "buttonText": "View Terms & Privacy Policy"
    }
]

for s in screens:
    content = TEMPLATE.replace("{className}", s["className"]) \
                      .replace("{title}", s["title"]) \
                      .replace("{icon}", s["icon"]) \
                      .replace("{emptyTitle}", s["emptyTitle"]) \
                      .replace("{emptySubtitle}", s["emptySubtitle"]) \
                      .replace("{buttonText}", s["buttonText"])
    with open(f"lib/settings/screens/{s['file']}", "w") as f:
        f.write(content)

print("Generated mock screens")
