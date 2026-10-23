import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/ai_composer_service.dart';
import '../models/ai_suggestion.dart';
import '../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class AiComposerMenu extends ConsumerStatefulWidget {
  final String conversationId;
  final String currentText;
  final ValueChanged<String> onSuggestionAccepted;

  const AiComposerMenu({
    super.key,
    required this.conversationId,
    required this.currentText,
    required this.onSuggestionAccepted,
  });

  static Future<void> show(
    BuildContext context, {
    required String conversationId,
    required String currentText,
    required ValueChanged<String> onSuggestionAccepted,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => AiComposerMenu(
        conversationId: conversationId,
        currentText: currentText,
        onSuggestionAccepted: onSuggestionAccepted,
      ),
    );
  }

  @override
  ConsumerState<AiComposerMenu> createState() => _AiComposerMenuState();
}

class _AiComposerMenuState extends ConsumerState<AiComposerMenu> {
  bool _isLoading = false;
  String? _suggestedText;

  // ignore: unused_field
  AiComposerAction? _activeAction;
  final List<Map<String, dynamic>> _actions = [
    {'action': AiComposerAction.makeProfessional, 'label': 'Make Professional', 'icon': Icons.business_center},
    {'action': AiComposerAction.makeFriendly, 'label': 'Make Friendly', 'icon': Icons.sentiment_satisfied},
    {'action': AiComposerAction.shorten, 'label': 'Shorten', 'icon': Icons.close_fullscreen},
    {'action': AiComposerAction.expand, 'label': 'Expand', 'icon': Icons.open_in_full},
    {'action': AiComposerAction.rewrite, 'label': 'Rewrite', 'icon': Icons.refresh},
  ];

  Future<void> _processAction(AiComposerAction action) async {
    setState(() {
      _isLoading = true;
      _activeAction = action;
      _suggestedText = null;
    });

    try {
      final service = ref.read(aiComposerServiceProvider);
      final suggestion = await service.composeMessage(
        conversationId: widget.conversationId,
        messageId: '',
        action: action,
        currentText: widget.currentText,
      );

      if (mounted && suggestion != null) {
        setState(() {
          _suggestedText = suggestion.suggestedText;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate suggestion: $e', style: const TextStyle(color: Colors.white))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.brandBlue, size: 24),
              const SizedBox(width: 12),
              Text(
                'AI Composer',
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (_suggestedText != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.darkBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.3)),
              ),
              child: Text(
                _suggestedText!,
                style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 15),
              ),
            ).animate().fadeIn().slideY(begin: 0.1),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.darkSurfaceHighlight),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      setState(() {
                        _suggestedText = null;
                        _activeAction = null;
                      });
                    },
                    child: const Text('Discard', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      widget.onSuggestionAccepted(_suggestedText!);
                      Navigator.pop(context);
                    },
                    child: const Text('Use Text', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ).animate().fadeIn(),
          ] else if (_isLoading) ...[
            SizedBox(
              height: 120,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AnimatedLoadingIndicator(color: AppColors.brandBlue),
                    const SizedBox(height: 16),
                    Text(
                      'AI is writing...',
                      style: GoogleFonts.inter(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Text(
              'How should we rewrite your message?',
              style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _actions.map((actionInfo) {
                final action = actionInfo['action'] as AiComposerAction;
                final label = actionInfo['label'] as String;
                final icon = actionInfo['icon'] as IconData;

                return ActionChip(
                  avatar: Icon(icon, size: 16, color: AppColors.textPrimary),
                  backgroundColor: AppColors.darkSurfaceHighlight,
                  side: BorderSide.none,
                  labelStyle: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                  label: Text(label),
                  onPressed: () => _processAction(action),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
