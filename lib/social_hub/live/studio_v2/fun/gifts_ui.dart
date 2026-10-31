// LIVE STUDIO v2 — gifting: the gift sheet (viewers / guests) and the
// on-stage gift animations everyone sees (sliding banners for every gift, a
// slow-motion centre reveal for big ones).

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../backend/live_studio/fun/studio_fun.dart';
import '../shell/shell_widgets.dart';
import '../theme/live_studio_tokens.dart';

IconData giftIcon(StudioGift g) => switch (g) {
      StudioGift.rose => Icons.local_florist_rounded,
      StudioGift.heart => Icons.favorite_rounded,
      StudioGift.star => Icons.star_rounded,
      StudioGift.crown => Icons.workspace_premium_rounded,
      StudioGift.rocket => Icons.rocket_launch_rounded,
      StudioGift.diamond => Icons.diamond_rounded,
    };

Color giftColor(StudioGift g) => switch (g) {
      StudioGift.rose || StudioGift.heart => LiveStudioAccent.pink,
      StudioGift.star => LiveStudioAccent.pinkLight,
      StudioGift.crown => LiveStudioAccent.blue,
      StudioGift.rocket => LiveStudioAccent.cyan,
      StudioGift.diamond => LiveStudioAccent.cyan,
    };

Future<void> showGiftSheet(BuildContext context, String streamId) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: LiveStudioAccent.clear,
    barrierColor: LiveStudioTokens.dimTint(0.3),
    sheetAnimationStyle: const AnimationStyle(duration: Duration(milliseconds: 480)),
    builder: (_) => _GiftSheet(streamId: streamId),
  );
}

class _GiftSheet extends ConsumerStatefulWidget {
  const _GiftSheet({required this.streamId});
  final String streamId;

  @override
  ConsumerState<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends ConsumerState<_GiftSheet> {
  StudioGift _gift = StudioGift.rose;
  int _qty = 1;
  bool _busy = false;
  String? _msg;

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    HapticFeedback.mediumImpact();
    try {
      await ref.read(studioGiftApiProvider).send(widget.streamId, _gift, qty: _qty);
      if (mounted) setState(() => _msg = 'Sent ${_gift.label}${_qty > 1 ? ' ×$_qty' : ''}!');
    } catch (e) {
      if (mounted) {
        setState(() => _msg = e is FirebaseFunctionsException && (e.message ?? '').isNotEmpty
            ? e.message
            : 'Could not send the gift. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coins = ref.watch(studioMyCoinsProvider).value ?? 0;
    final cost = _gift.coins * _qty;
    final enough = coins >= cost;
    return Container(
      decoration: const BoxDecoration(
        color: LiveStudioWorld.popHeader,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 38, height: 4, decoration: BoxDecoration(color: LiveStudioWorld.textDim, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Row(children: [
            Text('Send a gift', style: LiveStudioType.s(18, FontWeight.w800, LiveStudioWorld.textHigh)),
            const Spacer(),
            const Icon(Icons.monetization_on_rounded, size: 16, color: LiveStudioAccent.pink),
            const SizedBox(width: 4),
            Text('$coins coins', style: LiveStudioType.s(13, FontWeight.w700, LiveStudioWorld.textHigh)),
          ]),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final g in StudioGift.values)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _gift = g);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: _gift == g ? giftColor(g).withValues(alpha: 0.18) : LiveStudioWorld.surface2,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _gift == g ? giftColor(g) : LiveStudioWorld.nameplateBorder, width: _gift == g ? 2 : 1),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      AnimatedScale(
                        scale: _gift == g ? 1.2 : 1,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutBack,
                        child: Icon(giftIcon(g), size: 32, color: giftColor(g)),
                      ),
                      const SizedBox(height: 6),
                      Text(g.label, style: LiveStudioType.s(12, FontWeight.w700, LiveStudioWorld.textHigh)),
                      Text('${g.coins} coin${g.coins == 1 ? '' : 's'}',
                          style: LiveStudioType.s(11, FontWeight.w500, LiveStudioWorld.textMedium)),
                    ]),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            for (final q in const [1, 5, 10, 99])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => setState(() => _qty = q),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _qty == q ? LiveStudioAccent.blue : LiveStudioWorld.surface2,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('×$q', style: LiveStudioType.s(13, FontWeight.w800, LiveStudioAccent.white)),
                  ),
                ),
              ),
            const Spacer(),
            StudioPillButton(
              label: _busy ? 'Sending…' : 'Send · $cost',
              icon: Icons.card_giftcard_rounded,
              onTap: _busy || !enough ? null : _send,
              fill: enough ? LiveStudioAccent.pink : LiveStudioWorld.surface3,
              textColor: LiveStudioAccent.white,
              height: 44,
            ),
          ]),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: (_msg ?? (!enough ? 'Not enough coins for this gift.' : null)) == null
                ? const SizedBox(height: 8)
                : Padding(
                    key: ValueKey(_msg ?? 'nocoins'),
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_msg ?? 'Not enough coins for this gift.',
                        style: LiveStudioType.s(12.5, FontWeight.w600, LiveStudioWorld.textMedium)),
                  ),
          ),
        ]),
      ),
    );
  }
}

