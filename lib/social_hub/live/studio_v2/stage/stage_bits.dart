import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/live_studio_tokens.dart';

// Small shared stage widgets: LIVE pill, eq bars, nameplate, expand button,
// "In window" overlay. Sizes come from the prototype (SPEC §1.3, §3).

/// Pulsing white dot (`ss-pulse`: 1.4 s, opacity 1→.35, scale 1→.7).
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.size});
  final double size;
  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: LiveStudioMotion.pulse)..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
    final dot = SizedBox.square(
      dimension: widget.size,
      child: const DecoratedBox(
        decoration: BoxDecoration(color: LiveStudioWorld.textHigh, shape: BoxShape.circle),
      ),
    );
    return AnimatedBuilder(
      animation: curved,
      child: dot,
      builder: (_, child) => Opacity(
        opacity: 1 - 0.65 * curved.value,
        child: Transform.scale(scale: 1 - 0.3 * curved.value, child: child),
      ),
    );
  }
}

/// Red LIVE pill with the pulsing dot.
class LivePill extends StatelessWidget {
  const LivePill({
    super.key,
    this.fontSize = 10,
    this.lineHeight = 14,
    this.dot = 6,
    this.gap = 6,
    this.padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    this.weight = FontWeight.w600,
    this.letter = 0.06,
  });
  final double fontSize, lineHeight, dot, gap, letter;
  final EdgeInsets padding;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Live',
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: LiveStudioAccent.liveRed,
            borderRadius: BorderRadius.all(Radius.circular(9999)),
          ),
          child: Padding(
            padding: padding,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              PulseDot(size: dot),
              SizedBox(width: gap),
              Text('LIVE',
                  style: LiveStudioType.s(fontSize, weight, LiveStudioWorld.textHigh,
                      height: lineHeight, letter: letter)),
            ]),
          ),
        ),
      );
}

/// Audio bars in the speaker's accent (`ss-eq`: .9 s, 30%↔100%, stagger .25 s).
class EqBars extends StatefulWidget {
  const EqBars({super.key, required this.color, required this.height, required this.barWidth, required this.gap});
  final Color color;
  final double height, barWidth, gap;
  @override
  State<EqBars> createState() => _EqBarsState();
}

class _EqBarsState extends State<EqBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: LiveStudioMotion.eq)..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Bar height fraction at phase [t] (0..1) for bar [i].
  static double level(double t, int i) {
    final delay = i * LiveStudioMotion.eqStagger.inMilliseconds / LiveStudioMotion.eq.inMilliseconds;
    var p = (t - delay) % 1.0;
    if (p < 0) p += 1;
    final e = p < 0.5 ? Curves.easeInOut.transform(p * 2) : 1 - Curves.easeInOut.transform((p - 0.5) * 2);
    return 0.3 + 0.7 * e;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: widget.height,
        width: widget.barWidth * 3 + widget.gap * 2,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) SizedBox(width: widget.gap),
                Container(
                  width: widget.barWidth,
                  height: widget.height * level(_c.value, i),
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: const BorderRadius.all(Radius.circular(2)),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

/// Per-variant nameplate metrics.
class NameplateMetrics {
  const NameplateMetrics({
    required this.inset,
    required this.padding,
    required this.gap,
    required this.eqHeight,
    required this.eqBar,
    required this.eqGap,
    required this.font,
    required this.icon,
  });
  final double inset, gap, eqHeight, eqBar, eqGap, font, icon;
  final EdgeInsets padding;

  static const wide = NameplateMetrics(
      inset: 4, padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2), gap: 4,
      eqHeight: 9, eqBar: 2, eqGap: 1, font: 9, icon: 10);
  static const portrait = NameplateMetrics(
      inset: 4, padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2), gap: 4,
      eqHeight: 8, eqBar: 2, eqGap: 1, font: 8, icon: 9);
  static const phone = NameplateMetrics(
      inset: 7, padding: EdgeInsets.symmetric(horizontal: 9, vertical: 3), gap: 6,
      eqHeight: 12, eqBar: 3, eqGap: 2, font: 13, icon: 13);
}

/// Frosted nameplate (blur 8): eq bars while speaking, mic-off when muted,
/// then the name with ellipsis.
class Nameplate extends StatelessWidget {
  const Nameplate({
    super.key,
    required this.name,
    required this.accent,
    required this.speaking,
    required this.muted,
    required this.metrics,
  });
  final String name;
  final Color accent;
  final bool speaking, muted;
  final NameplateMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return Positioned(
      left: m.inset,
      right: m.inset,
      bottom: m.inset,
      child: Center(
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(9999)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: LiveStudioWorld.nameplate,
                border: Border.all(color: LiveStudioWorld.nameplateBorder, width: 1),
                borderRadius: const BorderRadius.all(Radius.circular(9999)),
              ),
              child: Padding(
                padding: m.padding,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (muted)
                    Icon(Icons.mic_off, size: m.icon, color: LiveStudioAccent.muteIcon)
                  else if (speaking)
                    EqBars(color: accent, height: m.eqHeight, barWidth: m.eqBar, gap: m.eqGap),
                  if (muted || speaking) SizedBox(width: m.gap),
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: LiveStudioType.s(m.font, FontWeight.w600, LiveStudioWorld.textHigh,
                          height: m.font * 1.25),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The dark expand (pop-out) button; blue on hover.
class StageExpandButton extends StatefulWidget {
  const StageExpandButton({
    super.key,
    required this.size,
    required this.iconSize,
    required this.radius,
    required this.label,
    required this.onTap,
  });
  final double size, iconSize, radius;
  final String label;
  final VoidCallback? onTap;

  @override
  State<StageExpandButton> createState() => _StageExpandButtonState();
}

class _StageExpandButtonState extends State<StageExpandButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: widget.label,
        excludeSemantics: true,
        onTap: widget.onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: _hover ? LiveStudioAccent.blue : LiveStudioWorld.expandButton,
                borderRadius: BorderRadius.all(Radius.circular(widget.radius)),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.open_in_full, size: widget.iconSize, color: LiveStudioWorld.textHigh),
            ),
          ),
        ),
      );
}

/// "In window" overlay shown on the source while its pop-out is open.
class InWindowOverlay extends StatelessWidget {
  const InWindowOverlay({super.key, required this.iconSize, required this.fontSize});
  final double iconSize, fontSize;

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: ColoredBox(
              color: LiveStudioWorld.inWindow,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.picture_in_picture_alt, size: iconSize, color: LiveStudioAccent.inWindowIcon),
                  SizedBox(height: math.max(3, fontSize / 3)),
                  Text('In window',
                      style: LiveStudioType.s(fontSize, FontWeight.w600, LiveStudioWorld.textHigh,
                          height: fontSize * 1.2)),
                ],
              ),
            ),
          ),
        ),
      );
}
