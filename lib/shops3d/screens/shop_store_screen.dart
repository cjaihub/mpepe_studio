import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../identity/widgets/oneova_verified_badge.dart';
import '../../shared/theme/app_theme.dart';
import '../../social_hub/biz_commerce/checkout_screen.dart' show formatMoney;
import '../data/share_ref.dart';
import '../data/shop3d_repository.dart';
import '../models/shop_models.dart';
import '../widgets/shop_stage_view.dart';

/// `/shops/:id` — the storefront: profile, live status, categories and the
/// full catalog (works while the seller is offline).
class ShopStoreScreen extends ConsumerStatefulWidget {
  const ShopStoreScreen({super.key, required this.shopId});
  final String shopId;

  @override
  ConsumerState<ShopStoreScreen> createState() => _ShopStoreScreenState();
}

class _ShopStoreScreenState extends ConsumerState<ShopStoreScreen> {
  String? _category;

  void _back() => context.canPop() ? context.pop() : context.go('/shops');

  @override
  Widget build(BuildContext context) {
    final shopAsync = ref.watch(shopProvider(widget.shopId));
    final me = ref.watch(shop3dRepositoryProvider).uid;

    return Scaffold(
      backgroundColor: context.bg,
      body: shopAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue, strokeWidth: 2)),
        error: (_, _) => _gone(),
        data: (shop) {
          if (shop == null) return _gone();
          final isOwner = me == shop.ownerId;
          if (shop.status != ShopStatus.open && !isOwner) return _gone();
          final live = ref.watch(liveShopsProvider)[shop.ownerId];
          final products = ref.watch(shopProductsProvider(shop.ownerId));
          return CustomScrollView(
            slivers: [
              _header(shop, isOwner),
              SliverToBoxAdapter(child: _profile(shop, live, isOwner)),
              ...products.when(
                loading: () => [
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator(color: AppColors.brandBlue, strokeWidth: 2)),
                  ),
                ],
                error: (_, _) => [
                  SliverToBoxAdapter(child: _note(Icons.wifi_off_rounded, "Couldn't load products. Pull to retry later.")),
                ],
                data: (list) => _catalog(list, isOwner),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }

  Widget _gone() => SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary), onPressed: _back),
            ),
            Expanded(child: _note(Icons.storefront_outlined, 'This shop is unavailable right now.')),
          ],
        ),
      );

  Widget _header(Shop3D shop, bool isOwner) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 150,
      backgroundColor: context.bg,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary), onPressed: _back),
      title: Text(shop.name, style: AppTypography.pageTitle(context.textPrimary)),
      actions: [
        IconButton(
          tooltip: 'Share',
          icon: Icon(Icons.ios_share_rounded, color: context.textPrimary, size: 21),
          onPressed: () async {
            final url = await ShareRef.linkFor('shop', shop.id, fallback: shopShareUrl(shop.id));
            await SharePlus.instance.share(ShareParams(text: '${shop.name} on Oneova 3D Shops\n$url'));
          },
        ),
        if (isOwner)
          IconButton(
            tooltip: 'My business',
            icon: Icon(Icons.business_center_outlined, color: context.textPrimary, size: 21),
            onPressed: () => context.push('/business'),
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: shop.bannerUrl.startsWith('http')
            ? Image.network(shop.bannerUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox())
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.2),
                    radius: 1.1,
                    colors: [
                      (shop.stage.accent == StageAccent.pink ? AppColors.brandPink : AppColors.brandBlue).withValues(alpha: 0.28),
                      context.bg,
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _profile(Shop3D shop, ShopLive? live, bool isOwner) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.brandBlue,
                backgroundImage: shop.avatarUrl.startsWith('http') ? NetworkImage(shop.avatarUrl) : null,
                child: shop.avatarUrl.startsWith('http')
                    ? null
                    : Text(shop.name.isEmpty ? '?' : shop.name.characters.first.toUpperCase(),
                        style: AppTypography.title2(Colors.white)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(shop.name, style: AppTypography.title2(context.textPrimary), overflow: TextOverflow.ellipsis)),
                        if (shop.verified) ...[
                          const SizedBox(width: 5),
                          OneovaVerifiedBadge(kind: VerifiedKind.business, level: shop.verifiedLevel, size: 17),
                        ],
                      ],
                    ),
                    if (shop.tagline.isNotEmpty)
                      Text(shop.tagline, style: AppTypography.sub(context.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (shop.followersCount > 0) '${shop.followersCount} followers',
                        if (shop.rating != null) '★ ${shop.rating!.toStringAsFixed(1)}',
                        if (isOwner && shop.status != ShopStatus.open) 'Not open yet — only you can see this',
                      ].join(' · '),
                      style: AppTypography.caption(context.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (shop.bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(shop.bio, style: AppTypography.body(context.textSecondary)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Btn(
                  icon: Icons.view_in_ar_rounded,
                  label: 'Enter 3D stage',
                  filled: true,
                  onTap: () => context.push('/shops/${shop.id}/stage'),
                ),
              ),
              if (live != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _Btn(
                    icon: Icons.videocam_rounded,
                    label: 'Watch live',
                    color: AppColors.brandPink,
                    filled: true,
                    onTap: () => context.push('/live/viewer/${live.streamId}'),
                  ),
                ),
              ],
            ],
          ),
          if (shop.categories.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _chip('All', _category == null, () => setState(() => _category = null)),
                  for (final c in shop.categories) _chip(c, _category == c, () => setState(() => _category = c)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: on,
          onSelected: (_) {
            HapticFeedback.selectionClick();
            onTap();
          },
          showCheckmark: false,
          labelStyle: AppTypography.small(on ? Colors.white : context.textPrimary),
          selectedColor: AppColors.brandBlue,
          backgroundColor: context.surface,
          side: BorderSide(color: on ? AppColors.brandBlue : context.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          visualDensity: VisualDensity.compact,
        ),
      );

  List<Widget> _catalog(List<ShopProduct> all, bool isOwner) {
    final list = _category == null
        ? all
        : all.where((p) => p.category.toLowerCase() == _category!.toLowerCase()).toList();
    if (list.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _note(Icons.inventory_2_outlined,
              isOwner ? 'Add products in your shop setup to fill this page.' : 'No products here yet.'),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _ProductTile(product: list[i]),
            childCount: list.length,
          ),
        ),
      ),
    ];
  }

  Widget _note(IconData icon, String text) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(icon, size: 32, color: context.textMuted),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center, style: AppTypography.body(context.textSecondary)),
          ],
        ),
      );
}

