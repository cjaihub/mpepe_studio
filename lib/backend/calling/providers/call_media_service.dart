import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Where call audio plays.
enum AudioRoute { earpiece, speaker, bluetooth, wired }

class AudioOutputOption {
  final AudioRoute route;
  final String deviceId;
  final String label;
  const AudioOutputOption(this.route, this.deviceId, this.label);
}

class CallMediaState {
  final MediaStream? localStream;
  final bool isAudioMuted;

  /// Camera is sending. False for audio calls and when the user turns the
  /// camera off.
  final bool isVideoOn;
  final bool isFrontCamera;
  final AudioRoute audioRoute;
  final List<AudioOutputOption> outputs;

  const CallMediaState({
    this.localStream,
    this.isAudioMuted = false,
    this.isVideoOn = false,
    this.isFrontCamera = true,
    this.audioRoute = AudioRoute.earpiece,
    this.outputs = const [],
  });

  bool get hasVideoTrack => localStream?.getVideoTracks().isNotEmpty ?? false;
  bool get hasBluetooth => outputs.any((o) => o.route == AudioRoute.bluetooth);

  CallMediaState copyWith({
    MediaStream? localStream,
    bool? isAudioMuted,
    bool? isVideoOn,
    bool? isFrontCamera,
    AudioRoute? audioRoute,
    List<AudioOutputOption>? outputs,
  }) {
    return CallMediaState(
      localStream: localStream ?? this.localStream,
      isAudioMuted: isAudioMuted ?? this.isAudioMuted,
      isVideoOn: isVideoOn ?? this.isVideoOn,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      audioRoute: audioRoute ?? this.audioRoute,
      outputs: outputs ?? this.outputs,
    );
  }
}

final callMediaServiceProvider =
    NotifierProvider<CallMediaService, CallMediaState>(CallMediaService.new);

/// Local microphone/camera and audio routing for the active call.
class CallMediaService extends Notifier<CallMediaState> {
  @override
  CallMediaState build() => const CallMediaState();

  static const Map<String, dynamic> _videoConstraints = {
    'facingMode': 'user',
    'width': {'ideal': 960},
    'height': {'ideal': 540},
    'frameRate': {'ideal': 24, 'max': 30},
  };

