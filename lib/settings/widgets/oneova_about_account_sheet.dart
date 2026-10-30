import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/user_service.dart';
import '../../shared/theme/app_theme.dart';

class OneovaAboutAccountSheet extends StatelessWidget {
  final AppUser user;

  const OneovaAboutAccountSheet({super.key, required this.user});

  static Future<void> show(BuildContext context, AppUser user) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => OneovaAboutAccountSheet(user: user),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[dt.month - 1]} ${dt.year}';
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
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(Icons.info_outline_rounded, color: AppColors.brandBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'About This Account',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Platform transparency & creator history',
                      style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary),
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
          const SizedBox(height: 20),

          // User summary
          CircleAvatar(
            radius: 32,
            backgroundColor: AppColors.brandBlue.withValues(alpha: 0.15),
            backgroundImage: user.profilePhotoUrl != null && user.profilePhotoUrl!.isNotEmpty
                ? NetworkImage(user.profilePhotoUrl!)
                : null,
            child: user.profilePhotoUrl == null || user.profilePhotoUrl!.isEmpty
                ? Text(
                    (user.fullName.isNotEmpty ? user.fullName[0] : 'O').toUpperCase(),
                    style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.brandBlue),
                  )
                : null,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                user.fullName.isNotEmpty ? user.fullName : 'Oneova User',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: context.textPrimary),
              ),
              if (user.isVerified) ...[
                const SizedBox(width: 4),
                const Icon(Icons.verified_rounded, size: 16, color: AppColors.brandBlue),
              ],
            ],
          ),
          Text(
            '@${user.username ?? user.id}',
            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.brandPink),
          ),
          const SizedBox(height: 24),

          // Transparency data points
          _buildDataRow(
            context,
            icon: Icons.calendar_today_rounded,
            title: 'Date Joined',
            value: _formatDate(user.createdAt),
          ),
          const Divider(height: 20),
          _buildDataRow(
            context,
            icon: Icons.location_on_rounded,
            title: 'Account Location',
            value: user.location?.isNotEmpty == true ? user.location! : 'Global / Not Specified',
          ),
          const Divider(height: 20),
          _buildDataRow(
            context,
            icon: Icons.badge_rounded,
            title: 'Account Type',
            value: user.accountType.toUpperCase(),
          ),
          const Divider(height: 20),
          _buildDataRow(
            context,
            icon: Icons.history_rounded,
            title: 'Former Usernames',
            value: '0 changes',
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: context.border, width: 1.0),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              child: Text(
                'Close',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: context.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: context.textPrimary),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textSecondary),
        ),
      ],
    );
  }
}
