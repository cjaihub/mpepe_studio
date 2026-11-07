import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:oneova_media_engine/oneova_media_engine.dart';

import '../models/studio_project.dart';
import 'studio_project_store.dart';

/// Cleaned copies of clip sound for the preview, so Clean voice is heard in
/// the editor exactly as the export applies it (same native processor).
/// One render per source and strength (rounded to 0.1), whole file, cached.
class StudioVoicePreview {
  StudioVoicePreview._();

  static final Map<String, String> _ready = {};
  static final Map<String, Future<String?>> _pending = {};

  /// Only one engine job runs at a time, so renders queue behind exports.
  static Future<void> _queue = Future.value();

  /// Resolves when no preview render is running (exports wait for it).
  static Future<void> idle() => _queue;

  static String _key(StudioClip c) => '${c.path}|${(c.voiceClean * 10).round()}';

  /// Cleaned audio for [c] if it is already rendered.
  static String? ready(StudioClip c) => c.voiceClean <= 0 ? null : _ready[_key(c)];

  /// Renders the cleaned sound for [c] in the background; [onReady] fires
  /// when it can be played.
  static Future<String?> prepare(StudioClip c, {VoidCallback? onReady}) {
    if (c.isImage || !c.hasAudio || c.voiceClean <= 0) return Future.value(null);
    final key = _key(c);
    final hit = _ready[key];
    if (hit != null) return Future.value(hit);
    return _pending[key] ??= () async {
      final done = _queue.then((_) async {
        final dir = await StudioProjectStore.dir('voice');
        final out = '${dir.path}/clean_${key.hashCode.toUnsigned(32).toRadixString(16)}.m4a';
        if (await File(out).exists()) return out;
        try {
          return await OneovaMediaEngine.export({
            'output': out,
            'audioOnly': true,
            'cleanVoice': true,
            'width': 0,
            'height': 0,
            'fps': 0,
            'bitrate': 0,
            'clips': [
              {'path': c.path, 'voiceClean': (c.voiceClean * 10).round() / 10},
            ],
            'audio': const [],
          });
        } catch (e) {
          debugPrint('[StudioVoicePreview] render failed: $e');
          return null;
        }
      });
      _queue = done.then((_) {}, onError: (_) {});
      final path = await done;
      _pending.remove(key);
      if (path != null) {
        _ready[key] = path;
        onReady?.call();
      }
      return path;
    }();
  }
}
