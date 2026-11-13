import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../identity/widgets/oneova_verified_badge.dart';
import '../../shared/theme/app_theme.dart';
import '../data/share_ref.dart';
import '../data/shop3d_repository.dart';
import '../models/shop_models.dart';
import '../widgets/customization_picker.dart';
import '../widgets/product_3d_viewer.dart';
import '../widgets/product_info_card.dart';
import '../widgets/reviews.dart';
import '../widgets/shop_stage_view.dart';
import '../widgets/stage_style.dart';

/// `/shops/p/:productId` — full-screen interactive product: rotate, pinch to
/// zoom, tap to focus, view in your room (AR), switch options, buy.
class ShopProductScreen extends ConsumerStatefulWidget {
  const ShopProductScreen({super.key, required this.productId, this.variantId, this.shareCode});
  final String productId;
  final String? variantId;

  /// The tracked share link this visit came from (`?ref=`).
  final String? shareCode;

  @override
  ConsumerState<ShopProductScreen> createState() => _ShopProductScreenState();
}

class _ShopProductScreenState extends ConsumerState<ShopProductScreen> {
  String? _variantId;
  bool _details = false;
  CustomSelection _custom = {};

  void _buy(ShopProduct p, ProductVariant? v) {
    final missing = missingRequired(p, _custom);
    if (missing != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Choose ${missing.label.toLowerCase()} first.')));
      return;
    }
    context.push(checkoutRoute(p, v, custom: _custom));
  }

  @override
  void initState() {
    super.initState();
    _variantId = widget.variantId;
    ShareRef.note(widget.shareCode);
  }

  void _back() => context.canPop() ? context.pop() : context.go('/shops');

  ProductVariant? _variant(ShopProduct p) {
    if (p.variants.isEmpty) return null;
    for (final v in p.variants) {
      if (v.id == _variantId) return v;
    }
    return p.variants.firstWhere((v) => !v.soldOut, orElse: () => p.variants.first);
  }

