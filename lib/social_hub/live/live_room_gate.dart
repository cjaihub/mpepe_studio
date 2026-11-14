// LIVE ROOM GATE — /live/viewer/:streamId
//
// Followers land here from the feed's live ring, profiles, notifications and
// deep links. Every live (solo, studio, game) runs in the one Live Studio.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../backend/live/models/live_models.dart';
import '../../shared/theme/app_theme.dart';
import 'studio_v2/shell/live_studio_v2_screen.dart';

class LiveRoomGate extends StatelessWidget {
  const LiveRoomGate({super.key, required this.streamId});
  final String streamId;

  @override
  Widget build(BuildContext context) {
    return LiveStudioV2Screen(streamId: streamId);
  }
}

/// Shown when a live can't be opened (ended, removed, or too old).
class LiveEndedView extends StatelessWidget {
  const LiveEndedView({super.key, required this.stream, required this.onClose, this.headline = 'LIVE has ended'});

  final LiveStream? stream;
  final VoidCallback onClose;
  final String headline;

  @override
  Widget build(BuildContext context) {
    final s = stream;
    final avatar = s?.hostAvatarUrl ?? '';
    return Scaffold(
      backgroundColor: context.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [AppColors.brandBlue, AppColors.brandPink]),
                ),
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: context.surfaceMid,
                  backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                  child: avatar.isEmpty ? Icon(Icons.person_rounded, color: context.textMuted, size: 36) : null,
                ),
              ),
              const SizedBox(height: 16),
              Text(headline,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      color: context.textPrimary, fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
              if (s != null && s.hostDisplayName.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(s.hostDisplayName, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: AppColors.brandWhite,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                  onPressed: onClose,
                  child: Text('Back', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
