import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import 'dart:math';

class VoiceWaveVisualizer extends StatefulWidget {
  final bool isSpeaking;
  final double height;
  final double width;
  
  const VoiceWaveVisualizer({
    super.key, 
    this.isSpeaking = true,
    this.height = 100,
    this.width = double.infinity,
  });

  @override
  State<VoiceWaveVisualizer> createState() => _VoiceWaveVisualizerState();
}

class _VoiceWaveVisualizerState extends State<VoiceWaveVisualizer> {
  final int barCount = 35;
  final Random random = Random();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: widget.width,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(barCount, (index) {
          // Create a wave effect by giving edge bars lower max heights
          double position = index / (barCount - 1);
          double distanceFromCenter = (0.5 - position).abs() * 2; // 0 at center, 1 at edges
          double maxBarHeight = widget.height * (1.0 - (distanceFromCenter * 0.7)); // center is taller

          return Container(
            width: 4,
            height: widget.isSpeaking ? 10 : 4, // Idle state
            decoration: BoxDecoration(
              color: AppColors.mpepeMaroon,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: AppColors.mpepeMaroon.withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                )
              ]
            ),
          ).animate(
            onPlay: (controller) {
              if (widget.isSpeaking) {
                controller.repeat(reverse: true);
              }
            },
            target: widget.isSpeaking ? 1 : 0,
          ).scaleY(
            begin: 1,
            end: maxBarHeight / 10,
            duration: Duration(milliseconds: 300 + random.nextInt(400)),
            curve: Curves.easeInOutSine,
          );
        }),
      ),
    );
  }
}
