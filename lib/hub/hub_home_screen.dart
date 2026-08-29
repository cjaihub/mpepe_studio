import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';

class HubHomeScreen extends StatelessWidget {
  const HubHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    MpepeAvatar(
                      text: 'M',
                      size: 26,
                      gradient: LinearGradient(
                        colors: [Color(0xFFFF8A00), Color(0xFFFF3D00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text('MPEPE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: -0.2)),
                  ],
                ),
                Row(
                  children: [
                    IconButton(icon: const Icon(Icons.search, color: AppColors.ashText), onPressed: () {}),
                    IconButton(icon: const Icon(Icons.notifications, color: AppColors.ashText), onPressed: () => context.go('/activity')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text('Good evening', style: TextStyle(color: AppColors.ashText, fontSize: 13)),
            const SizedBox(height: 2),
            const Text('Riverside Studio', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
            const SizedBox(height: 14),
            MpepeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('STUDIO OVERVIEW', style: TextStyle(color: AppColors.dustText, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                  const SizedBox(height: 4),
                  const Text('862K', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
                  const Text('Total audience across connected platforms', style: TextStyle(color: AppColors.dustText, fontSize: 11, fontWeight: FontWeight.w500)),
                  const Divider(color: AppColors.lineSoft, height: 28),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      MpepePill(text: '● YouTube · 862K', isLive: true),
                      MpepePill(text: 'Instagram · connect', isOutline: true),
                      MpepePill(text: 'TikTok · connect', isOutline: true),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text('5 projects in production · 2 tracks mastering', style: TextStyle(color: AppColors.dustText, fontSize: 11, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text('Your apps', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.15,
              children: [
                _buildAppTile(
                  context,
                  title: 'YouTube Manager',
                  meta: '7 channels linked',
                  icon: Icons.play_arrow,
                  iconColor: AppColors.ytAccent,
                  onTap: () => context.go('/yt/dashboard'),
                ),
                _buildAppTile(
                  context,
                  title: 'Video Production',
                  meta: '5 in edit',
                  icon: Icons.movie,
                  iconColor: Colors.deepPurple,
                  onTap: () => context.go('/video/dashboard'),
                ),
                _buildAppTile(
                  context,
                  title: 'Audio Production',
                  meta: '2 mastering',
                  icon: Icons.graphic_eq,
                  iconColor: Colors.teal,
                  onTap: () => context.go('/audio/dashboard'),
                ),
                _buildAppTile(
                  context,
                  title: 'Social Hub',
                  meta: '1 platform connected',
                  icon: Icons.share,
                  iconColor: Colors.grey,
                  onTap: () => context.go('/social_hub'),
                ),
                _buildAppTile(
                  context,
                  title: 'AI Assistant',
                  meta: 'Ask Gemini anything',
                  icon: Icons.auto_awesome,
                  isAi: true,
                  onTap: () => context.go('/hub_ai'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppTile(BuildContext context, {required String title, required String meta, required IconData icon, Color? iconColor, bool isAi = false, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: MpepeCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isAi ? null : iconColor,
                gradient: isAi ? AppColors.aiGradient : null,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const Spacer(),
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(meta, style: const TextStyle(fontSize: 11, color: AppColors.dustText)),
          ],
        ),
      ),
    );
  }
}
