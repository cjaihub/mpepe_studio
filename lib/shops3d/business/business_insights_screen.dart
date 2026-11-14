import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_theme.dart';
import '../../social_hub/biz_commerce/checkout_screen.dart' show formatMoney;
import '../data/currencies.dart' show deviceCurrency;
import '../data/shop3d_repository.dart';
import '../models/shop_models.dart';
import 'business_data.dart';

/// `/business/insights` — store analytics from real orders and the store's
/// daily counters only: sales and change, funnel, product performance,
/// buyers, buying hours, stock outlook and fulfilment health.
class BusinessInsightsScreen extends ConsumerStatefulWidget {
  const BusinessInsightsScreen({super.key});

  @override
  ConsumerState<BusinessInsightsScreen> createState() => _BusinessInsightsScreenState();
}

class _ProductRow {
  _ProductRow(this.id, this.name);
  final String id;
  String name;
  num views = 0;
  num carts = 0;
  int units = 0;
  int orders = 0;
  num revenue = 0;
  double? get conversion => views > 0 ? orders / views * 100 : null;
}

class _BusinessInsightsScreenState extends ConsumerState<BusinessInsightsScreen> {
  int _days = 30;

  DateTime _dayOf(String key) => DateTime(int.parse(key.substring(0, 4)), int.parse(key.substring(4, 6)), int.parse(key.substring(6, 8)));

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(sellerOrdersProvider).value ?? const [];
    final daily = ref.watch(myDailyStatsProvider).value ?? const [];
    final products = ref.watch(myCatalogProvider).value ?? const <ShopProduct>[];
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: _days - 1));
    final prevStart = start.subtract(Duration(days: _days));

    bool inRange(DateTime? t, DateTime a, DateTime b) => t != null && !t.isBefore(a) && t.isBefore(b);
    final end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final paid = [for (final o in orders) if (paidStatuses.contains(o['status']) && inRange(orderTime(o), start, end)) o];
    final prevPaid = [for (final o in orders) if (paidStatuses.contains(o['status']) && inRange(orderTime(o), prevStart, start)) o];
    final cancelled = orders.where((o) => {'cancelled', 'refunded', 'refunding'}.contains(o['status']) && inRange(orderTime(o), start, end)).length;

    // Main currency = the one with the most sales in the period.
    final byCurrency = <String, num>{};
    for (final o in paid) {
      final c = '${o['currency'] ?? deviceCurrency()}';
      byCurrency[c] = (byCurrency[c] ?? 0) + orderItems(o);
    }
    final currency = byCurrency.isEmpty
        ? (products.isNotEmpty ? products.first.currency : deviceCurrency())
        : (byCurrency.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    bool cur(Map<String, dynamic> o) => '${o['currency'] ?? deviceCurrency()}' == currency;
    final revenue = paid.where(cur).fold<num>(0, (a, o) => a + orderItems(o));
    final prevRevenue = prevPaid.where(cur).fold<num>(0, (a, o) => a + orderItems(o));
    final change = prevRevenue > 0 ? (revenue - prevRevenue) / prevRevenue * 100 : null;
    final aov = paid.isEmpty ? 0 : revenue / math.max(1, paid.where(cur).length);

    // Per day.
    final days = List.generate(_days, (i) => start.add(Duration(days: i)));
    final perDay = [
      for (final d in days)
        paid.where((o) {
          final t = orderTime(o);
          return cur(o) && t != null && t.year == d.year && t.month == d.month && t.day == d.day;
        }).fold<num>(0, (a, o) => a + orderItems(o)),
    ];

    // Counters in range.
    final dailyIn = [for (final d in daily) if (d['day'] is String && inRange(_dayOf(d['day'] as String), start, end)) d];
    num sum(String k) => dailyIn.fold<num>(0, (a, d) => a + ((d[k] as num?) ?? 0));
    final views = sum('views'), carts = sum('carts'), saves = sum('saves');

    // Products.
    final rows = <String, _ProductRow>{for (final p in products) p.id: _ProductRow(p.id, p.name)};
    for (final d in dailyIn) {
      final bp = d['byProduct'];
      if (bp is! Map) continue;
      for (final e in bp.entries) {
        final r = rows.putIfAbsent('${e.key}', () => _ProductRow('${e.key}', 'Removed product'));
        final m = e.value is Map ? e.value as Map : const {};
        r.views += (m['views'] as num?) ?? 0;
        r.carts += (m['carts'] as num?) ?? 0;
      }
    }
    for (final o in paid.where(cur)) {
      final id = '${o['productId']}';
      final r = rows.putIfAbsent(id, () => _ProductRow(id, '${o['productName'] ?? 'Item'}'));
      r.orders++;
      r.units += (o['quantity'] as num?)?.toInt() ?? 1;
      r.revenue += orderItems(o);
    }
    final perf = rows.values.where((r) => r.views > 0 || r.orders > 0).toList()..sort((a, b) => b.revenue.compareTo(a.revenue));

    // Buyers.
    final buyerOrders = <String, int>{};
    for (final o in paid) {
      final b = '${o['buyerId']}';
      buyerOrders[b] = (buyerOrders[b] ?? 0) + 1;
    }
    final everBefore = {for (final o in orders) if (paidStatuses.contains(o['status']) && (orderTime(o)?.isBefore(start) ?? false)) '${o['buyerId']}'};
    final returning = buyerOrders.keys.where((b) => everBefore.contains(b) || buyerOrders[b]! > 1).length;

    // Hours.
    final hours = List<num>.filled(24, 0);
    for (final o in paid) {
      final t = orderTime(o);
      if (t != null) hours[t.hour] += 1;
    }
    final peak = hours.every((h) => h == 0) ? null : hours.indexOf(hours.reduce(math.max));

    // Stock outlook.
    final outlook = <(ShopProduct, double)>[];
    for (final p in products) {
      final r = rows[p.id];
      if (p.stock == null || r == null || r.units == 0) continue;
      final perDayUnits = r.units / _days;
      outlook.add((p, p.stock! / perDayUnits));
    }
    outlook.sort((a, b) => a.$2.compareTo(b.$2));

    // Fulfilment speed: paid → shipped.
    final speeds = <double>[];
    for (final o in paid) {
      final tl = o['fulfilmentTimeline'];
      final t0 = orderTime(o);
      if (tl is! List || t0 == null) continue;
      for (final e in tl) {
        if (e is Map && e['step'] == 'shipped' && e['at'] is num) {
          speeds.add((DateTime.fromMillisecondsSinceEpoch((e['at'] as num).toInt()).difference(t0).inMinutes) / 60);
        }
      }
    }
    final dealSales = paid.where((o) => (o['dealPercent'] as num? ?? 0) > 0).length;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(backgroundColor: context.bg, elevation: 0, title: Text('Insights', style: AppTypography.pageTitle(context.textPrimary))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        Wrap(spacing: 8, children: [
          for (final d in const [7, 30, 90])
            ChoiceChip(
              label: Text('$d days'),
              selected: _days == d,
              selectedColor: AppColors.brandBlue,
              labelStyle: AppTypography.small(_days == d ? Colors.white : context.textPrimary),
              onSelected: (_) => setState(() => _days = d),
            ),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(formatMoney(revenue, currency), style: AppTypography.metric(context.textPrimary).copyWith(fontSize: 30)),
            ),
          ),
          const SizedBox(width: 10),
          if (change != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('${change >= 0 ? '▲' : '▼'} ${change.abs().toStringAsFixed(0)}%',
                  style: AppTypography.callout(change >= 0 ? const Color(0xFF2E9E5B) : AppColors.brandPink)),
            ),
        ]),
        Text('${paid.length} orders · average ${formatMoney(aov, currency)}${change == null ? '' : ' · vs previous $_days days'}',
            style: AppTypography.small(context.textSecondary)),
        const SizedBox(height: 12),
        SizedBox(height: 120, child: CustomPaint(painter: _Bars(perDay, AppColors.brandBlue, context.border), size: Size.infinite)),
        const SizedBox(height: 22),
        _Title('Sales funnel'),
        _Funnel(steps: [('Visitors', views), ('Added to cart', carts), ('Orders', paid.length)]),
        const SizedBox(height: 6),
        Text('$saves saves · ${views > 0 ? (paid.length / views * 100).toStringAsFixed(1) : '—'}% of visitors bought',
            style: AppTypography.caption(context.textSecondary)),
        const SizedBox(height: 22),
        _Title('Products'),
        if (perf.isEmpty)
          Text('Product numbers show up once people visit your stage.', style: AppTypography.body(context.textSecondary))
        else
          for (final r in perf.take(15))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: r.views >= 20 && r.orders == 0 ? AppColors.brandPink.withValues(alpha: 0.5) : context.border),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.callout(context.textPrimary))),
                    Text(formatMoney(r.revenue, currency), style: AppTypography.callout(context.textPrimary)),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    '${r.views} views · ${r.carts} carts · ${r.units} sold'
                    '${r.conversion == null ? '' : ' · ${r.conversion!.toStringAsFixed(1)}% bought'}'
                    '${r.views >= 20 && r.orders == 0 ? ' · many views, no sales: check price or photos' : ''}',
                    style: AppTypography.caption(context.textSecondary),
                  ),
                ]),
              ),
            ),
        const SizedBox(height: 14),
        _Title('Buyers'),
        Row(children: [
          _Kpi(label: 'Buyers', value: '${buyerOrders.length}'),
          _Kpi(label: 'Returning', value: buyerOrders.isEmpty ? '—' : '${(returning / buyerOrders.length * 100).round()}%'),
          _Kpi(label: 'Cancelled', value: '$cancelled'),
          _Kpi(label: 'Deal sales', value: '$dealSales'),
        ]),
        const SizedBox(height: 22),
        _Title('When people buy'),
        SizedBox(height: 64, child: CustomPaint(painter: _Bars(hours, AppColors.brandPink, context.border, highlightLast: false), size: Size.infinite)),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final h in const ['00', '06', '12', '18', '23']) Text(h, style: AppTypography.caption(context.textMuted)),
        ]),
        if (peak != null)
          Text('Busiest around ${peak.toString().padLeft(2, '0')}:00 — a good time to go live.', style: AppTypography.caption(context.textSecondary)),
        const SizedBox(height: 22),
        _Title('Stock outlook'),
        if (outlook.isEmpty)
          Text('Shows how long your stock lasts once products with tracked stock start selling.', style: AppTypography.body(context.textSecondary))
        else
          for (final (p, daysLeft) in outlook.take(8))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(Icons.inventory_2_outlined, color: daysLeft < 7 ? AppColors.brandPink : AppColors.brandBlue),
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.callout(context.textPrimary)),
              trailing: Text(daysLeft < 1 ? 'Out within a day' : '~${daysLeft.round()} days left',
                  style: AppTypography.small(daysLeft < 7 ? AppColors.brandPink : context.textSecondary)),
            ),
        const SizedBox(height: 22),
        _Title('Fulfilment'),
        Text(
          speeds.isEmpty
              ? 'Mark orders packed, ready and shipped to see how fast you send them.'
              : 'Average time from payment to shipped: ${(speeds.reduce((a, b) => a + b) / speeds.length).toStringAsFixed(1)} h',
          style: AppTypography.body(context.textSecondary),
        ),
        if (byCurrency.length > 1) ...[
          const SizedBox(height: 16),
          Text('Other currencies: ${byCurrency.entries.where((e) => e.key != currency).map((e) => formatMoney(e.value, e.key)).join(' · ')}',
              style: AppTypography.caption(context.textMuted)),
        ],
      ]),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: AppTypography.sectionTitle(context.textPrimary)));
}

