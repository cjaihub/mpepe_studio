import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../backend/social/services/recommendation_service.dart';
import '../../shared/theme/app_theme.dart';

class FeedControlsScreen extends ConsumerWidget {
  const FeedControlsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        title: const Text('Feed Controls', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'We optimize your feed for relevance, quality, diversity, and safety—not addictive behavior. Use these controls to tune your experience.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),
          _buildControlSection(
            title: 'Content Preferences',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history, color: Colors.white),
                title: const Text('Reset Recommendations', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Clear all learned preferences and start fresh.', style: TextStyle(color: AppColors.textSecondary)),
                onTap: () => _showResetConfirmation(context, ref),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_off, color: Colors.white),
                title: const Text('Hidden Creators', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Manage creators you have hidden from your feed.', style: TextStyle(color: AppColors.textSecondary)),
                trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                onTap: () {
                  // Navigate to hidden creators list
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hidden creators management coming soon.')));
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tag_faces, color: Colors.white),
                title: const Text('Hidden Topics', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Manage topics and hashtags you have muted.', style: TextStyle(color: AppColors.textSecondary)),
                trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                onTap: () {
                  // Navigate to hidden topics list
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hidden topics management coming soon.')));
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildControlSection(
            title: 'Playback',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Autoplay Videos', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Automatically play videos as you scroll.', style: TextStyle(color: AppColors.textSecondary)),
                value: true,
                activeThumbColor: AppColors.mpepeMaroon,
                onChanged: (val) {
                  // Implement autoplay toggle logic
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start with Sound', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Videos will start with sound enabled.', style: TextStyle(color: AppColors.textSecondary)),
                value: false,
                activeThumbColor: AppColors.mpepeMaroon,
                onChanged: (val) {
                  // Implement default sound logic
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlSection({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(children: children),
        ),
      ],
    );
  }

  void _showResetConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Reset Recommendations?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'This will clear all your hidden creators, muted topics, and learned preferences. Your feed will return to the default state. This cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              ref.read(recommendationServiceProvider).resetRecommendations(currentSocialUid());
              Navigator.pop(c);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recommendations have been reset.')));
            },
            child: const Text('Reset', style: TextStyle(color: AppColors.mpepeMaroon, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
