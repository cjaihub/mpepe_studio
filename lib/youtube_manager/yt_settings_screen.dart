import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../shared/theme/theme_provider.dart';
import '../shared/widgets/studio_background.dart';
import '../shared/widgets/components.dart';
import '../providers/settings_provider.dart';

class YtSettingsScreen extends ConsumerWidget {
  const YtSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;

    return StudioBackground(
      backgroundIcons: const [Icons.settings, Icons.security, Icons.cloud_sync],
      appBar: AppBar(
        title: Text('YouTube Settings', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Theme.of(context).colorScheme.onSurface)),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () {
              ref.read(themeProvider.notifier).toggleTheme();
            },
          ),
        ],
      ),
      child: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
        data: (settings) {
          final notifSettings = settings['notifications'] as Map<String, dynamic>? ?? {};
          
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            children: [
              _buildSettingsGroup(
                context,
                'Account & Security',
                [
                  _buildSettingsTile(context, Icons.account_circle, 'Linked Accounts', 'Manage connected Google accounts', true),
                  _buildSettingsTile(context, Icons.security, 'App Permissions', 'View what Oneova can access', false),
                ],
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),
              
              const SizedBox(height: 24),
              _buildSettingsGroup(
                context,
                'Upload Defaults',
                [
                  _buildSettingsTile(context, Icons.privacy_tip, 'Default Privacy', 'Private', true),
                  _buildSettingsTile(context, Icons.category, 'Default Category', 'Science & Technology', true),
                  _buildSettingsTile(context, Icons.language, 'Video Language', 'English (US)', false),
                ],
              ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),
              
              const SizedBox(height: 24),
              _buildSettingsGroup(
                context,
                'Notifications',
                [
                  _buildSettingsSwitch(context, ref, notifSettings, Icons.notifications, 'Upload Alerts', 'uploadAlerts', true),
                  _buildSettingsSwitch(context, ref, notifSettings, Icons.comment, 'Comments & Mentions', 'commentsMentions', true),
                  _buildSettingsSwitch(context, ref, notifSettings, Icons.trending_up, 'Milestone Alerts', 'milestoneAlerts', false),
                ],
              ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),
              
              const SizedBox(height: 32),
              OneovaCard(
                padding: EdgeInsets.zero,
                child: InkWell(
                  onTap: () {},
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout, color: Colors.red.shade400, size: 20),
                        const SizedBox(width: 8),
                        Text('Sign Out of YouTube', style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 300.ms),
              const SizedBox(height: 40),
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
        OneovaCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTile(BuildContext context, IconData icon, String title, String subtitle, bool showDivider) {
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
          subtitle: Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12)),
          trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
          onTap: () {},
        ),
        if (showDivider)
          Divider(height: 1, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1), indent: 70, endIndent: 20),
      ],
    );
  }
  
  Widget _buildSettingsSwitch(BuildContext context, WidgetRef ref, Map<String, dynamic> notifSettings, IconData icon, String title, String key, bool showDivider) {
    final bool value = notifSettings[key] ?? false;
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
            value: value,
            onChanged: (val) {
              ref.read(settingsProvider.notifier).updateSetting('notifications', key, val);
            },
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
        ),
        if (showDivider)
          Divider(height: 1, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1), indent: 70, endIndent: 20),
      ],
    );
  }
}
