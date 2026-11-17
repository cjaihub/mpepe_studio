// Live stage pieces:
//   PresenterBar          the seller / stage guest steers the 3D for everyone
//   ShelfCards            the goods of this live as small price cards
//   SpotlightCard         a question the seller answered on air
//   ProductPreviewScreen  full preview of one product with the Ova chat;
//                         back returns to the live
//   ShopProductChat       shopper ↔ Ova, the seller can step in
//   showSellerChatsSheet  the seller reads every conversation, takes over,
//                         answers privately or on air

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../shared/audio/ova_vertex_audio_engine.dart';
import '../../shared/theme/app_theme.dart';
import '../../social_hub/biz_commerce/checkout_screen.dart' show formatMoney;
import '../data/currencies.dart';
import '../data/shop3d_repository.dart';
import '../data/stage_show.dart';
import '../models/shop_models.dart';
import 'product_3d_viewer.dart';
import 'reviews.dart';
import 'shop_map_card.dart';
import 'shop_stage_view.dart' show checkoutRoute, productRoute;
import 'stage_style.dart';

// ───────────────────────────── Presenter ─────────────────────────────

/// Controls for whoever is presenting: jump to a view, spin, play the
/// model's animations. Every change is sent to all viewers of the stage.
class PresenterBar extends ConsumerWidget {
  const PresenterBar({
    super.key,
    required this.shop,
    required this.product,
    required this.show,
    required this.style,
    required this.controller,
    required this.isOwner,
  });

  final Shop3D shop;
  final ShopProduct product;
  final StageShow show;
  final StageStyle style;
  final Product3DController controller;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(stageShowRepositoryProvider);
    final spinning = show.spin ?? shop.stage.autoRotate;
    final unread = isOwner ? (ref.watch(shopChatsProvider(shop.id)).value ?? const []).fold<int>(0, (a, c) => a + c.unread) : 0;
    final views = isOwner ? (ref.watch(shopViewsTodayProvider(shop.id)).value ?? const {})[product.id] ?? 0 : 0;

    Widget chip(String label, {IconData? icon, bool on = false, required VoidCallback onTap, int badge = 0}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: on ? style.accent : style.glass,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: on ? style.accent : style.hairline),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 13, color: on ? Colors.white : style.fg), const SizedBox(width: 4)],
                Text(label, style: AppTypography.caption(on ? Colors.white : style.fg).copyWith(fontWeight: FontWeight.w600)),
                if (badge > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.brandPink, borderRadius: BorderRadius.circular(AppRadius.full)),
                    child: Text('$badge', style: AppTypography.micro(Colors.white)),
                  ),
                ],
              ]),
            ),
          ),
        );

    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: StagePill(label: 'PRESENTING', color: AppColors.brandPink, icon: Icons.podcasts_rounded)),
          ),
          if (isOwner) chip('Questions', icon: Icons.forum_outlined, badge: unread, onTap: () => showSellerChatsSheet(context, shop)),
          if (isOwner && views > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(child: Text('$views views today', style: AppTypography.caption(style.fgSecondary))),
            ),
          if (product.has3d) ...[
            for (final v in ProductView.values)
              chip(v.label, onTap: () {
                // Stops the spin so the view holds, then shares the new pose.
                controller.spin(false);
                controller.show(v);
                repo.present(shop.id, {'spin': false, 'cam': null, 'camProductId': product.id, 'view': v.name, 'viewAt': DateTime.now().millisecondsSinceEpoch});
              }),
            chip(spinning ? 'Spinning' : 'Spin', icon: Icons.threesixty_rounded, on: spinning, onTap: () {
              controller.spin(!spinning);
              repo.present(shop.id, {'spin': !spinning});
            }),
            for (final a in product.modelAnimations)
              chip(a, icon: show.animation == a ? Icons.pause_rounded : Icons.play_arrow_rounded, on: show.animation == a, onTap: () {
                repo.present(shop.id, {'animation': show.animation == a ? null : a});
              }),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────────── Shelf ─────────────────────────────

/// The goods of this live as small cards: photo, price, an ON AIR tag on the
/// one being presented.
class ShelfCards extends ConsumerWidget {
  const ShelfCards({
    super.key,
    required this.products,
    required this.current,
    required this.style,
    required this.onTap,
    this.onAirId,
    this.onInfo,
  });

  final List<ShopProduct> products;
  final ShopProduct current;
  final StageStyle style;
  final String? onAirId;
  final ValueChanged<ShopProduct> onTap;

  /// Opens the full preview (shown as a small expand corner).
  final ValueChanged<ShopProduct>? onInfo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: products.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = products[i];
          final on = p.id == current.id;
          final air = p.id == onAirId;
          return Semantics(
            button: true,
            selected: on,
            label: '${p.name}, ${formatMoney(p.price, p.currency)}',
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap(p);
              },
              onLongPress: onInfo == null ? null : () => onInfo!(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 148,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: style.glass,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: on ? style.accent : style.hairline, width: 1),
                  boxShadow: on ? AppShadows.glow(style.accent, radius: 10, spread: 0) : null,
                ),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: Stack(fit: StackFit.expand, children: [
                        StageImage(url: p.gallery.isEmpty ? '' : p.gallery.first, style: style, cacheWidth: 150),
                        if (p.has3d)
                          Positioned(
                            right: 2,
                            bottom: 2,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(color: style.accent, borderRadius: BorderRadius.circular(AppRadius.xs)),
                              child: const Icon(Icons.view_in_ar_rounded, size: 9, color: Colors.white),
                            ),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption(style.fg).copyWith(fontWeight: FontWeight.w600)),
                      Text(formatMoney(p.price, p.currency), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption(style.fgSecondary)),
                      if (air) const Padding(padding: EdgeInsets.only(top: 2), child: StagePill(label: 'ON AIR', color: AppColors.brandPink)),
                    ]),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// "Seller answered" card, visible to everyone for a short while.
