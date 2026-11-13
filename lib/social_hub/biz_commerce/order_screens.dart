import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/finance/commerce_service.dart';
import '../../backend/money/money_models.dart';
import '../../backend/money/money_service.dart';
import '../../backend/pay/oneova_pay_service.dart';
import '../../backend/pay/oneova_pay_sheet.dart';
import '../../shared/theme/app_theme.dart';
import '../../shops3d/widgets/reviews.dart' show showReviewSheet;
import 'checkout_screen.dart' show formatMoney;

const _steps = ['paid', 'assigned', 'in_transit', 'completed'];

/// Seller's preparation steps (set from the business portal).
const _fulfilmentSteps = ['new', 'packed', 'ready', 'shipped'];
const _fulfilmentLabels = ['Received', 'Packed', 'Ready', 'Shipped'];

/// `product_reviews/{orderId}` (public): the buyer's review, once given.
Stream<int?> _reviewStars(String orderId) => FirebaseFirestore.instance
    .collection('product_reviews')
    .doc(orderId)
    .snapshots()
    .map((d) => d.exists ? ((d.data()?['stars'] ?? d.data()?['rating']) as num?)?.toInt() ?? 5 : null);

String _statusLabel(String s) => switch (s) {
      'awaiting_payment' => 'Waiting for payment',
      'payment_failed' => 'Payment didn’t go through',
      'paid' => 'Paid, held safely',
      'assigned' => 'Rider on the way to the shop',
      'in_transit' => 'On the way to you',
      'releasing' => 'Paying the shop…',
      'completed' => 'Delivered',
      'release_failed' => 'Delivered; payout pending',
      'refunding' || 'refunded' => 'Refunded',
      'refund_review' => 'Refund on its way',
      'payment_mismatch' => 'Payment being checked',
      'cancelled' => 'Cancelled',
      _ => s,
    };