  @override
  Widget build(BuildContext context) {
    final productAsync = ref.watch(shopProductProvider(widget.productId));
    return Scaffold(
      backgroundColor: context.bg,
      body: productAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue, strokeWidth: 2)),
        error: (_, _) => _missing(),
        data: (p) {
          if (p == null || (!p.active && p.ownerId != ref.read(shop3dRepositoryProvider).uid)) return _missing();
          final shop = ref.watch(shopProvider(p.ownerId)).value;
          final stage = shop?.stage ?? const StageConfig();
          final style = StageStyle.of(context, stage);
          final v = _variant(p);
          final isOwner = ref.read(shop3dRepositoryProvider).uid == p.ownerId;
          // A customization choice can switch the model's material look.
          final look = customizationLook(p, _custom);
          final shown = look == null ? v : ProductVariant(id: 'custom', name: look, modelVariant: look);

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: style.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
            child: Stack(
              fit: StackFit.expand,
              children: [
                StageBackdropLayer(style: style),
                SafeArea(
                  child: Column(
                    children: [
                      _bar(style, p, shop),
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Product3DViewer(
                                      product: p,
                                      variant: shown,
                                      textures: customizationTextures(p, _custom),
                                      style: style,
                                      interactive: true,
                                      autoRotate: stage.autoRotate,
                                    ),
                                  ),
                                  IgnorePointer(
                                    child: Transform.translate(
                                      offset: const Offset(0, -16),
                                      child: StagePlatform(style: style, width: 260),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (p.has3d)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 4,
                                child: IgnorePointer(
                                  child: Center(
                                    child: Text(
                                      'Drag to rotate · pinch to zoom · double-tap to focus',
                                      style: AppTypography.caption(style.fgMuted),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: 480, maxHeight: MediaQuery.sizeOf(context).height * 0.56),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (p.description.isNotEmpty) _description(style, p),
                                  if (p.reviewCount > 0) ...[ProductReviews(productId: p.id, style: style, rating: p.rating), const SizedBox(height: 8)],
                                  if (p.customization.isNotEmpty) ...[
                                    CustomizationPicker(
                                      product: p,
                                      selection: _custom,
                                      style: style,
                                      onChanged: (s) => setState(() => _custom = s),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  ProductInfoCard(
                                    product: p,
                                    style: style,
                                    variant: v,
                                    isOwner: isOwner,
                                    deal: shop?.liveDeal,
                                    rating: p.rating ?? shop?.rating,
                                    extra: customizationExtra(p, _custom),
                                    onVariant: (x) => setState(() => _variantId = x.id),
                                    onBuy: () => _buy(p, v),
                                    onAddToCart: isOwner
                                        ? null
                                        : () async {
                                            final messenger = ScaffoldMessenger.of(context);
                                            try {
                                              await ref.read(shop3dRepositoryProvider).addToCart(p, v, customization: _custom);
                                              messenger.showSnackBar(SnackBar(content: Text('${p.name} added to your cart')));
                                            } on StateError catch (e) {
                                              messenger.showSnackBar(SnackBar(content: Text(e.message)));
                                            }
                                          },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _bar(StageStyle style, ShopProduct p, Shop3D? shop) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: Icon(Icons.arrow_back_rounded, color: style.fg),
            onPressed: _back,
          ),
          Expanded(
            child: GestureDetector(
              onTap: shop == null ? null : () => context.push('/shops/${shop.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.sectionTitle(style.fg)),
                  if (shop != null)
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            shop.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption(style.fgSecondary),
                          ),
                        ),
                        if (shop.verified) ...[
                          const SizedBox(width: 3),
                          OneovaVerifiedBadge(kind: VerifiedKind.business, level: shop.verifiedLevel, size: 12),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (p.has3d) const StagePill(label: '3D', color: AppColors.brandBlue, icon: Icons.view_in_ar_rounded),
          IconButton(
            tooltip: 'Share',
            icon: Icon(Icons.ios_share_rounded, size: 19, color: style.fg),
            onPressed: () async {
              HapticFeedback.lightImpact();
              final url = await ShareRef.linkFor('product', p.id, fallback: 'https://oneova.web.app/shops/${p.ownerId}');
              await SharePlus.instance.share(ShareParams(text: '${p.name} on Oneova\n$url', subject: p.name));
            },
          ),
        ],
      ),
    );
  }

  Widget _description(StageStyle style, ShopProduct p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setState(() => _details = !_details),
        child: GlassPanel(
          style: style,
          radius: AppRadius.md,
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    p.description,
                    maxLines: _details ? 12 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(style.fgSecondary),
                  ),
                ),
                Icon(_details ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: style.fgMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _missing() => SafeArea(
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary),
            onPressed: _back,
          ),
        ),
        Expanded(
          child: Center(child: Text('This product is no longer available.', style: AppTypography.body(context.textSecondary))),
        ),
      ],
    ),
  );
}

/// `/shops/saved` — products you saved from any shop.
class SavedProductsScreen extends ConsumerWidget {
  const SavedProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(savedProductIdsProvider);
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 50,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary),
          onPressed: () => context.canPop() ? context.pop() : context.go('/shops'),
        ),
        title: Text('Saved', style: AppTypography.pageTitle(context.textPrimary)),
      ),
      body: ids.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue, strokeWidth: 2)),
        error: (_, _) => Center(child: Text("Couldn't load your saved items.", style: AppTypography.body(context.textSecondary))),
        data: (list) => list.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bookmark_border_rounded, size: 34, color: context.textMuted),
                      const SizedBox(height: 8),
                      Text('Nothing saved yet', style: AppTypography.title3(context.textPrimary)),
                      const SizedBox(height: 4),
                      Text(
                        'Tap the bookmark on any product to keep it here.',
                        textAlign: TextAlign.center,
                        style: AppTypography.body(context.textSecondary),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _SavedRow(productId: list[i]),
              ),
      ),
    );
  }
}

class _SavedRow extends ConsumerWidget {
  const _SavedRow({required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(shopProductProvider(productId)).value;
    final style = StageStyle.of(context, const StageConfig());
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: p == null ? null : () => context.push(productRoute(p, null)),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: AppDecorations.card(context),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: SizedBox(
                width: 56,
                height: 56,
                child: StageImage(url: p == null || p.gallery.isEmpty ? '' : p.gallery.first, style: style, cacheWidth: 170),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p?.name ?? 'Unavailable',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.sectionTitle(context.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p == null ? 'This product was removed' : (p.soldOut ? 'Sold out' : (p.has3d ? 'View in 3D' : 'In stock')),
                    style: AppTypography.caption(p?.soldOut == true ? AppColors.brandPink : context.textSecondary),
                  ),
                ],
              ),
            ),
            if (p != null)
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.bookmark_rounded, color: AppColors.brandPink),
                onPressed: () => ref.read(shop3dRepositoryProvider).toggleSaved(p),
              ),
          ],
        ),
      ),
    );
  }
}
