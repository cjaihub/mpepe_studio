import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/user_service.dart';
import '../../../shared/theme/app_theme.dart';

/// Groups reactions by emoji (e.g., `❤️ 3`) and lets the user toggle their own
/// reaction with a tap or view who reacted on long-press.
class ChatReactionStrip extends StatelessWidget {
  final Map<String, String> reactions;
  final String myUid;
  final Future<AppUser?> Function(String uid) getUser;
  final void Function(String emoji, String? currentMine) onToggle;

  const ChatReactionStrip({
    super.key,
    required this.reactions,
    required this.myUid,
    required this.getUser,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    final counts = <String, List<String>>{};
    reactions.forEach((uid, emoji) {
      if (emoji.isEmpty) return;
      counts.putIfAbsent(emoji, () => []).add(uid);
    });
    if (counts.isEmpty) return const SizedBox.shrink();

    final myEmoji = reactions[myUid];

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: counts.entries.map((entry) {
          final emoji = entry.key;
          final reactors = entry.value;
          final mine = myEmoji == emoji;

          return InkWell(
            borderRadius: BorderRadius.circular(AppRadius.full),
            onTap: () {
              HapticFeedback.selectionClick();
              onToggle(emoji, myEmoji);
            },
            onLongPress: () {
              HapticFeedback.lightImpact();
              _showReactorsSheet(context, counts);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: mine ? AppColors.brandPink.withValues(alpha: 0.16) : context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: mine ? AppColors.brandPink : context.border,
                  width: mine ? 1.1 : 0.9,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 12)),
                  if (reactors.length > 1) ...[
                    const SizedBox(width: 3),
                    Text(
                      '${reactors.length}',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: mine ? AppColors.brandPink : context.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showReactorsSheet(BuildContext context, Map<String, List<String>> grouped) {
    final entries = <(String uid, String emoji)>[];
    grouped.forEach((emoji, uids) {
      for (final u in uids) {
        entries.add((u, emoji));
      }
    });

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: ctx.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Reactions (${entries.length})',
                style: GoogleFonts.inter(
                  color: ctx.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: ctx.border),
                  itemBuilder: (_, i) {
                    final (uid, emoji) = entries[i];
                    final isMe = uid == myUid;
                    return FutureBuilder<AppUser?>(
                      future: getUser(uid),
                      builder: (context, snap) {
                        final user = snap.data;
                        final name = isMe
                            ? 'You'
                            : (user != null && user.fullName.isNotEmpty
                                ? user.fullName
                                : (user?.username ?? 'Oneova User'));
                        final avatar = user?.profilePhotoUrl;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.brandBlue,
                            backgroundImage:
                                avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
                            child: avatar == null || avatar.isEmpty
                                ? Text(
                                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : null,
                          ),
                          title: Text(
                            name,
                            style: GoogleFonts.inter(
                              color: context.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: isMe
                              ? Text(
                                  'Tap to remove your reaction',
                                  style: GoogleFonts.inter(color: context.textMuted, fontSize: 11),
                                )
                              : null,
                          trailing: Text(emoji, style: const TextStyle(fontSize: 20)),
                          onTap: isMe
                              ? () {
                                  Navigator.pop(ctx);
                                  onToggle(emoji, emoji);
                                }
                              : null,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
