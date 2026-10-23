import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';
import '../../providers/settings_provider.dart';
import '../commands/update_setting_command.dart';
import '../../shared/undo/undo_manager.dart';
import '../../shared/undo/undo_snackbar.dart';
import '../widgets/settings_kit.dart';

/// App Settings Screen
/// Controls calling, instant messaging persistence, and desktop workstation links.
/// Universal dual-mode (Light/Dark), high-density compact scale, and instant auto-save.
class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              'App Settings',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: context.topBarFg,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 8),
            _buildAutoSavePill(context),
          ],
        ),
        backgroundColor: AppColors.brandBlue,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: context.topBarFg, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: settingsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.brandBlue),
        ),
        error: (e, s) => Center(
          child: Text('Error: $e', style: const TextStyle(color: AppColors.brandPink)),
        ),
        data: (settings) {
          final appSettings = settings['app'] as Map<String, dynamic>? ?? {};

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              _buildSettingsGroup(
                context,
                'Communication & Sessions',
                [
                  _buildSwitch(context, ref, appSettings, Icons.phone_rounded, 'Calls Enabled', 'Audio & video incoming call sessions', 'callsEnabled', true),
                  _buildSwitch(context, ref, appSettings, Icons.chat_rounded, 'Messaging Enabled', 'Receive incoming direct & team messages', 'messagingEnabled', true),
                  _buildSwitch(context, ref, appSettings, Icons.history_rounded, 'Save Chat History', 'Retain chat transcripts locally on this device', 'saveHistory', false),
                ],
              ),
              const SizedBox(height: 20),
              _buildSettingsGroup(
                context,
                'Workstation Integrations',
                [
                  _buildSwitch(context, ref, appSettings, Icons.desktop_windows_rounded, 'Desktop Auto-Connect', 'Automatically sync with Studio PC/Mac daemon', 'desktopAutoConnect', false),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAutoSavePill(BuildContext context) {
    return const SettingsSaveIndicator();
  }

  Widget _buildSettingsGroup(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            title.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.brandBlue,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border, width: 1.0),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitch(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> appSettings,
    IconData icon,
    String title,
    String subtitle,
    String key,
    bool showDivider,
  ) {
    final bool oldValue = appSettings[key] ?? false;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Icon(icon, color: AppColors.brandBlue, size: 17),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 13.0,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1.5),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 11.0,
                        color: context.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: oldValue,
                  onChanged: (newVal) {
                    final command = UpdateSettingCommand(
                      ref: ref,
                      category: 'app',
                      undoData: {key: oldValue},
                      data: {key: newVal},
                      name: 'Toggle $title',
                    );
                    ref.read(undoManagerProvider.notifier).executeAndRegister(command);
                    UndoSnackbar.show(context, ref, '$title ${newVal ? 'enabled' : 'disabled'}');
                  },
                  activeThumbColor: AppColors.brandBlue,
                  activeTrackColor: AppColors.brandBlue.withValues(alpha: 0.35),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: context.border, indent: 58, endIndent: 14),
      ],
    );
  }
}
