import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/theme/app_theme.dart';
import '../controllers/cloud_vision_controller.dart';

/// Interactive configuration sheet for neural relighting with normal-map estimation.
class RelightSheet extends ConsumerWidget {
  final VoidCallback onExecute;

  const RelightSheet({
    super.key,
    required this.onExecute,
  });

  static const List<Map<String, dynamic>> _lightPresets = [
    {'name': 'Studio White', 'hex': '#FFFFFF', 'color': Colors.white},
    {'name': 'Golden Hour', 'hex': '#FFB347', 'color': Color(0xFFFFB347)},
    {'name': 'Cyber Pink', 'hex': '#FF2D87', 'color': AppColors.brandPink},
    {'name': 'Neon Cyan', 'hex': '#00FFFF', 'color': Color(0xFF00FFFF)},
    {'name': 'Amber Flame', 'hex': '#FF7A00', 'color': Color(0xFFFF7A00)},
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cloudVisionControllerProvider);
    final notifier = ref.read(cloudVisionControllerProvider.notifier);
    final relight = state.relightConfig;

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
                  const Icon(Icons.light_mode_rounded, size: 18, color: Colors.amber),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Neural 3D Relighting',
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
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'Raymarch',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.amber,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Interactive 2D/3D Light Position Pad
        Text(
          'Light Source Position (X / Y)',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.textSecondary),
        ),
        const SizedBox(height: 6),
        Container(
          height: 90,
          decoration: BoxDecoration(
            color: context.surfaceMid,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.border),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final posX = (relight.lightPosition[0] * constraints.maxWidth).clamp(10.0, constraints.maxWidth - 20.0);
              final posY = (relight.lightPosition[1] * constraints.maxHeight).clamp(10.0, constraints.maxHeight - 20.0);

              return GestureDetector(
                onPanUpdate: (details) {
                  final newX = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                  final newY = (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
                  notifier.updateRelightPosition(newX, newY, relight.lightPosition[2]);
                },
                child: Stack(
                  children: [
                    Center(
                      child: Text(
                        'Drag to position virtual key light',
                        style: TextStyle(fontSize: 11, color: context.textMuted),
                      ),
                    ),
                    Positioned(
                      left: posX - 10,
                      top: posY - 10,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _hexToColor(relight.lightColorHex),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: _hexToColor(relight.lightColorHex).withValues(alpha: 0.6),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // Color Swatches
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Light Color',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.textSecondary),
            ),
            Row(
              children: _lightPresets.map((preset) {
                final isSelected = relight.lightColorHex == preset['hex'];
                final color = preset['color'] as Color;
                return GestureDetector(
                  onTap: () => notifier.updateRelightColor(preset['hex'] as String),
                  child: Container(
                    margin: const EdgeInsets.only(left: 6),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? AppColors.brandBlue : context.border,
                        width: isSelected ? 2.5 : 1.0,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Intensity Slider
        Row(
          children: [
            SizedBox(
              width: 60,
              child: Text(
                'Intensity',
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
                  value: relight.intensity,
                  min: 0.0,
                  max: 3.0,
                  activeColor: AppColors.brandBlue,
                  onChanged: notifier.updateRelightIntensity,
                ),
              ),
            ),
            SizedBox(
              width: 35,
              child: Text(
                relight.intensity.toStringAsFixed(1),
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
                  const Icon(Icons.wb_sunny_rounded, size: 16),
                const SizedBox(width: 8),
                Text(
                  state.isProcessing ? 'Computing Neural Relighting...' : 'Apply Relighting (1 Credit)',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static Color _hexToColor(String hex) {
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return Colors.white;
  }
}
