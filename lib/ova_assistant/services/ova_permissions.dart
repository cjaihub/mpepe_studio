import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../shared/theme/app_theme.dart';

/// Asks for a runtime permission with a short, plain explanation first.
/// Returns true when the permission is granted (or limited).
class OvaPermissions {
  static Future<bool> ensure(
    BuildContext? context,
    Permission permission, {
    required String title,
    required String why,
  }) async {
    var status = await permission.status;
    if (status.isGranted || status.isLimited) return true;

    if (status.isPermanentlyDenied || status.isRestricted) {
      if (context == null || !context.mounted) return false;
      final open = await _explain(context, title: title, why: '$why\n\nIt is turned off for Oneova. You can turn it on in Settings.', cta: 'Open Settings');
      if (open == true) await openAppSettings();
      return false;
    }

    if (context != null && context.mounted) {
      final go = await _explain(context, title: title, why: why, cta: 'Continue');
      if (go != true) return false;
    }
    status = await permission.request();
    return status.isGranted || status.isLimited;
  }

  static Future<bool?> _explain(
    BuildContext context, {
    required String title,
    required String why,
    required String cta,
  }) {
    HapticFeedback.lightImpact();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: BorderSide(color: ctx.border, width: 1),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
        contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        title: Row(
          children: [
            const Icon(Icons.lock_open_rounded, size: 18, color: AppColors.brandBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
            ),
          ],
        ),
        content: Text(why,
            style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: ctx.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Not now', style: GoogleFonts.inter(fontSize: 13, color: ctx.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              minimumSize: const Size(0, 38),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(cta, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
