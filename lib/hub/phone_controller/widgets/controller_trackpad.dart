import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../computer_action_log.dart';
import '../controller_link.dart';

/// Live trackpad: one finger moves the pointer, tap clicks, tap-tap double
/// clicks, hold-then-move drags, two fingers scroll (tap with two = right
/// click) and the right-edge rail scrolls with one finger. Scrolls released
/// with speed keep gliding with exponential easing until caught by a touch.
class ControllerTrackpad extends StatefulWidget {
  const ControllerTrackpad({
    super.key,
    required this.link,
    required this.enabled,
    this.sensitivity = 1.0,
    this.dragLock = false,
  });

  final ControllerLink link;
  final bool enabled;

  /// Pointer speed multiplier (≈0.7 precise … 1.5 swift).
  final double sensitivity;

  /// When on, a hold-drag keeps the button down after lifting; the next tap
  /// releases it.
  final bool dragLock;

  @override
  State<ControllerTrackpad> createState() => _ControllerTrackpadState();
}

class _ControllerTrackpadState extends State<ControllerTrackpad>
    with SingleTickerProviderStateMixin {
  static const double _railWidth = 34;
  static const double _tapSlop = 7;
  static const Duration _tapMax = Duration(milliseconds: 240);
  static const Duration _holdToDrag = Duration(milliseconds: 380);

  /// Momentum time constant: velocity decays as e^(-t/τ).
  static const double _tau = 0.42;
  static const double _scrollGain = 1.5;

  final _TouchField _field = _TouchField();
  final Map<int, Offset> _pointers = {};
  final Map<int, Duration> _lastStamp = {};
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  Size _size = Size.zero;

  bool _twoFinger = false;
  bool _rail = false;
  bool _moved = false;
  bool _dragging = false;
  int _maxPointers = 0;
  double _travel = 0;
  DateTime _downAt = DateTime.now();
  Timer? _holdTimer;
  VelocityTracker? _scrollTracker;
  Offset _momentum = Offset.zero;
  bool _everTouched = false;
  bool _glideLaunched = false;
  DateTime _lastMoveAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(covariant ControllerTrackpad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dragLock &&
        !widget.dragLock &&
        _dragging &&
        _pointers.isEmpty) {
      _endDrag();
    }
    if (!widget.enabled && _dragging) _endDrag();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    if (_dragging) widget.link.leftUp();
    _ticker.dispose();
    _field.dispose();
    super.dispose();
  }

  // ─── Gesture session ──────────────────────────────────────────────────────

  Offset _centroid() {
    if (_pointers.isEmpty) return Offset.zero;
    var sum = Offset.zero;
    for (final p in _pointers.values) {
      sum += p;
    }
    return sum / _pointers.length.toDouble();
  }

  void _onDown(PointerDownEvent e) {
    if (!widget.enabled) return;
    widget.link.source = ActionSource.trackpad;
    if (!_everTouched) setState(() => _everTouched = true);
    if (_momentum != Offset.zero) {
      // Catch the glide like a real trackpad.
      _momentum = Offset.zero;
      _field.momentum = 0;
      HapticFeedback.selectionClick();
    }
    _pointers[e.pointer] = e.localPosition;
    _lastStamp[e.pointer] = e.timeStamp;
    _field.touch(e.pointer, e.localPosition);
    _startTicker();

    if (_pointers.length == 1) {
      _twoFinger = false;
      _glideLaunched = false;
      _moved = false;
      _travel = 0;
      _maxPointers = 1;
      _downAt = DateTime.now();
      _rail = e.localPosition.dx > _size.width - _railWidth;
      _field.rail = _rail;
      if (_rail) {
        _scrollTracker = VelocityTracker.withKind(e.kind)
          ..addPosition(e.timeStamp, e.localPosition);
      } else if (!_dragging) {
        _holdTimer?.cancel();
        _holdTimer = Timer(_holdToDrag, _beginDrag);
      }
    } else {
      _holdTimer?.cancel();
      _maxPointers = math.max(_maxPointers, _pointers.length);
      if (!_dragging && !_rail) {
        _twoFinger = true;
        _scrollTracker = VelocityTracker.withKind(e.kind)
          ..addPosition(e.timeStamp, _centroid());
      }
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (!widget.enabled || !_pointers.containsKey(e.pointer)) return;
    final prevStamp = _lastStamp[e.pointer] ?? e.timeStamp;
    _pointers[e.pointer] = e.localPosition;
    _lastStamp[e.pointer] = e.timeStamp;
    _field.touch(e.pointer, e.localPosition);

    final d = e.localDelta;
    _travel += d.distance;
    _lastMoveAt = DateTime.now();
    if (_travel > _tapSlop && !_moved) {
      _moved = true;
      if (!_dragging) _holdTimer?.cancel();
    }

    if (_rail) {
      _scrollTracker?.addPosition(e.timeStamp, e.localPosition);
      widget.link.scroll(
        0,
        d.dy * _scrollGain * _whip(d, prevStamp, e.timeStamp),
      );
      return;
    }

    if (_twoFinger) {
      if (_pointers.length < 2) return; // residual finger after a lift
      final share = d / _pointers.length.toDouble();
      _scrollTracker?.addPosition(e.timeStamp, _centroid());
      final g = _scrollGain * _whip(share, prevStamp, e.timeStamp);
      widget.link.scroll(share.dx * g, share.dy * g);
      return;
    }

    if (_pointers.length > 1) return;

    // Pointer acceleration: slow strokes stay precise, quick flicks cross
    // the screen without lifting.
    final dtMs = math.max(1, (e.timeStamp - prevStamp).inMicroseconds / 1000.0);
    final speed = d.distance / dtMs; // logical px per ms
    final accel = 1.0 + ((speed - 0.2) * 1.5).clamp(0.0, 2.4);
    final g = widget.sensitivity * 1.35 * accel;
    widget.link.move(d.dx * g, d.dy * g);
  }

  /// Scroll gain grows gently with finger speed so a fast swipe "whips" the
  /// page further while slow drags track 1:1.
  double _whip(Offset d, Duration prev, Duration now) {
    final dtMs = math.max(1, (now - prev).inMicroseconds / 1000.0);
    final speed = d.distance / dtMs;
    return 1.0 + ((speed - 0.6) * 0.6).clamp(0.0, 1.1);
  }

  void _onUp(PointerEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers.remove(e.pointer);
    _lastStamp.remove(e.pointer);
    _field.release(e.pointer);
    // Two-finger glide starts as soon as the pair breaks, so a finger left
    // resting on the glass doesn't hold back (or distort) the flick.
    if (_twoFinger && _pointers.length == 1 && _moved && !_glideLaunched) {
      _glideLaunched = true;
      _launchMomentum(verticalOnly: false);
    }
    if (_pointers.isNotEmpty) return;

    _holdTimer?.cancel();
    final quick = DateTime.now().difference(_downAt) < _tapMax;
    final cancelled = e is PointerCancelEvent;

    if (_twoFinger) {
      if (!cancelled && !_moved && quick && _maxPointers == 2) {
        widget.link.rightClick();
        _field.flash(e.localPosition);
        HapticFeedback.mediumImpact();
      } else if (!_glideLaunched) {
        _launchMomentum(verticalOnly: false);
      }
    } else if (_rail) {
      if (_moved) _launchMomentum(verticalOnly: true);
    } else if (_dragging) {
      if (cancelled || !widget.dragLock || (!_moved && quick)) _endDrag();
    } else if (!cancelled && !_moved && quick) {
      widget.link.click();
      _field.flash(e.localPosition);
      HapticFeedback.lightImpact();
    }

    _twoFinger = false;
    _rail = false;
    _field.rail = false;
    _startTicker();
  }

  void _beginDrag() {
    if (_moved || _pointers.length != 1 || _dragging) return;
    _dragging = true;
    _field.dragging = true;
    widget.link.leftDown();
    HapticFeedback.heavyImpact();
  }

  void _endDrag() {
    if (!_dragging) return;
    _dragging = false;
    _field.dragging = false;
    widget.link.leftUp();
    HapticFeedback.selectionClick();
  }

  void _launchMomentum({required bool verticalOnly}) {
    final v = _scrollTracker?.getVelocity().pixelsPerSecond ?? Offset.zero;
    _scrollTracker = null;
    // Finger paused before lifting: no glide, like a real trackpad.
    final idle = DateTime.now().difference(_lastMoveAt);
    if (idle > const Duration(milliseconds: 90)) return;
    var vel = verticalOnly ? Offset(0, v.dy) : v;
    if (vel.distance < 140) return;
    if (vel.distance > 9000) vel = vel / vel.distance * 9000;
    _momentum = vel * _scrollGain;
    _lastTick = Duration.zero;
    _startTicker();
  }

  // ─── Frame loop (momentum + texture fade) ─────────────────────────────────

  void _startTicker() {
    if (_ticker.isActive) return;
    _lastTick = Duration.zero;
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;

    if (_momentum != Offset.zero && dt > 0) {
      final step = _momentum * dt;
      widget.link.scroll(step.dx, step.dy);
      _momentum *= math.exp(-dt / _tau);
      _field.momentum = (_momentum.distance / 3600).clamp(0.0, 1.0);
      if (_momentum.distance < 18) {
        _momentum = Offset.zero;
        _field.momentum = 0;
      }
    }

    final fading = _field.tick(dt);
    if (!fading && _momentum == Offset.zero && _pointers.isEmpty) {
      _ticker.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: _onUp,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: context.border, width: 1.0),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [context.surface, context.surfaceMid],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandBlack.withValues(
                    alpha: isDark ? 0.5 : 0.1,
                  ),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _TrackpadPainter(
                        field: _field,
                        dot: context.textMuted.withValues(
                          alpha: isDark ? 0.28 : 0.32,
                        ),
                        // Lifted a touch in dark mode so the ring and
                        // lit texture stay visible on near-black.
                        accent: isDark
                            ? Color.lerp(
                                AppColors.brandBlue,
                                AppColors.brandWhite,
                                0.28,
                              )!
                            : AppColors.brandBlue,
                        accentHot: AppColors.brandPink,
                        rail: context.border,
                        railWidth: _railWidth,
                        glowAlpha: isDark ? 0.34 : 0.2,
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _everTouched ? 0 : 1,
                      duration: const Duration(milliseconds: 260),
                      child: _IdleHint(enabled: widget.enabled),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IdleHint extends StatelessWidget {
  const _IdleHint({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.inter(
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
      color: context.textSecondary,
      height: 1.35,
    );
    Widget row(IconData icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: context.textMuted),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: style)),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 40, 20),
      child: Center(
        child: enabled
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  row(
                    Icons.touch_app_outlined,
                    'Move with one finger · tap to click',
                  ),
                  row(
                    Icons.swipe_vertical_outlined,
                    'Two fingers to scroll · flick to glide',
                  ),
                  row(Icons.pan_tool_alt_outlined, 'Hold, then move to drag'),
                ],
              )
            : Text('Waiting for your computer…', style: style),
      ),
    );
  }
}

