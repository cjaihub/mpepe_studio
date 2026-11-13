import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../ova_computer_live.dart';
import 'tactile.dart';

/// Ova Live deck: talk to Ova, it watches the live screen and works the
/// mouse and keyboard with you. A breathing orb shows listening / thinking /
/// speaking / acting; the transcript and the last action sit below.
class OvaLiveDeck extends ConsumerStatefulWidget {
  const OvaLiveDeck({
    super.key,
    required this.enabled,
    required this.screenLive,
    required this.onStart,
  });

  final bool enabled;
  final bool screenLive;
  final VoidCallback onStart;

  @override
  ConsumerState<OvaLiveDeck> createState() => _OvaLiveDeckState();
}

class _OvaLiveDeckState extends ConsumerState<OvaLiveDeck> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();
  final _text = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _pulse.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _phaseLabel(OvaComputerLiveState s) => switch (s.phase) {
        OvaLivePhase.off => 'Tap to start Ova Live',
        OvaLivePhase.connecting => 'Connecting…',
        OvaLivePhase.listening => s.seeing ? 'Listening · watching your screen' : 'Listening',
        OvaLivePhase.thinking => 'Thinking…',
        OvaLivePhase.speaking => 'Speaking',
        OvaLivePhase.acting => s.lastAction ?? 'Working…',
        OvaLivePhase.error => s.error ?? 'Something went wrong',
      };

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(ovaComputerLiveProvider);
    final notifier = ref.read(ovaComputerLiveProvider.notifier);
    final active = s.active;

    ref.listen(ovaComputerLiveProvider.select((x) => x.lines.length), (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    });

    return Container(
      decoration: Tactile.tile(context),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: !widget.enabled
                    ? null
                    : () {
                        HapticFeedback.mediumImpact();
                        if (active) {
                          notifier.stop();
                        } else {
                          widget.onStart();
                        }
                      },
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => CustomPaint(
                    size: const Size.square(64),
                    painter: _OrbPainter(
                      t: _pulse.value,
                      phase: s.phase,
                      idle: context.border,
                      core: context.surface,
                    ),
                    child: SizedBox.square(
                      dimension: 64,
                      child: Icon(
                        active ? Icons.stop_rounded : Icons.auto_awesome_rounded,
                        color: active ? AppColors.brandWhite : AppColors.brandBlue,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ova Live',
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _phaseLabel(s),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: s.phase == OvaLivePhase.error ? AppColors.brandPink : context.textSecondary,
                      ),
                    ),
                    if (!widget.screenLive)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          'Turn on the live screen so Ova can see.',
                          style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.brandPink),
                        ),
                      ),
                  ],
                ),
              ),
              if (active)
                IconButton(
                  tooltip: s.muted ? 'Unmute mic' : 'Mute mic',
                  onPressed: notifier.toggleMute,
                  icon: Icon(
                    s.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    color: s.muted ? AppColors.brandPink : context.textPrimary,
                    size: 20,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              decoration: Tactile.recessed(context, radius: AppRadius.md),
              child: s.lines.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Try: “open Safari and look up the weather”, “scroll down”, '
                          '“click the blue button”, “turn the volume to 30”.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted, height: 1.4),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(10),
                      itemCount: s.lines.length,
                      itemBuilder: (context, i) {
                        final l = s.lines[i];
                        return Align(
                          alignment: l.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            constraints: const BoxConstraints(maxWidth: 280),
                            decoration: BoxDecoration(
                              color: l.fromUser
                                  ? AppColors.brandBlue
                                  : context.surface,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              border: l.fromUser ? null : Border.all(color: context.border, width: 1.0),
                            ),
                            child: Text(
                              l.text,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                height: 1.35,
                                color: l.fromUser ? AppColors.brandWhite : context.textPrimary,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          if (active) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    textInputAction: TextInputAction.send,
                    style: GoogleFonts.inter(fontSize: 12.5, color: context.textPrimary),
                    onSubmitted: (v) {
                      notifier.say(v);
                      _text.clear();
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Or type to Ova…',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: BorderSide(color: context.border),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: AppColors.brandBlue),
                  onPressed: () {
                    notifier.say(_text.text);
                    _text.clear();
                  },
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18, color: AppColors.brandWhite),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.t, required this.phase, required this.idle, required this.core});
  final double t;
  final OvaLivePhase phase;
  final Color idle;
  final Color core;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final active = phase != OvaLivePhase.off && phase != OvaLivePhase.error;
    final color = switch (phase) {
      OvaLivePhase.speaking => AppColors.brandPink,
      OvaLivePhase.acting => AppColors.brandPink,
      _ => AppColors.brandBlue,
    };
    if (active) {
      final speed = phase == OvaLivePhase.speaking ? 2.0 : 1.0;
      for (var i = 0; i < 2; i++) {
        final k = ((t * speed) + i / 2) % 1.0;
        canvas.drawCircle(
          c,
          r * (0.72 + 0.3 * k),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = color.withValues(alpha: 0.5 * (1 - k)),
        );
      }
      final wobble = 1 + 0.04 * math.sin(t * 2 * math.pi * (phase == OvaLivePhase.speaking ? 3 : 1));
      canvas.drawCircle(
        c,
        r * 0.68 * wobble,
        Paint()
          ..shader = RadialGradient(
            colors: [Color.lerp(color, AppColors.brandWhite, 0.2)!, color],
          ).createShader(Rect.fromCircle(center: c, radius: r * 0.7)),
      );
    } else {
      canvas.drawCircle(c, r * 0.68, Paint()..color = core);
      canvas.drawCircle(
        c,
        r * 0.68,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = idle,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => old.t != t || old.phase != phase;
}
