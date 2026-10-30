// LIVE STUDIO v2 — Game Live chrome: "Now playing" pill, "Switch to game"
// button and the start-stream flow.

import 'package:flutter/material.dart';

import '../../../../backend/live_studio/contracts/studio_ports.dart';
import '../../../../backend/live_studio/media/game_stream.dart';
import '../shell/shell_widgets.dart';
import '../theme/live_studio_tokens.dart';

/// Shown after "Switch to game". We never launch other apps.
const String kSwitchToGameTip = 'Your live keeps going. Open your game; come back to read chat.';

/// Starts the game stream on [room] when it isn't running yet.
///
/// Returns true when the screen share is (now) running. Errors (consent
/// refused, capture failure) show a snackbar and return false. With
/// [showTip], a successful start (or an already running stream) shows
/// [kSwitchToGameTip].
Future<bool> startGameStreamFlow(BuildContext context, StudioRoomPort room, {bool showTip = false}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    if (room.tableScreen() == null) await startGameStreamOn(room);
  } catch (e) {
    messenger?.showSnackBar(const SnackBar(content: Text('Could not start the game stream. Allow screen sharing and try again.')));
    return false;
  }
  if (showTip) {
    messenger?.showSnackBar(const SnackBar(
      key: ValueKey('gaming-tip'),
      content: Text(kSwitchToGameTip),
      duration: Duration(seconds: 5),
    ));
  }
  return true;
}

/// "Now playing: GAME" pill (near the host card).
class NowPlayingPill extends StatelessWidget {
  const NowPlayingPill({super.key, required this.tokens, required this.gameTitle, this.phone = false});
  final LiveStudioTokens tokens;
  final String gameTitle;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Semantics(
      label: 'Now playing: $gameTitle',
      excludeSemantics: true,
      child: GlassBox(
        tokens: t,
        phone: phone,
        height: phone ? 28 : 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.sports_esports, size: 15, color: LiveStudioAccent.pink),
          const SizedBox(width: 6),
          Flexible(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Now playing: ', style: LiveStudioType.s(12, FontWeight.w500, t.textMedium, height: 16)),
                TextSpan(text: gameTitle, style: LiveStudioType.s(12, FontWeight.w700, t.textHigh, height: 16)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ),
    );
  }
}

/// Host-only "Switch to game" button (replaces Share-to-table on gaming lives).
class SwitchToGameButton extends StatelessWidget {
  const SwitchToGameButton({super.key, required this.tokens, required this.onTap, this.compact = false});
  final LiveStudioTokens tokens;
  final VoidCallback? onTap;

  /// Phone bottom bar: a 40 px round button.
  final bool compact;

  static const String label = 'Switch to game';

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    if (compact) {
      return StudioRoundButton(
        key: const ValueKey('gaming-switch'),
        tokens: t,
        icon: Icons.sports_esports,
        label: label,
        size: 40,
        iconSize: 20,
        fill: LiveStudioAccent.pinkA(0.15),
        border: LiveStudioAccent.pink,
        color: LiveStudioAccent.pink,
        onTap: onTap,
      );
    }
    return StudioPillButton(
      key: const ValueKey('gaming-switch'),
      label: label,
      icon: Icons.sports_esports,
      onTap: onTap,
      fill: LiveStudioAccent.pinkA(0.15),
      border: LiveStudioAccent.pink,
      textColor: t.textHigh,
      iconColor: LiveStudioAccent.pink,
    );
  }
}
