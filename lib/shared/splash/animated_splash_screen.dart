import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../../auth/security/login_security.dart';
import '../../backend/calling/providers/active_call_controller.dart';
import '../../inbox/calling/screens/active_call_screen.dart';
import '../../social_hub/calling/widgets/call_overlay_manager.dart';

/// Oneova launch splash: the logo pops in with a heartbeat, broadcast ripples
/// and floating hearts, then hands off to the feed (which autoplays) in about
/// a second. Tapping anywhere bursts hearts and opens the app right away.
class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen> {
  static const _minShow = Duration(milliseconds: 1100);
  static const _logoSize = 148.0;

  bool _hasNavigated = false;
  Timer? _watchdogTimer;
  Offset? _burstAt;
  late final Future<void> _securityReady;

  @override
  void initState() {
    super.initState();
    // Restore the two-factor state while the animation plays, not after it.
    _securityReady = LoginSecurity.instance
        .restore()
        .timeout(const Duration(milliseconds: 1500))
        .catchError((Object e) => debugPrint('[Splash] LoginSecurity restore skipped/timeout: $e'));
    // Safety watchdog: guarantees navigation happens even if async work stalls.
    _watchdogTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted && !_hasNavigated) {
        debugPrint('[Splash] Watchdog timer triggered fallback');
        _go();
      }
    });
    _navigateNext();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/images/oneova_logo.png'), context);
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    super.dispose();
  }

  Future<void> _navigateNext() async {
    await Future.wait([Future<void>.delayed(_minShow), _securityReady]);
    if (!mounted || _hasNavigated) return;

    final isDesktopDebug = kDebugMode && !kIsWeb && (Platform.isMacOS || Platform.isWindows);
    if (isDesktopDebug) {
      _hasNavigated = true;
      _watchdogTimer?.cancel();
      context.go('/desktop_agent');
      return;
    }
    _go();
  }

  /// Always open directly into the Reels/Feed screen (`/hub/home`).
  /// Unauthenticated users immediately explore public reels with full immersion,
  /// while authenticated users enjoy their active session without repeat logins.
  void _go() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    _watchdogTimer?.cancel();
    final router = GoRouter.of(context);
    var shouldOpenCall = CallOverlayManager.consumePendingOpenCall();
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      if (container.read(activeCallControllerProvider).isLive) {
        shouldOpenCall = true;
      }
    } catch (_) {}
    debugPrint('[Splash] Routing to /hub/home (Public Reel/Feed)');
    router.go('/hub/home');
    if (shouldOpenCall) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        openCallScreen(router);
      });
    }
  }

  void _onTap(TapDownDetails d) {
    if (_hasNavigated) return;
    HapticFeedback.lightImpact();
    setState(() => _burstAt = d.localPosition);
    Future<void>.delayed(const Duration(milliseconds: 260), _go);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final center = Offset(size.width / 2, size.height * 0.42);

    return Scaffold(
      backgroundColor: context.bg,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Ambient brand glow.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, (center.dy / size.height) * 2 - 1),
                  radius: 0.85,
                  colors: [
                    AppColors.brandBlue.withValues(alpha: context.isDark ? 0.30 : 0.16),
                    AppColors.brandPink.withValues(alpha: 0.05),
                    context.bg,
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),

            // Broadcast ripples spreading out from the logo, like its sound waves.
            for (var i = 0; i < 3; i++)
              Positioned(
                left: center.dx - _logoSize / 2,
                top: center.dy - _logoSize / 2,
                width: _logoSize,
                height: _logoSize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: (i.isEven ? AppColors.brandBlue : AppColors.brandPink).withValues(alpha: 0.55),
                      width: 2,
                    ),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(), delay: (300 + i * 420).ms)
                    .scaleXY(begin: 1.0, end: 2.4, duration: 1500.ms, curve: Curves.easeOutCubic)
                    .fadeOut(begin: 0.9, duration: 1500.ms, curve: Curves.easeOut),
              ),

            // Floating hearts rising around the logo.
            for (final h in _FloatingHeart.all)
              Positioned(
                left: center.dx + h.dx - h.size / 2,
                top: center.dy + 40,
                child: Icon(Icons.favorite_rounded, size: h.size, color: h.color)
                    .animate(onPlay: (c) => c.repeat(), delay: h.delay.ms)
                    .moveY(begin: 0, end: -h.rise, duration: h.duration.ms, curve: Curves.easeOut)
                    .moveX(begin: 0, end: h.drift, duration: h.duration.ms, curve: Curves.easeInOutSine)
                    .scaleXY(begin: 0.4, end: 1.0, duration: (h.duration * 0.35).ms, curve: Curves.easeOutBack)
                    .fadeIn(duration: 200.ms)
                    .then(delay: (h.duration * 0.25).ms)
                    .fadeOut(duration: (h.duration * 0.4).ms),
              ),

            // The logo: pop-in, then a two-beat heartbeat.
            Positioned(
              left: center.dx - _logoSize / 2,
              top: center.dy - _logoSize / 2,
              width: _logoSize,
              height: _logoSize,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandBlue.withValues(alpha: 0.45),
                      blurRadius: 42,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: context.isDark ? 0.5 : 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Image.asset('assets/images/oneova_logo.png', filterQuality: FilterQuality.high),
              )
                  .animate()
                  .fadeIn(duration: 260.ms)
                  .scaleXY(begin: 0.55, end: 1.0, duration: 620.ms, curve: Curves.elasticOut)
                  .rotate(begin: -0.04, end: 0, duration: 620.ms, curve: Curves.easeOutBack)
                  .then()
                  .animate(onPlay: (c) => c.repeat())
                  .scaleXY(begin: 1.0, end: 1.08, duration: 140.ms, curve: Curves.easeOut)
                  .then()
                  .scaleXY(begin: 1.0, end: 1 / 1.08, duration: 160.ms, curve: Curves.easeIn)
                  .then(delay: 80.ms)
                  .scaleXY(begin: 1.0, end: 1.05, duration: 120.ms, curve: Curves.easeOut)
                  .then()
                  .scaleXY(begin: 1.0, end: 1 / 1.05, duration: 160.ms, curve: Curves.easeIn)
                  .then(delay: 520.ms),
            ),

            // Wordmark and motto.
            Positioned(
              left: 24,
              right: 24,
              top: center.dy + _logoSize / 2 + 34,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ONEOVA',
                    style: GoogleFonts.inter(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6.0,
                      color: context.textPrimary,
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 220.ms, duration: 450.ms)
                      .slideY(begin: 0.3, end: 0, duration: 450.ms, curve: Curves.easeOutQuart),
                  const SizedBox(height: 8),
                  ShaderMask(
                    shaderCallback: (r) =>
                        const LinearGradient(colors: [AppColors.brandBlue, AppColors.brandPink]).createShader(r),
                    child: Text(
                      'The reason you matter',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: Colors.white,
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 380.ms, duration: 450.ms)
                      .slideY(begin: 0.3, end: 0, duration: 450.ms, curve: Curves.easeOutQuart),
                ],
              ),
            ),

            // Slim progress line, timed to the hand-off.
            Positioned(
              left: 0,
              right: 0,
              bottom: 56,
              child: SafeArea(
                child: Center(
                  child: Container(
                    width: 96,
                    height: 3,
                    decoration: BoxDecoration(
                      color: context.surfaceMid,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [AppColors.brandBlue, AppColors.brandPink]),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    )
                        .animate()
                        .custom(
                          duration: _minShow,
                          curve: Curves.easeInOutCubic,
                          builder: (context, value, child) => SizedBox(width: 96 * value, child: child),
                        ),
                  ),
                ),
              ),
            ),

            // Heart burst where the user tapped.
            if (_burstAt != null)
              for (var i = 0; i < 8; i++)
                Positioned(
                  left: _burstAt!.dx - 12,
                  top: _burstAt!.dy - 12,
                  child: Icon(
                    Icons.favorite_rounded,
                    size: 24,
                    color: i.isEven ? AppColors.brandPink : AppColors.brandBlue,
                  )
                      .animate()
                      .move(
                        end: Offset(math.cos(i * math.pi / 4) * 70, math.sin(i * math.pi / 4) * 70),
                        duration: 320.ms,
                        curve: Curves.easeOutCubic,
                      )
                      .scaleXY(begin: 0.3, end: 1.1, duration: 320.ms, curve: Curves.easeOutBack)
                      .fadeOut(delay: 140.ms, duration: 180.ms),
                ),
          ],
        ),
      ),
    );
  }
}

/// Fixed layout for the rising hearts (no randomness, so it looks the same
/// on every launch).
class _FloatingHeart {
  const _FloatingHeart(this.dx, this.size, this.rise, this.drift, this.duration, this.delay, this.color);

  final double dx;
  final double size;
  final double rise;
  final double drift;
  final int duration;
  final int delay;
  final Color color;

  static const all = [
    _FloatingHeart(-92, 18, 190, -18, 1700, 150, AppColors.brandPink),
    _FloatingHeart(84, 14, 170, 14, 1500, 420, AppColors.brandBlue),
    _FloatingHeart(-46, 12, 210, 10, 1900, 700, AppColors.brandPink),
    _FloatingHeart(52, 20, 230, -12, 1800, 260, AppColors.brandPink),
    _FloatingHeart(-120, 12, 150, 20, 1400, 900, AppColors.brandBlue),
    _FloatingHeart(118, 16, 200, -16, 1650, 600, AppColors.brandPink),
  ];
}
