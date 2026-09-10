import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import '../../upload/services/ai_voice_service.dart';

class FloatingAiOrb extends ConsumerStatefulWidget {
  const FloatingAiOrb({super.key});

  @override
  ConsumerState<FloatingAiOrb> createState() => _FloatingAiOrbState();
}

class _FloatingAiOrbState extends ConsumerState<FloatingAiOrb> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  Offset _position = const Offset(20, 100);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this, 
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aiState = ref.watch(aiVoiceServiceProvider);
    
    // Animate faster when listening or processing
    if (aiState.isListening || aiState.isProcessing) {
      _pulseController.duration = const Duration(milliseconds: 500);
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
    } else {
      _pulseController.duration = const Duration(seconds: 2);
    }

    final double orbSize = 60.0;
    
    // Scale orb based on sound level if listening
    final double extraScale = aiState.isListening ? (aiState.soundLevel / 50).clamp(0.0, 0.5) : 0.0;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position += details.delta;
          });
        },
        onTap: () {
          final aiNotifier = ref.read(aiVoiceServiceProvider.notifier);
          if (aiState.isListening) {
            aiNotifier.stopListening();
          } else {
            aiNotifier.startListening();
          }
        },
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final double scale = 1.0 + (_pulseController.value * 0.1) + extraScale;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: orbSize,
                height: orbSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.mpepeMaroon,
                  border: Border.all(color: AppColors.mpepeGold, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: aiState.isListening 
                          ? AppColors.mpepeMaroon.withValues(alpha: 0.6)
                          : AppColors.mpepeMaroon.withValues(alpha: 0.3 * _pulseController.value),
                      blurRadius: 20 * scale,
                      spreadRadius: 5 * scale,
                    ),
                  ],
                ),
                child: Center(
                  child: aiState.isProcessing
                    ? const CircularProgressIndicator(color: AppColors.mpepeGold, strokeWidth: 2)
                    : Icon(
                        aiState.isListening ? Icons.mic : Icons.graphic_eq,
                        color: AppColors.mpepeGold,
                        size: 30,
                      ),
                ),
              ),
            );
          }
        ),
      ),
    );
  }
}
