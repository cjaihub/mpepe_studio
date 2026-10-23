// LIVE STUDIO v2 — table content chrome + mode art (workstream #5).
//
// Tag pill, LIVE pill, bottom title/sub bar with CTA, and the per-mode
// backgrounds from the prototype. Colors come only from live_studio_tokens.

import 'package:flutter/material.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import '../theme/live_studio_tokens.dart';
import 'table_metrics.dart';

/// rgba(8,8,10,a): the in-world near-black (`LiveStudioTokens.dark.base`).
Color _ink(double a) => LiveStudioTokens.dark.base.withValues(alpha: a);
Color _white(double a) => LiveStudioAccent.white.withValues(alpha: a);

// ─── Pills ───────────────────────────────────────────────────────────────────

class TableTagPill extends StatelessWidget {
  const TableTagPill(this.text, {super.key, required this.m});
  final String text;
  final TableMetrics m;

  @override
  Widget build(BuildContext context) => Container(
        padding: m.tagPadding,
        decoration: BoxDecoration(
          color: LiveStudioWorld.tagPill,
          borderRadius: BorderRadius.circular(m.tagRadius),
        ),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LiveStudioType.s(m.tagFont, FontWeight.w600, LiveStudioAccent.pink,
                height: m.tagLine, letter: 0.06)),
      );
}

class TableLivePill extends StatelessWidget {
  const TableLivePill({super.key, required this.m});
  final TableMetrics m;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Live',
        child: Container(
          padding: m.tagPadding,
          decoration: const BoxDecoration(
            color: LiveStudioAccent.liveRed,
            borderRadius: BorderRadius.all(Radius.circular(9999)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: m.liveDot,
              height: m.liveDot,
              decoration: const BoxDecoration(color: LiveStudioAccent.white, shape: BoxShape.circle),
            ),
            SizedBox(width: m.liveGap),
            Text('LIVE',
                style: LiveStudioType.s(m.tagFont, FontWeight.w600, LiveStudioWorld.textHigh,
                    height: m.tagLine, letter: 0.06)),
          ]),
        ),
      );
}

// ─── CTA ─────────────────────────────────────────────────────────────────────

class TableCta extends StatelessWidget {
  const TableCta({
    super.key,
    required this.label,
    required this.m,
    this.watching = false,
    this.onTap,
  });
  final String label;
  final TableMetrics m;

  /// "Watching" style: `#191920` + pink border.
  final bool watching;

  /// Null = disabled.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(m.ctaRadius),
            child: Container(
              height: m.ctaHeight,
              padding: EdgeInsets.symmetric(horizontal: m.ctaPadH),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: watching ? LiveStudioWorld.watchingCta : LiveStudioAccent.pink,
                border: Border.all(color: LiveStudioAccent.pink),
                borderRadius: BorderRadius.circular(m.ctaRadius),
              ),
              child: Text(label,
                  maxLines: 1,
                  softWrap: false,
                  style: LiveStudioType.s(m.ctaFont, FontWeight.w600, LiveStudioWorld.textHigh,
                      height: m.ctaLine)),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Chrome layout ───────────────────────────────────────────────────────────

/// Background + tag row + bottom bar. [background] fills the box.
class TableChrome extends StatelessWidget {
  const TableChrome({
    super.key,
    required this.m,
    required this.mode,
    required this.background,
    required this.title,
    this.sub = '',
    this.cta,
    this.center,
  });

  final TableMetrics m;
  final TableMode mode;
  final Widget background;
  final String title;
  final String sub;
  final Widget? cta;

  /// Optional centered control (host play/pause).
  final Widget? center;

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        background,
        if (center != null) Center(child: center),
        Positioned(
          left: m.headerInset,
          top: m.headerInset,
          right: m.headerRight,
          child: Row(children: [
            Flexible(child: TableTagPill(TableModeCopy.tag(mode), m: m)),
            const Spacer(),
            if (mode.isStream) TableLivePill(m: m),
          ]),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: m.bottomPadding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [_ink(0.95), _ink(0.95), _ink(0)],
                stops: const [0, 0.4, 1],
              ),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LiveStudioType.s(m.titleFont, FontWeight.w600, LiveStudioWorld.textHigh,
                            height: m.titleLine)),
                    if (sub.isNotEmpty)
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LiveStudioType.s(m.subFont, FontWeight.w400, LiveStudioWorld.textMedium,
                              height: m.subLine)),
                  ],
                ),
              ),
              if (cta != null) ...[SizedBox(width: m.bottomGap), cta!],
            ]),
          ),
        ),
      ]);
}

