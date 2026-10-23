import 'dart:async';
import 'dart:io' show Platform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../../auth/security/login_security.dart';

class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with SingleTickerProviderStateMixin {
  bool _hasNavigated = false;
  Timer? _watchdogTimer;

  @override
  void initState() {
    super.initState();
    // Safety watchdog: guarantees navigation happens even if async network stutters
    _watchdogTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted && !_hasNavigated) {
        debugPrint('[Splash] Watchdog timer triggered fallback to /hub/home');
        _skipSplash();
      }
    });
    _navigateNext();
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    super.dispose();
  }

  Future<void> _navigateNext() async {
    try {
      debugPrint('[Splash] Initializing Oneova Corporate Splash...');
      // Allow the corporate entrance and pulse animation to breathe gracefully
      await Future.delayed(const Duration(milliseconds: 2300));
      if (!mounted || _hasNavigated) return;

      User? user = FirebaseAuth.instance.currentUser;
      debugPrint('[Splash] Initial user check: ${user?.uid}');
      final isDesktopDebug =
          kDebugMode && !kIsWeb && (Platform.isMacOS || Platform.isWindows);

      if (isDesktopDebug) {
        _hasNavigated = true;
        _watchdogTimer?.cancel();
        debugPrint('[Splash] Routing to /desktop_agent');
        context.go('/desktop_agent');
        return;
      }

      // No automatic sign-in of any kind: a session must come from the login
      // screen and pass the two-factor gate (LoginSecurity) on this device.
      try {
        await LoginSecurity.instance.restore().timeout(const Duration(milliseconds: 1500));
      } catch (e) {
        debugPrint('[Splash] LoginSecurity restore skipped/timeout: $e');
      }

      if (!mounted || _hasNavigated) return;
      _hasNavigated = true;
      _watchdogTimer?.cancel();

      final verified = user != null && (user.isAnonymous || LoginSecurity.instance.isVerified(user));
      final next = verified ? '/hub/home' : '/auth/main_login';
      debugPrint('[Splash] Routing to $next');
      context.go(next);
    } catch (e, st) {
      debugPrint('[Splash] Error during navigation: $e\n$st');
      if (mounted && !_hasNavigated) {
        _hasNavigated = true;
        _watchdogTimer?.cancel();
        final user = FirebaseAuth.instance.currentUser;
        final verified = user != null && (user.isAnonymous || LoginSecurity.instance.isVerified(user));
        final next = verified ? '/hub/home' : '/auth/main_login';
        context.go(next);
      }
    }
  }

  void _skipSplash() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    _watchdogTimer?.cancel();
    final user = FirebaseAuth.instance.currentUser;
    final verified = user != null && (user.isAnonymous || LoginSecurity.instance.isVerified(user));
    final next = verified ? '/hub/home' : '/auth/main_login';
    debugPrint('[Splash] _skipSplash routing to: $next');
    context.go(next);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: context.bg,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skipSplash,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Deep Ambient Radial Atmosphere
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.15),
                    radius: 0.9,
                    colors: [
                      AppColors.brandBlue.withValues(alpha: 0.16),
                      context.bg.withValues(alpha: 0.8),
                      context.bg,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),

            // 2. Subtle Concentric Corporate Broadcast Rings (echoing the soundwaves on the logo)
            Center(
              child: Transform.translate(
                offset: const Offset(0, -40),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer broadcast wave 3
                    Container(
                      width: 290,
                      height: 290,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.brandBlue.withValues(alpha: 0.12),
                          width: 1.0,
                        ),
                      ),
                    )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scale(
                          begin: const Offset(0.92, 0.92),
                          end: const Offset(1.08, 1.08),
                          duration: 3200.ms,
                          curve: Curves.easeInOutSine,
                        )
                        .fade(
                          begin: 0.2,
                          end: 0.6,
                          duration: 3200.ms,
                          curve: Curves.easeInOutSine,
                        ),

                    // Middle broadcast wave 2
                    Container(
                      width: 230,
                      height: 230,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.brandBlue.withValues(alpha: 0.22),
                          width: 1.2,
                        ),
                      ),
                    )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scale(
                          begin: const Offset(0.95, 0.95),
                          end: const Offset(1.05, 1.05),
                          duration: 2500.ms,
                          curve: Curves.easeInOutSine,
                        )
                        .fade(
                          begin: 0.3,
                          end: 0.8,
                          duration: 2500.ms,
                          curve: Curves.easeInOutSine,
                        ),

                    // Inner broadcast aura 1
                    Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brandBlue.withValues(alpha: 0.35),
                            blurRadius: 50,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                    )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scale(
                          begin: const Offset(0.96, 0.96),
                          end: const Offset(1.04, 1.04),
                          duration: 2000.ms,
                          curve: Curves.easeInOutSine,
                        ),

                    // Hero Logo Emblem (Clean squircle badge with corporate bevel and sheen)
                    Container(
                      width: 136,
                      height: 136,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(34),
                        border: Border.all(
                          color: context.border,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: context.isDark ? 0.6 : 0.12),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          ),
                          BoxShadow(
                            color: AppColors.brandBlue.withValues(alpha: 0.4),
                            blurRadius: 40,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: Image.asset(
                          'assets/images/oneova_logo.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 800.ms, curve: Curves.easeOutCubic)
                        .scale(
                          begin: const Offset(0.72, 0.72),
                          end: const Offset(1.0, 1.0),
                          duration: 900.ms,
                          curve: Curves.easeOutBack,
                        )
                        .then()
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .shimmer(
                          duration: 2600.ms,
                          color: Colors.white.withValues(alpha: 0.3),
                        )
                        .scale(
                          begin: const Offset(1.0, 1.0),
                          end: const Offset(1.025, 1.025),
                          duration: 2400.ms,
                          curve: Curves.easeInOutSine,
                        ),
                  ],
                ),
              ),
            ),

            // 3. Corporate Typography & Tagline
            Positioned(
              left: 24,
              right: 24,
              top: (size.height * 0.5) + 60,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Title: ONEOVA
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
                      .fadeIn(delay: 350.ms, duration: 700.ms)
                      .slideY(
                        begin: 0.25,
                        end: 0,
                        duration: 700.ms,
                        curve: Curves.easeOutQuart,
                      ),

                  const SizedBox(height: 10),

                  // Tagline
                  Text(
                    'CREATIVE SOCIAL STUDIO',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3.5,
                      color: context.textSecondary,
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 550.ms, duration: 700.ms)
                      .slideY(
                        begin: 0.2,
                        end: 0,
                        duration: 700.ms,
                        curve: Curves.easeOutQuart,
                      ),

                  const SizedBox(height: 18),

                  // Premium Status Pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: context.surfaceMid.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: context.border,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.brandPink,
                            shape: BoxShape.circle,
                          ),
                        )
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .scale(
                              begin: const Offset(0.7, 0.7),
                              end: const Offset(1.3, 1.3),
                              duration: 800.ms,
                            )
                            .fade(begin: 0.4, end: 1.0, duration: 800.ms),
                        const SizedBox(width: 8),
                        Text(
                          'ALL YOU NEED IN YOUR POCKET',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                            color: context.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 750.ms, duration: 600.ms)
                      .scale(
                        begin: const Offset(0.9, 0.9),
                        end: const Offset(1.0, 1.0),
                        duration: 600.ms,
                        curve: Curves.easeOutBack,
                      ),
                ],
              ),
            ),

            // 4. Minimalist Corporate Loading Indicator & Version
            Positioned(
              left: 32,
              right: 32,
              bottom: 48,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Sleek progress bar
                    Container(
                      width: 120,
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: context.surfaceMid,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 2.5,
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue,
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.brandBlue.withValues(alpha: 0.8),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        )
                            .animate()
                            .custom(
                              duration: 2100.ms,
                              curve: Curves.easeInOutCubic,
                              builder: (context, value, child) {
                                return SizedBox(
                                  width: 120 * value,
                                  child: child,
                                );
                              },
                            ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'CONNECTING TO NETWORK',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2.0,
                        color: context.textMuted,
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 850.ms, duration: 600.ms),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}