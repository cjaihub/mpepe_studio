import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/theme/app_theme.dart';
import '../controllers/cloud_vision_controller.dart';
import '../models/cloud_vision_models.dart';

/// Interactive configuration sheet for AI Upscale, Denoise, and 60FPS interpolation.
class AiEnhanceSheet extends ConsumerWidget {
  final VoidCallback onExecute;

  const AiEnhanceSheet({
    super.key,
    required this.onExecute,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cloudVisionControllerProvider);
    final notifier = ref.read(cloudVisionControllerProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.upgrade_rounded, size: 18, color: AppColors.brandBlue),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'AI Visual Enhancement',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.3)),
              ),
              child: Text(
                'GPU Tensor L4',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandBlue,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...AiEnhanceMode.values.map((mode) {
          final isSelected = state.selectedEnhanceMode == mode;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              onTap: () => notifier.selectEnhanceMode(mode),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.brandBlue.withValues(alpha: 0.12)
                      : context.surfaceMid,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? AppColors.brandBlue : context.border,
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                      size: 16,
                      color: isSelected ? AppColors.brandBlue : context.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mode.label,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? AppColors.brandBlue : context.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            mode.description,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ElevatedButton(
            onPressed: state.isProcessing ? null : onExecute,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (state.isProcessing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                else
                  const Icon(Icons.bolt_rounded, size: 16),
                const SizedBox(width: 8),
                Text(
                  state.isProcessing ? 'Enhancing on Cloud GPU...' : 'Start AI Enhance (1 Credit)',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
