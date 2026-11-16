import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../shared/audio/mic_coordinator.dart';

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

  /// Zero-cost on-device Studio Voice Clean (hardware + WebRTC AEC/NS/AGC/HPF).
  final bool isVoiceEnhanced;

  /// Increments whenever tracks inside [localStream] are added/swapped so
  /// renderers re-bind even when [localStream.id] stays the same.
  final int streamRevision;
  final AudioRoute audioRoute;
  final List<AudioOutputOption> outputs;

  /// Display media stream when screen sharing is active.
  final MediaStream? screenStream;
  final bool isScreenSharing;

  const CallMediaState({
    this.localStream,
    this.isAudioMuted = false,
    this.isVideoOn = false,
    this.isFrontCamera = true,
    this.isVoiceEnhanced = true,
    this.streamRevision = 0,
    this.audioRoute = AudioRoute.earpiece,
    this.outputs = const [],
    this.screenStream,
    this.isScreenSharing = false,
  });

  bool get hasVideoTrack => localStream?.getVideoTracks().isNotEmpty ?? false;
  bool get hasBluetooth => outputs.any((o) => o.route == AudioRoute.bluetooth);
  bool get isScreenSharingActive => isScreenSharing && screenStream != null;

  CallMediaState copyWith({
    MediaStream? localStream,
    bool? isAudioMuted,
    bool? isVideoOn,
    bool? isFrontCamera,
    bool? isVoiceEnhanced,
    int? streamRevision,
    AudioRoute? audioRoute,
    List<AudioOutputOption>? outputs,
    MediaStream? screenStream,
    bool? isScreenSharing,
    bool clearScreenStream = false,
  }) {
    return CallMediaState(
      localStream: localStream ?? this.localStream,
      isAudioMuted: isAudioMuted ?? this.isAudioMuted,
      isVideoOn: isVideoOn ?? this.isVideoOn,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      isVoiceEnhanced: isVoiceEnhanced ?? this.isVoiceEnhanced,
      streamRevision: streamRevision ?? this.streamRevision,
      audioRoute: audioRoute ?? this.audioRoute,
      outputs: outputs ?? this.outputs,
      screenStream: clearScreenStream ? null : (screenStream ?? this.screenStream),
      isScreenSharing: isScreenSharing ?? (clearScreenStream ? false : this.isScreenSharing),
    );
  }
}

final callMediaServiceProvider =
    NotifierProvider<CallMediaService, CallMediaState>(CallMediaService.new);

/// Local microphone/camera and audio routing for the active call.
class CallMediaService extends Notifier<CallMediaState> {
  @override
  CallMediaState build() => const CallMediaState();

  /// The call owns the mic for its whole length: Ova, AI voice, voice typing
  /// and voice notes are stopped before WebRTC opens it, and can't take it
  /// until the call ends. WebRTC handles audio focus itself.
  MicLease? _micLease;

  static const Map<String, dynamic> _videoConstraints = {
    'facingMode': 'user',
    'width': {'ideal': 1280},
    'height': {'ideal': 720},
    'frameRate': {'ideal': 30, 'max': 30},
  };

  static Map<String, dynamic> _audioConstraints({required bool enhanced}) {
    if (!enhanced) {
      return const {
        'echoCancellation': true,
        'noiseSuppression': false,
        'autoGainControl': false,
        'channelCount': 1,
        'sampleRate': 48000,
      };
    }
    return const {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
      'highPassFilter': true,
      'typingNoiseDetection': true,
      'channelCount': 1,
      'sampleRate': 48000,
      'googEchoCancellation': true,
      'googAutoGainControl': true,
      'googNoiseSuppression': true,
      'googHighpassFilter': true,
      'googTypingNoiseDetection': true,
    };
  }

  /// Maps [AudioRoute] to `flutter_webrtc` Android `AudioDeviceKind.typeName`.
  @visibleForTesting
  static String androidAudioDeviceTypeName(AudioRoute route) => switch (route) {
        AudioRoute.bluetooth => 'bluetooth',
        AudioRoute.wired => 'wired-headset',
        AudioRoute.speaker => 'speaker',
        AudioRoute.earpiece => 'earpiece',
      };