// ─── Touch field model ──────────────────────────────────────────────────────

class _TouchPoint {
  _TouchPoint(this.pos);
  Offset pos;
  bool active = true;
  double strength = 1;
  final List<Offset> trail = [];
}

class _Flash {
  _Flash(this.pos);
  final Offset pos;
  double t = 0;
}

class _TouchField extends ChangeNotifier {
  final Map<int, _TouchPoint> points = {};
  final List<_Flash> flashes = [];
  bool dragging = false;
  bool rail = false;
  double momentum = 0;

  void touch(int id, Offset pos) {
    final p = points.putIfAbsent(id, () => _TouchPoint(pos));
    p
      ..pos = pos
      ..active = true
      ..strength = 1;
    p.trail.add(pos);
    if (p.trail.length > 16) p.trail.removeAt(0);
    notifyListeners();
  }

  void release(int id) {
    points[id]?.active = false;
    notifyListeners();
  }

  void flash(Offset pos) {
    flashes.add(_Flash(pos));
    notifyListeners();
  }

  /// Advances fades. Returns true while anything is still animating.
  bool tick(double dt) {
    var animating = momentum > 0;
    points.removeWhere((_, p) {
      if (p.trail.length > 1) p.trail.removeAt(0);
      if (!p.active) {
        p.strength -= dt * 3.4;
        if (p.strength <= 0) return true;
      }
      animating = true;
      return false;
    });
    flashes.removeWhere((f) {
      f.t += dt * 2.6;
      if (f.t >= 1) return true;
      animating = true;
      return false;
    });
    notifyListeners();
    return animating;
  }
}

