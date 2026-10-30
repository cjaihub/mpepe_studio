import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/theme/app_theme.dart';
import '../controllers/looks_marketplace_controller.dart';
import '../controllers/wallet_controller.dart';
import '../models/looks_pack_models.dart';

/// Interactive modal dialog for purchasing and unlocking a `.oneovapack` bundle.
class BuyPackDialog extends ConsumerWidget {
  final OneovaLookPack pack;
  final String userId;

  const BuyPackDialog({
    super.key,
    required this.pack,
    this.userId = 'user_studio_pro',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletControllerProvider).wallet;
    final state = ref.watch(looksMarketplaceControllerProvider);
    final notifier = ref.read(looksMarketplaceControllerProvider.notifier);
    final hasEnoughCoins = wallet.coinBalance >= pack.priceCoins;

    return Dialog(
      backgroundColor: context.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.shopping_bag_rounded, size: 18, color: AppColors.brandPink),
                    const SizedBox(width: 8),
                    Text(
                      'Unlock Look Pack',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: AppColors.brandBlue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pack.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'By ${pack.creatorName} • ${pack.looks.length} Pro Looks',
                          style: TextStyle(fontSize: 11, color: context.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Your Balance:',
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
                Text(
                  '${wallet.coinBalance} Coins',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: hasEnoughCoins ? Colors.green : Colors.redAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Pack Price:',
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
                Text(
                  '${pack.priceCoins} Coins (\$${pack.priceFiat.toStringAsFixed(2)})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandPink,
                  ),
                ),
              ],
            ),
            if (state.errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                state.errorMessage!,
                style: const TextStyle(fontSize: 11, color: Colors.redAccent),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 42,
              child: ElevatedButton(
                onPressed: state.isPurchasing
                    ? null
                    : () async {
                        final success = await notifier.purchasePack(
                          userId: userId,
                          packId: pack.id,
                        );
                        if (success && context.mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Unlocked "${pack.title}"!')),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: state.isPurchasing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        'Unlock Pack for ${pack.priceCoins} Coins',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
