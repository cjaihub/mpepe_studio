import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../backend/coins/coin_store_service.dart';
import '../../backend/coins/gift_catalog.dart';
import '../../shared/theme/app_theme.dart';

/// Small "Lv 7" pill next to a name, from `gifter_stats/{uid}`. Hidden at level 0.
class GifterLevelBadge extends ConsumerWidget {
  const GifterLevelBadge({super.key, required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coins = ref.watch(gifterCoinsProvider(uid)).value ?? 0;
    final level = gifterLevelFor(coins);
    if (level == 0) return const SizedBox.shrink();
    final top = level >= 10;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: top ? const [AppColors.brandPink, AppColors.brandBlue] : const [AppColors.brandBlue, AppColors.brandBlue]),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.card_giftcard_rounded, size: 10, color: Colors.white),
          const SizedBox(width: 3),
          Text('Lv $level', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.4)),
        ],
      ),
    );
  }
}

/// Buy coins with Google Play. Opens as a bottom sheet.
class CoinStoreSheet extends ConsumerStatefulWidget {
  const CoinStoreSheet({super.key});

  static Future<void> show(BuildContext context) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CoinStoreSheet(),
    );
  }

  @override
  ConsumerState<CoinStoreSheet> createState() => _CoinStoreSheetState();
}

class _CoinStoreSheetState extends ConsumerState<CoinStoreSheet> {
  late final Future<List<ProductDetails>> _packs = ref.read(coinStoreServiceProvider).loadPacks();
  StreamSubscription<String>? _events;
  String? _buying;

  @override
  void initState() {
    super.initState();
    _events = ref.read(coinStoreServiceProvider).events.listen((m) {
      if (!mounted) return;
      setState(() => _buying = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  Future<void> _buy(ProductDetails p) async {
    HapticFeedback.selectionClick();
    setState(() => _buying = p.id);
    try {
      await ref.read(coinStoreServiceProvider).buy(p);
    } catch (e) {
      if (mounted) {
        setState(() => _buying = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is StateError ? e.message : 'Could not start the purchase.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(coinBalanceProvider).value;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border.all(color: context.border),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2)))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Text('Get coins', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
                  const Spacer(),
                  const Icon(Icons.toll_rounded, size: 16, color: AppColors.brandPink),
                  const SizedBox(width: 4),
                  Text(balance == null ? '…' : '$balance',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: context.textPrimary)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text('Send gifts in lives and to people you love. Paid securely with Google Play.',
                  style: TextStyle(fontSize: 12, color: context.textSecondary)),
            ),
            Flexible(
              child: FutureBuilder<List<ProductDetails>>(
                future: _packs,
                builder: (context, snap) {
                  if (snap.hasError) {
                    final e = snap.error;
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(e is StateError ? e.message : 'Coin packs are not available right now.',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: context.textSecondary)),
                    );
                  }
                  if (!snap.hasData) {
                    return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: AppColors.brandBlue)));
                  }
                  final packs = snap.data!;
                  return GridView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      mainAxisExtent: 96,
                    ),
                    itemCount: packs.length,
                    itemBuilder: (context, i) {
                      final p = packs[i];
                      final busy = _buying == p.id;
                      return InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        onTap: _buying == null ? () => _buy(p) : null,
                        child: Container(
                          decoration: AppDecorations.card(context),
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.toll_rounded, color: AppColors.brandPink, size: 22),
                              const SizedBox(height: 4),
                              Text('${coinPackCoins[p.id] ?? ''}',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: context.textPrimary)),
                              const SizedBox(height: 2),
                              busy
                                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue))
                                  : Text(p.price, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Send a gift to someone from their profile or a chat.
class UserGiftSheet extends ConsumerStatefulWidget {
  const UserGiftSheet({super.key, required this.toUid, required this.toName});
  final String toUid;
  final String toName;

  static Future<void> show(BuildContext context, {required String toUid, required String toName}) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => UserGiftSheet(toUid: toUid, toName: toName),
    );
  }

  @override
  ConsumerState<UserGiftSheet> createState() => _UserGiftSheetState();
}

class _UserGiftSheetState extends ConsumerState<UserGiftSheet> {
  int _index = 0;
  int _qty = 1;
  bool _sending = false;
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final g = giftCatalog[_index];
    setState(() => _sending = true);
    try {
      await ref.read(coinStoreServiceProvider).sendGift(toUid: widget.toUid, giftId: g.id, qty: _qty, message: _message.text);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('You sent ${widget.toName} ${_qty > 1 ? '$_qty × ' : 'a '}${g.label}'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.brandBlue,
      ));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final short = e.code == 'failed-precondition';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message ?? 'Could not send the gift.'),
        action: short ? SnackBarAction(label: 'Get coins', onPressed: () => CoinStoreSheet.show(context)) : null,
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(coinBalanceProvider).value ?? 0;
    final cost = giftCatalog[_index].coins * _qty;
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border.all(color: context.border),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Send ${widget.toName} a gift',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: context.textPrimary)),
                  ),
                  TextButton.icon(
                    onPressed: () => CoinStoreSheet.show(context),
                    icon: const Icon(Icons.toll_rounded, size: 15, color: AppColors.brandPink),
                    label: Text('$balance', style: TextStyle(fontWeight: FontWeight.w800, color: context.textPrimary)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.95,
                  ),
                  itemCount: giftCatalog.length,
                  itemBuilder: (context, i) {
                    final g = giftCatalog[i];
                    final on = i == _index;
                    return InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _index = i);
                      },
                      child: AnimatedScale(
                        scale: on ? 1.0 : 0.96,
                        duration: const Duration(milliseconds: 150),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: on ? AppColors.brandBlue.withValues(alpha: 0.1) : context.surfaceMid,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: on ? AppColors.brandBlue : context.border),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ShaderMask(
                                shaderCallback: (r) => LinearGradient(colors: g.colors).createShader(r),
                                child: Icon(g.icon, color: Colors.white, size: 24),
                              ),
                              const SizedBox(height: 3),
                              Text(g.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: context.textPrimary)),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.toll_rounded, size: 9, color: AppColors.brandPink),
                                  const SizedBox(width: 2),
                                  Text('${g.coins}', style: TextStyle(fontSize: 10, color: context.textSecondary)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _message,
                maxLength: 120,
                style: TextStyle(fontSize: 13, color: context.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  hintText: 'Add a message (shown big when it lands)',
                  hintStyle: TextStyle(fontSize: 12.5, color: context.textMuted),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final q in const [1, 5, 10, 99])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text('×$q'),
                        selected: _qty == q,
                        showCheckmark: false,
                        selectedColor: AppColors.brandBlue,
                        labelStyle: TextStyle(fontSize: 12, color: _qty == q ? Colors.white : context.textPrimary),
                        onSelected: (_) => setState(() => _qty = q),
                      ),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _sending ? null : _send,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandPink,
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    ),
                    child: _sending
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('Send · $cost', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
