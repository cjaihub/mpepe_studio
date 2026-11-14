// ─────────────────────────────────────────────────────────────────────────────
// LIVE STUDIO v2 — PORTS (integrator-owned).
//
// The seams between workstreams. Media (#1) implements [StudioRoomPort] on top
// of LiveKit; every other workstream depends only on these interfaces, so they
// can be built and tested in parallel with fakes.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'studio_contracts.dart';

/// Calls a `ls*` callable and returns its JSON result.
abstract class StudioCallPort {
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> args);
}

class FirebaseStudioCallPort implements StudioCallPort {
  FirebaseStudioCallPort([FirebaseFunctions? functions])
      : _functions = functions ?? FirebaseFunctions.instance;
  final FirebaseFunctions _functions;

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> args) async {
    final callable = _functions.httpsCallable(
      name,
      options: HttpsCallableOptions(timeout: const Duration(seconds: 40)),
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await callable.call<Object?>(args);
        final data = res.data;
        return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      } on FirebaseFunctionsException catch (e) {
        final retryable = e.code == 'deadline-exceeded' ||
            e.code == 'unavailable' ||
            e.code == 'aborted' ||
            e.code == 'internal';
        if (!retryable || attempt == 1) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    }
    return <String, dynamic>{};
  }
}

final studioCallPortProvider = Provider<StudioCallPort>((ref) => FirebaseStudioCallPort());

/// Media connection quality as seen by the local client.
enum StudioLinkQuality { excellent, good, poor, lost }

/// One publisher's media as rendered by the stage (opaque to non-media code).
abstract class StudioVideoHandle {
  String get uid;
  bool get hasVideo;

  /// Tells the SFU how big this video is drawn so it picks the right
  /// simulcast layer (0×0 = not visible → pause).
  void setRenderSize(double width, double height);
}

/// The live room: media + data events. Implemented by the media workstream.
abstract class StudioRoomPort {
  /// Decoded data messages from all topics, in arrival order.
  Stream<StudioEvent> get events;

  /// SFU active speakers, loudest first (uids).
  Stream<List<String>> get activeSpeakers;

  /// Current active speakers snapshot.
  List<String> get currentSpeakers;

  Stream<StudioLinkQuality> get quality;

  /// True when this client fell back to audio-only.
  bool get audioOnly;

  /// Video for a publisher (camera), or null if not published.
  StudioVideoHandle? cameraOf(String uid);

  /// The table screen-share video, if someone publishes it.
  StudioVideoHandle? tableScreen();

  /// Speaking right now (audio level above threshold), for nameplate bars.
  bool isSpeaking(String uid);
  bool isMicMuted(String uid);

  // Local publishing (only effective when the token grants publish).
  Future<void> setMicEnabled(bool on);
  Future<void> setCameraEnabled(bool on);
  Future<void> startTableScreenShare();
  Future<void> stopTableScreenShare();

  Future<void> disconnect();
}

/// Server clock offset (serverMs − localMs), for watch-party sync.
abstract class StudioClockPort {
  int get offsetMs;
  int serverNowMs();
  Future<void> calibrate();
}
