import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/theme/app_theme.dart';
import '../../social_hub/biz_commerce/checkout_screen.dart' show formatMoney;
import '../data/shop3d_repository.dart';
import 'business_data.dart';

/// `/business/orders` — the seller's queue: prepare, hand over, track.
class BusinessOrdersScreen extends ConsumerStatefulWidget {
  const BusinessOrdersScreen({super.key});

  @override
  ConsumerState<BusinessOrdersScreen> createState() => _BusinessOrdersScreenState();
}

class _BusinessOrdersScreenState extends ConsumerState<BusinessOrdersScreen> {
  String _filter = 'prepare';
  final Set<String> _busy = {};

  bool _match(Map<String, dynamic> o) => switch (_filter) {
        'prepare' => toPrepareStatuses.contains(o['status']),
        'delivery' => inDeliveryStatuses.contains(o['status']),
        'done' => o['status'] == 'completed',
        'cancelled' => {'cancelled', 'refunded', 'refunding', 'payment_failed'}.contains(o['status']),
        _ => true,
      };

  Future<void> _advance(Map<String, dynamic> o) async {
    final next = nextFulfilment(o['fulfilment'] as String?);
    if (next == null) return;
    final id = o['id'] as String;
    HapticFeedback.lightImpact();
    setState(() => _busy.add(id));
    try {
      await ref.read(shop3dRepositoryProvider).setFulfilment(id, next.$1);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn’t update the order: $e')));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(sellerOrdersProvider);
    final all = async.value ?? const [];
    final shown = all.where(_match).toList();
    const filters = [('prepare', 'To prepare'), ('delivery', 'In delivery'), ('done', 'Completed'), ('cancelled', 'Cancelled'), ('all', 'All')];
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(backgroundColor: context.bg, elevation: 0, title: Text('Orders', style: AppTypography.pageTitle(context.textPrimary))),
      body: Column(children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final (id, label) in filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$label${id == 'prepare' ? ' (${all.where((o) => toPrepareStatuses.contains(o['status'])).length})' : ''}'),
                    selected: _filter == id,
                    selectedColor: AppColors.brandBlue,
                    labelStyle: AppTypography.small(_filter == id ? Colors.white : context.textPrimary),
                    onSelected: (_) => setState(() => _filter = id),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: async.isLoading && all.isEmpty
              ? const Center(child: CircularProgressIndicator(color: AppColors.brandBlue))
              : shown.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          _filter == 'prepare' ? 'Nothing to prepare. New paid orders show up here.' : 'No orders here yet.',
                          textAlign: TextAlign.center,
                          style: AppTypography.body(context.textSecondary),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _OrderCard(order: shown[i], busy: _busy.contains(shown[i]['id']), onAdvance: _advance),
                    ),
        ),
      ]),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.busy, required this.onAdvance});
  final Map<String, dynamic> order;
  final bool busy;
  final ValueChanged<Map<String, dynamic>> onAdvance;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final status = '${o['status']}';
    final next = toPrepareStatuses.contains(status) || inDeliveryStatuses.contains(status) ? nextFulfilment(o['fulfilment'] as String?) : null;
    final custom = (o['customization'] as List?) ?? const [];
    final t = orderTime(o);
    final img = o['imageUrl'] as String?;
    return Material(
      color: context.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => context.push('/biz/orders/${o['id']}'),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: context.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Container(
                  width: 52,
                  height: 52,
                  color: context.surfaceMid,
                  child: img == null || img.isEmpty ? null : Image.network(img, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${o['quantity'] ?? 1} × ${o['productName'] ?? 'Item'}',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.callout(context.textPrimary)),
                  if (o['variantName'] != null) Text('${o['variantName']}', style: AppTypography.caption(context.textSecondary)),
                  for (final c in custom)
                    if (c is Map) Text('${c['label']}: ${c['value']}', style: AppTypography.caption(context.textSecondary)),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatMoney((o['totalAmount'] as num?) ?? 0, '${o['currency'] ?? 'usd'}'),
                    style: AppTypography.callout(context.textPrimary)),
                if (t != null)
                  Text('${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                      style: AppTypography.caption(context.textMuted)),
              ]),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _Chip(text: _statusText(status), color: status == 'completed' ? AppColors.brandBlue : AppColors.brandPink),
              const SizedBox(width: 6),
              if (paidStatuses.contains(status)) _Chip(text: fulfilmentLabel(o['fulfilment'] as String?), color: context.textSecondary),
              if (o['stockShortfall'] == true) ...[const SizedBox(width: 6), const _Chip(text: 'Check stock', color: AppColors.brandPink)],
              const Spacer(),
              if (next != null)
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
                  onPressed: busy ? null : () => onAdvance(o),
                  child: busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(next.$2),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  static String _statusText(String s) => switch (s) {
        'paid' => 'Paid',
        'assigned' => 'Rider assigned',
        'in_transit' => 'On the way',
        'releasing' || 'completed' => 'Delivered',
        'awaiting_payment' => 'Awaiting payment',
        'refunded' || 'refunding' => 'Refunded',
        'cancelled' => 'Cancelled',
        _ => s.replaceAll('_', ' '),
      };
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.full)),
        child: Text(text, style: AppTypography.caption(color).copyWith(fontWeight: FontWeight.w700)),
      );
}
