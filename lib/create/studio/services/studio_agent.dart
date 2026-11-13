import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../backend/social/services/story_service.dart';
import '../models/studio_project.dart';
import '../screens/studio_media_picker_screen.dart';
import 'package:oneova_media_engine/oneova_media_engine.dart';

import 'studio_captions.dart';
import 'studio_clip_tools.dart';
import 'studio_color.dart';
import 'studio_effects.dart';
import 'studio_faces.dart';
import 'studio_looks.dart';
import '../../../looks/filters/oneova_filter_library.dart';
import 'studio_media.dart';
import 'studio_project_store.dart';
import 'studio_publisher.dart';
import 'studio_renderer.dart';
import 'studio_stabilizer.dart';
import 'studio_text_templates.dart';
import '../widgets/studio_export_sheet.dart';

/// What an agent call did, in words for the assistant plus data for cards.
class StudioAgentResult {
  final bool ok;
  final String message;
  final StudioProject? project;

  /// Exported file, when the call exported.
  final String? outputPath;
  const StudioAgentResult(this.ok, this.message, {this.project, this.outputPath});
}

/// Headless Studio control for Ova and other agents. Every operation works on
/// saved projects without any screen open, so it also runs while Oneova is in
/// the background. Edits stay in the local draft until exported; posting is
/// left to callers that confirm with the user first.
class StudioAgent {
  final Ref ref;
  StudioAgent(this.ref);

  StudioProjectStore get _store => ref.read(studioProjectStoreProvider.notifier);

  Future<List<StudioProject>> projects() async => ref.read(studioProjectStoreProvider.future);

  /// [id] or 'latest' / empty for the newest project.
  Future<StudioProject?> project(String? id) async {
    final list = await projects();
    if (list.isEmpty) return null;
    if (id == null || id.isEmpty || id == 'latest') return list.first;
    return list.where((p) => p.id == id || p.id.startsWith(id) || p.title.toLowerCase() == id.toLowerCase()).firstOrNull;
  }

  String describe(StudioProject p) {
    final secs = (p.durationMs / 1000).round();
    final kind = p.isPhoto ? 'photo' : 'video';
    return '"${p.title}" (id ${p.id.substring(0, 8)}, $kind, ${p.clips.length} clip${p.clips.length == 1 ? '' : 's'}'
        '${p.isPhoto ? '' : ', ${secs}s'}, ${p.aspect.label}, ${p.texts.where((t) => t.isCaption).length} captions, '
        '${p.texts.where((t) => !t.isCaption).length} text layers, ${p.effects.length} effects, ${p.overlays.length} overlays)';
  }

  /// New project from the newest [count] gallery items.
  Future<StudioAgentResult> newFromGallery({bool photo = false, int count = 1, String format = 'short', String? title}) async {
    final perm = await PhotoManager.requestPermissionExtend();
    if (!perm.hasAccess) return const StudioAgentResult(false, 'Oneova needs gallery access to pick media. Open Studio once to allow it.');
    final paths = await PhotoManager.getAssetPathList(type: photo ? RequestType.image : RequestType.video, onlyAll: true);
    if (paths.isEmpty) return const StudioAgentResult(false, 'The gallery is empty.');
    final n = photo ? 1 : count.clamp(1, 10);
    final assets = await paths.first.getAssetListPaged(page: 0, size: n);
    final picks = <StudioPick>[];
    for (final a in assets) {
      final f = await a.originFile ?? await a.file;
      if (f == null) continue;
      final dur = a.type == AssetType.video ? a.videoDuration.inMilliseconds : 0;
      picks.add(StudioPick(path: f.path, isImage: a.type == AssetType.image, durationMs: dur, width: a.orientatedWidth, height: a.orientatedHeight, endMs: dur));
    }
    final imported = await StudioMedia.importPicks(picks, allowVideo: !photo);
    if (imported.clips.isEmpty) return StudioAgentResult(false, imported.message ?? 'Could not open the newest media.');
    final aspect = switch (format) {
      'short' => StudioAspect.portrait,
      'full' => StudioAspect.landscape,
      'square' => StudioAspect.square,
      _ => StudioAspect.original,
    };
    var p = StudioProject.create(isPhoto: photo, clips: imported.clips).copyWith(aspect: aspect, title: title);
    if (aspect == StudioAspect.portrait && title == null) p = p.copyWith(title: 'Short');
    p = await _store.save(p);
    return StudioAgentResult(true, 'Created ${describe(p)} from the newest ${photo ? 'photo' : '${imported.clips.length} video(s)'}.', project: p);
  }

