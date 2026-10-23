import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';

/// Global "smooth data" kit.
///
/// - [OneovaBlurReveal]: content resolves from a soft blur, fading and rising
///   slightly into place.
/// - [OneovaSmoothSwitcher]: cross-fades between states (skeleton -> data) with
///   the same blur, so loading never "pops".
/// - [OneovaSkeleton]: shimmering placeholder rows shown while data loads.
/// - [AsyncSmooth.smoothWhen]: drop-in replacement for `AsyncValue.when` that
///   animates between loading, data and error.

class OneovaBlurReveal extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final double sigma;
  final double rise;

  const OneovaBlurReveal({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 380),
    this.delay = Duration.zero,
    this.sigma = 8,
    this.rise = 10,
  });

  @override
  Widget build(BuildContext context) {
    final total = duration + delay;
    final startAt = total.inMilliseconds == 0 ? 0.0 : delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: total,
      curve: Interval(startAt, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * rise),
            // Filter is disabled once resolved, so settled content has no cost
            // and the child's state is never rebuilt.
            child: ImageFiltered(
              enabled: t < 0.995,
              imageFilter: ui.ImageFilter.blur(
                sigmaX: (1 - t) * sigma,
                sigmaY: (1 - t) * sigma,
                tileMode: TileMode.decal,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class OneovaSmoothSwitcher extends StatelessWidget {
  final Widget child;
  final Duration duration;

  const OneovaSmoothSwitcher({super.key, required this.child, this.duration = const Duration(milliseconds: 320)});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.passthrough,
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) {
        return AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            final v = animation.value;
            return Opacity(
              opacity: v,
              child: ImageFiltered(
                enabled: v < 0.995,
                imageFilter: ui.ImageFilter.blur(sigmaX: (1 - v) * 7, sigmaY: (1 - v) * 7, tileMode: TileMode.decal),
                child: child,
              ),
            );
          },
        );
      },
      child: child,
    );
  }
}

/// Shimmering placeholder rows (avatar + two lines) for list-style loading.
class OneovaSkeleton extends StatefulWidget {
  final int rows;
  final EdgeInsetsGeometry padding;
  final bool avatar;

  const OneovaSkeleton({
    super.key,
    this.rows = 7,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 12),
    this.avatar = true,
  });

  @override
  State<OneovaSkeleton> createState() => _OneovaSkeletonState();
}

class _OneovaSkeletonState extends State<OneovaSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.surfaceMid;
    final hi = context.border;
    return OneovaBlurReveal(
      duration: const Duration(milliseconds: 300),
      delay: const Duration(milliseconds: 120), // quick loads never flash a skeleton
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final dx = -1.0 + 3.0 * _c.value;
          Widget bar(double w, double h, {bool round = false}) => Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(round ? 999 : AppRadius.sm),
                  gradient: LinearGradient(
                    begin: Alignment(dx - 1, 0),
                    end: Alignment(dx, 0),
                    colors: [base, hi, base],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              );
          return ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: widget.padding,
            itemCount: widget.rows,
            itemBuilder: (context, i) {
              final line = 120.0 + (i * 37 % 90);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    if (widget.avatar) ...[bar(44, 44, round: true), const SizedBox(width: 12)],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [bar(line, 12), const SizedBox(height: 8), bar(line + 70, 10)],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

extension AsyncSmooth<T> on AsyncValue<T> {
  /// Same contract as [AsyncValue.when], but loading -> data -> error cross-fade
  /// with a soft blur instead of swapping abruptly. Only use where the result
  /// is a box widget (not a sliver).
  Widget smoothWhen({
    required Widget Function(T data) data,
    required Widget Function() loading,
    required Widget Function(Object error, StackTrace stack) error,
  }) {
    final Widget built = when(
      data: (d) => KeyedSubtree(key: const ValueKey('data'), child: data(d)),
      loading: () => KeyedSubtree(key: const ValueKey('loading'), child: loading()),
      error: (e, st) => KeyedSubtree(key: const ValueKey('error'), child: error(e, st)),
    );
    return OneovaSmoothSwitcher(child: built);
  }
}
