import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:video_player/video_player.dart';

import '../models/studio_project.dart';

/// Plays a [StudioProject] timeline in the editor: walks clip to clip (videos
/// through one controller per source file, photos on a wall clock), honours
/// trims, speed, volume and mute, and keeps the extra audio tracks in sync.
class StudioPlayback extends ChangeNotifier {
  StudioProject _project;
  final Map<String, VideoPlayerController> _videos = {};
  final Map<String, Future<VideoPlayerController?>> _pending = {};
  final Map<String, Player> _audio = {};
  final Set<String> _audioPlaying = {};
  Timer? _ticker;
  int _activeIndex = -1;
  DateTime _clockBase = DateTime.now();
  bool _disposed = false;
  int _seekToken = 0;

  int posMs = 0;
  bool playing = false;

  StudioPlayback(this._project);

  StudioProject get project => _project;

  int get durationMs => _project.durationMs;

  /// Clip currently shown in the preview.
  int get activeIndex => _project.clips.isEmpty ? -1 : _project.clipIndexAt(posMs);

  VideoPlayerController? controllerFor(StudioClip clip) => clip.isImage ? null : _videos[clip.path];

  /// Swap in an edited project; keeps the playhead where it is.
  void update(StudioProject p) {
    _project = p;
    final paths = p.clips.where((c) => !c.isImage).map((c) => c.path).toSet();
    for (final path in _videos.keys.toList()) {
      if (!paths.contains(path)) _videos.remove(path)?.dispose();
    }
    final audioIds = p.audios.map((a) => a.id).toSet();
    for (final id in _audio.keys.toList()) {
      if (!audioIds.contains(id)) {
        _audio.remove(id)?.dispose();
        _audioPlaying.remove(id);
      }
    }
    if (posMs > durationMs) posMs = durationMs;
    if (playing) {
      _startAt(posMs);
    } else {
      seek(posMs);
    }
  }

  Future<VideoPlayerController?> _ensure(String path) {
    final existing = _videos[path];
    if (existing != null) return Future.value(existing);
    return _pending[path] ??= () async {
      try {
        final c = VideoPlayerController.file(File(path));
        await c.initialize();
        if (_disposed) {
          await c.dispose();
          return null;
        }
        _videos[path] = c;
        return c;
      } catch (e) {
        debugPrint('[StudioPlayback] cannot open $path: $e');
        return null;
      } finally {
        _pending.remove(path);
      }
    }();
  }

  /// Opens every clip's source up front so scrubbing is instant.
  Future<void> warmUp() async {
    for (final c in _project.clips) {
      if (!c.isImage) await _ensure(c.path);
    }
    if (!_disposed) seek(posMs);
  }

  Future<void> seek(int ms) async {
    posMs = ms.clamp(0, durationMs);
    final token = ++_seekToken;
    notifyListeners();
    if (playing) {
      _startAt(posMs);
      return;
    }
    final idx = activeIndex;
    if (idx < 0) return;
    final clip = _project.clips[idx];
    if (clip.isImage) return;
    final c = await _ensure(clip.path);
    if (c == null || token != _seekToken) return;
    await c.seekTo(Duration(milliseconds: clip.sourceMsAt(posMs - _project.clipStartMs(idx))));
    if (!_disposed) notifyListeners();
  }

  Future<void> toggle() => playing ? pause() : play();

  Future<void> play() async {
    if (_project.clips.isEmpty) return;
    if (posMs >= durationMs - 40) posMs = 0;
    playing = true;
    notifyListeners();
    await _startAt(posMs);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) => _tick());
  }

  Future<void> pause() async {
    playing = false;
    _ticker?.cancel();
    for (final c in _videos.values) {
      if (c.value.isPlaying) await c.pause();
    }
    for (final id in _audioPlaying.toList()) {
      await _audio[id]?.pause();
    }
    _audioPlaying.clear();
    if (!_disposed) notifyListeners();
  }

  Future<void> _startAt(int ms) async {
    final idx = _project.clipIndexAt(ms);
    if (idx < 0) return;
    for (final entry in _videos.entries) {
      if (entry.value.value.isPlaying) await entry.value.pause();
    }
    _activeIndex = idx;
    final clip = _project.clips[idx];
    final local = ms - _project.clipStartMs(idx);
    _clockBase = DateTime.now().subtract(Duration(milliseconds: local));
    if (!clip.isImage) {
      final c = await _ensure(clip.path);
      if (c == null || !playing || _activeIndex != idx) return;
      await c.seekTo(Duration(milliseconds: clip.sourceMsAt(local)));
      await c.setPlaybackSpeed(clip.speed);
      await c.setVolume(clip.muted ? 0 : clip.volume.clamp(0.0, 1.0));
      if (playing && _activeIndex == idx) await c.play();
    }
    for (final id in _audioPlaying.toList()) {
      await _audio[id]?.pause();
    }
    _audioPlaying.clear();
  }

  void _tick() {
    if (!playing || _disposed) return;
    final idx = _activeIndex;
    if (idx < 0 || idx >= _project.clips.length) return;
    final clip = _project.clips[idx];
    final clipStart = _project.clipStartMs(idx);
    var reachedEnd = false;
    if (clip.isImage) {
      final local = DateTime.now().difference(_clockBase).inMilliseconds;
      posMs = clipStart + local.clamp(0, clip.outDurationMs);
      reachedEnd = local >= clip.outDurationMs;
    } else {
      final c = _videos[clip.path];
      if (c == null) return;
      final src = c.value.position.inMilliseconds;
      posMs = clipStart + ((src - clip.startMs) / clip.speed).round().clamp(0, clip.outDurationMs);
      reachedEnd = src >= clip.endMs - 35 || (c.value.isCompleted && !c.value.isPlaying);
    }
    _syncAudio();
    if (reachedEnd) {
      if (idx + 1 >= _project.clips.length) {
        posMs = durationMs;
        pause();
        return;
      }
      _startAt(_project.clipStartMs(idx + 1));
    }
    notifyListeners();
  }

  void _syncAudio() {
    for (final a in _project.audios) {
      final inRange = posMs >= a.offsetMs && posMs < a.offsetMs + a.durationMs;
      final isOn = _audioPlaying.contains(a.id);
      if (inRange && !isOn) {
        _audioPlaying.add(a.id);
        final player = _audio[a.id] ??= Player();
        () async {
          await player.open(Media(a.path), play: false);
          await player.seek(Duration(milliseconds: a.startMs + posMs - a.offsetMs));
          await player.setVolume((a.volume * 100).clamp(0, 100).toDouble());
          if (playing && _audioPlaying.contains(a.id)) await player.play();
        }();
      } else if (!inRange && isOn) {
        _audioPlaying.remove(a.id);
        _audio[a.id]?.pause();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    for (final c in _videos.values) {
      c.dispose();
    }
    for (final p in _audio.values) {
      p.dispose();
    }
    _videos.clear();
    _audio.clear();
    super.dispose();
  }
}
