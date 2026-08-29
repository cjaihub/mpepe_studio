import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';

class SocialHubScreen extends StatelessWidget {
  const SocialHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => context.go('/hub/home'),
                child: Row(
                  children: [
                    const Icon(Icons.chevron_left, color: AppColors.dust, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Studio Home',
                      style: AppTheme.bodyStyle.copyWith(
                        color: AppColors.dust,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text('Social Media', style: AppTheme.h1Style),
              const SizedBox(height: 8),
              const Text(
                'Every platform, linked in one place',
                style: TextStyle(color: AppColors.dust, fontSize: 13),
              ),
              const SizedBox(height: 18),
              MpepeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TOTAL REACH',
                      style: TextStyle(
                        color: AppColors.dust,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '862K',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '1 of 4 platforms connected',
                      style: AppTheme.bodyStyle.copyWith(color: AppColors.dust, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _PlatformCard(
                title: 'YouTube',
                subtitle: '7 channels • 862K reach',
                icon: Icons.play_arrow_rounded,
                iconColor: AppColors.red,
                connected: true,
                onTap: () => context.go('/auth/youtube'),
              ),
              const SizedBox(height: 10),
              _PlatformCard(
                title: 'Facebook',
                subtitle: 'Not connected',
                icon: Icons.facebook,
                iconColor: const Color(0xFF0866ff),
                connected: false,
                onTap: () => _showComingSoon(context, 'Facebook', 'Link your Facebook Pages to cross-post and track performance alongside YouTube.'),
              ),
              const SizedBox(height: 10),
              _PlatformCard(
                title: 'Instagram',
                subtitle: 'Not connected',
                icon: Icons.camera_alt_outlined,
                iconColor: Colors.transparent,
                gradient: const LinearGradient(
                  colors: [Color(0xFFf09433), Color(0xFFbc1888)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                connected: false,
                onTap: () => _showComingSoon(context, 'Instagram', 'Cross-post Reels, track engagement, and let AI repurpose your top YouTube videos.'),
              ),
              const SizedBox(height: 10),
              _PlatformCard(
                title: 'TikTok',
                subtitle: 'Not connected',
                icon: Icons.music_note_outlined,
                iconColor: Colors.black,
                border: Border.all(color: AppColors.line),
                iconWidgetColor: const Color(0xFF25f4ee),
                connected: false,
                onTap: () => _showComingSoon(context, 'TikTok', 'Link TikTok to publish Shorts-ready cuts straight from your studio.'),
              ),
              const SizedBox(height: 18),
              const Text(
                'Connecting a platform hands you to its own sign-in — MPEPE never asks for a password directly.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.dust, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String platform, String description) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Coming Soon: $platform - $description')),
    );
  }
}

class _PlatformCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Gradient? gradient;
  final Border? border;
  final Color iconWidgetColor;
  final bool connected;
  final VoidCallback onTap;

  const _PlatformCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    this.gradient,
    this.border,
    this.iconWidgetColor = Colors.white,
    required this.connected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: connected ? Border.all(color: AppColors.line) : Border.all(color: AppColors.line, style: BorderStyle.solid),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: gradient == null ? iconColor : null,
                gradient: gradient,
                borderRadius: BorderRadius.circular(13),
                border: border,
              ),
              child: Center(
                child: Icon(icon, color: iconWidgetColor, size: 24),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.dust, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (connected)
              MpepePill(
                label: 'Connected',
                color: AppColors.mint,
                isGhost: true,
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Connect',
                  style: TextStyle(
                    color: AppColors.dust,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
