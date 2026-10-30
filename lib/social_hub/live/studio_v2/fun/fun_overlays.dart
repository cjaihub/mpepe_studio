// LIVE STUDIO v2 — entertainment overlays on the stage: countdown timer,
// poll card (vote + animated results), spotlight banner, celebration burst
// and raffle winner reveal. Everyone sees the same server state
// (`studio/fun`); animations are deliberately slow and eased so the stage
// feels calm, never jumpy.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../backend/live_studio/fun/studio_fun.dart';
import '../shell/shell_widgets.dart';
import '../theme/live_studio_tokens.dart';

const _slow = Duration(milliseconds: 650);
const _curve = Curves.easeOutQuart;

class StudioFunOverlay extends ConsumerStatefulWidget {
  const StudioFunOverlay({super.key, required this.streamId, required this.canManage, required this.phone});
  final String streamId;
  final bool canManage;
  final bool phone;

  @override
  ConsumerState<StudioFunOverlay> createState() => _StudioFunOverlayState();
}

class _StudioFunOverlayState extends ConsumerState<StudioFunOverlay> with TickerProviderStateMixin {
  Timer? _tick;
  int _now = DateTime.now().millisecondsSinceEpoch;
  int? _myVote;
  String? _votedPoll;
  int _seenCelebrate = 0;
  int _seenRaffle = 0;
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
  String _burstKind = 'confetti';
  bool _showWinner = false;
  Timer? _winnerTimer;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _now = DateTime.now().millisecondsSinceEpoch);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _winnerTimer?.cancel();
    _burst.dispose();
    super.dispose();
  }

  void _react(StudioFunState fun) {
    // Only animate fresh events (not ones that happened before we joined).
    if (fun.celebrateKind != null && fun.celebrateAtMs > _seenCelebrate) {
      final fresh = _now - fun.celebrateAtMs < 6000;
      _seenCelebrate = fun.celebrateAtMs;
      if (fresh && ref.read(studioViewPrefsProvider).showEffects) {
        _burstKind = fun.celebrateKind!;
        HapticFeedback.lightImpact();
        _burst.forward(from: 0);
      }
    }
    if (fun.raffleWinnerName != null && fun.raffleAtMs > _seenRaffle) {
      final fresh = _now - fun.raffleAtMs < 10000;
      _seenRaffle = fun.raffleAtMs;
      if (fresh) {
        setState(() => _showWinner = true);
        _winnerTimer?.cancel();
        _winnerTimer = Timer(const Duration(seconds: 7), () {
          if (mounted) setState(() => _showWinner = false);
        });
      }
    }
  }

  Future<void> _vote(StudioPoll p, int i) async {
    HapticFeedback.selectionClick();
    setState(() {
      _myVote = i;
      _votedPoll = p.id;
    });
    try {
      await ref.read(studioFunApiProvider).vote(widget.streamId, i);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Vote not counted. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(studioFunProvider(widget.streamId), (_, next) {
      final v = next.value;
      if (v != null) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _react(v) : null);
    });
    final fun = ref.watch(studioFunProvider(widget.streamId)).value ?? const StudioFunState();
    final prefs = ref.watch(studioViewPrefsProvider);
    final poll = fun.poll;
    final showPoll = poll != null && (poll.acceptingAt(_now) || _now - poll.endsAtMs < 20000);
    final timerLeft = fun.timerEndsAtMs == null ? null : fun.timerEndsAtMs! - _now;
    final showTimer = timerLeft != null && timerLeft > -4000;
    if (_votedPoll != poll?.id) _myVote = null;

    return Stack(children: [
      // Countdown timer — top center.
      Positioned(
        top: widget.phone ? 100 : 80,
        left: 0,
        right: 0,
        child: Center(
          child: AnimatedSwitcher(
            duration: _slow,
            switchInCurve: _curve,
            transitionBuilder: _slideFade,
            child: showTimer
                ? _TimerPill(key: ValueKey(fun.timerEndsAtMs), label: fun.timerLabel ?? '', leftMs: timerLeft)
                : const SizedBox.shrink(),
          ),
        ),
      ),
      // Poll — left side, mid stage.
      Positioned(
        left: 10,
        top: widget.phone ? 150 : 130,
        width: widget.phone ? 240 : 300,
        child: AnimatedSwitcher(
          duration: _slow,
          switchInCurve: _curve,
          transitionBuilder: _slideFade,
          child: showPoll
              ? _PollCard(
                  key: ValueKey(poll.id),
                  poll: poll,
                  nowMs: _now,
                  myVote: _myVote,
                  onVote: poll.acceptingAt(_now) ? (i) => _vote(poll, i) : null,
                )
              : const SizedBox.shrink(),
        ),
      ),
      // Spotlight — pinned message above the comments.
      Positioned(
        left: 12,
        right: 12,
        bottom: widget.phone ? 230 : 170,
        child: AnimatedSwitcher(
          duration: _slow,
          switchInCurve: _curve,
          transitionBuilder: _slideFade,
          child: fun.spotlightText == null || fun.spotlightText!.isEmpty
              ? const SizedBox.shrink()
              : _Spotlight(key: ValueKey(fun.spotlightAtMs), fun: fun),
        ),
      ),
      // Celebration burst.
      if (prefs.showEffects)
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _burst,
              builder: (_, _) => _burst.isAnimating
                  ? CustomPaint(painter: _BurstPainter(_burst.value, _burstKind))
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      // Raffle winner reveal.
      Positioned.fill(
        child: IgnorePointer(
          ignoring: !_showWinner,
          child: AnimatedOpacity(
            opacity: _showWinner ? 1 : 0,
            duration: _slow,
            curve: _curve,
            child: AnimatedScale(
              scale: _showWinner ? 1 : 0.85,
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutBack,
              child: Center(child: _WinnerCard(fun: fun, onClose: () => setState(() => _showWinner = false))),
            ),
          ),
        ),
      ),
    ]);
  }

  static Widget _slideFade(Widget child, Animation<double> a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
          child: child,
        ),
      );
}

