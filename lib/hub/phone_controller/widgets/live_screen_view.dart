import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../computer_action_log.dart';
import '../controller_link.dart';
import 'tactile.dart';

/// The computer's live screen, rendered from the WebRTC video track, and a
/// direct touch surface for the mouse:
///
/// * tap → click there (tap twice → double-click)
/// * slide one finger → the pointer follows (hover)
/// * hold, then slide → drag
/// * hold and release without moving → right-click
/// * two fingers → pinch to zoom / pan the view; two-finger tap → right-click
///
/// The video is a GPU texture inside a [RepaintBoundary], so touch overlays
/// repaint on their own layer and never force the frame to re-upload.
class LiveScreenView extends StatefulWidget {
  const LiveScreenView({
    super.key,
    required this.renderer,
    required this.link,
    required this.hasVideo,
    required this.enabled,
    this.status,
  });

  final RTCVideoRenderer? renderer;
  final ControllerLink link;
  final bool hasVideo;
  final bool enabled;

  /// Small status shown over the stream (e.g. front app, "Locked").
  final String? status;

  @override
  State<LiveScreenView> createState() => _LiveScreenViewState();
}

class _LiveScreenViewState extends State<LiveScreenView> {
  static const double _slop = 8;
  static const Duration _tapMax = Duration(milliseconds: 230);
  static const Duration _hold = Duration(milliseconds: 360);

  final Map<int, Offset> _pointers = {};
  final ValueNotifier<_Touch?> _touch = ValueNotifier(null);
  Size _box = Size.zero;

  // View transform (local zoom/pan only, never sent to the computer).
  double _scale = 1;
  Offset _offset = Offset.zero;
  double _pinchStartScale = 1;
  double _pinchStartDist = 1;
  Offset _pinchStartFocal = Offset.zero;
  Offset _pinchStartOffset = Offset.zero;

