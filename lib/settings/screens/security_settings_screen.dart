import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import '../../providers/settings_provider.dart';
import '../commands/update_setting_command.dart';
import '../../shared/undo/undo_manager.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class SecuritySettingsScreen extends ConsumerWidget {
  const SecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: Text('Security Settings', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: context.topBarFg)),
        backgroundColor: AppColors.brandBlue,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: context.topBarFg, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: AnimatedLoadingIndicator()),
        error: (e, s) => Center(child: Text('Error: $e', style: TextStyle(color: context.textSecondary))),
        data: (settings) {
          final categoryData = settings['security'] as Map<String, dynamic>? ?? {};

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildSwitch(context, ref, categoryData, 'twoFactorAuth', 'Two-Factor Authentication', 'Require a 2FA code to login'),
              _buildSwitch(context, ref, categoryData, 'passkeys', 'Passkeys', 'Allow login with FaceID / TouchID'),
              _buildSwitch(context, ref, categoryData, 'loginAlerts', 'Login Alerts', 'Get notified of new logins from unrecognized devices'),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSwitch(BuildContext context, WidgetRef ref, Map<String, dynamic> currentData, String key, String title, String subtitle) {
    final value = currentData[key] as bool? ?? false;
    return OnerovaCard(
      child: SwitchListTile(
        value: value,
        title: Text(title, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: TextStyle(color: context.textSecondary)),
        activeThumbColor: AppColors.brandBlue,
        onChanged: (newValue) {
          final newData = Map<String, dynamic>.from(currentData);
          newData[key] = newValue;
          final command = UpdateSettingCommand(
            ref: ref,
            category: 'security',
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
