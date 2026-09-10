import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';

class YtAiScreen extends StatelessWidget {
  const YtAiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StudioBackground(
      backgroundIcons: const [Icons.auto_awesome, Icons.model_training, Icons.lightbulb_outline],
      appBar: AppBar(
        title: Row(
          children: [
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => AppColors.aiGradient.createShader(bounds),
              child: const Icon(Icons.auto_awesome),
            ),
            const SizedBox(width: 8),
            Text('Gemini Engine', style: AppTheme.h1Style.copyWith(fontSize: 22, color: Theme.of(context).colorScheme.onSurface)),
          ],
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => context.pop(),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  _buildAIToolsHeader(context).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05),
                  const SizedBox(height: 24),
                  
                  Text('Content Strategy', style: AppTheme.h2Style.copyWith(color: Theme.of(context).colorScheme.onSurface)).animate().fadeIn(delay: 100.ms),
                  const SizedBox(height: 16),
                  _buildContentIdeaCard(context, '5 Editing Mistakes Destroying Your Retention', 92, 'Tutorial').animate().fadeIn(delay: 200.ms).slideX(begin: 0.1),
                  _buildContentIdeaCard(context, 'Is the M4 Mac Studio Worth It? (Creator Review)', 88, 'Review').animate().fadeIn(delay: 300.ms).slideX(begin: 0.1),
                  _buildContentIdeaCard(context, 'Behind the Scenes: Color Grading My Cinematic Vlog', 75, 'Vlog').animate().fadeIn(delay: 400.ms).slideX(begin: 0.1),
                  
                  const SizedBox(height: 32),
                  Text('Optimization Suites', style: AppTheme.h2Style.copyWith(color: Theme.of(context).colorScheme.onSurface)).animate().fadeIn(delay: 500.ms),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      _buildSuiteCard(context, Icons.title, 'Title & Tags', 'Generate high-CTR metadata').animate().fadeIn(delay: 600.ms).slideY(begin: 0.1),
                      const SizedBox(width: 12),
                      _buildSuiteCard(context, Icons.image, 'Thumbnails', 'A/B testing & generation').animate().fadeIn(delay: 700.ms).slideY(begin: 0.1),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildSuiteCard(context, Icons.closed_caption, 'Captions', 'Auto-translate in 50 langs').animate().fadeIn(delay: 800.ms).slideY(begin: 0.1),
                      const SizedBox(width: 12),
                      _buildSuiteCard(context, Icons.forum, 'Auto-Reply', 'Smart community management').animate().fadeIn(delay: 900.ms).slideY(begin: 0.1),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                ],
              ),
            ),
            
            // Floating AI Input
            _buildAiChatInput(context).animate().slideY(begin: 1.0, duration: 600.ms, curve: Curves.easeOutBack),
          ],
        ),
      ),
    );
  }
  Widget _buildAIToolsHeader(BuildContext context) {
    return MpepeCard(
      borderColor: AppColors.neonPurple.withValues(alpha: 0.4),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.neonPurple.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.rocket_launch, color: AppColors.neonPurple, size: 24),
              ),
              const SizedBox(width: 12),
              Text('Channel Analysis Complete', style: AppTheme.h2Style.copyWith(fontSize: 18)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Gemini has analyzed your last 50 videos. Your audience responds best to highly-edited tech tutorials under 10 minutes. We generated 3 new ideas tailored to this insight.',
            style: AppTheme.bodyStyle.copyWith(height: 1.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8), fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildContentIdeaCard(BuildContext context, String title, int score, String category) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Colors.green.shade400, Colors.teal],
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$score', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                  const Text('score', style: TextStyle(color: Colors.white70, fontSize: 8)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.bodyStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 15, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    MpepePill(text: category, isOutline: true),
                    const SizedBox(width: 10),
                    Text('High Potential', style: AppTheme.bodyStyle.copyWith(fontSize: 13, color: AppColors.neonGreen, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildSuiteCard(BuildContext context, IconData icon, String title, String subtitle) {
    return Expanded(
      child: MpepeCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => AppColors.premiumGradient.createShader(bounds),
              child: Icon(icon, size: 32),
            ),
            const SizedBox(height: 12),
            Text(title, style: AppTheme.bodyStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 4),
            Text(subtitle, style: AppTheme.bodyStyle.copyWith(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          ],
        ),
      ),
    );
  }

  Widget _buildAiChatInput(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16.0, top: 8.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => AppColors.aiGradient.createShader(bounds),
                child: const Icon(Icons.auto_awesome, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Ask Gemini for video ideas or advice...',
                    hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.aiGradient,
                ),
                child: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
