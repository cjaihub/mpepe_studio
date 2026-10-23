// LIVE STUDIO v2 — host / co-host join request queue (workstream #4).
//
// [studioPendingRequestsProvider] streams the pending `studio_requests`
// (readable by managers only). [StudioRequestQueueController] approves or
// declines; it tracks in-flight uids so rows can show progress.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/studio_contracts.dart';
import 'studio_roles_api.dart';

/// Pending requests for [streamId], oldest first.
final studioPendingRequestsProvider = StreamProvider.autoDispose.family<List<JoinRequest>, String>(
    (ref, streamId) => ref.watch(studioRequestsSourceProvider).watchPending(streamId));

/// Number of pending requests (badge on the queue button).
final studioPendingRequestCountProvider = Provider.autoDispose.family<int, String>(
    (ref, streamId) => ref.watch(studioPendingRequestsProvider(streamId)).value?.length ?? 0);

@immutable
class StudioRequestQueueView {
  const StudioRequestQueueView({this.inFlight = const {}, this.answered = const {}, this.error});

  /// Uids with a respond call in flight.
  final Set<String> inFlight;

  /// Uids answered locally (hidden until the Firestore stream catches up).
  final Set<String> answered;
  final String? error;

  StudioRequestQueueView copyWith({Set<String>? inFlight, Set<String>? answered, String? error, bool clearError = false}) =>
      StudioRequestQueueView(
        inFlight: inFlight ?? this.inFlight,
        answered: answered ?? this.answered,
        error: clearError ? null : (error ?? this.error),
      );
}

final studioRequestQueueControllerProvider =
    NotifierProvider.autoDispose.family<StudioRequestQueueController, StudioRequestQueueView, String>(
        StudioRequestQueueController.new);

class StudioRequestQueueController extends Notifier<StudioRequestQueueView> {
  StudioRequestQueueController(this.streamId);
  final String streamId;

  @override
  StudioRequestQueueView build() => const StudioRequestQueueView();

  /// Pending requests minus the ones answered locally.
  List<JoinRequest> visible(List<JoinRequest> pending) =>
      [for (final r in pending) if (!state.answered.contains(r.uid)) r];

  Future<StudioRespondResult?> approve(String uid) => _respond(uid, true);
  Future<StudioRespondResult?> decline(String uid) => _respond(uid, false);

  Future<StudioRespondResult?> _respond(String uid, bool approve) async {
    if (state.inFlight.contains(uid)) return null;
    state = state.copyWith(inFlight: {...state.inFlight, uid}, clearError: true);
    try {
      final r = await ref.read(studioRolesApiProvider).respond(streamId, uid, approve: approve);
      if (ref.mounted) {
        state = state.copyWith(
          inFlight: {...state.inFlight}..remove(uid),
          answered: {...state.answered, uid},
        );
      }
      return r;
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(inFlight: {...state.inFlight}..remove(uid), error: studioErrorMessage(e));
      }
      return null;
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}
