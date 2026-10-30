// Test-only fakes for the Game Live workstream.

import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/contracts/studio_ports.dart';
import 'package:oneova/backend/live_studio/media/game_stream.dart';

class FakeHandle implements StudioVideoHandle {
  FakeHandle(this.uid);
  @override
  final String uid;
  @override
  bool get hasVideo => true;
  @override
  void setRenderSize(double width, double height) {}
}

/// Room with a toggleable screen share and camera handles.
class FakeGamingRoom implements StudioRoomPort, StudioGameStreamPort {
  FakeGamingRoom({this.screenOwner, this.cameras = const {}, this.failStart = false});

  /// uid publishing the screen, or null = no screen track.
  String? screenOwner;
  final Set<String> cameras;
  bool failStart;
  int gameStarts = 0;
  int tableStarts = 0;

  @override
  Future<void> startGameStream() async {
    gameStarts++;
    if (failStart) throw StateError('Screen sharing was not allowed.');
    screenOwner = 'host';
  }

  @override
  StudioVideoHandle? tableScreen() => screenOwner == null ? null : FakeHandle(screenOwner!);
  @override
  StudioVideoHandle? cameraOf(String uid) => cameras.contains(uid) ? FakeHandle(uid) : null;
  @override
  Stream<List<String>> get activeSpeakers => const Stream.empty();
  @override
  List<String> get currentSpeakers => const [];
  @override
  Stream<StudioEvent> get events => const Stream.empty();
  @override
  Stream<StudioLinkQuality> get quality => const Stream.empty();
  @override
  bool get audioOnly => false;
  @override
  bool isSpeaking(String uid) => false;
  @override
  bool isMicMuted(String uid) => false;
  @override
  Future<void> setMicEnabled(bool on) async {}
  @override
  Future<void> setCameraEnabled(bool on) async {}
  @override
  Future<void> startTableScreenShare() async => tableStarts++;
  @override
  Future<void> stopTableScreenShare() async {}
  @override
  Future<void> disconnect() async {}
}

/// A room without [StudioGameStreamPort] (fallback path).
class PlainRoom implements StudioRoomPort {
  final FakeGamingRoom inner = FakeGamingRoom();
  @override
  StudioVideoHandle? tableScreen() => inner.tableScreen();
  @override
  StudioVideoHandle? cameraOf(String uid) => inner.cameraOf(uid);
  @override
  Stream<List<String>> get activeSpeakers => inner.activeSpeakers;
  @override
  List<String> get currentSpeakers => inner.currentSpeakers;
  @override
  Stream<StudioEvent> get events => inner.events;
  @override
  Stream<StudioLinkQuality> get quality => inner.quality;
  @override
  bool get audioOnly => false;
  @override
  bool isSpeaking(String uid) => false;
  @override
  bool isMicMuted(String uid) => false;
  @override
  Future<void> setMicEnabled(bool on) async {}
  @override
  Future<void> setCameraEnabled(bool on) async {}
  @override
  Future<void> startTableScreenShare() => inner.startTableScreenShare();
  @override
  Future<void> stopTableScreenShare() async {}
  @override
  Future<void> disconnect() async {}
}
