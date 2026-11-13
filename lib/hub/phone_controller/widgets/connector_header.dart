import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import 'tactile.dart';

enum ControllerLinkState { offline, connecting, linked }

/// The phone ↔ computer link drawn as a piece of hardware: a matte hub on a
/// soft tile, a knob for each end, a cable sunk in a groove that carries live
/// packets, a labelled port, and status LEDs for link, fast lane and
/// encryption. Tapping the hub while offline reconnects.
class ConnectorHeader extends StatefulWidget {
  const ConnectorHeader({
    super.key,
    required this.computerName,
    required this.linkState,
    required this.fastLane,
    this.rttMs,
    this.onRetry,
  });

  final String computerName;
  final ControllerLinkState linkState;
  final bool fastLane;
  final int? rttMs;
  final VoidCallback? onRetry;

  @override
  State<ConnectorHeader> createState() => _ConnectorHeaderState();
}

class _ConnectorHeaderState extends State<ConnectorHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    _syncFlow();
  }

  @override
  void didUpdateWidget(covariant ConnectorHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.linkState != widget.linkState) {
      _syncFlow();
      if (widget.linkState == ControllerLinkState.linked) {
        HapticFeedback.mediumImpact();
      }
    }
  }

  void _syncFlow() {
    if (widget.linkState == ControllerLinkState.offline) {
      _flow.stop();
    } else if (!_flow.isAnimating) {
      _flow.repeat();
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final linked = widget.linkState == ControllerLinkState.linked;
    final offline = widget.linkState == ControllerLinkState.offline;
    final status = switch (widget.linkState) {
      ControllerLinkState.linked => 'Linked',
      ControllerLinkState.connecting => 'Connecting…',
      ControllerLinkState.offline => 'Not reachable',
    };
    final micro = GoogleFonts.inter(
      fontSize: 9,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.9,
      color: context.textMuted,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: offline ? widget.onRetry : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: Tactile.tile(context),
        child: Column(
          children: [
            Row(
              children: [
                _LedLabel(on: linked, label: 'LINK', style: micro),
                const SizedBox(width: 10),
                _LedLabel(
                  on: linked && widget.fastLane,
                  label: 'FAST',
                  style: micro,
                ),
                const SizedBox(width: 10),
                _LedLabel(on: linked, label: 'SECURE', style: micro),
                const Spacer(),
                _Readout(state: widget.linkState, rttMs: widget.rttMs),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: Tactile.raised(context, radius: AppRadius.lg + 2),
              child: Row(
                children: [
                  _Knob(icon: Icons.smartphone_rounded, lit: linked),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: _flow,
                            builder: (context, _) => CustomPaint(
                              painter: _CablePainter(
                                t: _flow.value,
                                state: widget.linkState,
                                groove: Color.lerp(
                                  context.bg,
                                  AppColors.brandBlack,
                                  context.isDark ? 0.4 : 0.06,
                                )!,
                                idle: context.border,
                              ),
                            ),
                          ),
                        ),
                        _Port(state: widget.linkState, style: micro),
                      ],
                    ),
                  ),
                  _Knob(icon: Icons.laptop_mac_rounded, lit: linked),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'This phone',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: context.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: widget.computerName,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: context.textPrimary,
                          ),
                        ),
                        TextSpan(
                          text: '  ·  $status',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: linked
                                ? AppColors.brandBlue
                                : context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LedLabel extends StatelessWidget {
  const _LedLabel({required this.on, required this.label, required this.style});
  final bool on;
  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusLed(on: on, size: 5),
        const SizedBox(width: 5),
        Text(
          label,
          style: on ? style.copyWith(color: context.textSecondary) : style,
        ),
      ],
    );
  }
}

/// Recessed latency readout, like a small LCD window.
class _Readout extends StatelessWidget {
  const _Readout({required this.state, required this.rttMs});
  final ControllerLinkState state;
  final int? rttMs;

  @override
  Widget build(BuildContext context) {
    final linked = state == ControllerLinkState.linked;
    final text = switch (state) {
      ControllerLinkState.linked => rttMs == null ? '-- ms' : '$rttMs ms',
      ControllerLinkState.connecting => 'sync…',
      ControllerLinkState.offline => 'offline',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: Tactile.recessed(context, radius: AppRadius.sm - 2),
      child: Text(
        text,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: linked ? AppColors.brandBlue : context.textMuted,
        ),
      ),
    );
  }
}

/// Round tactile node at each end of the hub.
class _Knob extends StatelessWidget {
  const _Knob({required this.icon, required this.lit});
  final IconData icon;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: Tactile.raised(
            context,
            circle: true,
            borderColor: lit
                ? AppColors.brandBlue.withValues(alpha: 0.55)
                : null,
          ),
          child: Icon(
            icon,
            size: 18,
            color: lit ? AppColors.brandBlue : context.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        StatusLed(on: lit, size: 4),
      ],
    );
  }
}

/// Labelled port where the cable lands.
class _Port extends StatelessWidget {
  const _Port({required this.state, required this.style});
  final ControllerLinkState state;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final linked = state == ControllerLinkState.linked;
    final label = state == ControllerLinkState.offline
        ? 'TAP TO RETRY'
        : 'OVA LINK';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: Tactile.raised(context, radius: AppRadius.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusLed(on: linked, size: 5),
          const SizedBox(width: 5),
          Text(
            label,
            style: style.copyWith(
              color: linked ? context.textPrimary : context.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _CablePainter extends CustomPainter {
  _CablePainter({
    required this.t,
    required this.state,
    required this.groove,
    required this.idle,
  });
  final double t;
  final ControllerLinkState state;
  final Color groove;
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2 - 2;
    const inset = 6.0;
    final left = Offset(inset, y);
    final right = Offset(size.width - inset, y);

    // Groove milled into the hub.
    canvas.drawLine(
      left,
      right,
      Paint()
        ..color = groove
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );

    if (state == ControllerLinkState.offline) {
      final p = Paint()
        ..color = idle
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(left, Offset(size.width * 0.22, y), p);
      canvas.drawLine(Offset(size.width * 0.78, y), right, p);
      return;
    }

    final linked = state == ControllerLinkState.linked;
    canvas.drawLine(
      left,
      right,
      Paint()
        ..color = linked ? AppColors.brandBlue : idle
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    if (linked) {
      // Input packets flow phone → computer; replies return in pink.
      for (var i = 0; i < 3; i++) {
        final k = (t + i / 3) % 1.0;
        final x = left.dx + (right.dx - left.dx) * k;
        final fade = (1 - (2 * k - 1).abs()).clamp(0.0, 1.0);
        final c = Offset(x, y);
        canvas.drawCircle(
          c,
          5,
          Paint()
            ..color = AppColors.brandBlue.withValues(alpha: 0.25 * fade)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawCircle(
          c,
          2,
          Paint()
            ..color = AppColors.brandWhite.withValues(alpha: 0.5 + 0.5 * fade),
        );
      }
      final back = 1 - ((t * 0.5 + 0.25) % 1.0);
      final bc = Offset(left.dx + (right.dx - left.dx) * back, y);
      canvas.drawCircle(
        bc,
        5,
        Paint()
          ..color = AppColors.brandPink.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(bc, 1.8, Paint()..color = AppColors.brandPink);
    } else {
      final x = left.dx + (right.dx - left.dx) * Curves.easeInOut.transform(t);
      canvas.drawCircle(
        Offset(x, y),
        2.4,
        Paint()..color = AppColors.brandBlue.withValues(alpha: 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CablePainter old) =>
      old.t != t ||
      old.state != state ||
      old.groove != groove ||
      old.idle != idle;
}
