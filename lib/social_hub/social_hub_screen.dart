import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../backend/social_connection_service.dart';
class SocialHubScreen extends ConsumerWidget {
  const SocialHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionsState = ref.watch(socialConnectionProvider);
    final connections = connectionsState.value ?? [];
    bool isConnected(String p) => connections.any((c) => c.platform.toLowerCase() == p.toLowerCase());
    
    final connectedCount = connections.where((c) => c.platform.toLowerCase() != 'youtube').length + 1;

    return StudioBackground(
      backgroundIcons: const [Icons.hub_outlined, Icons.people_outline, Icons.dashboard_outlined],
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.push('/hub/home');
                  }
                },
                child: Row(
                  children: [
                    Icon(Icons.chevron_left, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Studio Home',
                      style: AppTheme.bodyStyle.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text('Social Media', style: AppTheme.h1Style),
              const SizedBox(height: 8),
              Text(
                'Every platform, linked in one place',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13),
              ),
              const SizedBox(height: 18),
              MpepeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL REACH',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
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
                      '$connectedCount of 4 platforms connected',
                      style: AppTheme.bodyStyle.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _PlatformCard(
                title: 'YouTube',
                subtitle: '7 channels • 862K reach',
                logoAsset: 'assets/logos/youtube.svg',
                connected: true,
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/hub/home');
                  }
                },
              ),
              const SizedBox(height: 10),
              _PlatformCard(
                title: 'Facebook',
                subtitle: isConnected('Facebook') ? 'Connected' : 'Not connected',
                logoAsset: 'assets/logos/facebook.svg',
                connected: isConnected('Facebook'),
                onTap: () => isConnected('Facebook') ? null : context.push('/social_hub/connect_wizard', extra: 'Facebook'),
              ),
              const SizedBox(height: 10),
              _PlatformCard(
                title: 'Instagram',
                subtitle: isConnected('Instagram') ? 'Connected' : 'Not connected',
                logoAsset: 'assets/logos/instagram.svg',
                connected: isConnected('Instagram'),
                onTap: () => isConnected('Instagram') ? null : context.push('/social_hub/connect_wizard', extra: 'Instagram'),
              ),
              const SizedBox(height: 10),
              _PlatformCard(
                title: 'TikTok',
                subtitle: isConnected('TikTok') ? 'Connected' : 'Not connected',
                logoAsset: 'assets/logos/tiktok.svg',
                connected: isConnected('TikTok'),
                onTap: () => isConnected('TikTok') ? null : context.push('/social_hub/connect_wizard', extra: 'TikTok'),
              ),
              const SizedBox(height: 18),
              Text(
                'Connecting a platform hands you to its own sign-in — MPEPE never asks for a password directly.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

}

class _PlatformCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Gradient? gradient;
  final Border? border;
  final Color iconWidgetColor;
  final bool connected;
  final VoidCallback onTap;
  final String? logoAsset;

  const _PlatformCard({
    required this.title,
    required this.subtitle,
    required this.connected,
    required this.onTap,
    this.logoAsset,
  }) : icon = null, iconColor = null, gradient = null, border = null, iconWidgetColor = Colors.white;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MpepeCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (logoAsset != null)
              SizedBox(
                width: 44,
                height: 44,
                child: SvgPicture.asset(logoAsset!),
              )
            else
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
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12),
                  ),
                ],
              ),
            ),
            if (connected)
              Row(
                children: [
                  _PulseDot(color: AppColors.neonGreen),
                  const SizedBox(width: 6),
                  Text('Live', style: TextStyle(color: AppColors.neonGreen, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Connect',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
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

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.6),
              blurRadius: 6,
              spreadRadius: 2,
            )
          ],
        ),
      ),
    );
  }
}
