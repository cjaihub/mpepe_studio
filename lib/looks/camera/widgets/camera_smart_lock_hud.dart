import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/camera_smart_lock_state.dart';

/// Floating Smart Lock HUD pill visible while shooting, indicating AE/AF/AWB locked state.
class CameraSmartLockHud extends StatelessWidget {
  final CameraSmartLockState smartLock;
  final VoidCallback? onUnlockTap;

  const CameraSmartLockHud({
    super.key,
    required this.smartLock,
    this.onUnlockTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!smartLock.isSmartLockActive && !smartLock.isAnyLockActive) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.8), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPink.withValues(alpha: 0.25),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: AppColors.brandPink,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'SMART LOCK',
            style: GoogleFonts.inter(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 6),
          _buildLockTag('AE', smartLock.aeLocked),
          const SizedBox(width: 4),
          _buildLockTag('AF', smartLock.afLocked),
          const SizedBox(width: 4),
          _buildLockTag('AWB', smartLock.awbLocked),
          if (onUnlockTap != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onUnlockTap,
              child: const Icon(
                Icons.close_rounded,
                size: 13,
                color: Colors.white70,
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 200.ms);
  }

  Widget _buildLockTag(String label, bool isLocked) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: isLocked ? AppColors.brandPink.withValues(alpha: 0.25) : Colors.white12,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              color: isLocked ? Colors.white : Colors.white54,
            ),
          ),
          if (isLocked) ...[
            const SizedBox(width: 2),
            const Icon(Icons.lock_rounded, size: 8, color: Colors.white),
          ],
        ],
      ),
    );
  }
}
