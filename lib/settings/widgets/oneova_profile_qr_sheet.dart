import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr/qr.dart';
import 'package:share_plus/share_plus.dart';
import '../../backend/routing/oneova_share_engine.dart';
import '../../backend/user_service.dart';
import '../../shared/theme/app_theme.dart';

/// Modal bottom sheet displaying a high-contrast executive Oneova QR Code
/// for direct in-person profile sharing.
class OneovaProfileQrSheet extends StatelessWidget {
  final AppUser user;

  const OneovaProfileQrSheet({super.key, required this.user});

  static Future<void> show(BuildContext context, AppUser user) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => OneovaProfileQrSheet(user: user),
    );
  }

  String get _profileUrl {
    final handle = user.username?.isNotEmpty == true ? user.username! : user.id;
    return 'https://${OneovaShareEngine.webDomain}/profile/$handle';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border(top: BorderSide(color: context.border, width: 1.0)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.textMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(Icons.qr_code_2_rounded, color: AppColors.brandBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Profile QR Code',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Scan with any phone camera to visit profile',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: context.textSecondary, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // QR Card Container
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: context.border, width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                // User info header
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.brandBlue.withValues(alpha: 0.15),
                      backgroundImage: user.profilePhotoUrl != null && user.profilePhotoUrl!.isNotEmpty
                          ? NetworkImage(user.profilePhotoUrl!)
                          : null,
                      child: user.profilePhotoUrl == null || user.profilePhotoUrl!.isEmpty
                          ? Text(
                              (user.fullName.isNotEmpty ? user.fullName[0] : 'O').toUpperCase(),
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.brandBlue,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              user.fullName.isNotEmpty ? user.fullName : 'Oneova Creator',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: context.textPrimary,
                              ),
                            ),
                            if (user.isVerified) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.verified_rounded, size: 14, color: AppColors.brandBlue),
                            ],
                          ],
                        ),
                        Text(
                          '@${user.username ?? user.id}',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brandPink,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // QR Code Painter
                SizedBox(
                  width: 200,
                  height: 200,
                  child: CustomPaint(
                    painter: _OneovaQrPainter(
                      data: _profileUrl,
                      fgColor: context.textPrimary,
                      accentColor: AppColors.brandBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  'oneova.app/@${user.username ?? user.id}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: context.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Clipboard.setData(ClipboardData(text: _profileUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Profile link copied to clipboard!'),
                        backgroundColor: AppColors.brandBlue,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy Link'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.textPrimary,
                    side: BorderSide(color: context.border, width: 1.0),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    SharePlus.instance.share(
                      ShareParams(
                        text: 'Connect with ${user.fullName} on Oneova: $_profileUrl',
                      ),
                    );
                  },
                  icon: const Icon(Icons.share_rounded, size: 16, color: Colors.white),
                  label: const Text('Share Profile', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OneovaQrPainter extends CustomPainter {
  final String data;
  final Color fgColor;
  final Color accentColor;

  _OneovaQrPainter({
    required this.data,
    required this.fgColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final qr = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final qrImage = QrImage(qr);
    final count = qrImage.moduleCount;
    final moduleSize = size.width / count;

    final paintFg = Paint()
      ..color = fgColor
      ..style = PaintingStyle.fill;

    final paintAccent = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    for (int x = 0; x < count; x++) {
      for (int y = 0; y < count; y++) {
        if (qrImage.isDark(y, x)) {
          // Highlight position detection patterns (corners)
          final isCorner = (x < 7 && y < 7) || (x < 7 && y >= count - 7) || (x >= count - 7 && y < 7);
          final rect = Rect.fromLTWH(
            x * moduleSize,
            y * moduleSize,
            moduleSize * 0.92,
            moduleSize * 0.92,
          );
          final rrect = RRect.fromRectAndRadius(rect, Radius.circular(moduleSize * 0.25));
          canvas.drawRRect(rrect, isCorner ? paintAccent : paintFg);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OneovaQrPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.fgColor != fgColor || oldDelegate.accentColor != accentColor;
  }
}
