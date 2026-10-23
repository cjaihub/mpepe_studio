import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../backend/user_profile_completion_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../widgets/oneova_assistant_overlay.dart';

/// Interactive card displaying profile completion progress, algorithmic boost status,
/// and clickable action chips that open real editor sheets and update Firestore.
class ProfileCompletionReminderCard extends ConsumerWidget {
  final VoidCallback? onCompleteTap;

  const ProfileCompletionReminderCard({
    super.key,
    this.onCompleteTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(userProfileCompletionStateProvider);
    final service = ref.read(userProfileCompletionServiceProvider);

    return asyncState.when(
      data: (state) {
        if (state.isComplete) return const SizedBox.shrink();

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
        final surfaceMid = isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight;
        final borderColor = isDark ? AppColors.outline : AppColors.lightBorder;
        final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
        final textSecondary = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: borderColor, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: const Icon(Icons.rocket_launch_rounded, size: 16, color: AppColors.brandBlue),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Profile ${state.percentage}% Complete',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: AppColors.brandPink.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                state.audienceMultiplier,
                                style: GoogleFonts.inter(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.brandPink,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Algorithmic Distribution Boost Waiting',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.brandPink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      if (onCompleteTap != null) {
                        onCompleteTap!();
                      } else if (state.missingItems.isNotEmpty) {
                        service.executeAction(context, state.missingItems.first.id);
                      }
                    },
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.brandBlue,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        'Finish Now',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),

              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: state.percentage / 100.0,
                  backgroundColor: surfaceMid,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.brandBlue),
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 8),

              // Algorithmic advice
              Text(
                state.algorithmicAdvice,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: textSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 9),

              // Interactive Action Chips
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...state.missingItems.map((item) {
                    return InkWell(
                      onTap: () => service.executeAction(context, item.id),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: surfaceMid,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                          border: Border.all(color: borderColor, width: 1.0),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(item.icon, size: 11, color: AppColors.brandBlue),
                            const SizedBox(width: 4),
                            Text(
                              '+ ${item.title}',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  // Ova AI prompt pill
                  InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      OneOvaAssistantOverlay.show(
                        context,
                        initialPrompt: 'How can I optimize my profile niches and tags to get more views in the For You algorithm?',
                      );
                    },
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.brandPink.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.3), width: 1.0),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome, size: 11, color: AppColors.brandPink),
                          const SizedBox(width: 4),
                          Text(
                            'Ask Ova AI',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandPink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
    );
  }
}
