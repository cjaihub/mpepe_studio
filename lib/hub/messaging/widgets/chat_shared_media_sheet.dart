import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/messaging_repository.dart';
import '../../../shared/theme/app_theme.dart';
import 'chat_compact_cards.dart';
import 'peer_encrypted_media.dart';

/// Tabbed gallery for a conversation's shared Media (photos, videos, GIFs),
/// Files (documents, audio, archives, code), and Links.
Future<void> showChatSharedMediaSheet(
  BuildContext context, {
  required List<MessageModel> messages,
  required String Function(MessageModel) displayTextOf,
  required String? peerPublicKey,
  required void Function(MessageModel) onOpenMedia,
  required void Function(MessageModel) onSaveFile,
  required void Function(String url) onOpenUrl,
}) {
  final media = messages
      .where((m) =>
          m.mediaUrl != null &&
          (m.mediaType == 'image' ||
              m.mediaType == 'video' ||
              m.mediaType == 'video_note' ||
              m.mediaType == 'gif'))
      .toList();

  final files = messages
      .where((m) =>
          m.mediaUrl != null &&
          (m.mediaType == 'document' ||
              m.mediaType == 'file' ||
              m.mediaType == 'archive' ||
              m.mediaType == 'code' ||
              m.mediaType == 'audio'))
      .toList();

  final links = <(MessageModel msg, String url)>[];
  for (final m in messages) {
    final text = displayTextOf(m);
    final url = firstLinkIn(text);
    if (url != null) links.add((m, url));
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SharedMediaSheet(
      media: media,
      files: files,
      links: links,
      peerPublicKey: peerPublicKey,
      onOpenMedia: onOpenMedia,
      onSaveFile: onSaveFile,
      onOpenUrl: onOpenUrl,
    ),
  );
}

class _SharedMediaSheet extends StatelessWidget {
  final List<MessageModel> media;
  final List<MessageModel> files;
  final List<(MessageModel msg, String url)> links;
  final String? peerPublicKey;
  final void Function(MessageModel) onOpenMedia;
  final void Function(MessageModel) onSaveFile;
  final void Function(String url) onOpenUrl;

  const _SharedMediaSheet({
    required this.media,
    required this.files,
    required this.links,
    required this.peerPublicKey,
    required this.onOpenMedia,
    required this.onSaveFile,
    required this.onOpenUrl,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.82,
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
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Media, Files & Links',
                      style: GoogleFonts.inter(
                        color: context.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: context.textSecondary, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            TabBar(
              labelColor: AppColors.brandBlue,
              unselectedLabelColor: context.textSecondary,
              indicatorColor: AppColors.brandBlue,
              labelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
              tabs: [
                Tab(text: 'Media (${media.length})'),
                Tab(text: 'Files (${files.length})'),
                Tab(text: 'Links (${links.length})'),
              ],
            ),
            Divider(height: 1, color: context.border),
            Expanded(
              child: TabBarView(
                children: [
                  _buildMediaGrid(context),
                  _buildFilesList(context),
                  _buildLinksList(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaGrid(BuildContext context) {
    if (media.isEmpty) {
      return _empty(context, Icons.photo_library_outlined, 'No shared photos or videos yet');
    }
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: media.length,
      itemBuilder: (ctx, i) {
        final m = media[i];
        return InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () {
            Navigator.pop(ctx);
            onOpenMedia(m);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (m.mediaType == 'image' || m.mediaType == 'gif')
                  m.mediaEncrypted
                      ? PeerEncryptedMedia(
                          url: m.mediaUrl!,
                          peerPublicKey: peerPublicKey,
                          fileName: m.fileName,
                          builder: (_, path) => Image(image: chatMediaImage(path), fit: BoxFit.cover),
                        )
                      : Image(
                          image: chatMediaImage(m.mediaUrl!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => ColoredBox(color: ctx.surfaceMid),
                        )
                else
                  Container(
                    color: ctx.surfaceMid,
                    child: Icon(
                      m.mediaType == 'video_note' ? Icons.slow_motion_video_rounded : Icons.play_circle_outline_rounded,
                      color: AppColors.brandBlue,
                      size: 30,
                    ),
                  ),
                if (m.mediaType == 'video' || m.mediaType == 'video_note')
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_rounded, color: Colors.white, size: 11),
                          if (m.voiceDuration != null) ...[
                            const SizedBox(width: 2),
                            Text(
                              m.voiceDuration!,
                              style: GoogleFonts.inter(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilesList(BuildContext context) {
    if (files.isEmpty) {
      return _empty(context, Icons.folder_open_rounded, 'No shared documents or voice files yet');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      itemCount: files.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: context.border),
      itemBuilder: (ctx, i) {
        final m = files[i];
        final name = m.fileName ?? (m.mediaType == 'audio' ? 'Voice note' : 'Document');
        final kind = chatFileKind(name, m.mediaType);
        final size = chatFileSize(m.fileSize);
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              m.mediaType == 'audio' ? Icons.graphic_eq_rounded : kind.icon,
              size: 18,
              color: AppColors.brandBlue,
            ),
          ),
          title: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(color: ctx.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            [if (size.isNotEmpty) size, if (m.voiceDuration != null) m.voiceDuration!, ChatDateSeparator.label(m.timestamp.toDate())].join(' · '),
            style: GoogleFonts.inter(color: ctx.textMuted, fontSize: 11),
          ),
          trailing: IconButton(
            tooltip: 'Save / Share',
            icon: Icon(Icons.download_rounded, size: 19, color: ctx.textSecondary),
            onPressed: () {
              Navigator.pop(ctx);
              onSaveFile(m);
            },
          ),
          onTap: () {
            Navigator.pop(ctx);
            onOpenMedia(m);
          },
        );
      },
    );
  }

  Widget _buildLinksList(BuildContext context) {
    if (links.isEmpty) {
      return _empty(context, Icons.link_off_rounded, 'No links shared in this chat');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      itemCount: links.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: context.border),
      itemBuilder: (ctx, i) {
        final (msg, url) = links[i];
        final host = Uri.tryParse(url)?.host ?? url;
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.brandPink.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(Icons.public_rounded, size: 18, color: AppColors.brandPink),
          ),
          title: Text(
            url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(color: ctx.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '$host · ${ChatDateSeparator.label(msg.timestamp.toDate())}',
            style: GoogleFonts.inter(color: ctx.textMuted, fontSize: 11),
          ),
          trailing: Icon(Icons.open_in_new_rounded, size: 16, color: ctx.textMuted),
          onTap: () {
            Navigator.pop(ctx);
            onOpenUrl(url);
          },
        );
      },
    );
  }

  Widget _empty(BuildContext context, IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: context.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          Text(text, style: GoogleFonts.inter(color: context.textMuted, fontSize: 13)),
        ],
      ),
    );
  }
}
