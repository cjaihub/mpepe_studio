import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';

import '../../backend/coins/coin_store_service.dart';
import '../../shared/theme/app_theme.dart';
import 'money_widgets.dart';

/// Coin checkout (`/wallet/coins`): packs from Google Play with live prices.
/// Coins are digital goods, so they are only sold through Play Billing.
class CoinShopScreen extends ConsumerStatefulWidget {
  const CoinShopScreen({super.key});

  @override
  ConsumerState<CoinShopScreen> createState() => _CoinShopScreenState();
}

class _CoinShopScreenState extends ConsumerState<CoinShopScreen> {
  late Future<List<ProductDetails>> _packs = ref.read(coinStoreServiceProvider).loadPacks();
  StreamSubscription<String>? _events;
  String? _selected;
  String? _buying;
  int? _celebrate;

  @override
  void initState() {
    super.initState();
    _events = ref.read(coinStoreServiceProvider).events.listen((m) {
      if (!mounted) return;
      setState(() => _buying = null);
      final added = RegExp(r'^\+(\d+) coins').firstMatch(m);
      if (added != null) {
        HapticFeedback.heavyImpact();
        setState(() => _celebrate = int.parse(added.group(1)!));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
      }
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  /// Bonus coins on top of the pack's base amount (coins_700 → 720 is +20).
  int _bonus(String id) {
    final base = int.tryParse(id.replaceFirst('coins_', '')) ?? 0;
    return (coinPackCoins[id] ?? base) - base;
  }

  Future<void> _buy(ProductDetails p) async {
    HapticFeedback.selectionClick();
    setState(() => _buying = p.id);
    try {
      await ref.read(coinStoreServiceProvider).buy(p);
    } catch (e) {
      if (!mounted) return;
      setState(() => _buying = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is StateError ? e.message : 'Could not start the purchase.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(coinBalanceProvider).value;
    final fmt = NumberFormat.decimalPattern();
    return Stack(
      children: [
        MoneyScaffold(
          title: 'Get coins',
          body: FutureBuilder<List<ProductDetails>>(
            future: _packs,
            builder: (context, snap) {
              return ListView(
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(gradient: AppColors.premiumGradient, borderRadius: BorderRadius.circular(AppRadius.lg)),
                    child: Row(
                      children: [
                        const Icon(Icons.toll_rounded, color: Colors.white, size: 34)
                            .animate(onPlay: (c) => c.repeat())
                            .shimmer(duration: 1800.ms, color: Colors.white70),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('YOUR COINS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: Colors.white70)),
                              AnimatedNumber(
                                value: (balance ?? 0).toDouble(),
                                format: (v) => fmt.format(v.round()),
                                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        const Text('Make someone’s\nday with a gift', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, height: 1.3, color: Colors.white)),
                      ],
                    ),
                  ),
                  const SectionTitle('Choose a pack'),
                  if (snap.hasError)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Text(snap.error is StateError ? (snap.error as StateError).message : 'Coin packs are not available right now.',
                              textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: context.textSecondary)),
                          TextButton(
                            onPressed: () => setState(() => _packs = ref.read(coinStoreServiceProvider).loadPacks()),
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    )
                  else if (!snap.hasData)
                    const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: AppColors.brandBlue)))
                  else
                    _grid(snap.data!),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_rounded, size: 14, color: context.textMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Paid securely with Google Play. Coins are for gifts on Oneova. They aren’t money and can’t be cashed out or transferred.',
                            style: TextStyle(fontSize: 11, height: 1.4, color: context.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          bottom: FutureBuilder<List<ProductDetails>>(
            future: _packs,
            builder: (context, snap) {
              final pack = snap.data?.where((p) => p.id == _selected).firstOrNull;
              if (pack == null) return const SizedBox.shrink();
              return SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  decoration: BoxDecoration(color: context.surface, border: Border(top: BorderSide(color: context.border))),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${fmt.format(coinPackCoins[pack.id] ?? 0)} coins', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: context.textPrimary)),
                            Text('Total ${pack.price}', style: TextStyle(fontSize: 11.5, color: context.textSecondary)),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 170,
                        child: PrimaryButton(
                          label: 'Pay with Google Play',
                          icon: Icons.shopping_bag_rounded,
                          busy: _buying != null,
                          onPressed: () => _buy(pack),
                        ),
                      ),
                    ],
                  ),
                ),
              ).animate().slideY(begin: 1, end: 0, duration: 250.ms, curve: Curves.easeOutCubic);
            },
          ),
        ),
        if (_celebrate != null) _Celebration(coins: _celebrate!, onDone: () => setState(() => _celebrate = null)),
      ],
    );
  }

  Widget _grid(List<ProductDetails> packs) {
    final fmt = NumberFormat.decimalPattern();
    final popular = packs.length > 2 ? packs[packs.length ~/ 2 - 1].id : null;
    final best = packs.last.id;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, mainAxisExtent: 118),
      itemCount: packs.length,
      itemBuilder: (context, i) {
        final p = packs[i];
        final on = _selected == p.id;
        final bonus = _bonus(p.id);
        final tag = p.id == best ? 'BEST VALUE' : p.id == popular ? 'POPULAR' : null;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _selected = p.id);
          },
          child: AnimatedScale(
            scale: on ? 1.0 : 0.97,
            duration: const Duration(milliseconds: 150),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: on ? AppColors.brandBlue.withValues(alpha: 0.08) : context.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: on ? AppColors.brandBlue : context.border, width: on ? 1.5 : 1),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.toll_rounded, color: AppColors.brandPink, size: 18 + (i * 2.0).clamp(0, 10)),
                        const SizedBox(height: 4),
                        Text(fmt.format(coinPackCoins[p.id] ?? 0), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: context.textPrimary)),
                        if (bonus > 0) Text('+${fmt.format(bonus)} bonus', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.brandPink)),
                        const SizedBox(height: 3),
                        Text(p.price, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
                      ],
                    ),
                  ),
                  if (tag != null)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: const BoxDecoration(
                          color: AppColors.brandPink,
                          borderRadius: BorderRadius.only(topRight: Radius.circular(AppRadius.md), bottomLeft: Radius.circular(AppRadius.sm)),
                        ),
                        child: Text(tag, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: Colors.white)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ).animate(delay: (40 * i).ms).fadeIn(duration: 220.ms).scaleXY(begin: 0.94, end: 1);
      },
    );
  }
}

class _Celebration extends StatelessWidget {
  const _Celebration({required this.coins, required this.onDone});
  final int coins;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: context.bg.withValues(alpha: 0.94),
        child: Stack(
          children: [
            const Positioned.fill(child: ConfettiBurst()),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SuccessMark(icon: Icons.toll_rounded),
                    const SizedBox(height: 18),
                    Text('+${NumberFormat.decimalPattern().format(coins)} coins', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: context.textPrimary))
                        .animate().fadeIn(delay: 200.ms),
                    const SizedBox(height: 6),
                    Text('They’re in your wallet. Go make someone smile!', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: context.textSecondary))
                        .animate().fadeIn(delay: 350.ms),
                    const SizedBox(height: 20),
                    SizedBox(width: 200, child: PrimaryButton(label: 'Awesome', onPressed: onDone)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
