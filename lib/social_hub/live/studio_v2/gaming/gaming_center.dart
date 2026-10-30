// LIVE STUDIO v2 — Game Live center screen.
//
// On a gaming live (settings.layoutPreset == gaming) the center host screen
// shows the host's SCREEN share instead of the host camera. The camera moves
// to [GamingPipBubble].

import 'package:flutter/material.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import '../../../../backend/live_studio/contracts/studio_ports.dart';
import '../../../../backend/live_studio/media/studio_video_view.dart';
import '../theme/live_studio_tokens.dart';

/// The stage's video for [uid] on a gaming live.
///
/// - host + screen track → the screen share, letterboxed ([BoxFit.contain]);
/// - host, no screen track yet → [GamingWaitingPlaceholder] (with the
///   "Start game stream" button for the host himself);
/// - anyone else → their camera, as on a normal live.
///
/// [renderSize] is the on-screen size the stage passes to its video builder.
Widget gamingVideoFor({
  required StudioRoomPort room,
  required String uid,
  required String hostId,
  required Size renderSize,
  required bool viewerIsHost,
  VoidCallback? onStartGame,
  bool starting = false,
}) {
  if (uid == hostId) {
    final screen = room.tableScreen();
    if (screen != null) {
      return StudioVideoView(screen, key: const ValueKey('gaming-screen'), fit: BoxFit.contain);
    }
    return GamingWaitingPlaceholder(
      renderSize: renderSize,
      onStart: viewerIsHost ? onStartGame : null,
      starting: starting,
    );
  }
  final cam = room.cameraOf(uid);
  return cam == null ? const SizedBox.shrink() : StudioVideoView(cam);
}

/// Members as the gaming stage should draw them: the host's center screen
/// always shows video (the game), even when the host camera is off.
Map<String, StageMember> gamingStageMembers(Map<String, StageMember> members, String hostId) {
  final h = members[hostId];
  if (h == null || h.camOn) return members;
  return {
    ...members,
    hostId: StageMember.fromJson({...h.toJson(), 'uid': h.uid, 'camOn': true}),
  };
}

/// "Waiting for the game…" with a big "Start game stream" button for the host.
///
/// The stage lays its video out in world units and scales it by the studio
/// camera; this widget undoes that scale so text and the button keep their
/// logical size on any viewport.
class GamingWaitingPlaceholder extends StatelessWidget {
  const GamingWaitingPlaceholder({super.key, required this.renderSize, this.onStart, this.starting = false});

  /// On-screen size (from the stage's video builder).
  final Size renderSize;

  /// Null for viewers (no button).
  final VoidCallback? onStart;
  final bool starting;

  static const String waitingText = 'Waiting for the game…';
  static const String startLabel = 'Start game stream';

  @override
  Widget build(BuildContext context) {
    final w = renderSize.width > 0 ? renderSize.width : 320.0;
    final h = renderSize.height > 0 ? renderSize.height : 180.0;
    return ColoredBox(
      color: LiveStudioWorld.screen,
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: w,
          height: h,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.sports_esports, size: 44, color: LiveStudioAccent.pinkLight),
                  const SizedBox(height: 10),
                  Text(waitingText, style: LiveStudioType.s(16, FontWeight.w600, LiveStudioWorld.textHigh, height: 22)),
                  if (onStart != null) ...[
                    const SizedBox(height: 14),
                    _StartButton(onTap: starting ? null : onStart, starting: starting),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.onTap, required this.starting});
  final VoidCallback? onTap;
  final bool starting;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: GamingWaitingPlaceholder.startLabel,
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const ValueKey('gaming-start-stream'),
            borderRadius: BorderRadius.circular(9999),
            onTap: onTap,
            child: Ink(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [LiveStudioAccent.pink, LiveStudioAccent.pinkLight]),
                borderRadius: BorderRadius.circular(9999),
                boxShadow: [BoxShadow(color: LiveStudioAccent.pinkA(0.4), blurRadius: 18, offset: const Offset(0, 6))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (starting)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: LiveStudioAccent.white),
                  )
                else
                  const Icon(Icons.screen_share, size: 20, color: LiveStudioAccent.white),
                const SizedBox(width: 10),
                Text(GamingWaitingPlaceholder.startLabel,
                    style: LiveStudioType.s(15, FontWeight.w700, LiveStudioAccent.white, height: 20)),
              ]),
            ),
          ),
        ),
      );
}
