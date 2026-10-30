// LIVE STUDIO v2 — Game Live camera bubble.
//
// The host camera as a draggable picture-in-picture circle. Drag it anywhere;
// on release it snaps to the nearest side (left/right) inside [insets]. Tap
// hides it to a small tab on that side; tap the tab to show it again. The
// visibility is local to each viewer.

import 'package:flutter/material.dart';

import '../theme/live_studio_tokens.dart';

enum GamingPipSide { left, right }

/// Pure snapping rule (unit-tested): the bubble's top-left after a drag ends.
///
/// x snaps to the nearest side, y is clamped between the top and bottom
/// insets. [area] is the bubble's parent size.
Offset snapPipOffset({
  required Offset dropped,
  required Size area,
  required double diameter,
  required EdgeInsets insets,
}) {
  final minX = insets.left;
  final maxX = (area.width - insets.right - diameter).clamp(minX, double.infinity).toDouble();
  final minY = insets.top;
  final maxY = (area.height - insets.bottom - diameter).clamp(minY, double.infinity).toDouble();
  final centerX = dropped.dx + diameter / 2;
  final x = centerX < area.width / 2 ? minX : maxX;
  final y = dropped.dy.clamp(minY, maxY).toDouble();
  return Offset(x, y);
}

class GamingPipBubble extends StatefulWidget {
  const GamingPipBubble({
    super.key,
    required this.child,
    this.diameter = 96,
    this.insets = const EdgeInsets.fromLTRB(12, 96, 12, 96),
    this.ringColor = LiveStudioAccent.pink,
    this.initialSide = GamingPipSide.right,
    this.label = 'Host camera',
  });

  /// Camera (or avatar) content, clipped to the circle.
  final Widget child;
  final double diameter;

  /// Keep-out margins (header, bottom bar).
  final EdgeInsets insets;
  final Color ringColor;
  final GamingPipSide initialSide;
  final String label;

  static const Key bubbleKey = ValueKey('gaming-pip-bubble');
  static const Key tabKey = ValueKey('gaming-pip-tab');

  @override
  State<GamingPipBubble> createState() => _GamingPipBubbleState();
}

class _GamingPipBubbleState extends State<GamingPipBubble> {
  Offset? _pos;
  bool _dragging = false;
  bool _hidden = false;

  static const double _tabWidth = 28;
  static const double _tabHeight = 56;

  GamingPipSide _sideOf(Offset p, Size area) =>
      p.dx + widget.diameter / 2 < area.width / 2 ? GamingPipSide.left : GamingPipSide.right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final area = box.biggest;
      final d = widget.diameter;
      final initial = snapPipOffset(
        dropped: Offset(widget.initialSide == GamingPipSide.left ? 0 : area.width, widget.insets.top),
        area: area,
        diameter: d,
        insets: widget.insets,
      );
      final pos = _pos ?? initial;
      final side = _sideOf(pos, area);

      if (_hidden) {
        final left = side == GamingPipSide.left;
        return Stack(children: [
          Positioned(
            left: left ? 0 : null,
            right: left ? null : 0,
            top: pos.dy + (d - _tabHeight) / 2,
            child: Semantics(
              button: true,
              label: 'Show ${widget.label.toLowerCase()}',
              excludeSemantics: true,
              child: GestureDetector(
                key: GamingPipBubble.tabKey,
                onTap: () => setState(() => _hidden = false),
                child: Container(
                  width: _tabWidth,
                  height: _tabHeight,
                  decoration: BoxDecoration(
                    color: LiveStudioWorld.tagPill,
                    border: Border.all(color: widget.ringColor, width: 2),
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(left ? 0 : 14),
                      right: Radius.circular(left ? 14 : 0),
                    ),
                  ),
                  child: const Icon(Icons.videocam, size: 16, color: LiveStudioWorld.textHigh),
                ),
              ),
            ),
          ),
        ]);
      }

      return Stack(children: [
        AnimatedPositioned(
          duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          left: pos.dx,
          top: pos.dy,
          width: d,
          height: d,
          child: Semantics(
            button: true,
            label: '${widget.label}. Tap to hide, drag to move.',
            excludeSemantics: true,
            child: GestureDetector(
              key: GamingPipBubble.bubbleKey,
              onTap: () => setState(() => _hidden = true),
              onPanStart: (_) => setState(() {
                _dragging = true;
                _pos = pos;
              }),
              onPanUpdate: (e) => setState(() => _pos = (_pos ?? pos) + e.delta),
              onPanEnd: (_) => setState(() {
                _dragging = false;
                _pos = snapPipOffset(dropped: _pos ?? pos, area: area, diameter: d, insets: widget.insets);
              }),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: LiveStudioWorld.screen,
                  border: Border.all(color: widget.ringColor, width: 3),
                  boxShadow: [BoxShadow(color: widget.ringColor.withValues(alpha: 0.4), blurRadius: 16)],
                ),
                child: ClipOval(child: widget.child),
              ),
            ),
          ),
        ),
      ]);
    });
  }
}
