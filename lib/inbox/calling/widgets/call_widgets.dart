import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/calling/models/call_model.dart';
import '../../../backend/calling/providers/active_call_controller.dart';
import '../../../backend/calling/providers/call_media_service.dart';
import '../../../shared/theme/app_theme.dart';

/// Round avatar with initials fallback.
class CallAvatar extends StatelessWidget {
  final String? url;
  final String name;
  final double size;

  const CallAvatar({super.key, this.url, required this.name, this.size = 88});

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.brandBlue, shape: BoxShape.circle),
      child: Text(
        initials,
        style: GoogleFonts.inter(
          color: AppColors.brandWhite,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}

/// Avatar with a soft pulsing halo while ringing.
class RingingAvatar extends StatelessWidget {
  final String? url;
  final String name;
  final bool pulsing;
  final double size;

  const RingingAvatar({super.key, this.url, required this.name, this.pulsing = true, this.size = 96});

  @override
  Widget build(BuildContext context) {
    final avatar = CallAvatar(url: url, name: name, size: size);
    if (!pulsing) return avatar;
    return Stack(
      alignment: Alignment.center,
      children: [
        for (final delay in [0, 700])
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.55), width: 1),
            ),
          )
              .animate(onPlay: (c) => c.repeat(), delay: delay.ms)
              .scale(begin: const Offset(1, 1), end: const Offset(1.7, 1.7), duration: 1400.ms, curve: Curves.easeOut)
              .fadeOut(duration: 1400.ms),
        avatar,
      ],
    );
  }
}

/// mm:ss (or h:mm:ss) since [since], ticking every second.
class CallTimerText extends StatefulWidget {
  final DateTime since;
  final TextStyle? style;

  const CallTimerText({super.key, required this.since, this.style});

  @override
  State<CallTimerText> createState() => _CallTimerTextState();
}

class _CallTimerTextState extends State<CallTimerText> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now().difference(widget.since);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Text(
      h > 0 ? '$h:$m:$s' : '$m:$s',
      style: widget.style,
    );
  }
}

/// Status line for the current phase ("Ringing…", "02:14", "Busy" …).
String callStatusLabel(ActiveCallState s) {
  switch (s.phase) {
    case CallPhase.idle:
      return '';
    case CallPhase.outgoing:
      return s.remoteParticipants.isEmpty ? 'Calling…' : 'Ringing…';
    case CallPhase.incoming:
      final video = s.call?.isVideo ?? false;
      final group = s.call?.isGroup ?? false;
      return 'Incoming ${group ? 'group ' : ''}${video ? 'video' : 'voice'} call';
    case CallPhase.connecting:
      return 'Connecting…';
    case CallPhase.reconnecting:
      return 'Reconnecting…';
    case CallPhase.connected:
      return '';
    case CallPhase.ended:
      return callEndLabel(s.endReason);
  }
}

String callEndLabel(CallEndReason? r) {
  switch (r) {
    case CallEndReason.declined:
      return 'Declined';
    case CallEndReason.busy:
      return 'Busy on another call';
    case CallEndReason.noAnswer:
      return 'No answer';
    case CallEndReason.failed:
      return 'Call failed';
    case CallEndReason.cancelled:
      return 'Call cancelled';
    case CallEndReason.hangup:
    case null:
      return 'Call ended';
  }
}

IconData audioRouteIcon(AudioRoute r) {
  switch (r) {
    case AudioRoute.speaker:
      return Icons.volume_up_rounded;
    case AudioRoute.earpiece:
      return Icons.phone_in_talk_rounded;
    case AudioRoute.bluetooth:
      return Icons.bluetooth_audio_rounded;
    case AudioRoute.wired:
      return Icons.headset_rounded;
  }
}

String audioRouteLabel(AudioRoute r) {
  switch (r) {
    case AudioRoute.speaker:
      return 'Speaker';
    case AudioRoute.earpiece:
      return 'Phone';
    case AudioRoute.bluetooth:
      return 'Bluetooth';
    case AudioRoute.wired:
      return 'Headphones';
  }
}

/// Round call control with a tiny caption.
class CallControlButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final Color? fill;
  final Color? iconColor;
  final double size;
  final bool onDark;

  const CallControlButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
    this.fill,
    this.iconColor,
    this.size = 52,
    this.onDark = false,
  });

  @override
  State<CallControlButton> createState() => _CallControlButtonState();
}

class _CallControlButtonState extends State<CallControlButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final idleFill = widget.onDark
        ? AppColors.brandWhite.withValues(alpha: 0.14)
        : context.surfaceMid;
    final fill = widget.fill ?? (widget.active ? AppColors.brandBlue : idleFill);
    final fg = widget.iconColor ??
        (widget.active || widget.fill != null || widget.onDark ? AppColors.brandWhite : context.textPrimary);
    final caption = widget.onDark ? AppColors.brandWhite.withValues(alpha: 0.85) : context.textSecondary;
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                widget.onTap!();
              },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: _down ? 0.92 : 1,
              duration: 150.ms,
              child: AnimatedContainer(
                duration: 180.ms,
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: widget.onTap == null ? fill.withValues(alpha: 0.4) : fill,
                  shape: BoxShape.circle,
                  border: widget.onDark || widget.fill != null || widget.active
                      ? null
                      : Border.all(color: context.border, width: 1),
                ),
                child: Icon(widget.icon, color: fg, size: widget.size * 0.44),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.label,
              style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w500, color: caption),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small chip describing call encryption. Media is always DTLS-SRTP between
/// the devices (TURN relays only see ciphertext). "End-to-end encrypted" is
/// shown only once frame encryption with Oneova Shield keys is on for every
/// peer, because DTLS keys are exchanged through Oneova's signaling.
class CallEncryptedChip extends StatelessWidget {
  final bool onDark;
  final bool frameEncrypted;
  const CallEncryptedChip({super.key, this.onDark = false, this.frameEncrypted = false});

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? AppColors.brandWhite.withValues(alpha: 0.8) : context.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_rounded, size: 11, color: fg),
        const SizedBox(width: 4),
        Text(
          frameEncrypted ? 'End-to-end encrypted' : 'Encrypted in transit',
          style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w500, color: fg),
        ),
      ],
    );
  }
}

/// Picks the display name/avatar for the "other side" of a call.
({String name, String? avatar}) callHeadline(ActiveCallState s, {String? fallbackName, String? fallbackAvatar}) {
  final call = s.call;
  if (call == null) return (name: fallbackName ?? 'Oneova call', avatar: fallbackAvatar);
  final others = s.remoteParticipants;
  if (call.isGroup) {
    if (call.title != null && call.title!.isNotEmpty) return (name: call.title!, avatar: null);
    final names = others.map((p) => p.name.split(' ').first).where((n) => n.isNotEmpty).take(3).join(', ');
    return (name: names.isEmpty ? 'Group call' : names, avatar: null);
  }
  if (others.isNotEmpty && others.first.name.isNotEmpty) {
    return (name: others.first.name, avatar: others.first.avatar);
  }
  return (name: fallbackName ?? call.callerName, avatar: fallbackAvatar ?? call.callerAvatar);
}