/// One order, live: escrow status, the handover code (rider / seller), the
/// buyer's confirm-with-code step, rider actions and cancel/refund.
/// `/biz/orders/:id`
class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  bool _busy = false;
  final _code = TextEditingController();

  CommerceService get _svc => ref.read(commerceServiceProvider);
  String get _me => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      await action();
      _toast(done);
    } on FirebaseFunctionsException catch (e) {
      _toast(e.message ?? 'Something went wrong. Please try again.');
    } catch (_) {
      _toast('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Cancel this order?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
        content: Text('The full amount goes back to the buyer’s card.', style: TextStyle(fontSize: 12.5, color: ctx.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep order')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Cancel order', style: TextStyle(color: AppColors.brandPink))),
        ],
      ),
    );
    if (ok == true) await _run(() => _svc.cancelOrder(widget.orderId), 'Order cancelled');
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 50,
        leading: IconButton(icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary), onPressed: () => context.pop()),
        title: Text('Order', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _svc.watchOrder(widget.orderId),
        builder: (context, snap) {
          if (snap.hasError) return _center('You can’t see this order.');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.brandBlue));
          final o = snap.data!.data();
          if (o == null) return _center('Order not found.');
          final status = o['status'] as String? ?? '';
          final currency = o['currency'] as String? ?? 'usd';
          final isBuyer = o['buyerId'] == _me;
          final isSeller = o['sellerId'] == _me;
          final isRider = o['riderId'] == _me;
          final hasDelivery = o['delivery'] != null;
          final step = _steps.indexOf(status);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text(o['productName'] as String? ?? 'Order',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
              const SizedBox(height: 2),
              Text('${o['quantity']} × · ${formatMoney(o['totalAmount'] as num? ?? 0, currency)}',
                  style: TextStyle(fontSize: 12.5, color: context.textSecondary)),
              const SizedBox(height: 14),
              _statusCard(status, step, hasDelivery),
              if (o['fulfilment'] is String && ['paid', 'assigned'].contains(status)) ...[
                const SizedBox(height: 10),
                _fulfilmentCard(o['fulfilment'] as String),
              ],
              if (isBuyer && status == 'completed') ...[
                const SizedBox(height: 10),
                _rateCard(o['productName'] as String? ?? 'your order'),
              ],
              const SizedBox(height: 12),
              if (hasDelivery && (isRider || isSeller) && ['paid', 'assigned', 'in_transit'].contains(status))
                _handoverCode(),
              if (isBuyer && (hasDelivery ? ['assigned', 'in_transit'] : ['paid']).contains(status)) _confirmBox(),
              if (isRider && status == 'assigned')
                _primary('Start journey', Icons.two_wheeler_rounded, () => _run(() => _svc.startJourney(widget.orderId), 'Journey started. Ride safe!')),
              if ((isBuyer || isSeller) && ['awaiting_payment', 'paid', 'assigned', 'payment_failed'].contains(status))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton(
                    onPressed: _busy ? null : _cancel,
                    child: const Text('Cancel order', style: TextStyle(color: AppColors.brandPink, fontWeight: FontWeight.w600)),
                  ),
                ),
              const SizedBox(height: 8),
              _breakdown(o, currency),
            ],
          );
        },
      ),
    );
  }

  Widget _statusCard(String status, int step, bool hasDelivery) {
    final labels = hasDelivery ? const ['Paid', 'Rider', 'On the way', 'Delivered'] : const ['Paid', '', '', 'Collected'];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppDecorations.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(step >= 3 ? Icons.check_circle_rounded : Icons.lock_clock_outlined, size: 18, color: AppColors.brandBlue),
              const SizedBox(width: 8),
              Text(_statusLabel(status), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary)),
            ],
          ),
          if (step >= 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < 4; i++)
                  if (hasDelivery || i == 0 || i == 3)
                    Expanded(
                      child: Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: i <= step ? AppColors.brandBlue : context.border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(labels[i], style: TextStyle(fontSize: 10.5, color: i <= step ? context.textPrimary : context.textMuted)),
                        ],
                      ),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _fulfilmentCard(String current) {
    final at = _fulfilmentSteps.indexOf(current).clamp(0, 3);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppDecorations.card(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('The shop is preparing your order', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary)),
        const SizedBox(height: 10),
        Row(children: [
          for (var i = 0; i < 4; i++)
            Expanded(
              child: Column(children: [
                Icon(i <= at ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    size: 18, color: i <= at ? AppColors.brandPink : context.textMuted),
                const SizedBox(height: 4),
                Text(_fulfilmentLabels[i],
                    style: TextStyle(fontSize: 10.5, fontWeight: i == at ? FontWeight.w800 : FontWeight.w500,
                        color: i <= at ? context.textPrimary : context.textMuted)),
              ]),
            ),
        ]),
      ]),
    );
  }

  Widget _rateCard(String productName) => StreamBuilder<int?>(
        stream: _reviewStars(widget.orderId),
        builder: (context, snap) {
          if (!snap.hasData && snap.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
          final stars = snap.data;
          if (stars != null) {
            return Row(children: [
              const Icon(Icons.star_rounded, color: AppColors.brandPink, size: 18),
              const SizedBox(width: 6),
              Text('You rated this $stars/5. Thanks!', style: TextStyle(fontSize: 12.5, color: context.textSecondary)),
            ]);
          }
          return _primary('Rate your order', Icons.star_rounded,
              () => showReviewSheet(context, ref, orderId: widget.orderId, productName: productName));
        },
      );

  Widget _handoverCode() => StreamBuilder<String?>(
        stream: _svc.watchHandoverCode(widget.orderId),
        builder: (context, snap) {
          final code = snap.data;
          if (code == null) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Text('Handover code', style: TextStyle(fontSize: 12, color: context.textSecondary)),
                const SizedBox(height: 4),
                Text(code, style: const TextStyle(fontSize: 30, letterSpacing: 8, fontWeight: FontWeight.w900, color: AppColors.brandBlue)),
                const SizedBox(height: 4),
                Text('Show this to the buyer when you hand over the order.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: context.textSecondary)),
              ],
            ),
          );
        },
      );

  Widget _confirmBox() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: AppDecorations.card(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Got your order?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary)),
            const SizedBox(height: 4),
            Text('Enter the 4-digit code the rider shows you. Only then is the shop paid.',
                style: TextStyle(fontSize: 12, color: context.textSecondary)),
            const SizedBox(height: 10),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(fontSize: 22, letterSpacing: 10, fontWeight: FontWeight.w800, color: context.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
              ),
            ),
            const SizedBox(height: 10),
            _primary('Confirm I have it', Icons.verified_rounded, () {
              final c = _code.text.trim();
              if (c.length != 4) return _toast('Enter the 4-digit code.');
              _run(() => _svc.confirmDelivery(widget.orderId, c), 'Thanks! The shop has been paid.');
            }),
          ],
        ),
      );

  Widget _primary(String label, IconData icon, VoidCallback onTap) => FilledButton.icon(
        onPressed: _busy ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brandBlue,
          minimumSize: const Size.fromHeight(42),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
      );

  Widget _breakdown(Map<String, dynamic> o, String currency) {
    Widget text(String l, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(l, style: TextStyle(fontSize: 12.5, color: context.textSecondary))),
            const SizedBox(width: 8),
            Text(v, style: TextStyle(fontSize: 12.5, color: context.textPrimary, fontWeight: FontWeight.w600)),
          ]),
        );
    Widget line(String l, num v) => text(l, formatMoney(v, currency));
    final d = o['delivery'] as Map<String, dynamic>?;
    final qty = (o['quantity'] as num?) ?? 1;
    final discount = (o['discountAmount'] as num?) ?? 0;
    final items = (o['itemsAmount'] as num? ?? 0) + discount;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppDecorations.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in (o['customization'] as List? ?? const []))
            if (c is Map)
              text('${c['label']}: ${c['value']}',
                  ((c['priceDelta'] as num?) ?? 0) > 0 ? '+${formatMoney((c['priceDelta'] as num) * qty, currency)}' : 'Included'),
          if (o['dealPercent'] is num) text('Live deal', '${o['dealPercent']}% off'),
          line('Items', items),
          if (discount > 0) text('Code ${o['discountCode'] ?? ''}', '−${formatMoney(discount, currency)}'),
          if (d != null) line('Delivery (${d['distanceKm']} km)', o['deliveryFee'] as num? ?? 0),
          Divider(height: 16, color: context.border),
          line('Total', o['totalAmount'] as num? ?? 0),
          if (d != null && (d['address'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Note for rider: ${d['address']}', style: TextStyle(fontSize: 11.5, color: context.textMuted)),
          ],
        ],
      ),
    );
  }

  Widget _center(String t) => Center(child: Text(t, style: TextStyle(fontSize: 13, color: context.textSecondary)));
}

