import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';

class Particle {
  double x, y, vx, vy, life;
  final double maxLife;
  final double radius;

  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.maxLife,
    required this.radius,
  });

  bool update(double dt) {
    x += vx * dt;
    y += vy * dt;
    life -= dt;
    return life > 0;
  }
}

class Ripple {
  final double x, y;
  double radius;
  final double maxRadius;
  double life;
  final double maxLife;
  final double thickness;

  Ripple({
    required this.x,
    required this.y,
    required this.radius,
    required this.maxRadius,
    required this.maxLife,
    this.thickness = 2.0,
  }) : life = maxLife;

  bool update(double dt) {
    life -= dt;
    radius += (maxRadius - radius) * (dt * 4.0); // Ease out expansion
    return life > 0;
  }
}

class NeonTrackpad extends StatefulWidget {
  final GestureScaleUpdateCallback onScaleUpdate;
  final GestureTapCallback onTap;
  final GestureTapCallback onDoubleTap;
  final GestureTapCallback onSecondaryTap;
  final GestureLongPressCallback onLongPress;

  const NeonTrackpad({
    super.key,
    required this.onScaleUpdate,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSecondaryTap,
    required this.onLongPress,
  });

  @override
  State<NeonTrackpad> createState() => _NeonTrackpadState();
}

