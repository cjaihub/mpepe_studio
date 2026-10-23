import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova/backend/mask_engine/api/mask_engine_provider.dart';
import 'package:oneova/shared/theme/app_theme.dart';

class MaskStackPanel extends ConsumerWidget {
  const MaskStackPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layerManager = ref.watch(maskLayerManagerProvider);
    final layers = layerManager.layers;

    return ListenableBuilder(
      listenable: layerManager,
      builder: (context, _) {
        return Container(
          width: 240,
          decoration: BoxDecoration(
            color: AppColors.darkSurface.withValues(alpha: 0.85),
            border: Border(right: BorderSide(color: AppColors.outline.withValues(alpha: 0.5))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.all(12.0),
                child: Text('MASKS', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              const Divider(height: 1, color: Colors.white12),
              Expanded(
                child: layers.isEmpty
                    ? const Center(
                        child: Text('No masks created', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      )
                    : ListView.builder(
                        itemCount: layers.length,
                        itemBuilder: (context, index) {
                          // Reverse order to show newest on top (typical stack)
                          final layer = layers[layers.length - 1 - index];
                          final isActive = layerManager.activeLayerId == layer.id;
    
                          return InkWell(
                            onTap: () {
                              ref.read(maskLayerManagerProvider).selectLayer(layer.id);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              color: isActive ? AppColors.brandBlue.withValues(alpha: 0.2) : Colors.transparent,
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => ref.read(maskLayerManagerProvider).toggleLayerVisibility(layer.id),
                                    child: Icon(
                                      layer.isVisible ? Icons.visibility : Icons.visibility_off,
                                      size: 18,
                                      color: layer.isVisible ? AppColors.textPrimary : AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      layer.name,
                                      style: TextStyle(
                                        color: isActive ? AppColors.brandBlue : AppColors.textPrimary,
                                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => ref.read(maskLayerManagerProvider).toggleLayerLock(layer.id),
                                    child: Icon(
                                      layer.isLocked ? Icons.lock : Icons.lock_open,
                                      size: 16,
                                      color: layer.isLocked ? AppColors.textPrimary : AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () {
                                      // TODO: Delete logic
                                    },
                                    child: const Icon(
                                      Icons.delete_outline,
                                      size: 16,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      }
    );
  }
}
