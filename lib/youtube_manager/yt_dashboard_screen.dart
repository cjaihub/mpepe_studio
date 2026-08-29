import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';

class YtDashboardScreen extends StatelessWidget {
  const YtDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('YouTube Manager', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.go('/'), // Return to Hub
            tooltip: 'Back to Hub',
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildQuickStats(),
          const SizedBox(height: 24),
          const Text('Recent Uploads', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _buildVideoItem('How I Edit Cinematic Travel Vlogs', '10K views · 3 days ago', 'Riverside Shorts', true),
          _buildVideoItem('The Ultimate Desk Setup 2026', '45K views · 1 week ago', 'Tech Connect', false),
          const SizedBox(height: 24),
          const Text('AI Insights', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          MpepeCard(
            borderColor: AppColors.ytAccent.withOpacity(0.3),
            child: Row(
              children: [
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) => AppColors.aiGradient.createShader(bounds),
                  child: const Icon(Icons.auto_awesome, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Your recent shorts are performing 20% better when posted between 4 PM and 6 PM.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/yt/upload'),
        backgroundColor: AppColors.ytAccent,
        child: const Icon(Icons.upload, color: Colors.white),
      ),
    );
  }

  Widget _buildQuickStats() {
    return Row(
      children: [
        Expanded(
          child: MpepeCard(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Column(
              children: const [
                Text('Total Views', style: TextStyle(color: AppColors.dustText, fontSize: 12)),
                SizedBox(height: 4),
                Text('2.4M', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MpepeCard(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Column(
              children: const [
                Text('Subscribers', style: TextStyle(color: AppColors.dustText, fontSize: 12)),
                SizedBox(height: 4),
                Text('862K', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoItem(String title, String stats, String channel, bool isLive) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MpepeCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 80,
              height: 45,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.play_circle_outline, color: AppColors.ashText),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  const SizedBox(height: 4),
                  Text('$channel · $stats', style: const TextStyle(color: AppColors.dustText, fontSize: 11)),
                ],
              ),
            ),
            if (isLive)
              const MpepePill(text: 'Live', isLive: true)
          ],
        ),
      ),
    );
  }
}
