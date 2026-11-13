import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/finance/commerce_service.dart';
import '../../backend/pay/oneova_pay_service.dart' show currencyExponent;
import '../../shops3d/models/shop_models.dart' show LiveDeal;
import '../../shared/location/geo_services.dart';
import '../../shared/theme/app_theme.dart';

String formatMoney(num amount, String currency) {
  final c = currency.toUpperCase();
  final whole = amount == amount.roundToDouble();
  return '$c ${whole ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2)}';
}

/// Buy one product: quantity, delivery to where you are now (priced live from
/// the route), and pay with Oneova Pay. The money is held until you confirm you
/// have the goods. `/biz/checkout/:productId`
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, required this.productId, this.variantId, this.customization = const {}});
  final String productId;

  /// Buyer's customization (optionId → choiceId or text); the server re-prices it.
  final Map<String, String> customization;

  /// The option the buyer picked (colour, size…); the server re-validates it.
  final String? variantId;

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
  final _codeField = TextEditingController();

  /// Applied seller code and its previewed discount (the server re-checks both).
  String? _code;
  num _discount = 0;
  num? _discountFor;
  String? _codeError;
  bool _checkingCode = false;

  CommerceService get _svc => ref.read(commerceServiceProvider);

  /// The seller's live deal (`biz_shops/{seller}.liveDeal`); the server
  /// applies the same one when it prices the order.
  LiveDeal? _deal;
  StreamSubscription<LiveDeal?>? _dealSub;

  @override
  void initState() {
    super.initState();
    _refreshQuote();
    final db = FirebaseFirestore.instance;
    _dealSub = db.collection('products').doc(widget.productId).snapshots().asyncExpand((d) {
      final p = d.data();
      final seller = '${p?['ownerId'] ?? p?['userId'] ?? p?['uid'] ?? ''}';
      if (seller.isEmpty) return Stream<LiveDeal?>.value(null);
      return db.collection('biz_shops').doc(seller).snapshots().map((s) => LiveDeal.parse(s.data()?['liveDeal']));
    }).listen((d) {
      if (mounted) setState(() => _deal = d);
    }, onError: (_) {});
  }

  static num _roundMoney(num v, String currency) {
    final f = currencyExponent(currency) == 0 ? 1 : 100;
    return (v * f).round() / f;
  }

  static num _money(Object? v) {
    final n = v is num ? v : num.tryParse('$v');
    return n != null && n.isFinite && n > 0 ? (n > 1000000 ? 1000000 : n) : 0;
  }

  /// The buyer's customization as (label, value, extra price), like the server prices it.
  List<(String, String, num)> _customLines(Map<String, dynamic> p) {
    final out = <(String, String, num)>[];
    for (final raw in (p['customization'] as List? ?? const []).take(12)) {
      if (raw is! Map) continue;
      final id = '${raw['id'] ?? ''}';
      final label = '${raw['label'] ?? 'Option'}';
      final v = widget.customization[id];
      if (v == null || v.trim().isEmpty) continue;
      if (raw['type'] == 'text') {
        out.add((label, v.trim(), _money(raw['priceDelta'])));
        continue;
      }
      for (final c in (raw['choices'] as List? ?? const [])) {
        if (c is Map && '${c['id']}' == v) out.add((label, '${c['label'] ?? c['id']}', _money(c['priceDelta'])));
      }
    }
    return out;
  }

  Future<void> _applyCode(String sellerId, num items, String currency) async {
    final code = _codeField.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _checkingCode = true;
      _codeError = null;
    });
    try {
      final r = await FirebaseFunctions.instance.httpsCallable('bizCheckCode').call<Map<String, dynamic>>({
        'sellerId': sellerId,
        'code': code,
        'itemsAmount': items,
        'currency': currency.toUpperCase(),
      });
      if (!mounted) return;
      setState(() {
        _code = '${r.data['code'] ?? code}';
        _discount = (r.data['discount'] as num?) ?? 0;
        _discountFor = items;
      });
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() {
          _code = null;
          _discount = 0;
          _codeError = e.message ?? 'That code isn’t valid.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _codeError = 'Couldn’t check the code. Try again.');
    } finally {
      if (mounted) setState(() => _checkingCode = false);
    }
  }

  /// Deal price rounded to the currency's smallest unit, exactly as the server does.
  static num _dealPrice(num price, int percentOff, String currency) {
    final f = currencyExponent(currency) == 0 ? 1 : 100;
    return (price * (100 - percentOff) / 100 * f).round() / f;
  }

  String? _variantName(Map<String, dynamic> p) {
    final id = widget.variantId;
    if (id == null) return null;
    for (final v in (p['variants'] as List? ?? const [])) {
      if (v is Map && v['id'] == id) return (v['name'] ?? id).toString();
    }
    return null;
  }

  @override
  void dispose() {
    _dealSub?.cancel();
    _address.dispose();
    _codeField.dispose();
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
        variantId: widget.variantId,
        customization: widget.customization,
        code: _code,
      );
      if (!mounted) return;
      if (outcome == CheckoutOutcome.paid) {
        context.pushReplacement('/biz/orders/$orderId');
      }
    } on FirebaseFunctionsException catch (e) {
      _toast(e.message ?? 'Payment could not start. Please try again.');
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
          final listPrice = (p['price'] as num?) ?? 0;
          final currency = (p['currency'] as String? ?? 'usd').toLowerCase();
          final deal = (_deal?.appliesTo(widget.productId) ?? false) ? _deal : null;
          final price = deal == null ? listPrice : _dealPrice(listPrice, deal.percentOff, currency);
          final custom = _customLines(p);
          final unit = _roundMoney(price + custom.fold<num>(0, (s, l) => s + l.$3), currency);
          final sellerId = '${p['ownerId'] ?? p['userId'] ?? p['uid'] ?? ''}';
          final items = unit * _qty;
          // Quantity changed after a code was applied: preview it again.
          if (_code != null && _discountFor != items && !_checkingCode) {
            _discountFor = items;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _applyCode(sellerId, items, currency);
            });
          }
          final discount = _code == null ? 0 : _roundMoney(_discount > items ? items : _discount, currency);
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
                        if (_variantName(p) case final v?) ...[
                          const SizedBox(height: 2),
                          Text(v, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: context.textSecondary)),
                        ],
                        const SizedBox(height: 4),
                        Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text(formatMoney(price, currency),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
                          if (deal != null) ...[
                            Text(formatMoney(listPrice, currency),
                                style: TextStyle(fontSize: 12, color: context.textMuted, decoration: TextDecoration.lineThrough)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.brandPink, borderRadius: BorderRadius.circular(AppRadius.full)),
                              child: Text('${deal.percentOff}% OFF',
                                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)),
                            ),
                          ],
                        ]),
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
              _card(_code != null
                  ? Row(children: [
                      const Icon(Icons.local_offer_rounded, size: 18, color: AppColors.brandPink),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Code $_code applied',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _code = null;
                          _discount = 0;
                          _codeField.clear();
                        }),
                        child: const Text('Remove'),
                      ),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _codeField,
                            textCapitalization: TextCapitalization.characters,
                            maxLength: 20,
                            style: TextStyle(fontSize: 13, color: context.textPrimary),
                            decoration: InputDecoration(
                              isDense: true,
                              counterText: '',
                              hintText: 'Add a shop code',
                              prefixIcon: const Icon(Icons.local_offer_outlined, size: 18),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
                            ),
                            onSubmitted: (_) => _applyCode(sellerId, items, currency),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _checkingCode || sellerId.isEmpty ? null : () => _applyCode(sellerId, items, currency),
                          child: _checkingCode
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Apply', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ]),
                      if (_codeError != null) ...[
                        const SizedBox(height: 6),
                        Text(_codeError!, style: const TextStyle(fontSize: 12, color: AppColors.brandPink)),
                      ],
                    ])),
              const SizedBox(height: 12),
              _card(Column(
                children: [
                  for (final (label, value, extra) in custom)
                    _line('$label: $value', extra > 0 ? '+${formatMoney(extra * _qty, currency)}' : 'Included'),
                  _line('Items', formatMoney(items, currency)),
                  if (_code != null && discount > 0) _line('Code $_code', '−${formatMoney(discount, currency)}'),
                  if (_deliver) _line('Delivery', _quote == null ? '—' : formatMoney(delivery, currency)),
                  Divider(height: 18, color: context.border),
                  _line('Total', formatMoney(items - discount + delivery, currency), bold: true),
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
                    : Text('Pay ${formatMoney(items - discount + delivery, currency)}',
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
