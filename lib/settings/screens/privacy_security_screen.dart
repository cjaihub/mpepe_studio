import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import '../../providers/settings_provider.dart';
import '../commands/update_setting_command.dart';
import '../../shared/undo/undo_manager.dart';
import '../../shared/undo/undo_snackbar.dart';
import 'package:mpepe_studio/auth/screens/mpepe_pin_screen.dart';

class PrivacySecurityScreen extends ConsumerWidget {
  const PrivacySecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: Text('Privacy & Security', style: AppTheme.h2Style),
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
          final privacySettings = settings['privacy'] as Map<String, dynamic>? ?? {};

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            children: [
              _buildSettingsGroup(
                context,
                'Security',
                [
                  _buildSwitch(context, ref, privacySettings, Icons.fingerprint, 'Require Biometrics', 'requireBiometrics', true),
                  _buildSwitch(context, ref, privacySettings, Icons.security, 'Two-Factor Auth', 'twoFactorEnabled', true),
                  _buildActionTile(context, Icons.dialpad, 'Change App PIN', false, () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MpepePinScreen(mode: PinScreenMode.setup),
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 24),
              _buildSettingsGroup(
                context,
                'Data & Privacy',
                [
                  _buildSwitch(context, ref, privacySettings, Icons.public, 'Public Profile', 'publicProfile', true),
                  _buildSwitch(context, ref, privacySettings, Icons.analytics, 'Share Analytics', 'shareAnalytics', false),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSettingsGroup(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 12),
          child: Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
        ),
        MpepeCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitch(BuildContext context, WidgetRef ref, Map<String, dynamic> privacySettings, IconData icon, String title, String key, bool showDivider) {
    final bool oldValue = privacySettings[key] ?? false;
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 22),
          ),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface, fontSize: 15)),
          trailing: Switch(
            value: oldValue,
            onChanged: (newVal) {
              final command = UpdateSettingCommand(
                ref: ref,
                category: 'privacy',
                undoData: {key: oldValue},
                data: {key: newVal},
                name: 'Toggle $title',
              );
              ref.read(undoManagerProvider.notifier).executeAndRegister(command);
              UndoSnackbar.show(context, ref, '$title ${newVal ? 'enabled' : 'disabled'}');
            },
            activeThumbColor: AppColors.mpepeMaroon,
          ),
        ),
        if (showDivider)
          Divider(height: 1, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1), indent: 70, endIndent: 20),
      ],
    );
  }

  Widget _buildActionTile(BuildContext context, IconData icon, String title, bool showDivider, VoidCallback onTap) {
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 22),
          ),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface, fontSize: 15)),
          trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
        ),
        if (showDivider)
          Divider(height: 1, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1), indent: 70, endIndent: 20),
      ],
    );
  }
}