// ─── Mode art (prototype backgrounds) ────────────────────────────────────────

/// Goods: radial(70% 80% at 50% 40%, #1e2a3a, #121218 60%, #0b0b0f).
class GoodsArt extends StatelessWidget {
  const GoodsArt({super.key});
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.2),
            radius: 0.85,
            colors: [
              Color.lerp(LiveStudioWorld.surface2, LiveStudioAccent.blue, 0.12)!,
              LiveStudioWorld.surface2,
              LiveStudioWorld.screen,
            ],
            stops: const [0, 0.6, 1],
          ),
        ),
      );
}

/// The cube tile (product image or `inventory_2` fallback).
class GoodsCube extends StatelessWidget {
  const GoodsCube({super.key, required this.m, this.imageUrl = ''});
  final TableMetrics m;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(Icons.inventory_2, size: m.cubeIcon, color: LiveStudioAccent.cyan);
    return Container(
      width: m.cubeSize,
      height: m.cubeSize,
      decoration: BoxDecoration(
        color: LiveStudioWorld.surface2,
        borderRadius: BorderRadius.circular(m.cubeRadius),
        border: Border.all(color: LiveStudioAccent.cyanA(0.35)),
        boxShadow: [BoxShadow(color: LiveStudioAccent.cyanA(0.25), blurRadius: 24)],
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: imageUrl.isEmpty
          ? icon
          : Image.network(
              imageUrl,
              width: m.cubeSize,
              height: m.cubeSize,
              fit: BoxFit.cover,
              semanticLabel: 'Product image',
              errorBuilder: (_, _, _) => icon,
            ),
    );
  }
}

/// Screen: linear(160deg, #13283a, #0b0b0f).
class ScreenArt extends StatelessWidget {
  const ScreenArt({super.key});
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: const Alignment(-0.35, -1),
            end: const Alignment(0.35, 1),
            colors: [Color.lerp(LiveStudioWorld.screen, LiveStudioAccent.blue, 0.14)!, LiveStudioWorld.screen],
          ),
        ),
      );
}

/// The prototype's shared-window illustration (decorative).
class ScreenWindowArt extends StatelessWidget {
  const ScreenWindowArt({super.key, required this.m});
  final TableMetrics m;

