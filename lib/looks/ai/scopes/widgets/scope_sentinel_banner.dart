import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../models/scope_sentinel_alert.dart';

/// Floating Scope Sentinel alert banner on the editor or live preview viewfinder
/// allowing the creator to inspect and one-tap-fix color/exposure clipping.
class ScopeSentinelBanner extends StatelessWidget {
  final ScopeSentinelAlert alert;
  final VoidCallback onApplyFix;
  final VoidCallback onDismiss;

  const ScopeSentinelBanner({
    super.key,
    required this.alert,
    required this.onApplyFix,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isCritical = alert.severity == SentinelSeverity.critical;
    final accentColor = isCritical ? AppColors.brandPink : const Color(0xFFFFB300);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xEB121218),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: accentColor.withValues(alpha: 0.8), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.25),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCritical ? Icons.warning_rounded : Icons.auto_awesome,
              size: 15,
              color: accentColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'SENTINEL',
                      style: GoogleFonts.inter(
                        fontSize: 9.0,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '•',
                      style: TextStyle(fontSize: 8, color: context.textMuted),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        alert.headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12.0,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  alert.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11.0,
                    fontWeight: FontWeight.w400,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 1-Tap Fix Action Button
          InkWell(
            onTap: onApplyFix,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.brandBlue, AppColors.brandPink],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.flash_on_rounded, size: 12, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    alert.suggestedFixLabel,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Dismiss Button
          GestureDetector(
            onTap: onDismiss,
            child: const Padding(
              padding: EdgeInsets.all(4.0),
              child: Icon(Icons.close_rounded, size: 14, color: Colors.white60),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.1, end: 0);
  }
}