/// Everyone's view of gifts arriving: banners slide in on the left; gifts of
/// 50+ coins also get a slow-motion centre reveal.
class StudioGiftOverlay extends ConsumerStatefulWidget {
  const StudioGiftOverlay({super.key, required this.streamId, required this.phone});
  final String streamId;
  final bool phone;

  @override
  ConsumerState<StudioGiftOverlay> createState() => _StudioGiftOverlayState();
}

class _StudioGiftOverlayState extends ConsumerState<StudioGiftOverlay> {
  final List<StudioRecentGift> _banners = [];
  final Set<String> _seen = {};
  bool _primed = false;
  StudioRecentGift? _big;
  Timer? _bigTimer;
  final List<(String, int)> _bursts = [];

  @override
  void dispose() {
    _bigTimer?.cancel();
    super.dispose();
  }

  void _onFeed(List<StudioRecentGift> feed) {
    if (!_primed) {
      // Don't replay gifts sent before we joined.
      _seen.addAll(feed.map((g) => g.id));
      _primed = true;
      return;
    }
    for (final g in feed.reversed) {
      if (!_seen.add(g.id)) continue;
      setState(() {
        _banners.insert(0, g);
        if (_banners.length > 3) _banners.removeLast();
      });
      Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _banners.remove(g));
      });
      if (ref.read(studioViewPrefsProvider).showEffects) {
        final burst = (g.id, g.gift.coins * g.qty);
        setState(() => _bursts.add(burst));
        Timer(const Duration(milliseconds: 1700), () {
          if (mounted) setState(() => _bursts.remove(burst));
        });
      }
      if (g.gift.coins * g.qty >= 50 && ref.read(studioViewPrefsProvider).showEffects) {
        HapticFeedback.mediumImpact();
        setState(() => _big = g);
        _bigTimer?.cancel();
        _bigTimer = Timer(const Duration(milliseconds: 2800), () {
          if (mounted) setState(() => _big = null);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(studioGiftFeedProvider(widget.streamId), (_, next) {
      final v = next.value;
      if (v != null) _onFeed(v);
    });
    ref.watch(studioGiftFeedProvider(widget.streamId));
    return IgnorePointer(
      child: Stack(children: [
        for (final (id, coins) in _bursts) Positioned.fill(key: ValueKey('burst_$id'), child: _CoinBurst(seed: id.hashCode, coins: coins)),
        Positioned(
          left: 10,
          bottom: widget.phone ? 300 : 220,
          width: 240,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final g in _banners.reversed)
              TweenAnimationBuilder<double>(
                key: ValueKey(g.id),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutQuart,
                builder: (_, t, child) => Opacity(
                  opacity: t,
                  child: Transform.translate(offset: Offset(-40 * (1 - t), 0), child: child),
                ),
                child: _GiftBanner(gift: g),
              ),
          ]),
        ),
        Positioned.fill(
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 900),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: a, child: c)),
              child: _big == null
                  ? const SizedBox.shrink()
                  : Column(key: ValueKey(_big!.id), mainAxisSize: MainAxisSize.min, children: [
                      Icon(giftIcon(_big!.gift), size: 140, color: giftColor(_big!.gift)),
                      const SizedBox(height: 8),
                      Text('${_big!.name} sent ${_big!.gift.label}${_big!.qty > 1 ? ' ×${_big!.qty}' : ''}',
                          style: LiveStudioType.s(18, FontWeight.w900, LiveStudioWorld.textHigh)),
                    ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Coins that fly up from the bottom and spin out when a gift lands; bigger
/// gifts throw more coins (4–24).
class _CoinBurst extends StatefulWidget {
  const _CoinBurst({required this.seed, required this.coins});
  final int seed;
  final int coins;

  @override
  State<_CoinBurst> createState() => _CoinBurstState();
}

class _CoinBurstState extends State<_CoinBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..forward();
  late final List<(double, double, double, double)> _coins = () {
    final r = math.Random(widget.seed);
    final n = (4 + widget.coins ~/ 5).clamp(4, 24);
    // (start x 0..1, sideways drift, height 0..1, delay 0..0.35)
    return [for (var i = 0; i < n; i++) (0.25 + r.nextDouble() * 0.5, (r.nextDouble() - 0.5) * 0.5, 0.45 + r.nextDouble() * 0.4, r.nextDouble() * 0.35)];
  }();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, box) => AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Stack(children: [
            for (final (x, drift, height, delay) in _coins)
              Builder(builder: (_) {
                final t = ((_c.value - delay) / (1 - delay)).clamp(0.0, 1.0);
                if (t <= 0) return const SizedBox.shrink();
                final rise = Curves.easeOutCubic.transform(t);
                return Positioned(
                  left: box.maxWidth * (x + drift * rise) - 11,
                  top: box.maxHeight * (1 - height * rise),
                  child: Opacity(
                    opacity: t < 0.75 ? 1 : (1 - t) / 0.25,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(t * math.pi * 4),
                      child: const Icon(Icons.monetization_on_rounded, size: 22, color: LiveStudioAccent.pinkLight),
                    ),
                  ),
                );
              }),
          ]),
        ),
      );
}

