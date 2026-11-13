// LIVE ROOM GATE — /live/viewer/:streamId
//
// Followers land here from the feed's live ring, profiles, notifications and
// deep links. Every live (solo, studio, game) runs in the one Live Studio.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../backend/live/models/live_models.dart';
import '../../backend/live/services/live_service.dart';
import '../../backend/live_studio/live_studio_flag.dart';
import '../../shared/theme/app_theme.dart';
import 'studio_v2/shell/live_studio_v2_screen.dart';

class LiveRoomGate extends ConsumerWidget {
  const LiveRoomGate({super.key, required this.streamId});
  final String streamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(liveStreamProvider(streamId));
    void leave() => context.canPop() ? context.pop() : context.go('/hub/home');
    const loading = Scaffold(
      backgroundColor: AppColors.brandBlack,
      body: Center(child: CircularProgressIndicator(color: AppColors.brandPink)),
    );
    return async.when(
      loading: () => loading,
      error: (_, _) => LiveEndedView(stream: null, headline: 'This LIVE is unavailable', onClose: leave),
      data: (stream) {
        if (stream == null) {
          return LiveEndedView(stream: null, headline: 'This LIVE is unavailable', onClose: leave);
        }
        final version = ref.watch(liveStudioVersionProvider(streamId));
        if (!version.hasValue) return loading;
        if (version.value! >= 2) return LiveStudioV2Screen(streamId: streamId);
        // Started on an older app version (no studio room to join).
        return LiveEndedView(stream: stream, headline: 'This LIVE needs the latest Oneova', onClose: leave);
      },
    );
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
