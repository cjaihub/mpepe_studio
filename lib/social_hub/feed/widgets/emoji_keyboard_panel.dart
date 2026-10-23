import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../shared/theme/app_theme.dart';

class EmojiKeyboardPanel extends StatefulWidget {
  final TextEditingController controller;
  final bool isVisible;

  const EmojiKeyboardPanel({
    super.key,
    required this.controller,
    required this.isVisible,
  });

  @override
  State<EmojiKeyboardPanel> createState() => _EmojiKeyboardPanelState();
}

class _EmojiKeyboardPanelState extends State<EmojiKeyboardPanel> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const List<String> _popularEmojis = [
    '❤️', '🔥', '😂', '😍', '👏', '🙌', '✨', '🎉',
    '💯', '🤩', '🚀', '🥺', '😭', '🥰', '🙏', '😎',
    '🤔', '👀', '💪', '🥳', '🤯', '💖', '👑', '⭐',
  ];

  static const List<String> _faceEmojis = [
    '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂',
    '🙂', '🙃', '😉', '😊', '😇', '🥰', '😍', '🤩',
    '😘', '😗', '😚', '😙', '😋', '😛', '😜', '🤪',
    '😝', '🤑', '🤗', '🤭', '🤫', '🤔', '🤐', '🤨',
    '😐', '😑', '😶', '😏', '😒', '🙄', '😬', '🤥',
  ];

  static const List<String> _gestureEmojis = [
    '👍', '👎', '👊', '✊', '🤛', '🤜', '🤞', '✌️',
    '🤟', '🤘', '👌', '🤌', '🤏', '👈', '👉', '👆',
    '👇', '☝️', '✋', '🤚', '🖐️', '🖖', '👋', '🤙',
    '💪', '🦾', '🙏', '👏', '🙌', '👐', '🤲', '🤝',
  ];

  static const List<String> _heartEmojis = [
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍',
    '🤎', '💔', '❣️', '💕', '💞', '💓', '💗', '💖',
    '💘', '💝', '💟', '💌', '💐', '🌸', '💮', '🌹',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _insertEmoji(String emoji) {
    HapticFeedback.lightImpact();
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (selection.start >= 0 && selection.end >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, emoji);
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + emoji.length),
      );
    } else {
      widget.controller.text = text + emoji;
      widget.controller.selection = TextSelection.collapsed(offset: widget.controller.text.length);
    }
  }

  void _backspace() {
    HapticFeedback.lightImpact();
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (text.isEmpty) return;
    if (selection.start > 0) {
      // Handle surrogate pairs/grapheme clusters safely
      final characters = text.characters;
      if (characters.isNotEmpty) {
        final newText = characters.skipLast(1).toString();
        widget.controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: SizedBox(
        height: widget.isVisible ? 260 : 0,
        child: widget.isVisible
            ? Container(
                color: context.bg,
                child: Column(
                  children: [
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: context.surface,
                        border: Border(bottom: BorderSide(color: context.border, width: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TabBar(
                              controller: _tabController,
                              indicatorColor: AppColors.brandBlue,
                              indicatorWeight: 2,
                              labelColor: AppColors.brandBlue,
                              unselectedLabelColor: context.textMuted,
                              tabs: const [
                                Tab(icon: Icon(Icons.flash_on_rounded, size: 20)),
                                Tab(icon: Icon(Icons.sentiment_satisfied_rounded, size: 20)),
                                Tab(icon: Icon(Icons.pan_tool_rounded, size: 20)),
                                Tab(icon: Icon(Icons.favorite_rounded, size: 20)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.backspace_outlined, size: 20, color: context.textSecondary),
                            onPressed: _backspace,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildEmojiGrid(_popularEmojis),
                          _buildEmojiGrid(_faceEmojis),
                          _buildEmojiGrid(_gestureEmojis),
                          _buildEmojiGrid(_heartEmojis),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildEmojiGrid(List<String> emojis) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: emojis.length,
      itemBuilder: (context, index) {
        final emoji = emojis[index];
        return InkWell(
          onTap: () => _insertEmoji(emoji),
          borderRadius: BorderRadius.circular(8),
          child: Center(
            child: Text(
              emoji,
              style: const TextStyle(fontSize: 24),
            ),
          ),
        );
      },
    );
  }
}
