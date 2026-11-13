import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/theme/app_theme.dart';
import '../../social_hub/biz_commerce/checkout_screen.dart' show formatMoney;
import '../data/shop3d_repository.dart';
import '../models/shop_models.dart';

/// `/business/inventory` — every product with quick stock edits per option.
class BusinessInventoryScreen extends ConsumerStatefulWidget {
  const BusinessInventoryScreen({super.key});

  @override
  ConsumerState<BusinessInventoryScreen> createState() => _BusinessInventoryScreenState();
}

class _BusinessInventoryScreenState extends ConsumerState<BusinessInventoryScreen> {
  String _query = '';
  bool _lowOnly = false;

  @override
  Widget build(BuildContext context) {
    final shop = ref.watch(myShopProvider).value;
    final line = shop?.settings.lowStockAt ?? 5;
    final all = ref.watch(myCatalogProvider).value ?? const <ShopProduct>[];
    final shown = all.where((p) {
      if (_query.isNotEmpty && !p.name.toLowerCase().contains(_query)) return false;
      if (_lowOnly) return p.stock != null && p.stock! <= line;
      return true;
    }).toList();
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        title: Text('Products & inventory', style: AppTypography.pageTitle(context.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'Add product',
            icon: const Icon(Icons.add_rounded, color: AppColors.brandBlue),
            onPressed: () => context.push('/shops/product/new'),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Search products',
                  filled: true,
                  fillColor: context.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.full), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Low stock'),
              selected: _lowOnly,
              selectedColor: AppColors.brandPink.withValues(alpha: 0.2),
              onSelected: (v) => setState(() => _lowOnly = v),
            ),
          ]),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(all.isEmpty ? 'Add your first product to start selling.' : 'No products match.',
                      style: AppTypography.body(context.textSecondary)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _ProductStock(product: shown[i], lowLine: line),
                ),
        ),
      ]),
    );
  }
}

class _ProductStock extends ConsumerStatefulWidget {
  const _ProductStock({required this.product, required this.lowLine});
  final ShopProduct product;
  final int lowLine;

  @override
  ConsumerState<_ProductStock> createState() => _ProductStockState();
}

class _ProductStockState extends ConsumerState<_ProductStock> {
  bool _open = false;
  bool _saving = false;

  Future<void> _save({int? stock, Map<String, int?>? variants}) async {
    HapticFeedback.selectionClick();
    setState(() => _saving = true);
    try {
      await ref.read(shop3dRepositoryProvider).setStock(widget.product, stock: stock, variantStock: variants);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn’t save stock: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final low = p.stock != null && p.stock! <= widget.lowLine;
    final thumb = p.gallery.isEmpty ? '' : p.gallery.first;
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: low ? AppColors.brandPink.withValues(alpha: 0.5) : context.border),
      ),
      child: Column(children: [
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              width: 46,
              height: 46,
              color: context.surfaceMid,
              child: thumb.isEmpty ? null : Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
            ),
          ),
          title: Row(children: [
            Flexible(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.callout(context.textPrimary))),
            if (!p.active) ...[const SizedBox(width: 6), Text('Hidden', style: AppTypography.caption(context.textMuted))],
            if (p.has3d) ...[const SizedBox(width: 6), const Icon(Icons.view_in_ar_rounded, size: 15, color: AppColors.brandBlue)],
          ]),
          subtitle: Text(
            '${formatMoney(p.price, p.currency)} · ${p.stock == null ? 'Stock not tracked' : (p.stock! <= 0 ? 'Sold out' : '${p.stock} in stock')}'
            '${p.customization.isNotEmpty ? ' · ${p.customization.length} custom options' : ''}',
            style: AppTypography.caption(low ? AppColors.brandPink : context.textSecondary),
          ),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_saving) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            if (p.variants.isEmpty && !_saving)
              _Stepper(value: p.stock ?? 0, onChanged: (v) => _save(stock: v)),
            IconButton(
              tooltip: 'Edit product',
              icon: Icon(Icons.edit_outlined, color: context.textMuted, size: 20),
              onPressed: () => context.push('/shops/product/edit?id=${p.id}'),
            ),
          ]),
          onTap: p.variants.isEmpty ? null : () => setState(() => _open = !_open),
        ),
        if (_open && p.variants.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 8, 10),
            child: Column(children: [
              for (final v in p.variants)
                Row(children: [
                  if (v.swatch != null)
                    Container(width: 14, height: 14, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: v.swatch, shape: BoxShape.circle)),
                  Expanded(child: Text(v.name, style: AppTypography.small(context.textPrimary))),
                  _Stepper(value: v.stock ?? 0, onChanged: (n) => _save(variants: {v.id: n})),
                ]),
            ]),
          ),
      ]),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'One less',
          icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
          onPressed: value <= 0 ? null : () => onChanged(value - 1),
        ),
        GestureDetector(
          onTap: () async {
            final c = TextEditingController(text: '$value');
            final n = await showDialog<int>(
              context: context,
              builder: (d) => AlertDialog(
                title: const Text('Stock'),
                content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(d, int.tryParse(c.text.trim())), child: const Text('Save')),
                ],
              ),
            );
            if (n != null && n >= 0) onChanged(n);
          },
          child: SizedBox(width: 34, child: Text('$value', textAlign: TextAlign.center, style: AppTypography.callout(context.textPrimary))),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'One more',
          icon: const Icon(Icons.add_circle_outline_rounded, size: 20, color: AppColors.brandBlue),
          onPressed: () => onChanged(value + 1),
        ),
      ]);
}
