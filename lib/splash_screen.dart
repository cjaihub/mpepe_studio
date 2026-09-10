import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'shared/widgets/studio_background.dart';
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
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        context.go('/auth/main_login');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Force black background to ensure rich dark theme
      body: StudioBackground(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background animated roaming media icons
            ..._buildBackgroundIcons(),
            
            // Foreground logo and spinning dots
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer spinning dots ring (Clockwise)
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: Stack(
                      children: List.generate(16, (index) {
                        final angle = (index * pi * 2) / 16;
                        const offset = 100.0; // radius of the outer ring
                        return Positioned(
                          left: 110 + cos(angle) * offset - 4, // center + offset - half dot size
                          top: 110 + sin(angle) * offset - 4,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.mpepeMaroon.withValues(alpha: 0.8),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.mpepeMaroon.withValues(alpha: 0.6),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                )
                              ]
                            ),
                          ).animate(onPlay: (c) => c.repeat())
                           .fade(begin: 0.2, end: 1.0, duration: 1500.ms, delay: (index * 80).ms)
                           .scale(begin: const Offset(0.6, 0.6), end: const Offset(1.2, 1.2), duration: 1500.ms, delay: (index * 80).ms),
                        );
                      }),
                    ),
                  ).animate(onPlay: (c) => c.repeat()).rotate(duration: 10000.ms), // Slow clockwise rotation

                  // Inner spinning dots ring (Counter-clockwise)
                  SizedBox(
                    width: 170,
                    height: 170,
                    child: Stack(
                      children: List.generate(12, (index) {
                        final angle = (index * pi * 2) / 12;
                        const offset = 75.0; // radius of the inner ring
                        return Positioned(
                          left: 85 + cos(angle) * offset - 3, // center + offset - half dot size
                          top: 85 + sin(angle) * offset - 3,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                )
                              ]
                            ),
                          ).animate(onPlay: (c) => c.repeat())
                           .fade(begin: 0.1, end: 1.0, duration: 1200.ms, delay: (index * 100).ms)
                           .scale(begin: const Offset(0.5, 0.5), end: const Offset(1.5, 1.5), duration: 1200.ms, delay: (index * 100).ms),
                        );
                      }),
                    ),
                  ).animate(onPlay: (c) => c.repeat()).rotate(begin: 1.0, end: 0.0, duration: 8000.ms), // Slow counter-clockwise rotation

                  // Logo
                  Container(
                    width: 120, // Proper size to fit inside the inner dots
                    height: 120,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.transparent,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/logos/app_logo.png',
                      fit: BoxFit.contain, // Ensure it fits the circle
                    ),
                  ).animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(duration: 2000.ms, curve: Curves.easeInOutSine, begin: const Offset(0.95, 0.95), end: const Offset(1.05, 1.05))
                    .shimmer(delay: 1000.ms, duration: 2500.ms, color: Colors.white.withValues(alpha: 0.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBackgroundIcons() {
    final random = Random(42); // Fixed seed for consistent layout
    final iconDataList = [
      FontAwesomeIcons.youtube,
      FontAwesomeIcons.instagram,
      FontAwesomeIcons.tiktok,
      FontAwesomeIcons.video,
      FontAwesomeIcons.music,
      FontAwesomeIcons.headphones,
      FontAwesomeIcons.microphone,
      FontAwesomeIcons.camera,
      FontAwesomeIcons.tv,
      FontAwesomeIcons.film,
      FontAwesomeIcons.play,
      FontAwesomeIcons.clapperboard,
      FontAwesomeIcons.podcast,
      FontAwesomeIcons.compactDisc,
    ];

    return List.generate(25, (index) {
      final iconData = iconDataList[index % iconDataList.length];
      final top = random.nextDouble();
      final left = random.nextDouble();
      final size = 15.0 + random.nextDouble() * 45.0; // Varied sizes
      
      // Some icons are white, some are branded maroon for depth
      final isMaroon = random.nextBool();
      final opacity = isMaroon ? (0.05 + random.nextDouble() * 0.15) : (0.02 + random.nextDouble() * 0.08);
      final color = isMaroon ? AppColors.mpepeMaroon.withValues(alpha: opacity) : Colors.white.withValues(alpha: opacity);
      
      return Positioned(
        top: top * 850, // Approximate screen height
        left: left * 450, // Approximate screen width
        child: FaIcon(
          iconData,
          size: size,
          color: color,
        ).animate(onPlay: (controller) => controller.repeat(reverse: true))
          .moveY(
            begin: -40,
            end: 40,
            duration: (4000 + random.nextInt(5000)).ms,
            curve: Curves.easeInOutSine,
          )
          .moveX(
            begin: -30,
            end: 30,
            duration: (5000 + random.nextInt(4000)).ms,
            curve: Curves.easeInOutSine,
          )
          .scale(
            begin: const Offset(0.8, 0.8), 
            end: const Offset(1.2, 1.2), 
            duration: (3000 + random.nextInt(3000)).ms,
            curve: Curves.easeInOutSine,
          )
          .fade(
            begin: 0.5,
            end: 1.0,
            duration: (2000 + random.nextInt(2000)).ms,
            curve: Curves.easeInOutSine,
          ),
      );
    });
  }
}
