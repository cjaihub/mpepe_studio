// LIVE STUDIO v2 — ParticipantRowActions (workstream #4): the host /
// co-host menu on a member row (Participants panel, pop-out header).
//
// Offers only what ARCHITECTURE §6 allows (moderation_policy.dart); the
// server re-checks. Destructive items open a Cancel / Confirm dialog first.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import '../../../../backend/live_studio/roles/moderation_policy.dart';
import '../../../../backend/live_studio/roles/studio_moderation_controller.dart';
import '../../../../backend/live_studio/roles/studio_roles_api.dart';
import '../theme/live_studio_tokens.dart';
import 'studio_confirm_dialog.dart';

class ParticipantRowActions extends ConsumerWidget {
  const ParticipantRowActions({
    super.key,
    required this.streamId,
    required this.member,
    required this.myUid,
    required this.myRole,
    required this.onStage,
    required this.tokens,
  });

  final String streamId;
  final StageMember member;
  final String myUid;
  final StudioRole myRole;

  /// Whether [member] is on the stage layout (center, wall or overflow).
  final bool onStage;
  final LiveStudioTokens tokens;

  static String semanticsLabel(String name) => 'Actions for ${name.isEmpty ? 'participant' : name}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ops = allowedModerationOps(
      actorUid: myUid,
      actorRole: myRole,
      targetUid: member.uid,
      targetRole: member.role,
      targetOnStage: onStage,
    );
    if (ops.isEmpty) return const SizedBox.shrink();
    final provider = studioModerationControllerProvider(streamId);
    ref.listen<StudioModerationView>(provider, (prev, next) {
      final err = next.error;
      if (err != null && err != prev?.error) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(err)));
        ref.read(provider.notifier).clearError();
      }
    });
    final busy = ref.watch(provider.select((v) => v.inFlight.contains(member.uid)));
    final t = tokens;

    if (busy) {
      return SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: t.textMedium)),
        ),
      );
    }

    return Semantics(
      button: true,
      label: semanticsLabel(member.displayName),
      excludeSemantics: true,
      child: PopupMenuButton<StudioModerationOp>(
        tooltip: semanticsLabel(member.displayName),
        icon: Icon(Icons.more_horiz, size: 20, color: t.textMedium),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 200),
        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
        color: t.drawerBottom,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: t.drawerBorder, width: 1),
        ),
        onOpened: HapticFeedback.lightImpact,
        onSelected: (op) {
          unawaited(ref.read(provider.notifier).run(
                op,
                member.uid,
                name: member.displayName,
                confirm: studioConfirmFor(context, t),
              ));
        },
        itemBuilder: (_) => [
          for (final op in ops)
            PopupMenuItem<StudioModerationOp>(
              value: op,
              height: 44,
              child: Row(children: [
                Icon(_icon(op), size: 18, color: _destructive(op) ? LiveStudioAccent.pink : t.textHigh),
                const SizedBox(width: 10),
                Text(moderationLabel(op),
                    style: LiveStudioType.s(13, FontWeight.w600, _destructive(op) ? LiveStudioAccent.pink : t.textHigh)),
              ]),
            ),
        ],
      ),
    );
  }

  static bool _destructive(StudioModerationOp op) =>
      op == StudioModerationOp.block || op == StudioModerationOp.removeFromStage;

  static IconData _icon(StudioModerationOp op) => switch (op) {
        StudioModerationOp.mute => Icons.mic_off,
        StudioModerationOp.removeFromStage => Icons.person_remove_alt_1_outlined,
        StudioModerationOp.block => Icons.block,
        StudioModerationOp.promoteCoHost => Icons.star_outline,
        StudioModerationOp.demoteCoHost => Icons.star_border_purple500_outlined,
      };
}
