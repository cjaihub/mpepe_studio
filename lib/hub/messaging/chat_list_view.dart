import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../backend/messaging_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/animated_streaming_markdown.dart';

class ChatListView extends StatelessWidget {
  final List<MessageModel> messages;
  final String? currentUserId;
  final Function(String) onSuggestionTap;

  const ChatListView({
    super.key,
    required this.messages,
    required this.currentUserId,
    required this.onSuggestionTap,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: Text(
          'No messages yet. Say hello to the AI!',
          style: GoogleFonts.inter(color: Colors.white54),
        ),
      );
    }

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isMe = message.senderId == currentUserId;
        final isLast = index == 0;
        return _buildMessageBubble(context, message, isMe, isLast);
      },
    );
  }

  Widget _buildMessageBubble(BuildContext context, MessageModel message, bool isMe, bool isLast) {
    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: BoxDecoration(
              color: isMe ? AppColors.brandBlue : AppColors.darkSurfaceHighlight,
              borderRadius: BorderRadius.circular(16).copyWith(
                bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
                bottomLeft: !isMe ? const Radius.circular(4) : const Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isMe)
                  Text(message.text, style: GoogleFonts.inter(color: Colors.white, fontSize: 14))
                else
                  // If it's the latest AI message, apply streaming effect
                  isLast
                      ? AnimatedStreamingMarkdown(
                          text: message.text,
                          typingSpeed: const Duration(milliseconds: 15),
                        )
                      : MarkdownBody(
                          data: message.text,
                          styleSheet: MarkdownStyleSheet(
                            p: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                            code: GoogleFonts.firaCode(
                                color: AppColors.neonGreen,
                                fontSize: 12,
                                backgroundColor: Colors.transparent),
                            codeblockPadding: const EdgeInsets.all(12),
                            codeblockDecoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('h:mm a').format(message.timestamp.toDate()),
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
          ),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutQuad),

        // Phase 3: Smart Follow Up Suggestions
        if (!isMe && isLast) _buildSmartFollowUps(message.text),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSmartFollowUps(String text) {
    final lowerText = text.toLowerCase();
    List<String> suggestions = [];

    if (lowerText.contains('screenshot') || lowerText.contains('image')) {
      suggestions.addAll(['Analyze Image', 'Save to Desktop', 'Delete Image']);
    } else if (lowerText.contains('error') || lowerText.contains('failed')) {
      suggestions.addAll(['Check Logs', 'Retry Command', 'Get System Info']);
    } else if (lowerText.contains('file') || lowerText.contains('contents')) {
      suggestions.addAll(['Summarize File', 'Edit File', 'Delete File']);
    } else {
      suggestions.addAll(['What else can you do?', 'System Status']);
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8.0, top: 4.0),
      child: Wrap(
        spacing: 8,
        children: suggestions.map((s) => ActionChip(
              backgroundColor: AppColors.brandBlue.withValues(alpha: 0.2),
              side: BorderSide(color: AppColors.brandBlue.withValues(alpha: 0.5)),
              labelStyle: GoogleFonts.inter(color: AppColors.brandBlue, fontSize: 11, fontWeight: FontWeight.w600),
              label: Text(s),
              padding: EdgeInsets.zero,
              onPressed: () => onSuggestionTap(s),
            )).toList(),
      ),
    ).animate().fadeIn(delay: 800.ms).slideY(begin: 0.2, end: 0);
  }
}