  List<int> _clipIndexes(StudioProject p, int? clip) =>
      clip == null || clip < 1 || clip > p.clips.length ? List.generate(p.clips.length, (i) => i) : [clip - 1];

  StudioProject _mapClips(StudioProject p, int? clip, StudioClip Function(StudioClip) f) {
    final idx = _clipIndexes(p, clip).toSet();
    return p.copyWith(clips: [for (var i = 0; i < p.clips.length; i++) idx.contains(i) ? f(p.clips[i]) : p.clips[i]]);
  }

  /// One edit. [action] is one of [editActions]; the other arguments depend
  /// on it (see the Ova tool description).
  static const editActions = [
    'look', 'filter', 'adjust', 'retouch', 'beauty', 'speed', 'volume', 'mute', 'unmute', 'trim', 'aspect', 'fill', //
    'add_text', 'add_effect', 'clear_effects', 'clear_text', 'caption_style', 'rename', //
    'voice_clean', 'reverse', 'beat_sync', 'stabilize', 'add_overlay', 'clear_overlays',
  ];

  Future<StudioAgentResult> edit(
    String? projectId,
    String action, {
    String? name,
    double? value,
    int? clip,
    double? startS,
    double? endS,
    String? text,
  }) async {
    var p = await project(projectId);
    if (p == null) return const StudioAgentResult(false, 'There are no Studio projects yet. Create one first.');
    final total = p.durationMs;
    int ms(double? s, int d) => s == null ? d : (s * 1000).round().clamp(0, math.max(0, total));
    final v = value;
    String done;
    switch (action) {
      case 'look':
        final want = (name ?? '').toLowerCase();
        // A Studio preset, or any of the Oneova library filters by id or name.
        final lib = OneovaFilterLibrary.all.where((f) => f.id == name || f.name.toLowerCase() == want).firstOrNull;
        final def = StudioLooks.presets.where((l) => l.id == name || l.name.toLowerCase() == want).firstOrNull ??
            (lib == null ? null : StudioLooks.byId(lib.id));
        if (def == null) {
          final close = OneovaFilterLibrary.search(want).take(8).map((f) => f.name).join(', ');
          return StudioAgentResult(false, 'Unknown look "$name". Studio looks: ${StudioLooks.presets.map((l) => l.id).join(', ')}.${close.isEmpty ? '' : ' Close filters: $close.'}');
        }
        p = _mapClips(p, clip, (c) => c.copyWith(lookId: def.id, lookIntensity: (v ?? 1).clamp(0.0, 1.0)));
        done = 'Applied the ${def.name} look';
      case 'filter':
        final f = StudioColor.filters.where((f) => f.id == name || f.name.toLowerCase() == (name ?? '').toLowerCase()).firstOrNull;
        if (f == null) return StudioAgentResult(false, 'Unknown filter "$name". Filters: ${StudioColor.filters.map((f) => f.id).join(', ')}.');
        p = _mapClips(p, clip, (c) => c.copyWith(filterId: f.id, filterIntensity: (v ?? 1).clamp(0.0, 1.0)));
        done = 'Applied the ${f.name} filter';
      case 'adjust':
        if (name == null || !StudioAdjust.keys.contains(name)) {
          return StudioAgentResult(false, 'Adjust needs name = one of ${StudioAdjust.keys.join(', ')} and value -1..1.');
        }
        final val = (v ?? 0).clamp(StudioAdjust.positiveKeys.contains(name) ? 0.0 : -1.0, 1.0);
        p = _mapClips(p, clip, (c) => c.copyWith(adjust: c.adjust.withValue(name, val)));
        done = 'Set $name to ${val.toStringAsFixed(2)}';
      case 'retouch':
        if (name == null || !StudioRetouch.keys.contains(name)) {
          return StudioAgentResult(false, 'Retouch needs name = one of ${StudioRetouch.keys.join(', ')} and value 0..1 (warm and chin -1..1).');
        }
        final val = (v ?? 0.5).clamp(StudioRetouch.signedKeys.contains(name) ? -1.0 : 0.0, 1.0);
        p = _mapClips(p, clip, (c) => c.copyWith(retouch: c.retouch.withValue(name, val)));
        done = 'Set retouch $name to ${val.toStringAsFixed(2)}';
      case 'beauty':
        // One-tap natural beauty at [value] strength (default 0.5).
        final k = (v ?? 0.5).clamp(0.0, 1.0);
        final r = StudioRetouch(smooth: 0.6 * k, even: 0.4 * k, bright: 0.25 * k, eyes: 0.35 * k, teeth: 0.3 * k, slim: 0.15 * k, bigEyes: 0.1 * k);
        p = _mapClips(p, clip, (c) => c.copyWith(retouch: r));
        done = 'Applied natural beauty at ${(k * 100).round()}%';
      case 'speed':
        final s = (v ?? 1).clamp(0.25, 4.0);
        p = _mapClips(p, clip, (c) => c.isImage ? c : c.copyWith(speed: s));
        done = 'Set speed to ${s}x';
      case 'volume':
        final vol = (v ?? 1).clamp(0.0, 2.0);
        p = _mapClips(p, clip, (c) => c.copyWith(volume: vol, muted: vol == 0));
        done = 'Set volume to ${(vol * 100).round()}%';
      case 'mute':
      case 'unmute':
        p = _mapClips(p, clip, (c) => c.copyWith(muted: action == 'mute'));
        done = action == 'mute' ? 'Muted the original sound' : 'Turned the original sound on';
      case 'trim':
        final i = (clip ?? 1) - 1;
        if (i < 0 || i >= p.clips.length || p.clips[i].isImage) return const StudioAgentResult(false, 'Trim needs a video clip number (clip, from 1).');
        final c = p.clips[i];
        final s = ((startS ?? c.startMs / 1000) * 1000).round().clamp(0, c.sourceDurationMs - 300);
        final e = ((endS ?? c.endMs / 1000) * 1000).round().clamp(s + 300, c.sourceDurationMs);
        p = p.copyWith(clips: [...p.clips]..[i] = c.copyWith(startMs: s, endMs: e));
        done = 'Trimmed clip ${i + 1} to ${(s / 1000).toStringAsFixed(1)}–${(e / 1000).toStringAsFixed(1)}s of the source';
      case 'aspect':
        final a = switch (name) {
          'short' || '9:16' => StudioAspect.portrait,
          'full' || '16:9' => StudioAspect.landscape,
          'square' || '1:1' => StudioAspect.square,
          '4:5' => StudioAspect.feed,
          '3:4' => StudioAspect.classic,
          _ => StudioAspect.original,
        };
        p = p.copyWith(aspect: a);
        done = 'Set the canvas to ${a.label}';
      case 'fill':
        p = p.copyWith(clips: [for (final c in p.clips) c.copyWith(fill: (v ?? 1) > 0)]);
        done = (v ?? 1) > 0 ? 'Clips now fill the frame' : 'Clips now fit the frame';
      case 'add_text':
        if ((text ?? '').trim().isEmpty) return const StudioAgentResult(false, 'add_text needs text.');
        final tpl = _template(name);
        final s = p.isPhoto ? 0 : ms(startS, 0);
        final e = p.isPhoto ? 1 : ms(endS, math.min(total, s + 3000));
        var t = StudioText.create(text: text!.trim(), startMs: s, endMs: math.max(e, s + 300));
        if (tpl != null) t = tpl.applyTo(t);
        if (v != null) t = t.copyWith(y: v.clamp(-0.9, 0.9));
        p = p.copyWith(texts: [...p.texts, t]);
        done = 'Added text "${t.text}"${tpl == null ? '' : ' with the ${tpl.name} template'}';
      case 'caption_style':
        final tpl = _template(name, captions: true);
        if (tpl == null) return StudioAgentResult(false, 'Unknown caption style. Styles: ${StudioTextTemplates.inCategory('Captions').map((t) => t.id).join(', ')}.');
        p = p.copyWith(texts: [for (final t in p.texts) t.isCaption ? tpl.applyTo(t) : t]);
        done = 'Styled the captions with ${tpl.name}';
      case 'add_effect':
        final def = StudioEffects.all.where((e) => e.id == name || e.name.toLowerCase() == (name ?? '').toLowerCase()).firstOrNull;
        if (def == null) return StudioAgentResult(false, 'Unknown effect "$name". Effects: ${StudioEffects.all.map((e) => e.id).join(', ')}.');
        final s = p.isPhoto ? 0 : ms(startS, 0);
        final e = p.isPhoto ? 1 << 30 : ms(endS, math.min(total, s + 3000));
        if (!p.isPhoto && e - s < 200) return const StudioAgentResult(false, 'That effect range is too short.');
        p = p.copyWith(effects: [...p.effects, StudioEffect.create(effectId: def.id, startMs: s, endMs: e, amount: (v ?? def.amount).clamp(0.0, 1.0))]);
        done = 'Added the ${def.name} effect';
      case 'clear_effects':
        p = p.copyWith(effects: const []);
        done = 'Removed all effects';
      case 'clear_text':
        p = p.copyWith(texts: [for (final t in p.texts) if (t.isCaption) t]);
        done = 'Removed the text layers (captions kept)';
      case 'voice_clean':
        final k = (v ?? 0.6).clamp(0.0, 1.0);
        p = _mapClips(p, clip, (c) => c.isImage ? c : c.copyWith(voiceClean: k));
        done = k == 0 ? 'Turned voice clean-up off' : 'Voice clean-up at ${(k * 100).round()}%';
      case 'add_overlay':
        // Newest gallery photo (name = photo) or video as picture-in-picture.
        final photoLayer = name == 'photo' || p.isPhoto;
        final perm = await PhotoManager.requestPermissionExtend();
        if (!perm.hasAccess) return const StudioAgentResult(false, 'Oneova needs gallery access to add an overlay.');
        final paths = await PhotoManager.getAssetPathList(type: photoLayer ? RequestType.image : RequestType.video, onlyAll: true);
        final assets = paths.isEmpty ? const <AssetEntity>[] : await paths.first.getAssetListPaged(page: 0, size: 1);
        final file = assets.isEmpty ? null : (await assets.first.originFile ?? await assets.first.file);
        if (file == null) return const StudioAgentResult(false, 'No media found in the gallery for the overlay.');
        final imported = await StudioMedia.importPicks([
          StudioPick(path: file.path, isImage: photoLayer, durationMs: assets.first.videoDuration.inMilliseconds, width: 0, height: 0, endMs: 0),
        ], allowVideo: !p.isPhoto);
        if (imported.clips.isEmpty) return StudioAgentResult(false, imported.message ?? 'Could not open that media.');
        final at = p.isPhoto ? 0 : ms(startS, 0);
        var o = StudioOverlay.fromClip(imported.clips.first, offsetMs: at, maxMs: p.isPhoto ? null : math.max(500, total - at));
        if (v != null) o = o.copyWith(scale: v.clamp(0.08, 1.5));
        p = p.copyWith(overlays: [...p.overlays, o]);
        done = 'Added the newest ${photoLayer ? 'photo' : 'video'} as an overlay';
      case 'clear_overlays':
        p = p.copyWith(overlays: const []);
        done = 'Removed all overlays';
      case 'stabilize':
        final k = (v ?? 0.5).clamp(0.0, 1.0);
        for (final i in _clipIndexes(p, clip)) {
          if (p.clips[i].isImage || k == 0) continue;
          try {
            await StudioStabilizer.analyse(p.clips[i]);
          } on MediaEngineException catch (e) {
            return StudioAgentResult(false, e.message);
          }
        }
        p = _mapClips(p, clip, (c) => c.isImage ? c : c.copyWith(stabilize: k));
        done = k == 0 ? 'Turned stabilize off' : 'Stabilized at ${(k * 100).round()}%';
      case 'reverse':
        final i = (clip ?? 1) - 1;
        if (i < 0 || i >= p.clips.length || p.clips[i].isImage) return const StudioAgentResult(false, 'Reverse needs a video clip number (clip, from 1).');
        try {
          final r = await StudioClipTools.reverse(p.clips[i]);
          p = p.copyWith(clips: [...p.clips]..[i] = r);
        } on MediaEngineException catch (e) {
          return StudioAgentResult(false, e.message);
        }
        done = 'Reversed clip ${i + 1}';
      case 'beat_sync':
        if (p.audios.isEmpty) return const StudioAgentResult(false, 'Add music to the project first, then sync to its beat.');
        var a = p.audios.first;
        if (a.beatsMs.isEmpty) {
          try {
            a = await StudioClipTools.detectBeats(a);
          } on MediaEngineException catch (e) {
            return StudioAgentResult(false, e.message);
          }
          p = p.copyWith(audios: [a, ...p.audios.skip(1)]);
        }
        if (a.timelineBeats.length < 2) return const StudioAgentResult(false, 'No clear beat was found in that music.');
        p = StudioClipTools.cutToBeats(p, a);
        done = 'Cut the clips to the beat${a.bpm > 0 ? ' (${a.bpm.round()} BPM)' : ''}';
      case 'rename':
        if ((text ?? name ?? '').trim().isEmpty) return const StudioAgentResult(false, 'rename needs text.');
        p = p.copyWith(title: (text ?? name)!.trim());
        done = 'Renamed the project';
      default:
        return StudioAgentResult(false, 'Unknown action "$action". Actions: ${editActions.join(', ')}.');
    }
    p = await _store.save(p);
    return StudioAgentResult(true, '$done. Project: ${describe(p)}.', project: p);
  }

