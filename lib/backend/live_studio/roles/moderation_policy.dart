// LIVE STUDIO v2 — which moderation actions the UI offers (workstream #4).
//
// Mirror of authorizeModeration in functions/src/liveStudio/roles_logic.ts
// (ARCHITECTURE §6). The server re-checks everything; this only decides what
// a menu shows.

import '../contracts/studio_contracts.dart';
import 'studio_roles_api.dart';

/// Actions [actorRole] may take on [target] (in menu order).
List<StudioModerationOp> allowedModerationOps({
  required String actorUid,
  required StudioRole actorRole,
  required String targetUid,
  required StudioRole targetRole,
  required bool targetOnStage,
}) {
  if (!actorRole.isManager) return const [];
  if (actorUid == targetUid || targetRole == StudioRole.host) return const [];
  final onStage = targetOnStage || targetRole.canPublish;
  final isHost = actorRole == StudioRole.host;
  return [
    if (onStage) StudioModerationOp.mute,
    if (onStage) StudioModerationOp.removeFromStage,
    if (isHost && targetRole == StudioRole.guest) StudioModerationOp.promoteCoHost,
    if (isHost && targetRole == StudioRole.coHost) StudioModerationOp.demoteCoHost,
    if (isHost || targetRole != StudioRole.coHost) StudioModerationOp.block,
  ];
}

/// Whether [op] needs a confirmation dialog (destructive or grants power).
bool moderationNeedsConfirm(StudioModerationOp op) => op != StudioModerationOp.mute;

/// Menu label for [op].
String moderationLabel(StudioModerationOp op) => switch (op) {
      StudioModerationOp.mute => 'Mute mic',
      StudioModerationOp.removeFromStage => 'Remove from stage',
      StudioModerationOp.block => 'Block from this live',
      StudioModerationOp.promoteCoHost => 'Make co-host',
      StudioModerationOp.demoteCoHost => 'Remove co-host',
    };

/// Confirmation copy for [op] on [name].
StudioConfirmPrompt moderationPrompt(StudioModerationOp op, String name) {
  final who = name.isEmpty ? 'this person' : name;
  return switch (op) {
    StudioModerationOp.mute => StudioConfirmPrompt(
        title: 'Mute $who?', message: 'Their mic turns off for everyone. They can unmute.', confirmLabel: 'Mute', destructive: false),
    StudioModerationOp.removeFromStage => StudioConfirmPrompt(
        title: 'Remove $who from the stage?',
        message: 'Their camera and mic stop. They keep watching and can request again.',
        confirmLabel: 'Remove'),
    StudioModerationOp.block => StudioConfirmPrompt(
        title: 'Block $who?',
        message: 'They leave this live now and cannot come back to it.',
        confirmLabel: 'Block'),
    StudioModerationOp.promoteCoHost => StudioConfirmPrompt(
        title: 'Make $who a co-host?',
        message: 'Co-hosts can approve requests, arrange the stage, mute and remove guests.',
        confirmLabel: 'Make co-host',
        destructive: false),
    StudioModerationOp.demoteCoHost => StudioConfirmPrompt(
        title: 'Remove $who as co-host?',
        message: 'They stay on stage as a guest.',
        confirmLabel: 'Remove co-host'),
  };
}
