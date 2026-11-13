import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../backend/coins/gift_catalog.dart';
import '../../../backend/money/insights_logic.dart';
import '../../../backend/money/money_models.dart';
import '../../../backend/money/money_service.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../social_hub/money/money_widgets.dart';

/// Oneova Wallet (`/wallet`): coins to spend, Diamonds earned from gifts,
/// what is held / withdrawable / on the way, and the full history. All live
/// from `wallets/{uid}`, its ledger and `withdrawals`.
class OneovaWalletScreen extends ConsumerStatefulWidget {
  const OneovaWalletScreen({super.key});

  @override
  ConsumerState<OneovaWalletScreen> createState() => _OneovaWalletScreenState();
}

class _OneovaWalletScreenState extends ConsumerState<OneovaWalletScreen> {
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    // Releases Diamonds whose hold is over, then cheers if any were.
    ref.read(moneyServiceProvider).syncWallet().then((released) {
      if (!mounted || released <= 0) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.brandBlue,
        content: Text('${money(released * diamondUsd, 'USD')} just became withdrawable 🎉'),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(creatorWalletProvider).value ?? const CreatorWallet();
    final plan = ref.watch(planStateProvider).value ?? const PlanState();
    final open = (ref.watch(withdrawalsProvider).value ?? const <Withdrawal>[]).where((w) => w.isOpen).toList();

    return MoneyScaffold(
      title: 'Wallet',
      actions: [
        IconButton(
          tooltip: 'How it works',
          icon: Icon(Icons.help_outline_rounded, color: context.textSecondary, size: 20),
          onPressed: () => _explain(context),
        ),
      ],
      body: RefreshIndicator(
        color: AppColors.brandBlue,
        onRefresh: () => ref.read(moneyServiceProvider).syncWallet(),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const SizedBox(height: 4),
            _EarningsHero(wallet: wallet),
            const SizedBox(height: 12),
            GrowthBanner(
              title: wallet.lifetimeDiamonds == 0 ? 'Your earnings start here' : "You're growing!",
              body: earningsCheer(wallet),
              icon: wallet.canWithdraw ? Icons.celebration_rounded : Icons.trending_up_rounded,
            ),
            if (wallet.lifetimeDiamonds > 0) ...[
              const SizedBox(height: 12),
              MoneyCard(
                child: wallet.canWithdraw
                    ? MilestoneBar(
                        label: 'Next milestone: ${money(nextMilestone(wallet.lifetimeUsd.floor()).toDouble(), 'USD')} earned',
                        value: wallet.lifetimeUsd,
                        goal: nextMilestone(wallet.lifetimeUsd.floor()),
                      )
                    : MilestoneBar(
                        label: 'First withdrawal at ${money(minWithdrawUsd, 'USD')}',
                        value: wallet.availableUsd + wallet.pendingUsd,
                        goal: minWithdrawUsd,
                      ),
              ),
            ],
            for (final w in open) ...[
              const SizedBox(height: 12),
              _OpenWithdrawal(w: w),
            ],
            const SizedBox(height: 12),
            _CoinsCard(coins: wallet.coins),
            const SectionTitle('Grow & manage'),
            _Actions(plan: plan),
            SectionTitle('History', trailing: _Filter(value: _filter, onChanged: (v) => setState(() => _filter = v))),
            _History(filter: _filter),
          ],
        ),
      ),
    );
  }

  void _explain(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How your wallet works', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
              const SizedBox(height: 12),
              for (final (icon, title, body) in [
                (Icons.toll_rounded, 'Coins', 'Bought with Google Play and used to send gifts. Coins are credit and can’t be cashed out.'),
                (Icons.diamond_rounded, 'Diamonds', 'What you earn when people gift you. 100 Diamonds = ${money(100 * diamondUsd, 'USD')}.'),
                (Icons.schedule_rounded, 'Held for $holdDays days', 'New Diamonds wait $holdDays days in case a payment is reversed, then become withdrawable.'),
                (Icons.verified_user_rounded, 'Verified withdrawals', 'Verify your ID once, then withdraw any amount to mobile money or a bank, from as little as 1 in your own currency after the payout fee.'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 18, color: AppColors.brandBlue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary)),
                            Text(body, style: TextStyle(fontSize: 12, height: 1.35, color: context.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EarningsHero extends StatelessWidget {
  const _EarningsHero({required this.wallet});
  final CreatorWallet wallet;

  @override
  Widget build(BuildContext context) {
    final usd = NumberFormat.simpleCurrency(name: 'USD');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: AppColors.premiumGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [BoxShadow(color: AppColors.brandBlue.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.diamond_rounded, size: 14, color: Colors.white70),
              const SizedBox(width: 5),
              const Text('WITHDRAWABLE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: Colors.white70)),
              const Spacer(),
              Text('${compact(wallet.availableDiamonds)} Diamonds', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedNumber(
            value: wallet.availableUsd,
            format: usd.format,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _HeroStat(label: 'Held ($holdDays days)', value: usd.format(wallet.pendingUsd)),
              _HeroStat(label: 'On the way', value: usd.format(wallet.lockedUsd)),
              _HeroStat(label: 'Earned in total', value: usd.format(wallet.lifetimeUsd)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    context.push('/wallet/scan');
                  },
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 17),
                  label: const Text('Scan to pay', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    context.push('/pay');
                  },
                  icon: const Icon(Icons.account_balance_wallet_rounded, size: 17),
                  label: const Text('Oneova Pay', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                HapticFeedback.selectionClick();
                context.push('/wallet/withdraw');
              },
              icon: const Icon(Icons.north_east_rounded, size: 17),
              label: const Text('Withdraw', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.brandBlue,
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0);
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 1),
          Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
        ],
      ),
    );
  }
}

class _CoinsCard extends StatelessWidget {
  const _CoinsCard({required this.coins});
  final int coins;

  @override
  Widget build(BuildContext context) {
    return MoneyCard(
      onTap: () => context.push('/wallet/coins'),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: AppColors.brandPink.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Icon(Icons.toll_rounded, color: AppColors.brandPink, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedNumber(
                  value: coins.toDouble(),
                  format: (v) => '${NumberFormat.decimalPattern().format(v.round())} coins',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: context.textPrimary),
                ),
                Text('For gifts. Coins can’t be cashed out.', style: TextStyle(fontSize: 11.5, color: context.textSecondary)),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => context.push('/wallet/coins'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandPink,
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            child: const Text('Get coins', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.plan});
  final PlanState plan;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.insights_rounded, 'Insights', 'Your growth', '/creator/insights'),
      (Icons.workspace_premium_rounded, 'Plans', plan.active ? 'On ${plan.plan.name[0].toUpperCase()}${plan.plan.name.substring(1)}' : 'Free', '/wallet/plans'),
      (Icons.verified_user_rounded, 'Verify ID', 'For payouts', '/wallet/verify'),
      (Icons.receipt_long_rounded, 'Payouts', 'All withdrawals', '/wallet/withdrawals'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final (i, (icon, title, sub, route)) in items.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Material(
                color: context.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: () => context.push(route),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: context.border)),
                    child: Column(
                      children: [
                        Icon(icon, size: 20, color: AppColors.brandBlue),
                        const SizedBox(height: 5),
                        Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.textPrimary)),
                        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: context.textMuted)),
                      ],
                    ),
                  ),
                ),
              ),
            ).animate(delay: (60 * i).ms).fadeIn(duration: 250.ms).slideY(begin: 0.1, end: 0),
          ],
        ],
      ),
    );
  }
}

