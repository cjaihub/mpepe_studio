import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../shared/theme/app_theme.dart';

/// Shared pieces for the wallet, plans, withdraw and insights screens.

class MoneyScaffold extends StatelessWidget {
  const MoneyScaffold({super.key, required this.title, required this.body, this.actions, this.bottom});
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 50,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary, size: 20),
          onPressed: () => context.canPop() ? context.pop() : context.go('/hub/home'),
        ),
        title: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: context.textPrimary)),
        actions: actions,
      ),
      body: body,
      bottomNavigationBar: bottom,
    );
  }
}

/// Counts up to [value] when it first shows and whenever it changes.
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber({super.key, required this.value, required this.format, this.style});
  final double value;
  final String Function(double v) format;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text(format(v), style: style),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: context.textPrimary))),
          ?trailing,
        ],
      ),
    );
  }
}

/// A rounded card with the hairline border used across the money screens.
class MoneyCard extends StatelessWidget {
  const MoneyCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap, this.margin = const EdgeInsets.symmetric(horizontal: 16)});
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Material(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: context.border)),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Pulsing "You're growing" strip with an encouraging line.
class GrowthBanner extends StatelessWidget {
  const GrowthBanner({super.key, required this.title, required this.body, this.icon = Icons.trending_up_rounded});
  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brandPink.withValues(alpha: context.isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.premiumGradient),
            child: Icon(icon, color: Colors.white, size: 18),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(begin: 1, end: 1.08, duration: 900.ms, curve: Curves.easeInOut),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: context.textPrimary)),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(fontSize: 12, height: 1.35, color: context.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.08, end: 0);
  }
}

/// Progress toward the next milestone ("312 / 500 followers").
class MilestoneBar extends StatelessWidget {
  const MilestoneBar({super.key, required this.label, required this.value, required this.goal});
  final String label;
  final num value;
  final num goal;

  @override
  Widget build(BuildContext context) {
    final p = goal <= 0 ? 0.0 : (value / goal).clamp(0, 1).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary))),
            Text('${(p * 100).round()}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.brandPink)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: p),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 6,
              backgroundColor: context.surfaceMid,
              valueColor: const AlwaysStoppedAnimation(AppColors.brandBlue),
            ),
          ),
        ),
      ],
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key, this.review = false});
  final String status;
  final bool review;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      'paid' => ('Paid', AppColors.brandBlue, Icons.check_circle_rounded),
      'processing' => ('Sending', AppColors.brandBlue, Icons.sync_rounded),
      'failed' => ('Failed', AppColors.brandPink, Icons.error_rounded),
      'cancelled' => ('Cancelled', context.textMuted, Icons.block_rounded),
      _ => (review ? 'Checking' : 'Pending', AppColors.brandPink, Icons.schedule_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(label.toUpperCase(), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.6, color: color)),
        ],
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.icon, this.busy = false, this.color = AppColors.brandBlue});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        disabledBackgroundColor: color.withValues(alpha: 0.35),
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(42),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
      child: busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 17), const SizedBox(width: 6)],
                Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ],
            ),
    );
  }
}

/// Blue and pink confetti that bursts once from the top center.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..forward();
  late final List<_Bit> _bits = () {
    final r = Random();
    return List.generate(70, (i) => _Bit(
          angle: -pi / 2 + (r.nextDouble() - 0.5) * pi * 1.1,
          speed: 0.45 + r.nextDouble() * 0.7,
          spin: (r.nextDouble() - 0.5) * 12,
          size: 4 + r.nextDouble() * 5,
          pink: i.isEven,
        ));
  }();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(painter: _ConfettiPainter(_bits, _c.value), size: Size.infinite),
      ),
    );
  }
}

class _Bit {
  final double angle, speed, spin, size;
  final bool pink;
  const _Bit({required this.angle, required this.speed, required this.spin, required this.size, required this.pink});
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.bits, this.t);
  final List<_Bit> bits;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.32);
    final paint = Paint();
    for (final b in bits) {
      final d = b.speed * size.height * 0.55 * Curves.easeOut.transform(t);
      final pos = origin + Offset(cos(b.angle) * d, sin(b.angle) * d + 320 * t * t);
      paint.color = (b.pink ? AppColors.brandPink : AppColors.brandBlue).withValues(alpha: (1 - t).clamp(0, 1));
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(b.spin * t);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: b.size, height: b.size * 0.55), const Radius.circular(1)), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

/// Big animated check used after a payout or purchase succeeds.
class SuccessMark extends StatelessWidget {
  const SuccessMark({super.key, this.icon = Icons.check_rounded});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.premiumGradient,
        boxShadow: [BoxShadow(color: AppColors.brandBlue.withValues(alpha: 0.35), blurRadius: 24, spreadRadius: 2)],
      ),
      child: Icon(icon, color: Colors.white, size: 44),
    ).animate().scale(begin: const Offset(0.3, 0.3), end: const Offset(1, 1), duration: 520.ms, curve: Curves.elasticOut).fadeIn(duration: 200.ms);
  }
}
