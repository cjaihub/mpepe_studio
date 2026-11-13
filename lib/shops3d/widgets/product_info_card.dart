import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_theme.dart';
import '../../social_hub/biz_commerce/checkout_screen.dart' show formatMoney;
import '../data/currencies.dart';
import '../models/shop_models.dart';
import 'reviews.dart' show ReviewLine;
import 'stage_style.dart';

/// Compact floating commerce card: name, price, discount, stock, options and
/// the buy actions. Prices shown here are display only — checkout re-prices
/// on the server.
class ProductInfoCard extends ConsumerWidget {
  const ProductInfoCard({
    super.key,
    required this.product,
    required this.style,
    required this.variant,
    required this.onVariant,
    required this.onBuy,
    this.onOpen,
    this.onAddToCart,
    this.deal,
    this.rating,
    this.extra = 0,
    this.isOwner = false,
    this.preview = false,
  });

  /// Adds the chosen option to the private cart.
  final VoidCallback? onAddToCart;

  /// The shop's running live deal, when it covers this product.
  final LiveDeal? deal;

  /// Shop rating (shown only when the shop has one).
  final double? rating;

  /// Customization extras chosen by the buyer (added to the shown price).
  final num extra;

  final ShopProduct product;
  final StageStyle style;
  final ProductVariant? variant;
  final ValueChanged<ProductVariant> onVariant;
  final VoidCallback onBuy;
  final VoidCallback? onOpen;
  final bool isOwner;

  /// Seller preview: actions are shown but do nothing.
  final bool preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = product;
    final onDeal = deal != null && deal!.appliesTo(p.id);
    final price = (onDeal ? deal!.priceFor(p.price, p.currency) : p.price) + extra;
    final listPrice = onDeal ? p.price + extra : (p.compareAtPrice == null ? null : p.compareAtPrice! + extra);
    final pct = onDeal ? deal!.percentOff : p.discountPercent;
    final soldOut = p.soldOut || (variant?.soldOut ?? false);
    final thumb = p.gallery.isEmpty ? '' : p.gallery.first;

    return GlassPanel(
      style: style,
      strong: true,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (thumb.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: SizedBox(width: 40, height: 40, child: StageImage(url: thumb, style: style, cacheWidth: 120)),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.title3(style.fg).copyWith(fontSize: 14.5)),
                    // The product's own rating and count when it has reviews, else the shop's.
                    ReviewLine(rating: p.rating ?? rating, count: p.rating == null ? 0 : p.reviewCount, style: style),
                  ]),
                ),
                if (onOpen != null) Icon(Icons.chevron_right_rounded, size: 18, color: style.fgMuted),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(formatMoney(price, p.currency), style: AppTypography.metric(style.fg).copyWith(fontSize: 19)),
              if (pct != null && listPrice != null) ...[
                Text(
                  formatMoney(listPrice, p.currency),
                  style: AppTypography.small(style.fgMuted).copyWith(decoration: TextDecoration.lineThrough),
                ),
                StagePill(label: '-$pct%', color: AppColors.brandPink),
              ],
              // Today's rate into the buyer's own currency (checkout stays in the seller's).
              if (approxLocal(price, p.currency, ref.watch(fxRatesProvider).value ?? FxRates.empty) case final local?)
                Text(local, style: AppTypography.caption(style.fgMuted)),
            ],
          ),
          const SizedBox(height: 4),
          _StockLine(product: p, variant: variant, style: style),
          if (p.variants.isNotEmpty) ...[
            const SizedBox(height: 10),
            _VariantPicker(product: p, selected: variant, style: style, onPick: onVariant),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: style.hairline,
                      disabledForegroundColor: style.fgMuted,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                      textStyle: AppTypography.callout(Colors.white),
                    ),
                    onPressed: (isOwner || soldOut || p.price <= 0 || preview)
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            onBuy();
                          },
                    icon: Icon(isOwner ? Icons.storefront_outlined : Icons.shopping_bag_outlined, size: 17),
                    label: Text(isOwner ? 'Your product' : (soldOut ? 'Sold out' : 'Buy now')),
                  ),
                ),
              ),
              if (onAddToCart != null && !isOwner) ...[
                const SizedBox(width: 8),
                _SquareButton(
                  style: style,
                  icon: Icons.add_shopping_cart_rounded,
                  color: style.fg,
                  tooltip: 'Add to cart',
                  onTap: (preview || soldOut || p.price <= 0)
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          onAddToCart!();
                        },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StockLine extends StatelessWidget {
  const _StockLine({required this.product, required this.variant, required this.style});
  final ShopProduct product;
  final ProductVariant? variant;
  final StageStyle style;

  @override
  Widget build(BuildContext context) {
    final stock = variant?.stock ?? product.stock;
    final (String text, Color color) = switch (stock) {
      _ when product.soldOut || (variant?.soldOut ?? false) => ('Sold out', AppColors.brandPink),
      final int n when n <= 5 => ('Only $n left', AppColors.brandPink),
      final int n => ('$n in stock', style.fgSecondary),
      null => ('In stock', style.fgSecondary),
    };
    return Row(
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(text, style: AppTypography.small(color)),
      ],
    );
  }
}

class _VariantPicker extends StatelessWidget {
  const _VariantPicker({required this.product, required this.selected, required this.style, required this.onPick});
  final ShopProduct product;
  final ProductVariant? selected;
  final StageStyle style;
  final ValueChanged<ProductVariant> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in product.variants)
          Semantics(
            button: true,
            selected: v.id == selected?.id,
            label: v.soldOut ? '${v.name}, sold out' : v.name,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onPick(v);
              },
              child: v.swatch != null ? _swatch(v) : _chip(v),
            ),
          ),
      ],
    );
  }

  Widget _swatch(ProductVariant v) {
    final on = v.id == selected?.id;
    return Tooltip(
      message: v.name,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 26,
        height: 26,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: on ? style.accent : style.hairline, width: on ? 2 : 1),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(color: v.swatch, shape: BoxShape.circle),
          child: v.soldOut ? Icon(Icons.close_rounded, size: 12, color: style.fgMuted) : null,
        ),
      ),
    );
  }

  Widget _chip(ProductVariant v) {
    final on = v.id == selected?.id;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: on ? style.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: on ? style.accent : style.hairline),
      ),
      child: Text(
        v.name,
        style: AppTypography.small(on ? Colors.white : (v.soldOut ? style.fgMuted : style.fg)).copyWith(
          decoration: v.soldOut ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({required this.style, required this.icon, required this.color, required this.tooltip, this.onTap});
  final StageStyle style;
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: style.hairline),
          ),
          child: Icon(icon, size: 19, color: color),
        ),
      ),
    );
  }
}
