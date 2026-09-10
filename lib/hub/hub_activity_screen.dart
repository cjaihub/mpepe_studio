import 'package:flutter/material.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/studio_background.dart';

class HubActivityScreen extends StatelessWidget {
  const HubActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StudioBackground(
      backgroundIcons: const [Icons.hub_outlined, Icons.people_outline, Icons.dashboard_outlined],
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
          children: [
            Text('Activity', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.4, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 8),
            Text('Across every module in your studio', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13)),
            const SizedBox(height: 18),
            _buildActivityRow(
              context: context,
              title: 'Riverside Shorts crossed 250K subscribers',
              meta: 'YouTube · 2 hours ago',
              icon: Icons.play_arrow,
              iconColor: Theme.of(context).colorScheme.primary,
            ),
            _buildActivityRow(
              context: context,
              title: 'Episode 12 rough cut ready for review',
              meta: 'Video Production · 5 hours ago · Amara',
              icon: Icons.movie,
              iconColor: Colors.deepPurple,
            ),
            _buildActivityRow(
              context: context,
              title: '"Late Nights" finished mastering',
              meta: 'Audio Production · 1 day ago',
              icon: Icons.graphic_eq,
              iconColor: Colors.teal,
            ),
            _buildActivityRow(
              context: context,
              title: 'Gemini suggests posting Thursday at 6 PM for peak reach',
              meta: 'AI Assistant · 1 day ago',
              icon: Icons.auto_awesome,
              isAi: true,
            ),
            _buildActivityRow(
              context: context,
              title: 'Upload complete — "How I Edit Cinematic Travel Vlogs"',
              meta: 'YouTube · 3 days ago',
              icon: Icons.cloud_done,
              iconColor: Theme.of(context).colorScheme.primary,
            ),
            _buildActivityRow(
              context: context,
              title: 'Amara K. joined as Video Editor',
              meta: 'Team · 4 days ago',
              icon: Icons.person_add,
              iconColor: Theme.of(context).colorScheme.surface,
              iconWidgetColor: Theme.of(context).colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityRow({
    required BuildContext context,
    required String title,
    required String meta,
    required IconData icon,
    Color? iconColor,
    Color? iconWidgetColor,
    bool isAi = false,
  }) {
    final effectiveIconWidgetColor = iconWidgetColor ?? Theme.of(context).colorScheme.onPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: isAi ? null : iconColor,
              gradient: isAi ? AppColors.aiGradient : null,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: effectiveIconWidgetColor, size: 16),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 4),
                Text(meta, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
