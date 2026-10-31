import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:go_router/go_router.dart';

import '../../backend/finance/stripe_commerce_service.dart';
import '../../shared/location/geo_services.dart';
import '../../shared/theme/app_theme.dart';

String formatMoney(num amount, String currency) {
  final c = currency.toUpperCase();
  final whole = amount == amount.roundToDouble();
  return '$c ${whole ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2)}';
}

/// Buy one product: quantity, delivery to where you are now (priced live from
/// the route), and pay with Stripe. The money is held until you confirm you
/// have the goods. `/biz/checkout/:productId`
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, required this.productId});
  final String productId;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  int _qty = 1;
  bool _deliver = true;
  DeliveryQuote? _quote;
  String? _quoteError;
  bool _quoting = false;
  bool _paying = false;
  final _address = TextEditingController();

  StripeCommerceService get _svc => ref.read(stripeCommerceServiceProvider);

  @override
  void initState() {
    super.initState();
    _refreshQuote();
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _refreshQuote() async {
    setState(() {
      _quoting = true;
      _quoteError = null;
    });
    try {
      final geo = GeoServices.instance;
      final why = await geo.ensureReady();
      if (why != null) throw StateError(why);
      final pos = await geo.current();
      final q = await _svc.quote(productId: widget.productId, lat: pos.latitude, lng: pos.longitude);
      if (mounted) setState(() => _quote = q);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _quoteError = e.message ?? 'Could not price delivery right now.');
    } on StateError catch (e) {
      if (mounted) setState(() => _quoteError = e.message);
    } catch (_) {
      if (mounted) setState(() => _quoteError = 'Could not price delivery right now.');
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _pay() async {
    if (_paying) return;
    HapticFeedback.lightImpact();
    setState(() => _paying = true);
    try {
      final (orderId, outcome) = await _svc.checkout(
        context: context,
        productId: widget.productId,
        quantity: _qty,
        quoteId: _deliver ? _quote?.id : null,
        address: _deliver ? _address.text.trim() : null,
      );
      if (!mounted) return;
      if (outcome == CheckoutOutcome.paid) {
        context.pushReplacement('/biz/orders/$orderId');
      }
    } on FirebaseFunctionsException catch (e) {
      _toast(e.message ?? 'Payment could not start. Please try again.');
    } on StripeException catch (e) {
      _toast(e.error.localizedMessage ?? 'Payment did not go through.');
    } on StateError catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Payment could not start. Please try again.');
    } finally {
      if (mounted) setState(() => _paying = false);
    }
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
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Checkout', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('products').doc(widget.productId).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return _center('This product is not available.');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.brandBlue));
          final p = snap.data!.data();
          if (p == null) return _center('This product is no longer available.');
          final price = (p['price'] as num?) ?? 0;
          final currency = (p['currency'] as String? ?? 'usd').toLowerCase();
          final items = price * _qty;
          final delivery = _deliver ? (_quote?.fee ?? 0) : 0;
          final canPay = price > 0 && !_paying && (!_deliver || _quote != null);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              _card(Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: (p['imageUrl'] as String? ?? '').startsWith('http')
                          ? Image.network(p['imageUrl'] as String, fit: BoxFit.cover)
                          : ColoredBox(color: context.surfaceMid, child: Icon(Icons.shopping_bag_outlined, color: context.textMuted)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((p['name'] ?? p['title'] ?? 'Item').toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary)),
                        const SizedBox(height: 4),
                        Text(formatMoney(price, currency),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
                      ],
                    ),
                  ),
                  _qtyStepper(),
                ],
              )),
              const SizedBox(height: 12),
              _card(Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.two_wheeler_rounded, size: 18, color: AppColors.brandBlue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Motorbike delivery to me',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
                      ),
                      Switch(
                        value: _deliver,
                        activeThumbColor: AppColors.brandBlue,
                        onChanged: (v) => setState(() => _deliver = v),
                      ),
                    ],
                  ),
                  if (_deliver) ...[
                    const SizedBox(height: 6),
                    if (_quoting)
                      Text('Working out the route…', style: TextStyle(fontSize: 12, color: context.textSecondary))
                    else if (_quoteError != null)
                      Row(
                        children: [
                          Expanded(child: Text(_quoteError!, style: const TextStyle(fontSize: 12, color: AppColors.brandPink))),
                          TextButton(onPressed: _refreshQuote, child: const Text('Try again')),
                        ],
                      )
                    else if (_quote != null)
                      Text(
                        '${_quote!.distanceKm} km · about ${_quote!.durationMin} min · ${formatMoney(_quote!.fee, _quote!.currency)}',
                        style: TextStyle(fontSize: 12.5, color: context.textSecondary),
                      ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _address,
                      maxLength: 200,
                      style: TextStyle(fontSize: 13, color: context.textPrimary),
                      decoration: InputDecoration(
                        isDense: true,
                        counterText: '',
                        hintText: 'Directions for the rider (gate, floor, landmark)',
                        hintStyle: TextStyle(fontSize: 12.5, color: context.textMuted),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          borderSide: BorderSide(color: context.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          borderSide: BorderSide(color: context.border),
                        ),
                      ),
                    ),
                  ] else
                    Text('You’ll collect it from the shop.', style: TextStyle(fontSize: 12, color: context.textSecondary)),
                ],
              )),
              const SizedBox(height: 12),
              _card(Column(
                children: [
                  _line('Items', formatMoney(items, currency)),
                  if (_deliver) _line('Delivery', _quote == null ? '—' : formatMoney(delivery, currency)),
                  Divider(height: 18, color: context.border),
                  _line('Total', formatMoney(items + delivery, currency), bold: true),
                ],
              )),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.verified_user_outlined, size: 16, color: AppColors.brandBlue),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Your money is held safely and only paid to the shop after you confirm you have your order.',
                      style: TextStyle(fontSize: 11.5, height: 1.35, color: context.textSecondary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: canPay ? _pay : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  minimumSize: const Size.fromHeight(42),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                child: _paying
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('Pay ${formatMoney(items + delivery, currency)}',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _qtyStepper() => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: context.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.remove_rounded, size: 16, color: context.textPrimary),
              onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
            ),
            Text('$_qty', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary)),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.add_rounded, size: 16, color: context.textPrimary),
              onPressed: _qty < 20 ? () => setState(() => _qty++) : null,
            ),
          ],
        ),
      );

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(12),
        decoration: AppDecorations.card(context),
        child: child,
      );

  Widget _line(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text(label, style: TextStyle(fontSize: 13, color: bold ? context.textPrimary : context.textSecondary, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
            const Spacer(),
            Text(value, style: TextStyle(fontSize: 13, color: context.textPrimary, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ],
        ),
      );

  Widget _center(String t) => Center(child: Text(t, style: TextStyle(fontSize: 13, color: context.textSecondary)));
}
