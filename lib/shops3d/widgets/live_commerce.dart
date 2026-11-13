// Live commerce pieces for the shop stage. Each reuses an existing system:
//   SellerLiveLayer   the seller's camera from the live room (viewer join)
//   ShopLiveChat      live comments (seller live) or Ova answering (store live)
//   EngagementRail    love, gift, save, share, cart, more
//   LiveDealCard      the shop's time-limited deal with a countdown
//   showShopCartSheet the private cart; each line checks out on its own
//   showLiveDealEditor seller starts / ends a deal from their own stage

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/live_studio/contracts/studio_contracts.dart' show ReactionKind;
import '../../backend/live_studio/media/livekit_studio_room.dart';
import '../../backend/live_studio/media/studio_video_view.dart';
import '../../backend/live_studio/session/studio_session_controller.dart' show studioRoomProvider;
import '../../backend/live_studio/social/studio_reactions_controller.dart';
import '../../shared/theme/app_theme.dart';
import '../../social_hub/biz_commerce/checkout_screen.dart' show formatMoney;
import '../../social_hub/live/studio_v2/fun/gifts_ui.dart' show showGiftSheet;
import '../../social_hub/live/studio_v2/shell/shell_widgets.dart' show CommentBar, CommentFeed, FloatingHearts;
import '../../social_hub/live/studio_v2/theme/live_studio_tokens.dart';
import '../data/shop3d_repository.dart';
import '../models/shop_models.dart';
import 'shop_stage_view.dart' show checkoutRoute;
import 'stage_style.dart';

// ───────────────────────────── Seller live ─────────────────────────────

/// The seller's camera, full bleed behind the product, while they are live.
/// Joins the live room as a viewer only while this stage is on screen.
class SellerLiveLayer extends ConsumerStatefulWidget {
  const SellerLiveLayer({super.key, required this.streamId, required this.hostId, required this.style});
  final String streamId;
  final String hostId;
  final StageStyle style;

  @override
  ConsumerState<SellerLiveLayer> createState() => _SellerLiveLayerState();
}

class _SellerLiveLayerState extends ConsumerState<SellerLiveLayer> {
  StreamSubscription<void>? _sub;
  Object? _bound;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = ref.watch(studioRoomProvider(widget.streamId));
    if (!identical(room, _bound)) {
      _bound = room;
      _sub?.cancel();
      if (room is LiveKitStudioRoom) _sub = room.mediaChanged.listen((_) => mounted ? setState(() {}) : null);
    }
    final cam = room.cameraOf(widget.hostId);
    return Stack(fit: StackFit.expand, children: [
      if (cam != null)
        StudioVideoView(cam)
      else
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: widget.style.accent)),
            const SizedBox(height: 10),
            Text('Joining the seller live…', style: AppTypography.caption(Colors.white70)),
          ]),
        ),
      // Cinematic grade: keeps the header, product and chat readable.
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xB3000000), Color(0x14000000), Color(0x33000000), Color(0xE6000000)],
            stops: [0, 0.25, 0.55, 1],
          ),
        ),
      ),
    ]);
  }
}

// ───────────────────────────── Chat ─────────────────────────────

/// Live comments while the seller streams; Ova answers when the store runs
/// on its own.
class ShopLiveChat extends StatelessWidget {
  const ShopLiveChat({super.key, required this.shop, required this.products, required this.style, this.streamId});
  final Shop3D shop;
  final List<ShopProduct> products;
  final StageStyle style;
  final String? streamId;

  @override
  Widget build(BuildContext context) {
    final id = streamId;
    if (id != null) {
      const t = LiveStudioTokens.dark;
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(height: 110, child: CommentFeed(streamId: id, tokens: t)),
        const SizedBox(height: 6),
        SizedBox(height: 42, child: CommentBar(streamId: id, tokens: t, phone: true)),
      ]);
    }
    return StoreAssistantChat(shop: shop, products: products, style: style);
  }
}

class _Msg {
  const _Msg(this.text, {required this.mine});
  final String text;
  final bool mine;
}

