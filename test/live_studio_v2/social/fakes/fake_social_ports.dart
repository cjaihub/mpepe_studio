// Test-only fakes for the realtime social workstream.
import 'dart:async';

import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/contracts/studio_ports.dart';
import 'package:oneova/backend/live_studio/social/studio_social_ports.dart';

class FakeRoomPort implements StudioRoomPort {
  final StreamController<StudioEvent> _events = StreamController<StudioEvent>.broadcast();
  void emit(StudioEvent e) => _events.add(e);

  @override
  Stream<StudioEvent> get events => _events.stream;
  @override
  Stream<List<String>> get activeSpeakers => const Stream.empty();
  @override
  List<String> get currentSpeakers => const [];
  @override
  Stream<StudioLinkQuality> get quality => const Stream.empty();
  @override
  bool get audioOnly => false;
  @override
  StudioVideoHandle? cameraOf(String uid) => null;
  @override
  StudioVideoHandle? tableScreen() => null;
  @override
  bool isSpeaking(String uid) => false;
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
  Future<void> disconnect() async {}
}

class RecordedCall {
  RecordedCall(this.name, this.args);
  final String name;
  final Map<String, dynamic> args;
}

/// Records calls; each call is answered by [handler] (default: `{}`), and
/// [gate] (when set) holds the response until completed.
class FakeCallPort implements StudioCallPort {
  final List<RecordedCall> calls = [];
  FutureOr<Map<String, dynamic>> Function(String name, Map<String, dynamic> args)? handler;
  Completer<void>? gate;

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> args) async {
    calls.add(RecordedCall(name, args));
    if (gate != null) await gate!.future;
    return await (handler?.call(name, args) ?? <String, dynamic>{});
  }
}

class FakeHistorySource implements StudioCommentHistorySource {
  FakeHistorySource(this.items);
  final List<LiveStudioComment> items;
  Completer<void>? hold;

  @override
  Future<List<LiveStudioComment>> latest(String streamId, int limit) async {
    if (hold != null) await hold!.future;
    final sorted = [...items]..sort((a, b) => a.ts.compareTo(b.ts));
    return sorted.length > limit ? sorted.sublist(sorted.length - limit) : sorted;
  }
}

LiveStudioComment comment(String id, {int ts = 0, String uid = 'u', String text = 'hi'}) =>
    LiveStudioComment(id: id, uid: uid, name: 'N$uid', text: text, ts: ts);
