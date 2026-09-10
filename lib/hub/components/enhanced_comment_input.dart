import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';

import '../../../shared/theme/app_theme.dart';

class EnhancedCommentInput extends ConsumerStatefulWidget {
  const EnhancedCommentInput({super.key});

  @override
  ConsumerState<EnhancedCommentInput> createState() => _EnhancedCommentInputState();
}

class _EnhancedCommentInputState extends ConsumerState<EnhancedCommentInput> {
  final TextEditingController _controller = TextEditingController();
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        _isTyping = _controller.text.isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.darkSurface.withValues(alpha: 0.8),
        border: Border(top: BorderSide(color: AppColors.outline.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildIconButton(Icons.emoji_emotions_outlined, AppColors.textSecondary),
            const SizedBox(width: 8),
            _buildIconButton(Icons.card_giftcard, AppColors.neonPink),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.darkBackground,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.outline),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Add a comment...',
                          hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    if (_isTyping)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: GestureDetector(
                          onTap: () {
                            // TODO: Dispatch comment to unified provider
                            _controller.clear();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.neonPurple,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.send, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.darkBackground,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.outline),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}
