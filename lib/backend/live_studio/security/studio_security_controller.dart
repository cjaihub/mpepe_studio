// LIVE STUDIO v2 — host / co-host live-health controller (security workstream).
//
// Merges advisories from Firestore and the `security` data topic, tracks
// dismissals and runs advisory actions. Every action asks [StudioConfirm]
// first (studioConfirmFor in the UI) and does nothing on `false`.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../roles/studio_roles_api.dart';
import 'studio_security_api.dart';
import 'studio_security_models.dart';

@immutable
class StudioSecurityView {
  const StudioSecurityView({
    this.live = const [],
    this.dismissed = const {},
    this.inFlight = const {},
    this.done = const {},
    this.error,
  });

  /// Advisories received on the data topic (newest first).
  final List<StudioAdvisory> live;
  final Set<String> dismissed;

  /// `advisoryId|actionKey` in flight / already done.
  final Set<String> inFlight;
  final Set<String> done;
  final String? error;

  StudioSecurityView copyWith({
    List<StudioAdvisory>? live,
    Set<String>? dismissed,
    Set<String>? inFlight,
    Set<String>? done,
    String? error,
    bool clearError = false,
  }) =>
      StudioSecurityView(
        live: live ?? this.live,
        dismissed: dismissed ?? this.dismissed,
        inFlight: inFlight ?? this.inFlight,
        done: done ?? this.done,
        error: clearError ? null : (error ?? this.error),
      );
}

String studioActionKey(StudioAdvisory a, StudioAdvisoryAction x) => '${a.id}|${x.key}';

final studioSecurityControllerProvider =
    NotifierProvider.autoDispose.family<StudioSecurityController, StudioSecurityView, String>(
        StudioSecurityController.new);

/// The advisory the banner shows (newest, not dismissed), or null.
final studioCurrentAdvisoryProvider = Provider.autoDispose.family<StudioAdvisory?, String>((ref, streamId) {
  final stored = ref.watch(studioSecurityAdvisoriesProvider(streamId)).value ?? const <StudioAdvisory>[];
  final view = ref.watch(studioSecurityControllerProvider(streamId));
  return pickCurrentAdvisory(stored, view);
});

/// Newest non-dismissed advisory from [stored] (Firestore) + [view].live.
StudioAdvisory? pickCurrentAdvisory(List<StudioAdvisory> stored, StudioSecurityView view) {
  final byId = <String, StudioAdvisory>{for (final a in stored) a.id: a, for (final a in view.live) a.id: a};
  final list = byId.values.where((a) => !view.dismissed.contains(a.id)).toList()
    ..sort((a, b) => b.atMs.compareTo(a.atMs));
  return list.isEmpty ? null : list.first;
}

class StudioSecurityController extends Notifier<StudioSecurityView> {
  StudioSecurityController(this.streamId);
  final String streamId;

  @override
  StudioSecurityView build() {
    final sub = ref.watch(studioSecurityPacketsProvider(streamId)).listen((p) {
      if (p is AdvisoryPacket && ref.mounted) _addLive(p.advisory);
    });
    ref.onDispose(sub.cancel);
    return const StudioSecurityView();
  }

  void _addLive(StudioAdvisory a) {
    if (a.id.isEmpty || state.live.any((x) => x.id == a.id)) return;
    state = state.copyWith(live: [a, ...state.live].take(10).toList(growable: false));
  }

  void dismiss(String advisoryId) => state = state.copyWith(dismissed: {...state.dismissed, advisoryId});

  bool isDone(StudioAdvisory a, StudioAdvisoryAction x) => state.done.contains(studioActionKey(a, x));
  bool isBusy(StudioAdvisory a, StudioAdvisoryAction x) => state.inFlight.contains(studioActionKey(a, x));

  /// Confirms, then runs [x]. Returns true when the server accepted it.
  Future<bool> apply(StudioAdvisory a, StudioAdvisoryAction x, {required StudioConfirm confirm}) async {
    final key = studioActionKey(a, x);
    if (state.inFlight.contains(key) || state.done.contains(key)) return false;
    if (!await confirm(advisoryPrompt(x))) return false;
    if (!ref.mounted) return false;
    state = state.copyWith(inFlight: {...state.inFlight, key}, clearError: true);
    try {
      await ref.read(studioSecurityApiProvider).run(streamId, x);
      if (ref.mounted) {
        state = state.copyWith(inFlight: {...state.inFlight}..remove(key), done: {...state.done, key});
      }
      return true;
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(inFlight: {...state.inFlight}..remove(key), error: studioErrorMessage(e));
      }
      return false;
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}