class SpotlightCard extends StatefulWidget {
  const SpotlightCard({super.key, required this.show, required this.style});
  final StageShow show;
  final StageStyle style;

  @override
  State<SpotlightCard> createState() => _SpotlightCardState();
}

class _SpotlightCardState extends State<SpotlightCard> {
  Timer? _hide;
  static const _for = Duration(seconds: 20);

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.show.spotlight;
    if (s == null) return const SizedBox.shrink();
    final left = _for - DateTime.now().difference(s.at);
    if (left.isNegative) return const SizedBox.shrink();
    _hide?.cancel();
    _hide = Timer(left, () => mounted ? setState(() {}) : null);
    return GlassPanel(
      style: widget.style,
      strong: true,
      radius: AppRadius.md,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        const StagePill(label: 'SELLER ANSWERED', color: AppColors.brandPink, icon: Icons.campaign_rounded),
        if (s.question.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(s.question, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.caption(widget.style.fgSecondary)),
        ],
        const SizedBox(height: 3),
        Text(s.answer, maxLines: 4, overflow: TextOverflow.ellipsis, style: AppTypography.small(widget.style.fg).copyWith(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ───────────────────────────── Preview ─────────────────────────────

/// Full preview of one product over the live: turn and zoom it yourself, read
/// the details, ask Ova. Back returns to the live exactly where it was.
class ProductPreviewScreen extends ConsumerStatefulWidget {
  const ProductPreviewScreen({super.key, required this.shop, required this.product});
  final Shop3D shop;
  final ShopProduct product;

  static Future<void> open(BuildContext context, Shop3D shop, ShopProduct product) {
    HapticFeedback.lightImpact();
    return Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => ProductPreviewScreen(shop: shop, product: product),
      transitionsBuilder: (_, a, _, child) => FadeTransition(
        opacity: a,
        child: SlideTransition(position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(a), child: child),
      ),
    ));
  }

  @override
  ConsumerState<ProductPreviewScreen> createState() => _ProductPreviewScreenState();
}

class _ProductPreviewScreenState extends ConsumerState<ProductPreviewScreen> {
  final _controller = Product3DController();

  @override
  Widget build(BuildContext context) {
    // Live data: price, stock and the model can change during the live.
    final p = ref.watch(shopProductProvider(widget.product.id)).value ?? widget.product;
    final shop = widget.shop;
    final style = StageStyle.of(context, shop.stage);
    final rates = ref.watch(fxRatesProvider).value ?? FxRates.empty;
    final deal = shop.liveDeal != null && shop.liveDeal!.appliesTo(p.id) ? shop.liveDeal : null;
    final price = deal == null ? p.price : deal.priceFor(p.price, p.currency);
    final local = approxLocal(price, p.currency, rates);
    final mine = ref.read(shop3dRepositoryProvider).uid == p.ownerId;
    final needsOptions = p.customization.any((o) => o.required) || p.variants.length > 1;

    return Scaffold(
      backgroundColor: style.base,
      resizeToAvoidBottomInset: true,
      body: Stack(fit: StackFit.expand, children: [
        StageBackdropLayer(style: style),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 10, 2),
              child: Row(children: [
                IconButton(
                  tooltip: 'Back to the live',
                  icon: Icon(Icons.arrow_back_rounded, color: style.fg),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.sectionTitle(style.fg)),
                    Text(shop.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption(style.fgSecondary)),
                  ]),
                ),
                if (shop.hasPickup)
                  IconButton(
                    tooltip: 'Find the shop',
                    icon: Icon(Icons.near_me_outlined, size: 20, color: style.fg),
                    onPressed: () => showShopMapSheet(context, shop),
                  ),
              ]),
            ),
            Expanded(
              flex: 5,
              child: Stack(children: [
                Positioned.fill(child: Product3DViewer(product: p, style: style, interactive: true, autoRotate: false, controller: _controller)),
                if (p.has3d)
                  Positioned(
                    left: 10,
                    bottom: 8,
                    right: 110,
                    child: SizedBox(
                      height: 28,
                      child: ListView(scrollDirection: Axis.horizontal, children: [
                        for (final v in ProductView.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                _controller.show(v);
                              },
                              child: GlassPanel(
                                style: style,
                                radius: AppRadius.full,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                child: Text(v.label, style: AppTypography.caption(style.fg).copyWith(fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: GlassPanel(
                style: style,
                strong: true,
                radius: AppRadius.md,
                padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(formatMoney(price, p.currency), style: AppTypography.metric(style.fg).copyWith(fontSize: 17)),
                        if (deal != null) ...[const SizedBox(width: 6), StagePill(label: '-${deal.percentOff}%', color: AppColors.brandPink)],
                      ]),
                      Row(children: [
                        if (local != null) Text('$local  ', style: AppTypography.caption(style.fgSecondary)),
                        ReviewLine(rating: p.rating, count: p.reviewCount, style: style),
                      ]),
                    ]),
                  ),
                  TextButton(onPressed: () => context.push(productRoute(p, null)), child: const Text('Details')),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 38),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                    onPressed: mine || !p.sellable ? null : () => context.push(needsOptions ? productRoute(p, null) : checkoutRoute(p, null)),
                    child: Text(p.soldOut ? 'Sold out' : 'Buy'),
                  ),
                ]),
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: mine
                    ? Center(child: Text('Shoppers ask Ova about this product here.', style: AppTypography.caption(style.fgSecondary)))
                    : ShopProductChat(shop: shop, product: p, style: style),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────────── Shopper chat ─────────────────────────────

/// Whether replies are read aloud; kept while the app is open.
bool _voiceOn = false;

class ShopProductChat extends ConsumerStatefulWidget {
  const ShopProductChat({super.key, required this.shop, required this.product, required this.style});
  final Shop3D shop;
  final ShopProduct product;
  final StageStyle style;

  @override
  ConsumerState<ShopProductChat> createState() => _ShopProductChatState();
}

class _ShopProductChatState extends ConsumerState<ShopProductChat> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _stt = SpeechToText();
  bool _busy = false;
  bool _listening = false;
  int _spoken = -1;

  @override
  void dispose() {
    OvaVertexAudioEngine.instance.stop();
    _stt.stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final q = (text ?? _input.text).trim();
    if (q.isEmpty || _busy) return;
    HapticFeedback.selectionClick();
    _input.clear();
    setState(() => _busy = true);
    try {
      await ref.read(stageShowRepositoryProvider).ask(widget.shop.id, q, productId: widget.product.id);
    } on StateError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mic() async {
    if (_listening) {
      await _stt.stop();
      return setState(() => _listening = false);
    }
    await OvaVertexAudioEngine.instance.stop();
    final ok = await _stt.initialize(onStatus: (s) {
      if ((s == 'done' || s == 'notListening') && mounted) setState(() => _listening = false);
    });
    if (!ok) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Allow the microphone to ask by voice.')));
      return;
    }
    setState(() => _listening = true);
    await _stt.listen(onResult: (r) {
      if (!mounted) return;
      _input.text = r.recognizedWords;
      if (r.finalResult) _send(r.recognizedWords);
    });
  }

  /// Reads new answers aloud while voice is on.
  void _speakNew(List<ShopChatMessage> msgs) {
    if (!_voiceOn || msgs.isEmpty) {
      _spoken = msgs.length - 1;
      return;
    }
    final last = msgs.length - 1;
    if (_spoken == -1) {
      _spoken = last; // don't read history when the chat opens
      return;
    }
    if (last > _spoken && msgs[last].from != 'buyer') {
      _spoken = last;
      unawaited(OvaVertexAudioEngine.instance.speak(msgs[last].text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.style;
    final me = ref.read(stageShowRepositoryProvider).uid;
    if (me == null) return const SizedBox.shrink();
    final key = (widget.shop.id, me);
    final msgs = ref.watch(shopChatMessagesProvider(key)).value ?? const <ShopChatMessage>[];
    final sellerHere = ref.watch(shopChatProvider(key)).value?.takenOver ?? false;
    _speakNew(msgs);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });

    return Column(children: [
      Row(children: [
        Icon(sellerHere ? Icons.storefront_rounded : Icons.auto_awesome_rounded, size: 13, color: sellerHere ? AppColors.brandPink : s.accent),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            sellerHere ? 'The seller joined this chat' : 'Ask Ova about this product · the seller can see and join',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption(s.fgSecondary),
          ),
        ),
        GestureDetector(
          onTap: () {
            setState(() => _voiceOn = !_voiceOn);
            if (!_voiceOn) unawaited(OvaVertexAudioEngine.instance.stop());
          },
          child: Tooltip(
            message: _voiceOn ? 'Answers are read aloud' : 'Read answers aloud',
            child: Icon(_voiceOn ? Icons.volume_up_rounded : Icons.volume_off_outlined, size: 17, color: _voiceOn ? s.accent : s.fgMuted),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      Expanded(
        child: msgs.isEmpty
            ? Align(
                alignment: Alignment.topLeft,
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final q in ['Is it in stock?', 'What sizes or colours are there?', 'How does delivery work?'])
                    GestureDetector(
                      onTap: () => _send(q),
                      child: GlassPanel(
                        style: s,
                        radius: AppRadius.full,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Text(q, style: AppTypography.caption(s.fg)),
                      ),
                    ),
                ]),
              )
            : ListView.builder(
                controller: _scroll,
                padding: EdgeInsets.zero,
                itemCount: msgs.length + (_busy ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i >= msgs.length) return _line(s, 'Ova', 'Thinking…', mine: false, seller: false);
                  final m = msgs[i];
                  return _line(s, m.from == 'buyer' ? 'You' : (m.from == 'seller' ? widget.shop.name : 'Ova'), m.text, mine: m.from == 'buyer', seller: m.from == 'seller');
                },
              ),
      ),
      const SizedBox(height: 6),
      GlassPanel(
        style: s,
        radius: AppRadius.full,
        padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              style: AppTypography.body(s.fg),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              maxLength: 500,
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                border: InputBorder.none,
                hintText: _listening ? 'Listening…' : 'Ask about this product',
                hintStyle: AppTypography.body(s.fgMuted),
              ),
            ),
          ),
          IconButton(
            tooltip: _listening ? 'Stop' : 'Ask by voice',
            visualDensity: VisualDensity.compact,
            icon: Icon(_listening ? Icons.stop_circle_outlined : Icons.mic_none_rounded, size: 20, color: _listening ? AppColors.brandPink : s.fg),
            onPressed: _mic,
          ),
          IconButton(
            tooltip: 'Send',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.arrow_upward_rounded, size: 20, color: s.accent),
            onPressed: _busy ? null : _send,
          ),
        ]),
      ),
    ]);
  }

  Widget _line(StageStyle s, String name, String text, {required bool mine, required bool seller}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
              decoration: BoxDecoration(
                color: mine ? AppColors.brandBlue : s.glassStrong,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: mine ? null : Border.all(color: seller ? AppColors.brandPink : s.hairline),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (!mine) Text(name, style: AppTypography.micro(seller ? AppColors.brandPink : s.accent)),
                Text(text, style: AppTypography.small(mine ? Colors.white : s.fg)),
              ]),
            ),
          ),
        ),
      );
}

