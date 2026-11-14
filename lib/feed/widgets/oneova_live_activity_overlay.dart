import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';
import '../providers/live_activity_provider.dart';
import 'oneova_quick_privacy_sheet.dart';
import 'voice_comment_card.dart';

/// Floating luminous glowing love heart model rising upwards from bottom left
/// and dissolving cleanly in the middle of the video.
class _GlowingLoveHeart {
  final Key key;
  final double startX; // Left side start ratio (0.05 to 0.44)
  final double size; // 22.0 to 32.0 dp
  final Color color; // Strictly AppColors.brandPink (#FF2D87) or AppColors.brandBlue (#0C4FA8)
  final String? avatarUrl;
  final String? username;
  final String initial;
  final double speed;
  final double swayAmplitude;
  final double swayFrequency;
  final double swayPhase;
  final double rotation;
  final double glowRadius;
  final DateTime createdAt;
  final int durationMs;

  _GlowingLoveHeart({
    required this.key,
    required this.startX,
    required this.size,
    required this.color,
    this.avatarUrl,
    this.username,
    this.initial = '♥',
    required this.speed,
    required this.swayAmplitude,
    required this.swayFrequency,
    required this.swayPhase,
    required this.rotation,
    required this.glowRadius,
    required this.createdAt,
    required this.durationMs,
  });
}

/// A comment/like pill currently shown in the mid-video floating stream.
/// Uses a monotonic [seq] so sibling keys are guaranteed 100% unique even when
/// a reel has only 1–2 comments/likes cycling over time.
class _ShownItem {
  final LiveActivityCardItem card;
  final int seq;
  final DateTime shownAt;
  _ShownItem(this.card, this.seq) : shownAt = DateTime.now();
}

/// Animates a floating pill in from below, glides it gently upward, and
/// dissolves + collapses it as it reaches the middle of the video.
class _FadingLifetime extends StatefulWidget {
  final Duration lifetime;
  final Widget child;
  const _FadingLifetime({super.key, required this.lifetime, required this.child});

  @override
  State<_FadingLifetime> createState() => _FadingLifetimeState();
}

