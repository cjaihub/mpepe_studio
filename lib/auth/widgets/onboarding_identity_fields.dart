import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import '../services/oneova_username_service.dart';

/// Name + @username inputs with the live availability line. The one
/// identity step shared by phone registration (login screen) and the social
/// signup wizard.
class OnboardingIdentityFields extends StatelessWidget {
  const OnboardingIdentityFields({
    super.key,
    required this.nameController,
    required this.usernameController,
    required this.checking,
    required this.result,
    this.onUsernameChanged,
  });

  final TextEditingController nameController;
  final TextEditingController usernameController;
  final bool checking;
  final UsernameCheckResult? result;

  /// Leave null when the caller listens to [usernameController] itself.
  final ValueChanged<String>? onUsernameChanged;

  InputDecoration _decoration(BuildContext context, {required String hint, required IconData icon, Widget? suffix}) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
      filled: true,
      fillColor: context.surfaceMid,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: border(context.border, 1.0),
      enabledBorder: border(context.border, 1.0),
      focusedBorder: border(AppColors.brandBlue, 1.2),
      prefixIcon: Icon(icon, color: context.textSecondary, size: 16),
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = result;
    final ok = r?.isValidAndAvailable ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: nameController,
          cursorColor: AppColors.brandBlue,
          textCapitalization: TextCapitalization.words,
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary),
          decoration: _decoration(context, hint: 'Display name (e.g. Maya Lin)', icon: Icons.person_outline_rounded),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: usernameController,
          onChanged: onUsernameChanged,
          cursorColor: AppColors.brandBlue,
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary),
          decoration: _decoration(
            context,
            hint: 'Unique handle (e.g. mayacreates)',
            icon: Icons.alternate_email_rounded,
            suffix: checking
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.brandBlue),
                    ),
                  )
                : ok
                    ? const Icon(Icons.check_circle_rounded, color: AppColors.brandBlue, size: 18)
                    : null,
          ),
        ),
        if (r != null && (r.message ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Row(
              children: [
                Icon(ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                    size: 13, color: ok ? AppColors.brandBlue : AppColors.brandPink),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    r.message!,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: ok ? AppColors.brandBlue : AppColors.brandPink,
                    ),
                  ),
                ),
                if (r.potentialBadge != OneovaBadgeType.none)
                  const Icon(Icons.verified_rounded, size: 13, color: AppColors.brandBlue),
              ],
            ),
          ),
      ],
    );
  }
}