/// Store live: Ova answers questions from this shop's own catalog.
class StoreAssistantChat extends StatefulWidget {
  const StoreAssistantChat({super.key, required this.shop, required this.products, required this.style});
  final Shop3D shop;
  final List<ShopProduct> products;
  final StageStyle style;

  @override
  State<StoreAssistantChat> createState() => _StoreAssistantChatState();
}

class _StoreAssistantChatState extends State<StoreAssistantChat> {
  final _input = TextEditingController();
  final List<_Msg> _msgs = [];
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  String _catalog() => widget.products.take(20).map((p) {
        final stock = p.soldOut ? 'sold out' : (p.stock == null ? 'in stock' : '${p.stock} in stock');
        final opts = p.variants.isEmpty ? '' : ' Options: ${p.variants.map((v) => v.name).join(', ')}.';
        return '- ${p.name}: ${formatMoney(p.price, p.currency)}, $stock.$opts ${p.description.trim().replaceAll('\n', ' ')}'.trim();
      }).join('\n');

  Future<void> _ask() async {
    final q = _input.text.trim();
    if (q.isEmpty || _busy) return;
    HapticFeedback.selectionClick();
    _input.clear();
    setState(() {
      _msgs.add(_Msg(q, mine: true));
      _busy = true;
    });
    String reply;
    try {
      final r = await FirebaseFunctions.instance
          .httpsCallable('aiGateway', options: HttpsCallableOptions(timeout: const Duration(seconds: 25)))
          .call(<String, dynamic>{
        'prompt': 'You are Ova, answering a shopper in the "${widget.shop.name}" shop on Oneova while the seller is away. '
            'Answer in one or two short, friendly sentences using only the shop details below. '
            'If the answer is not there, say the seller will reply when they are back. Do not use any tools.\n'
            'Shop: ${widget.shop.name}. ${widget.shop.tagline} ${widget.shop.bio}\n'
            'Products:\n${_catalog()}\n'
            'Question: $q',
      });
      reply = (r.data is Map ? r.data['reply'] : null)?.toString().trim() ?? '';
      if (reply.isEmpty) reply = 'The seller will answer this when they are back.';
    } catch (_) {
      reply = 'Ova can’t answer right now. Try again in a moment.';
    }
    if (!mounted) return;
    setState(() {
      _msgs.add(_Msg(reply, mine: false));
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.style;
    final shown = _msgs.length > 2 ? _msgs.sublist(_msgs.length - 2) : _msgs;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_msgs.isEmpty)
        _Bubble(
          style: s,
          name: 'Ova',
          text: 'The seller is away. Ask me about sizes, colors, stock or delivery.',
          ai: true,
        ),
      for (final m in shown) _Bubble(style: s, name: m.mine ? 'You' : 'Ova', text: m.text, ai: !m.mine),
      if (_busy) _Bubble(style: s, name: 'Ova', text: 'Thinking…', ai: true),
      const SizedBox(height: 6),
      GlassPanel(
        style: s,
        radius: AppRadius.full,
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: SizedBox(
          height: 40,
          child: Row(children: [
            const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.brandPink),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _input,
                onSubmitted: (_) => _ask(),
                textInputAction: TextInputAction.send,
                style: AppTypography.small(s.fg),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Ask about this shop…',
                  hintStyle: AppTypography.small(s.fgMuted),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Send',
              visualDensity: VisualDensity.compact,
              onPressed: _ask,
              icon: Icon(Icons.send_rounded, size: 18, color: s.accent),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.style, required this.name, required this.text, this.ai = false});
  final StageStyle style;
  final String name;
  final String text;
  final bool ai;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: GlassPanel(
          style: style,
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '$name  ',
                style: AppTypography.caption(ai ? AppColors.brandPink : style.accent).copyWith(fontWeight: FontWeight.w800),
              ),
              TextSpan(text: text, style: AppTypography.small(style.fg)),
            ]),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
}

// ───────────────────────────── Engagement ─────────────────────────────

/// Love, gift, save, share, cart, more. Love and gift go to the live room
/// while the seller is live; love saves the product when the store is offline.
class EngagementRail extends ConsumerWidget {
  const EngagementRail({
    super.key,
    required this.shop,
    required this.product,
    required this.style,
    required this.onShare,
    required this.onMore,
    this.streamId,
    this.preview = false,
  });

