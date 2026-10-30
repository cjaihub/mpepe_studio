import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/linked_destinations_picker.dart';

/// "Platforms" sheet on the Go LIVE screen: which linked accounts this live
/// is also streamed to. The choice is saved for the account
/// (user_settings/{uid}.publishing.liveSimulcastPlatforms), the same value the
/// Connected accounts page edits.
class GoLivePlatformsSheet {
  GoLivePlatformsSheet._();

  static Future<void> show(BuildContext context) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      barrierColor: AppColors.brandBlack.withValues(alpha: 0.35),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: ctx.border, borderRadius: BorderRadius.circular(AppRadius.full)),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.cell_tower_rounded, size: 18, color: AppColors.brandBlue),
                  const SizedBox(width: 8),
                  Text('Also go live on',
                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Optional. Your live stays on Oneova and is restreamed to the accounts you pick. '
                'Only YouTube and Facebook offer a live API.',
                style: GoogleFonts.inter(fontSize: 12, height: 1.35, color: ctx.textSecondary),
              ),
              const SizedBox(height: 14),
              const LinkedDestinationsPicker(purpose: DestinationPurpose.live),
            ],
          ),
        ),
      ),
    );
  }
}
