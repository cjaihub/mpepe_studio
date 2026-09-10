import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../shared/theme/app_theme.dart';
import '../shared/theme/theme_provider.dart';
import '../shared/widgets/studio_background.dart';
import '../shared/widgets/components.dart';
import '../providers/settings_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../auth/services/secure_logout_service.dart';

class MainSettingsScreen extends ConsumerWidget {
  const MainSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final user = FirebaseAuth.instance.currentUser;
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;

    return StudioBackground(
      backgroundIcons: const [Icons.settings, Icons.tune, Icons.person],
      appBar: AppBar(
        title: Text('Studio Settings', style: AppTheme.h2Style.copyWith(color: Theme.of(context).colorScheme.onSurface)),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.push('/hub/home');
            }
          },
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
        error: (err, stack) => Center(child: Text('Error loading settings: $err', style: TextStyle(color: Colors.red))),
        data: (settings) {
          final profile = settings['profile'] as Map<String, dynamic>? ?? {};
          final displayName = profile['displayName']?.toString().isNotEmpty == true 
              ? profile['displayName'] 
              : (user?.displayName ?? 'Studio Creator');
              
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            children: [
              // User Profile Summary
              MpepeCard(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: AppColors.mpepeMaroon,
                      backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                      child: user?.photoURL == null 
                          ? Text(displayName[0].toUpperCase(), style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold))
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displayName, style: AppTheme.h2Style.copyWith(fontSize: 20)),
                          const SizedBox(height: 4),
                          Text(user?.email ?? '', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, color: AppColors.mpepeGold),
                      onPressed: () => context.push('/settings/profile'),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),
              
              const SizedBox(height: 32),
              
              _buildSettingsGroup(
                context,
                'Preferences',
                [
                  _buildSettingsTile(context, Icons.phone_android, 'App Settings', 'Calls, messaging, connection', true, '/settings/app'),
                  _buildSettingsTile(context, Icons.notifications, 'Notifications', 'Push & alert preferences', true, '/settings/notifications'),
                  _buildSettingsTile(context, Icons.auto_awesome, 'AI Assistant', 'Models & tone settings', false, '/settings/ai'),
                ],
              ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),
              
              const SizedBox(height: 24),
              
              _buildSettingsGroup(
                context,
                'Integrations',
                [
                  _buildSettingsTile(context, Icons.video_library, 'YouTube Settings', 'Upload defaults & channels', true, '/yt/settings'),
                  _buildSettingsTile(context, Icons.share, 'Social Accounts', 'Meta, Instagram, TikTok', false, '/social_hub'),
                ],
              ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),
              
              const SizedBox(height: 24),
              
              _buildSettingsGroup(
                context,
                'Security',
                [
                  _buildSettingsTile(context, Icons.lock, 'Privacy & Security', 'App lock, 2FA, analytics', false, '/settings/privacy'),
                ],
              ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),
              
              const SizedBox(height: 40),
              
              MpepeCard(
                padding: EdgeInsets.zero,
                child: InkWell(
                  onTap: () async {
                    await ref.read(secureLogoutServiceProvider).logout();
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout, color: Colors.red.shade400, size: 20),
                        const SizedBox(width: 8),
                        Text('Sign Out', style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 400.ms),
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
        MpepeCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTile(BuildContext context, IconData icon, String title, String subtitle, bool showDivider, String route) {
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
          onTap: () => context.push(route),
        ),
        if (showDivider)
          Divider(height: 1, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1), indent: 70, endIndent: 20),
      ],
    );
  }
}