  final Shop3D shop;
  final ShopProduct product;
  final StageStyle style;
  final VoidCallback onShare;
  final VoidCallback onMore;
  final String? streamId;
  final bool preview;

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    try {
      final now = await ref.read(shop3dRepositoryProvider).toggleSaved(product);
      if (now) ref.read(shop3dRepositoryProvider).trackEvent(shop.id, 'save', productId: product.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(now ? 'Saved to your list' : 'Removed from saved')));
      }
    } on StateError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(productSavedProvider(product.id)).value ?? false;
    final cart = ref.watch(cartProvider).value ?? const [];
    final live = streamId;
    final loves = live == null ? 0 : ref.watch(studioReactionsProvider(live)).myLoves;

    Widget item(IconData icon, String label, VoidCallback? onTap, {Color? color, int badge = 0}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: GestureDetector(
              onTap: preview || onTap == null
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      onTap();
                    },
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Stack(clipBehavior: Clip.none, children: [
                  GlassPanel(
                    style: style,
                    radius: AppRadius.full,
                    padding: const EdgeInsets.all(10),
                    child: Icon(icon, size: 21, color: color ?? style.fg),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 17),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.brandPink, borderRadius: BorderRadius.circular(9)),
                        child: Text('$badge',
                            textAlign: TextAlign.center,
                            style: AppTypography.micro(Colors.white).copyWith(fontWeight: FontWeight.w800)),
                      ),
                    ),
                ]),
                const SizedBox(height: 3),
                Text(label, style: AppTypography.caption(style.fgSecondary).copyWith(fontSize: 10)),
              ]),
            ),
          ),
        );

    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (live != null) ...[
        item(Icons.favorite_rounded, loves > 0 ? '$loves' : 'Love',
            () => ref.read(studioReactionsProvider(live).notifier).tap(ReactionKind.love),
            color: AppColors.brandPink),
        item(Icons.card_giftcard_rounded, 'Gift', () => showGiftSheet(context, live)),
      ],
      item(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, saved ? 'Saved' : 'Save',
          () => _save(context, ref),
          color: saved ? AppColors.brandPink : null),
      item(Icons.ios_share_rounded, 'Share', onShare),
      item(Icons.shopping_cart_outlined, 'Cart', () => showShopCartSheet(context), badge: cart.length),
      item(Icons.more_horiz_rounded, 'More', onMore),
    ]);
  }
}

/// Hearts rising from the rail while the seller is live.
class LiveHearts extends StatelessWidget {
  const LiveHearts({super.key, required this.streamId});
  final String streamId;

  @override
  Widget build(BuildContext context) => IgnorePointer(child: FloatingHearts(streamId: streamId, rise: 220));
}

// ───────────────────────────── Live deal ─────────────────────────────

class LiveDealCard extends StatefulWidget {
  const LiveDealCard({super.key, required this.deal, required this.style});
  final LiveDeal deal;
  final StageStyle style;

  @override
  State<LiveDealCard> createState() => _LiveDealCardState();
}

class _LiveDealCardState extends State<LiveDealCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.deal.endsAt.difference(DateTime.now());
    if (left.isNegative) return const SizedBox.shrink();
    String two(int n) => n.toString().padLeft(2, '0');
    final clock = '${two(left.inHours)}:${two(left.inMinutes % 60)}:${two(left.inSeconds % 60)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: LinearGradient(colors: [
          AppColors.brandBlue.withValues(alpha: 0.55),
          AppColors.brandPink.withValues(alpha: 0.55),
        ]),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        boxShadow: [BoxShadow(color: AppColors.brandPink.withValues(alpha: 0.35), blurRadius: 18)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('LIVE DEAL', style: AppTypography.micro(Colors.white).copyWith(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          Text('${widget.deal.percentOff}% OFF ${widget.deal.productIds.isEmpty ? 'today' : 'on picks'}',
              style: AppTypography.callout(Colors.white).copyWith(fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(8)),
          child: Text(clock,
              style: AppTypography.callout(Colors.white).copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w800,
              )),
        ),
      ]),
    );
  }
}