// ─── Painter ────────────────────────────────────────────────────────────────

class _TrackpadPainter extends CustomPainter {
  _TrackpadPainter({
    required this.field,
    required this.dot,
    required this.accent,
    required this.accentHot,
    required this.rail,
    required this.railWidth,
    required this.glowAlpha,
  }) : super(repaint: field);

  final _TouchField field;
  final Color dot;
  final Color accent;
  final Color accentHot;
  final Color rail;
  final double railWidth;
  final double glowAlpha;

  static const double _spacing = 15;
  static const double _reach = 105;

  @override
  void paint(Canvas canvas, Size size) {
    final hot = field.dragging ? accentHot : accent;
    final touches = field.points.values.toList(growable: false);

    // Scroll rail on the right edge.
    final railX = size.width - railWidth;
    canvas.drawLine(
      Offset(railX, 18),
      Offset(railX, size.height - 18),
      Paint()
        ..color = rail
        ..strokeWidth = 1,
    );
    final railActive = field.rail || field.momentum > 0;
    final pill = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(railX + railWidth / 2, size.height / 2),
        width: 4,
        height: 46 + 90 * field.momentum,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      pill,
      Paint()
        ..color = (railActive ? accent : rail).withValues(
          alpha: railActive ? 0.85 : 1,
        ),
    );