/// All your orders as buyer, seller or rider. `/biz/orders`
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 50,
        leading: IconButton(icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary), onPressed: () => context.pop()),
        title: Text('Orders', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'Payouts',
            icon: Icon(Icons.account_balance_wallet_outlined, color: context.textPrimary),
            onPressed: () => context.push('/biz/payouts'),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ref.read(commerceServiceProvider).myOrders(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Could not load orders.', style: TextStyle(color: context.textSecondary)));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.brandBlue));
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Center(child: Text('No orders yet', style: TextStyle(fontSize: 13, color: context.textSecondary)));
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: docs.length,
            separatorBuilder: (_, _) => Divider(height: 1, indent: 72, color: context.border),
            itemBuilder: (context, i) {
              final o = docs[i].data();
              final role = o['buyerId'] == me ? 'Bought' : (o['sellerId'] == me ? 'Sold' : 'Delivering');
              return ListTile(
                onTap: () => context.push('/biz/orders/${docs[i].id}'),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: (o['imageUrl'] as String? ?? '').startsWith('http')
                        ? Image.network(o['imageUrl'] as String, fit: BoxFit.cover)
                        : ColoredBox(color: context.surfaceMid, child: Icon(Icons.shopping_bag_outlined, color: context.textMuted, size: 20)),
                  ),
                ),
                title: Text(o['productName'] as String? ?? 'Order',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.textPrimary)),
                subtitle: Text('$role · ${_statusLabel(o['status'] as String? ?? '')}',
                    style: TextStyle(fontSize: 11.5, color: context.textSecondary)),
                trailing: role == 'Bought' && o['status'] == 'completed'
                    ? StreamBuilder<int?>(
                        stream: _reviewStars(docs[i].id),
                        builder: (context, r) => r.hasData || r.connectionState == ConnectionState.waiting
                            ? Text(formatMoney(o['totalAmount'] as num? ?? 0, o['currency'] as String? ?? 'usd'),
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.textPrimary))
                            : TextButton.icon(
                                onPressed: () => showReviewSheet(context, ref,
                                    orderId: docs[i].id, productName: o['productName'] as String? ?? 'your order'),
                                icon: const Icon(Icons.star_rounded, size: 16, color: AppColors.brandPink),
                                label: const Text('Rate', style: TextStyle(fontWeight: FontWeight.w800)),
                              ),
                      )
                    : Text(formatMoney(o['totalAmount'] as num? ?? 0, o['currency'] as String? ?? 'usd'),
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
              );
            },
          );
        },
      ),
    );
  }
}

