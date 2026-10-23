import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart';

/// Compact engagement count: 999, 1.2K, 12K, 3.4M, 1.1B.
String formatCompactCount(int count) {
  final n = count < 0 ? 0 : count;
  String fmt(double v, String suffix) {
    final s = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}$suffix';
  }

  if (n >= 1000000000) return fmt(n / 1000000000, 'B');
  if (n >= 1000000) return fmt(n / 1000000, 'M');
  if (n >= 1000) return fmt(n / 1000, 'K');
  return '$n';
}

/// A count that rolls up (new value slides in from below) or down (from
/// above) whenever it changes.
class RollingCount extends StatefulWidget {
  final int value;
  final TextStyle style;

  const RollingCount({super.key, required this.value, required this.style});

  @override
  State<RollingCount> createState() => _RollingCountState();
}

class _RollingCountState extends State<RollingCount> {
  bool _up = true;

  @override
  void didUpdateWidget(RollingCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) _up = widget.value > oldWidget.value;
  }

  @override
  Widget build(BuildContext context) {
    final label = formatCompactCount(widget.value);
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.center,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, anim) {
          final incoming = child.key == ValueKey(label);
          final dir = _up ? 1.0 : -1.0;
          final begin = Offset(0, incoming ? dir : -dir);
          return SlideTransition(
            position: Tween<Offset>(begin: begin, end: Offset.zero).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          );
        },
        child: Text(label, key: ValueKey(label), style: widget.style),
      ),
    );
  }
}

/// Hearts that float up from a point (the like button) and fade out.
/// Call [FloatingHeartsState.burst] through a GlobalKey.
class FloatingHearts extends StatefulWidget {
  final double width;
  final double height;

  const FloatingHearts({super.key, this.width = 60, this.height = 180});

  @override
  State<FloatingHearts> createState() => FloatingHeartsState();
}

class _Heart {
  final AnimationController controller;
  final double drift;
  final double phase;
  final double size;
  final Color color;
  _Heart(this.controller, this.drift, this.phase, this.size, this.color);
}

class FloatingHeartsState extends State<FloatingHearts> with TickerProviderStateMixin {
  final _rnd = math.Random();
  final List<_Heart> _hearts = [];

  void burst({int count = 5}) {
    for (var i = 0; i < count; i++) {
      Future.delayed(Duration(milliseconds: i * 90), _spawn);
    }
  }

  void _spawn() {
    if (!mounted || _hearts.length > 14) return;
    final c = AnimationController(vsync: this, duration: Duration(milliseconds: 1100 + _rnd.nextInt(500)));
    final heart = _Heart(
      c,
      (_rnd.nextDouble() - 0.5) * 36,
      _rnd.nextDouble() * math.pi * 2,
      14 + _rnd.nextDouble() * 10,
      _rnd.nextInt(3) == 0 ? AppColors.brandBlue : AppColors.brandPink,
    );
    setState(() => _hearts.add(heart));
    c.forward().whenComplete(() {
      if (!mounted) return;
      setState(() => _hearts.remove(heart));
      c.dispose();
    });
  }

  @override
  void dispose() {
    for (final h in _hearts) {
      h.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final h in _hearts)
              AnimatedBuilder(
                animation: h.controller,
                builder: (context, child) {
                  final t = h.controller.value;
                  final rise = Curves.easeOutCubic.transform(t);
                  final x = widget.width / 2 - h.size / 2 + h.drift * t + math.sin(h.phase + t * 6) * 6;
                  final y = widget.height - h.size - rise * (widget.height - h.size);
                  final scale = t < 0.15 ? Curves.easeOutBack.transform(t / 0.15) : 1.0 - 0.3 * t;
                  return Positioned(
                    left: x,
                    top: y,
                    child: Opacity(
                      opacity: (1 - Curves.easeIn.transform(t)).clamp(0.0, 1.0),
                      child: Transform.scale(scale: scale, child: child),
                    ),
                  );
                },
                child: Icon(
                  Icons.favorite_rounded,
                  size: h.size,
                  color: h.color,
                  shadows: const [Shadow(color: Colors.black26, blurRadius: 6)],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
