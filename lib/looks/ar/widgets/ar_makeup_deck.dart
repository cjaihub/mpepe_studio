import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/theme/app_theme.dart';
import '../controllers/ar_effect_controller.dart';

/// Compact adjustment sliders for dynamic AR makeup and hair coloring.
class ArMakeupDeck extends ConsumerWidget {
  const ArMakeupDeck({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(arEffectControllerProvider);
    final notifier = ref.read(arEffectControllerProvider.notifier);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.face_retouching_natural_rounded, size: 16, color: AppColors.brandPink),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'AR Makeup & Hair',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Live Neural Shader',
                style: TextStyle(fontSize: 10, color: context.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildSliderRow(
            context: context,
            label: 'Lip Tint',
            value: state.lipTintOpacity,
            onChanged: notifier.updateLipstick,
          ),
          _buildSliderRow(
            context: context,
            label: 'Cheek Blush',
            value: state.blushOpacity,
            onChanged: notifier.updateBlush,
          ),
          _buildSliderRow(
            context: context,
            label: 'Eyeliner',
            value: state.eyelinerOpacity,
            onChanged: notifier.updateEyeliner,
          ),
          _buildSliderRow(
            context: context,
            label: 'Hair Hue',
            value: state.hairHue / 360.0,
            onChanged: (v) => notifier.updateHairHue(v * 360.0),
            customDisplay: '${state.hairHue.toInt()}°',
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required BuildContext context,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    String? customDisplay,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 75,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: context.textSecondary),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.0,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
              ),
              child: Slider(
                value: value.clamp(0.0, 1.0),
                activeColor: AppColors.brandPink,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              customDisplay ?? '${(value * 100).toInt()}%',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
