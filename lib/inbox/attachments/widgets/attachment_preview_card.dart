import 'package:flutter/material.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import '../../../backend/inbox/models/attachment_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class AttachmentPreviewCard extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback onDelete;

  const AttachmentPreviewCard({
    super.key,
    required this.attachment,
    required this.onDelete,
  });

  IconData _getIconForType() {
    switch (attachment.type) {
      case AttachmentType.image:
        return Icons.image;
      case AttachmentType.video:
        return Icons.videocam;
      case AttachmentType.audio:
      case AttachmentType.voice:
        return Icons.audiotrack;
      case AttachmentType.pdf:
        return Icons.picture_as_pdf;
      case AttachmentType.document:
        return Icons.description;
      case AttachmentType.link:
        return Icons.link;
      default:
        return Icons.insert_drive_file;
    }
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.download, color: Colors.white),
            title: const Text('Download', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              if (attachment.downloadUrl != null) {
                launchUrl(Uri.parse(attachment.downloadUrl!));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.share, color: Colors.white),
            title: const Text('Share', style: TextStyle(color: Colors.white)),
            onTap: () {
              // Implementation would use share_plus
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.forward, color: Colors.white),
            title: const Text('Forward', style: TextStyle(color: Colors.white)),
            onTap: () {
              // Implementation would open contact picker
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Delete', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              onDelete();
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (attachment.status == AttachmentStatus.validating) {
      return _buildValidationState();
    }

    if (attachment.type == AttachmentType.image && attachment.downloadUrl != null) {
      return GestureDetector(
        onLongPress: () => _showContextMenu(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            attachment.downloadUrl!,
            width: 200,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: 200,
                height: 150,
                color: AppColors.darkSurfaceHighlight,
                child: const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
              );
            },
            errorBuilder: (context, error, stackTrace) => Container(
              width: 200, height: 150, color: AppColors.darkSurfaceHighlight,
              child: const Icon(Icons.broken_image, color: Colors.white54),
            ),
          ),
        ),
      );
    }

    // Generic file preview (PDF, Audio, Video, Docs)
    return GestureDetector(
      onLongPress: () => _showContextMenu(context),
      onTap: () {
        if (attachment.downloadUrl != null) {
          launchUrl(Uri.parse(attachment.downloadUrl!));
        }
      },
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.darkSurfaceHighlight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_getIconForType(), color: AppColors.brandBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    attachment.fileName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(attachment.fileSize / 1024).toStringAsFixed(1)} KB',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildValidationState() {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkSurfaceHighlight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: AnimatedLoadingIndicator(color: Colors.orange, strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Scanning & Validating...',
              style: TextStyle(color: Colors.orange[200], fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
