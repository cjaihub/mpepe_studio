import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../../shared/theme/app_theme.dart';
import '../widgets/studio_ui.dart';

/// What the picker hands back to Studio.
class StudioPick {
  final String path;
  final bool isImage;
  final int durationMs;
  final int width;
  final int height;
  final int startMs;
  final int endMs;

  const StudioPick({
    required this.path,
    required this.isImage,
    required this.durationMs,
    required this.width,
    required this.height,
    this.startMs = 0,
    required this.endMs,
  });
}

class StudioPickResult {
  final List<StudioPick> picks;

  /// "HD" on: export at the media's own resolution instead of 720p.
  final bool hd;
  const StudioPickResult(this.picks, this.hd);
}

enum StudioPickMode { any, video, photo }

/// Gallery picker: albums, Videos / Photos tabs, numbered multi-select with
/// durations, HD toggle, and a full-screen preview with trim before adding.
class StudioMediaPickerScreen extends StatefulWidget {
  final StudioPickMode mode;
  final bool multiple;
  final String actionLabel;

  const StudioMediaPickerScreen({
    super.key,
    this.mode = StudioPickMode.any,
    this.multiple = true,
    this.actionLabel = 'Add',
  });

  @override
  State<StudioMediaPickerScreen> createState() => _StudioMediaPickerScreenState();
}

