// LIVE STUDIO v2 — client session: the single source of [StudioState]
// (workstream #1, ARCHITECTURE §3).
//
// Providers:
// - [studioRoomProvider] (streamId) → the connected [StudioRoomPort] (LiveKit);
// - [studioStateProvider] (streamId) → AsyncValue<StudioState>, merged from
//   `lsStateFull` (or a one-time Firestore get) + `state.patch` / `state.full`
//   data events in seq order. Alias: [studioSessionProvider]; its notifier's
//   [StudioSessionController.states] is a Stream<StudioState> for adapters;
// - [studioMyRoleProvider] (streamId) → my role, from my members doc;
// - [studioMembersProvider] (streamId) → all members docs;
// - [studioClockProvider] → server clock offset (lsTime, 5 samples).

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../looks/live/live_looks_controller.dart';
import '../../observability/telemetry_service.dart';
import '../contracts/studio_contracts.dart';
import '../contracts/studio_ports.dart';
import '../media/livekit_studio_room.dart';
import '../media/qos_sampler.dart';
import '../media/studio_media_api.dart';
import 'studio_clock.dart';
import 'studio_state_sync.dart';

// ─── Injection points (overridden in tests) ──────────────────────────────────

final studioFirestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

/// Signed-in uid (null when signed out).
final studioMyUidProvider = Provider<String?>((ref) => FirebaseAuth.instance.currentUser?.uid);

/// One-time read of `studio/state` (fallback when lsStateFull fails).
typedef StudioStateReader = Future<StudioState?> Function(String streamId);

final studioStateReaderProvider = Provider<StudioStateReader>((ref) {
  final db = ref.watch(studioFirestoreProvider);
  return (streamId) async {
    try {
      final snap = await db.doc(StudioPaths.state(streamId)).get();
      final data = snap.data();
      if (data != null) return StudioState.fromJson(data);
    } catch (_) {}

    // Resilient fallback: derive a valid StudioState from parent live_streams doc
    try {
      final streamSnap = await db.collection('live_streams').doc(streamId).get();
      final d = streamSnap.data();
      if (d != null) {
        final hostId = (d['hostId'] as String?) ?? '';
        final title = (d['title'] as String?) ?? 'Live Studio';
        final statusStr = (d['status'] as String?) ?? 'live';
        final isEnded = statusStr == 'ended';
        final now = DateTime.now().millisecondsSinceEpoch;
        return StudioState(
          schemaVersion: 1,
          streamId: streamId,
          hostId: hostId,
          title: title,
          status: isEnded ? StudioStatus.ended : StudioStatus.live,
          seq: 0,
          settings: const StudioSettings(),
          stage: StageLayout(
            centerUid: hostId,
            updatedAtMs: now,
            updatedBy: hostId,
          ),
          table: const TableState(),
          counts: const StudioCounts(viewers: 1),
        );
      }
    } catch (_) {}
    return null;
  };
});

/// Delay before asking for a full state after a seq gap: a short grace for
/// out-of-order packets plus jitter so 100k viewers do not resync at once.
final studioGapResyncDelayProvider = Provider<Duration Function()>((ref) {
  final r = Random();
  return () => Duration(milliseconds: 400 + r.nextInt(600));
});

// ─── Room ────────────────────────────────────────────────────────────────────

/// The live room for [streamId]. Connecting starts on first read; the room
/// disconnects when the last listener goes away.
final studioRoomProvider = Provider.autoDispose.family<StudioRoomPort, String>((ref, streamId) {
  final room = LiveKitStudioRoom(
    streamId: streamId,
    api: ref.watch(studioMediaApiProvider),
    metrics: TelemetryMetricsSink(ref.watch(telemetryServiceProvider)),
  );
  room.onCameraTrackPublished = (trackId) {
    ref.read(liveLooksControllerProvider.notifier).attachCameraTrack(trackId);
  };
  room.onCameraTrackUnpublished = (trackId) {
    ref.read(liveLooksControllerProvider.notifier).detachCameraTrack();
  };
  final started = ref.read(studioStartCredentialsProvider).remove(streamId);
  if (started != null) room.useInitialCredentials(started);
  final media = ref.read(studioStartMediaProvider).remove(streamId);
  if (media != null) {
    room
      ..hostStartsWithMic = media.mic
      ..hostStartsWithCamera = media.camera;
  }
  unawaited(room.connect());
  ref.onDispose(() => unawaited(room.disconnect()));
  return room;
});

// ─── State ───────────────────────────────────────────────────────────────────

final studioStateProvider =
    NotifierProvider.autoDispose.family<StudioSessionController, AsyncValue<StudioState>, String>(
        StudioSessionController.new);

/// Same provider as [studioStateProvider] (name used by other workstreams).
final studioSessionProvider = studioStateProvider;

class StudioSessionController extends Notifier<AsyncValue<StudioState>> {
  StudioSessionController(this.streamId);

  final String streamId;

  StudioStateSync _sync = StudioStateSync();
  StreamController<StudioState> _states = StreamController<StudioState>.broadcast();
  Timer? _gapTimer;
  bool _resyncing = false;
  bool _resyncAgain = false;
  bool _wasLost = false;

  /// Current merged state (null until the first full state).
  StudioState? get current => _sync.state;

