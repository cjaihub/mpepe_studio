import 'package:flutter/material.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';

class HubActivityScreen extends StatelessWidget {
  const HubActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
          children: [
            const Text('Activity', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
            const SizedBox(height: 8),
            const Text('Across every module in your studio', style: TextStyle(color: AppColors.ashText, fontSize: 13)),
            const SizedBox(height: 18),
            _buildActivityRow(
              title: 'Riverside Shorts crossed 250K subscribers',
              meta: 'YouTube · 2 hours ago',
              icon: Icons.play_arrow,
              iconColor: AppColors.ytAccent,
            ),
            _buildActivityRow(
              title: 'Episode 12 rough cut ready for review',
              meta: 'Video Production · 5 hours ago · Amara',
              icon: Icons.movie,
              iconColor: Colors.deepPurple,
            ),
            _buildActivityRow(
              title: '"Late Nights" finished mastering',
              meta: 'Audio Production · 1 day ago',
              icon: Icons.graphic_eq,
              iconColor: Colors.teal,
            ),
            _buildActivityRow(
              title: 'Gemini suggests posting Thursday at 6 PM for peak reach',
              meta: 'AI Assistant · 1 day ago',
              icon: Icons.auto_awesome,
              isAi: true,
            ),
            _buildActivityRow(
              title: 'Upload complete — "How I Edit Cinematic Travel Vlogs"',
              meta: 'YouTube · 3 days ago',
              icon: Icons.cloud_done,
              iconColor: AppColors.ytAccent,
            ),
            _buildActivityRow(
              title: 'Amara K. joined as Video Editor',
              meta: 'Team · 4 days ago',
              icon: Icons.person_add,
              iconColor: AppColors.surface2,
              iconWidgetColor: AppColors.ashText,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityRow({
    required String title,
    required String meta,
    required IconData icon,
    Color? iconColor,
    Color? iconWidgetColor = Colors.white,
    bool isAi = false,
  }) {
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
            child: Icon(icon, color: iconWidgetColor, size: 16),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(meta, style: const TextStyle(fontSize: 11, color: AppColors.dustText, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
