import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:video_player/video_player.dart';

import '../models/studio_project.dart';
import 'studio_voice_preview.dart';

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

  /// One player per picture-in-picture video layer.
  final Map<String, VideoPlayerController> _overlays = {};
  final Set<String> _overlayPending = {};

  /// Player of overlay [o], once it has opened.
  VideoPlayerController? overlayController(StudioOverlay o) => o.isImage ? null : _overlays[o.id];

  /// Plays a clip's cleaned sound (Clean voice) in place of its own.
  Player? _voice;
  String? _voicePath;

  StudioPlayback(this._project);

  StudioProject get project => _project;

  int get durationMs => _project.durationMs;

  /// Clip currently shown in the preview.
  int get activeIndex => _project.clips.isEmpty ? -1 : _project.clipIndexAt(posMs);

  VideoPlayerController? controllerFor(StudioClip clip) => clip.isImage ? null : _videos[clip.path];

  /// Swap in an edited project; keeps the playhead where it is.
  void update(StudioProject p) {
    _project = p;
    final ovIds = p.overlays.map((o) => o.id).toSet();
    for (final id in _overlays.keys.toList()) {
      if (!ovIds.contains(id)) _overlays.remove(id)?.dispose();
    }
    for (final c in p.clips) {
      if (c.voiceClean > 0 && StudioVoicePreview.ready(c) == null) {
        StudioVoicePreview.prepare(c, onReady: () {
          if (!_disposed && playing) _startAt(posMs);
        });
      }
    }
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
    _syncOverlays(force: true);
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
    await _voice?.pause();
    for (final o in _overlays.values) {
      if (o.value.isPlaying) await o.pause();
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
      final cleaned = clip.muted ? null : StudioVoicePreview.ready(clip);
      await c.setVolume(clip.muted || cleaned != null ? 0 : clip.volume.clamp(0.0, 1.0));
      await _startVoice(cleaned, clip, local);
      if (playing && _activeIndex == idx) await c.play();
    } else {
      await _voice?.pause();
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
      _syncVoice(clip, src);
    }
    _syncAudio();
    _syncOverlays();
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

  Future<void> _startVoice(String? path, StudioClip clip, int local) async {
    if (path == null) {
      await _voice?.pause();
      return;
    }
    final v = _voice ??= Player();
    if (_voicePath != path) {
      await v.open(Media(path), play: false);
      _voicePath = path;
    }
    await v.seek(Duration(milliseconds: clip.sourceMsAt(local)));
    await v.setRate(clip.speed);
    await v.setVolume((clip.volume * 100).clamp(0, 100).toDouble());
    if (playing) await v.play();
  }

  /// Keeps the cleaned sound within ~120 ms of the picture.
  void _syncVoice(StudioClip clip, int srcMs) {
    final v = _voice;
    if (v == null || _voicePath == null || !v.state.playing) return;
    final drift = (v.state.position.inMilliseconds - srcMs).abs();
    if (drift > 120) v.seek(Duration(milliseconds: srcMs));
  }

  /// Opens, plays, pauses and re-syncs overlay players for the playhead.
  void _syncOverlays({bool force = false}) {
    for (final o in _project.overlays) {
      if (o.isImage) continue;
      final inRange = posMs >= o.offsetMs && posMs < o.endOnTimeline;
      final c = _overlays[o.id];
      if (c == null) {
        if (inRange && _overlayPending.add(o.id)) {
          () async {
            try {
              final v = VideoPlayerController.file(File(o.path));
              await v.initialize();
              if (_disposed || !_project.overlays.any((x) => x.id == o.id)) {
                await v.dispose();
                return;
              }
              _overlays[o.id] = v;
              _syncOverlays(force: true);
              notifyListeners();
            } catch (e) {
              debugPrint('[StudioPlayback] cannot open overlay ${o.path}: $e');
            } finally {
              _overlayPending.remove(o.id);
            }
          }();
        }
        continue;
      }
      if (!inRange) {
        if (c.value.isPlaying) c.pause();
        continue;
      }
      final target = o.startMs + posMs - o.offsetMs;
      final drift = (c.value.position.inMilliseconds - target).abs();
      c.setVolume(o.muted ? 0 : o.volume.clamp(0.0, 1.0));
      if (playing) {
        if (!c.value.isPlaying) {
          c.seekTo(Duration(milliseconds: target));
          c.play();
        } else if (drift > 150) {
          c.seekTo(Duration(milliseconds: target));
        }
      } else if (force || drift > 40) {
        if (c.value.isPlaying) c.pause();
        c.seekTo(Duration(milliseconds: target));
      }
    }
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
    _voice?.dispose();
    for (final o in _overlays.values) {
      o.dispose();
    }
    _overlays.clear();
    _videos.clear();
    _audio.clear();
    super.dispose();
  }
}
