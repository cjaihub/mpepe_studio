import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../../backend/inbox/models/conversation_model.dart';
import '../../../backend/inbox/models/message_model.dart';
import '../../../backend/inbox/providers/conversation_state_provider.dart';
import '../../../backend/inbox/repositories/canonical_inbox_repository.dart';
import '../../../shared/theme/app_theme.dart';

class CapabilityAwareComposer extends ConsumerStatefulWidget {
  final Conversation conversation;

  const CapabilityAwareComposer({
    super.key,
    required this.conversation,
  });

  @override
  ConsumerState<CapabilityAwareComposer> createState() =>
      _CapabilityAwareComposerState();
}

class _CapabilityAwareComposerState
    extends ConsumerState<CapabilityAwareComposer> {
  final TextEditingController _textController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    final currentUserId =
        FirebaseAuth.instance.currentUser?.uid ?? 'anonymous_user';
    final messageId = const Uuid().v4();
    final now = DateTime.now();

    final newMessage = InboxMessage(
      id: messageId,
      conversationId: widget.conversation.id,
      senderId: currentUserId,
      content: text,
      timestamp: now,
      status: MessageStatus.sent,
    );

    // Optimistically add message
    ref
        .read(conversationStateProvider(widget.conversation.id).notifier)
        .addOptimisticMessage(newMessage);

    _textController.clear();
    setState(() => _isSending = true);

    try {
      await ref
          .read(canonicalInboxRepositoryProvider)
          .ingestExternalMessage(widget.conversation, newMessage);
    } catch (_) {
      // Ingest error handled gracefully
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        MediaQuery.paddingOf(context).bottom + 8,
      ),
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(
          top: BorderSide(color: context.border, width: 1.0),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: TextField(
                  controller: _textController,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: context.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 13,
                      color: context.textMuted,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _handleSend(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: _isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.brandBlue),
                      ),
                    )
                  : const Icon(Icons.send_rounded,
                      color: AppColors.brandBlue, size: 22),
              onPressed: _handleSend,
            ),
          ],
        ),
      ),
    );
  }
}