class _Funnel extends StatelessWidget {
  const _Funnel({required this.steps});
  final List<(String, num)> steps;

  @override
  Widget build(BuildContext context) {
    final top = steps.first.$2 <= 0 ? 1 : steps.first.$2;
    return Column(children: [
      for (var i = 0; i < steps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(width: 104, child: Text(steps[i].$1, style: AppTypography.small(context.textSecondary))),
            Expanded(
              child: LayoutBuilder(
                builder: (_, box) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 22,
                    width: math.max(4.0, box.maxWidth * (steps[i].$2 / top).clamp(0.0, 1.0)),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: LinearGradient(colors: [AppColors.brandBlue, Color.lerp(AppColors.brandBlue, AppColors.brandPink, i / math.max(1, steps.length - 1))!]),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 70,
              child: Text(
                '${steps[i].$2}${i == 0 || steps[i - 1].$2 <= 0 ? '' : ' · ${(steps[i].$2 / steps[i - 1].$2 * 100).round()}%'}',
                textAlign: TextAlign.right,
                style: AppTypography.caption(context.textPrimary),
              ),
            ),
          ]),
        ),
    ]);
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: AppTypography.title3(context.textPrimary))),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption(context.textSecondary)),
        ]),
      );
}

class _Bars extends CustomPainter {
  _Bars(this.values, this.color, this.base, {this.highlightLast = true});
  final List<num> values;
  final Color color;
  final Color base;
  final bool highlightLast;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = values.fold<num>(0, (a, v) => math.max(a, v));
    final w = size.width / values.length;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), Paint()..color = base);
    for (var i = 0; i < values.length; i++) {
      final h = maxV <= 0 ? 0.0 : (values[i] / maxV) * (size.height - 4);
      if (h <= 0) continue;
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(i * w + w * 0.15, size.height - h, w * 0.7, h), const Radius.circular(3));
      canvas.drawRRect(r, Paint()..color = highlightLast && i == values.length - 1 ? AppColors.brandPink : color);
    }
  }

  @override
  bool shouldRepaint(_Bars old) => old.values != values;
}