  StudioTextTemplate? _template(String? q, {bool captions = false}) {
    if (q == null || q.isEmpty) return null;
    final pool = captions ? StudioTextTemplates.inCategory('Captions') : StudioTextTemplates.all;
    return pool.where((t) => t.id == q).firstOrNull ??
        pool.where((t) => t.name.toLowerCase() == q.toLowerCase()).firstOrNull ??
        pool.where((t) => t.matches(q)).firstOrNull;
  }

  Future<StudioAgentResult> autoCaptions(String? projectId, {String language = 'auto', String style = 'ca_karaoke'}) async {
    final p = await project(projectId);
    if (p == null) return const StudioAgentResult(false, 'There are no Studio projects yet.');
    if (p.isPhoto) return const StudioAgentResult(false, 'Captions are for video projects.');
    try {
      final r = await StudioCaptionService.autoCaptions(p, language: language, templateId: _template(style, captions: true)?.id ?? 'ca_karaoke');
      final notice = StudioCaptionService.supportNotice(r.languageName, r.support, captions: true);
      if (r.support == StudioLanguageSupport.unsupported) return StudioAgentResult(false, notice!);
      if (r.captions.isEmpty) return const StudioAgentResult(false, 'No speech was found in the original sound.');
      final saved = await _store.save(p.copyWith(texts: [...p.texts.where((t) => !t.isCaption), ...r.captions]));
      return StudioAgentResult(true, 'Added ${r.captions.length} captions in ${r.languageName}.${notice == null ? '' : ' $notice'}', project: saved);
    } on StudioAiException catch (e) {
      return StudioAgentResult(false, e.message);
    }
  }