    // Dot texture that swells and leans toward fingers.
    final base = <Offset>[];
    final cols = ((size.width - railWidth) / _spacing).floor();
    final rows = (size.height / _spacing).floor();
    final ox = ((size.width - railWidth) - (cols - 1) * _spacing) / 2;
    final oy = (size.height - (rows - 1) * _spacing) / 2;
    final lit = Paint();
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final p = Offset(ox + c * _spacing, oy + r * _spacing);
        var influence = 0.0;
        var pull = Offset.zero;
        for (final t in touches) {
          final v = t.pos - p;
          final dist = v.distance;
          if (dist >= _reach) continue;
          final f = math.pow(1 - dist / _reach, 2).toDouble() * t.strength;
          if (f > influence) {
            influence = f;
            pull = v;
          }
        }
        if (influence < 0.03) {
          base.add(p);
        } else {
          lit.color = Color.lerp(dot, hot, influence.clamp(0.0, 1.0))!;
          canvas.drawCircle(
            p + pull * (0.14 * influence),
            0.9 + 2.1 * influence,
            lit,
          );
        }
      }
    }
    canvas.drawPoints(
      ui.PointMode.points,
      base,
      Paint()
        ..color = dot
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );

    // Finger glow, ring and fading trail.
    for (final t in touches) {
      final s = t.strength.clamp(0.0, 1.0);
      final rect = Rect.fromCircle(center: t.pos, radius: 78);
      canvas.drawCircle(
        t.pos,
        78,
        Paint()
          ..shader = RadialGradient(
            colors: [
              hot.withValues(alpha: glowAlpha * s),
              hot.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
      canvas.drawCircle(
        t.pos,
        field.dragging ? 26 : 21,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = hot.withValues(alpha: 0.55 * s),
      );
      if (field.dragging) {
        canvas.drawCircle(
          t.pos,
          5,
          Paint()..color = hot.withValues(alpha: 0.9 * s),
        );
      }
      final trail = t.trail;
      for (var i = 1; i < trail.length; i++) {
        final k = i / trail.length;
        canvas.drawLine(
          trail[i - 1],
          trail[i],
          Paint()
            ..color = hot.withValues(alpha: 0.4 * k * s)
            ..strokeWidth = 1 + 3 * k
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Click ripples.
    for (final f in field.flashes) {
      final e = Curves.easeOutCubic.transform(f.t);
      canvas.drawCircle(
        f.pos,
        14 + 34 * e,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 * (1 - e) + 0.4
          ..color = accent.withValues(alpha: 0.7 * (1 - e)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrackpadPainter old) =>
      old.dot != dot || old.accent != accent || old.glowAlpha != glowAlpha;
}