class _GiftBanner extends StatelessWidget {
  const _GiftBanner({required this.gift});
  final StudioRecentGift gift;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [giftColor(gift.gift).withValues(alpha: 0.85), LiveStudioWorld.inWindow]),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          StudioAvatar(name: gift.name, url: gift.avatarUrl, size: 28, fill: LiveStudioWorld.surface3),
          const SizedBox(width: 8),
          Flexible(
            child: Text('${gift.name} sent ${gift.gift.label}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: LiveStudioType.s(12.5, FontWeight.w800, LiveStudioAccent.white)),
          ),
          const SizedBox(width: 6),
          Icon(giftIcon(gift.gift), size: 20, color: LiveStudioAccent.white),
          if (gift.qty > 1) ...[
            const SizedBox(width: 4),
            Text('×${gift.qty}', style: LiveStudioType.s(15, FontWeight.w900, LiveStudioAccent.white)),
          ],
        ]),
      );
}

/// Top gifters + this live's gift total (Live controls).
class StudioTopGifters extends ConsumerWidget {
  const StudioTopGifters({super.key, required this.streamId});
  final String streamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = ref.watch(studioTopGiftersProvider(streamId)).value ?? const [];
    if (top.isEmpty) {
      return Text('No gifts yet. Viewers send them with the gift button.',
          style: LiveStudioType.s(12, FontWeight.w500, LiveStudioWorld.textMedium));
    }
    return Column(children: [
      for (final (i, g) in top.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(
              width: 18,
              child: Text('${i + 1}', style: LiveStudioType.s(13, FontWeight.w900, i == 0 ? LiveStudioAccent.pink : LiveStudioWorld.textMedium)),
            ),
            StudioAvatar(name: g.name, url: g.avatarUrl, size: 26, fill: LiveStudioWorld.surface3),
            const SizedBox(width: 8),
            Expanded(child: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: LiveStudioType.s(13, FontWeight.w700, LiveStudioWorld.textHigh))),
            const Icon(Icons.monetization_on_rounded, size: 14, color: LiveStudioAccent.pink),
            const SizedBox(width: 3),
            Text('${g.coins}', style: LiveStudioType.s(13, FontWeight.w800, LiveStudioWorld.textHigh)),
          ]),
        ),
    ]);
  }
}
