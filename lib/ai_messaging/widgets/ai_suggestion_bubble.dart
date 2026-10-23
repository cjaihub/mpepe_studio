import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';
import '../models/ai_suggestion.dart';

class AiSuggestionBubble extends StatelessWidget {
  final AiSuggestion suggestion;
  final VoidCallback onAccept;
  final VoidCallback onEdit;
  final VoidCallback onReject;
  final VoidCallback onRegenerate;

  const AiSuggestionBubble({
    super.key,
    required this.suggestion,
    required this.onAccept,
    required this.onEdit,
    required this.onReject,
    required this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestion.status == AiSuggestionStatus.rejected) {
      return const SizedBox.shrink(); // Hide if rejected
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.darkSurfaceHighlight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppColors.brandBlue, size: 14),
                const SizedBox(width: 8),
                Text(
                  'AI Suggestion (${suggestion.action.name})',
                  style: const TextStyle(color: AppColors.brandBlue, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              suggestion.suggestedText,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          Divider(height: 1, color: AppColors.outline.withValues(alpha: 0.2)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(Icons.close, 'Reject', AppColors.textMuted, onReject),
                _buildActionButton(Icons.refresh, 'Regenerate', AppColors.textSecondary, onRegenerate),
                _buildActionButton(Icons.edit, 'Edit', AppColors.textSecondary, onEdit),
                _buildActionButton(Icons.send, 'Accept & Send', AppColors.brandBlue, onAccept, isPrimary: true),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color, VoidCallback onTap, {bool isPrimary = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: isPrimary ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
