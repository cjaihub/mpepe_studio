import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
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
import '../services/studio_media.dart';
import '../services/studio_playback.dart';
import '../services/studio_project_store.dart';
import '../services/studio_publisher.dart';
import '../services/studio_renderer.dart';
import '../services/studio_text_painter.dart';
import '../widgets/studio_export_sheet.dart';
import '../widgets/studio_panels.dart';
import '../widgets/studio_preview.dart';
import '../widgets/studio_progress_dialog.dart';
import '../widgets/studio_timeline.dart';
import '../widgets/studio_ui.dart';
import 'studio_media_picker_screen.dart';

class StudioEditorArgs {
  final StudioProject project;
  final StudioTarget target;

  /// Panel to open first ('captions', 'filters', 'speed', 'text', 'audio').
  final String? initialTool;

  const StudioEditorArgs({required this.project, this.target = StudioTarget.post, this.initialTool});
}

enum _Panel { none, clip, audio, text, captions, filters, adjust, aspect, speed, volume, transform, crop, duration, audioVolume }

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
  _Panel _panel = _Panel.none;
  bool _fullscreen = false;
  Timer? _autosave;

  bool get _isPhoto => _p.isPhoto;

  @override
  void initState() {
    super.initState();
    _pb.warmUp();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _save();
      switch (widget.args.initialTool) {
        case 'captions':
          setState(() => _panel = _Panel.captions);
        case 'filters':
          _openClipPanel(_Panel.filters);
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
    _autosave?.cancel();
    _pb.dispose();
    super.dispose();
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

  void _replaceClip(StudioClip c, {bool live = false}) {
    final clips = [for (final x in _p.clips) x.id == c.id ? c : x];
    live ? _live(_p.copyWith(clips: clips)) : _set(_p.copyWith(clips: clips));
  }

  void _replaceText(StudioText t) => _set(_p.copyWith(texts: [for (final x in _p.texts) x.id == t.id ? t : x]));

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
    if (res == null || res.picks.isEmpty) return const [];
    return StudioMedia.clipsFromPicks(res.picks);
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
    final file = await FilePicker.pickFile(type: FileType.audio);
    if (file?.path == null) return;
    try {
      final probe = await OneovaMediaEngine.probe(file!.path!);
      if (!probe.hasAudio || probe.duration.inMilliseconds <= 0) {
        _toast('That file has no playable audio');
        return;
      }
      final remaining = math.max(1000, _p.durationMs - _pb.posMs);
      final a = StudioAudio.create(
        path: file.path!,
        title: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
        durationMs: probe.duration.inMilliseconds,
        endMs: math.min(probe.duration.inMilliseconds, remaining),
        offsetMs: _pb.posMs,
      );
      _set(_p.copyWith(audios: [..._p.audios, a]));
      setState(() => _audioId = a.id);
    } catch (e) {
      _toast('Could not read that audio file');
    }
  }

  Future<void> _addText({bool caption = false}) async {
    _pb.pause();
    final draft = StudioText.create(text: '', startMs: _isPhoto ? 0 : _pb.posMs, endMs: _textEnd, isCaption: caption);
    final t = await showStudioTextSheet(context, draft, title: caption ? 'Caption' : 'Text');
    if (t == null) return;
    _set(_p.copyWith(texts: [..._p.texts, t]));
    setState(() => _textId = t.id);
    if (caption && !_isPhoto) _pb.seek(t.endMs);
  }

  Future<void> _editText(StudioText t) async {
    final edited = await showStudioTextSheet(context, t, title: t.isCaption ? 'Caption' : (t.isSticker ? 'Sticker' : 'Text'));
    if (edited != null) _replaceText(edited);
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
    final pick = await showModalBottomSheet<(StudioTextStyle, int)>(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) {
        final templates = <(String, StudioTextStyle, int)>[
          ('Default', StudioTextStyle.box, 0xFFFFFFFF),
          ('Bold', StudioTextStyle.bold, 0xFFFFD60A),
          ('Outline', StudioTextStyle.outline, 0xFFFFFFFF),
          ('Glow', StudioTextStyle.glow, 0xFFFF2D87),
          ('Clean', StudioTextStyle.plain, 0xFFFFFFFF),
          ('Brand', StudioTextStyle.box, 0xFF0C4FA8),
        ];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const StudioSheetHandle(),
              Text('Caption templates', style: GoogleFonts.inter(color: ctx.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              SizedBox(
                height: 90,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final t in templates)
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx, (t.$2, t.$3)),
                        child: Container(
                          width: 110,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2E),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: ctx.border),
                          ),
                          alignment: Alignment.center,
                          child: FittedBox(
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: StudioTextLayerPreview(
                                text: StudioText(
                                  id: 'tpl',
                                  text: t.$1,
                                  startMs: 0,
                                  endMs: 1,
                                  style: t.$2,
                                  color: t.$3,
                                  size: 0.14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
    if (pick == null) return;
    _set(_p.copyWith(texts: [
      for (final t in _p.texts) t.isCaption ? t.copyWith(style: pick.$1, color: pick.$2) : t,
    ]));
    _toast('Applied to ${captions.length} captions');
  }

  // ── Export ─────────────────────────────────────────────────────────────

  Future<void> _export() async {
    _pb.pause();
    if (_p.clips.isEmpty) return;
    final choice = await showStudioExportSheet(context, _p);
    if (choice == null || !mounted) return;
    if (choice.video != null) _p = _p.copyWith(exportShortSide: choice.video!.shortSide);
    await _save();
    if (!mounted) return;

    final path = await runStudioTask<String>(
      context,
      title: _isPhoto ? 'Exporting photo' : 'Exporting video',
      onCancel: _isPhoto ? null : OneovaMediaEngine.cancel,
      describeError: (e) => e is MediaEngineException ? 'The export stopped: ${e.message}' : '$e',
      task: (onProgress) async {
        if (_isPhoto) {
          onProgress(0.3);
          return StudioRenderer.exportPhoto(_p, maxLongSide: choice.photoLongSide);
        }
        final sub = OneovaMediaEngine.progress.listen(onProgress);
        try {
          return await StudioRenderer.exportVideo(_p, choice.video!);
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
          if (_isPhoto) {
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
                  height: 156,
                  child: StudioTimeline(
                    playback: _pb,
                    project: _p,
                    selectedClipId: _panel == _Panel.none && _clipId == null ? null : _clipId,
                    selectedTextId: _textId,
                    selectedAudioId: _audioId,
                    onSelectClip: (id) => setState(() {
                      _clipId = id;
                      _textId = null;
                      _audioId = null;
                      _panel = id == null ? _Panel.none : _Panel.clip;
                    }),
                    onSelectText: (id) => setState(() {
                      _textId = id;
                      _clipId = null;
                      _audioId = null;
                      final t = _text;
                      _panel = id == null ? _Panel.none : (t?.isCaption == true ? _Panel.captions : _Panel.text);
                    }),
                    onSelectAudio: (id) => setState(() {
                      _audioId = id;
                      _clipId = null;
                      _textId = null;
                      _panel = id == null ? _Panel.none : _Panel.audio;
                    }),
                    onTrimPreview: (c) => _replaceClip(c, live: true),
                    onTrimCommit: _commit,
                    onAddClip: _addClips,
                    onAddAudio: () => setState(() => _panel = _Panel.audio),
                    onAddText: () => setState(() => _panel = _Panel.text),
                    onCover: _setCover,
                    onToggleMuteAll: _toggleMuteAll,
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
                  onEditText: _editText,
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

  Widget _mainBar() {
    if (_isPhoto) {
      return _bar([
        StudioToolButton(icon: Icons.crop_rounded, label: 'Crop', onTap: () => _openClipPanel(_Panel.crop)),
        StudioToolButton(icon: Icons.rotate_90_degrees_cw_outlined, label: 'Transform', onTap: () => _openClipPanel(_Panel.transform)),
        StudioToolButton(icon: Icons.auto_awesome_outlined, label: 'Filters', onTap: () => _openClipPanel(_Panel.filters)),
        StudioToolButton(icon: Icons.tune_rounded, label: 'Adjust', onTap: () => _openClipPanel(_Panel.adjust)),
        StudioToolButton(icon: Icons.title_rounded, label: 'Text', onTap: () => _addText()),
        StudioToolButton(icon: Icons.emoji_emotions_outlined, label: 'Stickers', onTap: _addSticker),
        StudioToolButton(icon: Icons.aspect_ratio_rounded, label: 'Aspect ratio', onTap: () => setState(() => _panel = _Panel.aspect)),
        StudioToolButton(icon: Icons.add_photo_alternate_outlined, label: 'Replace', onTap: _replace),
      ]);
    }
    return _bar([
      StudioToolButton(icon: Icons.content_cut_rounded, label: 'Edit', onTap: () => _openClipPanel(_Panel.clip)),
      StudioToolButton(icon: Icons.music_note_outlined, label: 'Audio', onTap: () => setState(() => _panel = _Panel.audio)),
      StudioToolButton(icon: Icons.title_rounded, label: 'Text', onTap: () => setState(() => _panel = _Panel.text)),
      StudioToolButton(icon: Icons.emoji_emotions_outlined, label: 'Stickers', onTap: _addSticker),
      StudioToolButton(icon: Icons.closed_caption_outlined, label: 'Captions', onTap: () => setState(() => _panel = _Panel.captions)),
      StudioToolButton(icon: Icons.auto_awesome_outlined, label: 'Filters', onTap: () => _openClipPanel(_Panel.filters)),
      StudioToolButton(icon: Icons.tune_rounded, label: 'Adjust', onTap: () => _openClipPanel(_Panel.adjust)),
      StudioToolButton(icon: Icons.aspect_ratio_rounded, label: 'Aspect ratio', onTap: () => setState(() => _panel = _Panel.aspect)),
    ]);
  }

  Widget _clipBar(StudioClip clip) {
    final video = !clip.isImage;
    return _bar(onBack: _back, [
      StudioToolButton(icon: Icons.vertical_split_outlined, label: 'Split', onTap: _split),
      if (video) StudioToolButton(icon: Icons.volume_up_outlined, label: 'Volume', onTap: () => setState(() => _panel = _Panel.volume)),
      if (video) StudioToolButton(icon: Icons.speed_rounded, label: 'Speed', onTap: () => setState(() => _panel = _Panel.speed)),
      if (!video) StudioToolButton(icon: Icons.timer_outlined, label: 'Duration', onTap: () => setState(() => _panel = _Panel.duration)),
      StudioToolButton(icon: Icons.crop_rounded, label: 'Crop', onTap: () => setState(() => _panel = _Panel.crop)),
      StudioToolButton(icon: Icons.rotate_90_degrees_cw_outlined, label: 'Transform', onTap: () => setState(() => _panel = _Panel.transform)),
      StudioToolButton(icon: Icons.auto_awesome_outlined, label: 'Filters', onTap: () => setState(() => _panel = _Panel.filters)),
      StudioToolButton(icon: Icons.tune_rounded, label: 'Adjust', onTap: () => setState(() => _panel = _Panel.adjust)),
      StudioToolButton(icon: Icons.copy_all_outlined, label: 'Duplicate', onTap: _duplicate),
      StudioToolButton(icon: Icons.swap_horiz_rounded, label: 'Replace', onTap: _replace),
      if (video) StudioToolButton(icon: Icons.pause_presentation_outlined, label: 'Freeze', onTap: _freeze),
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
      if (t != null && !t.isCaption) ..._layerTools(t),
    ]);
  }

  Widget _captionsBar() {
    final t = _text;
    return _bar(onBack: _back, [
      StudioToolButton(icon: Icons.add_comment_outlined, label: 'Enter captions', onTap: () => _addText(caption: true)),
      StudioToolButton(icon: Icons.style_outlined, label: 'Caption templates', onTap: _captionTemplates),
      StudioToolButton(icon: Icons.file_open_outlined, label: 'Import captions', onTap: _importCaptions),
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
