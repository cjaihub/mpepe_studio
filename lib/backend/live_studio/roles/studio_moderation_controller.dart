// LIVE STUDIO v2 — host / co-host moderation (workstream #4).
//
// mute · remove from stage · block · promote / demote co-host · end the live.
// Every destructive action goes through a [StudioConfirm] the UI provides
// (repo rule: confirm before destructive actions); nothing runs on `false`.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../media/studio_media_api.dart';
import 'moderation_policy.dart';
import 'studio_roles_api.dart';

@immutable
class StudioModerationView {
  const StudioModerationView({this.inFlight = const {}, this.ending = false, this.error});

  /// Target uids with a moderation call in flight.
  final Set<String> inFlight;
  final bool ending;
  final String? error;

  StudioModerationView copyWith({Set<String>? inFlight, bool? ending, String? error, bool clearError = false}) =>
      StudioModerationView(
        inFlight: inFlight ?? this.inFlight,
        ending: ending ?? this.ending,
        error: clearError ? null : (error ?? this.error),
      );
}

final studioModerationControllerProvider =
    NotifierProvider.autoDispose.family<StudioModerationController, StudioModerationView, String>(
        StudioModerationController.new);

class StudioModerationController extends Notifier<StudioModerationView> {
  StudioModerationController(this.streamId);
  final String streamId;

  @override
  StudioModerationView build() => const StudioModerationView();

  Future<bool> mute(String uid, {required String name, required StudioConfirm confirm}) =>
      run(StudioModerationOp.mute, uid, name: name, confirm: confirm);
  Future<bool> removeFromStage(String uid, {required String name, required StudioConfirm confirm}) =>
      run(StudioModerationOp.removeFromStage, uid, name: name, confirm: confirm);
  Future<bool> block(String uid, {required String name, required StudioConfirm confirm}) =>
      run(StudioModerationOp.block, uid, name: name, confirm: confirm);
  Future<bool> promote(String uid, {required String name, required StudioConfirm confirm}) =>
      run(StudioModerationOp.promoteCoHost, uid, name: name, confirm: confirm);
  Future<bool> demote(String uid, {required String name, required StudioConfirm confirm}) =>
      run(StudioModerationOp.demoteCoHost, uid, name: name, confirm: confirm);

  /// Runs [op] on [uid]; asks [confirm] first when [moderationNeedsConfirm].
  /// Returns true when the server accepted it.
  Future<bool> run(StudioModerationOp op, String uid, {required String name, required StudioConfirm confirm}) async {
    if (state.inFlight.contains(uid)) return false;
    if (moderationNeedsConfirm(op) && !await confirm(moderationPrompt(op, name))) return false;
    if (!ref.mounted) return false;
    state = state.copyWith(inFlight: {...state.inFlight, uid}, clearError: true);
    try {
      await ref.read(studioRolesApiProvider).moderate(streamId, uid, op);
      if (ref.mounted) state = state.copyWith(inFlight: {...state.inFlight}..remove(uid));
      return true;
    } catch (e) {
      if (ref.mounted) state = state.copyWith(inFlight: {...state.inFlight}..remove(uid), error: studioErrorMessage(e));
      return false;
    }
  }

  /// Host ends the live (lsEnd) after confirmation.
  Future<bool> endLive({required StudioConfirm confirm}) async {
    if (state.ending) return false;
    final ok = await confirm(const StudioConfirmPrompt(
      title: 'End the live?',
      message: 'Everyone leaves the studio and the live stops for all viewers.',
      confirmLabel: 'End live',
    ));
    if (!ok || !ref.mounted) return false;
    state = state.copyWith(ending: true, clearError: true);
    try {
      await ref.read(studioMediaApiProvider).end(streamId);
      if (ref.mounted) state = state.copyWith(ending: false);
      return true;
    } catch (e) {
      if (ref.mounted) state = state.copyWith(ending: false, error: studioErrorMessage(e));
      return false;
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}
