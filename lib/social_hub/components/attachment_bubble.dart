import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/inbox/models/attachment_model.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/encrypted_media_loader.dart';
import 'audio_player_widget.dart';

class AttachmentBubble extends StatelessWidget {
  final Attachment attachment;
  final bool isMine;

  const AttachmentBubble({
    super.key,
    required this.attachment,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    if (attachment.type == AttachmentType.image || attachment.type == AttachmentType.video) {
      return _buildMediaPreview(context);
    }
    if (attachment.type == AttachmentType.audio || attachment.type == AttachmentType.voice) {
      if (attachment.encryptionKey != null) {
        return EncryptedMediaLoader(
          attachment: attachment,
          fallback: _buildFallbackIcon(context),
          builder: (context, file) => AudioPlayerWidget(
            audioUrl: file.path,
            isOutgoing: isMine,
          ),
        );
      }
      return AudioPlayerWidget(
        audioUrl: attachment.downloadUrl ?? attachment.storagePath,
        isOutgoing: isMine,
      );
    }
    return _buildDocumentPreview(context);
  }

  Widget _buildMediaPreview(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 250, maxWidth: 250),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMine ? AppColors.brandBlue.withValues(alpha: 0.4) : context.border,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (attachment.encryptionKey != null)
            EncryptedMediaLoader(
              attachment: attachment,
              fallback: _buildFallbackIcon(context),
              builder: (context, file) => Image.file(
                file,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _buildFallbackIcon(context),
              ),
            )
          else if (attachment.downloadUrl != null && attachment.downloadUrl!.isNotEmpty)
            Image.network(
              attachment.downloadUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _buildFallbackIcon(context),
            )
          else
            _buildFallbackIcon(context),
            
          if (attachment.type == AttachmentType.video)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 24),
            ),
        ],
      ),
    );
  }

  Widget _buildFallbackIcon(BuildContext context) {
    return Container(
      color: context.surfaceMid,
      alignment: Alignment.center,
      child: Icon(
        attachment.type == AttachmentType.video ? Icons.videocam : Icons.image,
        color: context.textSecondary,
        size: 40,
      ),
    );
  }

  Widget _buildDocumentPreview(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMine ? AppColors.brandBlue.withValues(alpha: 0.12) : context.surfaceMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMine ? AppColors.brandBlue.withValues(alpha: 0.3) : context.border,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: attachment.type == AttachmentType.pdf ? Colors.redAccent.withValues(alpha: 0.2) : Colors.blueAccent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              attachment.type == AttachmentType.pdf ? Icons.description : Icons.insert_drive_file_outlined,
              color: attachment.type == AttachmentType.pdf ? Colors.redAccent : Colors.blueAccent,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.fileName,
                  style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatBytes(attachment.fileSize),
                  style: GoogleFonts.inter(
                    color: context.textSecondary,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double b = bytes.toDouble();
    while (b >= 1024 && i < suffixes.length - 1) {
      b /= 1024;
      i++;
    }
    return '${b.toStringAsFixed(1)} ${suffixes[i]}';
  }
}