/// Get paid as a seller or delivery partner: your Oneova balance from
/// confirmed orders, your identity check and payout methods, and withdraw.
/// `/biz/payouts`
class PayoutsScreen extends ConsumerStatefulWidget {
  const PayoutsScreen({super.key});

  @override
  ConsumerState<PayoutsScreen> createState() => _PayoutsScreenState();
}

class _PayoutsScreenState extends ConsumerState<PayoutsScreen> {
  late Future<PayoutStatus> _status = _load();
  bool _busy = false;

  Future<PayoutStatus> _load() => ref.read(commerceServiceProvider).payoutStatus().catchError((_) => const PayoutStatus());

  void _toast(String t) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t), behavior: SnackBarBehavior.floating));

  Future<void> _withdraw(String currency, int availableMinor, {String balance = 'personal'}) async {
    final methods = (ref.read(payoutMethodsProvider).value ?? const <PayoutMethod>[]).where((m) => m.currency.toUpperCase() == currency).toList();
    if (methods.isEmpty) {
      _toast('Add a $currency payout method first.');
      context.push('/wallet/withdraw');
      return;
    }
    final amount = TextEditingController(text: (availableMinor / _pow(currency)).toStringAsFixed(currencyExponent(currency)));
    PayoutMethod method = methods.first;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.viewInsetsOf(c).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Withdraw $currency${balance == 'business' ? ' · Business' : ''}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.textPrimary)),
            const SizedBox(height: 4),
            Text('Available ${formatMinor(availableMinor, currency)}', style: TextStyle(fontSize: 13, color: c.textSecondary)),
            const SizedBox(height: 14),
            for (final m in methods)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(m.rail == 'bank' ? Icons.account_balance_rounded : Icons.phone_android_rounded, color: AppColors.brandBlue),
                title: Text('${m.label} ••${m.last4}', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700)),
                subtitle: Text(m.holderName, style: TextStyle(color: c.textSecondary)),
                trailing: Icon(method.id == m.id ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: AppColors.brandBlue),
                onTap: () => set(() => method = m),
              ),
            const SizedBox(height: 6),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => set(() {}),
              decoration: InputDecoration(labelText: 'Amount ($currency)', border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            Builder(builder: (_) {
              final minor = ((double.tryParse(amount.text.replaceAll(',', '')) ?? 0) * _pow(currency)).round();
              final pct = method.rail == 'bank' ? 1 : 1.5;
              final fee = (minor * pct / 100).ceil();
              final over = minor > availableMinor;
              Widget row(String l, String v, {bool strong = false}) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Expanded(child: Text(l, style: TextStyle(fontSize: 13, color: c.textSecondary))),
                      Text(v,
                          style: TextStyle(
                              fontSize: strong ? 15 : 13,
                              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                              color: c.textPrimary)),
                    ]),
                  );
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.surfaceMid, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: Column(children: [
                  row('Payout fee (${method.rail == 'bank' ? '1' : '1.5'}%)', formatMinor(fee, currency)),
                  row('You receive', formatMinor(minor > fee ? minor - fee : 0, currency), strong: true),
                  if (over) ...[
                    const SizedBox(height: 6),
                    const Text('That’s more than your available balance.',
                        style: TextStyle(fontSize: 12, color: AppColors.brandPink)),
                  ],
                ]),
              );
            }),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, minimumSize: const Size.fromHeight(46)),
              child: const Text('Withdraw', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final minor = ((double.tryParse(amount.text.replaceAll(',', '')) ?? 0) * _pow(currency)).round();
    if (minor <= 0 || minor > availableMinor) {
      _toast('Enter an amount up to your available balance.');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await ref.read(oneovaPayServiceProvider).withdraw(
            methodId: method.id,
            amountMinor: minor,
            currency: currency,
            idempotencyKey: '${DateTime.now().microsecondsSinceEpoch}${method.id}'.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), ''),
            balance: balance,
          );
      _toast(r['review'] == true ? 'Withdrawal is being checked. We’ll send it shortly.' : 'Withdrawal on its way — you’ll get a notification when it lands.');
      setState(() => _status = _load());
    } catch (e) {
      _toast(payErrorText(e, fallback: 'The withdrawal didn’t go through. Your money is still in your balance.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static int _pow(String currency) => currencyExponent(currency) == 0 ? 1 : 100;

  @override
  Widget build(BuildContext context) {
    final methods = ref.watch(payoutMethodsProvider).value ?? const <PayoutMethod>[];
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 50,
        leading: IconButton(icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary), onPressed: () => context.pop()),
        title: Text('Payouts', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
      ),
      body: RefreshIndicator(
        color: AppColors.brandBlue,
        onRefresh: () async {
          setState(() => _status = _load());
          await _status;
        },
        child: FutureBuilder<PayoutStatus>(
          future: _status,
          builder: (context, snap) {
            final s = snap.data;
            final ready = s?.payoutsEnabled == true;
            final kyc = s?.kycStatus ?? 'none';
            final kycText = switch (kyc) {
              'verified' => 'Identity verified',
              'review' => 'Identity check in review',
              'rejected' => 'Identity check needs another try',
              'collecting' => 'Finish your identity check',
              _ => 'Verify your identity',
            };
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppDecorations.card(context),
                  child: Row(children: [
                    Icon(ready ? Icons.check_circle_rounded : Icons.account_balance_wallet_outlined, color: AppColors.brandBlue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (!snap.hasData)
                          const _Skeleton(width: 140, height: 16)
                        else
                          Text(ready ? 'Payouts are on' : 'Get paid on Oneova',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary)),
                        const SizedBox(height: 2),
                        Text(
                          ready
                              ? 'Money from confirmed orders and deliveries lands in your Oneova balance. Withdraw it any time.'
                              : 'Verify your identity and add mobile money or a bank account to sell or deliver.',
                          style: TextStyle(fontSize: 12, color: context.textSecondary),
                        ),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                if (!snap.hasData) const _Skeleton(height: 92, radius: AppRadius.lg),
                // Business (shop sales, scan to pay) first, then personal.
                if (s != null)
                  for (final (kind, e) in [
                    for (final e in s.businessBalances.entries) ('business', e),
                    for (final e in s.balances.entries) ('personal', e),
                  ])
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [AppColors.brandBlue, AppColors.brandPink]),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(kind == 'business' ? 'Business · available' : 'Personal · available',
                                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(formatMinor(e.value.available, e.key),
                                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                            ),
                            if (e.value.locked > 0)
                              Text('${formatMinor(e.value.locked, e.key)} on its way', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ]),
                        ),
                        FilledButton(
                          onPressed: _busy || e.value.available <= 0 || !ready ? null : () => _withdraw(e.key, e.value.available, balance: kind),
                          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.brandBlue),
                          child: const Text('Withdraw', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ]),
                    ),
                const _RecentWithdrawals(),
                _TopUpTile(onDone: () => setState(() => _status = _load())),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.receipt_long_rounded, color: AppColors.brandBlue),
                  title: Text('Payment history', style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimary)),
                  subtitle: Text('Orders, top-ups and refunds', style: TextStyle(color: context.textSecondary, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/wallet/payments'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(kyc == 'verified' ? Icons.verified_user_rounded : Icons.badge_outlined, color: AppColors.brandBlue),
                  title: Text(kycText, style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimary)),
                  subtitle: Text('Your ID and a selfie, checked by our team.', style: TextStyle(color: context.textSecondary, fontSize: 12)),
                  trailing: kyc == 'verified' ? null : const Icon(Icons.chevron_right_rounded),
                  onTap: kyc == 'verified' ? null : () => context.push('/wallet/verify').then((_) => setState(() => _status = _load())),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_balance_rounded, color: AppColors.brandBlue),
                  title: Text(methods.isEmpty ? 'Add a payout method' : 'Payout methods (${methods.length})',
                      style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimary)),
                  subtitle: Text(
                    methods.isEmpty ? 'Mobile money or a bank account in your name.' : methods.map((m) => '${m.label} ••${m.last4}').join(' · '),
                    style: TextStyle(color: context.textSecondary, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/wallet/withdraw').then((_) => setState(() => _status = _load())),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// "Add money" to the Oneova balance (shown only when the balance is switched on).
class _TopUpTile extends ConsumerStatefulWidget {
  const _TopUpTile({required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<_TopUpTile> createState() => _TopUpTileState();
}

class _TopUpTileState extends ConsumerState<_TopUpTile> {
  late final Future<PayOptions?> _opts = ref.read(oneovaPayServiceProvider).options().then<PayOptions?>((o) => o, onError: (_) => null);

  Future<void> _topUp(PayOptions o) async {
    final amount = TextEditingController();
    final value = await showModalBottomSheet<num>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.viewInsetsOf(c).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Add money', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.textPrimary)),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Amount (${o.currency})', border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => Navigator.pop(c, num.tryParse(amount.text.replaceAll(',', ''))),
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, minimumSize: const Size.fromHeight(46)),
            child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
    if (value == null || value <= 0 || !mounted) return;
    final f = currencyExponent(o.currency) == 0 ? 1 : 100;
    final paid = await showOneovaPaySheet(
      context,
      purpose: 'topup',
      topupAmount: value,
      amountMinor: (value * f).round(),
      currency: o.currency,
      title: 'Add to your balance',
    );
    if (paid?.succeeded == true) widget.onDone();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PayOptions?>(
        future: _opts,
        builder: (context, snap) {
          final o = snap.data;
          if (o == null || !o.walletEnabled) return const SizedBox.shrink();
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.add_card_rounded, color: AppColors.brandPink),
            title: Text('Add money', style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimary)),
            subtitle: Text(
              o.balanceMinor == null ? 'Top up with mobile money or card' : 'Balance ${formatMinor(o.balanceMinor!, o.currency)}',
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _topUp(o),
          );
        },
      );
}

/// Soft pulsing placeholder while something loads.
class _Skeleton extends StatefulWidget {
  const _Skeleton({this.width, required this.height, this.radius = 8});
  final double? width;
  final double height;
  final double radius;

  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1).animate(_c),
        child: Container(
          width: widget.width ?? double.infinity,
          height: widget.height,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: context.surfaceMid, borderRadius: BorderRadius.circular(widget.radius)),
        ),
      );
}