class _NeonTrackpadState extends State<NeonTrackpad> with TickerProviderStateMixin {
  Offset? _currentTouch;
  final List<Particle> _particles = [];
  final List<Ripple> _ripples = [];
  late Ticker _ticker;
  final Random _random = Random();
  Duration? _lastElapsed;
  double _rippleTimer = 0;
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _ticker = createTicker((elapsed) {
      if (_lastElapsed == null) {
        _lastElapsed = elapsed;
        return;
      }
      final double dt = (elapsed.inMilliseconds - _lastElapsed!.inMilliseconds) / 1000.0;
      _lastElapsed = elapsed;
      
      setState(() {
        _particles.removeWhere((p) => !p.update(dt));
        _ripples.removeWhere((r) => !r.update(dt));

        if (_currentTouch != null) {
          _rippleTimer += dt;
          if (_rippleTimer > 0.12) { // Spawn wave rapidly while touched
            _rippleTimer = 0;
            _ripples.add(Ripple(
              x: _currentTouch!.dx, 
              y: _currentTouch!.dy, 
              radius: 10, 
              maxRadius: 150, 
              maxLife: 1.2,
              thickness: 3.0,
            ));
          }
          // Continuous intense particles spraying out
          _spawnParticles(_currentTouch!, 2, speedMultiplier: 2.0, lifeMultiplier: 1.5);
        } else {
          _rippleTimer = 0;
        }
      });
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _spawnParticles(Offset pos, int count, {double speedMultiplier = 1.0, double lifeMultiplier = 1.0}) {
    for (int i = 0; i < count; i++) {
      final angle = _random.nextDouble() * 2 * pi;
      final speed = (_random.nextDouble() * 200 + 50) * speedMultiplier;
      final maxLife = (_random.nextDouble() * 0.6 + 0.3) * lifeMultiplier;
      final radius = _random.nextDouble() * 4 + 1.5; 
      _particles.add(Particle(
        x: pos.dx,
        y: pos.dy,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        life: maxLife,
        maxLife: maxLife,
        radius: radius,
      ));
    }
  }

  void _addPoint(Offset point) {
    setState(() {
      _currentTouch = point;
    });
    // Spawn trailing particles and mini ripples while moving
    _spawnParticles(point, 4, speedMultiplier: 1.2);
    if (_random.nextDouble() > 0.7) {
       _ripples.add(Ripple(
          x: point.dx, 
          y: point.dy, 
          radius: 5, 
          maxRadius: 50, 
          maxLife: 0.5,
          thickness: 1.5,
       ));
    }
  }

  void _handleTapEvent(Offset? localFocalPoint, VoidCallback callback, int burstCount) {
    final pos = localFocalPoint ?? _currentTouch;
    if (pos != null) {
      _spawnParticles(pos, burstCount, speedMultiplier: 3.0, lifeMultiplier: 1.5);
      _ripples.add(Ripple(
        x: pos.dx, 
        y: pos.dy, 
        radius: 15, 
        maxRadius: 200, 
        maxLife: 1.5,
        thickness: 6.0,
      ));
    }
    callback();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: GestureDetector(
        onScaleStart: (details) => _addPoint(details.localFocalPoint),
        onScaleUpdate: (details) {
          _addPoint(details.localFocalPoint);
          widget.onScaleUpdate(details);
        },
        onScaleEnd: (details) {
          setState(() {
            _currentTouch = null;
          });
        },
        onTapDown: (details) {
           _currentTouch = details.localPosition;
        },
        onTap: () => _handleTapEvent(_currentTouch, widget.onTap, 30),
        onDoubleTap: () => _handleTapEvent(_currentTouch, widget.onDoubleTap, 50),
        onSecondaryTap: () => _handleTapEvent(_currentTouch, widget.onSecondaryTap, 40),
        onLongPress: () => _handleTapEvent(_currentTouch, widget.onLongPress, 45),
        child: CustomPaint(
          foregroundPainter: NeonPainter(_particles, _ripples, _currentTouch, _pulseAnimation.value),
          child: Container(
            color: Colors.transparent, 
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.touch_app_rounded, color: Colors.white24, size: 56),
                  const SizedBox(height: 16),
                  Text(
                    'Live Trackpad',
                    style: GoogleFonts.inter(
                      color: Colors.white54, 
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1-Finger Drag: Move Mouse\n2-Finger Drag: Scroll\nPinch: Zoom\nTap: Left Click, Long Press: Right Click',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: Colors.white30, fontSize: 11, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NeonPainter extends CustomPainter {
  final List<Particle> particles;
  final List<Ripple> ripples;
  final Offset? currentTouch;
  final double pulseValue;

  NeonPainter(this.particles, this.ripples, this.currentTouch, this.pulseValue);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw Ripples (Waves)
    for (final r in ripples) {
      final opacity = (r.life / r.maxLife).clamp(0.0, 1.0);
      final ripplePaint = Paint()
        ..color = AppColors.brandBlue.withValues(alpha: opacity * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r.thickness;
        
      final rippleGlow = Paint()
        ..color = AppColors.brandBlue.withValues(alpha: opacity * 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r.thickness * 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        
      canvas.drawCircle(Offset(r.x, r.y), r.radius, rippleGlow);
      canvas.drawCircle(Offset(r.x, r.y), r.radius, ripplePaint);
    }

    // Draw Particles
    final particlePaint = Paint()..style = PaintingStyle.fill;
    final particleGlowPaint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    for (final p in particles) {
      final opacity = (p.life / p.maxLife).clamp(0.0, 1.0);
      particlePaint.color = AppColors.brandBlue.withValues(alpha: opacity);
      particleGlowPaint.color = AppColors.brandBlue.withValues(alpha: opacity * 0.8);
      
      canvas.drawCircle(Offset(p.x, p.y), p.radius * 2, particleGlowPaint);
      canvas.drawCircle(Offset(p.x, p.y), p.radius, particlePaint);
    }

    // Draw touch orb
    if (currentTouch != null) {
      final orbRadius = 18.0 * pulseValue;
      final orbGlowPaint = Paint()
        ..color = AppColors.brandBlue.withValues(alpha: 0.7)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
        
      final orbCorePaint = Paint()
        ..color = AppColors.brandBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
        
      final innerOrbPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(currentTouch!, orbRadius, orbGlowPaint);
      canvas.drawCircle(currentTouch!, orbRadius, innerOrbPaint);
      canvas.drawCircle(currentTouch!, orbRadius, orbCorePaint);
    }
  }

  @override
  bool shouldRepaint(covariant NeonPainter oldDelegate) {
    return true; // Continuously repainting for smooth physics
  }
}