// ───────────────────────────── Seller panel ─────────────────────────────

/// Every shopper conversation, live. The seller can read along while Ova
/// answers, take a chat over, and answer privately or on air.
Future<void> showSellerChatsSheet(BuildContext context, Shop3D shop) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (_) => SizedBox(height: MediaQuery.sizeOf(context).height * 0.72, child: _SellerChats(shop: shop)),
  );
}

class _SellerChats extends ConsumerStatefulWidget {
  const _SellerChats({required this.shop});
  final Shop3D shop;

  @override
  ConsumerState<_SellerChats> createState() => _SellerChatsState();
}

class _SellerChatsState extends ConsumerState<_SellerChats> {
  String? _buyerId;
  final _input = TextEditingController();
  bool _onAir = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(stageShowRepositoryProvider);
    final shopId = widget.shop.id;
    final chats = ref.watch(shopChatsProvider(shopId)).value ?? const <ShopChatSummary>[];
    final open = _buyerId == null ? null : chats.where((c) => c.buyerId == _buyerId).firstOrNull;

    if (open == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Shopper questions', style: AppTypography.title3(context.textPrimary)),
          Text('Ova answers from your catalog. Open a chat to read along or step in.', style: AppTypography.caption(context.textSecondary)),
          const SizedBox(height: 8),
          Expanded(
            child: chats.isEmpty
                ? Center(child: Text('No questions yet.', style: AppTypography.body(context.textSecondary)))
                : ListView.builder(
                    itemCount: chats.length,
                    itemBuilder: (context, i) {
                      final c = chats[i];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onTap: () {
                          setState(() => _buyerId = c.buyerId);
                          if (c.unread > 0) repo.markRead(shopId, c.buyerId);
                        },
                        title: Row(children: [
                          Flexible(child: Text(c.buyerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.callout(context.textPrimary))),
                          if (c.takenOver) ...[const SizedBox(width: 6), const StagePill(label: 'YOU', color: AppColors.brandPink)],
                        ]),
                        subtitle: Text(
                          '${c.productName == null ? '' : '${c.productName} · '}${c.lastFrom == 'ova' ? 'Ova: ' : (c.lastFrom == 'seller' ? 'You: ' : '')}${c.lastText}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption(context.textSecondary),
                        ),
                        trailing: c.unread > 0
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.brandPink, borderRadius: BorderRadius.circular(AppRadius.full)),
                                child: Text('${c.unread}', style: AppTypography.micro(Colors.white)),
                              )
                            : Icon(Icons.chevron_right_rounded, size: 18, color: context.textMuted),
                      );
                    },
                  ),
          ),
        ]),
      );
    }

    final msgs = ref.watch(shopChatMessagesProvider((shopId, open.buyerId))).value ?? const <ShopChatMessage>[];
    final lastQuestion = msgs.lastWhere((m) => m.from == 'buyer', orElse: () => const ShopChatMessage(from: 'buyer', text: '')).text;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 8, 12, 8 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(children: [
        Row(children: [
          IconButton(icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary), onPressed: () => setState(() => _buyerId = null)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(open.buyerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.sectionTitle(context.textPrimary)),
              Text(open.takenOver ? 'You are answering · Ova is quiet' : 'Ova is answering', style: AppTypography.caption(context.textSecondary)),
            ]),
          ),
          TextButton(
            onPressed: () => repo.setTakenOver(shopId, open.buyerId, !open.takenOver),
            child: Text(open.takenOver ? 'Hand back to Ova' : 'Take over'),
          ),
        ]),
        Expanded(
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: msgs.length,
            itemBuilder: (context, i) {
              final m = msgs[msgs.length - 1 - i];
              final mine = m.from == 'seller';
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.76),
                  decoration: BoxDecoration(
                    color: mine ? AppColors.brandBlue : context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    if (!mine) Text(m.from == 'ova' ? 'Ova' : open.buyerName, style: AppTypography.micro(m.from == 'ova' ? AppColors.brandBlue : context.textSecondary)),
                    Text(m.text, style: AppTypography.small(mine ? Colors.white : context.textPrimary)),
                  ]),
                ),
              );
            },
          ),
        ),
        Row(children: [
          Tooltip(
            message: _onAir ? 'Everyone on the live sees this answer' : 'Only this shopper sees this answer',
            child: FilterChip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(_onAir ? Icons.campaign_rounded : Icons.lock_outline_rounded, size: 14),
              label: Text(_onAir ? 'On air' : 'Private'),
              selected: _onAir,
              onSelected: (v) => setState(() => _onAir = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _input,
              maxLength: 1000,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                hintText: 'Answer ${open.buyerName}',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Send',
            icon: const Icon(Icons.send_rounded, color: AppColors.brandBlue),
            onPressed: () async {
              final text = _input.text;
              if (text.trim().isEmpty) return;
              _input.clear();
              HapticFeedback.selectionClick();
              try {
                await repo.reply(shopId, open.buyerId, text, question: lastQuestion, onAir: _onAir);
              } catch (_) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Your answer wasn't sent. Try again.")));
              }
            },
          ),
        ]),
      ]),
    );
  }
}
