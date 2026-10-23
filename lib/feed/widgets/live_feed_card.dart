import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../backend/live/models/live_models.dart';
import '../../backend/live/services/live_service.dart';
import '../../shared/theme/app_theme.dart';

/// A live session slotted into the vertical reel feed.
class LiveFeedSlot {
  final LiveStream initial;
  LiveFeedSlot(this.initial);
  String get streamId => initial.id;
}

/// Full-screen feed page for a live session. It follows the stream document,
/// so it shows LIVE with a Join button while the host is on air and flips to
/// "Live ended" (with how long it lasted) the moment they stop.
class LiveFeedCard extends ConsumerWidget {
  final LiveStream initial;
  final bool isActive;
  final VoidCallback onSkip;

  const LiveFeedCard({super.key, required this.initial, required this.isActive, required this.onSkip});

  bool _isEnded(LiveStream s) => s.status == LiveStreamStatus.ended || s.status == LiveStreamStatus.abandoned;

  void _join(BuildContext context, LiveStream s) {
    HapticFeedback.mediumImpact();
    context.push('/live/viewer/${s.id}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(liveStreamProvider(initial.id));
    // A deleted stream doc is treated as ended.
    final stream = async.hasValue ? async.value : initial;
    final s = stream ?? initial;
    final ended = stream == null || _isEnded(s);
    final reconnecting = !ended && s.status == LiveStreamStatus.reconnecting;
    final name = s.hostDisplayName.isNotEmpty ? s.hostDisplayName : 'Live creator';

    return GestureDetector(
      onTap: ended ? null : () => _join(context, s),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Backdrop(avatarUrl: s.hostAvatarUrl, dimmed: ended),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 150, 28, 90),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _HostAvatar(url: s.hostAvatarUrl, name: name, live: !ended, animate: isActive),
                  const SizedBox(height: 16),
                  _StatusBadge(ended: ended, reconnecting: reconnecting, viewers: s.viewerCount),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3),
                  ),
                  if (s.title.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      s.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 13.5, height: 1.35, color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    ended ? _endedLine(s) : 'Started ${timeago.format(s.createdAt)}${s.category.isNotEmpty ? ' · ${s.category}' : ''}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 22),
                  if (!ended)
                    _PrimaryButton(
                      label: 'Tap to join live',
                      icon: Icons.sensors_rounded,
                      color: AppColors.brandPink,
                      onTap: () => _join(context, s),
                    )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scaleXY(begin: 1, end: 1.04, duration: 900.ms, curve: Curves.easeInOut)
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PrimaryButton(
                          label: 'View profile',
                          icon: Icons.person_outline_rounded,
                          color: AppColors.brandBlue,
                          onTap: () => context.push('/profile/${s.hostId}'),
                        ),
                        const SizedBox(width: 10),
                        _PrimaryButton(
                          label: 'Next',
                          icon: Icons.keyboard_arrow_down_rounded,
                          color: Colors.white.withValues(alpha: 0.14),
                          onTap: onSkip,
                        ),
                      ],
                    ),
                  const SizedBox(height: 14),
                  Text(
                    ended ? 'This live has finished' : 'Swipe up to keep scrolling',
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ],
              ).animate(key: ValueKey(ended)).fadeIn(duration: 260.ms).slideY(begin: 0.04, end: 0),
            ),
          ),
        ],
      ),
    );
  }

  String _endedLine(LiveStream s) {
    final endedAt = s.endedAt;
    if (endedAt == null) return 'Live ended';
    final d = endedAt.difference(s.createdAt);
    final lasted = d.inHours > 0 ? '${d.inHours}h ${d.inMinutes % 60}m' : (d.inMinutes > 0 ? '${d.inMinutes}m' : '${d.inSeconds}s');
    return 'Lasted $lasted · ended ${timeago.format(endedAt)}';
  }
}

class _Backdrop extends StatelessWidget {
  final String avatarUrl;
  final bool dimmed;
  const _Backdrop({required this.avatarUrl, required this.dimmed});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.brandBlue, AppColors.darkBackground],
            ),
          ),
        ),
        if (avatarUrl.isNotEmpty)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Image.network(avatarUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
          ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          color: AppColors.darkBackground.withValues(alpha: dimmed ? 0.78 : 0.55),
        ),
      ],
    );
  }
}

class _HostAvatar extends StatelessWidget {
  final String url;
  final String name;
  final bool live;
  final bool animate;
  const _HostAvatar({required this.url, required this.name, required this.live, required this.animate});

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: live ? AppColors.premiumGradient : null,
        color: live ? null : Colors.white.withValues(alpha: 0.2),
      ),
      child: CircleAvatar(
        radius: 44,
        backgroundColor: AppColors.darkSurfaceHighlight,
        backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
        child: url.isEmpty
            ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: GoogleFonts.inter(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white))
            : null,
      ),
    );
    if (!live || !animate) return Opacity(opacity: live ? 1 : 0.6, child: avatar);

    // Broadcast "ripple" rings while the host is on air.
    return SizedBox(
      width: 130,
      height: 130,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final delay in [0, 700])
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.7), width: 1.5),
              ),
            )
                .animate(onPlay: (c) => c.repeat(), delay: delay.ms)
                .scaleXY(begin: 1, end: 1.3, duration: 1400.ms, curve: Curves.easeOut)
                .fadeOut(duration: 1400.ms),
          avatar,
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool ended;
  final bool reconnecting;
  final int viewers;
  const _StatusBadge({required this.ended, required this.reconnecting, required this.viewers});

  @override
  Widget build(BuildContext context) {
    if (ended) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.0),
        ),
        child: Text('LIVE ENDED',
            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.9, color: Colors.white.withValues(alpha: 0.8))),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: AppColors.brandPink, borderRadius: BorderRadius.circular(AppRadius.xs)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .fade(begin: 0.3, end: 1, duration: 600.ms),
              const SizedBox(width: 5),
              Text(reconnecting ? 'RECONNECTING' : 'LIVE',
                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.9, color: Colors.white)),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(AppRadius.xs)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.visibility_rounded, size: 11, color: Colors.white),
              const SizedBox(width: 4),
              Text(_compact(viewers), style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

String _compact(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}