  /// Opens the microphone (and camera for video calls).
  Future<void> initializeMedia({
    required bool video,
    bool? voiceEnhanced,
    bool startMuted = false,
  }) async {
    if (state.localStream != null) return;
    final enhanced = voiceEnhanced ?? state.isVoiceEnhanced;
    final got = await MicCoordinator.instance.acquire(
      MicUser.call,
      onPreempted: () async {},
      takeFocus: false,
    );
    if (got is MicLease) _micLease = got;
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': _audioConstraints(enhanced: enhanced),
      'video': video ? _videoConstraints : false,
    });
    if (startMuted) {
      for (final t in stream.getAudioTracks()) {
        t.enabled = false;
      }
    }
    state = state.copyWith(
      localStream: stream,
      isVideoOn: video,
      isFrontCamera: true,
      isAudioMuted: startMuted,
      isVoiceEnhanced: enhanced,
      streamRevision: state.streamRevision + 1,
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
      state = state.copyWith(
        isVideoOn: true,
        localStream: stream,
        streamRevision: state.streamRevision + 1,
      );
      if (state.audioRoute == AudioRoute.earpiece) await selectRoute(AudioRoute.speaker);
      return track;
    }
    final tracks = stream.getVideoTracks();
    for (final t in tracks) {
      t.enabled = on;
    }
    state = state.copyWith(isVideoOn: on, streamRevision: state.streamRevision + 1);
    return on && tracks.isNotEmpty ? tracks.first : null;
  }

  /// Flips front ↔ rear camera. Uses native hardware switch first (<120ms,
  /// zero renegotiation); falls back to capturing a new track if a device HAL
  /// rejects in-place switching. Returns a replacement track only on fallback.
  Future<MediaStreamTrack?> switchCamera() async {
    final stream = state.localStream;
    final tracks = stream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (stream == null || tracks.isEmpty) return null;
    final nextFront = !state.isFrontCamera;
    try {
      await Helper.switchCamera(tracks.first);
      state = state.copyWith(
        isFrontCamera: nextFront,
        streamRevision: state.streamRevision + 1,
      );
      return null;
    } catch (e) {
      debugPrint('[CallMedia] Helper.switchCamera fallback: $e');
      final cam = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {..._videoConstraints, 'facingMode': nextFront ? 'user' : 'environment'},
      });
      final newTrack = cam.getVideoTracks().first;
      for (final old in List<MediaStreamTrack>.from(tracks)) {
        try {
          await stream.removeTrack(old);
          await old.stop();
        } catch (_) {}
      }
      await stream.addTrack(newTrack);
      state = state.copyWith(
        isFrontCamera: nextFront,
        localStream: stream,
        streamRevision: state.streamRevision + 1,
      );
      return newTrack;
    }
  }

  /// Toggles zero-cost Studio Voice Clean (hardware + WebRTC DSP) and returns
  /// the hot-swapped audio track if a call is active.
  Future<MediaStreamTrack?> toggleVoiceEnhanced() => setVoiceEnhanced(!state.isVoiceEnhanced);

  Future<MediaStreamTrack?> setVoiceEnhanced(bool enhanced) async {
    if (state.isVoiceEnhanced == enhanced) return null;
    final stream = state.localStream;
    if (stream == null) {
      state = state.copyWith(isVoiceEnhanced: enhanced);
      return null;
    }
    try {
      final fresh = await navigator.mediaDevices.getUserMedia({
        'audio': _audioConstraints(enhanced: enhanced),
        'video': false,
      });
      final newAudio = fresh.getAudioTracks().firstOrNull;
      if (newAudio == null) return null;
      newAudio.enabled = !state.isAudioMuted;
      for (final old in List<MediaStreamTrack>.from(stream.getAudioTracks())) {
        try {
          await stream.removeTrack(old);
          await old.stop();
        } catch (_) {}
      }
      await stream.addTrack(newAudio);
      state = state.copyWith(
        isVoiceEnhanced: enhanced,
        localStream: stream,
        streamRevision: state.streamRevision + 1,
      );
      return newAudio;
    } catch (e) {
      debugPrint('[CallMedia] setVoiceEnhanced($enhanced) failed: $e');
      state = state.copyWith(isVoiceEnhanced: enhanced);
      return null;
    }
  }

  /// Interpreter mode takes the microphone for itself: the call's mic track is
  /// stopped (callers send null on every connection first).
  Future<void> releaseMicForInterpreter() async {
    final stream = state.localStream;
    if (stream == null) return;
    for (final old in List<MediaStreamTrack>.from(stream.getAudioTracks())) {
      try {
        await stream.removeTrack(old);
        await old.stop();
      } catch (_) {}
    }
    state = state.copyWith(localStream: stream, streamRevision: state.streamRevision + 1);
  }

  /// Gives the microphone back to the call after interpreter mode. Returns the
  /// new track to put on every connection.
  Future<MediaStreamTrack?> restoreMicAfterInterpreter() async {
    final stream = state.localStream;
    if (stream == null) return null;
    try {
      final fresh = await navigator.mediaDevices.getUserMedia({
        'audio': _audioConstraints(enhanced: state.isVoiceEnhanced),
        'video': false,
      });
      final track = fresh.getAudioTracks().firstOrNull;
      if (track == null) return null;
      track.enabled = !state.isAudioMuted;
      await stream.addTrack(track);
      state = state.copyWith(localStream: stream, streamRevision: state.streamRevision + 1);
      return track;
    } catch (e) {
      debugPrint('[CallMedia] restore mic failed: $e');
      return null;
    }
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
      final targetId = defaultTargetPlatform == TargetPlatform.android
          ? androidAudioDeviceTypeName(route)
          : (deviceId ?? option.deviceId);
      switch (route) {
        case AudioRoute.speaker:
          await Helper.setSpeakerphoneOn(true);
          if (defaultTargetPlatform == TargetPlatform.android) {
            await Helper.selectAudioOutput('speaker');
          }
          break;
        case AudioRoute.earpiece:
          await Helper.setSpeakerphoneOn(false);
          if (defaultTargetPlatform == TargetPlatform.android) {
            await Helper.selectAudioOutput('earpiece');
          }
          break;
        case AudioRoute.bluetooth:
          if (defaultTargetPlatform == TargetPlatform.android) {
            await Helper.setSpeakerphoneOnButPreferBluetooth();
          } else {
            await Helper.setSpeakerphoneOn(false);
          }
          await Helper.selectAudioOutput(targetId);
          break;
        case AudioRoute.wired:
          await Helper.setSpeakerphoneOn(false);
          await Helper.selectAudioOutput(targetId);
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

  /// Starts device screen sharing while preserving the camera stream ("stay camera").
  /// Returns the screen video track so the WebRTC mesh can replace the outgoing track.
  Future<MediaStreamTrack?> startScreenShare() async {
    if (state.isScreenSharing) return state.screenStream?.getVideoTracks().firstOrNull;
    // Android 14+ only allows screen capture while a foreground service of
    // type mediaProjection runs; without it the plugin throws a
    // SecurityException on the main thread and the whole app stops. Same
    // order as Live Studio: consent, then the service, then capture.
    if (_isAndroid) {
      try {
        final granted = await Helper.requestCapturePermission();
        if (!granted) return null;
        await _screenCaptureService.invokeMethod<bool>('start');
        // The service reaches startForeground on its own main-thread turn.
        await Future<void>.delayed(const Duration(milliseconds: 300));
      } catch (e) {
        debugPrint('[CallMedia] screen capture service failed: $e');
        await _stopScreenCaptureService();
        return null;
      }
    }
    try {
      final stream = await navigator.mediaDevices.getDisplayMedia({
        'video': {
          'width': {'ideal': 1920},
          'height': {'ideal': 1080},
          'frameRate': {'ideal': 30, 'max': 30},
        },
        'audio': false,
      });
      final track = stream.getVideoTracks().firstOrNull;
      if (track == null) {
        await _stopScreenCaptureService();
        return null;
      }

      track.onEnded = () {
        debugPrint('[CallMedia] screen sharing ended by system');
        stopScreenShare();
      };

      state = state.copyWith(
        screenStream: stream,
        isScreenSharing: true,
        streamRevision: state.streamRevision + 1,
      );
      return track;
    } catch (e) {
      debugPrint('[CallMedia] startScreenShare failed: $e');
      await _stopScreenCaptureService();
      return null;
    }
  }

  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// MainActivity.kt → LiveScreenCaptureService (shared with Live Studio).
  static const MethodChannel _screenCaptureService = MethodChannel('com.oneova.app/live_screen_capture');

  Future<void> _stopScreenCaptureService() async {
    if (!_isAndroid) return;
    try {
      await _screenCaptureService.invokeMethod<bool>('stop');
    } catch (e) {
      debugPrint('[CallMedia] stop screen capture service: $e');
    }
  }

  /// Stops screen sharing and restores the local camera track ("stay camera").
  /// Returns the camera video track (or null if camera is off) to swap back into WebRTC.
  Future<MediaStreamTrack?> stopScreenShare() async {
    final stream = state.screenStream;
    if (stream != null) {
      for (final t in stream.getTracks()) {
        try {
          await t.stop();
        } catch (_) {}
      }
      try {
        await stream.dispose();
      } catch (_) {}
      await _stopScreenCaptureService();
    }

    state = state.copyWith(
      clearScreenStream: true,
      isScreenSharing: false,
      streamRevision: state.streamRevision + 1,
    );

    // Return the camera track to resume camera video if camera is on
    final camTracks = state.localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    return state.isVideoOn && camTracks.isNotEmpty ? camTracks.first : null;
  }

  Future<void> disposeMedia() async {
    navigator.mediaDevices.ondevicechange = null;
    final lease = _micLease;
    _micLease = null;
    unawaited(lease?.release());
    final stream = state.localStream;
    final screen = state.screenStream;
    final keepVoiceClean = state.isVoiceEnhanced;
    state = CallMediaState(isVoiceEnhanced: keepVoiceClean);
    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (_) {}
    if (screen != null) {
      for (final t in screen.getTracks()) {
        try {
          await t.stop();
        } catch (_) {}
      }
      try {
        await screen.dispose();
      } catch (_) {}
      await _stopScreenCaptureService();
    }
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
