import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/theme/app_theme.dart';
import '../data/shop3d_repository.dart';
import '../models/shop_models.dart';

/// Entry to Oneova 3D Shops from the Biz area: browse showrooms, or set up /
/// manage your own shop.
class ShopsEntryCard extends ConsumerWidget {
  const ShopsEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myShopProvider).value;
    final liveCount = ref.watch(liveShopsProvider).length;
    final myLabel = switch (mine?.status) {
      null => 'Open a shop',
      ShopStatus.open => 'My shop',
      _ => 'Finish setup',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () {
            HapticFeedback.lightImpact();
            context.push('/shops');
          },
          child: Ink(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: AppDecorations.groupedSection(context),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: AppShadows.glow(AppColors.brandBlue, radius: 12, spread: 0),
                  ),
                  child: const Icon(Icons.view_in_ar_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('3D Shops', style: AppTypography.title3(context.textPrimary)),
                          if (liveCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.brandPink,
                                borderRadius: BorderRadius.circular(AppRadius.full),
                              ),
                              child: Text('LIVE', style: AppTypography.micro(Colors.white).copyWith(fontSize: 8.5)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('Spin, zoom and buy from live showrooms',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption(context.textSecondary)),
                    ],
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.brandBlue,
                    visualDensity: VisualDensity.compact,
                    textStyle: AppTypography.small(AppColors.brandBlue).copyWith(fontWeight: FontWeight.w700),
                  ),
                  onPressed: () => context.push('/shops/setup'),
                  child: Text(myLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
