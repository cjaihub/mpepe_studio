import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../backend/social/services/recommendation_service.dart';
import 'package:oneova/shared/theme/app_theme.dart';

class FeedControlsScreen extends ConsumerWidget {
  const FeedControlsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        title: Text('Feed Controls', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: context.textPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text(
            'We optimize your feed for relevance, quality, diversity, and safety—not addictive behavior. Use these controls to tune your experience.',
            style: TextStyle(color: context.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),
          _buildControlSection(
            context: context,
            title: 'Content Preferences',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.history, color: context.textPrimary),
                title: Text('Reset Recommendations', style: TextStyle(color: context.textPrimary)),
                subtitle: Text('Clear all learned preferences and start fresh.', style: TextStyle(color: context.textSecondary)),
                onTap: () => _showResetConfirmation(context, ref),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.person_off, color: context.textPrimary),
                title: Text('Hidden Creators', style: TextStyle(color: context.textPrimary)),
                subtitle: Text('Manage creators you have hidden from your feed.', style: TextStyle(color: context.textSecondary)),
                trailing: Icon(Icons.chevron_right, color: context.textMuted),
                onTap: () {
                  // Navigate to hidden creators list
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hidden creators management coming soon.')));
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.tag_faces, color: context.textPrimary),
                title: Text('Hidden Topics', style: TextStyle(color: context.textPrimary)),
                subtitle: Text('Manage topics and hashtags you have muted.', style: TextStyle(color: context.textSecondary)),
                trailing: Icon(Icons.chevron_right, color: context.textMuted),
                onTap: () {
                  // Navigate to hidden topics list
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hidden topics management coming soon.')));
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildControlSection(
            context: context,
            title: 'Playback',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Autoplay Videos', style: TextStyle(color: context.textPrimary)),
                subtitle: Text('Automatically play videos as you scroll.', style: TextStyle(color: context.textSecondary)),
                value: true,
                activeThumbColor: AppColors.brandBlue,
                onChanged: (val) {
                  // Implement autoplay toggle logic
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Start with Sound', style: TextStyle(color: context.textPrimary)),
                subtitle: Text('Videos will start with sound enabled.', style: TextStyle(color: context.textSecondary)),
                value: false,
                activeThumbColor: AppColors.brandBlue,
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

  Widget _buildControlSection({required BuildContext context, required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: context.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.border),
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
        backgroundColor: context.surface,
        title: Text('Reset Recommendations?', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          'This will clear all your hidden creators, muted topics, and learned preferences. Your feed will return to the default state. This cannot be undone.',
          style: TextStyle(color: context.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('Cancel', style: TextStyle(color: context.textMuted)),
          ),
          TextButton(
            onPressed: () {
              ref.read(recommendationServiceProvider).resetRecommendations('currentUser');
              Navigator.pop(c);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recommendations have been reset.')));
            },
            child: const Text('Reset', style: TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
