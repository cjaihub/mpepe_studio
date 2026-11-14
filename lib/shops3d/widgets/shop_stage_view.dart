import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../identity/widgets/oneova_verified_badge.dart';
import '../../shared/theme/app_theme.dart';
import '../../backend/live_studio/session/studio_session_controller.dart' show studioMyRoleProvider;
import '../data/share_ref.dart';
import '../data/shop3d_repository.dart';
import '../data/stage_show.dart';
import '../models/shop_models.dart';
import '../../backend/social/repositories/relationship_repository.dart';
import 'customization_picker.dart';
import 'live_commerce.dart';
import 'product_3d_viewer.dart';
import 'product_info_card.dart';
import 'shop_map_card.dart';
import 'stage_live.dart';
import 'stage_style.dart';
import 'texture_picker.dart';

/// Public link for a storefront.
String shopShareUrl(String shopId) => 'https://oneova.web.app/shops/$shopId';

String productRoute(ShopProduct p, ProductVariant? v) => '/shops/p/${p.id}${v == null ? '' : '?variant=${Uri.encodeQueryComponent(v.id)}'}';

String checkoutRoute(ShopProduct p, ProductVariant? v, {Map<String, String> custom = const {}}) {
  final q = <String, String>{if (v != null) 'variant': v.id, if (custom.isNotEmpty) 'custom': encodeCustomization(custom)};
  return Uri(path: '/biz/checkout/${p.id}', queryParameters: q.isEmpty ? null : q).toString();
}

/// One shop stage in the framed design (same as framed Reels): what's on at
/// the top (live title, shop, LIVE badge, viewers), then a rounded screen frame
/// holding the seller's live video, the product on a lit platform (3D when the
/// seller has a model), the action rail, chat, product switcher and the
/// commerce card.
class ShopStageView extends ConsumerStatefulWidget {
  const ShopStageView({
    super.key,
    required this.shop,
    this.live,
    this.active = true,
    this.preview = false,
    this.onClose,
    this.productsOverride,
  });

  final Shop3D shop;
  final ShopLive? live;

  /// Only the visible page runs the 3D web view.
  final bool active;

  /// Seller preview: real layout and data, inert commerce actions.
  final bool preview;
  final VoidCallback? onClose;

  /// Seller preview shows the seller's catalog including drafts.
  final List<ShopProduct>? productsOverride;

  @override
  ConsumerState<ShopStageView> createState() => _ShopStageViewState();
}

class _ShopStageViewState extends ConsumerState<ShopStageView> {
  String? _productId;
  final Map<String, ProductVariant> _variants = {};
  final _controller = Product3DController();

  /// The viewer is turning the product themselves instead of following the presenter.
  bool _explore = false;
  StageShow _show = StageShow.empty;

  /// The live this seller already opened the show for.
  String? _claimed;

  bool get _liveNow => widget.live != null && widget.active && !widget.preview;

  ShopProduct? _current(List<ShopProduct> products) {
    if (products.isEmpty) return null;
    // On a live, viewers follow what is on air until they pick something themselves.
    final want = _productId ?? (_liveNow ? _show.activeId : null) ?? widget.shop.featuredProductId;
    for (final p in products) {
      if (p.id == want) return p;
    }
    return products.firstWhere((p) => p.sellable, orElse: () => products.first);
  }

  ProductVariant? _variantOf(ShopProduct p) {
    if (p.variants.isEmpty) return null;
    return _variants[p.id] ?? p.variants.firstWhere((v) => !v.soldOut, orElse: () => p.variants.first);
  }

  bool get _isOwner => ref.read(shop3dRepositoryProvider).uid == widget.shop.ownerId;

  Future<void> _share() async {
    HapticFeedback.lightImpact();
    final shop = widget.shop;
    // A tracked link: opens the app on this shop, or the store without the app.
    final url = await ShareRef.linkFor('shop', shop.id, fallback: shopShareUrl(shop.id));
    await SharePlus.instance.share(ShareParams(text: '${shop.name} on Oneova 3D Shops\n$url', subject: shop.name));
  }