class _FadingLifetimeState extends State<_FadingLifetime> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.lifetime)..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        final fadeIn = Curves.easeOutCubic.transform((t / 0.10).clamp(0.0, 1.0));
        final fadeOut = 1.0 - Curves.easeInCubic.transform(((t - 0.64) / 0.28).clamp(0.0, 1.0));
        final collapse = 1.0 - Curves.easeInOut.transform(((t - 0.90) / 0.10).clamp(0.0, 1.0));
        // Gentle continuous upward drift toward the middle of the video
        final lift = -14.0 * Curves.easeOutSine.transform(t);
        return Align(
          alignment: Alignment.bottomLeft,
          heightFactor: collapse,
          child: Opacity(
            opacity: (fadeIn * fadeOut).clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, (1 - fadeIn) * 14 + lift),
              child: Transform.scale(
                scale: 0.88 + 0.12 * fadeIn,
                alignment: Alignment.centerLeft,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Live activity & floating comments overlay for Reels:
/// - Floating comments, GIF pills, voice pills, and likes originate above the
///   creator info block and **strictly end / dissolve in the middle of the video**
///   (50% vertical mark), never encroaching on the upper video or top navigation.
/// - Unique sequence keys prevent duplicate-key element accumulation when a reel
///   has a small pool of comments/likes.
class OneovaLiveActivityOverlay extends ConsumerStatefulWidget {
  final String contentId;
  final bool isVisible;

  /// Cinematic (focus) mode: chrome is hidden, so comments and likes float
  /// non-interactively from near the bottom edge up to the middle of the video.
  final bool immersive;
  final VoidCallback? onCommentTap;
  final VoidCallback? onLikesTap;

  /// The like button: hearts rise from it and fade, instead of floating
  /// across the video.
  final GlobalKey? heartAnchor;

  const OneovaLiveActivityOverlay({
    super.key,
    required this.contentId,
    this.isVisible = true,
    this.immersive = false,
    this.onCommentTap,
    this.onLikesTap,
    this.heartAnchor,
  });

  @override
  ConsumerState<OneovaLiveActivityOverlay> createState() => _OneovaLiveActivityOverlayState();
}

class _OneovaLiveActivityOverlayState extends ConsumerState<OneovaLiveActivityOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  final List<_GlowingLoveHeart> _activeHearts = [];
  final Random _rnd = Random();

  Timer? _ambientHeartTimer;
  Timer? _tickerTimer;

  // One comment at a time: each stays ~3 s, then the next slides in.
  static const Duration _normalPillLife = Duration(milliseconds: 3000);
  static const Duration _immersivePillLife = Duration(milliseconds: 3400);

  final List<_ShownItem> _shownItems = [];
  int _streamCursor = 0;
  int _pillSeq = 0;
  int _heartCounter = 0;
  String? _primedForContentId;

  // STRICTLY Oneova brand colors: Blue & Pink only
  static const List<Color> _heartPalette = [
    AppColors.brandPink, // Secondary accent #FF2D87
    AppColors.brandBlue, // Primary core #0C4FA8
  ];

  Duration get _activeLifetime => widget.immersive ? _immersivePillLife : _normalPillLife;
  int get _maxVisiblePills => 1;
  final GlobalKey _selfKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();

    _startHeartEngine();
    _startTickerEngine();
  }

  @override
  void didUpdateWidget(covariant OneovaLiveActivityOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentId != widget.contentId) {
      _shownItems.clear();
      _streamCursor = 0;
      _activeHearts.clear();
      _primedForContentId = null;
      _startTickerEngine();
    } else if (oldWidget.immersive != widget.immersive) {
      if (_shownItems.length > _maxVisiblePills) {
        _shownItems.removeRange(0, _shownItems.length - _maxVisiblePills);
      }
    }
  }

  @override
  void dispose() {
    _ambientHeartTimer?.cancel();
    _tickerTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _startHeartEngine() {
    _ambientHeartTimer?.cancel();
    _ambientHeartTimer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      if (!mounted || !widget.isVisible) return;
      final liveEvents = ref.read(contentLiveActivityStreamProvider(widget.contentId)).value ?? const [];
      final likers = liveEvents.where((e) => e.type.contains('like') || e.type.contains('reaction')).length;
      final cap = min(likers, 4);
      if (_activeHearts.length < cap) {
        _spawnGlowingHeart();
      }
    });
  }

  void _startTickerEngine() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(milliseconds: 3200), (_) {
      if (!mounted || !widget.isVisible) return;
      _advanceTicker();
    });
  }

  void _primeInitialItems(List<LiveActivityCardItem> liveEvents) {
    if (liveEvents.isEmpty || _primedForContentId == widget.contentId) return;
    _primedForContentId = widget.contentId;

    final seenIds = <String>{};
    final initial = <LiveActivityCardItem>[];
    for (final ev in liveEvents) {
      if (ev.type.contains('like')) continue;
      if (seenIds.add(ev.id)) {
        initial.add(ev);
        if (initial.length >= min(2, _maxVisiblePills)) break;
      }
    }
    if (initial.isEmpty) return;

    setState(() {
      for (final item in initial) {
        _shownItems.add(_ShownItem(item, _pillSeq++));
      }
      _streamCursor = initial.length % liveEvents.length;
    });
  }

  void _advanceTicker() {
    final now = DateTime.now();
    final life = _activeLifetime;
    // Likes show as hearts from the like button; the stream is comments only.
    final liveEvents = [
      for (final e in ref.read(contentLiveActivityStreamProvider(widget.contentId)).value ?? const <LiveActivityCardItem>[])
        if (!e.type.contains('like')) e,
    ];

    if (liveEvents.isEmpty) {
      if (_shownItems.isNotEmpty) {
        setState(() {
          _shownItems.removeWhere((s) => now.difference(s.shownAt) >= life);
        });
      }
      return;
    }

    // Pick next item that isn't already actively visible on screen
    final activeIds = _shownItems
        .where((s) => now.difference(s.shownAt) < life * 0.85)
        .map((s) => s.card.id)
        .toSet();

    LiveActivityCardItem? chosen;
    for (var attempt = 0; attempt < liveEvents.length; attempt++) {
      final candidate = liveEvents[(_streamCursor + attempt) % liveEvents.length];
      if (!activeIds.contains(candidate.id)) {
        chosen = candidate;
        _streamCursor = (_streamCursor + attempt + 1) % liveEvents.length;
        break;
      }
    }

    setState(() {
      _shownItems.removeWhere((s) => now.difference(s.shownAt) >= life);
      if (chosen != null) {
        _shownItems.add(_ShownItem(chosen, _pillSeq++));
        while (_shownItems.length > _maxVisiblePills) {
          _shownItems.removeAt(0);
        }
      }
    });
  }

  /// Spawns a luminous pink or blue heart rising up to the middle of the video.
  void _spawnGlowingHeart({Color? customColor, bool isBurst = false}) {
    if (!mounted) return;

    _heartCounter++;
    final color = customColor ?? _heartPalette[_heartCounter % _heartPalette.length];
    final size = 21.0 + _rnd.nextDouble() * (isBurst ? 9.0 : 7.0);
    final durationMs = 2600 + _rnd.nextInt(1000);

    final startX = widget.immersive
        ? (0.08 + _rnd.nextDouble() * 0.72)
        : isBurst
            ? (0.05 + _rnd.nextDouble() * 0.36)
            : (0.06 + _rnd.nextDouble() * 0.30);

    final liveEvents = ref.read(contentLiveActivityStreamProvider(widget.contentId)).value ?? const [];
    final likers = liveEvents.where((e) => e.type.contains('like') || e.type.contains('reaction')).toList();
    final liker = likers.isNotEmpty
        ? likers[_heartCounter % likers.length]
        : (liveEvents.isNotEmpty ? liveEvents[_heartCounter % liveEvents.length] : null);

    final heart = _GlowingLoveHeart(
      key: UniqueKey(),
      startX: startX,
      size: size,
      color: color,
      avatarUrl: liker?.avatarUrl,
      username: liker?.username,
      initial: (liker != null && liker.username.isNotEmpty) ? liker.username[0].toUpperCase() : '♥',
      speed: 0.75 + _rnd.nextDouble() * 0.35,
      swayAmplitude: 10.0 + _rnd.nextDouble() * 14.0,
      swayFrequency: 1.8 + _rnd.nextDouble() * 1.1,
      swayPhase: _rnd.nextDouble() * 2 * pi,
      rotation: (_rnd.nextDouble() - 0.5) * 0.26,
      glowRadius: 9.0 + _rnd.nextDouble() * 5.0,
      createdAt: DateTime.now(),
      durationMs: durationMs,
    );

    setState(() {
      _activeHearts.add(heart);
    });

    Future.delayed(Duration(milliseconds: durationMs + 100), () {
      if (mounted) {
        setState(() {
          _activeHearts.removeWhere((h) => h.key == heart.key);
        });
      }
    });
  }

  /// Celebration flurry of glowing love hearts (triggered on like or double-tap)
  void burstGlowingLove({int count = 6}) {
    HapticFeedback.lightImpact();
    for (int i = 0; i < count; i++) {
      Future.delayed(Duration(milliseconds: i * 80), () {
        if (mounted) {
          _spawnGlowingHeart(
            customColor: i % 2 == 0 ? AppColors.brandPink : AppColors.brandBlue,
            isBurst: true,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();

    final liveEventsAsync = ref.watch(contentLiveActivityStreamProvider(widget.contentId));
    final liveEvents = liveEventsAsync.value ?? const [];

    // Watch newly posted comments in real time: if a brand-new comment arrives
    // that isn't shown yet, surface it immediately in the floating stream.
    ref.listen<AsyncValue<List<LiveActivityCardItem>>>(
      contentLiveActivityStreamProvider(widget.contentId),
      (prev, next) {
        final nextItems = next.value ?? const [];
        if (nextItems.isEmpty) return;
        final prevIds = (prev?.value ?? const []).map((e) => e.id).toSet();
        final freshComment = nextItems.where((e) => !prevIds.contains(e.id) && e.type.contains('comment')).firstOrNull;
        if (freshComment != null && mounted && prevIds.isNotEmpty) {
          setState(() {
            _shownItems.removeWhere((s) => s.card.id == freshComment.id);
            _shownItems.add(_ShownItem(freshComment, _pillSeq++));
            while (_shownItems.length > _maxVisiblePills) {
              _shownItems.removeAt(0);
            }
          });
        }
      },
    );

    ref.listen<int>(glowingLoveBurstProvider, (prev, next) {
      if (next > (prev ?? 0)) {
        burstGlowingLove(count: 6);
      }
    });

    if (_shownItems.isEmpty && liveEvents.isNotEmpty && _primedForContentId != widget.contentId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _primeInitialItems(liveEvents);
      });
    }

    return LayoutBuilder(
      key: _selfKey,
      builder: (context, constraints) {
        final mediaSize = MediaQuery.sizeOf(context);
        final safeBottom = MediaQuery.paddingOf(context).bottom;
        final viewportH = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : mediaSize.height;
        final viewportW = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : mediaSize.width;

        final bottomNavInset = 66.0 + safeBottom;
        final bottomAnchor = widget.immersive ? safeBottom + 26.0 : bottomNavInset + 178.0;

        // STRICT MID-VIDEO CEILING: Floating comments & hearts end right in the
        // middle of the video (50% of viewport height) and dissolve smoothly.
        final midVideoTop = viewportH * 0.50;
        final topCeiling = min(midVideoTop, max(0.0, viewportH - bottomAnchor - 88.0));

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Radiant Floating Love Icons (Capped at Middle of Video) ──
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _animController,
                  builder: (context, _) {
                    final now = DateTime.now();
                    return Stack(
                      clipBehavior: Clip.none,
                      children: _activeHearts.map((heart) {
                        return _buildAnimatedGlowingLove(
                          heart,
                          now,
                          viewportH: viewportH,
                          viewportW: viewportW,
                          safeBottom: safeBottom,
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ),

            // ── Mid-Video Bounded Floating Comments & Activity Stream ─────
            if (_shownItems.isNotEmpty)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOutCubic,
                left: 14,
                top: topCeiling,
                bottom: bottomAnchor,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: min(236.0, viewportW - 92.0)),
                  child: ClipRect(
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (rect) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x00FFFFFF),
                          Color(0xB3FFFFFF),
                          Color(0xFFFFFFFF),
                        ],
                        stops: [0.0, 0.22, 0.42],
                      ).createShader(rect),
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: IgnorePointer(
                          ignoring: widget.immersive,
                          // Newest stays at the bottom; older bubbles slide out
                          // of the top (already faded) instead of overflowing.
                          child: SingleChildScrollView(
                            reverse: true,
                            physics: const NeverScrollableScrollPhysics(),
                            child: _buildFloatingMidpointStream(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Rises with sinusoidal sway and dissolves strictly by the middle of the video (50% height).
  Widget _buildAnimatedGlowingLove(
    _GlowingLoveHeart heart,
    DateTime now, {
    required double viewportH,
    required double viewportW,
    required double safeBottom,
  }) {
    final elapsedMs = now.difference(heart.createdAt).inMilliseconds;
    final progress = (elapsedMs / heart.durationMs).clamp(0.0, 1.0);

    // Origin: the like button's centre (fallback: right side, lower third).
    var originX = viewportW - 34.0;
    var originBottom = viewportH * 0.32;
    final self = _selfKey.currentContext?.findRenderObject() as RenderBox?;
    final anchor = widget.heartAnchor?.currentContext?.findRenderObject() as RenderBox?;
    if (self != null && anchor != null && self.attached && anchor.attached) {
      final c = self.globalToLocal(anchor.localToGlobal(anchor.size.center(Offset.zero)));
      originX = c.dx;
      originBottom = self.size.height - c.dy;
    }
    // Rises a short way above the button with a gentle sway, then fades.
    final rise = 120.0 + heart.speed * 40.0;
    final currentY = originBottom + progress * rise - heart.size / 2;
    final sway = sin((progress * pi * heart.swayFrequency) + heart.swayPhase) * min(heart.swayAmplitude, 9.0) * progress;
    final currentX = originX - heart.size / 2 + sway;

    double scale;
    if (progress < 0.15) {
      scale = 0.40 + (progress / 0.15) * 0.66;
    } else if (progress > 0.72) {
      scale = 1.0 - ((progress - 0.72) / 0.28) * 0.28;
    } else {
      scale = 1.0;
    }

    // Dissolves smoothly to 0.0 right as it reaches the middle of the video
    double opacity;
    if (progress < 0.12) {
      opacity = (progress / 0.12).clamp(0.0, 1.0) * 0.76;
    } else if (progress > 0.60) {
      opacity = (1.0 - ((progress - 0.60) / 0.40)).clamp(0.0, 1.0) * 0.76;
    } else {
      opacity = 0.76;
    }

    final rocking = heart.rotation + sin(progress * pi * 3) * 0.06;

    return Positioned(
      bottom: currentY,
      left: currentX,
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: rocking,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: heart.size,
              height: heart.size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: heart.color.withValues(alpha: 0.22),
                border: Border.all(
                  color: heart.color.withValues(alpha: 0.70),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: heart.color.withValues(alpha: 0.45),
                    blurRadius: heart.glowRadius,
                    spreadRadius: 1.2,
                  ),
                ],
              ),
              child: heart.avatarUrl != null && heart.avatarUrl!.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        heart.avatarUrl!,
                        width: heart.size,
                        height: heart.size,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _buildHeartBubbleIcon(heart),
                      ),
                    )
                  : _buildHeartBubbleIcon(heart),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeartBubbleIcon(_GlowingLoveHeart heart) {
    return Icon(
      Icons.favorite_rounded,
      size: heart.size * 0.54,
      color: heart.color,
    );
  }

  /// Self-fading rolling stream of pills with unique sequence keys.
  /// Older pills at the top progressively dim and dissolve at the midpoint.
  Widget _buildFloatingMidpointStream() {
    final item = _shownItems.isEmpty ? null : _shownItems.last;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 360),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      child: item == null
          ? const SizedBox.shrink()
          : _FadingLifetime(
              key: ValueKey('pill_${item.seq}'),
              lifetime: _activeLifetime,
              child: _buildCompactPill(item.card),
            ),
    );
  }

  /// Compact activity chip:
  /// - Like: author avatar with pink heart badge + @name.
  /// - Voice comment: mini waveform player card.
  /// - GIF comment: author + mini rounded GIF preview (+ optional text).
  /// - Text comment: author + crisp 1–2 line comment text.
  Widget _buildCompactPill(LiveActivityCardItem card) {
    final isLike = card.type.contains('like');
    final isVoice = card.voiceUrl != null;
    final hasGif = card.gif != null;
    final accent = isLike ? AppColors.brandPink : AppColors.brandBlue;

    void onTap() {
      HapticFeedback.lightImpact();
      if (isLike && widget.onLikesTap != null) {
        widget.onLikesTap!();
      } else if (widget.onCommentTap != null) {
        widget.onCommentTap!();
      } else {
        OneovaQuickPrivacySheet.show(context);
      }
    }

    final Widget body;
    if (isLike) {
      body = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _avatarWithBadge(card, accent, Icons.favorite_rounded, 20),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '@${card.username}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      );
    } else if (isVoice) {
      body = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _avatarWithBadge(card, accent, Icons.graphic_eq_rounded, 20),
          const SizedBox(width: 6),
          VoiceCommentMiniCard(
            key: ValueKey('voice_${card.id}'),
            url: card.voiceUrl!,
            durationMs: card.voiceDurationMs,
            seed: card.id,
          ),
        ],
      );
    } else if (hasGif) {
      final gif = card.gif!;
      body = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _avatarWithBadge(card, AppColors.brandPink, Icons.gif_box_rounded, 20),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '@${card.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                if (card.message.isNotEmpty)
                  Text(
                    card.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  )
                else
                  Text(
                    'GIF',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: AppColors.brandPink,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: SizedBox(
              width: (32 * gif.aspectRatio).clamp(28.0, 46.0),
              height: 32,
              child: Image.network(
                gif.url,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => Container(
                  color: Colors.white12,
                  alignment: Alignment.center,
                  child: const Icon(Icons.gif_rounded, color: Colors.white70, size: 16),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      body = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _avatarWithBadge(card, accent, Icons.chat_bubble_rounded, 20),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '@${card.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
                Text(
                  card.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    height: 1.22,
                    color: Colors.white.withValues(alpha: 0.95),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            constraints: BoxConstraints(maxWidth: isLike ? 168 : 224),
            padding: EdgeInsets.fromLTRB(4, 3, hasGif ? 5 : 10, 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.48),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (hasGif ? AppColors.brandPink : accent).withValues(alpha: isLike ? 0.50 : 0.32),
                width: 1.0,
              ),
            ),
            child: body,
          ),
        ),
      ),
    );
  }

  Widget _avatarWithBadge(LiveActivityCardItem card, Color accent, IconData icon, double size) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: accent, width: 1.0),
              ),
              child: ClipOval(
                child: card.avatarUrl.isNotEmpty
                    ? Image.network(
                        card.avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _buildFallbackAvatar(card, accent),
                      )
                    : _buildFallbackAvatar(card, accent),
              ),
            ),
          ),
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: size * 0.5,
              height: size * 0.5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent,
                border: Border.all(color: Colors.black, width: 1.0),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: size * 0.3, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackAvatar(LiveActivityCardItem card, Color glowColor) {
    if (card.username.isNotEmpty) {
      return Container(
        color: glowColor.withValues(alpha: 0.25),
        alignment: Alignment.center,
        child: Text(
          card.username[0].toUpperCase(),
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 10,
          ),
        ),
      );
    }
    return Container(
      color: glowColor.withValues(alpha: 0.25),
      alignment: Alignment.center,
      child: Icon(
        card.icon,
        size: 13,
        color: Colors.white,
      ),
    );
  }
}
