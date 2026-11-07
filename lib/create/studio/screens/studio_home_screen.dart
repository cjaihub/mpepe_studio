import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:oneova_media_engine/oneova_media_engine.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../shared/theme/app_theme.dart';
import '../models/studio_project.dart';
import '../services/studio_media.dart';
import '../services/studio_project_store.dart';
import '../widgets/studio_progress_dialog.dart';
import '../widgets/studio_ui.dart';
import 'studio_editor_screen.dart';
import 'studio_media_picker_screen.dart';

/// Studio landing page: start a video or photo edit, jump straight into a
/// tool, or reopen a saved project.
class StudioHomeScreen extends ConsumerWidget {
  /// Tool to jump into right away (from the create sheet): any editor tool
  /// id, or 'retouch_photo' for a photo retouch.
  final String? initialTool;

  const StudioHomeScreen({super.key, this.initialTool});

  static Future<void> start(
    BuildContext context, {
    required bool photo,
    String? tool,
    StudioTarget target = StudioTarget.post,
    StudioAspect aspect = StudioAspect.original,
  }) async {
    final res = await context.push<StudioPickResult>('/create/studio/picker?mode=${photo ? 'photo' : 'any'}&multi=${photo ? 0 : 1}');
    if (res == null || res.picks.isEmpty || !context.mounted) return;
    final result = await studioImportWithProgress(context, res.picks, allowVideo: !photo);
    if (!context.mounted || result == null) return;
    final msg = result.message;
    if (result.clips.isEmpty || msg != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg ?? 'Could not open that media.')));
    }
    if (result.clips.isEmpty) return;
    final project = StudioProject.create(isPhoto: photo, clips: result.clips, exportShortSide: res.hd ? 0 : 720).copyWith(
      aspect: aspect,
      title: aspect == StudioAspect.portrait ? 'Short' : null,
    );
    await context.push('/create/studio/editor', extra: StudioEditorArgs(project: project, target: target, initialTool: tool));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(studioProjectStoreProvider);
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        toolbarHeight: 50,
        leading: IconButton(icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary), onPressed: () => context.pop()),
        title: Text('Studio', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Camera',
            icon: Icon(Icons.photo_camera_outlined, color: context.textPrimary),
            onPressed: () => context.push('/create/camera?mode=video'),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          if (initialTool != null) SliverToBoxAdapter(child: _AutoStart(tool: initialTool!)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _HeroCard(
                      icon: Icons.add_rounded,
                      label: 'New Short',
                      onTap: () => start(context, photo: false, aspect: StudioAspect.portrait),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _HeroCard(
                      icon: Icons.movie_creation_outlined,
                      label: 'Full video',
                      onTap: () => start(context, photo: false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _HeroCard(
                      icon: Icons.photo_outlined,
                      label: 'Edit photo',
                      onTap: () => start(context, photo: true),
                    ),
                  ),
                ],
              ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverGrid.count(
              crossAxisCount: 4,
              mainAxisSpacing: 12,
              crossAxisSpacing: 10,
              childAspectRatio: 0.78,
              children: [
                _ToolTile(icon: Icons.videocam_outlined, label: 'Camera', onTap: () => context.push('/create/camera?mode=video')),
                _ToolTile(icon: Icons.record_voice_over_outlined, label: 'Auto captions', onTap: () => start(context, photo: false, tool: 'autocaptions')),
                _ToolTile(icon: Icons.photo_filter_outlined, label: 'Photo editor', onTap: () => start(context, photo: true, tool: 'filters')),
                _ToolTile(icon: Icons.image_outlined, label: 'Cover maker', onTap: () => _coverMaker(context)),
                _ToolTile(icon: Icons.movie_filter_outlined, label: 'Looks', onTap: () => start(context, photo: false, tool: 'looks')),
                _ToolTile(icon: Icons.auto_fix_high_rounded, label: 'Effects', onTap: () => start(context, photo: false, tool: 'effects')),
                _ToolTile(
                  icon: Icons.amp_stories_outlined,
                  label: 'Story',
                  onTap: () => start(context, photo: false, target: StudioTarget.story),
                ),
                _ToolTile(icon: Icons.apps_rounded, label: 'All tools', onTap: () => _allTools(context)),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 22, 8, 6),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Text('Projects', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 19, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  if ((projects.value ?? const []).isNotEmpty)
                    Text('${projects.value!.length}',
                        style: GoogleFonts.inter(color: context.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
          projects.when(
            loading: () => const SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.brandBlue))),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load projects: $e', style: GoogleFonts.inter(color: context.textSecondary)),
              ),
            ),
            data: (list) => list.isEmpty
                ? SliverToBoxAdapter(child: _empty(context))
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverList.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _ProjectRow(project: list[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Icon(Icons.movie_edit, size: 52, color: context.textMuted),
            const SizedBox(height: 12),
            Text('Your projects will appear here.\nStart creating now.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: context.textSecondary, fontSize: 13.5, height: 1.4)),
          ],
        ),
      );

  /// Pick a video, choose a frame, then finish it in the photo editor.
  Future<void> _coverMaker(BuildContext context) async {
    final res = await context.push<StudioPickResult>('/create/studio/picker?mode=video&multi=0');
    if (res == null || res.picks.isEmpty || !context.mounted) return;
    final clips = await StudioMedia.clipsFromPicks(res.picks);
    if (clips.isEmpty || !context.mounted) return;
    final frame = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => _FramePicker(clip: clips.first)),
    );
    if (frame == null || !context.mounted) return;
    final still = await StudioMedia.clipFromFile(frame, isImage: true);
    if (!context.mounted) return;
    final project = StudioProject.create(isPhoto: true, clips: [still]).copyWith(title: 'Cover');
    await context.push('/create/studio/editor', extra: StudioEditorArgs(project: project, initialTool: 'text'));
  }

  void _allTools(BuildContext context) {
    // (icon, name, what it does, editor tool to open, photo project)
    final tools = <(IconData, String, String, String?, bool)>[
      (Icons.record_voice_over_outlined, 'Auto captions', 'Word-timed captions in any language, local ones too', 'autocaptions', false),
      (Icons.title_rounded, 'Text templates', '113 animated templates, fonts, outline, shadow, timing', 'text', false),
      (Icons.face_retouching_natural_rounded, 'Retouch', 'Smooth skin, even tone, bright eyes, whiter teeth, face shape', 'retouch', false),
      (Icons.movie_filter_outlined, 'Looks', '25 cinematic, portrait, film and mono grades', 'looks', false),
      (Icons.auto_fix_high_rounded, 'Effects', '30 timed effects: glitch, VHS, blur, light leak, transitions', 'effects', false),
      (Icons.auto_awesome_outlined, 'Filters', '18 quick filters with intensity', 'filters', false),
      (Icons.speed_rounded, 'Speed', '0.25x to 4x per clip', 'speed', false),
      (Icons.music_note_outlined, 'Audio & beats', 'Music, extract audio, find beats, cut to the beat', 'audio', false),
      (Icons.crop_rounded, 'Crop & transform', 'Free crop, rotate, mirror, zoom, fit or fill', 'crop', false),
      (Icons.closed_caption_outlined, 'Captions', 'Type, style, translate, import or save .srt', 'captions', false),
      (Icons.photo_filter_outlined, 'Photo editor', 'Looks, retouch, effects and text on a photo', 'looks', true),
    ];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, scroll) => ListView(
          controller: scroll,
          children: [
            const StudioSheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('All tools', style: GoogleFonts.inter(color: ctx.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            for (final t in tools)
              ListTile(
                dense: true,
                leading: Icon(t.$1, color: AppColors.brandBlue, size: 22),
                title: Text(t.$2, style: GoogleFonts.inter(color: ctx.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700)),
                subtitle: Text(t.$3, style: GoogleFonts.inter(color: ctx.textMuted, fontSize: 11.5)),
                onTap: () {
                  Navigator.pop(ctx);
                  start(context, photo: t.$5, tool: t.$4);
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Opens the picker for [tool] once, when Studio was opened for a tool.
class _AutoStart extends StatefulWidget {
  final String tool;
  const _AutoStart({required this.tool});

  @override
  State<_AutoStart> createState() => _AutoStartState();
}

class _AutoStartState extends State<_AutoStart> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final photo = widget.tool == 'retouch_photo';
      StudioHomeScreen.start(context, photo: photo, tool: photo ? 'retouch' : widget.tool);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _HeroCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _HeroCard({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        height: 132,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(AppColors.brandBlue, AppColors.brandWhite, 0.25)!, AppColors.brandBlue],
          ),
        ),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.brandWhite, borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: Icon(icon, color: AppColors.brandBlue, size: 26),
              ),
              const SizedBox(height: 10),
              Text(label, style: GoogleFonts.inter(color: AppColors.brandWhite, fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ToolTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1.15,
            child: Container(
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: context.border),
              ),
              child: Icon(icon, color: context.textPrimary, size: 26),
            ),
          ),
          const SizedBox(height: 6),
          Text(label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: context.textPrimary, fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.15)),
        ],
      ),
    );
  }
}

