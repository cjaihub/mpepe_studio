import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/live/models/live_models.dart';
import '../../../shared/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CLASSIC LIVE — shared overlay pieces for the full-screen vertical live
// (viewer + host). Everything here sits on top of live video, so it uses the
// fixed brandWhite / brandBlack overlay tokens instead of theme surfaces.
// ─────────────────────────────────────────────────────────────────────────────

const Color _onVideo = AppColors.brandWhite;
Color _scrim([double a = 0.35]) => AppColors.brandBlack.withValues(alpha: a);

String compactCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

/// Full-bleed live video, or a blurred avatar while connecting / camera off.
class ClassicVideoBackdrop extends StatelessWidget {
  final RTCVideoRenderer? renderer;
  final bool hasVideo;
  final bool mirror;
  final String avatarUrl;
  final String statusText;

  const ClassicVideoBackdrop({
    super.key,
    required this.renderer,
    required this.hasVideo,
    required this.avatarUrl,
    this.mirror = false,
    this.statusText = 'Connecting to live…',
  });

  @override
  Widget build(BuildContext context) {
    if (hasVideo && renderer != null) {
      return RTCVideoView(
        renderer!,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        mirror: mirror,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.brandBlack),
        if (avatarUrl.isNotEmpty)
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Opacity(
              opacity: 0.55,
              child: Image.network(avatarUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink()),
            ),
          ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClassicAvatar(url: avatarUrl, size: 76, ring: true),
              const SizedBox(height: 14),
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _onVideo.withValues(alpha: 0.8)),
              ),
              const SizedBox(height: 10),
              Text(statusText,
                  style: GoogleFonts.inter(
                      color: _onVideo.withValues(alpha: 0.85),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}

class ClassicAvatar extends StatelessWidget {
  final String url;
  final double size;
  final bool ring;

  const ClassicAvatar(
      {super.key, required this.url, this.size = 34, this.ring = false});

  @override
  Widget build(BuildContext context) {
    final img = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.brandBlue.withValues(alpha: 0.35),
        image: url.isNotEmpty
            ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover)
            : null,
      ),
      child: url.isEmpty
          ? Icon(Icons.person_rounded, color: _onVideo, size: size * 0.55)
          : null,
    );
    if (!ring) return img;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
            colors: [AppColors.brandPink, AppColors.brandBlue]),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
            shape: BoxShape.circle, color: AppColors.brandBlack),
        child: img,
      ),
    );
  }
}

/// Pulsing pink "LIVE" tag.
class ClassicLiveBadge extends StatelessWidget {
  const ClassicLiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.brandPink,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration:
                const BoxDecoration(color: _onVideo, shape: BoxShape.circle),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fade(begin: 1, end: 0.25, duration: 700.ms),
          const SizedBox(width: 4),
          Text('LIVE',
              style: GoogleFonts.inter(
                  color: _onVideo,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8)),
        ],
      ),
    );
  }
}