class _ProductTile extends StatefulWidget {
  const _ProductTile({required this.product});
  final ShopProduct product;

  @override
  State<_ProductTile> createState() => _ProductTileState();
}

class _ProductTileState extends State<_ProductTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final pct = p.discountPercent;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.lightImpact();
        context.push(productRoute(p, null));
      },
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 150),
        child: Container(
          decoration: AppDecorations.card(context),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    p.gallery.isEmpty
                        ? ColoredBox(color: context.surfaceMid, child: Icon(Icons.shopping_bag_outlined, color: context.textMuted))
                        : Image.network(p.gallery.first, fit: BoxFit.cover, cacheWidth: 500,
                            errorBuilder: (_, _, _) => ColoredBox(color: context.surfaceMid)),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Row(
                        children: [
                          if (p.has3d) _badge('3D', AppColors.brandBlue, Icons.view_in_ar_rounded),
                          if (pct != null) ...[const SizedBox(width: 4), _badge('-$pct%', AppColors.brandPink, null)],
                        ],
                      ),
                    ),
                    if (p.soldOut)
                      Positioned(right: 6, top: 6, child: _badge('SOLD OUT', context.textSecondary, null)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.sectionTitle(context.textPrimary)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(formatMoney(p.price, p.currency), style: AppTypography.callout(context.textPrimary)),
                        if (pct != null) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(formatMoney(p.compareAtPrice!, p.currency),
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.caption(context.textMuted).copyWith(decoration: TextDecoration.lineThrough)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, Color color, IconData? icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.xs)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 10, color: Colors.white), const SizedBox(width: 3)],
            Text(label, style: AppTypography.micro(Colors.white).copyWith(fontSize: 9)),
          ],
        ),
      );
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.label, required this.onTap, this.filled = false, this.color = AppColors.brandBlue});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: filled ? color : context.surface,
          foregroundColor: filled ? Colors.white : context.textPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: AppTypography.callout(Colors.white),
        ),
        onPressed: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        icon: Icon(icon, size: 17),
        label: Text(label),
      ),
    );
  }
}