class _ProjectRow extends ConsumerWidget {
  final StudioProject project;
  const _ProjectRow({required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = project;
    final missing = p.clips.any((c) => !File(c.path).existsSync());
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () {
        if (missing) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Some media in this project was removed from the device.')),
          );
        }
        context.push('/create/studio/editor', extra: StudioEditorArgs(project: p));
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: SizedBox(
                width: 64,
                height: 64,
                child: p.thumbnailPath != null && File(p.thumbnailPath!).existsSync()
                    ? Image.file(File(p.thumbnailPath!), fit: BoxFit.cover, cacheWidth: 200)
                    : ColoredBox(color: context.surfaceMid, child: Icon(Icons.movie_outlined, color: context.textMuted)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    [
                      p.isPhoto ? 'Photo' : studioClock(p.durationMs),
                      if (!p.isPhoto) '${p.clips.length} clip${p.clips.length == 1 ? '' : 's'}',
                      timeago.format(p.updatedAt),
                    ].join('  ·  '),
                    style: GoogleFonts.inter(color: context.textMuted, fontSize: 11.5),
                  ),
                  if (missing)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('Media missing', style: GoogleFonts.inter(color: AppColors.brandPink, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz_rounded, color: context.textSecondary),
              color: context.surface,
              onSelected: (v) async {
                final store = ref.read(studioProjectStoreProvider.notifier);
                if (v == 'dup') {
                  await store.duplicate(p);
                } else if (v == 'delete') {
                  final ok = await studioConfirm(
                    context,
                    title: 'Delete project?',
                    message: '"${p.title}" will be removed from Projects. Your original photos and videos stay in your gallery.',
                    confirmLabel: 'Delete',
                  );
                  if (ok) await store.delete(p.id);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'dup', child: Text('Duplicate', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13))),
                PopupMenuItem(value: 'delete', child: Text('Delete', style: GoogleFonts.inter(color: AppColors.brandPink, fontSize: 13))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Scrub a video and grab one frame as a still.
class _FramePicker extends StatefulWidget {
  final StudioClip clip;
  const _FramePicker({required this.clip});

  @override
  State<_FramePicker> createState() => _FramePickerState();
}

class _FramePickerState extends State<_FramePicker> {
  double _ms = 0;
  String? _preview;
  bool _busy = false;
  int _token = 0;

  StudioClip get clip => widget.clip;

  @override
  void initState() {
    super.initState();
    _grab();
  }

  Future<void> _grab() async {
    final token = ++_token;
    final dir = await StudioProjectStore.dir('media');
    final out = '${dir.path}/cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      final path = await OneovaMediaEngine.frame(clip.path, ms: _ms.round(), out: out);
      if (mounted && token == _token) setState(() => _preview = path);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brandBlack,
      appBar: AppBar(
        backgroundColor: AppColors.brandBlack,
        foregroundColor: AppColors.brandWhite,
        title: Text('Choose a frame', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _preview == null
                    ? const CircularProgressIndicator(color: AppColors.brandBlue)
                    : Image.file(File(_preview!), gaplessPlayback: true),
              ),
            ),
            Slider(
              value: _ms,
              max: clip.sourceDurationMs.toDouble().clamp(1, double.infinity),
              activeColor: AppColors.brandBlue,
              onChanged: (v) => setState(() => _ms = v),
              onChangeEnd: (_) => _grab(),
            ),
            Text(studioClockFine(_ms.round()), style: GoogleFonts.inter(color: AppColors.brandWhite, fontSize: 12)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: StudioPrimaryButton(
                  label: 'Use this frame',
                  busy: _busy,
                  onTap: _preview == null
                      ? null
                      : () {
                          setState(() => _busy = true);
                          Navigator.pop(context, _preview);
                        },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
