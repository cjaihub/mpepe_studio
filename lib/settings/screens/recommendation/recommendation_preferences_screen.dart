import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../backend/recommendation/services/recommendation_preferences_service.dart';
import '../../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class RecommendationPreferencesScreen extends ConsumerWidget {
  const RecommendationPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(recommendationPreferencesProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Content Preferences', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: prefsAsync.when(
        data: (prefs) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionTitle(context, 'Recommendation Engine'),
            _buildResetButton(context, ref),
            
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Hidden Topics'),
            if (prefs.hiddenTopics.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text('No hidden topics', style: TextStyle(color: context.textMuted)),
              )
            else
              ...prefs.hiddenTopics.map((t) => Card(
                color: context.surface,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  side: BorderSide(color: context.border, width: 1.0),
                ),
                child: ListTile(
                  title: Text(t, style: TextStyle(color: context.textPrimary)),
                  trailing: const Icon(Icons.remove_circle, color: AppColors.brandBlue),
                  onTap: () {}, // unhide
                ),
              )),
              
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Hidden Creators'),
            if (prefs.hiddenCreators.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text('No hidden creators', style: TextStyle(color: context.textMuted)),
              )
            else
              ...prefs.hiddenCreators.map((c) => Card(
                color: context.surface,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  side: BorderSide(color: context.border, width: 1.0),
                ),
                child: ListTile(
                  title: Text('Creator ID: $c', style: TextStyle(color: context.textPrimary)),
                  trailing: const Icon(Icons.remove_circle, color: AppColors.brandBlue),
                  onTap: () {}, // unhide
                ),
              )),

            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Explicit Interests'),
            if (prefs.explicitInterests.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text('No explicit interests set. Watch more to build your profile.', style: TextStyle(color: context.textMuted)),
              )
            else
              ...prefs.explicitInterests.entries.map((e) => Card(
                color: context.surface,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  side: BorderSide(color: context.border, width: 1.0),
                ),
                child: ListTile(
                  title: Text(e.key, style: TextStyle(color: context.textPrimary)),
                  trailing: Text('${(e.value * 100).toInt()}%', style: const TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.bold)),
                ),
              )),
          ],
        ),
        loading: () => const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
        error: (e, st) => Center(child: Text('Error loading preferences: $e', style: TextStyle(color: context.textSecondary))),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(color: context.textSecondary, fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildResetButton(BuildContext context, WidgetRef ref) {
    return Card(
      color: context.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: context.border, width: 1.0),
      ),
      child: ListTile(
        leading: const Icon(Icons.refresh, color: AppColors.brandBlue),
        title: Text('Reset Recommendations', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        subtitle: Text('Clear your watch history profile and start fresh.', style: TextStyle(color: context.textSecondary)),
        onTap: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: ctx.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                side: BorderSide(color: ctx.border, width: 1.0),
              ),
              title: Text('Reset Recommendations?', style: TextStyle(color: ctx.textPrimary, fontWeight: FontWeight.bold)),
              content: Text('This will wipe your behavioral profile. This cannot be undone.', style: TextStyle(color: ctx.textSecondary)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('Cancel', style: TextStyle(color: ctx.textMuted)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
          
          if (confirm == true) {
            await ref.read(recommendationPreferencesServiceProvider).resetRecommendations();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Recommendations reset.'), backgroundColor: AppColors.brandBlue),
              );
            }
          }
        },
      ),
    );
  }
}