  // One-finger session.
  DateTime _downAt = DateTime.now();
  Offset _downPos = Offset.zero;
  bool _moved = false;
  bool _held = false;
  bool _dragging = false;
  bool _twoFinger = false;
  Timer? _holdTimer;
  DateTime _lastHoverSent = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _holdTimer?.cancel();
    if (_dragging) widget.link.leftUp();
    _touch.dispose();
    super.dispose();
  }

  /// Rect of the video inside the box (BoxFit.contain), before zoom.
  Rect _videoRect() {
    final r = widget.renderer;
    final vw = (r?.videoWidth ?? 0).toDouble();
    final vh = (r?.videoHeight ?? 0).toDouble();
    if (vw <= 0 || vh <= 0 || _box.isEmpty) return Offset.zero & _box;
    final fitted = applyBoxFit(BoxFit.contain, Size(vw, vh), _box).destination;
    return Alignment.center.inscribe(fitted, Offset.zero & _box);
  }

  /// Screen point → normalised computer coordinates (0..1), or null when
  /// outside the picture.
  Offset? _normalise(Offset local) {
    final scene = (local - _offset) / _scale;
    final rect = _videoRect();
    if (rect.isEmpty) return null;
    final nx = (scene.dx - rect.left) / rect.width;
    final ny = (scene.dy - rect.top) / rect.height;
    if (nx < -0.02 || nx > 1.02 || ny < -0.02 || ny > 1.02) return null;
    return Offset(nx.clamp(0.0, 1.0), ny.clamp(0.0, 1.0));
  }

  void _clampView() {
    if (_scale <= 1.001) {
      _scale = 1;
      _offset = Offset.zero;
      return;
    }
    final maxX = 0.0, minX = _box.width - _box.width * _scale;
    final maxY = 0.0, minY = _box.height - _box.height * _scale;
    _offset = Offset(_offset.dx.clamp(minX, maxX), _offset.dy.clamp(minY, maxY));
  }

  Offset _centroid() {
    var sum = Offset.zero;
    for (final p in _pointers.values) {
      sum += p;
    }
    return sum / math.max(1, _pointers.length).toDouble();
  }

  double _spread() {
    if (_pointers.length < 2) return 1;
    final pts = _pointers.values.toList();
    return math.max(1, (pts[0] - pts[1]).distance);
  }

  void _onDown(PointerDownEvent e) {
    if (!widget.enabled || !widget.hasVideo) return;
    _pointers[e.pointer] = e.localPosition;
    widget.link.source = ActionSource.touch;
    if (_pointers.length == 1) {
      _downAt = DateTime.now();
      _downPos = e.localPosition;
      _moved = false;
      _held = false;
      _twoFinger = false;
      _touch.value = _Touch(e.localPosition, false);
      _holdTimer?.cancel();
      _holdTimer = Timer(_hold, () {
        if (_moved || _pointers.length != 1) return;
        _held = true;
        HapticFeedback.mediumImpact();
        _touch.value = _Touch(_downPos, true);
      });
    } else if (_pointers.length == 2) {
      _holdTimer?.cancel();
      if (_dragging) {
        widget.link.leftUp();
        _dragging = false;
      }
      _twoFinger = true;
      _pinchStartScale = _scale;
      _pinchStartDist = _spread();
      _pinchStartFocal = _centroid();
      _pinchStartOffset = _offset;
      _touch.value = null;
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;

    if (_twoFinger) {
      if (_pointers.length < 2) return;
      final focal = _centroid();
      final nextScale = (_pinchStartScale * _spread() / _pinchStartDist).clamp(1.0, 4.0);
      // Keep the content under the starting focal point under the fingers.
      final sceneFocal = (_pinchStartFocal - _pinchStartOffset) / _pinchStartScale;
      setState(() {
        _scale = nextScale;
        _offset = focal - sceneFocal * nextScale;
        _clampView();
      });
      if ((focal - _pinchStartFocal).distance > _slop) _moved = true;
      return;
    }

    if (!_moved && (e.localPosition - _downPos).distance > _slop) {
      _moved = true;
      if (!_held) _holdTimer?.cancel();
    }
    if (!_moved) return;

    final n = _normalise(e.localPosition);
    if (n == null) return;
    if (_held && !_dragging) {
      _dragging = true;
      final start = _normalise(_downPos) ?? n;
      widget.link.pressAt(start.dx, start.dy);
    }
    // Hover/drag moves are throttled to the display refresh (~120 Hz max).
    final now = DateTime.now();
    if (now.difference(_lastHoverSent).inMicroseconds >= 8000) {
      _lastHoverSent = now;
      widget.link.moveTo(n.dx, n.dy);
    }
    _touch.value = _Touch(e.localPosition, _dragging);
  }

  void _onUp(PointerEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    final last = _pointers.remove(e.pointer)!;
    if (_pointers.isNotEmpty) return;
    _holdTimer?.cancel();
    final quick = DateTime.now().difference(_downAt) < _tapMax;
    final cancelled = e is PointerCancelEvent;

    if (_twoFinger) {
      if (!cancelled && !_moved && quick) {
        final n = _normalise(_pinchStartFocal);
        if (n != null) {
          widget.link.rightClickAt(n.dx, n.dy);
          HapticFeedback.mediumImpact();
        }
      }
    } else if (_dragging) {
      final n = _normalise(last);
      if (n != null) widget.link.moveTo(n.dx, n.dy, log: true);
      widget.link.leftUp();
      HapticFeedback.selectionClick();
    } else if (!cancelled && _held && !_moved) {
      final n = _normalise(last);
      if (n != null) {
        widget.link.rightClickAt(n.dx, n.dy);
        HapticFeedback.mediumImpact();
      }
    } else if (!cancelled && !_moved && quick) {
      final n = _normalise(last);
      if (n != null) {
        widget.link.clickAt(n.dx, n.dy);
        HapticFeedback.lightImpact();
        _touch.value = _Touch(last, false, ripple: true);
      }
    } else if (_moved) {
      final n = _normalise(last);
      if (n != null) widget.link.moveTo(n.dx, n.dy, log: true);
    }
    _dragging = false;
    _held = false;
    _twoFinger = false;
    Future<void>.delayed(const Duration(milliseconds: 260), () {
      if (mounted && _pointers.isEmpty) _touch.value = null;
    });
  }

  void _resetZoom() {
    HapticFeedback.selectionClick();
    setState(() {
      _scale = 1;
      _offset = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    final renderer = widget.renderer;
    return Container(
      decoration: Tactile.recessed(context, radius: AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _box = constraints.biggest;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onDown,
            onPointerMove: _onMove,
            onPointerUp: _onUp,
            onPointerCancel: _onUp,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (renderer != null)
                  RepaintBoundary(
                    child: Transform(
                      transform: Matrix4.identity()
                        ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
                        ..scaleByDouble(_scale, _scale, 1, 1),
                      child: RTCVideoView(
                        renderer,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                if (!widget.hasVideo) _Placeholder(enabled: widget.enabled),
                // Touch feedback on its own layer.
                RepaintBoundary(
                  child: ValueListenableBuilder<_Touch?>(
                    valueListenable: _touch,
                    builder: (context, t, _) => t == null
                        ? const SizedBox.shrink()
                        : CustomPaint(painter: _TouchPainter(t)),
                  ),
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: _LiveBadge(live: widget.hasVideo, status: widget.status),
                ),
                if (_scale > 1)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: GestureDetector(
                      onTap: _resetZoom,
                      child: _Chip(
                        icon: Icons.zoom_out_map_rounded,
                        label: '${_scale.toStringAsFixed(1)}×',
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Touch {
  _Touch(this.pos, this.dragging, {this.ripple = false});
  final Offset pos;
  final bool dragging;
  final bool ripple;
}

class _TouchPainter extends CustomPainter {
  _TouchPainter(this.t);
  final _Touch t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = t.dragging ? AppColors.brandPink : AppColors.brandBlue;
    canvas.drawCircle(
      t.pos,
      t.ripple ? 26 : 20,
      Paint()
        ..color = c.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      t.pos,
      t.ripple ? 22 : 16,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = c.withValues(alpha: 0.85),
    );
    canvas.drawCircle(t.pos, 3, Paint()..color = c);
  }

  @override
  bool shouldRepaint(covariant _TouchPainter old) => old.t != t;
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.desktop_windows_outlined, size: 28, color: context.textMuted),
          const SizedBox(height: 8),
          Text(
            enabled ? 'Starting live screen…' : 'Waiting for your computer…',
            style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.live, this.status});
  final bool live;
  final String? status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.brandBlack.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusLed(on: live, size: 5),
          const SizedBox(width: 5),
          Text(
            live ? (status == null ? 'LIVE' : 'LIVE · $status') : 'OFF',
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppColors.brandWhite,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.brandBlack.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.brandWhite),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: AppColors.brandWhite,
            ),
          ),
        ],
      ),
    );
  }
}