BoxDecoration _glass({Color? border}) => BoxDecoration(
      color: LiveStudioWorld.inWindow,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: border ?? LiveStudioWorld.nameplateBorder),
      boxShadow: [BoxShadow(color: LiveStudioAccent.blueA(0.18), blurRadius: 24, offset: const Offset(0, 8))],
    );

class _TimerPill extends StatelessWidget {
  const _TimerPill({super.key, required this.label, required this.leftMs});
  final String label;
  final int leftMs;

  @override
  Widget build(BuildContext context) {
    final s = (leftMs / 1000).ceil().clamp(0, 99999);
    final done = s == 0;
    final mm = (s ~/ 60).toString().padLeft(2, '0'), ss = (s % 60).toString().padLeft(2, '0');
    return AnimatedContainer(
      duration: _slow,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: _glass(border: done ? LiveStudioAccent.pink : (s <= 10 ? LiveStudioAccent.pinkA(0.7) : null)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(done ? Icons.alarm_on_rounded : Icons.timer_outlined, size: 16, color: LiveStudioAccent.pink),
        const SizedBox(width: 8),
        if (label.isNotEmpty) ...[
          Text(label, style: LiveStudioType.s(12, FontWeight.w600, LiveStudioWorld.textMedium)),
          const SizedBox(width: 8),
        ],
        Text(done ? "Time's up!" : '$mm:$ss',
            style: LiveStudioType.s(15, FontWeight.w800, LiveStudioWorld.textHigh).copyWith(fontFeatures: LiveStudioType.tabular)),
      ]),
    );
  }
}

class _PollCard extends StatelessWidget {
  const _PollCard({super.key, required this.poll, required this.nowMs, required this.myVote, required this.onVote});
  final StudioPoll poll;
  final int nowMs;
  final int? myVote;
  final ValueChanged<int>? onVote;

  @override
  Widget build(BuildContext context) {
    final total = poll.total;
    final open = onVote != null;
    final reveal = !open || myVote != null;
    final left = ((poll.endsAtMs - nowMs) / 1000).ceil();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: _glass(border: LiveStudioAccent.blueA(0.6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Icon(Icons.poll_rounded, size: 16, color: LiveStudioAccent.blue),
          const SizedBox(width: 6),
          Text(open ? 'POLL · ${left}s' : 'POLL RESULTS', style: LiveStudioType.s(11, FontWeight.w800, LiveStudioWorld.textMedium)),
          const Spacer(),
          Text('$total vote${total == 1 ? '' : 's'}', style: LiveStudioType.s(11, FontWeight.w600, LiveStudioWorld.textMedium)),
        ]),
        const SizedBox(height: 6),
        Text(poll.question, style: LiveStudioType.s(14, FontWeight.w800, LiveStudioWorld.textHigh)),
        const SizedBox(height: 8),
        for (final (i, o) in poll.options.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _PollOption(
              label: o,
              fraction: total == 0 ? 0 : poll.counts[i] / total,
              reveal: reveal,
              mine: myVote == i,
              onTap: open ? () => onVote!(i) : null,
            ),
          ),
      ]),
    );
  }
}

