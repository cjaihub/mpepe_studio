import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/finance/stripe_commerce_service.dart';
import '../../shared/theme/app_theme.dart';
import 'checkout_screen.dart' show formatMoney;

const _steps = ['paid', 'assigned', 'in_transit', 'completed'];

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

  StripeCommerceService get _svc => ref.read(stripeCommerceServiceProvider);
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
    Widget line(String l, num v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Text(l, style: TextStyle(fontSize: 12.5, color: context.textSecondary)),
            const Spacer(),
            Text(formatMoney(v, currency), style: TextStyle(fontSize: 12.5, color: context.textPrimary, fontWeight: FontWeight.w600)),
          ]),
        );
    final d = o['delivery'] as Map<String, dynamic>?;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppDecorations.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line('Items', o['itemsAmount'] as num? ?? 0),
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
        stream: ref.read(stripeCommerceServiceProvider).myOrders(),
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
                trailing: Text(formatMoney(o['totalAmount'] as num? ?? 0, o['currency'] as String? ?? 'usd'),
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
              );
            },
          );
        },
      ),
    );
  }
}

/// Get paid as a seller or delivery partner (Stripe Express). `/biz/payouts`
class PayoutsScreen extends ConsumerStatefulWidget {
  const PayoutsScreen({super.key});

  @override
  ConsumerState<PayoutsScreen> createState() => _PayoutsScreenState();
}

class _PayoutsScreenState extends ConsumerState<PayoutsScreen> with WidgetsBindingObserver {
  late Future<PayoutStatus> _status = _load();
  bool _busy = false;

  Future<PayoutStatus> _load() => ref.read(stripeCommerceServiceProvider).payoutStatus().catchError((_) => const PayoutStatus());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from Stripe's onboarding page: refresh.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(() => _status = _load());
  }

  Future<void> _onboard() async {
    setState(() => _busy = true);
    try {
      await ref.read(stripeCommerceServiceProvider).startPayoutOnboarding();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Could not open payout setup.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        title: Text('Payouts', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
      ),
      body: FutureBuilder<PayoutStatus>(
        future: _status,
        builder: (context, snap) {
          final s = snap.data;
          final ready = s?.payoutsEnabled == true;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: AppDecorations.card(context),
                child: Row(
                  children: [
                    Icon(ready ? Icons.check_circle_rounded : Icons.account_balance_outlined, color: AppColors.brandBlue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            !snap.hasData ? 'Checking…' : ready ? 'Payouts are on' : (s!.connected ? 'Finish setting up payouts' : 'Get paid on Oneova'),
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            ready
                                ? 'Money from your sales and deliveries goes to your bank after each confirmed order.'
                                : 'Add your bank details with Stripe to sell in your shop or deliver as a partner.',
                            style: TextStyle(fontSize: 12, color: context.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (snap.hasData)
                FilledButton(
                  onPressed: _busy ? null : _onboard,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  child: Text(ready ? 'Update bank details' : 'Set up payouts', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
            ],
          );
        },
      ),
    );
  }
}