  /// Opens the microphone (and camera for video calls).
  Future<void> initializeMedia({required bool video}) async {
    if (state.localStream != null) return;
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': video ? _videoConstraints : false,
    });
    state = state.copyWith(
      localStream: stream,
      isVideoOn: video,
      isAudioMuted: false,
      audioRoute: video ? AudioRoute.speaker : AudioRoute.earpiece,
    );
    navigator.mediaDevices.ondevicechange = (_) => _onDevicesChanged();
    await refreshOutputs();
    // Video calls default to the loudspeaker, audio calls to the earpiece,
    // unless a headset is connected.
    final preferred = state.outputs.firstWhere(
      (o) => o.route == AudioRoute.bluetooth || o.route == AudioRoute.wired,
      orElse: () => AudioOutputOption(
        video ? AudioRoute.speaker : AudioRoute.earpiece,
        video ? 'speaker' : 'earpiece',
        '',
      ),
    );
    await selectRoute(preferred.route, deviceId: preferred.deviceId);
  }

  /// A headset was plugged in or paired mid-call: switch to it. The device in
  /// use went away: fall back to the speaker (video) or earpiece (audio).
  Future<void> _onDevicesChanged() async {
    if (state.localStream == null) return;
    final before = state.outputs.map((o) => o.route).toSet();
    await refreshOutputs();
    final after = state.outputs;
    final added = after.where(
      (o) => (o.route == AudioRoute.bluetooth || o.route == AudioRoute.wired) && !before.contains(o.route),
    );
    if (added.isNotEmpty) {
      await selectRoute(added.first.route, deviceId: added.first.deviceId);
      return;
    }
    if (!after.any((o) => o.route == state.audioRoute)) {
      await selectRoute(state.isVideoOn ? AudioRoute.speaker : AudioRoute.earpiece);
    }
  }

  void toggleAudio() => setAudioMuted(!state.isAudioMuted);

  void setAudioMuted(bool muted) {
    for (final t in state.localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
    state = state.copyWith(isAudioMuted: muted);
  }

  /// Turns the camera on or off. Returns the track to send (null when off) so
  /// the mesh can `replaceTrack` it.
  Future<MediaStreamTrack?> setVideoOn(bool on) async {
    final stream = state.localStream;
    if (stream == null) return null;
    if (on && stream.getVideoTracks().isEmpty) {
      // Audio → video upgrade: open the camera now.
      final cam = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {..._videoConstraints, 'facingMode': state.isFrontCamera ? 'user' : 'environment'},
      });
      final track = cam.getVideoTracks().first;
      await stream.addTrack(track);
      state = state.copyWith(isVideoOn: true, localStream: stream);
      if (state.audioRoute == AudioRoute.earpiece) await selectRoute(AudioRoute.speaker);
      return track;
    }
    final tracks = stream.getVideoTracks();
    for (final t in tracks) {
      t.enabled = on;
    }
    state = state.copyWith(isVideoOn: on);
    return on && tracks.isNotEmpty ? tracks.first : null;
  }

  Future<void> switchCamera() async {
    final tracks = state.localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
    state = state.copyWith(isFrontCamera: !state.isFrontCamera);
  }

  Future<void> refreshOutputs() async {
    try {
      final devices = await Helper.audiooutputs;
      final options = <AudioOutputOption>[];
      for (final d in devices) {
        final id = d.deviceId;
        final key = '${d.deviceId} ${d.label}'.toLowerCase();
        AudioRoute? route;
        if (key.contains('bluetooth') || key.contains('bt') || key.contains('airpods')) {
          route = AudioRoute.bluetooth;
        } else if (key.contains('wired') || key.contains('headset') || key.contains('headphone')) {
          route = AudioRoute.wired;
        } else if (key.contains('speaker')) {
          route = AudioRoute.speaker;
        } else if (key.contains('earpiece') || key.contains('receiver') || key.contains('iphone')) {
          route = AudioRoute.earpiece;
        }
        if (route != null && !options.any((o) => o.route == route)) {
          options.add(AudioOutputOption(route, id, d.label));
        }
      }
      if (!options.any((o) => o.route == AudioRoute.speaker)) {
        options.add(const AudioOutputOption(AudioRoute.speaker, 'speaker', 'Speaker'));
      }
      if (!options.any((o) => o.route == AudioRoute.earpiece || o.route == AudioRoute.wired)) {
        options.add(const AudioOutputOption(AudioRoute.earpiece, 'earpiece', 'Phone'));
      }
      state = state.copyWith(outputs: options);
    } catch (e) {
      debugPrint('[CallMedia] audio outputs unavailable: $e');
    }
  }

  Future<void> selectRoute(AudioRoute route, {String? deviceId}) async {
    try {
      final option = state.outputs.firstWhere(
        (o) => o.route == route,
        orElse: () => AudioOutputOption(route, deviceId ?? route.name, ''),
      );
      switch (route) {
        case AudioRoute.speaker:
          await Helper.setSpeakerphoneOn(true);
          break;
        case AudioRoute.earpiece:
          await Helper.setSpeakerphoneOn(false);
          if (defaultTargetPlatform == TargetPlatform.android) {
            await Helper.selectAudioOutput('earpiece');
          }
          break;
        case AudioRoute.bluetooth:
        case AudioRoute.wired:
          await Helper.setSpeakerphoneOn(false);
          await Helper.selectAudioOutput(deviceId ?? option.deviceId);
          break;
      }
      state = state.copyWith(audioRoute: route);
    } catch (e) {
      debugPrint('[CallMedia] selectRoute($route) failed: $e');
    }
  }

  /// Speaker ↔ earpiece (or headset) quick toggle.
  Future<void> toggleSpeaker() async {
    if (state.audioRoute == AudioRoute.speaker) {
      final headset = state.outputs.where(
        (o) => o.route == AudioRoute.bluetooth || o.route == AudioRoute.wired,
      );
      if (headset.isNotEmpty) {
        await selectRoute(headset.first.route, deviceId: headset.first.deviceId);
      } else {
        await selectRoute(AudioRoute.earpiece);
      }
    } else {
      await selectRoute(AudioRoute.speaker);
    }
  }

  Future<void> disposeMedia() async {
    navigator.mediaDevices.ondevicechange = null;
    final stream = state.localStream;
    state = const CallMediaState();
    if (stream == null) return;
    for (final t in stream.getTracks()) {
      try {
        await t.stop();
      } catch (_) {}
    }
    try {
      await stream.dispose();
    } catch (_) {}
  }
}
