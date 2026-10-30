import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/theme/app_theme.dart';
import '../controllers/looks_marketplace_controller.dart';
import '../models/looks_pack_models.dart';
import '../widgets/buy_pack_dialog.dart';

/// Screen displaying rich metadata, showcase video, and before/after comparisons for a Look Pack.
class LooksPackDetailsScreen extends ConsumerWidget {
  final OneovaLookPack pack;
  final String userId;

  const LooksPackDetailsScreen({
    super.key,
    required this.pack,
    this.userId = 'user_studio_pro',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(looksMarketplaceControllerProvider.notifier);
    final isUnlocked = notifier.isPackUnlocked(userId, pack.id);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          pack.title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Showcase Video Monitor Frame
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.border),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.play_circle_fill_rounded,
                                  size: 48,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Play Showcase Video',
                                  style: TextStyle(fontSize: 11, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.brandPink,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'SHOWCASE',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Title and Creator Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pack.title,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: context.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Created by ${pack.creatorName} • ${pack.downloadCount} Downloads',
                                style: TextStyle(fontSize: 11.5, color: context.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text(
                              pack.rating.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      pack.description,
                      style: TextStyle(fontSize: 12.5, height: 1.4, color: context.textPrimary),
                    ),
                    const SizedBox(height: 16),
                    // Included Looks List
                    Text(
                      'Included Pro Looks (${pack.looks.length})',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...pack.looks.map((look) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.surfaceMid,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: context.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.palette_rounded, size: 18, color: AppColors.brandBlue),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    look.name,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${look.categories.isNotEmpty ? look.categories.first : "Pro"} • Default Intensity: ${(look.intensity * 100).toInt()}%',
                                    style: TextStyle(fontSize: 10.5, color: context.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            if (isUnlocked)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Ready to Grade',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            // Bottom Sticky Purchase Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: context.surface,
                border: Border(top: BorderSide(color: context.border, width: 1.0)),
              ),
              child: isUnlocked
                  ? Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                      ),
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_rounded, size: 16, color: Colors.green),
                          SizedBox(width: 6),
                          Text(
                            'Pack Unlocked & Synced with Studio',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    )
                  : SizedBox(
                      height: 42,
                      child: ElevatedButton(
                        onPressed: () {
                          showDialog<void>(
                            context: context,
                            builder: (_) => BuyPackDialog(pack: pack, userId: userId),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.shopping_bag_rounded, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              pack.isFree
                                  ? 'Get Pack Free'
                                  : 'Unlock Pack (${pack.priceCoins} Coins • \$${pack.priceFiat.toStringAsFixed(2)})',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