/// The latest balance withdrawals with a clear status timeline:
/// Requested → With the partner → Sent (or Returned to balance).
class _RecentWithdrawals extends StatelessWidget {
  const _RecentWithdrawals();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '-';
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('pay_payouts')
          .where('uid', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 6),
          Text('Recent withdrawals', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: context.textPrimary)),
          const SizedBox(height: 8),
          for (final d in docs) _WithdrawalCard(data: d.data()),
          const SizedBox(height: 4),
        ]);
      },
    );
  }
}

class _WithdrawalCard extends StatelessWidget {
  const _WithdrawalCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final status = '${data['status'] ?? 'pending'}';
    final failed = status == 'failed';
    final step = switch (status) { 'paid' => 2, 'processing' => 1, _ => 0 };
    final labels = ['Requested', 'With the partner', failed ? 'Returned' : 'Sent'];
    final currency = '${data['currency'] ?? ''}';
    final net = (data['netMinor'] as num?)?.toInt() ?? 0;
    final String? note = failed
        ? '${data['failureReason'] ?? 'It didn’t go through.'} The money is back in your balance.'
        : data['review'] == true
            ? 'We’re double-checking this one. It goes out right after.'
            : status == 'processing'
                ? 'The partner is sending it. This can take a few minutes, sometimes longer for banks.'
                : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: AppDecorations.card(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('${data['methodLabel'] ?? 'Payout'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary)),
          ),
          Text(formatMinor(net, currency), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: context.textPrimary)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  height: 4,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: failed && i == 2
                        ? AppColors.brandPink
                        : (i <= step || (failed && i < 2))
                            ? AppColors.brandBlue
                            : context.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Text(labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: i <= step || failed ? context.textPrimary : context.textMuted)),
              ]),
            ),
        ]),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(note, style: TextStyle(fontSize: 11.5, height: 1.35, color: context.textSecondary)),
        ],
      ]),
    );
  }
}
