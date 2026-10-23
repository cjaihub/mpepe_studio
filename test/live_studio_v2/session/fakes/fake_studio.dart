// Test-only fakes for the media / session workstream.

import 'dart:async';

import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/contracts/studio_ports.dart';

/// Records calls; answers from [handlers] (name → result or throw).
class FakeCallPort implements StudioCallPort {
  final Map<String, FutureOr<Map<String, dynamic>> Function(Map<String, dynamic> args)> handlers = {};
  final List<(String, Map<String, dynamic>)> calls = [];

  /// Registers a handler; chainable.
  FakeCallPort on(String name, FutureOr<Map<String, dynamic>> Function(Map<String, dynamic> args) h) {
    handlers[name] = h;
    return this;
  }

  int count(String name) => calls.where((c) => c.$1 == name).length;

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> args) async {
    calls.add((name, args));
    final h = handlers[name];
    if (h == null) return <String, dynamic>{};
    return await h(args);
  }
}

class FakeRoom implements StudioRoomPort {
  final eventsCtl = StreamController<StudioEvent>.broadcast(sync: true);
  final speakersCtl = StreamController<List<String>>.broadcast(sync: true);
  final qualityCtl = StreamController<StudioLinkQuality>.broadcast(sync: true);
  bool disconnected = false;

  void emit(StudioEvent e) => eventsCtl.add(e);
  void setQuality(StudioLinkQuality q) => qualityCtl.add(q);

  @override
  Stream<StudioEvent> get events => eventsCtl.stream;
  @override
  Stream<List<String>> get activeSpeakers => speakersCtl.stream;
  @override
  List<String> get currentSpeakers => const [];
  @override
  Stream<StudioLinkQuality> get quality => qualityCtl.stream;
  @override
  bool get audioOnly => false;
  @override
  StudioVideoHandle? cameraOf(String uid) => null;
  @override
  StudioVideoHandle? tableScreen() => null;
  @override
  bool isSpeaking(String uid) => false;
  @override
  bool isMicMuted(String uid) => true;
  @override
  Future<void> setMicEnabled(bool on) async {}
  @override
  Future<void> setCameraEnabled(bool on) async {}
  @override
  Future<void> startTableScreenShare() async {}
  @override
  Future<void> stopTableScreenShare() async {}
  @override
  Future<void> disconnect() async => disconnected = true;
}

StudioState testState({int seq = 0, String title = 'T', String center = 'host'}) => StudioState(
      streamId: 's1',
      hostId: 'host',
      title: title,
      status: StudioStatus.live,
      seq: seq,
      stage: StageLayout(centerUid: center),
    );