class _StudioMediaPickerScreenState extends State<StudioMediaPickerScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  PermissionState? _permission;
  List<AssetPathEntity> _albums = const [];
  final Map<int, AssetPathEntity?> _album = {0: null, 1: null};
  final Map<int, List<AssetEntity>> _assets = {0: [], 1: []};
  final Map<int, int> _page = {0: 0, 1: 0};
  final Map<int, bool> _hasMore = {0: true, 1: true};
  final Map<int, bool> _loading = {0: false, 1: false};
  final List<AssetEntity> _selected = [];
  final Map<String, (int, int)> _trims = {};
  bool _hd = true;
  bool _resolving = false;

  bool get _showVideos => widget.mode != StudioPickMode.photo;
  bool get _showPhotos => widget.mode != StudioPickMode.video;
  List<int> get _tabKinds => [if (_showVideos) 0, if (_showPhotos) 1];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabKinds.length, vsync: this)..addListener(() => setState(() {}));
    _init();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final state = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    setState(() => _permission = state);
    if (!state.hasAccess) return;
    final type = switch (widget.mode) {
      StudioPickMode.video => RequestType.video,
      StudioPickMode.photo => RequestType.image,
      StudioPickMode.any => RequestType.common,
    };
    final albums = await PhotoManager.getAssetPathList(type: type);
    if (!mounted) return;
    setState(() => _albums = albums);
    for (final kind in _tabKinds) {
      await _loadMore(kind, reset: true);
    }
  }

  Future<AssetPathEntity?> _pathFor(int kind) async {
    final chosen = _album[kind];
    final type = kind == 0 ? RequestType.video : RequestType.image;
    if (chosen == null) {
      final all = await PhotoManager.getAssetPathList(type: type, onlyAll: true);
      return all.isEmpty ? null : all.first;
    }
    // Same album, filtered to this tab's media type.
    final typed = await PhotoManager.getAssetPathList(type: type);
    for (final p in typed) {
      if (p.id == chosen.id) return p;
    }
    return null;
  }

  Future<void> _loadMore(int kind, {bool reset = false}) async {
    if (_loading[kind] == true) return;
    if (!reset && _hasMore[kind] != true) return;
    _loading[kind] = true;
    if (reset) {
      _page[kind] = 0;
      _hasMore[kind] = true;
      _assets[kind] = [];
    }
    final path = await _pathFor(kind);
    if (path == null) {
      _loading[kind] = false;
      if (mounted) setState(() => _hasMore[kind] = false);
      return;
    }
    final page = await path.getAssetListPaged(page: _page[kind]!, size: 60);
    _loading[kind] = false;
    if (!mounted) return;
    setState(() {
      _assets[kind] = [..._assets[kind]!, ...page];
      _page[kind] = _page[kind]! + 1;
      _hasMore[kind] = page.length == 60;
    });
  }

  void _toggle(AssetEntity a) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.any((e) => e.id == a.id)) {
        _selected.removeWhere((e) => e.id == a.id);
      } else if (widget.multiple) {
        _selected.add(a);
      } else {
        _selected
          ..clear()
          ..add(a);
      }
    });
  }

  Future<void> _preview(AssetEntity a) async {
    final file = await a.file;
    if (file == null || !mounted) return;
    final res = await Navigator.of(context).push<(int, int)?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _StudioAssetPreview(
          file: file,
          isVideo: a.type == AssetType.video,
          trim: _trims[a.id],
          actionLabel: widget.multiple ? 'Add' : widget.actionLabel,
        ),
      ),
    );
    if (res == null || !mounted) return;
    setState(() {
      if (res.$2 > 0) {
        _trims[a.id] = res;
      } else {
        _trims.remove(a.id);
      }
      if (!_selected.any((e) => e.id == a.id)) {
        if (!widget.multiple) _selected.clear();
        _selected.add(a);
      }
    });
    if (!widget.multiple) _finish();
  }

  Future<void> _finish() async {
    if (_selected.isEmpty || _resolving) return;
    setState(() => _resolving = true);
    final picks = <StudioPick>[];
    for (final a in _selected) {
      final file = await a.originFile ?? await a.file;
      if (file == null) continue;
      final isImage = a.type == AssetType.image;
      final durationMs = isImage ? 0 : a.videoDuration.inMilliseconds;
      final trim = _trims[a.id];
      picks.add(StudioPick(
        path: file.path,
        isImage: isImage,
        durationMs: durationMs,
        width: a.orientatedWidth,
        height: a.orientatedHeight,
        startMs: trim?.$1 ?? 0,
        endMs: trim?.$2 ?? durationMs,
      ));
    }
    if (!mounted) return;
    setState(() => _resolving = false);
    if (picks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Those files are not available on this device.')));
      return;
    }
    context.pop(StudioPickResult(picks, _hd));
  }

  Future<void> _chooseAlbum() async {
    final kind = _tabKinds[_tabs.index];
    final picked = await showModalBottomSheet<AssetPathEntity?>(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const StudioSheetHandle(),
            for (final album in _albums)
              ListTile(
                dense: true,
                leading: Icon(album.isAll ? Icons.photo_library_rounded : Icons.folder_rounded, color: AppColors.brandBlue, size: 20),
                title: Text(album.isAll ? 'Recents' : album.name,
                    style: GoogleFonts.inter(color: ctx.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600)),
                trailing: FutureBuilder<int>(
                  future: album.assetCountAsync,
                  builder: (_, s) => Text('${s.data ?? ''}', style: GoogleFonts.inter(color: ctx.textMuted, fontSize: 12)),
                ),
                onTap: () => Navigator.pop(ctx, album),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _album[kind] = picked.isAll ? null : picked);
    await _loadMore(kind, reset: true);
  }

  String _albumLabel() {
    if (_tabKinds.isEmpty) return 'Albums';
    final a = _album[_tabKinds[_tabs.index]];
    return a == null ? 'Recents' : a.name;
  }

  @override
  Widget build(BuildContext context) {
    final p = _permission;
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        toolbarHeight: 50,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: GestureDetector(
          onTap: _albums.isEmpty ? null : _chooseAlbum,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_albumLabel(), style: GoogleFonts.inter(color: context.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, color: context.textPrimary, size: 20),
            ],
          ),
        ),
        bottom: _tabKinds.length < 2
            ? null
            : TabBar(
                controller: _tabs,
                indicatorColor: AppColors.brandBlue,
                labelColor: context.textPrimary,
                unselectedLabelColor: context.textMuted,
                labelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
                tabs: [
                  if (_showVideos) const Tab(text: 'Videos', height: 40),
                  if (_showPhotos) const Tab(text: 'Photos', height: 40),
                ],
              ),
      ),
      body: p == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.brandBlue))
          : !p.hasAccess
              ? _permissionPrompt()
              : TabBarView(controller: _tabs, children: [for (final k in _tabKinds) _grid(k)]),
      bottomNavigationBar: p?.hasAccess == true ? _bottomBar() : null,
    );
  }

  Widget _permissionPrompt() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_library_outlined, size: 44, color: context.textMuted),
              const SizedBox(height: 12),
              Text('Allow access to your photos and videos',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: context.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Studio needs it to show your gallery here.',
                  textAlign: TextAlign.center, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12.5)),
              const SizedBox(height: 16),
              StudioPrimaryButton(
                label: 'Open settings',
                onTap: () async {
                  await PhotoManager.openSetting();
                  _init();
                },
              ),
            ],
          ),
        ),
      );

  Widget _grid(int kind) {
    final items = _assets[kind]!;
    if (items.isEmpty) {
      return Center(
        child: _loading[kind] == true || _hasMore[kind] == true
            ? const CircularProgressIndicator(color: AppColors.brandBlue)
            : Text(kind == 0 ? 'No videos here' : 'No photos here',
                style: GoogleFonts.inter(color: context.textMuted, fontSize: 13)),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) _loadMore(kind);
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(2),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final a = items[i];
          final order = _selected.indexWhere((e) => e.id == a.id);
          return _AssetTile(
            asset: a,
            order: order,
            trimmed: _trims[a.id],
            onTap: () => _preview(a),
            onSelect: () => _toggle(a),
          );
        },
      ),
    );
  }

  Widget _bottomBar() {
    final count = _selected.length;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(color: context.surface, border: Border(top: BorderSide(color: context.border))),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final a in _selected)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                          child: SizedBox(width: 44, height: 44, child: _Thumb(asset: a)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _hd = !_hd),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Icon(_hd ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: 18, color: _hd ? AppColors.brandBlue : context.textMuted),
                    const SizedBox(width: 4),
                    Text('HD', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            StudioPrimaryButton(
              label: count == 0 ? widget.actionLabel : '${widget.actionLabel} ($count)',
              busy: _resolving,
              onTap: count == 0 ? null : _finish,
            ),
          ],
        ),
      ),
    );
  }
}

