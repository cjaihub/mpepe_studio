import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/inbox/providers/presence_service.dart';
import '../theme/app_theme.dart';

/// Highly-polished, real-time live presence dot for user avatars and chat headers.
///
/// Features:
/// - Online: Emerald green dot with animated luminous pulse ring.
/// - In-Call: Violet badge with phone icon.
/// - Live: Oneova brandPink dot with energetic glow.
/// - Recently Active: Subtle amber rim.
class LiveUserPresenceDot extends StatefulWidget {
  final UserPresence presence;
  final double size;
  final Color? borderColor;
  final bool animate;

  const LiveUserPresenceDot({
    super.key,
    required this.presence,
    this.size = 11.0,
    this.borderColor,
    this.animate = true,
  });

  @override
  State<LiveUserPresenceDot> createState() => _LiveUserPresenceDotState();
}

class _LiveUserPresenceDotState extends State<LiveUserPresenceDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.animate && widget.presence.isOnline) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant LiveUserPresenceDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.presence.isOnline && !oldWidget.presence.isOnline) {
      if (widget.animate) _pulseController.repeat(reverse: true);
    } else if (!widget.presence.isOnline && oldWidget.presence.isOnline) {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.presence.status;
    if (status == PresenceStatus.offline) {
      return const SizedBox.shrink();
    }

    final border = widget.borderColor ?? context.surface;

    if (status == PresenceStatus.inCall) {
      return Container(
        width: widget.size * 1.35,
        height: widget.size * 1.35,
        decoration: BoxDecoration(
          color: const Color(0xFF8B5CF6), // Violet call indicator
          shape: BoxShape.circle,
          border: Border.all(color: border, width: 2.0),
          boxShadow: const [
            BoxShadow(color: Color(0x668B5CF6), blurRadius: 6),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.phone_in_talk_rounded,
          size: widget.size * 0.75,
          color: Colors.white,
        ),
      );
    }

    final Color dotColor;
    final Color glowColor;

    switch (status) {
      case PresenceStatus.online:
        dotColor = const Color(0xFF10B981); // Emerald green
        glowColor = const Color(0x8810B981);
        break;
      case PresenceStatus.inLive:
        dotColor = AppColors.brandPink;
        glowColor = AppColors.brandPink.withValues(alpha: 0.55);
        break;
      case PresenceStatus.recentlyActive:
        dotColor = const Color(0xFFF59E0B); // Amber
        glowColor = const Color(0x66F59E0B);
        break;
      default:
        return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = widget.animate && widget.presence.isOnline
            ? 1.0 + (_pulseController.value * 0.18)
            : 1.0;
        final spread = widget.animate && widget.presence.isOnline
            ? 1.0 + (_pulseController.value * 3.5)
            : 1.5;

        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              border: Border.all(color: border, width: 2.0),
              boxShadow: [
                BoxShadow(
                  color: glowColor,
                  blurRadius: spread,
                  spreadRadius: spread * 0.4,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Compact presence pill displaying dot + live textual status.
class LivePresencePill extends StatelessWidget {
  final UserPresence presence;
  final Color? textColor;

  const LivePresencePill({
    super.key,
    required this.presence,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    if (presence.status == PresenceStatus.offline) {
      return Text(
        presence.label,
        style: GoogleFonts.inter(
          fontSize: 11.5,
          color: textColor ?? context.textMuted,
          fontWeight: FontWeight.w400,
        ),
      );
    }

    final fg = textColor ?? (presence.isOnline ? const Color(0xFF10B981) : context.textSecondary);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        LiveUserPresenceDot(
          presence: presence,
          size: 7.5,
          animate: presence.isOnline,
        ),
        const SizedBox(width: 5),
        Text(
          presence.label,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            color: fg,
            fontWeight: presence.isOnline ? FontWeight.w600 : FontWeight.w500,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}

