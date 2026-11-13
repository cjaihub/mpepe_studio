import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:oneova_media_engine/oneova_media_engine.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../backend/social/services/story_service.dart';
import '../../../shared/theme/app_theme.dart';
import '../../media_preview_screen.dart';
import '../models/studio_project.dart';
import '../services/studio_captions.dart';
import '../services/studio_clip_tools.dart';
import '../services/studio_effects.dart';
import '../services/studio_faces.dart';
import '../services/studio_media.dart';
import '../services/studio_cutout.dart';
import '../services/studio_playback.dart';
import '../services/studio_project_store.dart';
import '../services/studio_publisher.dart';
import '../../widgets/phone_music_sheet.dart';
import '../services/studio_renderer.dart';
import '../services/studio_stabilizer.dart';
import '../services/studio_text_painter.dart';
import '../widgets/studio_export_sheet.dart';
import '../services/studio_export_extras.dart';
import '../widgets/studio_panels.dart';
import '../widgets/studio_preview.dart';
import '../widgets/studio_pro_panels.dart';
import '../widgets/studio_progress_dialog.dart';
import '../widgets/studio_text_editor_sheet.dart';
import '../widgets/studio_timeline.dart';
import '../widgets/studio_ui.dart';
import 'studio_media_picker_screen.dart';

class StudioEditorArgs {
  final StudioProject project;
  final StudioTarget target;

  /// Panel to open first ('captions', 'autocaptions', 'filters', 'looks',
  /// 'effects', 'speed', 'text', 'audio', 'crop').
  final String? initialTool;

  const StudioEditorArgs({required this.project, this.target = StudioTarget.post, this.initialTool});
}

enum _Panel { none, clip, audio, text, captions, filters, looks, effects, retouch, voice, stabilize, overlay, adjust, aspect, speed, volume, transform, crop, duration, audioVolume }

/// Studio editor: preview, timeline and the tools that change the export.
class StudioEditorScreen extends ConsumerStatefulWidget {
  final StudioEditorArgs args;
  const StudioEditorScreen({super.key, required this.args});

  @override
  ConsumerState<StudioEditorScreen> createState() => _StudioEditorScreenState();
}

class _StudioEditorScreenState extends ConsumerState<StudioEditorScreen> {
  late StudioProject _p = widget.args.project;
  late final StudioPlayback _pb = StudioPlayback(_p);
  final List<StudioProject> _undo = [];
  final List<StudioProject> _redo = [];
  StudioProject? _liveBase;
  String? _clipId;
  String? _textId;
  String? _audioId;
  String? _effectId;
  String? _overlayId;
  _Panel _panel = _Panel.none;
  bool _fullscreen = false;
  Timer? _autosave;

  bool get _isPhoto => _p.isPhoto;

