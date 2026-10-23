// LIVE STUDIO v2 — local camera / mic preview for the device check
// (workstream #4). [StudioDevicePreview] is the seam; the LiveKit
// implementation opens real tracks (released before going on stage so the
// room can open the camera itself).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

enum StudioDevicePermission { granted, denied, permanentlyDenied }

class StudioDevicePermissions {
  const StudioDevicePermissions({required this.camera, required this.microphone});
  final StudioDevicePermission camera;
  final StudioDevicePermission microphone;

  bool get cameraOk => camera == StudioDevicePermission.granted;
  bool get micOk => microphone == StudioDevicePermission.granted;
}

abstract class StudioDevicePreview {
  /// Asks the OS for camera + microphone access.
  Future<StudioDevicePermissions> requestPermissions();

  Future<void> setCamera(bool on);
  Future<void> setMic(bool on);

  /// Live camera preview (mirrored), or null when the camera is off.
  Widget? buildVideo();

  /// Mic input level, 0–1.
  Stream<double> get micLevel;

  /// Opens the app's OS settings page (after a permanent denial).
  Future<void> openSettings();

  /// Stops and releases every local track.
  Future<void> dispose();
}

/// Creates a fresh preview per device check (override in tests).
final studioDevicePreviewFactoryProvider =
    Provider<StudioDevicePreview Function()>((ref) => LiveKitDevicePreview.new);

class LiveKitDevicePreview implements StudioDevicePreview {
  LocalVideoTrack? _video;
  LocalAudioTrack? _audio;
  AudioVisualizer? _viz;
  EventsListener<AudioVisualizerEvent>? _vizListener;
  final StreamController<double> _level = StreamController<double>.broadcast();
  bool _disposed = false;

  static StudioDevicePermission _map(PermissionStatus s) {
    if (s.isGranted || s.isLimited) return StudioDevicePermission.granted;
    if (s.isPermanentlyDenied || s.isRestricted) return StudioDevicePermission.permanentlyDenied;
    return StudioDevicePermission.denied;
  }

  @override
  Future<StudioDevicePermissions> requestPermissions() async {
    final r = await [Permission.camera, Permission.microphone].request();
    return StudioDevicePermissions(
      camera: _map(r[Permission.camera] ?? PermissionStatus.denied),
      microphone: _map(r[Permission.microphone] ?? PermissionStatus.denied),
    );
  }

  @override
  Future<void> setCamera(bool on) async {
    if (_disposed) return;
    if (on) {
      _video ??= await LocalVideoTrack.createCameraTrack(const CameraCaptureOptions(cameraPosition: CameraPosition.front));
    } else {
      final v = _video;
      _video = null;
      if (v != null) await _release(v);
    }
  }

  @override
  Future<void> setMic(bool on) async {
    if (_disposed) return;
    if (on) {
      if (_audio != null) return;
      final a = await LocalAudioTrack.create();
      _audio = a;
      final viz = createVisualizer(a, options: const AudioVisualizerOptions(barCount: 7, centeredBands: false));
      _viz = viz;
      _vizListener = viz.createListener()
        ..on<AudioVisualizerEvent>((e) {
          final bands = e.event.whereType<num>().toList();
          if (bands.isEmpty || _level.isClosed) return;
          final peak = bands.fold<double>(0, (m, v) => v > m ? v.toDouble() : m);
          _level.add(peak.clamp(0, 1).toDouble());
        });
      await viz.start();
    } else {
      await _stopMic();
    }
  }

  Future<void> _stopMic() async {
    final viz = _viz, a = _audio;
    _viz = null;
    _audio = null;
    await _vizListener?.dispose();
    _vizListener = null;
    if (viz != null) {
      await viz.stop();
      await viz.dispose();
    }
    if (a != null) await _release(a);
    if (!_level.isClosed) _level.add(0);
  }

  static Future<void> _release(LocalTrack t) async {
    try {
      await t.stop();
      await t.dispose();
    } catch (_) {}
  }

  @override
  Widget? buildVideo() {
    final v = _video;
    return v == null
        ? null
        : VideoTrackRenderer(v, fit: VideoViewFit.cover, mirrorMode: VideoViewMirrorMode.mirror);
  }

  @override
  Stream<double> get micLevel => _level.stream;

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    final v = _video;
    _video = null;
    if (v != null) await _release(v);
    await _stopMic();
    _disposed = true;
    await _level.close();
  }
}
