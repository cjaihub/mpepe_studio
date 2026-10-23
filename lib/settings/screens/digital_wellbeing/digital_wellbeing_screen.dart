import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../backend/digital_wellbeing/services/wellbeing_service.dart';
import '../../../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class DigitalWellbeingScreen extends ConsumerWidget {
  const DigitalWellbeingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(wellbeingPreferencesProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        title: Text('Digital Wellbeing', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: prefsAsync.when(
        data: (prefs) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionTitle(context, 'Screen Time Management'),
            _buildCard(context, [
              SwitchListTile(
                title: Text('Daily Screen Time Reminders', style: TextStyle(color: context.textPrimary)),
                subtitle: Text('Get notified when you reach your limit', style: TextStyle(color: context.textMuted)),
                value: prefs.screenTimeRemindersEnabled,
                activeThumbColor: AppColors.brandBlue,
                onChanged: (val) {
                  // In production: update via service
                },
              ),
              ListTile(
                title: Text('Daily Limit', style: TextStyle(color: context.textPrimary)),
                trailing: Text('${prefs.screenTimeLimitMinutes} mins', style: TextStyle(color: context.textMuted)),
              ),
              SwitchListTile(
                title: Text('Take a Break Reminders', style: TextStyle(color: context.textPrimary)),
                subtitle: Text('Reminds you to look away after continuous scrolling', style: TextStyle(color: context.textMuted)),
                value: prefs.breakRemindersEnabled,
                activeThumbColor: AppColors.brandBlue,
                onChanged: (val) {},
              ),
            ]),

            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Content Experience'),
            _buildCard(context, [
              ListTile(
                title: Text('Feed Layout Mode', style: TextStyle(color: context.textPrimary)),
                subtitle: Text(_formatEnum(prefs.feedMode.name), style: TextStyle(color: context.textMuted)),
                trailing: Icon(Icons.chevron_right, color: context.textMuted),
                onTap: () {
                  // Open modal to select: Algorithmic, Chronological, Following Only, Reduced Recommendations
                },
              ),
              ListTile(
                title: Text('Content Filters', style: TextStyle(color: context.textPrimary)),
                subtitle: Text('Block specific words, hashtags, or topics', style: TextStyle(color: context.textMuted)),
                trailing: Icon(Icons.chevron_right, color: context.textMuted),
                onTap: () {},
              ),
            ]),
            
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Quiet Mode'),
            _buildCard(context, [
              SwitchListTile(
                title: Text('Enable Quiet Mode', style: TextStyle(color: context.textPrimary)),
                subtitle: Text('Mute all notifications during specific hours', style: TextStyle(color: context.textMuted)),
                value: prefs.quietModeEnabled,
                activeThumbColor: AppColors.brandBlue,
                onChanged: (val) {},
              ),
              ListTile(
                title: Text('Quiet Hours Start', style: TextStyle(color: context.textPrimary)),
                trailing: Text('${prefs.quietHoursStart}:00', style: TextStyle(color: context.textMuted)),
              ),
              ListTile(
                title: Text('Quiet Hours End', style: TextStyle(color: context.textPrimary)),
                trailing: Text('${prefs.quietHoursEnd}:00', style: TextStyle(color: context.textMuted)),
              ),
            ]),
          ],
        ),
        loading: () => const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
        error: (e, st) => Center(child: Text('Error loading preferences: $e', style: TextStyle(color: context.textPrimary))),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(color: context.textMuted, fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildCard(BuildContext context, List<Widget> children) {
    return Card(
      color: context.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(children: children),
    );
  }

  String _formatEnum(String str) {
    if (str == 'followingOnly') return 'Following Only';
    if (str == 'reducedRecommendations') return 'Reduced Recommendations';
    return str[0].toUpperCase() + str.substring(1);
  }
}
