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
class _GlowingLoveHeart {
  final Key key;
  final double startX; // Left side start ratio (0.05 to 0.44)
  final double size; // 24.0 to 34.0 dp
  final Color color; // Strictly AppColors.brandPink (#FF2D87) or AppColors.brandBlue (#0C4FA8)
  final String? avatarUrl;
  final String? username;
  final String initial;
  final double speed; // Relative ascent velocity
  final double swayAmplitude; // Horizontal swaying range (px)
  final double swayFrequency; // Oscillation frequency
  final double swayPhase; // Unique sine phase
  final double rotation; // Slight organic tilt (-0.25 to +0.25 rad)
  final double glowRadius; // Soft halo blur radius
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

/// A comment/like pill currently shown in immersive mode, with its own lifetime.
class _ShownItem {
  final LiveActivityCardItem card;
  final int seq;
  final DateTime shownAt = DateTime.now();
  _ShownItem(this.card, this.seq);
}

/// Fades an ambient pill in, holds it, then fades it out while collapsing its
/// height so the pills above glide down instead of jumping.
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
        final fadeIn = Curves.easeOutCubic.transform((t / 0.08).clamp(0.0, 1.0));
        final fadeOut = 1.0 - Curves.easeInCubic.transform(((t - 0.62) / 0.30).clamp(0.0, 1.0));
        final collapse = 1.0 - Curves.easeInOut.transform(((t - 0.90) / 0.10).clamp(0.0, 1.0));
        final lift = -10.0 * Curves.easeInCubic.transform(((t - 0.62) / 0.38).clamp(0.0, 1.0));
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

/// Advanced TikTok-grade live activity & comments overlay:
/// 1. Auto-animating stream of small micro-pills rolling upwards until user scrolls
/// 2. Initial state pre-renders existing comments/likes seamlessly to avoid empty jumps
/// 3. Continuous radiant glowing love hearts rising from the bottom with organic physics
/// 4. Tap & like celebration heart bursts with vibrant dual-tone brand glow
class OneovaLiveActivityOverlay extends ConsumerStatefulWidget {
  final String contentId;
  final bool isVisible;

  /// Cinematic (focus) mode: chrome is hidden, so comments and likes become
  /// ambient, non-interactive, self-fading elements along the bottom edge.
  final bool immersive;
  final VoidCallback? onCommentTap;
  final VoidCallback? onLikesTap;