  /// Every new merged state; replays the current one to each new listener.
  Stream<StudioState> get states {
    final ctl = _states;
    return Stream<StudioState>.multi((c) {
      final s = _sync.state;
      if (s != null) c.add(s);
      final sub = ctl.stream.listen(c.add, onError: c.addError, onDone: c.close);
      c.onCancel = sub.cancel;
    });
  }

  @override
  AsyncValue<StudioState> build() {
    _sync = StudioStateSync();
    _resyncing = false;
    _resyncAgain = false;
    _wasLost = false;
    final states = StreamController<StudioState>.broadcast();
    _states = states;

    final room = ref.watch(studioRoomProvider(streamId));
    final evSub = room.events.listen(_onEvent);
    final qSub = room.quality.listen(_onQuality);
    ref.onDispose(() {
      evSub.cancel();
      qSub.cancel();
      _gapTimer?.cancel();
      _gapTimer = null;
      states.close();
    });

    Future.microtask(resync);
    return const AsyncLoading();
  }

  /// Fetches the authoritative state (lsStateFull, else Firestore get).
  Future<void> resync() async {
    if (_resyncing) {
      _resyncAgain = true;
      return;
    }
    _resyncing = true;
    final sync = _sync;
    try {
      StudioState? full;
      Object? callError;
      // First load: read Firestore in parallel so a cold lsStateFull (up to
      // its 15 s timeout) never holds the join spinner. applyFull keeps
      // whichever is newer. Later resyncs use the callable alone.
      Future<StudioState?>? early;
      if (_sync.state == null) {
        early = ref.read(studioStateReaderProvider)(streamId).then<StudioState?>((s) => s, onError: (_) => null);
        unawaited(early.then((s) {
          if (s != null && ref.mounted && identical(sync, _sync) && _sync.applyFull(s)) _emit();
        }));
      }
      try {
        full = await ref.read(studioMediaApiProvider).stateFull(streamId);
      } catch (e) {
        callError = e;
      }
      if (!ref.mounted || !identical(sync, _sync)) return;
      full ??= await (early ?? ref.read(studioStateReaderProvider)(streamId));
      if (!ref.mounted || !identical(sync, _sync)) return;
      if (full != null) {
        if (_sync.applyFull(full)) _emit();
      } else if (_sync.state == null) {
        state = AsyncError(callError ?? StateError('This live does not exist.'), StackTrace.current);
      }
    } catch (e, st) {
      if (ref.mounted && identical(sync, _sync) && _sync.state == null) state = AsyncError(e, st);
    } finally {
      if (identical(sync, _sync)) _resyncing = false;
    }
    if (!ref.mounted || !identical(sync, _sync)) return;
    if (_resyncAgain) {
      _resyncAgain = false;
      unawaited(resync());
    } else {
      _checkGap();
    }
  }

  void _onEvent(StudioEvent e) {
    switch (e) {
      case StatePatchEvent():
        if (_sync.applyPatch(e) == StudioPatchOutcome.applied) _emit();
        _checkGap();
      case StateFullEvent():
        if (_sync.applyFull(e.state)) _emit();
        _checkGap();
      default:
        break;
    }
  }

  void _onQuality(StudioLinkQuality q) {
    if (q == StudioLinkQuality.lost) {
      _wasLost = true;
    } else if (_wasLost) {
      // Back from a disconnect: data events may have been missed.
      _wasLost = false;
      unawaited(resync());
    }
  }

  void _checkGap() {
    if (!_sync.hasGap) {
      _gapTimer?.cancel();
      _gapTimer = null;
      return;
    }
    _gapTimer ??= Timer(ref.read(studioGapResyncDelayProvider)(), () {
      _gapTimer = null;
      if (ref.mounted && _sync.hasGap) unawaited(resync());
    });
  }

  void _emit() {
    final s = _sync.state;
    if (s == null || !ref.mounted) return;
    state = AsyncData(s);
    if (!_states.isClosed) _states.add(s);
  }
}

// ─── Members / role ──────────────────────────────────────────────────────────

/// All `members` docs (stage members, co-hosts, removed guests), join order.
final studioMembersProvider = StreamProvider.autoDispose.family<List<StageMember>, String>((ref, streamId) {
  final db = ref.watch(studioFirestoreProvider);
  return db.collection(StudioPaths.members(streamId)).snapshots().map((q) {
    final list = [for (final d in q.docs) StageMember.fromJson({'uid': d.id, ...d.data()})];
    list.sort((a, b) => a.joinedAtMs.compareTo(b.joinedAtMs));
    return list;
  });
});

/// My role in [streamId]: from my members doc; viewer when there is none.
final studioMyRoleProvider = StreamProvider.autoDispose.family<StudioRole, String>((ref, streamId) {
  final uid = ref.watch(studioMyUidProvider);
  if (uid == null || uid.isEmpty) return Stream.value(StudioRole.viewer);
  final db = ref.watch(studioFirestoreProvider);
  return db.doc('${StudioPaths.members(streamId)}/$uid').snapshots().map((d) {
    final data = d.data();
    return data == null ? StudioRole.viewer : StudioRole.fromWire(data['role']);
  });
});

// ─── Clock ───────────────────────────────────────────────────────────────────

/// Server clock; calibrates once on first read. Call `calibrate()` again
/// after a reconnect or when starting a watch party.
final studioClockProvider = Provider<StudioClockPort>((ref) {
  final clock = CallableStudioClock(ref.watch(studioCallPortProvider));
  unawaited(clock.calibrate());
  return clock;
});