class _OpenWithdrawal extends StatelessWidget {
  const _OpenWithdrawal({required this.w});
  final Withdrawal w;

  @override
  Widget build(BuildContext context) {
    return MoneyCard(
      onTap: () => context.push('/wallet/withdrawals/${w.id}'),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.brandBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${money(w.localAmount, w.currency)} on the way', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
                Text(w.review ? 'We’re double-checking it for your safety.' : 'To ${w.methodLabel}', style: TextStyle(fontSize: 11.5, color: context.textSecondary)),
              ],
            ),
          ),
          StatusPill(w.status, review: w.review),
        ],
      ),
    );
  }
}

class _Filter extends StatelessWidget {
  const _Filter({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (k, label) in const [('all', 'All'), ('earn', 'Earned'), ('coins', 'Coins')])
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: GestureDetector(
              onTap: () => onChanged(k),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: value == k ? AppColors.brandBlue : context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: value == k ? Colors.white : context.textSecondary)),
              ),
            ),
          ),
      ],
    );
  }
}

class _History extends ConsumerWidget {
  const _History({required this.filter});
  final String filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(walletLedgerProvider);
    final items = (async.value ?? const <LedgerItem>[]).where((e) => switch (filter) {
          'earn' => e.isDiamonds,
          'coins' => !e.isDiamonds,
          _ => true,
        }).toList();
    if (async.isLoading && items.isEmpty) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: AppColors.brandBlue)));
    }
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text('Nothing here yet. Gifts you send and receive, coin top-ups and withdrawals will show up here.',
            style: TextStyle(fontSize: 12.5, color: context.textSecondary)),
      );
    }
    final date = DateFormat('d MMM · HH:mm');
    return MoneyCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (i, e) in items.indexed) ...[
            if (i > 0) Divider(height: 1, color: context.border, indent: 54),
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: _ledgerIcon(context, e),
              title: Text(
                e.giftId != null ? '${e.title} · ${e.qty > 1 ? '${e.qty}× ' : ''}${giftById(e.giftId).label}' : e.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary),
              ),
              subtitle: Text(
                [if (e.createdAt != null) date.format(e.createdAt!), if (e.status == 'pending' && !e.isWithdrawal) 'held $holdDays days'].join(' · '),
                style: TextStyle(fontSize: 11, color: context.textMuted),
              ),
              trailing: Text(
                '${e.amount > 0 ? '+' : ''}${NumberFormat.decimalPattern().format(e.amount)}${e.isDiamonds ? ' 💎' : ''}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: e.amount > 0 ? AppColors.brandBlue : context.textPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ledgerIcon(BuildContext context, LedgerItem e) {
    final (icon, color) = switch (e.type) {
      'coin_purchase' => (Icons.add_card_rounded, AppColors.brandPink),
      'withdrawal' => (Icons.north_east_rounded, AppColors.brandBlue),
      'withdrawal_returned' => (Icons.undo_rounded, AppColors.brandPink),
      _ when e.giftId != null => (giftById(e.giftId).icon, e.amount > 0 ? AppColors.brandBlue : AppColors.brandPink),
      _ => (Icons.swap_horiz_rounded, context.textSecondary),
    };
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Icon(icon, size: 16, color: color),
    );
  }
}