  @override
  Widget build(BuildContext context) {
    final s = m.scale;
    Widget bar(double h, {double? w, Color? c}) => Container(
          height: h * s,
          width: w,
          decoration: BoxDecoration(color: c ?? _white(0.1), borderRadius: BorderRadius.circular(3 * s)),
        );
    Widget dot(Color c) => Container(
        width: m.windowDot, height: m.windowDot, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
    return Stack(fit: StackFit.expand, children: [
      const ScreenArt(),
      Padding(
        padding: m.screenWindow,
        child: Container(
          decoration: BoxDecoration(
            color: LiveStudioWorld.surface2,
            borderRadius: BorderRadius.circular(6 * s),
            border: Border.all(color: _white(0.1)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: m.windowBar,
              color: LiveStudioWorld.surface3,
              padding: EdgeInsets.only(left: (m.phone ? 6 : 7) * s),
              child: Row(children: [
                dot(LiveStudioAccent.pink),
                SizedBox(width: 4 * s),
                dot(LiveStudioWorld.textDim),
                SizedBox(width: 4 * s),
                dot(LiveStudioWorld.textDim),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all((m.phone ? 8 : 10) * s),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: (m.phone ? 40 : 52) * s,
                    height: (m.phone ? 56 : 52) * s,
                    decoration:
                        BoxDecoration(color: _white(0.06), borderRadius: BorderRadius.circular(4 * s)),
                  ),
                  SizedBox(width: (m.phone ? 8 : 10) * s),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        bar(m.phone ? 8 : 9, w: c.maxWidth * 0.7, c: LiveStudioAccent.cyanA(0.35)),
                        SizedBox(height: (m.phone ? 6 : 7) * s),
                        bar(m.phone ? 6 : 7),
                        SizedBox(height: (m.phone ? 6 : 7) * s),
                        bar(m.phone ? 6 : 7, w: c.maxWidth * 0.85),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

/// Match: pitch (viewBox 236×133, stretched).
class MatchArt extends StatelessWidget {
  const MatchArt({super.key});
  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _PitchPainter(), child: SizedBox.expand());
}

class _PitchPainter extends CustomPainter {
  const _PitchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 236, sy = size.height / 133;
    canvas.drawRect(Offset.zero & size,
        Paint()..color = Color.lerp(LiveStudioWorld.screen, LiveStudioAccent.teal, 0.16)!);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * ((sx + sy) / 2)
      ..color = _white(0.32);
    Rect r(double x, double y, double w, double h) => Rect.fromLTWH(x * sx, y * sy, w * sx, h * sy);
    canvas.drawRect(r(10, 8, 216, 117), line);
    canvas.drawLine(Offset(118 * sx, 8 * sy), Offset(118 * sx, 125 * sy), line);
    canvas.drawOval(Rect.fromCenter(center: Offset(118 * sx, 66.5 * sy), width: 34 * sx, height: 34 * sy), line);
    canvas.drawRect(r(10, 38, 28, 57), line);
    canvas.drawRect(r(198, 38, 28, 57), line);
    canvas.drawRect(r(10, 53, 10, 27), line);
    canvas.drawRect(r(216, 53, 10, 27), line);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(138 * sx, 58 * sy), width: 6 * sx, height: 6 * sy),
        Paint()..color = LiveStudioAccent.white);
  }

  @override
  bool shouldRepaint(_PitchPainter oldDelegate) => false;
}

/// Movie: radial(90% 80% at 60% 35%, #3a1630, #150f1c 55%, #08080A) + letterbox.
class MovieArt extends StatelessWidget {
  const MovieArt({super.key, required this.m, this.showPlay = true});
  final TableMetrics m;
  final bool showPlay;

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.2, -0.3),
              radius: 0.95,
              colors: LiveStudioWorld.hostBg.colors,
              stops: LiveStudioWorld.hostBg.stops,
            ),
          ),
        ),
        Positioned(left: 0, right: 0, top: 0, height: m.letterbox, child: ColoredBox(color: _ink(1))),
        if (showPlay)
          Positioned(
            left: 0,
            right: 0,
            top: m.playTop,
            child: Center(child: PlayDisc(m: m)),
          ),
      ]);
}

/// The translucent play circle (movie art; host play/pause control).
class PlayDisc extends StatelessWidget {
  const PlayDisc({super.key, required this.m, this.icon = Icons.play_arrow});
  final TableMetrics m;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: m.playSize,
        height: m.playSize,
        decoration: BoxDecoration(
          color: _white(0.12),
          shape: BoxShape.circle,
          border: Border.all(color: _white(0.35)),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: m.playIcon * 1.25, color: LiveStudioAccent.white),
      );
}

/// Empty / waiting state: icon + one line, centered above the bottom bar.
class TableEmptyArt extends StatelessWidget {
  const TableEmptyArt({super.key, required this.m, required this.icon, required this.background});
  final TableMetrics m;
  final IconData icon;
  final Widget background;

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        background,
        Align(
          alignment: const Alignment(0, -0.25),
          child: Icon(icon, size: m.emptyIcon, color: LiveStudioWorld.textDim),
        ),
      ]);
}

/// Network poster over [fallback]; fallback shows on error / empty URL.
class TablePoster extends StatelessWidget {
  const TablePoster({super.key, required this.url, required this.fallback});
  final String url;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => url.isEmpty
      ? fallback
      : Stack(fit: StackFit.expand, children: [
          fallback,
          Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
        ]);
}