  Future<StudioAgentResult> translateCaptions(String? projectId, String language) async {
    final p = await project(projectId);
    if (p == null) return const StudioAgentResult(false, 'There are no Studio projects yet.');
    final caps = p.texts.where((t) => t.isCaption).toList();
    if (caps.isEmpty) return const StudioAgentResult(false, 'This project has no captions to translate.');
    final lang = StudioCaptionService.find(language) ?? StudioLanguage.custom(language);
    try {
      final (out, support) = await StudioCaptionService.translate([for (final t in caps) t.text], lang.code);
      final notice = StudioCaptionService.supportNotice(lang.name, support, captions: false);
      if (support == StudioLanguageSupport.unsupported) return StudioAgentResult(false, notice!);
      final byId = {for (var i = 0; i < caps.length; i++) caps[i].id: out[i]};
      final saved = await _store.save(p.copyWith(texts: [
        for (final t in p.texts) byId.containsKey(t.id) ? t.copyWith(text: byId[t.id], lang: lang.code, words: const []) : t,
      ]));
      return StudioAgentResult(true, 'Translated ${caps.length} captions into ${lang.name}.${notice == null ? '' : ' $notice'}', project: saved);
    } on StudioAiException catch (e) {
      return StudioAgentResult(false, e.message);
    }
  }

