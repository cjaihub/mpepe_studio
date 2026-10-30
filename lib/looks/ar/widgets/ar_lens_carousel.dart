import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/theme/app_theme.dart';
import '../controllers/ar_effect_controller.dart';
import '../models/ar_effect_package.dart';

/// Circular Snap/TikTok-style bottom lens selector with category tabs.
class ArLensCarousel extends ConsumerWidget {
  const ArLensCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(arEffectControllerProvider);
    final notifier = ref.read(arEffectControllerProvider.notifier);
    final lenses = state.filteredPackages;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Category Pills Row
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: ArCategory.values.length,
            separatorBuilder: (context, index) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final cat = ArCategory.values[index];
              final isSelected = state.activeCategory == cat;

              return GestureDetector(
                onTap: () => notifier.selectCategory(cat),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.brandBlue.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? AppColors.brandBlue : Colors.white12,
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(cat.icon, style: const TextStyle(fontSize: 11)),
                      const SizedBox(width: 4),
                      Text(
                        cat.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // Circular Lens Thumbnails Dock
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: lenses.length + 1, // +1 for "None / Clear" button
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                // Clear button
                final isNoneSelected = state.activeEffect == null;
                return GestureDetector(
                  onTap: notifier.clearEffect,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isNoneSelected
                              ? AppColors.brandBlue.withValues(alpha: 0.3)
                              : Colors.white10,
                          border: Border.all(
                            color: isNoneSelected ? AppColors.brandBlue : Colors.white30,
                            width: isNoneSelected ? 2.5 : 1.0,
                          ),
                        ),
                        child: const Icon(
                          Icons.not_interested_rounded,
                          size: 24,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'None',
                        style: TextStyle(fontSize: 9.5, color: Colors.white70),
                      ),
                    ],
                  ),
                );
              }

              final lens = lenses[index - 1];
              final isSelected = state.activeEffect?.id == lens.id;

              return GestureDetector(
                onTap: () => notifier.selectEffect(lens),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.brandBlue.withValues(alpha: 0.8),
                            AppColors.brandPink.withValues(alpha: 0.8),
                          ],
                        ),
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: isSelected ? 2.5 : 0.0,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppColors.brandPink.withValues(alpha: 0.6),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Icon(
                          _getIconForCategory(lens.category),
                          size: 22,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 56,
                      child: Text(
                        lens.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _getIconForCategory(ArCategory cat) {
    switch (cat) {
      case ArCategory.trending:
        return Icons.whatshot_rounded;
      case ArCategory.makeup:
        return Icons.face_retouching_natural_rounded;
      case ArCategory.masks:
        return Icons.masks_rounded;
      case ArCategory.fx3d:
        return Icons.auto_awesome_rounded;
      case ArCategory.backgrounds:
        return Icons.videocam_rounded;
    }
  }
}
