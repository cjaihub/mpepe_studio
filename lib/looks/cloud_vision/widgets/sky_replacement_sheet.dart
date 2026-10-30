import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/theme/app_theme.dart';
import '../controllers/cloud_vision_controller.dart';
import '../models/cloud_vision_models.dart';

/// Interactive configuration sheet for AI sky segmentation & atmospheric replacement.
class SkyReplacementSheet extends ConsumerWidget {
  final VoidCallback onExecute;

  const SkyReplacementSheet({
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
                  const Icon(Icons.cloud_sync_rounded, size: 18, color: Colors.cyan),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'AI Sky Replacement',
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
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.cyan.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.cyan.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'Harmonizer',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.cyan,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Horizontal Sky Presets
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: SkyPreset.defaultPresets.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final preset = SkyPreset.defaultPresets[index];
              final isSelected = state.selectedSky.id == preset.id;

              return GestureDetector(
                onTap: () => notifier.selectSkyPreset(preset),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 110,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.brandBlue.withValues(alpha: 0.15)
                        : context.surfaceMid,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? AppColors.brandBlue : context.border,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        preset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                          color: isSelected ? AppColors.brandBlue : context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        preset.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9.5, color: context.textMuted),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // Horizon Height Slider
        Row(
          children: [
            SizedBox(
              width: 85,
              child: Text(
                'Horizon Line',
                style: TextStyle(fontSize: 11, color: context.textSecondary),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: state.skyHorizonOffset,
                  min: -0.5,
                  max: 0.5,
                  activeColor: AppColors.brandBlue,
                  onChanged: notifier.updateSkyHorizon,
                ),
              ),
            ),
            SizedBox(
              width: 35,
              child: Text(
                '${(state.skyHorizonOffset * 100).toInt()}%',
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.textPrimary),
              ),
            ),
          ],
        ),
        // Spill Blend Slider
        Row(
          children: [
            SizedBox(
              width: 85,
              child: Text(
                'Spill Blend',
                style: TextStyle(fontSize: 11, color: context.textSecondary),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: state.skyAtmosphericBlend,
                  min: 0.0,
                  max: 1.0,
                  activeColor: AppColors.brandBlue,
                  onChanged: notifier.updateSkyBlend,
                ),
              ),
            ),
            SizedBox(
              width: 35,
              child: Text(
                '${(state.skyAtmosphericBlend * 100).toInt()}%',
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.textPrimary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
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
                  const Icon(Icons.cloud_sync_rounded, size: 16),
                const SizedBox(width: 8),
                Text(
                  state.isProcessing ? 'Harmonizing Sky Lighting...' : 'Replace Sky & Blend (1 Credit)',
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
