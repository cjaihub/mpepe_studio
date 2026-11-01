import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import '../theme/live_studio_tokens.dart';
import 'shell_widgets.dart';

/// Columns for [n] tiles (1–[StudioLimits.maxOnStage]) on a phone (portrait)
/// or a landscape screen. Rows follow: `ceil(n / cols)`.
int stagePanelColumns(int n, {required bool phone}) {
  if (n <= 1) return 1;
  if (phone) return n <= 4 ? 2 : (n <= 6 ? 2 : 3);
  if (n <= 2) return 2;
  if (n <= 4) return 2;
  if (n <= 6) return 3;
  if (n <= 8) return 4;
  return 5;
}

/// People the studio world shows on its own (center + wall slots). Past this
/// the live switches to [StagePanelGrid] so nobody on stage is hidden.
int studioWorldCapacity({required bool phone}) =>
    1 + (phone ? StudioLimits.phoneWallSlots : StudioLimits.wallSlots);

/// A clean, even grid of everyone on stage (1–10): video or avatar, name,
/// mic state and a speaking ring. The center person comes first.
class StagePanelGrid extends StatelessWidget {
  const StagePanelGrid({
    super.key,
    required this.uids,
    required this.members,
    required this.tokens,
    required this.phone,
    required this.videoBuilder,
    required this.isSpeaking,
    required this.isMuted,
    this.hostId = '',
    this.onTileTap,
  });

  final List<String> uids;
  final Map<String, StageMember> members;
  final LiveStudioTokens tokens;
  final bool phone;
  final Widget Function(String uid, Size size) videoBuilder;
  final bool Function(String uid) isSpeaking;
  final bool Function(String uid) isMuted;
  final String hostId;

  /// Managers: tap a tile to bring that person to the center.
  final ValueChanged<String>? onTileTap;

  @override
  Widget build(BuildContext context) {
    final people = uids.take(StudioLimits.maxOnStage).toList();
    if (people.isEmpty) return const SizedBox.shrink();
    final cols = stagePanelColumns(people.length, phone: phone);
    final rows = (people.length / cols).ceil();
    const gap = 6.0;
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      final h = (box.maxHeight - gap * (rows - 1)) / rows;
      final size = Size(math.max(0, w), math.max(0, h));
      return Column(children: [
        for (var r = 0; r < rows; r++) ...[
          if (r > 0) const SizedBox(height: gap),
          Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var c = 0; c < cols && r * cols + c < people.length; c++) ...[
                if (c > 0) const SizedBox(width: gap),
                SizedBox(
                  width: size.width,
                  child: _PanelTile(
                    key: ValueKey('panel-${people[r * cols + c]}'),
                    uid: people[r * cols + c],
                    member: members[people[r * cols + c]],
                    isHost: people[r * cols + c] == hostId,
                    tokens: tokens,
                    size: size,
                    compact: people.length > 4,
                    video: videoBuilder,
                    speaking: isSpeaking(people[r * cols + c]),
                    muted: isMuted(people[r * cols + c]),
                    onTap: onTileTap == null ? null : () => onTileTap!(people[r * cols + c]),
                  ),
                ),
              ],
            ]),
          ),
        ],
      ]);
    });
  }
}

class _PanelTile extends StatelessWidget {
  const _PanelTile({
    super.key,
    required this.uid,
    required this.member,
    required this.isHost,
    required this.tokens,
    required this.size,
    required this.compact,
    required this.video,
    required this.speaking,
    required this.muted,
    this.onTap,
  });

  final String uid;
  final StageMember? member;
  final bool isHost;
  final LiveStudioTokens tokens;
  final Size size;
  final bool compact;
  final Widget Function(String uid, Size size) video;
  final bool speaking;
  final bool muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final name = m?.displayName.isNotEmpty == true ? m!.displayName : 'Guest';
    final accent = studioHex(m?.accent ?? '', fallback: LiveStudioAccent.blue);
    final avatar = Center(
      child: StudioAvatar(
        name: name,
        url: m?.avatarUrl ?? '',
        size: math.min(compact ? 48.0 : 72.0, size.shortestSide * 0.5),
        fill: LiveStudioWorld.surface3,
        ring: accent,
      ),
    );
    return Semantics(
      label: '$name${isHost ? ', host' : ''}${muted ? ', muted' : ''}${speaking ? ', speaking' : ''}',
      button: onTap != null,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: LiveStudioWorld.surface2,
            borderRadius: BorderRadius.circular(compact ? 12 : 16),
            border: Border.all(
              color: speaking ? LiveStudioAccent.pink : LiveStudioWorld.nameplateBorder,
              width: speaking ? 2 : 1,
            ),
            boxShadow: speaking ? [BoxShadow(color: LiveStudioAccent.pinkA(0.35), blurRadius: 14)] : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(fit: StackFit.expand, children: [
            avatar,
            if (m == null || m.camOn) video(uid, size),
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Row(children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: LiveStudioWorld.nameplate,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (isHost) ...[
                        const Icon(Icons.star_rounded, size: 11, color: LiveStudioAccent.pink),
                        const SizedBox(width: 3),
                      ],
                      Flexible(
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LiveStudioType.s(compact ? 10.5 : 12, FontWeight.w600, LiveStudioWorld.textHigh)),
                      ),
                    ]),
                  ),
                ),
                if (muted) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(color: LiveStudioWorld.nameplate, shape: BoxShape.circle),
                    child: const Icon(Icons.mic_off_rounded, size: 12, color: LiveStudioAccent.muteIcon),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
