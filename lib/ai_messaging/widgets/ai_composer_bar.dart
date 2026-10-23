import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';
import '../models/ai_suggestion.dart';
import '../screens/live_voice_mode_screen.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class AiComposerBar extends StatelessWidget {
  final TextEditingController textController;
  final Function(AiComposerAction) onActionSelected;
  final bool isGenerating;

  const AiComposerBar({
    super.key,
    required this.textController,
    required this.onActionSelected,
    this.isGenerating = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isGenerating) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          border: Border(top: BorderSide(color: AppColors.outline.withValues(alpha: 0.2))),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: AnimatedLoadingIndicator(strokeWidth: 2, color: AppColors.brandBlue),
            ),
            const SizedBox(width: 12),
            Text('AI is composing...', style: TextStyle(color: AppColors.brandBlue, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        border: Border(top: BorderSide(color: AppColors.outline.withValues(alpha: 0.2))),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
            child: ActionChip(
              backgroundColor: AppColors.brandBlue.withValues(alpha: 0.1),
              side: BorderSide(color: AppColors.brandBlue),
              labelStyle: const TextStyle(
                color: AppColors.brandBlue,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
              avatar: const Icon(Icons.graphic_eq, size: 16, color: AppColors.brandBlue),
              label: const Text('Live Voice'),
              onPressed: () {
                 // Push Live Voice Mode Screen
                 Navigator.of(context).push(MaterialPageRoute(
                   builder: (_) => const _LiveVoiceModeRouteWrapper()
                 ));
              },
            ),
          ),
          _buildActionChip(context, AiComposerAction.improve, Icons.auto_fix_high, 'Improve'),
          _buildActionChip(context, AiComposerAction.shorten, Icons.compress, 'Shorten'),
          _buildActionChip(context, AiComposerAction.expand, Icons.expand, 'Expand'),
          _buildActionChip(context, AiComposerAction.makeProfessional, Icons.work_outline, 'Professional'),
          _buildActionChip(context, AiComposerAction.makeFriendly, Icons.mood, 'Friendly'),
          _buildActionChip(context, AiComposerAction.translate, Icons.translate, 'Translate'),
          _buildActionChip(context, AiComposerAction.reply, Icons.reply, 'Reply'),
          _buildActionChip(context, AiComposerAction.summarize, Icons.summarize, 'Summarize'),
          _buildActionChip(context, AiComposerAction.rewrite, Icons.refresh, 'Rewrite'),
        ],
      ),
    );
  }

  Widget _buildActionChip(BuildContext context, AiComposerAction action, IconData icon, String label) {
    final hasText = textController.text.trim().isNotEmpty;
    // Reply and summarize can be context-based (no input required), others need input.
    final bool isEnabled = hasText || action == AiComposerAction.reply || action == AiComposerAction.summarize;

    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
      child: ActionChip(
        backgroundColor: Colors.transparent,
        side: BorderSide(color: isEnabled ? AppColors.outline : AppColors.outline.withValues(alpha: 0.3)),
        labelStyle: TextStyle(
          color: isEnabled ? AppColors.textPrimary : AppColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
        avatar: Icon(
          icon, 
          size: 16, 
          color: isEnabled ? AppColors.brandBlue : AppColors.textMuted
        ),
        label: Text(label),
        onPressed: isEnabled ? () => onActionSelected(action) : null,
      ),
    );
  }
}

class _LiveVoiceModeRouteWrapper extends StatelessWidget {
  const _LiveVoiceModeRouteWrapper();

  @override
  Widget build(BuildContext context) {
    return const LiveVoiceModeScreen();
  }
}
