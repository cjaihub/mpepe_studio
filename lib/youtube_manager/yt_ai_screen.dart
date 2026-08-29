import 'package:flutter/material.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';

class YtAiScreen extends StatelessWidget {
  const YtAiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => AppColors.aiGradient.createShader(bounds),
              child: const Icon(Icons.auto_awesome),
            ),
            const SizedBox(width: 8),
            const Text('Gemini for YouTube', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            MpepeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Video Optimization', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  const Text('Select an uploaded video to generate titles, descriptions, and tags optimized for search.', style: TextStyle(color: AppColors.dustText, height: 1.4)),
                  const SizedBox(height: 16),
                  MpepeButton(text: 'Select Video', onPressed: () {}, isPrimary: false),
                ],
              ),
            ),
            const SizedBox(height: 16),
            MpepeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Content Ideas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  const Text('Based on your channel "Riverside Shorts", Gemini suggests:', style: TextStyle(color: AppColors.dustText, height: 1.4)),
                  const SizedBox(height: 12),
                  _buildIdeaItem('5 editing mistakes to avoid'),
                  _buildIdeaItem('Behind the scenes: Color grading'),
                  _buildIdeaItem('Best budget camera for 2026'),
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
                        hintText: 'Ask Gemini about your YouTube strategy...',
                        hintStyle: TextStyle(color: AppColors.dustText, fontSize: 12.5),
                        border: InputBorder.none,
                        isDense: true,
                      ),
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
    );
  }

  Widget _buildIdeaItem(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.ytAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