/// Top-left host capsule: avatar · name · likes · optional Follow.
class ClassicHostPill extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final int likes;
  final bool showFollow;
  final bool isFollowing;
  final VoidCallback? onFollow;
  final VoidCallback? onTap;

  const ClassicHostPill({
    super.key,
    required this.name,
    required this.avatarUrl,
    required this.likes,
    this.showFollow = false,
    this.isFollowing = false,
    this.onFollow,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(3, 3, 4, 3),
        decoration: BoxDecoration(
          color: _scrim(0.38),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClassicAvatar(url: avatarUrl, size: 32),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          color: _onVideo,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.favorite_rounded,
                          color: AppColors.brandPink, size: 10),
                      const SizedBox(width: 3),
                      Text(compactCount(likes),
                          style: GoogleFonts.inter(
                              color: _onVideo.withValues(alpha: 0.8),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (showFollow)
              AnimatedSwitcher(
                duration: 220.ms,
                transitionBuilder: (c, a) =>
                    ScaleTransition(scale: a, child: c),
                child: isFollowing
                    ? Container(
                        key: const ValueKey('following'),
                        width: 30,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _onVideo.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                        child: const Icon(Icons.check_rounded,
                            color: _onVideo, size: 16),
                      )
                    : GestureDetector(
                        key: const ValueKey('follow'),
                        onTap: onFollow,
                        child: Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.brandPink,
                            borderRadius:
                                BorderRadius.circular(AppRadius.full),
                          ),
                          child: Text('Follow',
                              style: GoogleFonts.inter(
                                  color: _onVideo,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
              )
            else
              const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

/// Eye + viewer count capsule.
class ClassicViewerBadge extends StatelessWidget {
  final int count;
  const ClassicViewerBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: _scrim(0.38),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.remove_red_eye_outlined, color: _onVideo, size: 13),
          const SizedBox(width: 4),
          Text(compactCount(count),
              style: GoogleFonts.inter(
                  color: _onVideo,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Round translucent icon button for the overlay.
class ClassicRoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color? color;
  final Color? background;
  final String? tooltip;

  const ClassicRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 38,
    this.color,
    this.background,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = _Pressable(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background ?? _scrim(0.38),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color ?? _onVideo, size: size * 0.5),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _Pressable({required this.child, required this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.9 : 1,
        duration: const Duration(milliseconds: 150),
        child: widget.child,
      ),
    );
  }
}

/// Bottom-left comment stream. [comments] is newest-first (Firestore order).
class ClassicCommentList extends StatelessWidget {
  final List<LiveComment> comments;
  final String hostId;
  final int maxVisible;

  const ClassicCommentList({
    super.key,
    required this.comments,
    required this.hostId,
    this.maxVisible = 30,
  });

  @override
  Widget build(BuildContext context) {
    final items = comments.take(maxVisible).toList();
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, AppColors.brandBlack],
        stops: [0, 0.28],
      ).createShader(r),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.only(top: 40),
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final c = items[i];
          return _CommentRow(
            key: ValueKey(c.id),
            comment: c,
            isHost: c.authorId == hostId,
          );
        },
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  final LiveComment comment;
  final bool isHost;
  const _CommentRow({super.key, required this.comment, required this.isHost});

  @override
  Widget build(BuildContext context) {
    final gift = comment.isGift;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
          decoration: BoxDecoration(
            color: gift
                ? AppColors.brandPink.withValues(alpha: 0.32)
                : _scrim(0.28),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClassicAvatar(url: comment.authorAvatarUrl, size: 22),
              const SizedBox(width: 7),
              Flexible(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: comment.authorDisplayName,
                      style: GoogleFonts.inter(
                          color: _onVideo.withValues(alpha: 0.72),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700),
                    ),
                    if (isHost)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue,
                            borderRadius:
                                BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text('HOST',
                              style: GoogleFonts.inter(
                                  color: _onVideo,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6)),
                        ),
                      ),
                    TextSpan(
                      text: '  ${comment.text}',
                      style: GoogleFonts.inter(
                          color: _onVideo,
                          fontSize: 12.5,
                          fontWeight: gift ? FontWeight.w700 : FontWeight.w500,
                          height: 1.3),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 250.ms).slideX(begin: -0.08, end: 0);
  }
}

/// Hearts that float up from the like button. Bump [bursts] to spawn one.
class ClassicFloatingHearts extends StatefulWidget {
  final int bursts;
  const ClassicFloatingHearts({super.key, required this.bursts});

  @override
  State<ClassicFloatingHearts> createState() => _ClassicFloatingHeartsState();
}

class _ClassicFloatingHeartsState extends State<ClassicFloatingHearts> {
  final _rng = math.Random();
  final List<_Heart> _hearts = [];
  int _seq = 0;

  @override
  void didUpdateWidget(covariant ClassicFloatingHearts old) {
    super.didUpdateWidget(old);
    final add = (widget.bursts - old.bursts).clamp(0, 6);
    for (var i = 0; i < add; i++) {
      _hearts.add(_Heart(
        id: _seq++,
        dx: (_rng.nextDouble() - 0.5) * 50,
        color: _rng.nextBool() ? AppColors.brandPink : AppColors.brandBlue,
        size: 20 + _rng.nextDouble() * 12,
      ));
    }
    if (_hearts.length > 24) _hearts.removeRange(0, _hearts.length - 24);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: 90,
        height: 260,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final h in _hearts)
              Positioned(
                key: ValueKey(h.id),
                bottom: 0,
                left: 30 + h.dx,
                child: Icon(Icons.favorite_rounded, color: h.color, size: h.size)
                    .animate(onComplete: (_) {
                      if (mounted) setState(() => _hearts.remove(h));
                    })
                    .scale(
                        begin: const Offset(0.4, 0.4),
                        end: const Offset(1, 1),
                        duration: 220.ms,
                        curve: Curves.easeOutBack)
                    .moveY(begin: 0, end: -230, duration: 1600.ms,
                        curve: Curves.easeOut)
                    .moveX(begin: 0, end: h.dx * 0.6, duration: 1600.ms)
                    .fadeOut(delay: 900.ms, duration: 700.ms),
              ),
          ],
        ),
      ),
    );
  }
}

