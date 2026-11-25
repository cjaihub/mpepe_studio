import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';
import '../backend/social_connection_service.dart';
import 'components/tiktok_profile_panel.dart';

class SocialIntegrationDashboard extends ConsumerWidget {
  const SocialIntegrationDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionsState = ref.watch(socialConnectionProvider);
    final connections = connectionsState.value ?? [];
    
    bool isConnected(String p) => connections.any((c) => c.platform.toLowerCase() == p.toLowerCase());
    bool hasYoutube = isConnected('youtube');
    bool hasTiktok = isConnected('tiktok');
    bool hasFacebook = isConnected('facebook');
    bool hasInstagram = isConnected('instagram');

    return Scaffold(
      body: StudioBackground(
        backgroundIcons: const [Icons.share, Icons.video_camera_back, Icons.auto_awesome],
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context),
                      const SizedBox(height: 24),
                      _buildConnectionStatusCard(context, hasYoutube, hasTiktok, hasFacebook, hasInstagram),
                      const SizedBox(height: 16),
                      _buildReelsCard(context),
                      if (hasTiktok) ...[
                        const SizedBox(height: 24),
                        const TikTokProfilePanel(),
                      ],
                      const SizedBox(height: 32),
                      if (connections.isNotEmpty) ...[
                        _buildSectionTitle(context, 'Core Automation'),
                        const SizedBox(height: 16),
                        _buildFeatureGrid(context),
                        const SizedBox(height: 32),
                        _buildSectionTitle(context, 'Growth & Analytics'),
                        const SizedBox(height: 16),
                        _buildAnalyticsCommandCenter(context),
                      ] else ...[
                        _buildLockedState(context),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'upload_hub',
            onPressed: () => context.push('/upload/global'),
            backgroundColor: AppColors.mpepeGold,
            icon: const Icon(Icons.cloud_upload, color: Colors.black),
            label: const Text('Global Upload', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          if (hasTiktok) 
            FloatingActionButton.extended(
              heroTag: 'tiktok_assistant',
              onPressed: () => context.push('/social_hub/tiktok_assistant'),
              backgroundColor: AppColors.mpepeMaroon,
              icon: const Icon(Icons.mic, color: AppColors.mpepeGold),
              label: const Text('AI Manager', style: TextStyle(color: AppColors.mpepeGold, fontWeight: FontWeight.bold)),
            ),
        ],
      ).animate().scale(delay: 500.ms, duration: 400.ms, curve: Curves.easeOutBack),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.pop();
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
        Text('Social Integrations', style: AppTheme.h1Style).animate().fade().slideY(begin: -0.2, curve: Curves.easeOutCubic),
        const SizedBox(height: 8),
        Text(
          'Unified Accounts & AI Sync',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary, 
            fontSize: 14, 
            fontWeight: FontWeight.bold,
          ),
        ).animate().fade(delay: 100.ms),
      ],
    );
  }

  Widget _buildConnectionStatusCard(BuildContext context, bool hasYoutube, bool hasTiktok, bool hasFacebook, bool hasInstagram) {
    return MpepeCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPlatformNode(
                context, 
                'YouTube', 
                'assets/logos/youtube.svg', 
                hasYoutube,
                onTap: hasYoutube ? null : () => context.push('/auth/youtube'),
              ),
              _buildPlatformNode(
                context, 
                'TikTok', 
                'assets/logos/tiktok.svg', 
                hasTiktok,
                onTap: hasTiktok ? null : () => context.push('/social_hub/tiktok_wizard'),
              ),
              _buildPlatformNode(
                context, 
                'Instagram', 
                'assets/logos/instagram.svg', 
                hasInstagram,
                onTap: hasInstagram ? null : () => context.push('/social_hub/meta_wizard/instagram'),
              ),
              _buildPlatformNode(
                context, 
                'Facebook', 
                'assets/logos/facebook.svg', 
                hasFacebook,
                onTap: hasFacebook ? null : () => context.push('/social_hub/meta_wizard/facebook'),
              ),
            ],
          ),
          if (!hasYoutube || !hasTiktok || !hasFacebook || !hasInstagram) ...[
            const SizedBox(height: 24),
            Text(
              'Connect your platforms to unlock cross-platform features without pasting API keys.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
            const MpepePill(text: 'All Core Platforms Connected', color: Color(0xFF00E676), isGhost: true),
          ]
        ],
      ),
    ).animate().fade(duration: 400.ms).slideY(begin: 0.1);
  }

  Widget _buildPlatformNode(BuildContext context, String name, String asset, bool connected, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? Theme.of(context).colorScheme.surface : Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
              border: Border.all(
                color: connected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline,
                width: 2,
              ),
              boxShadow: connected ? [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 15,
                  spreadRadius: 2,
                )
              ] : [],
            ),
            child: SvgPicture.asset(asset, 
              colorFilter: connected ? null : const ColorFilter.mode(Colors.grey, BlendMode.srcIn),
            ),
          ),
          const SizedBox(height: 8),
          Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildConnectionLine(BuildContext context, bool active) {
    return Expanded(
      child: Container(
        height: 4,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          color: active ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }

  /// Our own reels feed. Always available: it does not need a connected
  /// platform.
  Widget _buildReelsCard(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return MpepeCard(
      child: Row(
        children: [
          const Icon(Icons.slow_motion_video, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Reels', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('Watch and post short videos', style: TextStyle(color: muted, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Post a reel',
            icon: const Icon(Icons.add_box_outlined),
            onPressed: () => context.push('/social_hub/reels/post'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.mpepeMaroon),
            onPressed: () => context.push('/social_hub/reels'),
            child: const Text('Watch'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: -0.5),
    );
  }

  Widget _buildFeatureGrid(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 0.85,
      children: [
        _buildFeatureCard(context, 'Smart Sync', 'Auto-publish Long-form to Shorts', Icons.sync_alt, AppColors.premiumGradient, null),
        _buildFeatureCard(context, 'AI Cropper', 'Face-tracking 16:9 to 9:16', Icons.crop_free, AppColors.aiGradient, null),
        _buildFeatureCard(context, 'Auto-Caption', 'Dynamic animated text', Icons.subtitles, null, null),
        _buildFeatureCard(context, 'Unified Inbox', 'Moderate YT & TT comments', Icons.inbox, null, () => context.push('/social_hub/unified_inbox')),
      ],
    ).animate().fade().slideY(begin: 0.2);
  }

  Widget _buildFeatureCard(BuildContext context, String title, String subtitle, IconData icon, Gradient? gradient, VoidCallback? onTap) {
    return MpepeCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap ?? () {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: gradient,
              color: gradient == null ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1) : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: gradient == null ? Theme.of(context).colorScheme.primary : Colors.white),
          ),
          const Spacer(),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  Widget _buildAnalyticsCommandCenter(BuildContext context) {
    return MpepeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Cross-Platform Health', style: TextStyle(fontWeight: FontWeight.bold)),
              MpepePill(text: '+12% this week', color: Colors.green, isGhost: true),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _buildStatColumn(context, 'Combined Reach', '2.4M')),
              Container(width: 1, height: 40, color: Theme.of(context).colorScheme.outline),
              Expanded(child: _buildStatColumn(context, 'Unified Revenue', '\$12.5K')),
            ],
          ),
          const SizedBox(height: 24),
          MpepeButton(
            text: 'View Full Report',
            onPressed: () => context.push('/social_hub/analytics'),
            isPrimary: false,
            icon: Icons.analytics,
          ),
        ],
      ),
    ).animate().fade().slideY(begin: 0.2);
  }

  Widget _buildStatColumn(BuildContext context, String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -1.0)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
      ],
    );
  }

  Widget _buildLockedState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.lock_outline, size: 48, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            'Features Locked',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect both platforms to enable the automation suite.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
          ),
        ],
      ),
    ).animate().fade(delay: 300.ms);
  }
}
