import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova/backend/mask_engine/api/mask_engine_provider.dart';
import 'package:oneova/shared/theme/app_theme.dart';

class MaskStackPanel extends ConsumerWidget {
  const MaskStackPanel({super.key});

  Future<void> _confirmDeleteMask(
    BuildContext context,
    WidgetRef ref,
    String layerId,
    String layerName,
  ) async {
    HapticFeedback.lightImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: ctx.border),
        ),
        title: Text(
          'Delete Mask Layer',
          style: TextStyle(
            color: ctx.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Remove "$layerName" from the mask stack?',
          style: TextStyle(color: ctx.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: ctx.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandPink,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(maskLayerManagerProvider).removeLayer(layerId);
    }
  }

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
            color: context.surface.withValues(alpha: 0.92),
            border: Border(right: BorderSide(color: context.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  'MASKS',
                  style: TextStyle(
                    color: context.textSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              Divider(height: 1, color: context.border),
              Expanded(
                child: layers.isEmpty
                    ? Center(
                        child: Text(
                          'No masks created',
                          style: TextStyle(color: context.textSecondary, fontSize: 12),
                        ),
                      )
                    : ListView.builder(
                        itemCount: layers.length,
                        itemBuilder: (context, index) {
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
                                      color: layer.isVisible ? context.textPrimary : context.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      layer.name,
                                      style: TextStyle(
                                        color: isActive ? AppColors.brandBlue : context.textPrimary,
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
                                      color: layer.isLocked ? context.textPrimary : context.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: layer.isLocked
                                        ? null
                                        : () => _confirmDeleteMask(context, ref, layer.id, layer.name),
                                    child: Icon(
                                      Icons.delete_outline,
                                      size: 16,
                                      color: layer.isLocked ? context.textMuted : context.textSecondary,
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
      },
    );
  }
}