  @override
  void initState() {
    super.initState();
    _watchLifecycle();
    _pb.warmUp();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _save();
      switch (widget.args.initialTool) {
        case 'captions':
          setState(() => _panel = _Panel.captions);
        case 'autocaptions':
          setState(() => _panel = _Panel.captions);
          _autoCaptions();
        case 'filters':
          _openClipPanel(_Panel.filters);
        case 'looks':
          _openClipPanel(_Panel.looks);
        case 'retouch':
          _openRetouch();
        case 'effects':
          setState(() => _panel = _Panel.effects);
        case 'speed':
          _openClipPanel(_Panel.speed);
        case 'text':
          setState(() => _panel = _Panel.text);
        case 'audio':
          setState(() => _panel = _Panel.audio);
        case 'crop':
          _openClipPanel(_Panel.crop);
      }
    });
  }

  @override
  void dispose() {
    // Leaving with an edit still waiting: save it now, not never.
    if (_autosave?.isActive ?? false) {
      _autosave!.cancel();
      final store = ref.read(studioProjectStoreProvider.notifier);
      final p = _p;
      if (p.clips.isNotEmpty) unawaited(store.save(p).then((_) {}, onError: (Object e) => debugPrint('[StudioEditor] final save failed: $e')));
    }
    _lifecycle?.dispose();
    _pb.dispose();
    super.dispose();
  }

  /// Saves right away when the app goes to the background (it may be killed).
  AppLifecycleListener? _lifecycle;
  void _watchLifecycle() {
    _lifecycle = AppLifecycleListener(onPause: _flushSave, onInactive: _flushSave, onDetach: _flushSave);
  }

  void _flushSave() {
    if (!(_autosave?.isActive ?? false)) return;
    _autosave!.cancel();
    unawaited(_save());
  }

  // ── History ────────────────────────────────────────────────────────────

  void _set(StudioProject p) {
    _undo.add(_p);
    if (_undo.length > 80) _undo.removeAt(0);
    _redo.clear();
    _liveBase = null;
    _apply(p);
  }

  void _live(StudioProject p) {
    _liveBase ??= _p;
    _apply(p);
  }

  void _commit() {
    final base = _liveBase;
    _liveBase = null;
    if (base == null || identical(base, _p)) return;
    _undo.add(base);
    if (_undo.length > 80) _undo.removeAt(0);
    _redo.clear();
    _scheduleSave();
    setState(() {});
  }

  void _apply(StudioProject p) {
    setState(() => _p = p);
    _pb.update(p);
    _scheduleSave();
  }

  void _undoStep() {
    if (_undo.isEmpty) return;
    HapticFeedback.selectionClick();
    _redo.add(_p);
    _apply(_undo.removeLast());
  }

  void _redoStep() {
    if (_redo.isEmpty) return;
    HapticFeedback.selectionClick();
    _undo.add(_p);
    _apply(_redo.removeLast());
  }

  void _scheduleSave() {
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 1200), _save);
  }

  Future<void> _save() async {
    if (_p.clips.isEmpty) return;
    try {
      final saved = await ref.read(studioProjectStoreProvider.notifier).save(_p);
      if (mounted && saved.thumbnailPath != _p.thumbnailPath) _p = _p.copyWith(thumbnailPath: saved.thumbnailPath);
    } catch (e) {
      debugPrint('[StudioEditor] autosave failed: $e');
    }
  }

  // ── Selection helpers ──────────────────────────────────────────────────

  int get _clipIndex {
    final i = _p.clips.indexWhere((c) => c.id == _clipId);
    if (i >= 0) return i;
    return _p.clipIndexAt(_pb.posMs);
  }

  StudioClip? get _clip {
    final i = _clipIndex;
    return i < 0 ? null : _p.clips[i];
  }

  StudioText? get _text => _p.texts.where((t) => t.id == _textId).firstOrNull;
  StudioAudio? get _audio => _p.audios.where((a) => a.id == _audioId).firstOrNull;
  StudioEffect? get _effect => _p.effects.where((e) => e.id == _effectId).firstOrNull;
  StudioOverlay? get _overlay => _p.overlays.where((o) => o.id == _overlayId).firstOrNull;

  void _replaceOverlay(StudioOverlay o, {bool live = false}) {
    final list = [for (final x in _p.overlays) x.id == o.id ? o : x];
    live ? _live(_p.copyWith(overlays: list)) : _set(_p.copyWith(overlays: list));
  }

  void _selectOverlay(String? id) => setState(() {
        _overlayId = id;
        _clipId = null;
        _textId = null;
        _audioId = null;
        _effectId = null;
        _panel = id == null ? _Panel.none : _Panel.overlay;
      });

  /// Picture-in-picture: a photo or video placed over the main track at the playhead.
  Future<void> _addOverlay() async {
    _pb.pause();
    final res = await context.push<StudioPickResult>('/create/studio/picker?mode=${_isPhoto ? 'photo' : 'any'}&multi=0');
    if (res == null || res.picks.isEmpty || !mounted) return;
    final imported = await studioImportWithProgress(context, res.picks, allowVideo: !_isPhoto);
    if (imported == null || imported.clips.isEmpty || !mounted) {
      if (imported?.message != null) _toast(imported!.message!);
      return;
    }
    final start = _isPhoto ? 0 : _pb.posMs;
    final room = _isPhoto ? null : math.max(500, _p.durationMs - start);
    final o = StudioOverlay.fromClip(imported.clips.first, offsetMs: start, maxMs: room);
    _set(_p.copyWith(overlays: [..._p.overlays, o]));
    _selectOverlay(o.id);
    _toast('Drag to place it, pinch to resize and rotate');
  }

  void _replaceClip(StudioClip c, {bool live = false}) {
    final clips = [for (final x in _p.clips) x.id == c.id ? c : x];
    live ? _live(_p.copyWith(clips: clips)) : _set(_p.copyWith(clips: clips));
  }

  void _replaceText(StudioText t) => _set(_p.copyWith(texts: [for (final x in _p.texts) x.id == t.id ? t : x]));

  void _replaceEffect(StudioEffect e, {bool live = false}) {
    final list = [for (final x in _p.effects) x.id == e.id ? e : x];
    live ? _live(_p.copyWith(effects: list)) : _set(_p.copyWith(effects: list));
  }

  void _replaceAudio(StudioAudio a, {bool live = false}) {
    final audios = [for (final x in _p.audios) x.id == a.id ? a : x];
    live ? _live(_p.copyWith(audios: audios)) : _set(_p.copyWith(audios: audios));
  }

  void _openClipPanel(_Panel panel) {
    final c = _clip;
    if (c == null) return;
    _pb.pause();
    setState(() {
      _clipId = c.id;
      _panel = panel;
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)));
  }

  int get _textEnd => _isPhoto ? 1 : math.max(_pb.posMs + 300, math.min(_pb.posMs + 3000, _p.durationMs));

  // ── Media ──────────────────────────────────────────────────────────────

  Future<List<StudioClip>> _pickClips({bool multiple = true}) async {
    _pb.pause();
    final mode = _isPhoto ? 'photo' : 'any';
    final res = await context.push<StudioPickResult>('/create/studio/picker?mode=$mode&multi=${multiple ? 1 : 0}');
    if (res == null || res.picks.isEmpty || !mounted) return const [];
    final result = await studioImportWithProgress(context, res.picks, allowVideo: !_isPhoto);
    if (result == null) return const [];
    final msg = result.message;
    if (msg != null) _toast(msg);
    return result.clips;
  }

  Future<void> _addClips() async {
    final clips = await _pickClips();
    if (clips.isEmpty || !mounted) return;
    final at = _p.clips.isEmpty ? 0 : _p.clipIndexAt(_pb.posMs) + 1;
    final list = [..._p.clips]..insertAll(at, clips);
    _set(_p.copyWith(clips: list));
    _pb.warmUp();
    _pb.seek(_p.clipStartMs(at));
  }

  Future<void> _replace() async {
    final old = _clip;
    if (old == null) return;
    final picked = await _pickClips(multiple: false);
    if (picked.isEmpty) return;
    var c = picked.first;
    if (!c.isImage) {
      final wantSrc = old.isImage ? old.imageDurationMs : old.endMs - old.startMs;
      c = c.copyWith(endMs: math.min(c.sourceDurationMs, c.startMs + wantSrc));
    } else {
      c = c.copyWith(imageDurationMs: old.outDurationMs);
    }
    c = c.copyWith(
      id: old.id,
      filterId: old.filterId,
      filterIntensity: old.filterIntensity,
      adjust: old.adjust,
      rotation: 0,
      fill: old.fill,
      speed: c.isImage ? 1 : old.speed,
      volume: old.volume,
      muted: old.muted,
    );
    _replaceClip(c);
    _pb.warmUp();
    _toast('Clip replaced');
  }

  Future<void> _split() async {
    final i = _p.clipIndexAt(_pb.posMs);
    if (i < 0) return;
    final c = _p.clips[i];
    final local = _pb.posMs - _p.clipStartMs(i);
    if (local < 200 || c.outDurationMs - local < 200) {
      _toast('Move the playhead inside the clip to split');
      return;
    }
    final StudioClip a, b;
    if (c.isImage) {
      a = c.copyWith(imageDurationMs: local);
      b = c.copyWith(id: '${c.id}_${DateTime.now().millisecondsSinceEpoch}', imageDurationMs: c.imageDurationMs - local);
    } else {
      final cut = c.sourceMsAt(local);
      a = c.copyWith(endMs: cut);
      b = c.copyWith(id: '${c.id}_${DateTime.now().millisecondsSinceEpoch}', startMs: cut);
    }
    final list = [..._p.clips]..replaceRange(i, i + 1, [a, b]);
    _set(_p.copyWith(clips: list));
    setState(() => _clipId = b.id);
    HapticFeedback.mediumImpact();
  }

  Future<void> _delete() async {
    final i = _clipIndex;
    if (i < 0) return;
    if (_p.clips.length == 1) {
      _toast('A project needs at least one clip');
      return;
    }
    final ok = await studioConfirm(context, title: 'Delete clip?', message: 'You can undo this.', confirmLabel: 'Delete');
    if (!ok) return;
    final list = [..._p.clips]..removeAt(i);
    _set(_p.copyWith(clips: list));
    setState(() {
      _clipId = null;
      _panel = _Panel.none;
    });
  }

  void _duplicate() {
    final i = _clipIndex;
    if (i < 0) return;
    final c = _p.clips[i];
    final list = [..._p.clips]..insert(i + 1, c.copyWith(id: '${c.id}_d${DateTime.now().millisecondsSinceEpoch}'));
    _set(_p.copyWith(clips: list));
    _toast('Clip duplicated');
  }

  Future<void> _freeze() async {
    final i = _p.clipIndexAt(_pb.posMs);
    if (i < 0) return;
    final c = _p.clips[i];
    if (c.isImage) {
      _toast('Freeze works on video clips');
      return;
    }
    _pb.pause();
    final local = _pb.posMs - _p.clipStartMs(i);
    final media = await StudioProjectStore.dir('media');
    try {
      final path = await OneovaMediaEngine.frame(
        c.path,
        ms: c.sourceMsAt(local),
        out: '${media.path}/freeze_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final size = await StudioMedia.imageSize(path);
      final still = StudioClip.create(path: path, isImage: true, durationMs: 0, width: size.$1, height: size.$2).copyWith(
        imageDurationMs: 2000,
        filterId: c.filterId,
        filterIntensity: c.filterIntensity,
        adjust: c.adjust,
        crop: c.crop,
        rotation: c.rotation,
        flipH: c.flipH,
        flipV: c.flipV,
        zoom: c.zoom,
        fill: c.fill,
      );
      final cut = c.sourceMsAt(local);
      final parts = <StudioClip>[
        if (cut - c.startMs >= 100) c.copyWith(endMs: cut),
        still,
        if (c.endMs - cut >= 100) c.copyWith(id: '${c.id}_f${DateTime.now().millisecondsSinceEpoch}', startMs: cut),
      ];
      final list = [..._p.clips]..replaceRange(i, i + 1, parts);
      _set(_p.copyWith(clips: list));
      setState(() => _clipId = still.id);
      _toast('Added a 2s freeze frame');
    } catch (e) {
      _toast('Could not grab that frame: $e');
    }
  }

  void _extractAudio() {
    final i = _clipIndex;
    if (i < 0) return;
    final c = _p.clips[i];
    if (c.isImage || !c.hasAudio) {
      _toast('This clip has no sound');
      return;
    }
    if (c.speed != 1) {
      _toast('Set speed to 1x before extracting audio');
      return;
    }
    final a = StudioAudio.create(
      path: c.path,
      title: 'Extracted audio',
      durationMs: c.sourceDurationMs,
      startMs: c.startMs,
      endMs: c.endMs,
      offsetMs: _p.clipStartMs(i),
    );
    final clips = [for (final x in _p.clips) x.id == c.id ? x.copyWith(muted: true) : x];
    _set(_p.copyWith(clips: clips, audios: [..._p.audios, a]));
    setState(() => _audioId = a.id);
    _toast('Audio moved to its own track');
  }

  void _toggleMuteAll() {
    final videos = _p.clips.where((c) => !c.isImage);
    if (videos.isEmpty) return;
    final mute = !videos.every((c) => c.muted);
    _set(_p.copyWith(clips: [for (final c in _p.clips) c.isImage ? c : c.copyWith(muted: mute)]));
    _toast(mute ? 'Original sound muted' : 'Original sound on');
  }

  void _setCover() {
    _set(_p.copyWith(coverMs: _pb.posMs));
    _toast('Cover set to ${studioClockFine(_pb.posMs)}');
  }

  Future<void> _addMusic() async {
    _pb.pause();
    // The phone's music library (with a Files button for anything else).
    final song = await showPhoneMusicSheet(context);
    if (song == null) return;
    try {
      final probe = await StudioMedia.probeAudio(song.path);
      final remaining = math.max(1000, _p.durationMs - _pb.posMs);
      final a = StudioAudio.create(
        path: song.path,
        title: song.title,
        durationMs: probe.duration.inMilliseconds,
        endMs: math.min(probe.duration.inMilliseconds, remaining),
        offsetMs: _pb.posMs,
      );
      _set(_p.copyWith(audios: [..._p.audios, a]));
      setState(() => _audioId = a.id);
    } on StudioMediaException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Could not read that audio file');
    }
  }

  Future<void> _addText({bool caption = false}) async {
    _pb.pause();
    var draft = StudioText.create(text: '', startMs: _isPhoto ? 0 : _pb.posMs, endMs: _textEnd, isCaption: caption);
    if (caption) {
      // New captions match the captions already on the timeline.
      final like = _p.texts.where((t) => t.isCaption).lastOrNull;
      if (like != null) draft = draft.copyWith(type: like.type, anim: like.anim, size: like.size, y: like.y, templateId: like.templateId);
    }
    final edit = await showStudioTextEditor(context, draft, title: caption ? 'Caption' : 'Text', maxEndMs: _isPhoto ? 0 : _p.durationMs);
    if (edit == null) return;
    final t = edit.text;
    _set(_p.copyWith(texts: [..._applyCaptionStyle(_p.texts, t, edit.applyToAllCaptions), t]));
    setState(() => _textId = t.id);
    if (caption && !_isPhoto) _pb.seek(t.endMs);
  }

  Future<void> _editText(StudioText t, {int tab = 0}) async {
    _pb.pause();
    final edit = await showStudioTextEditor(
      context,
      t,
      title: t.isCaption ? 'Caption' : (t.isSticker ? 'Sticker' : 'Text'),
      initialTab: tab,
      maxEndMs: _isPhoto ? 0 : _p.durationMs,
    );
    if (edit == null) return;
    final e = edit.text;
    final texts = [for (final x in _p.texts) x.id == e.id ? e : x];
    _set(_p.copyWith(texts: _applyCaptionStyle(texts, e, edit.applyToAllCaptions)));
  }

  /// Copies [from]'s template, style, animation and size to every caption.
  List<StudioText> _applyCaptionStyle(List<StudioText> texts, StudioText from, bool apply) {
    if (!apply || !from.isCaption) return texts;
    return [
      for (final x in texts)
        x.isCaption && x.id != from.id ? x.copyWith(type: from.type, anim: from.anim, size: from.size, y: from.y, templateId: from.templateId) : x,
    ];
  }

  /// Auto captions: render the original sound, transcribe it on the server
  /// (Vertex AI), and lay word-timed captions on the timeline.
  Future<void> _autoCaptions() async {
    _pb.pause();
    if (_isPhoto) return;
    final hasCaptions = _p.texts.any((t) => t.isCaption);
    final choice = await showStudioAutoCaptionSheet(context, hasCaptions: hasCaptions);
    if (choice == null || !mounted) return;
    final result = await runStudioTask<StudioCaptionResult>(
      context,
      title: 'Auto captions',
      describeError: (e) => e is StudioAiException ? e.message : 'Auto captions stopped: $e',
      task: (onProgress) => StudioCaptionService.autoCaptions(
        _p,
        language: choice.language,
        templateId: choice.templateId,
        onProgress: (p, _) => onProgress(p),
      ),
    );
    if (result == null || !mounted) return;
    final captions = result.captions;
    final notice = StudioCaptionService.supportNotice(result.languageName, result.support, captions: true);
    if (result.support == StudioLanguageSupport.unsupported) {
      await _notice('Language not supported yet', notice!);
      return;
    }
    if (captions.isEmpty) {
      _toast('No speech found in the original sound');
      return;
    }
    final kept = choice.replaceExisting ? _p.texts.where((t) => !t.isCaption) : _p.texts;
    _set(_p.copyWith(texts: [...kept, ...captions]));
    setState(() {
      _panel = _Panel.captions;
      _textId = null;
    });
    if (notice != null || result.lowConfidence > 0) {
      final unsure = result.lowConfidence > 0 ? ' ${result.lowConfidence} caption${result.lowConfidence == 1 ? '' : 's'} may be unclear.' : '';
      await _notice('${captions.length} captions in ${result.languageName}', '${notice ?? 'Check the captions before posting.'}$unsure');
    } else {
      _toast('${captions.length} captions · ${result.languageName}');
    }
  }

  Future<void> _notice(String title, String message) => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: c.surface,
          title: Text(title, style: GoogleFonts.inter(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          content: Text(message, style: GoogleFonts.inter(color: c.textSecondary, fontSize: 13, height: 1.4)),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );

  /// Translates every caption, or just [only].
  Future<void> _translate({StudioText? only}) async {
    _pb.pause();
    final targets = only != null ? [only] : _p.texts.where((t) => t.isCaption).toList();
    if (targets.isEmpty) {
      _toast(only == null ? 'Add captions first' : 'Pick a text layer');
      return;
    }
    final lang = await showStudioLanguagePicker(context);
    if (lang == null || !mounted) return;
    final res = await runStudioTask<(List<String>, StudioLanguageSupport)>(
      context,
      title: 'Translating to ${lang.name}',
      describeError: (e) => e is StudioAiException ? e.message : 'Translation stopped: $e',
      task: (onProgress) async {
        onProgress(0.2);
        return StudioCaptionService.translate([for (final t in targets) t.text], lang.code);
      },
    );
    if (res == null || !mounted) return;
    final (out, support) = res;
    final notice = StudioCaptionService.supportNotice(lang.name, support, captions: false);
    if (support == StudioLanguageSupport.unsupported) {
      await _notice('Language not supported yet', notice!);
      return;
    }
    final byId = {for (var i = 0; i < targets.length; i++) targets[i].id: out[i]};
    _set(_p.copyWith(texts: [
      for (final t in _p.texts)
        if (byId.containsKey(t.id)) _translated(t, byId[t.id]!, lang.code) else t,
    ]));
    if (notice != null || lang.limited) {
      await _notice('Translated to ${lang.name}', notice ?? StudioCaptionService.supportNotice(lang.name, StudioLanguageSupport.limited, captions: false)!);
    } else {
      _toast(only == null ? '${targets.length} captions in ${lang.name}' : 'Translated to ${lang.name}');
    }
  }

  /// [t] with new text; word timing is spread evenly over the caption so
  /// word highlights keep working in the new language.
  StudioText _translated(StudioText t, String text, String lang) {
    final words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final timed = t.words.isEmpty || words.isEmpty
        ? const <StudioWord>[]
        : [
            for (var i = 0; i < words.length; i++)
              StudioWord(
                words[i],
                t.startMs + ((t.endMs - t.startMs) * i / words.length).round(),
                t.startMs + ((t.endMs - t.startMs) * (i + 1) / words.length).round(),
              ),
          ];
    return t.copyWith(text: text, lang: lang, words: timed);
  }

  /// Saves the captions as an .srt file the user picks a place for.
  Future<void> _exportSrt() async {
    final caps = _p.texts.where((t) => t.isCaption).toList()..sort((a, b) => a.startMs.compareTo(b.startMs));
    if (caps.isEmpty) {
      _toast('Add captions first');
      return;
    }
    String ts(int ms) {
      final h = ms ~/ 3600000, m = (ms ~/ 60000) % 60, s = (ms ~/ 1000) % 60, f = ms % 1000;
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(h)}:${two(m)}:${two(s)},${f.toString().padLeft(3, '0')}';
    }

    final b = StringBuffer();
    for (var i = 0; i < caps.length; i++) {
      b
        ..writeln(i + 1)
        ..writeln('${ts(caps[i].startMs)} --> ${ts(caps[i].endMs)}')
        ..writeln(caps[i].text)
        ..writeln();
    }
    final name = '${_p.title.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')}_captions.srt';
    try {
      final saved = await FilePicker.saveFile(fileName: name, bytes: Uint8List.fromList(utf8.encode(b.toString())));
      if (saved != null) _toast('Captions saved');
    } catch (e) {
      _toast('Could not save the captions file');
    }
  }

  /// Faces found per clip id (null = still looking).
  final Map<String, bool?> _faces = {};

  Future<void> _openRetouch() async {
    final c = _clip;
    if (c == null) return;
    _openClipPanel(_Panel.retouch);
    final cached = StudioFaceTracker.cached(c);
    if (cached != null) {
      setState(() => _faces[c.id] = cached.hasFaces);
      return;
    }
    setState(() => _faces[c.id] = null);
    try {
      final t = await StudioFaceTracker.track(c);
      if (mounted) setState(() => _faces[c.id] = t.hasFaces);
    } catch (e) {
      debugPrint('[StudioEditor] face tracking failed: $e');
      if (mounted) setState(() => _faces[c.id] = false);
    }
  }

  Future<void> _reverse() async {
    final c = _clip;
    if (c == null || c.isImage) {
      _toast('Reverse works on video clips');
      return;
    }
    if (c.endMs - c.startMs > StudioClipTools.maxReverseMs) {
      _toast('Trim the clip to 60 seconds or less to reverse it');
      return;
    }
    _pb.pause();
    final reversed = await runStudioTask<StudioClip>(
      context,
      title: 'Reversing clip',
      describeError: (e) => e is MediaEngineException ? e.message : '$e',
      task: (onProgress) async {
        final sub = OneovaMediaEngine.progress.listen(onProgress);
        try {
          return await StudioClipTools.reverse(c);
        } finally {
          await sub.cancel();
        }
      },
    );
    if (reversed == null || !mounted) return;
    _replaceClip(reversed);
    _pb.warmUp();
    _toast('Clip reversed');
  }

  Future<void> _openStabilize() async {
    final c = _clip;
    if (c == null || c.isImage) {
      _toast('Stabilize works on video clips');
      return;
    }
    _pb.pause();
    if (StudioStabilizer.cached(c) == null) {
      final m = await runStudioTask<StudioMotion>(
        context,
        title: 'Measuring camera shake',
        describeError: (e) => e is MediaEngineException ? e.message : '$e',
        task: (onProgress) async {
          final sub = OneovaMediaEngine.progress.listen(onProgress);
          try {
            return await StudioStabilizer.analyse(c);
          } finally {
            await sub.cancel();
          }
        },
      );
      if (m == null || !mounted) return;
    }
    if (c.stabilize == 0) _replaceClip(c.copyWith(stabilize: 0.5));
    setState(() {
      _clipId = c.id;
      _panel = _Panel.stabilize;
    });
  }

  Future<void> _detectBeats() async {
    final a = _audio;
    if (a == null) {
      _toast('Pick an audio track first');
      return;
    }
    _pb.pause();
    final withBeats = await runStudioTask<StudioAudio>(
      context,
      title: 'Finding beats',
      describeError: (e) => e is MediaEngineException ? e.message : '$e',
      task: (onProgress) async {
        onProgress(0.3);
        return StudioClipTools.detectBeats(a);
      },
    );
    if (withBeats == null || !mounted) return;
    _replaceAudio(withBeats);
    final n = withBeats.timelineBeats.length;
    _toast(n == 0 ? 'No clear beats found' : '$n beats${withBeats.bpm > 0 ? ' · ${withBeats.bpm.round()} BPM' : ''}');
  }

  void _cutToBeats() {
    final a = _audio ?? _p.audios.where((x) => x.beatsMs.isNotEmpty).firstOrNull;
    if (a == null || a.beatsMs.isEmpty) {
      _toast('Find the beats of a track first');
      return;
    }
    _set(StudioClipTools.cutToBeats(_p, a));
    _toast('Cuts now land on the beat');
  }

  void _addEffect(String effectId) {
    final def = StudioEffects.byId(effectId);
    if (def == null) return;
    final start = _isPhoto ? 0 : _pb.posMs;
    final end = _isPhoto ? 1 << 30 : math.min(_p.durationMs, start + (def.group == 'Transition' ? 800 : 3000));
    if (end - start < 200) {
      _toast('Move the playhead back a little to add an effect');
      return;
    }
    final e = StudioEffect.create(effectId: effectId, startMs: start, endMs: end, amount: def.amount);
    _set(_p.copyWith(effects: [..._p.effects, e]));
    setState(() {
      _effectId = e.id;
      _panel = _Panel.effects;
    });
  }

  Future<void> _addSticker() async {
    _pb.pause();
    final s = await showStudioStickerSheet(context);
    if (s == null) return;
    final t = StudioText.create(text: s, startMs: _isPhoto ? 0 : _pb.posMs, endMs: _textEnd, isSticker: true);
    _set(_p.copyWith(texts: [..._p.texts, t]));
    setState(() {
      _textId = t.id;
      _panel = _Panel.text;
    });
  }

  Future<void> _importCaptions() async {
    _pb.pause();
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['srt']);
    if (f?.path == null) return;
    final cues = parseSrt(await File(f!.path!).readAsString());
    final total = _p.durationMs;
    final added = [
      for (final c in cues)
        if (c.$1 < total) StudioText.create(text: c.$3, startMs: c.$1, endMs: math.min(c.$2, total), isCaption: true),
    ];
    if (added.isEmpty) {
      _toast('No captions found in that file');
      return;
    }
    _set(_p.copyWith(texts: [..._p.texts, ...added]));
    _toast('Imported ${added.length} captions');
  }

  Future<void> _captionTemplates() async {
    final captions = _p.texts.where((t) => t.isCaption).toList();
    if (captions.isEmpty) {
      _toast('Add captions first');
      return;
    }
    final first = _text?.isCaption == true ? _text! : captions.first;
    final edit = await showStudioTextEditor(context, first, title: 'Caption style', maxEndMs: _p.durationMs);
    if (edit == null) return;
    final e = edit.text;
    _set(_p.copyWith(texts: _applyCaptionStyle([for (final x in _p.texts) x.id == e.id ? e : x], e, true)));
    _toast('Style applied to ${captions.length} captions');
  }

  // ── Export ─────────────────────────────────────────────────────────────

  Future<void> _export() async {
    _pb.pause();
    if (_p.clips.isEmpty) return;
    final choice = await showStudioExportSheet(context, _p, allowGif: widget.args.target == StudioTarget.device);
    if (choice == null || !mounted) return;
    if (choice.video != null) _p = _p.copyWith(exportShortSide: choice.video!.shortSide);
    await _save();
    if (!mounted) return;

    final gif = choice.gif;
    // The mark is added to the rendered copy only, never to the project.
    final out = choice.watermark
        ? StudioExportExtras.withWatermark(_p, handle: FirebaseAuth.instance.currentUser?.displayName)
        : _p;
    final path = await runStudioTask<String>(
      context,
      title: _isPhoto ? 'Exporting photo' : (gif != null ? 'Making GIF' : 'Exporting video'),
      onCancel: _isPhoto ? null : OneovaMediaEngine.cancel,
      describeError: (e) => e is MediaEngineException ? 'The export stopped: ${e.message}' : '$e',
      task: (onProgress) async {
        if (_isPhoto) {
          onProgress(0.3);
          return StudioRenderer.exportPhoto(out, maxLongSide: choice.photoLongSide);
        }
        if (gif != null) {
          final sub = OneovaMediaEngine.progress.listen((v) => onProgress(v * 0.6));
          try {
            return await StudioExportExtras.exportGif(out, gif, onProgress: onProgress);
          } finally {
            await sub.cancel();
          }
        }
        final sub = OneovaMediaEngine.progress.listen(onProgress);
        try {
          return await StudioRenderer.exportVideo(out, choice.video!);
        } finally {
          await sub.cancel();
        }
      },
    );
    if (path == null || !mounted) return;

    if (choice.saveToGallery) {
      try {
        final ok = (await PhotoManager.requestPermissionExtend()).hasAccess;
        if (ok) {
          if (gif != null) {
            await PhotoManager.editor.saveImageWithPath(path, title: 'Oneova_${DateTime.now().millisecondsSinceEpoch}.gif');
          } else if (_isPhoto) {
            await PhotoManager.editor.saveImageWithPath(path, title: 'Oneova_${DateTime.now().millisecondsSinceEpoch}.jpg');
          } else {
            await PhotoManager.editor.saveVideo(File(path), title: 'Oneova_${DateTime.now().millisecondsSinceEpoch}.mp4');
          }
        }
      } catch (e) {
        debugPrint('[StudioEditor] gallery save failed: $e');
      }
    }
    if (!mounted) return;

    switch (widget.args.target) {
      case StudioTarget.story:
        final storyId = await runStudioTask<String>(
          context,
          title: 'Posting story',
          task: (onProgress) => StudioPublisher.publishStory(
            stories: ref.read(storyServiceProvider),
            path: path,
            isVideo: !_isPhoto,
            onProgress: onProgress,
          ),
        );
        if (storyId != null && mounted) {
          _toast('Your story is live');
          context.go('/hub/home');
        }
      case StudioTarget.device:
        _toast(choice.saveToGallery ? 'Saved to your gallery' : 'Export ready');
      case StudioTarget.post:
        String? cover;
        if (!_isPhoto) {
          try {
            final dir = await StudioProjectStore.dir('exports');
            cover = await OneovaMediaEngine.frame(
              path,
              ms: _p.coverMs.clamp(0, math.max(0, _p.durationMs - 100)),
              out: '${dir.path}/cover_${DateTime.now().millisecondsSinceEpoch}.jpg',
              maxSide: 1280,
            );
          } catch (_) {}
        }
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MediaPreviewScreen(
            mediaPath: path,
            isVideo: !_isPhoto,
            initialCoverPath: cover,
            initialCoverTimeMs: _p.coverMs,
            remixOf: _p.remixOf,
          ),
        ));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_panel != _Panel.none) {
          setState(() => _panel = _Panel.none);
          return;
        }
        await _close();
      },
      child: Scaffold(
        backgroundColor: context.bg,
        body: SafeArea(
          child: Column(
            children: [
              if (!_fullscreen) _topBar(),
              Expanded(child: _stage()),
              if (!_fullscreen) _controls(),
              if (!_fullscreen && !_isPhoto)
                SizedBox(
                  height: 208,
                  child: StudioTimeline(
                    playback: _pb,
                    project: _p,
                    selectedClipId: _panel == _Panel.none && _clipId == null ? null : _clipId,
                    selectedTextId: _textId,
                    selectedAudioId: _audioId,
                    selectedEffectId: _effectId,
                    onSelectClip: (id) => setState(() {
                      _clipId = id;
                      _textId = null;
                      _audioId = null;
                      _effectId = null;
                      _panel = id == null ? _Panel.none : _Panel.clip;
                    }),
                    onSelectText: (id) => setState(() {
                      _textId = id;
                      _clipId = null;
                      _audioId = null;
                      _effectId = null;
                      final t = _text;
                      _panel = id == null ? _Panel.none : (t?.isCaption == true ? _Panel.captions : _Panel.text);
                    }),
                    onSelectAudio: (id) => setState(() {
                      _audioId = id;
                      _clipId = null;
                      _textId = null;
                      _effectId = null;
                      _panel = id == null ? _Panel.none : _Panel.audio;
                    }),
                    onSelectEffect: (id) => setState(() {
                      _effectId = id;
                      _clipId = null;
                      _textId = null;
                      _audioId = null;
                      _panel = _Panel.effects;
                    }),
                    onAddEffect: () => setState(() {
                      _effectId = null;
                      _panel = _Panel.effects;
                    }),
                    selectedOverlayId: _overlayId,
                    onSelectOverlay: _selectOverlay,
                    onAddOverlay: _addOverlay,
                    onTrimPreview: (c) => _replaceClip(c, live: true),
                    onTrimCommit: _commit,
                    onAddClip: _addClips,
                    onAddAudio: () => setState(() => _panel = _Panel.audio),
                    onAddText: () => setState(() => _panel = _Panel.text),
                    onCover: _setCover,
                    onToggleMuteAll: _toggleMuteAll,
                    onReorderClips: (clips) {
                      _set(_p.copyWith(clips: clips));
                      _toast('Clips reordered');
                    },
                  ),
                ),
              if (!_fullscreen) _bottom(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _close() async {
    _pb.pause();
    _autosave?.cancel();
    await _save();
    if (mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/hub/home');
      }
    }
  }

  Widget _topBar() {
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          IconButton(icon: Icon(Icons.close_rounded, color: context.textPrimary), onPressed: _close),
          Expanded(
            child: GestureDetector(
              onTap: _rename,
              child: Text(
                _p.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (widget.args.target == StudioTarget.story)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.brandPink, borderRadius: BorderRadius.circular(AppRadius.full)),
              child: Text('STORY', style: GoogleFonts.inter(color: AppColors.brandWhite, fontSize: 9.5, fontWeight: FontWeight.w900)),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: StudioPrimaryButton(label: widget.args.target == StudioTarget.story ? 'Next' : 'Export', onTap: _export),
          ),
        ],
      ),
    );
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: _p.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Rename project', style: GoogleFonts.inter(color: ctx.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(controller: c, autofocus: true, style: GoogleFonts.inter(color: ctx.textPrimary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    if (name != null && name.isNotEmpty) _set(_p.copyWith(title: name));
  }

  Widget _stage() {
    final clip = _clip;
    final cropping = _panel == _Panel.crop && clip != null;
    return GestureDetector(
      onTap: _fullscreen ? () => setState(() => _fullscreen = false) : null,
      child: ColoredBox(
        color: AppColors.brandBlack,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: cropping
              ? StudioCropEditor(
                  clip: clip,
                  frame: StudioClipView(
                    clip: clip.copyWith(rotation: 0, flipH: false, flipV: false, zoom: 1, fill: false),
                    controller: _pb.controllerFor(clip),
                    uncropped: true,
                  ),
                  onChanged: (crop) => _replaceClip(clip.copyWith(crop: crop)),
                )
              : StudioPreview(
                  playback: _pb,
                  project: _p,
                  showAllText: _isPhoto,
                  selectedTextId: _textId,
                  onSelectText: (id) => setState(() {
                    _textId = id;
                    if (id != null) {
                      _panel = _text?.isCaption == true ? _Panel.captions : _Panel.text;
                    } else if (_panel == _Panel.text || _panel == _Panel.captions) {
                      _panel = _Panel.none;
                    }
                  }),
                  onMoveText: (t, x, y) => _replaceText(t.copyWith(x: x, y: y)),
                  onTransformText: (t, size, rotation) {
                    final current = _p.texts.where((x) => x.id == t.id).firstOrNull;
                    if (current != null) _replaceText(current.copyWith(size: size, rotation: rotation));
                  },
                  onEditText: _editText,
                  selectedOverlayId: _overlayId,
                  onSelectOverlay: _selectOverlay,
                  onMoveOverlay: (o, x, y, sc, rot) {
                    final current = _p.overlays.where((e) => e.id == o.id).firstOrNull;
                    if (current != null) _replaceOverlay(current.copyWith(x: x, y: y, scale: sc, rotation: rot));
                  },
                ),
        ),
      ),
    );
  }

  Widget _controls() {
    final icon = context.textPrimary;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.fullscreen_rounded, color: icon),
            onPressed: () => setState(() => _fullscreen = true),
          ),
          if (!_isPhoto)
            ListenableBuilder(
              listenable: _pb,
              builder: (_, _) => Text(
                '${studioClock(_pb.posMs)} / ${studioClock(_p.durationMs)}',
                style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          const Spacer(),
          if (!_isPhoto)
            ListenableBuilder(
              listenable: _pb,
              builder: (_, _) => IconButton(
                iconSize: 30,
                icon: Icon(_pb.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: icon),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _pb.toggle();
                },
              ),
            ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.undo_rounded, color: _undo.isEmpty ? context.textMuted : icon),
            onPressed: _undo.isEmpty ? null : _undoStep,
          ),
          IconButton(
            icon: Icon(Icons.redo_rounded, color: _redo.isEmpty ? context.textMuted : icon),
            onPressed: _redo.isEmpty ? null : _redoStep,
          ),
        ],
      ),
    );
  }

  Widget _bar(List<Widget> tools, {VoidCallback? onBack}) {
    return Container(
      height: 76,
      decoration: BoxDecoration(color: context.surface, border: Border(top: BorderSide(color: context.border))),
      child: Row(
        children: [
          if (onBack != null)
            GestureDetector(
              onTap: onBack,
              child: Container(
                width: 40,
                margin: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                decoration: BoxDecoration(color: context.surfaceMid, borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: Icon(Icons.chevron_left_rounded, color: context.textPrimary),
              ),
            ),
          Expanded(child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 4), children: tools)),
        ],
      ),
    );
  }

  void _back() => setState(() {
        _panel = _Panel.none;
        _clipId = null;
        _textId = null;
        _audioId = null;
        _effectId = null;
        _overlayId = null;
      });

  Widget _bottom() {
    final clip = _clip;
    switch (_panel) {
      case _Panel.none:
        return _mainBar();
      case _Panel.clip:
        return clip == null ? _mainBar() : _clipBar(clip);
      case _Panel.audio:
        return _audioBar();
      case _Panel.text:
        return _textBar();
      case _Panel.captions:
        return _captionsBar();
      case _Panel.filters:
        if (clip == null) return _mainBar();
        return StudioFiltersPanel(
          clip: clip,
          onLive: (c) => _replaceClip(c, live: true),
          onCommit: _commit,
          onApplyAll: () {
            _set(_p.copyWith(clips: [
              for (final c in _p.clips) c.copyWith(filterId: clip.filterId, filterIntensity: clip.filterIntensity),
            ]));
            _toast('Filter applied to all clips');
          },
          onDone: () => setState(() => _panel = _isPhoto ? _Panel.none : _Panel.clip),
        );
      case _Panel.looks:
        if (clip == null) return _mainBar();
        return StudioLooksPanel(
          clip: clip,
          onLive: (c) => _replaceClip(c, live: true),
          onCommit: _commit,
          onApplyAll: () {
            _set(_p.copyWith(clips: [
              for (final c in _p.clips) c.copyWith(lookId: clip.lookId, lookIntensity: clip.lookIntensity),
            ]));
            _toast('Look applied to all clips');
          },
          onDone: () => setState(() => _panel = _isPhoto ? _Panel.none : _Panel.clip),
        );
      case _Panel.retouch:
        if (clip == null) return _mainBar();
        return StudioRetouchPanel(
          clip: clip,
          facesFound: _faces[clip.id] ?? (StudioFaceTracker.cached(clip)?.hasFaces),
          onLive: (c) => _replaceClip(c, live: true),
          onCommit: _commit,
          onApplyAll: () {
            _set(_p.copyWith(clips: [for (final c in _p.clips) c.copyWith(retouch: clip.retouch)]));
            _toast('Retouch applied to all clips');
          },
          onDone: () => setState(() => _panel = _isPhoto ? _Panel.none : _Panel.clip),
        );
      case _Panel.overlay:
        final o = _overlay;
        if (o == null) return _mainBar();
        return StudioPanel(
          title: o.isImage ? 'Photo overlay' : 'Video overlay',
          onDone: () => _selectOverlay(null),
          action: Row(mainAxisSize: MainAxisSize.min, children: [
            if (!_isPhoto) ...[
              StudioTextAction(
                icon: Icons.start_rounded,
                label: 'Start',
                onTap: () => _replaceOverlay(o.copyWith(offsetMs: math.min(_pb.posMs, math.max(0, _p.durationMs - 300)))),
              ),
              StudioTextAction(
                icon: Icons.keyboard_tab_rounded,
                label: 'End',
                onTap: () {
                  final len = _pb.posMs - o.offsetMs;
                  if (len < 300) {
                    _toast('Move the playhead inside the overlay');
                    return;
                  }
                  _replaceOverlay(o.isImage ? o.copyWith(imageDurationMs: len) : o.copyWith(endMs: math.min(o.sourceDurationMs, o.startMs + len)));
                },
              ),
            ],
            StudioTextAction(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              onTap: () {
                _set(_p.copyWith(overlays: [..._p.overlays]..removeWhere((x) => x.id == o.id)));
                _selectOverlay(null);
              },
            ),
          ]),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StudioSliderRow(
                  label: 'Size',
                  value: o.scale * 100,
                  min: 8,
                  max: 150,
                  format: (v) => '${v.round()}%',
                  onChanged: (v) => _replaceOverlay(o.copyWith(scale: v / 100), live: true),
                  onChangeEnd: (_) => _commit(),
                ),
                StudioSliderRow(
                  label: 'Opacity',
                  value: o.opacity * 100,
                  min: 5,
                  max: 100,
                  format: (v) => '${v.round()}%',
                  onChanged: (v) => _replaceOverlay(o.copyWith(opacity: v / 100), live: true),
                  onChangeEnd: (_) => _commit(),
                ),
                StudioSliderRow(
                  label: 'Rotate',
                  value: o.rotation,
                  min: -180,
                  max: 180,
                  format: (v) => '${v.round()}°',
                  onChanged: (v) => _replaceOverlay(o.copyWith(rotation: v.roundToDouble()), live: true),
                  onChangeEnd: (_) => _commit(),
                ),
                if (!o.isImage && o.hasAudio)
                  StudioSliderRow(
                    label: 'Volume',
                    value: o.muted ? 0 : o.volume * 100,
                    min: 0,
                    max: 200,
                    format: (v) => '${v.round()}%',
                    onChanged: (v) => _replaceOverlay(o.copyWith(volume: v / 100, muted: v == 0), live: true),
                    onChangeEnd: (_) => _commit(),
                  ),
              ],
            ),
          ),
        );
      case _Panel.stabilize:
        if (clip == null || clip.isImage) return _mainBar();
        return StudioSliderPanel(
          title: 'Stabilize',
          label: 'Strength',
          value: clip.stabilize * 100,
          min: 0,
          max: 100,
          format: (v) => v == 0 ? 'Off' : '${v.round()}',
          onLive: (v) => _replaceClip(clip.copyWith(stabilize: v / 100), live: true),
          onCommit: _commit,
          onDone: () => setState(() => _panel = _Panel.clip),
          footer: Text('Smooths handheld shake. Stronger settings zoom in a little more to hide the edges.',
              style: GoogleFonts.inter(color: context.textMuted, fontSize: 11.5)),
        );
      case _Panel.voice:
        if (clip == null || clip.isImage) return _mainBar();
        return StudioSliderPanel(
          title: 'Clean voice',
          label: 'Strength',
          value: clip.voiceClean * 100,
          min: 0,
          max: 100,
          format: (v) => v == 0 ? 'Off' : '${v.round()}',
          onLive: (v) => _replaceClip(clip.copyWith(voiceClean: v / 100), live: true),
          onCommit: _commit,
          onDone: () => setState(() => _panel = _Panel.clip),
          footer: Text('Cuts rumble and background hiss, evens out loud and quiet parts. The preview switches to the cleaned sound a moment after you let go.',
              style: GoogleFonts.inter(color: context.textMuted, fontSize: 11.5)),
        );
      case _Panel.effects:
        final fx = _effect;
        return StudioEffectsPanel(
          key: ValueKey(fx?.id ?? 'new'),
          selected: fx,
          onAdd: _addEffect,
          onLive: (e) => _replaceEffect(e, live: true),
          onCommit: _commit,
          onStartHere: fx == null || _isPhoto ? null : () => _replaceEffect(fx.copyWith(startMs: math.min(_pb.posMs, fx.endMs - 200))),
          onEndHere: fx == null || _isPhoto ? null : () => _replaceEffect(fx.copyWith(endMs: math.max(_pb.posMs, fx.startMs + 200))),
          onDelete: fx == null
              ? null
              : () {
                  _set(_p.copyWith(effects: [..._p.effects]..removeWhere((x) => x.id == fx.id)));
                  setState(() => _effectId = null);
                },
          onDone: () => setState(() {
            _panel = _Panel.none;
            _effectId = null;
          }),
        );
      case _Panel.adjust:
        if (clip == null) return _mainBar();
        return StudioAdjustPanel(
          clip: clip,
          onLive: (c) => _replaceClip(c, live: true),
          onCommit: _commit,
          onApplyAll: () {
            _set(_p.copyWith(clips: [for (final c in _p.clips) c.copyWith(adjust: clip.adjust)]));
            _toast('Adjustments applied to all clips');
          },
          onDone: () => setState(() => _panel = _isPhoto ? _Panel.none : _Panel.clip),
        );
      case _Panel.aspect:
        final fill = _p.clips.isNotEmpty && _p.clips.every((c) => c.fill);
        return StudioAspectPanel(
          aspect: _p.aspect,
          fill: fill,
          onAspect: (a) => _set(_p.copyWith(aspect: a)),
          onFill: (v) => _set(_p.copyWith(clips: [for (final c in _p.clips) c.copyWith(fill: v)])),
          onDone: () => setState(() => _panel = _Panel.none),
        );
      case _Panel.speed:
        if (clip == null || clip.isImage) return _mainBar();
        return StudioSliderPanel(
          title: 'Speed',
          label: 'Speed',
          value: clip.speed,
          min: 0.25,
          max: 4,
          divisions: 75,
          presets: const [('0.5x', 0.5), ('1x', 1), ('1.5x', 1.5), ('2x', 2), ('3x', 3)],
          format: (v) => '${v.toStringAsFixed(2)}x',
          onLive: (v) => _replaceClip(clip.copyWith(speed: v), live: true),
          onCommit: _commit,
          onDone: () => setState(() => _panel = _Panel.clip),
          footer: Text('${studioClockFine(clip.endMs - clip.startMs)} → ${studioClockFine(clip.outDurationMs)}',
              style: GoogleFonts.inter(color: context.textMuted, fontSize: 11.5)),
        );
      case _Panel.volume:
        if (clip == null || clip.isImage) return _mainBar();
        return StudioSliderPanel(
          title: 'Volume',
          label: 'Volume',
          value: clip.muted ? 0 : clip.volume * 100,
          min: 0,
          max: 200,
          format: (v) => '${v.round()}%',
          onLive: (v) => _replaceClip(clip.copyWith(volume: v / 100, muted: v == 0), live: true),
          onCommit: _commit,
          onDone: () => setState(() => _panel = _Panel.clip),
        );
      case _Panel.duration:
        if (clip == null || !clip.isImage) return _mainBar();
        return StudioSliderPanel(
          title: 'Duration',
          label: 'Seconds',
          value: clip.imageDurationMs / 1000,
          min: 0.5,
          max: 15,
          divisions: 29,
          format: (v) => '${v.toStringAsFixed(1)}s',
          onLive: (v) => _replaceClip(clip.copyWith(imageDurationMs: (v * 1000).round()), live: true),
          onCommit: _commit,
          onDone: () => setState(() => _panel = _Panel.clip),
        );
      case _Panel.transform:
        if (clip == null) return _mainBar();
        return StudioTransformPanel(
          clip: clip,
          onLive: (c) => _replaceClip(c, live: true),
          onCommit: _commit,
          onDone: () => setState(() => _panel = _isPhoto ? _Panel.none : _Panel.clip),
        );
      case _Panel.crop:
        if (clip == null) return _mainBar();
        return StudioPanel(
          title: 'Crop',
          onDone: () => setState(() => _panel = _isPhoto ? _Panel.none : _Panel.clip),
          action: StudioTextAction(
            icon: Icons.refresh_rounded,
            label: 'Reset',
            onTap: () => _replaceClip(clip.copyWith(crop: const StudioCrop())),
          ),
          child: SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final r in const <(String, double?)>[
                  ('Free', null),
                  ('9:16', 9 / 16),
                  ('1:1', 1),
                  ('4:5', 4 / 5),
                  ('3:4', 3 / 4),
                  ('16:9', 16 / 9),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                    child: ActionChip(
                      label: Text(r.$1),
                      labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: context.textPrimary),
                      backgroundColor: context.surfaceMid,
                      side: BorderSide(color: context.border),
                      onPressed: () => _replaceClip(clip.copyWith(crop: studioCropForRatio(clip, r.$2))),
                    ),
                  ),
              ],
            ),
          ),
        );
      case _Panel.audioVolume:
        final a = _audio;
        if (a == null) return _audioBar();
        return StudioSliderPanel(
          title: 'Audio volume',
          label: 'Volume',
          value: a.volume * 100,
          min: 0,
          max: 200,
          format: (v) => '${v.round()}%',
          onLive: (v) => _replaceAudio(a.copyWith(volume: v / 100), live: true),
          onCommit: _commit,
          onDone: () => setState(() => _panel = _Panel.audio),
        );
    }
  }

  /// Photo background removal: on-device subject segmentation, then the
  /// chosen background (transparent, blur, a colour or another photo).
  Future<void> _removeBackground() async {
    final clip = _clip;
    if (clip == null || !clip.isImage) {
      _toast('Select a photo to remove its background');
      return;
    }
    _pb.pause();
    final cut = await runStudioTask<String>(
      context,
      title: 'Removing background',
      task: (onProgress) async {
        onProgress(0.2);
        final r = await StudioCutout.cutout(clip.path);
        onProgress(1);
        return r;
      },
    );
    if (cut == null || !mounted) return;
    final choice = await showModalBottomSheet<(CutoutBackground, Color)>(
      context: context,
      backgroundColor: context.surface,
      builder: (ctx) {
        Widget tile(IconData icon, String label, (CutoutBackground, Color) v) => ListTile(
              leading: Icon(icon, color: AppColors.brandBlue),
              title: Text(label, style: TextStyle(color: ctx.textPrimary, fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, v),
            );
        const colours = <(String, Color)>[
          ('White', Color(0xFFFFFFFF)),
          ('Black', Color(0xFF111114)),
          ('Oneova blue', AppColors.brandBlue),
          ('Pink', AppColors.brandPink),
          ('Studio green', Color(0xFF00B140)),
        ];
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              tile(Icons.layers_outlined, 'Transparent (PNG)', (CutoutBackground.transparent, const Color(0x00000000))),
              tile(Icons.blur_on_rounded, 'Blur the background', (CutoutBackground.blur, const Color(0x00000000))),
              tile(Icons.image_outlined, 'Photo from my phone', (CutoutBackground.image, const Color(0x00000000))),
              for (final c in colours) tile(Icons.circle, c.$1, (CutoutBackground.colour, c.$2)),
            ]),
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    String? image;
    if (choice.$1 == CutoutBackground.image) {
      image = (await FilePicker.pickFile(type: FileType.image))?.path;
      if (image == null || !mounted) return;
    }
    final out = await runStudioTask<String>(
      context,
      title: 'Applying background',
      task: (onProgress) => StudioCutout.compose(
        originalPath: clip.path,
        cutoutPath: cut,
        background: choice.$1,
        colour: choice.$2,
        imagePath: image,
      ),
    );
    if (out == null || !mounted) return;
    final fresh = await StudioMedia.clipFromFile(out, isImage: true);
    _set(_p.copyWith(clips: [
      for (final c in _p.clips)
        c.id == clip.id ? c.copyWith(path: out, sourceWidth: fresh.sourceWidth, sourceHeight: fresh.sourceHeight) : c,
    ]));
    _toast('Background removed');
  }

  Widget _mainBar() {
    if (_isPhoto) {
      return _bar([
        StudioToolButton(icon: Icons.person_remove_outlined, label: 'Cut out', onTap: _removeBackground),
        StudioToolButton(icon: Icons.crop_rounded, label: 'Crop', onTap: () => _openClipPanel(_Panel.crop)),
        StudioToolButton(icon: Icons.rotate_90_degrees_cw_outlined, label: 'Transform', onTap: () => _openClipPanel(_Panel.transform)),
        StudioToolButton(icon: Icons.face_retouching_natural_rounded, label: 'Retouch', onTap: _openRetouch),
        StudioToolButton(icon: Icons.movie_filter_outlined, label: 'Looks', onTap: () => _openClipPanel(_Panel.looks)),
        StudioToolButton(icon: Icons.auto_awesome_outlined, label: 'Filters', onTap: () => _openClipPanel(_Panel.filters)),
        StudioToolButton(icon: Icons.tune_rounded, label: 'Adjust', onTap: () => _openClipPanel(_Panel.adjust)),
        StudioToolButton(icon: Icons.auto_fix_high_rounded, label: 'Effects', onTap: () => setState(() => _panel = _Panel.effects)),
        StudioToolButton(icon: Icons.title_rounded, label: 'Text', onTap: () => _addText()),
        StudioToolButton(icon: Icons.emoji_emotions_outlined, label: 'Stickers', onTap: _addSticker),
        StudioToolButton(icon: Icons.picture_in_picture_alt_rounded, label: 'Overlay', onTap: _addOverlay),
        StudioToolButton(icon: Icons.aspect_ratio_rounded, label: 'Canvas', onTap: () => setState(() => _panel = _Panel.aspect)),
        StudioToolButton(icon: Icons.add_photo_alternate_outlined, label: 'Replace', onTap: _replace),
      ]);
    }
    return _bar([
      StudioToolButton(icon: Icons.content_cut_rounded, label: 'Edit', onTap: () => _openClipPanel(_Panel.clip)),
      StudioToolButton(icon: Icons.music_note_outlined, label: 'Audio', onTap: () => setState(() => _panel = _Panel.audio)),
      StudioToolButton(icon: Icons.title_rounded, label: 'Text', onTap: () => setState(() => _panel = _Panel.text)),
      StudioToolButton(icon: Icons.closed_caption_outlined, label: 'Captions', onTap: () => setState(() => _panel = _Panel.captions)),
      StudioToolButton(icon: Icons.auto_fix_high_rounded, label: 'Effects', onTap: () => setState(() => _panel = _Panel.effects)),
      StudioToolButton(icon: Icons.face_retouching_natural_rounded, label: 'Retouch', onTap: _openRetouch),
      StudioToolButton(icon: Icons.movie_filter_outlined, label: 'Looks', onTap: () => _openClipPanel(_Panel.looks)),
      StudioToolButton(icon: Icons.auto_awesome_outlined, label: 'Filters', onTap: () => _openClipPanel(_Panel.filters)),
      StudioToolButton(icon: Icons.tune_rounded, label: 'Adjust', onTap: () => _openClipPanel(_Panel.adjust)),
      StudioToolButton(icon: Icons.picture_in_picture_alt_rounded, label: 'Overlay', onTap: _addOverlay),
      StudioToolButton(icon: Icons.emoji_emotions_outlined, label: 'Stickers', onTap: _addSticker),
      StudioToolButton(icon: Icons.aspect_ratio_rounded, label: 'Canvas', onTap: () => setState(() => _panel = _Panel.aspect)),
    ]);
  }

  Widget _clipBar(StudioClip clip) {
    final video = !clip.isImage;
    return _bar(onBack: _back, [
      StudioToolButton(icon: Icons.vertical_split_outlined, label: 'Split', onTap: _split),
      if (video) StudioToolButton(icon: Icons.volume_up_outlined, label: 'Volume', onTap: () => setState(() => _panel = _Panel.volume)),
      if (video) StudioToolButton(icon: Icons.speed_rounded, label: 'Speed', onTap: () => setState(() => _panel = _Panel.speed)),
      if (!video) StudioToolButton(icon: Icons.timer_outlined, label: 'Duration', onTap: () => setState(() => _panel = _Panel.duration)),
      if (!video) StudioToolButton(icon: Icons.person_remove_outlined, label: 'Cut out', onTap: _removeBackground),
      StudioToolButton(icon: Icons.crop_rounded, label: 'Crop', onTap: () => setState(() => _panel = _Panel.crop)),
      StudioToolButton(icon: Icons.rotate_90_degrees_cw_outlined, label: 'Transform', onTap: () => setState(() => _panel = _Panel.transform)),
      StudioToolButton(icon: Icons.face_retouching_natural_rounded, label: 'Retouch', onTap: _openRetouch),
      StudioToolButton(icon: Icons.movie_filter_outlined, label: 'Looks', onTap: () => setState(() => _panel = _Panel.looks)),
      StudioToolButton(icon: Icons.auto_awesome_outlined, label: 'Filters', onTap: () => setState(() => _panel = _Panel.filters)),
      StudioToolButton(icon: Icons.tune_rounded, label: 'Adjust', onTap: () => setState(() => _panel = _Panel.adjust)),
      StudioToolButton(icon: Icons.copy_all_outlined, label: 'Duplicate', onTap: _duplicate),
      StudioToolButton(icon: Icons.swap_horiz_rounded, label: 'Replace', onTap: _replace),
      if (video) StudioToolButton(icon: Icons.pause_presentation_outlined, label: 'Freeze', onTap: _freeze),
      if (video) StudioToolButton(icon: Icons.fast_rewind_rounded, label: 'Reverse', onTap: _reverse),
      if (video) StudioToolButton(icon: Icons.video_stable_rounded, label: 'Stabilize', onTap: _openStabilize),
      if (video && clip.hasAudio) StudioToolButton(icon: Icons.record_voice_over_outlined, label: 'Clean voice', onTap: () => setState(() => _panel = _Panel.voice)),
      if (video) StudioToolButton(icon: Icons.graphic_eq_rounded, label: 'Extract audio', onTap: _extractAudio),
      if (video)
        StudioToolButton(
          icon: clip.muted ? Icons.volume_off_outlined : Icons.volume_mute_outlined,
          label: clip.muted ? 'Unmute' : 'Mute',
          onTap: () => _replaceClip(clip.copyWith(muted: !clip.muted)),
        ),
      StudioToolButton(icon: Icons.delete_outline_rounded, label: 'Delete', onTap: _delete),
    ]);
  }

  Widget _audioBar() {
    final a = _audio;
    return _bar(onBack: _back, [
      StudioToolButton(icon: Icons.library_music_outlined, label: 'Add music', onTap: _addMusic),
      StudioToolButton(icon: Icons.graphic_eq_rounded, label: 'Extract audio', onTap: _extractAudio),
      if (a != null) ...[
        StudioToolButton(icon: Icons.volume_up_outlined, label: 'Volume', onTap: () => setState(() => _panel = _Panel.audioVolume)),
        StudioToolButton(icon: Icons.graphic_eq_rounded, label: 'Find beats', onTap: _detectBeats),
        if (a.beatsMs.isNotEmpty) StudioToolButton(icon: Icons.content_cut_rounded, label: 'Cut to beat', onTap: _cutToBeats),
        StudioToolButton(
          icon: Icons.start_rounded,
          label: 'Start here',
          onTap: () => _replaceAudio(a.copyWith(offsetMs: _pb.posMs)),
        ),
        StudioToolButton(
          icon: Icons.content_cut_rounded,
          label: 'End here',
          onTap: () {
            final len = _pb.posMs - a.offsetMs;
            if (len < 300) {
              _toast('Move the playhead inside the audio');
              return;
            }
            _replaceAudio(a.copyWith(endMs: math.min(a.sourceDurationMs, a.startMs + len)));
          },
        ),
        StudioToolButton(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          onTap: () async {
            final ok = await studioConfirm(context, title: 'Delete audio?', message: 'You can undo this.', confirmLabel: 'Delete');
            if (!ok) return;
            _set(_p.copyWith(audios: [..._p.audios]..removeWhere((x) => x.id == a.id)));
            setState(() => _audioId = null);
          },
        ),
      ],
    ]);
  }

  List<Widget> _layerTools(StudioText t) => [
        StudioToolButton(icon: Icons.edit_outlined, label: 'Edit', onTap: () => _editText(t)),
        if (!t.isSticker) StudioToolButton(icon: Icons.style_outlined, label: 'Templates', onTap: () => _editText(t)),
        StudioToolButton(icon: Icons.animation_rounded, label: 'Animate', onTap: () => _editText(t, tab: t.isSticker ? 0 : 3)),
        if (!t.isSticker) StudioToolButton(icon: Icons.translate_rounded, label: 'Translate', onTap: () => _translate(only: t)),
        if (!_isPhoto) ...[
          StudioToolButton(
            icon: Icons.start_rounded,
            label: 'Start here',
            onTap: () => _replaceText(t.copyWith(startMs: math.min(_pb.posMs, t.endMs - 200))),
          ),
          StudioToolButton(
            icon: Icons.keyboard_tab_rounded,
            label: 'End here',
            onTap: () => _replaceText(t.copyWith(endMs: math.max(_pb.posMs, t.startMs + 200))),
          ),
        ],
        StudioToolButton(
          icon: Icons.copy_all_outlined,
          label: 'Duplicate',
          onTap: () {
            final copy = StudioText.fromJson({...t.toJson(), 'id': '${t.id}_${DateTime.now().millisecondsSinceEpoch}'})
                .copyWith(y: (t.y + 0.15).clamp(-1.0, 1.0));
            _set(_p.copyWith(texts: [..._p.texts, copy]));
            setState(() => _textId = copy.id);
          },
        ),
        StudioToolButton(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          onTap: () async {
            final ok = await studioConfirm(context, title: 'Delete layer?', message: 'You can undo this.', confirmLabel: 'Delete');
            if (!ok) return;
            _set(_p.copyWith(texts: [..._p.texts]..removeWhere((x) => x.id == t.id)));
            setState(() => _textId = null);
          },
        ),
      ];

  Widget _textBar() {
    final t = _text;
    return _bar(onBack: _back, [
      StudioToolButton(icon: Icons.title_rounded, label: 'Add text', onTap: () => _addText()),
      StudioToolButton(icon: Icons.emoji_emotions_outlined, label: 'Stickers', onTap: _addSticker),
      StudioToolButton(icon: Icons.auto_fix_high_rounded, label: 'Effects', onTap: () => setState(() => _panel = _Panel.effects)),
      if (t != null && !t.isCaption) ..._layerTools(t),
    ]);
  }

  Widget _captionsBar() {
    final t = _text;
    return _bar(onBack: _back, [
      StudioToolButton(icon: Icons.record_voice_over_outlined, label: 'Auto captions', onTap: _autoCaptions),
      StudioToolButton(icon: Icons.translate_rounded, label: 'Translate', onTap: () => _translate()),
      StudioToolButton(icon: Icons.add_comment_outlined, label: 'Enter captions', onTap: () => _addText(caption: true)),
      StudioToolButton(icon: Icons.style_outlined, label: 'Caption style', onTap: _captionTemplates),
      StudioToolButton(icon: Icons.file_open_outlined, label: 'Import SRT', onTap: _importCaptions),
      StudioToolButton(icon: Icons.save_alt_rounded, label: 'Save SRT', onTap: _exportSrt),
      if (t != null && t.isCaption) ..._layerTools(t),
    ]);
  }
}

/// Small static preview of a text style (caption templates).
class StudioTextLayerPreview extends StatelessWidget {
  final StudioText text;
  const StudioTextLayerPreview({super.key, required this.text});

  @override
  Widget build(BuildContext context) => StudioTextLayer(text: text, canvasWidth: 300);
}
