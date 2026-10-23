import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../geometry/studio_geometry.dart';
import '../theme/live_studio_tokens.dart';
import 'popout_controller.dart';
import 'stage_bits.dart';

/// Builds a pop-out body for [target] at [size] (artboard px).
typedef PopoutContentBuilder = Widget Function(BuildContext context, PopoutTarget target, Size size);

/// The floating window layer (UI space, artboard px). Place it inside the
/// artboard transform, above chrome. Renders nothing when closed.
///
/// Drag by the header (not on its buttons, not in full screen); resize by the
/// 28px grip with the JSON min size, clamped to [bounds]; double-tap the
/// header or press the button to toggle full screen. Content is built lazily:
/// only while open, and only after the window's first frame.
class StudioPopoutLayer extends ConsumerWidget {
  const StudioPopoutLayer({
    super.key,
    required this.geometry,
    required this.bounds,
    required this.frameWidth,
    required this.frameColor,
    required this.titleFor,
    required this.contentBuilder,
  });

  final OrientationGeometry geometry;

  /// Clamp area in artboard px (the viewport mapped into the artboard). The
  /// layer's own box is `bounds.size`, with its origin at `bounds.topLeft`.
  final Rect bounds;
  final double frameWidth;
  final Color frameColor;
  final String Function(PopoutTarget target) titleFor;
  final PopoutContentBuilder contentBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(studioPopoutProvider);
    if (st == null) return const SizedBox.shrink();
    final c = ref.read(studioPopoutProvider.notifier);
    // Local coordinates: artboard px relative to bounds.topLeft.
    final rect = (st.fullScreen ? bounds : st.rect).shift(-bounds.topLeft);
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fromRect(
        rect: rect,
        child: PopoutWindow(
          key: ValueKey(st.target),
          title: titleFor(st.target),
          fullScreen: st.fullScreen,
          frameWidth: frameWidth,
          frameColor: frameColor,
          onClose: c.close,
          onToggleFullScreen: c.toggleFullScreen,
          onDrag: (d) => c.moveBy(d, bounds),
          onResize: (d) => c.resizeBy(d, geometry.popoutMin, bounds),
          child: LayoutBuilder(
            builder: (ctx, box) => contentBuilder(ctx, st.target, box.biggest),
          ),
        ),
      ),
    ]);
  }
}

/// The window chrome itself (stateless about position; see the controller).
class PopoutWindow extends StatelessWidget {
  const PopoutWindow({
    super.key,
    required this.title,
    required this.fullScreen,
    required this.frameWidth,
    required this.frameColor,
    required this.child,
    this.onClose,
    this.onToggleFullScreen,
    this.onDrag,
    this.onResize,
  });

  final String title;
  final bool fullScreen;
  final double frameWidth;
  final Color frameColor;
  final Widget child;
  final VoidCallback? onClose;
  final VoidCallback? onToggleFullScreen;
  final ValueChanged<Offset>? onDrag;
  final ValueChanged<Offset>? onResize;

  @override
  Widget build(BuildContext context) {
    final radius = fullScreen ? 20.0 : 14.0;
    final header = SizedBox(
      height: 44,
      child: ColoredBox(
        color: LiveStudioWorld.popHeader,
        child: Row(children: [
          Expanded(
            // Drag handle: everything except the buttons.
            child: GestureDetector(
              key: const ValueKey('popout-drag'),
              behavior: HitTestBehavior.opaque,
              onPanUpdate: fullScreen || onDrag == null ? null : (d) => onDrag!(d.delta),
              onDoubleTap: onToggleFullScreen,
              child: MouseRegion(
                cursor: fullScreen ? SystemMouseCursors.basic : SystemMouseCursors.move,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(children: [
                    const Icon(Icons.drag_indicator, size: 16, color: LiveStudioAccent.inWindowIcon),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LiveStudioType.s(13, FontWeight.w600, LiveStudioWorld.textHigh, height: 18)),
                    ),
                    const SizedBox(width: 8),
                    const LivePill(
                      weight: FontWeight.w700,
                      letter: 0.04,
                      gap: 5,
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    ),
                    const SizedBox(width: 8),
                  ]),
                ),
              ),
            ),
          ),
          _HeaderButton(
            icon: fullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
            label: fullScreen ? 'Exit full screen' : 'Full screen',
            onTap: onToggleFullScreen,
          ),
          _HeaderButton(icon: Icons.close, label: 'Close window', onTap: onClose),
          const SizedBox(width: 4),
        ]),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: LiveStudioWorld.screen,
        border: frameWidth > 0 ? Border.all(color: frameColor, width: frameWidth) : null,
        borderRadius: BorderRadius.all(Radius.circular(radius)),
        boxShadow: LiveStudioWorld.popShadow,
      ),
      child: Padding(
        padding: EdgeInsets.all(frameWidth),
        child: ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular((radius - frameWidth).clamp(0.0, radius))),
          child: Stack(children: [
            Column(children: [
              header,
              Expanded(child: LazyMount(child: child)),
            ]),
            if (!fullScreen)
              Positioned(
                right: 0,
                bottom: 0,
                width: 28,
                height: 28,
                child: Semantics(
                  label: 'Resize window',
                  button: true,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeDownRight,
                    child: GestureDetector(
                      key: const ValueKey('popout-resize'),
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: onResize == null ? null : (d) => onResize!(d.delta),
                      child: const Align(
                        alignment: Alignment.bottomRight,
                        child: Icon(Icons.south_east, size: 18, color: LiveStudioAccent.inWindowIcon),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox.square(
            dimension: 36,
            child: Icon(icon, size: 18, color: LiveStudioWorld.popIcon),
          ),
        ),
      );
}

/// Mounts [child] one frame after the window appears, so opening stays a
/// cheap transform-only frame (lazy pop-out content).
class LazyMount extends StatefulWidget {
  const LazyMount({super.key, required this.child});
  final Widget child;
  @override
  State<LazyMount> createState() => _LazyMountState();
}

class _LazyMountState extends State<LazyMount> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.child : const ColoredBox(color: LiveStudioWorld.screen);
}
