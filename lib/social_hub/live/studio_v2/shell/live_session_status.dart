// LIVE STUDIO v2 — session status UI: the "Connecting… / Reconnecting…"
// banner over the stage and the full-screen "Live ended" view.

import 'package:flutter/material.dart';

import '../theme/live_studio_tokens.dart';
import 'shell_widgets.dart';

/// Media link phase shown by [StudioConnectionBanner].
enum StudioLinkPhase { connected, connecting, reconnecting }

/// Small pill at the top of the stage while the room is not connected.
class StudioConnectionBanner extends StatelessWidget {
  const StudioConnectionBanner({super.key, required this.phase});
  final StudioLinkPhase phase;

  @override
  Widget build(BuildContext context) {
    final visible = phase != StudioLinkPhase.connected;
    final label = phase == StudioLinkPhase.reconnecting ? 'Reconnecting…' : 'Joining live…';
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedSlide(
            offset: visible ? Offset.zero : const Offset(0, -1.6),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                margin: const EdgeInsets.only(top: 64),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: LiveStudioWorld.inWindow,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: phase == StudioLinkPhase.reconnecting
                        ? LiveStudioAccent.pinkA(0.7)
                        : LiveStudioWorld.nameplateBorder,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: phase == StudioLinkPhase.reconnecting ? LiveStudioAccent.pink : LiveStudioAccent.blue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(label, style: LiveStudioType.s(13, FontWeight.w700, LiveStudioWorld.textHigh)),
                  if (phase == StudioLinkPhase.reconnecting) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.wifi_off_rounded, size: 15, color: LiveStudioWorld.textMedium),
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

/// Full-screen "Live ended" view for hosts and viewers.
class StudioLiveEndedView extends StatelessWidget {
  const StudioLiveEndedView({
    super.key,
    required this.isHost,
    required this.hostName,
    required this.hostAvatarUrl,
    required this.reason,
    required this.onClose,
    this.onViewHost,
    this.loves,
    this.viewers,
    this.duration,
    this.extra,
  });

  final bool isHost;
  final String hostName;
  final String hostAvatarUrl;

  /// Server `endedReason`: host · timeout · host_left · room_closed (or null).
  final String? reason;
  final VoidCallback onClose;
  final VoidCallback? onViewHost;
  final int? loves;
  final int? viewers;
  final Duration? duration;

  /// Extra content under the stats (e.g. the host's recording decision).
  final Widget? extra;

  String get _subtitle {
    if (isHost) {
      return switch (reason) {
        'timeout' || 'host_left' => 'Your connection dropped for too long, so the live was closed for everyone.',
        _ => 'Thanks for going live. Your viewers have left the studio.',
      };
    }
    return switch (reason) {
      'timeout' || 'host_left' => '$hostName lost connection and the live was closed.',
      _ => '$hostName has ended this live.',
    };
  }

  static String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    const t = LiveStudioTokens.dark;
    final stats = <(IconData, String, String)>[
      if (duration != null) (Icons.timer_outlined, _fmt(duration!), 'Duration'),
      if (viewers != null) (Icons.visibility_outlined, '$viewers', 'Viewers'),
      if (loves != null) (Icons.favorite_rounded, '$loves', 'Loves'),
    ];
    return ColoredBox(
      color: t.base,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                StudioAvatar(
                  name: hostName,
                  url: hostAvatarUrl,
                  size: 92,
                  fill: LiveStudioWorld.surface3,
                  ring: LiveStudioAccent.pink,
                  ringWidth: 3,
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: LiveStudioWorld.surface3,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('LIVE ENDED', style: LiveStudioType.s(11, FontWeight.w800, t.textMedium)),
                ),
                const SizedBox(height: 14),
                Text(isHost ? 'Your live has ended' : 'This live has ended',
                    textAlign: TextAlign.center, style: LiveStudioType.s(22, FontWeight.w800, t.textHigh)),
                const SizedBox(height: 8),
                Text(_subtitle, textAlign: TextAlign.center, style: LiveStudioType.s(14, FontWeight.w500, t.textMedium)),
                if (stats.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Row(children: [
                    for (final s in stats)
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: LiveStudioWorld.surface2,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(children: [
                            Icon(s.$1, size: 18, color: LiveStudioAccent.pink),
                            const SizedBox(height: 6),
                            Text(s.$2, style: LiveStudioType.s(17, FontWeight.w800, t.textHigh)),
                            const SizedBox(height: 2),
                            Text(s.$3, style: LiveStudioType.s(11, FontWeight.w500, t.textMedium)),
                          ]),
                        ),
                      ),
                  ]),
                ],
                ?extra,
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: StudioPillButton(
                    label: isHost ? 'Done' : 'Back to feed',
                    icon: isHost ? Icons.check_rounded : Icons.arrow_back,
                    onTap: onClose,
                    fill: LiveStudioAccent.blue,
                    textColor: LiveStudioAccent.white,
                    height: 50,
                  ),
                ),
                if (!isHost && onViewHost != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: StudioPillButton(
                      label: 'View $hostName',
                      icon: Icons.person_outline,
                      onTap: onViewHost!,
                      fill: LiveStudioWorld.surface2,
                      textColor: LiveStudioWorld.textHigh,
                      height: 50,
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