class _PollOption extends StatelessWidget {
  const _PollOption({required this.label, required this.fraction, required this.reveal, required this.mine, this.onTap});
  final String label;
  final double fraction;
  final bool reveal;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color: LiveStudioWorld.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: mine ? LiveStudioAccent.pink : LiveStudioWorld.nameplateBorder, width: mine ? 1.5 : 1),
          ),
          child: Stack(children: [
            // Result bar grows slowly (slow-motion fill).
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: reveal ? fraction : 0),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => FractionallySizedBox(
                widthFactor: v.clamp(0, 1),
                child: Container(color: mine ? LiveStudioAccent.pinkA(0.45) : LiveStudioAccent.blueA(0.4)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: [
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LiveStudioType.s(13, FontWeight.w700, LiveStudioWorld.textHigh)),
                ),
                if (reveal) Text('${(fraction * 100).round()}%', style: LiveStudioType.s(12, FontWeight.w800, LiveStudioWorld.textHigh)),
                if (mine) ...[const SizedBox(width: 4), const Icon(Icons.check_circle_rounded, size: 14, color: LiveStudioAccent.pink)],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Spotlight extends StatelessWidget {
  const _Spotlight({super.key, required this.fun});
  final StudioFunState fun;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: _glass(border: LiveStudioAccent.pinkA(0.8)),
        child: Row(children: [
          StudioAvatar(name: fun.spotlightName, url: fun.spotlightAvatarUrl, size: 30, fill: LiveStudioWorld.surface3),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Icon(Icons.push_pin_rounded, size: 12, color: LiveStudioAccent.pink),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(fun.spotlightName.isEmpty ? 'Spotlight' : fun.spotlightName,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: LiveStudioType.s(11, FontWeight.w800, LiveStudioAccent.pinkLight)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(fun.spotlightText ?? '',
                  maxLines: 3, overflow: TextOverflow.ellipsis, style: LiveStudioType.s(14, FontWeight.w700, LiveStudioWorld.textHigh)),
            ]),
          ),
        ]),
      );
}

class _WinnerCard extends StatelessWidget {
  const _WinnerCard({required this.fun, required this.onClose});
  final StudioFunState fun;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onClose,
        child: Container(
          width: 260,
          padding: const EdgeInsets.all(20),
          decoration: _glass(border: LiveStudioAccent.pink),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.emoji_events_rounded, size: 34, color: LiveStudioAccent.pink),
            const SizedBox(height: 8),
            Text('RAFFLE WINNER', style: LiveStudioType.s(11, FontWeight.w900, LiveStudioWorld.textMedium)),
            const SizedBox(height: 12),
            StudioAvatar(
              name: fun.raffleWinnerName ?? '',
              url: fun.raffleWinnerAvatarUrl,
              size: 64,
              fill: LiveStudioWorld.surface3,
              ring: LiveStudioAccent.pink,
              ringWidth: 3,
            ),
            const SizedBox(height: 10),
            Text(fun.raffleWinnerName ?? '',
                textAlign: TextAlign.center, style: LiveStudioType.s(18, FontWeight.w800, LiveStudioWorld.textHigh)),
            const SizedBox(height: 4),
            Text('picked from ${fun.raffleEntrants} commenter${fun.raffleEntrants == 1 ? '' : 's'}',
                style: LiveStudioType.s(12, FontWeight.w500, LiveStudioWorld.textMedium)),
          ]),
        ),
      );
}

