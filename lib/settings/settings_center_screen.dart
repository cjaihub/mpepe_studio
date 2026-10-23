import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/settings/settings_models.dart';
import '../backend/settings/settings_service.dart';
import '../shared/modals/app_modals.dart';
import '../shared/theme/app_theme.dart';
import '../backend/ai_agents/omni_command/omni_context_resolver.dart';
import '../features/omni_command/omni_command_sheet.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class SettingsCenterScreen extends ConsumerStatefulWidget {
  const SettingsCenterScreen({super.key});

  @override
  ConsumerState<SettingsCenterScreen> createState() => _SettingsCenterScreenState();
}

class _SettingsCenterScreenState extends ConsumerState<SettingsCenterScreen> {
  int _selectedIndex = 0;

  final List<String> _sections = [
    "Security",
    "Privacy",
    "AI & Automation",
    "Appearance",
    "Data & Export",
  ];

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        elevation: 0,
        title: Text(
          "SETTINGS",
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: 1.5, color: context.textPrimary),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
        error: (err, stack) => Center(child: Text("Error: $err")),
        data: (settings) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sidebar
              Container(
                width: 250,
                color: context.surface.withValues(alpha: 0.5),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  itemCount: _sections.length,
                  itemBuilder: (context, index) {
                    final isSelected = _selectedIndex == index;
                    return ListTile(
                      title: Text(
                        _sections[index],
                        style: GoogleFonts.inter(
                          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                          color: isSelected ? context.textPrimary : context.textMuted,
                        ),
                      ),
                      selected: isSelected,
                      selectedTileColor: AppColors.brandBlue.withValues(alpha: 0.15),
                      onTap: () => setState(() => _selectedIndex = index),
                    );
                  },
                ),
              ),
              // Content
              Expanded(
                child: _buildSectionContent(settings),
              ),
            ],
          );
        },
      ),
      floatingActionButton: OmniCommandButton(
        omniContext: OmniContext(
          sessionId: buildOmniSessionId(),
          userId: FirebaseAuth.instance.currentUser?.uid ?? 'anonymous',
          surface: 'settings',
        ),
      ),
    );
  }

  Widget _buildSectionContent(AppSettings settings) {
    switch (_selectedIndex) {
      case 0: return _buildSecurity(settings);
      case 1: return _buildPrivacy(settings);
      case 2: return _buildAI(settings);
      case 3: return _buildAppearance(settings);
      case 4: return _buildDataExport(settings);
      default: return const SizedBox.shrink();
    }
  }

  Widget _buildSecurity(AppSettings settings) {
    return _SettingsListView(
      title: "SECURITY",
      children: [
        _SettingsSwitch(
          title: "Require Passkey for Login",
          subtitle: "Use biometrics or device passkey to authenticate.",
          value: settings.requirePasskey,
          onChanged: (val) {
            ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(requirePasskey: val));
          },
        ),
        _SettingsSwitch(
          title: "Login Alerts",
          subtitle: "Notify me when my account logs in from a new device.",
          value: settings.loginAlerts,
          onChanged: (val) {
            ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(loginAlerts: val));
          },
        ),
        const SizedBox(height: 24),
        _SettingsAction(
          title: "Revoke All Sessions",
          subtitle: "Sign out of all devices immediately.",
          icon: Icons.logout,
          isDestructive: true,
          onTap: () => AppModals.showDestructive(
            context: context,
            title: "Revoke All Sessions",
            message: "Are you sure you want to sign out of all active sessions globally?",
            onConfirm: () => ref.read(settingsProvider.notifier).revokeAllSessions(),
          ),
        ),
      ],
    );
  }

  Widget _buildPrivacy(AppSettings settings) {
    return _SettingsListView(
      title: "PRIVACY",
      children: [
        _SettingsDropdown<ProfileVisibility>(
          title: "Profile Visibility",
          value: settings.profileVisibility,
          items: ProfileVisibility.values,
          onChanged: (val) {
            if (val != null) ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(profileVisibility: val));
          },
        ),
        _SettingsDropdown<MessagePermissions>(
          title: "Who can message me",
          value: settings.messagePermissions,
          items: MessagePermissions.values,
          onChanged: (val) {
            if (val != null) ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(messagePermissions: val));
          },
        ),
        _SettingsSwitch(
          title: "Read Receipts",
          subtitle: "Let others know when you have read their messages.",
          value: settings.readReceipts,
          onChanged: (val) {
            ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(readReceipts: val));
          },
        ),
      ],
    );
  }

  Widget _buildAI(AppSettings settings) {
    return _SettingsListView(
      title: "AI & AUTOMATION",
      children: [
        _SettingsSwitch(
          title: "Enable AI Core",
          subtitle: "Master toggle for all Oneova AI integrations.",
          value: settings.aiEnabled,
          onChanged: (val) {
            ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(aiEnabled: val));
          },
        ),
        if (settings.aiEnabled) ...[
          _SettingsDropdown<AILocalAgentMode>(
            title: "AI Auto Mode",
            subtitle: "Controls how autonomously the AI can reply.",
            value: settings.autoMode,
            items: AILocalAgentMode.values,
            onChanged: (val) {
              if (val != null) {
                // Sensitive action confirmation rule
                if (val == AILocalAgentMode.fullAuto || val == AILocalAgentMode.autoApprove) {
                  AppModals.showDestructive(
                    context: context,
                    title: "Enable Auto Mode?", 
                    message: "You are granting AI permission to autonomously send messages on your behalf.",
                    onConfirm: () => ref.read(settingsProvider.notifier).setAutoMode(val),
                  );
                } else {
                  ref.read(settingsProvider.notifier).setAutoMode(val);
                }
              }
            },
          ),
          _SettingsSwitch(
            title: "Background Agent",
            subtitle: "Allow AI to process queues while offline.",
            value: settings.backgroundAgentEnabled,
            onChanged: (val) {
              ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(backgroundAgentEnabled: val));
            },
          ),
          _SettingsSwitch(
            title: "AI Personalization",
            subtitle: "Allow AI to learn from your messaging style.",
            value: settings.aiPersonalization,
            onChanged: (val) {
              ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(aiPersonalization: val));
            },
          ),
        ]
      ],
    );
  }

  Widget _buildAppearance(AppSettings settings) {
    return _SettingsListView(
      title: "APPEARANCE & LANGUAGE",
      children: [
        _SettingsSwitch(
          title: "Dark Mode",
          subtitle: "Toggle studio dark theme.",
          value: settings.isDarkMode,
          onChanged: (val) {
            ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(isDarkMode: val));
          },
        ),
      ],
    );
  }

  Widget _buildDataExport(AppSettings settings) {
    return _SettingsListView(
      title: "DATA & ACCOUNT",
      children: [
        _SettingsAction(
          title: "Export Account Data",
          subtitle: "Receive an email with a ZIP of your data.",
          icon: Icons.download,
          onTap: () {
            ref.read(settingsProvider.notifier).exportData();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Export requested. You will receive an email shortly.")));
          },
        ),
        const SizedBox(height: 24),
        _SettingsAction(
          title: "Delete Account",
          subtitle: "Permanently erase all data. This cannot be undone.",
          icon: Icons.delete_forever,
          isDestructive: true,
          onTap: () => AppModals.showDestructive(
            context: context,
            title: "Delete Account",
            message: "This will permanently destroy all your data, messages, and settings. This cannot be undone.",
            isIrreversible: true,
            onConfirm: () => ref.read(settingsProvider.notifier).requestAccountDeletion(),
          ),
        ),
      ],
    );
  }


}

class _SettingsListView extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsListView({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: context.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 32),
        ...children,
      ],
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.surfaceMid.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: GoogleFonts.inter(fontSize: 14, color: context.textMuted)),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.brandBlue,
              inactiveTrackColor: Colors.black45,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsDropdown<T extends Enum> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;

  const _SettingsDropdown({
    required this.title,
    this.subtitle,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.surfaceMid.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: GoogleFonts.inter(fontSize: 14, color: context.textMuted)),
                  ]
                ],
              ),
            ),
            DropdownButton<T>(
              value: value,
              dropdownColor: context.surface,
              underline: const SizedBox.shrink(),
              items: items.map((e) => DropdownMenuItem(
                value: e,
                child: Text(e.name, style: GoogleFonts.inter(color: context.textPrimary)),
              )).toList(),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsAction extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;

  const _SettingsAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? Colors.redAccent : context.textPrimary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDestructive ? Colors.red.withValues(alpha: 0.05) : context.surfaceMid.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDestructive ? Colors.red.withValues(alpha: 0.2) : context.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: GoogleFonts.inter(fontSize: 14, color: color.withValues(alpha: 0.7))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}
