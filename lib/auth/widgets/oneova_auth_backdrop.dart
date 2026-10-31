import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/theme/app_theme.dart';

/// Hides the status and navigation bars while an auth screen is open.
/// `immersiveSticky` lets the person swipe the bars back in; they fade away
/// again on their own. The previous edge-to-edge mode is restored on dispose.
mixin OneovaImmersiveAuth<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }
}

/// The live, faded background behind the login and sign-up screens: slow
/// drifting brand-colour light plus a few softly floating icons that hint at
/// what Oneova is for (reels, chat, live, creating, community).
class OneovaAuthBackdrop extends StatefulWidget {
  const OneovaAuthBackdrop({super.key, required this.child});

  final Widget child;

  @override
  State<OneovaAuthBackdrop> createState() => _OneovaAuthBackdropState();
}

class _OneovaAuthBackdropState extends State<OneovaAuthBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 24))
    ..repeat();

  static const _icons = <IconData>[
    Icons.play_circle_outline_rounded,
    Icons.chat_bubble_outline_rounded,
    Icons.favorite_border_rounded,
    Icons.videocam_outlined,
    Icons.auto_awesome_outlined,
    Icons.music_note_outlined,
    Icons.groups_2_outlined,
    Icons.sensors_rounded,
    Icons.brush_outlined,
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion && _c.isAnimating) _c.stop();

    return ColoredBox(
      color: context.bg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value * 2 * math.pi;
                final size = MediaQuery.sizeOf(context);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _glow(
                      size,
                      dx: 0.15 + 0.12 * math.sin(t),
                      dy: 0.18 + 0.08 * math.cos(t),
                      radius: size.width * 0.85,
                      color: AppColors.brandBlue.withValues(alpha: isDark ? 0.30 : 0.16),
                    ),
                    _glow(
                      size,
                      dx: 0.90 + 0.10 * math.cos(t * 1.3),
                      dy: 0.72 + 0.08 * math.sin(t * 1.3),
                      radius: size.width * 0.75,
                      color: AppColors.brandPink.withValues(alpha: isDark ? 0.18 : 0.10),
                    ),
                    _glow(
                      size,
                      dx: 0.55 + 0.20 * math.sin(t * 0.7 + 1),
                      dy: 1.02,
                      radius: size.width * 0.6,
                      color: AppColors.brandBlue.withValues(alpha: isDark ? 0.18 : 0.08),
                    ),
                    for (var i = 0; i < _icons.length; i++) _floatingIcon(size, i, t, isDark),
                  ],
                );
              },
            ),
          ),
          widget.child,
        ],
      ),
    );
  }

  Widget _glow(Size size, {required double dx, required double dy, required double radius, required Color color}) {
    return Positioned(
      left: size.width * dx - radius,
      top: size.height * dy - radius,
      width: radius * 2,
      height: radius * 2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }

  Widget _floatingIcon(Size size, int i, double t, bool isDark) {
    // Spread the icons on a loose grid around the edges so they never sit
    // behind the form itself.
    final rnd = math.Random(i * 31 + 7);
    final left = i.isEven;
    final baseX = left ? 0.04 + rnd.nextDouble() * 0.14 : 0.80 + rnd.nextDouble() * 0.14;
    final baseY = 0.06 + (i / _icons.length) * 0.86;
    final phase = rnd.nextDouble() * 2 * math.pi;
    final x = size.width * baseX + 8 * math.sin(t + phase);
    final y = size.height * baseY + 14 * math.cos(t * 0.8 + phase);
    final opacity = (isDark ? 0.10 : 0.08) + 0.05 * math.sin(t * 1.5 + phase);
    final color = i % 3 == 0 ? AppColors.brandPink : AppColors.brandBlue;
    return Positioned(
      left: x,
      top: y,
      child: Transform.rotate(
        angle: 0.25 * math.sin(t + phase),
        child: Icon(_icons[i], size: 20 + rnd.nextDouble() * 10, color: color.withValues(alpha: opacity.clamp(0.0, 1.0))),
      ),
    );
  }
}

/// "Oneova — the reason you matter." brand lockup used at the top of the
/// login and sign-up screens.
class OneovaAuthTagline extends StatelessWidget {
  const OneovaAuthTagline({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'ONEOVA',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: compact ? 15 : 20,
            letterSpacing: 3.0,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(colors: [AppColors.brandBlue, AppColors.brandPink]).createShader(r),
          child: Text(
            'the reason you matter',
            style: TextStyle(
              fontSize: compact ? 11.5 : 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

/// Three small promise chips shown under the login form.
class OneovaAuthPromises extends StatelessWidget {
  const OneovaAuthPromises({super.key});

  @override
  Widget build(BuildContext context) {
    Widget chip(IconData icon, String label) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: context.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: AppColors.brandBlue),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: context.textSecondary)),
            ],
          ),
        );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        chip(Icons.verified_user_outlined, 'Private by default'),
        chip(Icons.auto_awesome_outlined, 'Made for creators'),
        chip(Icons.favorite_border_rounded, 'Your people, first'),
      ],
    );
  }
}
