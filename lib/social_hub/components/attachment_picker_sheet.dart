import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';

class AttachmentPickerSheet extends StatelessWidget {
  final VoidCallback onPickImage;
  final VoidCallback onPickVideo;
  final VoidCallback onPickDocument;
  final VoidCallback onPickLocation;

  const AttachmentPickerSheet({
    super.key,
    required this.onPickImage,
    required this.onPickVideo,
    required this.onPickDocument,
    required this.onPickLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: context.border,
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.all(24.0),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: context.textMuted,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Share Attachment',
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildOption(
                  context: context,
                  icon: Icons.image,
                  label: 'Photo',
                  onTap: () {
                    Navigator.pop(context);
                    onPickImage();
                  },
                ),
                _buildOption(
                  context: context,
                  icon: Icons.videocam,
                  label: 'Video',
                  onTap: () {
                    Navigator.pop(context);
                    onPickVideo();
                  },
                ),
                _buildOption(
                  context: context,
                  icon: Icons.description,
                  label: 'Document',
                  onTap: () {
                    Navigator.pop(context);
                    onPickDocument();
                  },
                ),
                _buildOption(
                  context: context,
                  icon: Icons.location_on,
                  label: 'Location',
                  onTap: () {
                    Navigator.pop(context);
                    onPickLocation();
                  },
                ),
              ],
            ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutQuad),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.brandBlue,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandBlue.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 26,
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(duration: 2000.ms, color: Colors.white24),
          const SizedBox(height: 12),
          Text(
            label,
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
