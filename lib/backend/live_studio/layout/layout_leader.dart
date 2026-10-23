import 'dart:async';

import '../contracts/studio_contracts.dart';
import '../contracts/studio_ports.dart';
import 'layout_commands.dart';
import 'speaker_hysteresis.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LayoutLeader — ARCHITECTURE §8. Exactly one client drives auto layout:
//  • the host while the host is connected;
//  • otherwise, once the host has been gone for StudioLimits.leaderFailover
//    (10 s), the longest-serving connected coHost (lowest joinedAtMs, uid as
//    tie-break);
//  • nobody during the failover window.
// The leader in autoActiveSpeaker mode feeds StudioRoomPort.activeSpeakers
// into SpeakerHysteresis and calls lsSetLayout {op: autoPromote, uid}.
// The server re-checks leadership, mode, pin and hold (layout_logic.ts).
// ─────────────────────────────────────────────────────────────────────────────

/// Pure leader election. [hostAbsentSinceMs] is when the host was last seen
/// leaving (null while connected or never seen).
String? electLayoutLeader({
  required String hostId,
  required Iterable<StageMember> members,
  required Set<String> connected,
  required int? hostAbsentSinceMs,
  required int nowMs,
  Duration failover = StudioLimits.leaderFailover,
}) {
  if (connected.contains(hostId)) return hostId;
  if (hostAbsentSinceMs != null && nowMs - hostAbsentSinceMs < failover.inMilliseconds) {
    return null;
  }
  StageMember? best;
  for (final m in members) {
    if (m.role != StudioRole.coHost || !connected.contains(m.uid) || m.uid == hostId) continue;
    if (best == null ||
        m.joinedAtMs < best.joinedAtMs ||
        (m.joinedAtMs == best.joinedAtMs && m.uid.compareTo(best.uid) < 0)) {
      best = m;
    }
  }
  return best?.uid;
}

class LayoutLeader {
  LayoutLeader({
    required this.selfUid,
    required StudioRoomPort room,
    required LayoutCommands commands,
    NowMs? nowMs,
    Stream<void>? ticks,
    Duration tickEvery = const Duration(milliseconds: 250),
  })  : _commands = commands, // ignore: prefer_initializing_formals
        _now = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch) {
    _hysteresis = SpeakerHysteresis(nowMs: _now);
    _subs.add(room.activeSpeakers.listen((s) {
      _hysteresis.onSpeakers(s);
      _drive();
    }));
    _hysteresis.onSpeakers(room.currentSpeakers);
    _subs.add((ticks ?? Stream<void>.periodic(tickEvery)).listen((_) => _drive()));
  }

  final String selfUid;
  final LayoutCommands _commands;
  final NowMs _now;
  late final SpeakerHysteresis _hysteresis;
  final List<StreamSubscription<Object?>> _subs = [];

  StudioState? _state;
  Map<String, StageMember> _members = const {};
  Set<String>? _connected;
  int? _hostAbsentSince;
  bool _inFlight = false;
  bool _disposed = false;

  /// Promotions sent (for tests and telemetry).
  final List<String> sent = [];

  /// The current leader uid (null = nobody, e.g. during failover).
  String? get leaderUid {
    final s = _state;
    if (s == null) return null;
    return electLayoutLeader(
      hostId: s.hostId,
      members: _members.values,
      // No presence yet: assume the host is there (a coHost never takes
      // over without evidence that the host left).
      connected: _connected ?? {selfUid, s.hostId},
      hostAbsentSinceMs: _hostAbsentSince,
      nowMs: _now(),
    );
  }

  bool get isLeader => leaderUid == selfUid;

  void updateState(StudioState state) {
    _state = state;
    _hysteresis.observeStage(state.stage);
    _drive();
  }

  void updateMembers(Map<String, StageMember> members) {
    _members = members;
    _drive();
  }

  /// Connected room identities (from the media layer's participant list).
  void updatePresence(Set<String> connected) {
    final hostId = _state?.hostId;
    if (hostId != null) {
      final wasIn = _connected?.contains(hostId) ?? false;
      final isIn = connected.contains(hostId);
      if (isIn) {
        _hostAbsentSince = null;
      } else if (wasIn || _connected == null) {
        _hostAbsentSince ??= _now();
      }
    }
    _connected = connected;
    _drive();
  }

  void _drive() {
    final s = _state;
    if (_disposed || s == null || _inFlight || !isLeader) return;
    final uid = _hysteresis.evaluate(stage: s.stage, mode: s.settings.speakerMode);
    if (uid == null) return;
    _inFlight = true;
    sent.add(uid);
    _commands.autoPromote(uid).catchError((Object _) => <String, dynamic>{}).whenComplete(() {
      _inFlight = false;
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final s in _subs) {
      await s.cancel();
    }
  }
}