final Map<String, Uint8List?> _thumbCache = {};

class _Thumb extends StatelessWidget {
  final AssetEntity asset;
  const _Thumb({required this.asset});

  @override
  Widget build(BuildContext context) {
    final cached = _thumbCache[asset.id];
    if (cached != null) return Image.memory(cached, fit: BoxFit.cover, gaplessPlayback: true);
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(const ThumbnailSize.square(240), quality: 80),
      builder: (_, s) {
        if (s.data == null) return ColoredBox(color: context.surfaceMid);
        _thumbCache[asset.id] = s.data;
        return Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }
}

class _AssetTile extends StatelessWidget {
  final AssetEntity asset;
  final int order;
  final (int, int)? trimmed;
  final VoidCallback onTap;
  final VoidCallback onSelect;

  const _AssetTile({required this.asset, required this.order, required this.trimmed, required this.onTap, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final selected = order >= 0;
    final isVideo = asset.type == AssetType.video;
    final ms = trimmed != null ? trimmed!.$2 - trimmed!.$1 : asset.videoDuration.inMilliseconds;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Thumb(asset: asset),
          if (selected) ColoredBox(color: AppColors.brandBlack.withValues(alpha: 0.35)),
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSelect,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppColors.brandBlue : AppColors.brandBlack.withValues(alpha: 0.2),
                    border: Border.all(color: AppColors.brandWhite, width: 1.5),
                  ),
                  child: selected
                      ? Text('${order + 1}',
                          style: GoogleFonts.inter(color: AppColors.brandWhite, fontSize: 11, fontWeight: FontWeight.w800))
                      : null,
                ),
              ),
            ),
          ),
          if (isVideo)
            Positioned(
              right: 6,
              bottom: 4,
              child: Row(
                children: [
                  if (trimmed != null) const Icon(Icons.content_cut_rounded, size: 11, color: AppColors.brandWhite),
                  const SizedBox(width: 2),
                  Text(studioClock(ms),
                      style: GoogleFonts.inter(
                        color: AppColors.brandWhite,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        shadows: const [Shadow(blurRadius: 4)],
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Full-screen look at one item, with optional trim, before adding it.
class _StudioAssetPreview extends StatefulWidget {
  final File file;
  final bool isVideo;
  final (int, int)? trim;
  final String actionLabel;

  const _StudioAssetPreview({required this.file, required this.isVideo, required this.trim, required this.actionLabel});

  @override
  State<_StudioAssetPreview> createState() => _StudioAssetPreviewState();
}

class _StudioAssetPreviewState extends State<_StudioAssetPreview> {
  VideoPlayerController? _video;
  bool _trimming = false;
  RangeValues? _range;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _video = VideoPlayerController.file(widget.file)
        ..initialize().then((_) {
          if (!mounted) return;
          final d = _video!.value.duration.inMilliseconds.toDouble();
          final t = widget.trim;
          setState(() => _range = t == null ? RangeValues(0, d) : RangeValues(t.$1.toDouble(), t.$2.toDouble()));
          _video!
            ..setLooping(true)
            ..addListener(_loopInRange)
            ..play();
        });
    }
  }

  void _loopInRange() {
    final v = _video, r = _range;
    if (v == null || r == null || !v.value.isPlaying) return;
    final pos = v.value.position.inMilliseconds;
    if (pos >= r.end || pos < r.start - 250) v.seekTo(Duration(milliseconds: r.start.round()));
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    final total = v?.value.duration.inMilliseconds ?? 0;
    final r = _range;
    return Scaffold(
      backgroundColor: AppColors.brandBlack,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.brandWhite, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Expanded(
              child: Center(
                child: widget.isVideo
                    ? (v != null && v.value.isInitialized
                        ? GestureDetector(
                            onTap: () => setState(() => v.value.isPlaying ? v.pause() : v.play()),
                            child: AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v)),
                          )
                        : const CircularProgressIndicator(color: AppColors.brandBlue))
                    : Image.file(widget.file, fit: BoxFit.contain),
              ),
            ),
            if (v != null && r != null) ...[
              if (_trimming)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      RangeSlider(
                        values: r,
                        min: 0,
                        max: total.toDouble(),
                        activeColor: AppColors.brandBlue,
                        inactiveColor: AppColors.brandWhite.withValues(alpha: 0.2),
                        onChanged: (nr) {
                          if (nr.end - nr.start < 500) return;
                          setState(() => _range = nr);
                          v.seekTo(Duration(milliseconds: (nr.start != r.start ? nr.start : nr.end).round()));
                        },
                        onChangeEnd: (_) => v.seekTo(Duration(milliseconds: _range!.start.round())),
                      ),
                      Text('${studioClock(r.start.round())} – ${studioClock(r.end.round())}  ·  ${studioClock((r.end - r.start).round())}',
                          style: GoogleFonts.inter(color: AppColors.brandWhite, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                )
              else
                Slider(
                  value: v.value.position.inMilliseconds.clamp(0, total).toDouble(),
                  max: total <= 0 ? 1 : total.toDouble(),
                  activeColor: AppColors.brandWhite,
                  inactiveColor: AppColors.brandWhite.withValues(alpha: 0.25),
                  onChanged: (x) => v.seekTo(Duration(milliseconds: x.round())),
                ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  if (widget.isVideo)
                    TextButton.icon(
                      onPressed: r == null ? null : () => setState(() => _trimming = !_trimming),
                      icon: Icon(_trimming ? Icons.check_rounded : Icons.content_cut_rounded, color: AppColors.brandWhite, size: 20),
                      label: Text(_trimming ? 'Done' : 'Trim',
                          style: GoogleFonts.inter(color: AppColors.brandWhite, fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  const Spacer(),
                  StudioPrimaryButton(
                    label: widget.actionLabel,
                    onTap: () {
                      final rr = _range;
                      final trimmed = rr != null && (rr.start > 0 || rr.end < total);
                      Navigator.pop(context, trimmed ? (rr.start.round(), rr.end.round()) : (0, 0));
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
