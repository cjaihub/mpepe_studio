import 'package:flutter/material.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';

class HubAiScreen extends StatelessWidget {
  const HubAiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) => AppColors.aiGradient.createShader(bounds),
                        child: const Icon(Icons.auto_awesome, size: 24),
                      ),
                      const SizedBox(width: 8),
                      const Text('AI Assistant', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const MpepePill(text: 'Gemini', isAi: true),
                ],
              ),
              const SizedBox(height: 8),
              const Text('For your whole studio · updated just now', style: TextStyle(color: AppColors.ashText, fontSize: 13)),
              const SizedBox(height: 18),
              MpepeCard(
                borderColor: const Color(0x40FF6A00),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const MpepeAvatar(
                      text: '',
                      gradient: AppColors.aiGradient,
                      size: 34,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("This week's priority", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                          const SizedBox(height: 8),
                          const Text(
                            "Publish 2 more Shorts — they're driving 40% of new subscribers across Riverside channels this month",
                            style: TextStyle(color: AppColors.dustText, fontSize: 11, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              MpepeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: AppColors.studioAccent, size: 14),
                        const SizedBox(width: 8),
                        const Text('Cross-platform opportunity', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Your top video, \"Cinematic Travel Vlogs,\" hasn't been repurposed anywhere else. It could become 4 Shorts and 2 Reels once Instagram is connected.",
                      style: TextStyle(color: AppColors.ashText, fontSize: 12.5, height: 1.5),
                    ),
                    const SizedBox(height: 10),
                    const MpepePill(text: 'Connect Instagram', isOutline: true),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.lineSoft),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    const Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Ask AI about your studio…',
                          hintStyle: TextStyle(color: AppColors.dustText, fontSize: 12.5),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        style: TextStyle(color: AppColors.primaryText, fontSize: 12.5),
                      ),
                    ),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.aiGradient),
                      child: const Icon(Icons.send, color: Colors.white, size: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
