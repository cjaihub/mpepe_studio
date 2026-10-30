import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/post_draft_provider.dart';

class DraftStatusPill extends StatelessWidget {
  final PostDraftState draftState;
  final VoidCallback? onTap;

  const DraftStatusPill({
    super.key,
    required this.draftState,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (draftState.status == PostDraftStatus.idle && draftState.draft == null) {
      return const SizedBox.shrink();
    }

    Color pillColor;
    Color textColor;
    IconData icon;
    String label;

    switch (draftState.status) {
      case PostDraftStatus.saving:
        pillColor = AppColors.brandBlue.withValues(alpha: 0.12);
        textColor = AppColors.brandBlue;
        icon = Icons.sync;
        label = 'Saving…';
        break;
      case PostDraftStatus.saved:
        pillColor = context.surfaceMid;
        textColor = context.textSecondary;
        icon = Icons.cloud_done_outlined;
        label = 'Draft saved';
        break;
      case PostDraftStatus.error:
        pillColor = AppColors.brandPink.withValues(alpha: 0.12);
        textColor = AppColors.brandPink;
        icon = Icons.warning_amber_rounded;
        label = 'Offline draft';
        break;
      case PostDraftStatus.idle:
        pillColor = context.surfaceMid;
        textColor = context.textMuted;
        icon = Icons.save_as_outlined;
        label = 'Draft';
        break;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: pillColor,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: context.border, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (draftState.status == PostDraftStatus.saving)
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(textColor),
                ),
              )
            else
              Icon(icon, size: 12, color: textColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
