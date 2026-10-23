import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/oneova_feature_tour_service.dart';
import '../theme/app_theme.dart';

class OneovaFeatureTourBubble extends ConsumerStatefulWidget {
  final VoidCallback? onDismiss;
  final ValueChanged<int>? onStepChanged;

  const OneovaFeatureTourBubble({
    super.key,
    this.onDismiss,
    this.onStepChanged,
  });

  @override
  ConsumerState<OneovaFeatureTourBubble> createState() => _OneovaFeatureTourBubbleState();
}

class _OneovaFeatureTourBubbleState extends ConsumerState<OneovaFeatureTourBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _nextStep(int currentStep) {
    HapticFeedback.lightImpact();
    if (currentStep < OneovaFeatureTourService.steps.length - 1) {
      final nextIdx = currentStep + 1;
      ref.read(featureTourCurrentStepProvider.notifier).setStep(nextIdx);
      widget.onStepChanged?.call(nextIdx);
    } else {
      _finishTour();
    }
  }

  void _prevStep(int currentStep) {
    HapticFeedback.lightImpact();
    if (currentStep > 0) {
      final prevIdx = currentStep - 1;
      ref.read(featureTourCurrentStepProvider.notifier).setStep(prevIdx);
      widget.onStepChanged?.call(prevIdx);
    }
  }

  void _finishTour() {
    HapticFeedback.mediumImpact();
    ref.read(featureTourServiceProvider).markTourCompleted();
    ref.read(featureTourVisibilityProvider.notifier).hide();
    widget.onDismiss?.call();
  }

  void _skipTour() {
    HapticFeedback.selectionClick();
    ref.read(featureTourServiceProvider).markTourCompleted();
    ref.read(featureTourVisibilityProvider.notifier).hide();
    widget.onDismiss?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isVisible = ref.watch(featureTourVisibilityProvider);
    final currentStep = ref.watch(featureTourCurrentStepProvider);
    final totalSteps = OneovaFeatureTourService.steps.length;
    final step = OneovaFeatureTourService.steps[currentStep.clamp(0, totalSteps - 1)];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isBottomTarget = step.targetArea.startsWith('nav_');

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      left: 16,
      right: 16,
      bottom: isBottomTarget ? 78 : 110,
      child: IgnorePointer(
        ignoring: !isVisible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          opacity: isVisible ? 1.0 : 0.0,
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: [
                  BoxShadow(
                    color: step.accentColor.withValues(alpha: isDark ? 0.35 : 0.18),
                    blurRadius: 28,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.surface.withValues(alpha: isDark ? 0.88 : 0.94),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: step.accentColor.withValues(alpha: 0.45),
                        width: 1.0,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Header Row: Animated Icon + Badge + Skip Button ────────
                        Row(
                          children: [
                            // Advanced Animated Icon with Pulsing Halo & Micro Transforms
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, _) {
                                final pulseValue = _pulseController.value;
                                final scaleVal = 0.94 + (pulseValue * 0.12);
                                final rotAngle = -0.05 + (pulseValue * 0.10);

                                return Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        step.accentColor.withValues(alpha: 0.9),
                                        step.accentColor == AppColors.brandBlue
                                            ? AppColors.brandPink.withValues(alpha: 0.8)
                                            : AppColors.brandBlue.withValues(alpha: 0.8),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: step.accentColor.withValues(alpha: 0.4 + (pulseValue * 0.3)),
                                        blurRadius: 10 + (pulseValue * 6),
                                        spreadRadius: pulseValue * 2,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Transform.scale(
                                      scale: scaleVal,
                                      child: Transform.rotate(
                                        angle: rotAngle,
                                        child: Icon(
                                          step.icon,
                                          size: 20,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 10),

                        // Badge & Step Counter
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: step.accentColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(AppRadius.xs),
                                  border: Border.all(
                                    color: step.accentColor.withValues(alpha: 0.3),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  step.badge,
                                  style: GoogleFonts.inter(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                    color: step.accentColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                step.title,
                                style: GoogleFonts.inter(
                                  fontSize: 14.0,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                  color: context.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),

                        // Skip Version Button
                        InkWell(
                          onTap: _skipTour,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                            decoration: BoxDecoration(
                              color: context.surfaceMid,
                              borderRadius: BorderRadius.circular(AppRadius.full),
                              border: Border.all(color: context.border, width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Skip',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.brandPink,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Icon(
                                  Icons.close_rounded,
                                  size: 13,
                                  color: AppColors.brandPink,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // ── Body Description ───────────────────────────────────────
                    Text(
                      step.description,
                      style: GoogleFonts.inter(
                        fontSize: 12.0,
                        fontWeight: FontWeight.w400,
                        height: 1.35,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Footer: Dots Indicator & Action Buttons ─────────────────
                    Row(
                      children: [
                        // Progress Dots (7 steps)
                        Row(
                          children: List.generate(totalSteps, (i) {
                            final isActive = (i == currentStep);
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 240),
                              margin: const EdgeInsets.only(right: 4),
                              width: isActive ? 16 : 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? step.accentColor
                                    : context.border.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(AppRadius.full),
                              ),
                            );
                          }),
                        ),
                        const Spacer(),

                        // Back Button (if past first step)
                        if (currentStep > 0) ...[
                          InkWell(
                            onTap: () => _prevStep(currentStep),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            child: Container(
                              height: 32,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: context.surfaceMid,
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                                border: Border.all(color: context.border, width: 0.8),
                              ),
                              child: Text(
                                'Back',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: context.textSecondary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],

                        // Next / Got It Button
                        InkWell(
                          onTap: () => _nextStep(currentStep),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          child: Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  step.accentColor,
                                  step.accentColor == AppColors.brandBlue
                                      ? const Color(0xFF1E6FD9)
                                      : const Color(0xFFFF529D),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              boxShadow: [
                                BoxShadow(
                                  color: step.accentColor.withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  currentStep == totalSteps - 1 ? 'Start Exploring' : 'Next',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  currentStep == totalSteps - 1
                                      ? Icons.check_circle_rounded
                                      : Icons.arrow_forward_rounded,
                                  size: 13,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
