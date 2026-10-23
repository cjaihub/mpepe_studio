import 'dart:async';

import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/contracts/studio_ports.dart';

/// Test-only fakes for the layout workstream.
class FakeRoom implements StudioRoomPort {
  final _speakers = StreamController<List<String>>.broadcast(sync: true);
  List<String> _current = const [];

  void speak(List<String> uids) {
    _current = uids;
    _speakers.add(uids);
  }

  @override
  Stream<List<String>> get activeSpeakers => _speakers.stream;
  @override
  List<String> get currentSpeakers => _current;
  @override
  Stream<StudioEvent> get events => const Stream.empty();
  @override
  Stream<StudioLinkQuality> get quality => const Stream.empty();
  @override
  bool get audioOnly => false;
  @override
  StudioVideoHandle? cameraOf(String uid) => null;
  @override
  StudioVideoHandle? tableScreen() => null;
  @override
  bool isSpeaking(String uid) => _current.contains(uid);
  @override
  bool isMicMuted(String uid) => false;
  @override
  Future<void> setMicEnabled(bool on) async {}
  @override
  Future<void> setCameraEnabled(bool on) async {}
  @override
  Future<void> startTableScreenShare() async {}
  @override
  Future<void> stopTableScreenShare() async {}
  @override
  Future<void> disconnect() async => _speakers.close();
}

class FakeCallPort implements StudioCallPort {
  final List<(String, Map<String, dynamic>)> calls = [];
  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> args) async {
    calls.add((name, args));
    return {'ok': true};
  }
}

class FakeClock {
  int ms = 1000000;
  int now() => ms;
  void advance(int d) => ms += d;
}

StageLayout stage6({String center = 'host', String? pinned, List<String> overflow = const []}) =>
    StageLayout(
      centerUid: center,
      wall: const ['g1', 'g2', 'g3', 'g4', 'g5', 'g6']
          .map((u) => u == center ? 'host' : u)
          .toList(),
      overflow: overflow,
      pinnedUid: pinned,
    );
