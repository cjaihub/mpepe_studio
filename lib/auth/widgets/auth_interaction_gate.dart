import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';

/// Interaction gate for guest browsing:
/// Allows guest users to explore the feed freely, but seamlessly intercepts
/// stateful interactions (like, follow, comment, create, chat) with a pro auth sheet.
class AuthInteractionGate {
  /// Checks authentication. If user is logged in, executes [onAuthenticated].
  /// Otherwise, presents the high-converting Oneova authentication prompt.
  static bool requireAuth(
    BuildContext context, {
    required String actionTitle,
    VoidCallback? onAuthenticated,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    final isAuthenticated = user != null && !user.isAnonymous;

    if (isAuthenticated) {
      onAuthenticated?.call();
      return true;
    }

    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OneovaAuthInteractionSheet(actionTitle: actionTitle),
    );
    return false;
  }
}

class OneovaAuthInteractionSheet extends StatelessWidget {
  final String actionTitle;

  const OneovaAuthInteractionSheet({
    super.key,
    required this.actionTitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final surfaceMid = isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight;
    final borderColor = isDark ? AppColors.outline : AppColors.lightBorder;
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border(
          top: BorderSide(color: borderColor, width: 1.0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.12),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Emblem & Accent Aura
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: surfaceMid,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.35), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandBlue.withValues(alpha: 0.25),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/images/oneova_logo.png',
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.lock_outline_rounded,
                    color: AppColors.brandBlue,
                    size: 26,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Title
          Text(
            'Join Oneova',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),

          // Action context
          Text(
            'Create an account to $actionTitle, unlock trending recommendations, and connect with top creators worldwide.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),

          // Feature Highlights Pill Strip
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildFeaturePill(Icons.verified_rounded, 'Verified Badges', surfaceMid, borderColor, textPrimary),
              _buildFeaturePill(Icons.shield_outlined, 'AI Anti-Scam Shield', surfaceMid, borderColor, textPrimary),
              _buildFeaturePill(Icons.fingerprint_rounded, 'Passkey Unlock', surfaceMid, borderColor, textPrimary),
            ],
          ),
          const SizedBox(height: 22),

          // CTA 1: Create Account
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/auth/signup_wizard');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
              child: Text(
                'Create Account in 60s',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // CTA 2: Log In
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/auth/main_login');
              },
              style: OutlinedButton.styleFrom(
                backgroundColor: surfaceMid,
                foregroundColor: textPrimary,
                side: BorderSide(color: borderColor, width: 1.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
              child: Text(
                'Log In to Existing Account',
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Dismiss: Continue Guest Browsing
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Continue Browsing as Guest',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturePill(
    IconData icon,
    String label,
    Color bg,
    Color border,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: border, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.brandPink),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
