import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'shared/theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2300), () {
      if (mounted) {
        context.go('/hub/home');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: context.bg,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (mounted) context.go('/hub/home');
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background Radial Lighting
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

            // Corporate Broadcast Waves & Emblem
            Center(
              child: Transform.translate(
                offset: const Offset(0, -40),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 280,
                      height: 280,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.brandBlue.withValues(alpha: 0.14),
                          width: 1.0,
                        ),
                      ),
                    )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scale(
                          begin: const Offset(0.94, 0.94),
                          end: const Offset(1.06, 1.06),
                          duration: 3000.ms,
                        ),

                    Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.brandBlue.withValues(alpha: 0.24),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brandBlue.withValues(alpha: 0.3),
                            blurRadius: 40,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scale(
                          begin: const Offset(0.96, 0.96),
                          end: const Offset(1.04, 1.04),
                          duration: 2400.ms,
                        ),

                    // Logo Emblem
                    Container(
                      width: 136,
                      height: 136,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(34),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
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
                          begin: const Offset(0.75, 0.75),
                          end: const Offset(1.0, 1.0),
                          duration: 900.ms,
                          curve: Curves.easeOutBack,
                        )
                        .then()
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .shimmer(
                          duration: 2600.ms,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                  ],
                ),
              ),
            ),

            // Typography
            Positioned(
              left: 24,
              right: 24,
              top: (size.height * 0.5) + 60,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
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
                      .fadeIn(delay: 350.ms, duration: 700.ms)
                      .slideY(begin: 0.2, end: 0, duration: 700.ms),

                  const SizedBox(height: 10),

                  Text(
                    'THE REASON YOU MATTER',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3.5,
                      color: context.textSecondary,
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 550.ms, duration: 700.ms),

                  const SizedBox(height: 18),

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
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'REELS · CHAT · LIVE · STUDIO',
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
                      .fadeIn(delay: 750.ms, duration: 600.ms),
                ],
              ),
            ),

            // Bottom loading bar
            Positioned(
              left: 32,
              right: 32,
              bottom: 48,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
