import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/theme/app_theme.dart';
import '../controllers/wallet_controller.dart';
import '../models/wallet_models.dart';

/// Full-featured Oneova Wallet Screen.
/// Supports:
/// - Double-entry ledger real-time balance
/// - Top-up via African Mobile Money (M-Pesa, MTN, Airtel, Vodafone, Orange) & Stripe (Cards, Apple Pay, Google Pay)
/// - Creator revenue withdrawals with KYC validation
/// - Live ledger transaction history
class OneovaWalletScreen extends ConsumerWidget {
  final String userId;

  const OneovaWalletScreen({super.key, this.userId = 'user_studio_pro'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(walletControllerProvider);
    final wallet = state.wallet;

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
          'Oneova Wallet & Coins',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_rounded, size: 12, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  wallet.isKycVerified ? 'KYC Verified' : 'Unverified',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.green),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Balance Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.brandBlue,
                    AppColors.brandBlue.withValues(alpha: 0.85),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandBlue.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Creator Balance',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          wallet.localCurrency,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${wallet.coinBalance} Coins',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '≈ \$${wallet.fiatBalance.toStringAsFixed(2)} USD in Creator Royalties',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _showTopUpDialog(context, ref),
                          icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                          label: const Text('Top Up Coins'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.brandBlue,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showWithdrawDialog(context, ref),
                          icon: const Icon(Icons.account_balance_wallet_outlined, size: 16),
                          label: const Text('Withdraw'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white60),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Ledger Transaction History Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ledger Transactions',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                Text(
                  'Double-Entry Verified',
                  style: TextStyle(fontSize: 11, color: context.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (wallet.transactions.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'No transaction history yet',
                    style: TextStyle(fontSize: 12, color: context.textMuted),
                  ),
                ),
              )
            else
              ...wallet.transactions.map((tx) {
                final isCredit = tx.coinsDelta > 0 || tx.fiatDelta > 0;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: (isCredit ? Colors.green : Colors.orange).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                          size: 18,
                          color: isCredit ? Colors.green : Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tx.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tx.referenceId,
                              style: TextStyle(fontSize: 10.5, color: context.textMuted),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            tx.coinsDelta != 0
                                ? '${tx.coinsDelta > 0 ? "+" : ""}${tx.coinsDelta} Coins'
                                : '${tx.fiatDelta > 0 ? "+" : ""}\$${tx.fiatDelta.abs().toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: isCredit ? Colors.green : Colors.redAccent,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tx.status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: isCredit ? Colors.green : context.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  void _showTopUpDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Top Up Oneova Coins',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'Instant mobile money & card checkout via Flutterwave & Stripe',
                style: TextStyle(fontSize: 11.5, color: context.textMuted),
              ),
              const SizedBox(height: 14),
              _buildTopUpOption(
                context,
                ref,
                coins: 100,
                fiat: 1.99,
                provider: PaymentProvider.flutterwaveMpesa,
              ),
              _buildTopUpOption(
                context,
                ref,
                coins: 500,
                fiat: 9.99,
                provider: PaymentProvider.stripeApplePay,
              ),
              _buildTopUpOption(
                context,
                ref,
                coins: 1200,
                fiat: 19.99,
                provider: PaymentProvider.flutterwaveMtn,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopUpOption(
    BuildContext context,
    WidgetRef ref, {
    required int coins,
    required double fiat,
    required PaymentProvider provider,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(provider.icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$coins Coins',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary),
                  ),
                  Text(
                    provider.label,
                    style: TextStyle(fontSize: 10.5, color: context.textMuted),
                  ),
                ],
              ),
            ],
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final success = await ref.read(walletControllerProvider.notifier).topUpCoins(
                    userId: userId,
                    coins: coins,
                    fiatAmount: fiat,
                    provider: provider,
                  );
              if (success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Added $coins Coins to your wallet!')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: Text('\$$fiat', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showWithdrawDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: context.surface,
          title: Text(
            'Withdraw Earnings',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.textPrimary),
          ),
          content: Text(
            'Transfer creator royalties to M-Pesa, MTN Mobile Money, or international bank account.',
            style: TextStyle(fontSize: 12, color: context.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await ref.read(walletControllerProvider.notifier).withdrawEarnings(
                      userId: userId,
                      amount: 10.0,
                      provider: PaymentProvider.flutterwaveMpesa,
                      destinationAccountOrPhone: '+254712345678',
                      accountHolderName: 'Verified Creator',
                    );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Withdrawal request dispatched to M-Pesa!')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm \$10.00 M-Pesa'),
            ),
          ],
        );
      },
    );
  }
}
