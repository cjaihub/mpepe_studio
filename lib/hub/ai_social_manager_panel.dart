import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shared/theme/app_theme.dart';
// import 'package:flutter_markdown/flutter_markdown.dart'; // Future integration

class AISocialManagerPanel extends ConsumerStatefulWidget {
  const AISocialManagerPanel({super.key});

  @override
  ConsumerState<AISocialManagerPanel> createState() => _AISocialManagerPanelState();
}

class _AISocialManagerPanelState extends ConsumerState<AISocialManagerPanel> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  final List<Map<String, String>> _messages = [
    {
      'role': 'ai',
      'text': 'Hello! I am your Studio AI Manager. Select a video from the library, and I can generate titles, hashtags, and post it to your linked social channels.',
    }
  ];

  void _sendMessage() {
    if (_promptController.text.trim().isEmpty) return;
    
    setState(() {
      _messages.add({'role': 'user', 'text': _promptController.text});
    });
    
    final query = _promptController.text;
    _promptController.clear();
    _scrollToBottom();
    
    // Simulated AI Processing Delay
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _messages.add({
            'role': 'ai',
            'text': 'I understand you want to process "$query". I am currently in beta and waiting for full API integrations to post to Meta and TikTok directly. But I can help draft your content now!',
          });
        });
        _scrollToBottom();
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: AppColors.darkBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _buildMessageList(),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.darkBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.menu, color: AppColors.textSecondary),
            tooltip: 'History',
            onPressed: () {
              // TODO: Implement History drawer/sheet
            },
          ),
          // Center title with dropdown feel
          InkWell(
            onTap: () {
              // TODO: Model selector
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'MPEPE Advanced',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down, size: 20, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.edit_square, color: AppColors.textSecondary, size: 20),
                tooltip: 'New Chat',
                onPressed: () {
                  setState(() {
                    _messages.removeWhere((m) => m['role'] != 'ai' || m != _messages.first);
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 24),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isAI = msg['role'] == 'ai';

        if (isAI) {
          return _buildAIMessage(msg['text'] ?? '');
        } else {
          return _buildUserMessage(msg['text'] ?? '');
        }
      },
    );
  }

  Widget _buildAIMessage(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundImage: AssetImage('assets/logos/app_logo.png'),
            backgroundColor: Colors.transparent,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Future: Use MarkdownBody here when flutter_markdown is fully integrated
                Text(
                  text,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildIconBtn(Icons.thumb_up_alt_outlined),
                    const SizedBox(width: 8),
                    _buildIconBtn(Icons.thumb_down_alt_outlined),
                    const SizedBox(width: 8),
                    _buildIconBtn(Icons.copy_outlined),
                    const SizedBox(width: 8),
                    _buildIconBtn(Icons.refresh),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserMessage(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.darkSurfaceHighlight,
                borderRadius: BorderRadius.circular(20).copyWith(
                  topRight: const Radius.circular(4),
                ),
              ),
              child: Text(
                text,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconBtn(IconData icon) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Icon(icon, size: 18, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      color: AppColors.darkBackground,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24, // Safe area bottom
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Suggestions row (if empty input)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildSuggestionChip(Icons.video_library_outlined, 'Select Video'),
                const SizedBox(width: 8),
                _buildSuggestionChip(Icons.tag, 'Generate Hashtags'),
                const SizedBox(width: 8),
                _buildSuggestionChip(Icons.insights, 'Analyze Analytics'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Input field container (Gemini style)
          Container(
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: AppColors.outline.withValues(alpha: 0.3)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: AppColors.textSecondary),
                  onPressed: () {
                    // TODO: Open attachment/tools menu
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: _promptController,
                    focusNode: _focusNode,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
                    minLines: 1,
                    maxLines: 6,
                    decoration: InputDecoration(
                      hintText: 'Ask MPEPE AI...',
                      hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 16),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onChanged: (val) {
                      setState(() {}); // Rebuild to toggle send/mic button
                    },
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                if (_promptController.text.trim().isEmpty)
                  IconButton(
                    icon: const Icon(Icons.mic_none, color: AppColors.textSecondary),
                    onPressed: () {
                      // TODO: Voice input
                    },
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, right: 4),
                    child: CircleAvatar(
                      backgroundColor: AppColors.mpepeMaroon,
                      radius: 20,
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white, size: 18),
                        onPressed: _sendMessage,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'MPEPE AI may display inaccurate info, so double-check its answers.',
            style: TextStyle(fontSize: 10, color: AppColors.textSecondary.withValues(alpha: 0.7)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(IconData icon, String label) {
    return ActionChip(
      backgroundColor: AppColors.darkBackground,
      side: BorderSide(color: AppColors.outline.withValues(alpha: 0.5)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textPrimary),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
        ],
      ),
      onPressed: () {
        _promptController.text = label;
        _focusNode.requestFocus();
      },
    );
  }
}