  const OneovaLiveActivityOverlay({
    super.key,
    required this.contentId,
    this.isVisible = true,
    this.immersive = false,
    this.onCommentTap,
    this.onLikesTap,
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

  // Rolling displayed comments/activities stream
  List<LiveActivityCardItem> _displayedItems = [];
  int _streamCursor = 0;
  int _heartCounter = 0;

  // Immersive (focus mode) rolling window: each pill lives ~6s then fades away
  static const Duration _immersiveLife = Duration(milliseconds: 6000);
  final List<_ShownItem> _immersiveItems = [];
  int _immersiveSeq = 0;

  // STRICTLY Oneova brand colors: Blue & Pink only
  static const List<Color> _heartPalette = [
    AppColors.brandPink, // Secondary accent #FF2D87
    AppColors.brandBlue, // Primary core #0C4FA8
  ];

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
      // User scrolled to another reel: reset ticker and start fresh
      _displayedItems.clear();
      _streamCursor = 0;
      _activeHearts.clear();
      _immersiveItems.clear();
      _startTickerEngine();
    }
    if (oldWidget.immersive != widget.immersive) {
      _immersiveItems.clear();
      if (widget.immersive) _advanceTicker();
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
    // Ambient glowing love icons rise from the left side based on backend likers
    _ambientHeartTimer = Timer.periodic(const Duration(milliseconds: 1100), (_) {
      if (!mounted || !widget.isVisible) return;
      // Ambient hearts stand for real likers of this reel only: none when
      // nobody has liked it, and never more on screen than actual likers.
      final liveEvents = ref.read(contentLiveActivityStreamProvider(widget.contentId)).value ?? const [];
      final likers = liveEvents.where((e) => e.type.contains('like') || e.type.contains('reaction')).length;
      final cap = min(likers, widget.immersive ? 22 : 16);
      if (_activeHearts.length < cap) {
        _spawnGlowingHeart();
      }
    });
  }

  void _startTickerEngine() {
    _tickerTimer?.cancel();
    // Auto-advance comments and activity items smoothly every 2.1s
    _tickerTimer = Timer.periodic(const Duration(milliseconds: 2100), (_) {
      if (!mounted || !widget.isVisible) return;
      _advanceTicker();
    });
  }

  void _advanceTicker() {
    final liveEvents = ref.read(contentLiveActivityStreamProvider(widget.contentId)).value ?? [];
    if (liveEvents.isEmpty) return;

    if (widget.immersive) {
      setState(() {
        final now = DateTime.now();
        _immersiveItems.removeWhere((s) => now.difference(s.shownAt) > _immersiveLife);
        final next = liveEvents[_streamCursor % liveEvents.length];
        _streamCursor = (_streamCursor + 1) % liveEvents.length;
        _immersiveItems.add(_ShownItem(next, _immersiveSeq++));
        if (_immersiveItems.length > 4) _immersiveItems.removeAt(0);
      });
      return;
    }

    setState(() {
      // Initialize pre-rendered items on first run so the look is instantly rendered
      if (_displayedItems.isEmpty) {
        final initialTake = min(3, liveEvents.length);
        _displayedItems = liveEvents.take(initialTake).toList();
        _streamCursor = initialTake % liveEvents.length;
        return;
      }

      // Pick next item from continuous pool
      final nextItem = liveEvents[_streamCursor % liveEvents.length];
      _streamCursor = (_streamCursor + 1) % liveEvents.length;

      // Add to rolling window (up to 3-4 items visible at a time)
      _displayedItems.add(nextItem);
      if (_displayedItems.length > 3) {
        _displayedItems.removeAt(0);
      }
    });
  }

  /// Spawns a faded love pink or blue icon floating upwards from the left side,
  /// directly based on real users who liked this reel from the Firestore backend.
  void _spawnGlowingHeart({Color? customColor, bool isBurst = false}) {
    if (!mounted) return;

    _heartCounter++;
    final color = customColor ?? _heartPalette[_heartCounter % _heartPalette.length];
    final size = 22.0 + _rnd.nextDouble() * (isBurst ? 10.0 : 8.0);
    final durationMs = 2800 + _rnd.nextInt(1200);

    // Left side: comes from the left side around comments & creator info (0.05 to 0.44)
    final startX = widget.immersive
        ? (0.08 + _rnd.nextDouble() * 0.80) // chrome is hidden: hearts rise across the whole width
        : isBurst
            ? (0.05 + _rnd.nextDouble() * 0.40)
            : (0.07 + _rnd.nextDouble() * 0.35);

    // Pick actual user who liked from the backend Firestore stream
    final liveEvents = ref.read(contentLiveActivityStreamProvider(widget.contentId)).value ?? [];
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
      speed: 0.75 + _rnd.nextDouble() * 0.40,
      swayAmplitude: 12.0 + _rnd.nextDouble() * 16.0,
      swayFrequency: 1.8 + _rnd.nextDouble() * 1.2,
      swayPhase: _rnd.nextDouble() * 2 * pi,
      rotation: (_rnd.nextDouble() - 0.5) * 0.28,
      glowRadius: 10.0 + _rnd.nextDouble() * 6.0,
      createdAt: DateTime.now(),
      durationMs: durationMs,
    );

    setState(() {
      _activeHearts.add(heart);
    });

    // Clean up heart after its flight duration
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

    // Watch live events stream
    final liveEventsAsync = ref.watch(contentLiveActivityStreamProvider(widget.contentId));
    final liveEvents = liveEventsAsync.value ?? [];

    // Watch burst trigger from double-tap or like button
    ref.listen<int>(glowingLoveBurstProvider, (prev, next) {
      if (next > (prev ?? 0)) {
        burstGlowingLove(count: 6);
      }
    });

    // Seamless initial population: if events arrived and displayed items is empty, populate immediately
    if (_displayedItems.isEmpty && liveEvents.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _displayedItems.isEmpty) {
          setState(() {
            final initialCount = min(3, liveEvents.length);
            _displayedItems = liveEvents.take(initialCount).toList();
            _streamCursor = initialCount % liveEvents.length;
          });
        }
      });
    }

    final bottomNavInset = 66.0 + MediaQuery.paddingOf(context).bottom;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── Radiant Floating Faded Love Pink & Blue Icons from Left Side ──
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _animController,
              builder: (context, _) {
                final now = DateTime.now();
                return Stack(
                  clipBehavior: Clip.none,
                  children: _activeHearts.map((heart) {
                    return _buildAnimatedGlowingLove(heart, now);
                  }).toList(),
                );
              },
            ),
          ),
        ),

        // ── Auto-Animated Compact TikTok-Style Live Stream (Above Creator Info) ─
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          left: 14,
          // Normal: above creator caption & audio row. Immersive: near the bottom edge.
          bottom: widget.immersive ? MediaQuery.paddingOf(context).bottom + 26.0 : bottomNavInset + 182.0,
          child: widget.immersive
              ? IgnorePointer(child: _buildImmersiveStream())
              : _buildCompactLiveStream(_displayedItems.isNotEmpty ? _displayedItems : liveEvents.take(3).toList()),
        ),
      ],
    );
  }

  /// Rises with dynamic sinusoidal sway, glowing box shadow, and scale bloom
  Widget _buildAnimatedGlowingLove(_GlowingLoveHeart heart, DateTime now) {
    final elapsedMs = now.difference(heart.createdAt).inMilliseconds;
    final progress = (elapsedMs / heart.durationMs).clamp(0.0, 1.0);

    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;

    // Start travel on the left side above the comment bar (~96dp + safe area)
    final bottomInset = (widget.immersive ? 36.0 : 90.0) + MediaQuery.paddingOf(context).bottom;
    final currentY = bottomInset + (progress * (screenH * (widget.immersive ? 0.62 : 0.52)));

    // Sinusoidal horizontal sway on the left side
    final sway = sin((progress * pi * heart.swayFrequency) + heart.swayPhase) * heart.swayAmplitude;
    final currentX = (screenW * heart.startX) + sway;

    // Scale bloom: 0.40 at launch -> 1.08 -> 1.0 -> 0.75 at end
    double scale;
    if (progress < 0.15) {
      scale = 0.40 + (progress / 0.15) * 0.68;
    } else if (progress > 0.80) {
      scale = 1.0 - ((progress - 0.80) / 0.20) * 0.25;
    } else {
      scale = 1.0;
    }

    // Faded opacity: soft translucent appearance (0.75 max)
    double opacity;
    if (progress < 0.12) {
      opacity = (progress / 0.12).clamp(0.0, 1.0) * 0.78;
    } else if (progress > 0.75) {
      opacity = (1.0 - ((progress - 0.75) / 0.25)).clamp(0.0, 1.0) * 0.78;
    } else {
      opacity = 0.78;
    }

    // Gentle rocking rotation
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
                  // Luminous ambient glow shadow in Oneova Pink or Blue
                  BoxShadow(
                    color: heart.color.withValues(alpha: 0.45),
                    blurRadius: heart.glowRadius,
                    spreadRadius: 1.5,
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

  /// Ambient comments & likes for cinematic mode: self-fading pills with a soft
  /// fade toward the top so the stream dissolves into the video.
  Widget _buildImmersiveStream() {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF)],
        stops: [0.0, 0.5],
      ).createShader(rect),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in _immersiveItems)
            _FadingLifetime(
              key: ValueKey('imm_${s.seq}'),
              lifetime: _immersiveLife,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 5.0),
                child: _buildCompactPill(s.card),
              ),
            ),
        ],
      ),
    );
  }

  /// Compact, high-density live comments & activity stream
  /// Auto-animates coming from the back with 3D scale bloom and smooth fading
  Widget _buildCompactLiveStream(List<LiveActivityCardItem> items) {
    if (items.isEmpty) {
      return _buildCompactPill(
        LiveActivityCardItem(
          id: 'welcome_live',
          type: 'stage.live',
          userId: 'oneova',
          username: 'Oneova',
          avatarUrl: '',
          message: 'Reel stream active ❤️',
          icon: Icons.movie_filter_rounded,
          badgeColor: AppColors.brandBlue,
          timestamp: DateTime.now(),
          rotationAngle: -0.010,
          isVerified: true,
        ),
      );
    }

    final total = items.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(total, (index) {
        final card = items[index];
        // Oldest item at top fades slightly, newest at bottom is 1.0 opacity
        final targetOpacity = (total > 2 && index == 0)
            ? 0.62
            : (total > 2 && index == 1)
                ? 0.86
                : 1.0;

        return Padding(
          key: ValueKey(card.id),
          padding: const EdgeInsets.only(bottom: 5.0),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutBack,
            builder: (context, animValue, child) {
              // 3D depth pop: emerging from the back (0.74 scale -> 1.0)
              final scale = 0.74 + (0.26 * animValue);
              final slideY = (1.0 - animValue) * 12.0;
              final opacity = (animValue * targetOpacity).clamp(0.0, 1.0);

              return Transform.translate(
                offset: Offset(0, slideY),
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.centerLeft,
                  child: Opacity(
                    opacity: opacity,
                    child: child,
                  ),
                ),
              );
            },
            child: _buildCompactPill(card),
          ),
        );
      }),
    );
  }

  /// Compact activity chip.
  /// - Like: the author's avatar with an attached pink heart badge + @name.
  /// - Comment: smaller, cleaner single chip with the author and one/two lines of text.
  /// - Voice comment: mini play card with waveform and duration.
  Widget _buildCompactPill(LiveActivityCardItem card) {
    final isLike = card.type.contains('like');
    final isVoice = card.voiceUrl != null;
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
          _avatarWithBadge(card, accent, Icons.favorite_rounded, 22),
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
                    height: 1.25,
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
            constraints: BoxConstraints(maxWidth: isLike ? 170 : 220),
            padding: const EdgeInsets.fromLTRB(4, 3, 10, 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: isLike ? 0.55 : 0.30), width: 1.0),
            ),
            child: body,
          ),
        ),
      ),
    );
  }

  /// Author avatar with the action attached as a small icon badge.
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
        size: 14,
        color: Colors.white,
      ),
    );
  }
}
