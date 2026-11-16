import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/messaging_repository.dart';
import '../../../backend/security/e2e_encryption_service.dart';
import '../../../shared/theme/app_theme.dart';
import '../chat_assist_service.dart';
import 'chat_compact_cards.dart';

/// Displays real highlighted/starred messages across all of the current user's
/// conversations (with client-side E2EE decryption when opening).
Future<void> showGlobalStarredMessagesSheet(BuildContext context, {required String uid}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _GlobalStarredMessagesSheet(uid: uid),
  );
}

class _GlobalStarredMessagesSheet extends ConsumerWidget {
  final String uid;
  const _GlobalStarredMessagesSheet({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlightsAsync = ref.watch(allChatHighlightsProvider(uid));

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border(top: BorderSide(color: context.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.star_rounded, color: AppColors.brandPink, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Starred Messages',
                    style: GoogleFonts.inter(
                      color: context.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: context.textSecondary, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.border),
          Expanded(
            child: highlightsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
              error: (_, _) => Center(
                child: Text(
                  'Could not load starred messages right now.',
                  style: GoogleFonts.inter(color: context.textMuted, fontSize: 13),
                ),
              ),
              data: (entries) {
                if (entries.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_outline_rounded, size: 42, color: context.textMuted.withValues(alpha: 0.5)),
                          const SizedBox(height: 10),
                          Text(
                            'No starred messages yet',
                            style: GoogleFonts.inter(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Long-press any message in a chat and tap Highlight to save it here.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(color: context.textMuted, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: context.border),
                  itemBuilder: (ctx, i) => _StarredEntryTile(uid: uid, entry: entries[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StarredEntryTile extends ConsumerStatefulWidget {
  final String uid;
  final GlobalHighlightEntry entry;

  const _StarredEntryTile({required this.uid, required this.entry});

  @override
  ConsumerState<_StarredEntryTile> createState() => _StarredEntryTileState();
}

class _StarredEntryTileState extends ConsumerState<_StarredEntryTile> {
  late Future<({ChatModel? chat, MessageModel? msg, String text})> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  Future<({ChatModel? chat, MessageModel? msg, String text})> _resolve() async {
    final repo = ref.read(messagingRepositoryProvider);
    final results = await Future.wait([
      repo.getChat(widget.entry.chatId, widget.uid),
      repo.getMessage(widget.entry.chatId, widget.entry.messageId),
    ]);
    final chat = results[0] as ChatModel?;
    final msg = results[1] as MessageModel?;
    var text = msg?.text ?? '';
    if (msg != null && msg.isEncrypted && chat != null) {
      final partner = chat.participants.firstWhere((id) => id != widget.uid, orElse: () => '');
      if (partner.isNotEmpty) {
        try {
          final e2ee = ref.read(e2eEncryptionServiceProvider);
          final pub = await e2ee.getRecipientPublicKey(partner);
          if (pub != null && pub.isNotEmpty) {
            text = await e2ee.decryptMessage(msg.text, pub);
          }
        } catch (_) {}
      }
    }
    return (chat: chat, msg: msg, text: text);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({ChatModel? chat, MessageModel? msg, String text})>(
      future: _future,
      builder: (ctx, snap) {
        final data = snap.data;
        final chatTitle = data?.chat?.title?.isNotEmpty == true ? data!.chat!.title! : 'Conversation';
        final msg = data?.msg;
        final snippet = data == null
            ? 'Loading…'
            : (data.text.isNotEmpty
                ? data.text
                : (msg?.fileName ?? msg?.mediaType ?? 'Message unavailable'));
        final ts = msg?.timestamp.toDate() ?? widget.entry.highlightedAt.toDate();

        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.brandBlue.withValues(alpha: 0.14),
            backgroundImage: data?.chat?.avatarUrl?.isNotEmpty == true ? NetworkImage(data!.chat!.avatarUrl!) : null,
            child: data?.chat?.avatarUrl?.isNotEmpty != true
                ? const Icon(Icons.star_rounded, color: AppColors.brandPink, size: 17)
                : null,
          ),
          title: Text(
            chatTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            snippet,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                ChatDateSeparator.label(ts),
                style: GoogleFonts.inter(color: context.textMuted, fontSize: 10.5),
              ),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: () => ref
                    .read(chatAssistServiceProvider)
                    .setHighlight(widget.uid, widget.entry.chatId, widget.entry.messageId, false),
                child: Icon(Icons.close_rounded, size: 15, color: context.textMuted),
              ),
            ],
          ),
          onTap: () {
            Navigator.pop(context);
            context.push('/hub/messages/${widget.entry.chatId}');
          },
        );
      },
    );
  }
}