/// Particles drifting up (hearts) or falling (confetti) or bursting (fireworks).
class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t, this.kind);
  final double t;
  final String kind;

  static const _colors = [LiveStudioAccent.pink, LiveStudioAccent.blue, LiveStudioAccent.cyan, LiveStudioAccent.pinkLight, LiveStudioAccent.white];

  @override
  void paint(Canvas canvas, Size size) {
    final fade = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25);
    for (var i = 0; i < 48; i++) {
      final r = math.Random(i * 7919);
      final color = _colors[i % _colors.length].withValues(alpha: 0.9 * fade);
      final paint = Paint()..color = color;
      final x0 = r.nextDouble() * size.width;
      final speed = 0.6 + r.nextDouble() * 0.6;
      final sway = math.sin((t * 6 + i) * 1.3) * 18;
      final ease = Curves.easeOutCubic.transform(t);
      switch (kind) {
        case 'hearts':
          final y = size.height * (1.05 - ease * speed);
          _heart(canvas, Offset(x0 + sway, y), 7 + r.nextDouble() * 8, paint);
        case 'fireworks':
          final c = Offset(size.width * (0.25 + 0.5 * ((i % 3) / 2)), size.height * (0.3 + 0.1 * (i % 2)));
          final a = r.nextDouble() * math.pi * 2;
          final d = ease * (80 + r.nextDouble() * 90);
          canvas.drawCircle(c + Offset(math.cos(a) * d, math.sin(a) * d + t * t * 60), 2.5 + r.nextDouble() * 2, paint);
        default:
          final y = -20 + size.height * ease * speed * 1.1;
          canvas.save();
          canvas.translate(x0 + sway, y);
          canvas.rotate(t * 8 + i);
          canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-4, -2, 8, 4), const Radius.circular(1)), paint);
          canvas.restore();
      }
    }
  }

  void _heart(Canvas c, Offset o, double s, Paint p) {
    final path = Path()
      ..moveTo(o.dx, o.dy + s * 0.35)
      ..cubicTo(o.dx - s, o.dy - s * 0.4, o.dx - s * 0.4, o.dy - s, o.dx, o.dy - s * 0.35)
      ..cubicTo(o.dx + s * 0.4, o.dy - s, o.dx + s, o.dy - s * 0.4, o.dx, o.dy + s * 0.35);
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t || old.kind != kind;
}

/// Double-tap anywhere on [child] to send a love: a heart blooms where you
/// tapped and floats up slowly. Uses a raw Listener, so single taps on the
/// stage (pop-outs, swaps) are never delayed or swallowed.
class DoubleTapLove extends StatefulWidget {
  const DoubleTapLove({super.key, required this.child, required this.onLove});
  final Widget child;
  final VoidCallback onLove;

  @override
  State<DoubleTapLove> createState() => _DoubleTapLoveState();
}

class _DoubleTapLoveState extends State<DoubleTapLove> {
  int _lastUpMs = 0;
  Offset _lastUpAt = Offset.zero;
  Offset _downAt = Offset.zero;
  final List<(int, Offset, double)> _hearts = [];
  int _seq = 0;
  final _rng = math.Random();

  void _onUp(PointerUpEvent e) {
    if ((e.localPosition - _downAt).distance > 20) return; // a swipe, not a tap
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastUpMs < 320 && (e.localPosition - _lastUpAt).distance < 60) {
      _lastUpMs = 0;
      HapticFeedback.lightImpact();
      widget.onLove();
      final id = ++_seq;
      setState(() => _hearts.add((id, e.localPosition, (_rng.nextDouble() - 0.5) * 0.5)));
      Timer(const Duration(milliseconds: 1300), () {
        if (mounted) setState(() => _hearts.removeWhere((h) => h.$1 == id));
      });
    } else {
      _lastUpMs = now;
      _lastUpAt = e.localPosition;
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) => _downAt = e.localPosition,
        onPointerUp: _onUp,
        child: Stack(fit: StackFit.expand, children: [
          widget.child,
          for (final h in _hearts)
            Positioned(
              left: h.$2.dx - 48,
              top: h.$2.dy - 48,
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(h.$1),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 1250),
                  builder: (_, t, _) {
                    final pop = Curves.elasticOut.transform((t * 2.2).clamp(0, 1));
                    final fade = t < 0.6 ? 1.0 : 1 - (t - 0.6) / 0.4;
                    return Opacity(
                      opacity: fade.clamp(0, 1),
                      child: Transform.translate(
                        offset: Offset(0, -60 * Curves.easeOutCubic.transform(t)),
                        child: Transform.rotate(
                          angle: h.$3,
                          child: Transform.scale(
                            scale: 0.4 + 0.8 * pop,
                            child: const Icon(Icons.favorite_rounded, size: 96, color: LiveStudioAccent.pink),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ]),
      );
}