  /// Reacts to the presenter: a new product on air, a jump to a named view.
  void _onShow(StageShow? prev, StageShow next, bool canPresent) {
    _show = next;
    if (!_liveNow) return;
    if (next.activeId != null && next.activeId != prev?.activeId && next.by != ref.read(shop3dRepositoryProvider).uid) {
      if (_productId != null && _productId != next.activeId) {
        // The viewer chose another product; tell them instead of pulling them away.
        final products = ref.read(shopProductsProvider(widget.shop.ownerId)).value ?? const <ShopProduct>[];
        final p = products.where((x) => x.id == next.activeId).firstOrNull;
        if (p != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text('Now showing: ${p.name}'),
                action: SnackBarAction(label: 'View', onPressed: () => setState(() => _productId = null)),
              ),
            );
        }
      } else if (mounted) {
        setState(() {});
      }
    }
    if (next.viewAt != (prev?.viewAt ?? 0) && next.view != null && !_explore && !canPresent) {
      final v = ProductView.values.where((x) => x.name == next.view).firstOrNull;
      if (v != null) _controller.show(v);
    }
  }

  /// The presenter picked a product: it goes on air for everyone.
  void _putOnAir(ShopProduct p) {
    setState(() => _productId = p.id);
    ref.read(stageShowRepositoryProvider).present(widget.shop.id, {
      'streamId': widget.live!.streamId,
      'activeId': p.id,
      'cam': null,
      'camProductId': p.id,
      'animation': null,
    });
  }

  /// Products already counted as viewed on this stage.
  final Set<String> _viewed = {};

  void _countView(ShopProduct p) {
    if (!widget.active || widget.preview || !_viewed.add(p.id)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(shop3dRepositoryProvider).trackEvent(widget.shop.id, 'view', productId: p.id);
    });
  }

  Future<void> _addToCart(ShopProduct p, ProductVariant? v) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(shop3dRepositoryProvider).addToCart(p, v);
      ref.read(shop3dRepositoryProvider).trackEvent(widget.shop.id, 'cart', productId: p.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text('${p.name} added to your cart'),
          action: SnackBarAction(label: 'View', onPressed: () => showShopCartSheet(context)),
        ),
      );
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// One place for everything that is not a primary action.
  void _more(ShopProduct p) {
    final live = widget.live;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (sheet) {
        Widget tile(IconData icon, String label, VoidCallback onTap) => ListTile(
          leading: Icon(icon, color: sheet.textPrimary),
          title: Text(label, style: AppTypography.callout(sheet.textPrimary)),
          onTap: () {
            Navigator.pop(sheet);
            onTap();
          },
        );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              if (live != null) tile(Icons.sensors_rounded, 'Open the full live room', () => context.push('/live/viewer/${live.streamId}')),
              if (p.has3d) tile(Icons.view_in_ar_rounded, 'Explore in 3D', () => context.push(productRoute(p, _variantOf(p)))),
              if (!_isOwner)
                tile(Icons.auto_awesome_rounded, 'Ask Ova about this product', () => ProductPreviewScreen.open(context, widget.shop, p)),
              if (_isOwner) tile(Icons.forum_outlined, 'Shopper questions', () => showSellerChatsSheet(context, widget.shop)),
              if (widget.shop.hasPickup) tile(Icons.near_me_outlined, 'Find the shop', () => showShopMapSheet(context, widget.shop)),
              tile(Icons.storefront_outlined, 'Visit store', () => context.push('/shops/${widget.shop.id}')),
              tile(Icons.bookmarks_outlined, 'Saved products', () => context.push('/shops/saved')),
              if (_isOwner) tile(Icons.local_fire_department_rounded, 'Live deal', () => showLiveDealEditor(context, ref, widget.shop)),
              if (_isOwner && p.has3d)
                tile(Icons.texture_rounded, 'Show a texture on air', () async {
                  final t = await showTexturePicker(context);
                  if (t == null) return;
                  await ref.read(shop3dRepositoryProvider).setStageTexture(p.id, ProductTexture(material: '', texture: t));
                }),
              if (_isOwner && widget.shop.stageTexture != null)
                tile(
                  Icons.format_color_reset_rounded,
                  'Back to the original look',
                  () => ref.read(shop3dRepositoryProvider).setStageTexture(p.id, null),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = StageStyle.of(context, widget.shop.stage);
    final liveNow = _liveNow;
    // On the live's stage (host, co-host, guest) = can steer the 3D for everyone.
    final role = liveNow ? ref.watch(studioMyRoleProvider(widget.live!.streamId)).value : null;
    final canPresent = liveNow && (_isOwner || (role?.canPublish ?? false));
    if (liveNow) {
      _show = ref.watch(stageShowProvider(widget.shop.id)).value ?? _show;
      ref.listen(stageShowProvider(widget.shop.id), (prev, next) {
        if (next.value != null) _onShow(prev?.value, next.value!, canPresent);
      });
    }
    // A new live starts a fresh show: stage guests can steer it, nothing is
    // left over from the last one.
    if (liveNow && _isOwner && _claimed != widget.live!.streamId) {
      _claimed = widget.live!.streamId;
      final streamId = _claimed!;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final current = await ref.read(stageShowRepositoryProvider).watchShow(widget.shop.id).first;
        if (current.streamId == streamId) return;
        await ref.read(stageShowRepositoryProvider).present(widget.shop.id, {
          'streamId': streamId,
          'activeId': null,
          'cam': null,
          'camProductId': null,
          'animation': null,
          'spin': null,
          'spotlight': null,
          'view': null,
          'viewAt': 0,
        });
      });
    }
    final productsAsync = widget.productsOverride != null
        ? AsyncValue.data(widget.productsOverride!)
        : ref.watch(shopProductsProvider(widget.shop.ownerId));

    final appDark = context.isDark;
    final stage = Stack(
      fit: StackFit.expand,
      children: [
        StageBackdropLayer(style: style),
        if (widget.live != null && widget.active && !widget.preview)
          Positioned.fill(
            child: SellerLiveLayer(streamId: widget.live!.streamId, hostId: widget.shop.ownerId, style: style),
          ),
        Column(
          children: [
            if (widget.live != null && !widget.active)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _LiveBanner(
                  live: widget.live!,
                  style: style,
                  preview: widget.preview,
                ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.1, end: 0),
              ),
            if (widget.shop.liveDeal?.active ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LiveDealCard(
                  deal: widget.shop.liveDeal!,
                  style: style,
                ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.96, 0.96)),
              ),
            Expanded(
              child: productsAsync.when(
                loading: () => Center(child: CircularProgressIndicator(color: style.accent, strokeWidth: 2)),
                error: (_, _) =>
                    _Message(style: style, icon: Icons.wifi_off_rounded, text: "Couldn't load this showroom. Check your connection."),
                data: (products) {
                  final p = _current(products);
                  if (p == null) {
                    return _Message(
                      style: style,
                      icon: Icons.inventory_2_outlined,
                      text: 'This shop is still setting up its showroom.',
                      action: widget.preview ? null : ('Visit store', () => context.push('/shops/${widget.shop.id}')),
                    );
                  }
                  _countView(p);
                  return _Stage(
                    key: ValueKey(widget.shop.id),
                    shop: widget.shop,
                    products: products,
                    product: p,
                    variant: _variantOf(p),
                    style: style,
                    active: widget.active,
                    preview: widget.preview,
                    isOwner: _isOwner,
                    show: liveNow ? _show : StageShow.empty,
                    canPresent: canPresent,
                    explore: _explore,
                    controller: _controller,
                    onExplore: (v) => setState(() => _explore = v),
                    onCamera: (pose) => ref.read(stageShowRepositoryProvider).present(widget.shop.id, {
                      'cam': pose.toMap(),
                      'camProductId': p.id,
                      'spin': false,
                    }),
                    onPreview: (x) => ProductPreviewScreen.open(context, widget.shop, x),
                    onPick: (x) {
                      if (canPresent) return _putOnAir(x);
                      // Watching a live: a card opens the full preview; the live keeps running behind it.
                      if (liveNow) return ProductPreviewScreen.open(context, widget.shop, x).ignore();
                      setState(() => _productId = x.id);
                    },
                    onVariant: (v) => setState(() => _variants[p.id] = v),
                    onShare: _share,
                    live: widget.live,
                    onMore: () => _more(p),
                    onAddToCart: () => _addToCart(p, _variantOf(p)),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: appDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Stack(
        fit: StackFit.expand,
        children: [
          StageFrameBackdrop(dark: appDark),
          SafeArea(
            child: Column(
              children: [
                _TopBar(shop: widget.shop, live: widget.live, onClose: widget.onClose, preview: widget.preview),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                    child: StageFrame(dark: appDark, child: stage),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The page behind the frame: quiet surface with a soft blue-to-pink glow,
/// the same as framed Reels.
class StageFrameBackdrop extends StatelessWidget {
  const StageFrameBackdrop({super.key, required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final base = dark ? AppColors.darkBackground : AppColors.lightSurface;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: base,
          gradient: RadialGradient(
            center: const Alignment(0, 0.35),
            radius: 1.1,
            colors: [
              AppColors.brandBlue.withValues(alpha: dark ? 0.20 : 0.08),
              AppColors.brandPink.withValues(alpha: dark ? 0.06 : 0.04),
              base,
            ],
            stops: const [0, 0.45, 1],
          ),
        ),
      ),
    );
  }
}

/// The screen frame: 25 px corners, hairline border, soft brand shadow.
class StageFrame extends StatelessWidget {
  const StageFrame({super.key, required this.dark, required this.child});
  final bool dark;
  final Widget child;

  static const radius = 25.0;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandBlue.withValues(alpha: dark ? 0.22 : 0.14),
              blurRadius: 24,
              spreadRadius: -6,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: AppColors.brandPink.withValues(alpha: dark ? 0.12 : 0.08),
              blurRadius: 16,
              spreadRadius: -8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The product's textures with the one the seller is showing on air on top.
List<ProductTexture>? _onAir(Shop3D shop, ShopProduct p) {
  final st = shop.stageTexture;
  if (st == null || st.productId != p.id) return null;
  return [
    for (final t in p.textures)
      if (st.texture.material.isNotEmpty && t.material != st.texture.material) t,
    st.texture,
  ];
}

class _Stage extends StatelessWidget {
  const _Stage({
    super.key,
    required this.shop,
    required this.products,
    required this.product,
    required this.variant,
    required this.style,
    required this.active,
    required this.preview,
    required this.isOwner,
    required this.onPick,
    required this.onVariant,
    required this.onShare,
    required this.onMore,
    required this.onAddToCart,
    required this.show,
    required this.canPresent,
    required this.explore,
    required this.controller,
    required this.onExplore,
    required this.onCamera,
    required this.onPreview,
    this.live,
  });

  final StageShow show;
  final bool canPresent;
  final bool explore;
  final Product3DController controller;
  final ValueChanged<bool> onExplore;
  final ValueChanged<CameraPose> onCamera;
  final ValueChanged<ShopProduct> onPreview;

  final VoidCallback onMore;
  final VoidCallback onAddToCart;
  final ShopLive? live;
  final Shop3D shop;
  final List<ShopProduct> products;
  final ShopProduct product;
  final ProductVariant? variant;
  final StageStyle style;
  final bool active;
  final bool preview;
  final bool isOwner;
  final ValueChanged<ShopProduct> onPick;
  final ValueChanged<ProductVariant> onVariant;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final railRight = shop.stage.card == CardPlacement.right;
    final width = MediaQuery.sizeOf(context).width;
    // The frame is inset 8 px on each side; the card keeps 12 px inside it.
    final cardWidth = width >= 600 ? 380.0 : width - 40;

    void open() {
      if (preview) return;
      HapticFeedback.lightImpact();
      context.push(productRoute(product, variant));
    }

    final streamId = active && !preview ? live?.streamId : null;
    final onLive = streamId != null;
    // Presenters and viewers who chose to explore turn the model themselves.
    final handsOn = onLive && (canPresent || explore);
    final following = onLive && !handsOn;
    final shelf = onLive && show.shelf.isNotEmpty ? [for (final id in show.shelf) ...products.where((x) => x.id == id)] : products;
    final rail = EngagementRail(
      shop: shop,
      product: product,
      style: style,
      preview: preview,
      streamId: streamId,
      onShare: onShare,
      onMore: onMore,
    );

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              // Product + platform.
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.only(left: railRight ? 12 : 64, right: railRight ? 64 : 12),
                  child: Column(
                    children: [
                      Expanded(
                        child: Semantics(
                          button: !preview,
                          label: 'Open ${product.name}',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: handsOn ? null : (onLive ? () => onPreview(product) : open),
                            // The feed keeps the 3D view non-interactive so the
                            // vertical swipe always works. On a live it becomes
                            // interactive for presenters and for viewers who
                            // choose to explore.
                            child: IgnorePointer(
                              ignoring: !handsOn,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 280),
                                switchInCurve: Curves.easeOutCubic,
                                child: Product3DViewer(
                                  key: ValueKey(product.id),
                                  product: product,
                                  variant: variant,
                                  textures: _onAir(shop, product),
                                  style: style,
                                  live: active,
                                  interactive: handsOn,
                                  autoRotate: shop.stage.autoRotate,
                                  controller: controller,
                                  onUserCamera: canPresent ? onCamera : null,
                                  followPose: following ? show.poseFor(product.id) : null,
                                  spin: following ? (show.spin ?? shop.stage.autoRotate) : null,
                                  animation: onLive && product.modelAnimations.contains(show.animation) ? show.animation : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: const Offset(0, -18),
                        child: StagePlatform(style: style, width: (cardWidth * 0.72).clamp(200, 300)),
                      ),
                    ],
                  ),
                ),
              ),
              // Explore hint.
              Positioned(
                left: 0,
                right: 0,
                top: 4,
                child: Center(
                  child: GestureDetector(
                    // On a live, viewers switch between following the presenter and exploring.
                    onTap: !onLive
                        ? open
                        : (canPresent || !product.has3d
                              ? null
                              : () {
                                  HapticFeedback.selectionClick();
                                  onExplore(!explore);
                                }),
                    child: GlassPanel(
                      style: style,
                      radius: AppRadius.full,
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            !product.has3d
                                ? Icons.photo_library_outlined
                                : (onLive && explore ? Icons.podcasts_rounded : Icons.threesixty_rounded),
                            size: 14,
                            color: style.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            !product.has3d
                                ? 'Tap for details'
                                : !onLive
                                ? 'Tap to explore in 3D'
                                : canPresent
                                ? 'Everyone sees how you turn it'
                                : explore
                                ? 'Exploring · back to presenter'
                                : 'Following the presenter · explore yourself',
                            style: AppTypography.caption(style.fg).copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (onLive && show.spotlight != null)
                Positioned(
                  left: railRight ? 12 : 72,
                  right: railRight ? 72 : 12,
                  top: 40,
                  child: SpotlightCard(show: show, style: style),
                ),
              // Action rail.
              Positioned(
                top: 8,
                bottom: 8,
                right: railRight ? 10 : null,
                left: railRight ? null : 10,
                child: Center(child: rail),
              ),
              if (streamId != null)
                Positioned(
                  right: railRight ? 6 : null,
                  left: railRight ? null : 6,
                  bottom: 40,
                  width: 56,
                  height: 240,
                  child: LiveHearts(streamId: streamId),
                ),
              // Live comments, or Ova when the seller is away.
              if (!preview && active)
                Positioned(
                  left: railRight ? 10 : 76,
                  right: railRight ? 76 : 10,
                  bottom: 34,
                  child: ShopLiveChat(shop: shop, products: products, style: style, streamId: streamId),
                ),
            ],
          ),
        ),
        if (canPresent)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: PresenterBar(shop: shop, product: product, show: show, style: style, controller: controller, isOwner: isOwner),
          ),
        if (shelf.length > 1)
          ShelfCards(
            products: shelf,
            current: product,
            style: style,
            onAirId: onLive ? show.activeId : null,
            onTap: onPick,
            onInfo: preview ? null : onPreview,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Align(
            alignment: railRight ? Alignment.centerLeft : Alignment.centerRight,
            child: SizedBox(
              width: cardWidth,
              child: ProductInfoCard(
                product: product,
                style: style,
                variant: variant,
                onVariant: onVariant,
                isOwner: isOwner,
                preview: preview,
                onOpen: preview ? null : open,
                // Required customizations are chosen on the product page.
                onBuy: () => product.customization.any((o) => o.required)
                    ? context.push(productRoute(product, variant))
                    : context.push(checkoutRoute(product, variant)),
                onAddToCart: product.customization.any((o) => o.required) ? null : onAddToCart,
                deal: shop.liveDeal,
                rating: shop.rating,
              ),
            ),
          ),
        ).animate(key: ValueKey(product.id)).fadeIn(duration: 220.ms).slideY(begin: 0.04, end: 0),
      ],
    );
  }
}

/// What's on, above the frame: the live's title (or the shop's line), the
/// shop with its badge, LIVE and viewers, then Follow and Close.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.shop, required this.live, required this.onClose, required this.preview});
  final Shop3D shop;
  final ShopLive? live;
  final VoidCallback? onClose;
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final live = this.live;
    final title = live != null
        ? (live.title.trim().isNotEmpty ? live.title.trim() : '${shop.name} is live')
        : (shop.tagline.trim().isNotEmpty ? shop.tagline.trim() : '${shop.name} showroom');
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            if (onClose != null) ...[
              _CircleButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', onTap: onClose!),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Semantics(
                button: !preview,
                label: 'Visit ${shop.name}',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: preview ? null : () => context.push('/shops/${shop.id}'),
                  child: Row(
                    children: [
                      _ShopAvatar(shop: shop, live: live != null),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.sectionTitle(context.textPrimary),
                            ),
                            const SizedBox(height: 1),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    shop.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.caption(context.textSecondary),
                                  ),
                                ),
                                if (shop.verified) ...[
                                  const SizedBox(width: 3),
                                  OneovaVerifiedBadge(kind: VerifiedKind.business, level: shop.verifiedLevel, size: 12),
                                ],
                                if (live != null) ...[
                                  const SizedBox(width: 6),
                                  const StagePill(label: 'LIVE', color: AppColors.brandPink, icon: Icons.circle),
                                  const SizedBox(width: 5),
                                  Icon(Icons.visibility_outlined, size: 12, color: context.textSecondary),
                                  const SizedBox(width: 2),
                                  Text(_compact(live.viewerCount), style: AppTypography.micro(context.textSecondary)),
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
            ),
            if (!preview) ...[const SizedBox(width: 8), _FollowChip(sellerId: shop.ownerId)],
          ],
        ),
      ),
    );
  }
}

/// Shop picture with a pink ring while the seller is live.
class _ShopAvatar extends StatelessWidget {
  const _ShopAvatar({required this.shop, required this.live});
  final Shop3D shop;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: live ? AppColors.brandPink : context.border, width: 1.5),
      ),
      child: ClipOval(
        child: shop.avatarUrl.startsWith('http')
            ? Image.network(shop.avatarUrl, fit: BoxFit.cover, cacheWidth: 120, errorBuilder: (_, _, _) => _initial(context))
            : _initial(context),
      ),
    );
  }

  Widget _initial(BuildContext context) => ColoredBox(
    color: AppColors.brandBlue,
    child: Center(
      child: Text(
        shop.name.isEmpty ? '?' : shop.name.characters.first.toUpperCase(),
        style: AppTypography.callout(Colors.white).copyWith(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class _LiveBanner extends StatelessWidget {
  const _LiveBanner({required this.live, required this.style, required this.preview});
  final ShopLive live;
  final StageStyle style;
  final bool preview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: preview
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  context.push('/live/viewer/${live.streamId}');
                },
          child: GlassPanel(
            style: style,
            radius: AppRadius.md,
            padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
            child: Row(
              children: [
                const Icon(Icons.videocam_rounded, size: 16, color: AppColors.brandPink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    live.title.isEmpty ? 'The seller is live now' : live.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.small(style.fg).copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.brandPink, borderRadius: BorderRadius.circular(AppRadius.sm)),
                  child: Text('Watch live', style: AppTypography.small(Colors.white).copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Follow the seller from the stage header.
class _FollowChip extends ConsumerWidget {
  const _FollowChip({required this.sellerId});
  final String sellerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(shop3dRepositoryProvider).uid;
    if (me == null || me == sellerId) return const SizedBox.shrink();
    final repo = ref.read(relationshipRepositoryProvider);
    return StreamBuilder<bool>(
      stream: repo.watchIsFollowing(me, sellerId),
      builder: (context, snap) {
        final following = snap.data ?? false;
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            following ? repo.unfollowUser(me, sellerId) : repo.followUser(me, sellerId);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: following ? Colors.transparent : AppColors.brandBlue,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: following ? context.border : AppColors.brandBlue),
            ),
            child: Text(
              following ? 'Following' : 'Follow',
              style: AppTypography.small(following ? context.textPrimary : Colors.white).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        );
      },
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.tooltip, this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onTap!();
                },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
              border: Border.all(color: context.border),
            ),
            child: Icon(icon, size: 20, color: context.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.style, required this.icon, required this.text, this.action});
  final StageStyle style;
  final IconData icon;
  final String text;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: style.fgMuted),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: AppTypography.body(style.fgSecondary)),
            if (action != null) ...[
              const SizedBox(height: 14),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: style.fg,
                  side: BorderSide(color: style.hairline),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                onPressed: action!.$2,
                child: Text(action!.$1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _compact(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
  return '$n';
}
