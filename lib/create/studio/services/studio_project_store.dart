import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova_media_engine/oneova_media_engine.dart';
import 'package:path_provider/path_provider.dart';

import '../models/studio_project.dart';

/// Saved Studio projects, newest first. Each project is one JSON file under
/// `<app documents>/studio/projects`; the media stays where it was picked
/// (camera recordings are copied in so the OS can't clear them).
class StudioProjectStore extends AsyncNotifier<List<StudioProject>> {
  static Future<Directory> root() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/studio');
  }

  static Future<Directory> dir(String name) async {
    final d = Directory('${(await root()).path}/$name');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  @override
  Future<List<StudioProject>> build() async {
    final d = await dir('projects');
    final out = <StudioProject>[];
    await for (final f in d.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        out.add(StudioProject.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('[StudioProjectStore] skipping unreadable ${f.path}: $e');
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<StudioProject> save(StudioProject project) async {
    var p = project.copyWith(updatedAt: DateTime.now());
    if (p.clips.isNotEmpty && (p.thumbnailPath == null || !File(p.thumbnailPath!).existsSync())) {
      p = p.copyWith(thumbnailPath: await _thumbnail(p));
    }
    final f = File('${(await dir('projects')).path}/${p.id}.json');
    await f.writeAsString(jsonEncode(p.toJson()), flush: true);
    final list = [...?state.value]..removeWhere((e) => e.id == p.id);
    state = AsyncData([p, ...list]);
    return p;
  }

  Future<void> delete(String id) async {
    final f = File('${(await dir('projects')).path}/$id.json');
    if (await f.exists()) await f.delete();
    final thumb = File('${(await dir('thumbs')).path}/$id.jpg');
    if (await thumb.exists()) await thumb.delete();
    state = AsyncData([...?state.value]..removeWhere((e) => e.id == id));
  }

  Future<StudioProject> duplicate(StudioProject p) async {
    final copy = StudioProject.fromJson({
      ...p.toJson(),
      'id': '${p.id.substring(0, 8)}-${DateTime.now().millisecondsSinceEpoch}',
      'title': '${p.title} (copy)',
      'thumbnailPath': null,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    return save(copy);
  }

  Future<String?> _thumbnail(StudioProject p) async {
    final first = p.clips.first;
    if (first.isImage) return first.path;
    try {
      final out = '${(await dir('thumbs')).path}/${p.id}.jpg';
      return await OneovaMediaEngine.frame(first.path, ms: first.startMs, out: out, maxSide: 480);
    } catch (e) {
      debugPrint('[StudioProjectStore] thumbnail failed: $e');
      return null;
    }
  }

  /// Copies a temporary file (camera recording, cache) into Studio storage.
  static Future<String> keepFile(String path) async {
    final media = await dir('media');
    if (path.startsWith(media.path)) return path;
    final name = path.split(Platform.pathSeparator).last;
    final out = File('${media.path}/${DateTime.now().millisecondsSinceEpoch}_$name');
    await File(path).copy(out.path);
    return out.path;
  }
}

final studioProjectStoreProvider =
    AsyncNotifierProvider<StudioProjectStore, List<StudioProject>>(StudioProjectStore.new);