  /// Renders the project (all edits baked in) and optionally saves it to the gallery.
  Future<StudioAgentResult> export(String? projectId, {int shortSide = 1080, int fps = 30, bool saveToGallery = true}) async {
    final p = await project(projectId);
    if (p == null) return const StudioAgentResult(false, 'There are no Studio projects yet.');
    try {
      final String path;
      if (p.isPhoto) {
        path = await StudioRenderer.exportPhoto(p, maxLongSide: shortSide >= 2160 ? 4096 : 2160);
      } else {
        final short = math.min(shortSide, math.max(480, p.maxSourceShortSide));
        final rate = math.min(fps, math.max(24, p.maxSourceFps.round()));
        path = await StudioRenderer.exportVideo(p, StudioVideoSettings(shortSide: short, fps: rate, bitrate: studioRecommendedBitrate(short, rate)));
      }
      var where = 'in Studio exports';
      if (saveToGallery) {
        final ok = (await PhotoManager.requestPermissionExtend()).hasAccess;
        if (ok) {
          final name = 'Oneova_${DateTime.now().millisecondsSinceEpoch}';
          p.isPhoto
              ? await PhotoManager.editor.saveImageWithPath(path, title: '$name.jpg')
              : await PhotoManager.editor.saveVideo(File(path), title: '$name.mp4');
          where = 'in the gallery';
        }
      }
      return StudioAgentResult(true, 'Exported "${p.title}" and saved it $where.', project: p, outputPath: path);
    } catch (e) {
      debugPrint('[StudioAgent] export failed: $e');
      return StudioAgentResult(false, 'The export stopped: $e');
    }
  }

  /// Exports and posts the project as a 24h story. Callers confirm with the user first.
  Future<StudioAgentResult> postStory(String? projectId) async {
    final ex = await export(projectId, saveToGallery: false);
    if (!ex.ok || ex.outputPath == null) return ex;
    try {
      await StudioPublisher.publishStory(
        stories: ref.read(storyServiceProvider),
        path: ex.outputPath!,
        isVideo: !(ex.project?.isPhoto ?? false),
        onProgress: (_) {},
      );
      return StudioAgentResult(true, 'Posted "${ex.project?.title}" to your story.', project: ex.project, outputPath: ex.outputPath);
    } catch (e) {
      return StudioAgentResult(false, 'Could not post the story: $e');
    }
  }

  /// Finds faces in a project's clips ahead of an export (retouch tools).
  Future<int> trackFaces(StudioProject p) async {
    var n = 0;
    for (final c in p.clips) {
      if ((await StudioFaceTracker.track(c)).hasFaces) n++;
    }
    return n;
  }
}

final studioAgentProvider = Provider<StudioAgent>((ref) => StudioAgent(ref));