class _Heart {
  final int id;
  final double dx;
  final Color color;
  final double size;
  _Heart(
      {required this.id,
      required this.dx,
      required this.color,
      required this.size});
}

/// Gift picker sheet (types match LiveComment.giftType).
class ClassicGiftSheet extends StatelessWidget {
  final void Function(String type) onSend;
  const ClassicGiftSheet({super.key, required this.onSend});

  static Future<void> show(BuildContext context,
      {required void Function(String type) onSend}) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ClassicGiftSheet(onSend: onSend),
    );
  }

  static const _gifts = [
    ('heart', Icons.favorite_rounded, 'Heart'),
    ('star', Icons.star_rounded, 'Star'),
    ('crown', Icons.workspace_premium_rounded, 'Crown'),
    ('rocket', Icons.rocket_launch_rounded, 'Rocket'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border(top: BorderSide(color: context.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Text('Send a gift',
                style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (var i = 0; i < _gifts.length; i++)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      Navigator.of(context).pop();
                      onSend(_gifts[i].$1);
                    },
                    child: Column(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: context.surfaceMid,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            border: Border.all(color: context.border),
                          ),
                          child: Icon(_gifts[i].$2,
                                  color: i.isEven
                                      ? AppColors.brandPink
                                      : AppColors.brandBlue,
                                  size: 28)
                              .animate(
                                  onPlay: (c) => c.repeat(reverse: true))
                              .scale(
                                  begin: const Offset(0.92, 0.92),
                                  end: const Offset(1.06, 1.06),
                                  duration: (900 + i * 150).ms,
                                  curve: Curves.easeInOut),
                        ),
                        const SizedBox(height: 6),
                        Text(_gifts[i].$3,
                            style: GoogleFonts.inter(
                                color: context.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600)),
                      ],
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

/// Bottom "Add comment…" capsule used by viewer and host.
class ClassicCommentField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback onSend;
  final String hint;

  const ClassicCommentField({
    super.key,
    required this.controller,
    required this.onSend,
    this.focusNode,
    this.hint = 'Add comment…',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: _scrim(0.38),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => onSend(),
        style: GoogleFonts.inter(color: _onVideo, fontSize: 13),
        cursorColor: AppColors.brandPink,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          hintText: hint,
          hintStyle: GoogleFonts.inter(
              color: _onVideo.withValues(alpha: 0.65), fontSize: 13),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, v, _) => v.text.trim().isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    onPressed: onSend,
                    icon: const Icon(Icons.send_rounded,
                        color: AppColors.brandPink, size: 18),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Shown when the host ends the live.
class ClassicEndedView extends StatelessWidget {
  final LiveStream? stream;
  final VoidCallback onClose;
  final String headline;

  const ClassicEndedView({
    super.key,
    required this.stream,
    required this.onClose,
    this.headline = 'LIVE has ended',
  });

  @override
  Widget build(BuildContext context) {
    final s = stream;
    return Scaffold(
      backgroundColor: context.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClassicAvatar(url: s?.hostAvatarUrl ?? '', size: 84, ring: true)
                    .animate()
                    .scale(duration: 350.ms, curve: Curves.easeOutBack),
                const SizedBox(height: 16),
                Text(headline,
                    style: GoogleFonts.inter(
                        color: context.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3)),
                if (s != null) ...[
                  const SizedBox(height: 6),
                  Text(s.hostDisplayName,
                      style: GoogleFonts.inter(
                          color: context.textSecondary, fontSize: 13)),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Stat(label: 'Likes', value: compactCount(s.totalLikes)),
                      _Stat(
                          label: 'Comments',
                          value: compactCount(s.totalComments)),
                      _Stat(
                          label: 'Watching',
                          value: compactCount(s.viewerCount)),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: AppColors.brandWhite,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                    onPressed: onClose,
                    child: Text('Back',
                        style: GoogleFonts.inter(
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          Text(value,
              style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.inter(
                  color: context.textMuted, fontSize: 11)),
        ],
      ),
    );
  }
}
