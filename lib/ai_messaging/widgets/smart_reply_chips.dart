import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ai_composer_service.dart';
import '../models/ai_suggestion.dart';
import '../../shared/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

class SmartReplyChips extends ConsumerStatefulWidget {
  final String conversationId;
  final String? lastMessageText;
  final ValueChanged<String> onSelectReply;

  const SmartReplyChips({
    super.key,
    required this.conversationId,
    this.lastMessageText,
    required this.onSelectReply,
  });

  @override
  ConsumerState<SmartReplyChips> createState() => _SmartReplyChipsState();
}

class _SmartReplyChipsState extends ConsumerState<SmartReplyChips> {
  List<String> _suggestions = [];
  bool _isLoading = false;
  String? _lastQueriedText;

  @override
  void initState() {
    super.initState();
    _fetchSuggestions();
  }

  @override
  void didUpdateWidget(covariant SmartReplyChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lastMessageText != oldWidget.lastMessageText) {
      _fetchSuggestions();
    }
  }

  Future<void> _fetchSuggestions() async {
    if (widget.lastMessageText == null || widget.lastMessageText!.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }

    if (widget.lastMessageText == _lastQueriedText) return;

    setState(() {
      _isLoading = true;
      _lastQueriedText = widget.lastMessageText;
    });

    try {
      final service = ref.read(aiComposerServiceProvider);
      final suggestion = await service.composeMessage(
        conversationId: widget.conversationId,
        messageId: '',
        action: AiComposerAction.reply,
        currentText: widget.lastMessageText!,
      );

      if (suggestion != null && suggestion.suggestedText.isNotEmpty) {
        if (mounted) {
          // Parse JSON array or split by newline if the AI returns a list
          // Assuming the AI returns options separated by newline or it's just one strong reply
          setState(() {
            _suggestions = suggestion.suggestedText.split('\n').where((s) => s.trim().isNotEmpty).toList();
            if (_suggestions.length > 3) {
              _suggestions = _suggestions.sublist(0, 3);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching smart replies: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: AppColors.brandBlue, size: 16)
                .animate(onPlay: (controller) => controller.repeat())
                .shimmer(duration: 1200.ms, color: Colors.white),
            const SizedBox(width: 8),
            Text('AI is thinking...', style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      );
    }

    if (_suggestions.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: _suggestions.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final reply = _suggestions[index];
          // Clean up numbering if any e.g. "1. Hello"
          final cleanReply = reply.replaceAll(RegExp(r'^\d+\.\s*'), '').replaceAll(RegExp(r'^-\s*'), '').replaceAll('"', '');

          return ActionChip(
            backgroundColor: AppColors.darkSurface,
            side: const BorderSide(color: AppColors.darkSurfaceHighlight, width: 1.5),
            labelStyle: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
            label: Text(cleanReply),
            onPressed: () => widget.onSelectReply(cleanReply),
          ).animate().fadeIn(delay: Duration(milliseconds: 100 * index)).slideX();
        },
      ),
    );
  }
}