/// Seller: start a deal on their own stage, or end the running one.
Future<void> showLiveDealEditor(BuildContext context, WidgetRef ref, Shop3D shop) {
  var pct = 20.0;
  var minutes = 30;
  final messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, set) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Live deal', style: AppTypography.title2(sheet.textPrimary)),
            const SizedBox(height: 4),
            Text('A discount on your whole shop for a limited time. Buyers see the countdown on your stage.',
                style: AppTypography.small(sheet.textSecondary)),
            const SizedBox(height: 16),
            Text('${pct.round()}% off', style: AppTypography.title3(sheet.textPrimary)),
            Slider(value: pct, min: 5, max: 80, divisions: 15, activeColor: AppColors.brandPink, onChanged: (v) => set(() => pct = v)),
            const SizedBox(height: 4),
            Wrap(spacing: 8, children: [
              for (final m in const [15, 30, 60, 180])
                ChoiceChip(
                  label: Text(m < 60 ? '$m min' : '${m ~/ 60} h'),
                  selected: minutes == m,
                  onSelected: (_) => set(() => minutes = m),
                ),
            ]),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brandPink, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(46)),
              onPressed: () async {
                Navigator.pop(sheet);
                try {
                  await ref.read(shop3dRepositoryProvider).startLiveDeal(percentOff: pct.round(), length: Duration(minutes: minutes));
                  messenger.showSnackBar(const SnackBar(content: Text('Your live deal is on.')));
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('Could not start the deal: $e')));
                }
              },
              child: const Text('Start deal'),
            ),
            if (shop.liveDeal?.active ?? false)
              TextButton(
                onPressed: () async {
                  Navigator.pop(sheet);
                  await ref.read(shop3dRepositoryProvider).endLiveDeal().catchError((_) {});
                  messenger.showSnackBar(const SnackBar(content: Text('Deal ended.')));
                },
                child: const Text('End the current deal'),
              ),
          ]),
        ),
      ),
    ),
  );
}

// ───────────────────────────── Cart ─────────────────────────────

Future<void> showShopCartSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (_) => const _CartSheet(),
  );
}

class _CartSheet extends ConsumerWidget {
  const _CartSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(cartProvider).value ?? const <CartLine>[];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text('Your cart', style: AppTypography.title2(context.textPrimary)),
          ),
          if (lines.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Text('Nothing here yet. Add products from any shop stage.', style: AppTypography.body(context.textSecondary)),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: lines.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: context.border),
                itemBuilder: (context, i) => _CartRow(line: lines[i]),
              ),
            ),
        ]),
      ),
    );
  }
}

class _CartRow extends ConsumerWidget {
  const _CartRow({required this.line});
  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(shopProductProvider(line.productId)).value;
    if (p == null) return const SizedBox(height: 64);
    final v = line.variantId == null ? null : p.variants.where((x) => x.id == line.variantId).firstOrNull;
    final thumb = p.gallery.isEmpty ? '' : p.gallery.first;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          width: 48,
          height: 48,
          color: context.surfaceMid,
          child: thumb.isEmpty ? null : Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
        ),
      ),
      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.callout(context.textPrimary)),
      subtitle: Text(
        '${formatMoney(p.price, p.currency)}${v == null ? '' : ' · ${v.name}'} · ×${line.quantity}',
        style: AppTypography.caption(context.textSecondary),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Remove',
          icon: Icon(Icons.delete_outline_rounded, color: context.textMuted),
          onPressed: () => ref.read(shop3dRepositoryProvider).removeFromCart(line.id),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
          onPressed: p.sellable
              ? () {
                  Navigator.pop(context);
                  context.push(checkoutRoute(p, v, custom: line.customization));
                }
              : null,
          child: Text(p.sellable ? 'Buy' : 'Sold out'),
        ),
      ]),
    );
  }
}
