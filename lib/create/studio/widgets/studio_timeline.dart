import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/studio_project.dart';
import '../services/studio_effects.dart';
import '../services/studio_media.dart';
import '../services/studio_playback.dart';
import 'studio_ui.dart';

/// Horizontal timeline with a fixed center playhead. Scrolling scrubs;
/// playback scrolls it. Rows: ruler, clips (thumbnails, trim handles),
/// text & captions, audio.
class StudioTimeline extends StatefulWidget {
  final StudioPlayback playback;
  final StudioProject project;
  final String? selectedClipId;
  final String? selectedTextId;
  final String? selectedAudioId;
  final String? selectedEffectId;
  final String? selectedOverlayId;
  final ValueChanged<String?> onSelectClip;
  final ValueChanged<String?> onSelectText;
  final ValueChanged<String?> onSelectAudio;
  final ValueChanged<String?>? onSelectEffect;
  final ValueChanged<String?>? onSelectOverlay;

  /// Live trim while dragging a handle (not yet committed to history).
  final void Function(StudioClip clip) onTrimPreview;
  final VoidCallback onTrimCommit;
  final VoidCallback onAddClip;
  final VoidCallback onAddAudio;
  final VoidCallback onAddText;
  final VoidCallback? onAddEffect;
  final VoidCallback? onAddOverlay;
  final VoidCallback onCover;
  final VoidCallback onToggleMuteAll;

  /// New clip order after a drag (long-press a clip to start).
  final ValueChanged<List<StudioClip>>? onReorderClips;

  /// Live/commit updates for dragging and stretching layered tracks directly on the timeline.
  final void Function(StudioText text, {bool commit})? onUpdateText;
  final void Function(StudioAudio audio, {bool commit})? onUpdateAudio;
  final void Function(StudioOverlay overlay, {bool commit})? onUpdateOverlay;
  final void Function(StudioEffect effect, {bool commit})? onUpdateEffect;

  /// Quick actions triggered from the timeline terminal bar.
  final VoidCallback? onSplitAtPlayhead;
  final VoidCallback? onAlignToPlayhead;
  final VoidCallback? onFitDuration;
  final VoidCallback? onOpenAiGrade;
  final VoidCallback? onDuplicateSelected;

  const StudioTimeline({
    super.key,
    required this.playback,
    required this.project,
    required this.selectedClipId,
    required this.selectedTextId,
    required this.selectedAudioId,
    this.selectedEffectId,
    this.selectedOverlayId,
    required this.onSelectClip,
    required this.onSelectText,
    required this.onSelectAudio,
    this.onSelectEffect,
    this.onSelectOverlay,
    required this.onTrimPreview,
    required this.onTrimCommit,
    required this.onAddClip,
    required this.onAddAudio,
    required this.onAddText,
    this.onAddEffect,
    this.onAddOverlay,
    required this.onCover,
    required this.onToggleMuteAll,
    this.onReorderClips,
    this.onUpdateText,
    this.onUpdateAudio,
    this.onUpdateOverlay,
    this.onUpdateEffect,
    this.onSplitAtPlayhead,
    this.onAlignToPlayhead,
    this.onFitDuration,
    this.onOpenAiGrade,
    this.onDuplicateSelected,
  });

  @override
  State<StudioTimeline> createState() => _StudioTimelineState();
}

class _StudioTimelineState extends State<StudioTimeline> {
  final _scroll = ScrollController();
  double _pps = 64; // pixels per second
  double _ppsAtScaleStart = 64;
  bool _userScrolling = false;
  bool _programmatic = false;
  bool _stretchMode = false;
  bool _snapEnabled = true;
  int? _snapLineMs;

  /// Clip order while the reorder strip is open (null when closed).
  List<StudioClip>? _order;

  static const _clipH = 50.0;
  static const _rowH = 24.0;

  @override
  void initState() {
    super.initState();
    // Long videos open zoomed out so about 90 seconds fit the strip.
    final secs = widget.project.durationMs / 1000;
    if (secs > 90) _pps = (5400 / secs).clamp(4.0, 64.0);
    widget.playback.addListener(_followPlayhead);
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant StudioTimeline old) {
    super.didUpdateWidget(old);
    if (old.playback != widget.playback) {
      old.playback.removeListener(_followPlayhead);
      widget.playback.addListener(_followPlayhead);
    }
  }

  @override
  void dispose() {
    widget.playback.removeListener(_followPlayhead);
    _scroll.dispose();
    super.dispose();
  }

  double _x(int ms) => ms / 1000 * _pps;

  void _followPlayhead() {
    if (_userScrolling || !_scroll.hasClients) return;
    final target = _x(widget.playback.posMs);
    if ((target - _scroll.offset).abs() < 0.5) return;
    _programmatic = true;
    _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
    _programmatic = false;
  }

  void _onScroll() {
    if (_programmatic || !_userScrolling) return;
    widget.playback.seek((_scroll.offset / _pps * 1000).round());
  }

  /// Collects all magnetic alignment snap targets (playhead, clip edges, beats, layer boundaries).
  List<int> _snapTargets({String? ignoreId}) {
    final p = widget.project;
    final pts = <int>{0, widget.playback.posMs, p.durationMs};
    var acc = 0;
    for (final c in p.clips) {
      pts.add(acc);
      acc += c.outDurationMs;
      pts.add(acc);
    }
    for (final a in p.audios) {
      if (a.id != ignoreId) {
        pts.add(a.offsetMs);
        pts.add(a.offsetMs + a.durationMs);
      }
      pts.addAll(a.timelineBeats);
    }
    for (final t in p.texts) {
      if (t.id == ignoreId) continue;
      pts.add(t.startMs);
      pts.add(t.endMs);
    }
    for (final o in p.overlays) {
      if (o.id == ignoreId) continue;
      pts.add(o.offsetMs);
      pts.add(o.endOnTimeline);
    }
    for (final e in p.effects) {
      if (e.id == ignoreId) continue;
      pts.add(e.startMs);
      pts.add(e.endMs);
    }
    return pts.toList();
  }

  /// Snaps [candidateMs] to the nearest alignment target if within ~9px.
  int _snapMs(int candidateMs, {String? ignoreId}) {
    if (!_snapEnabled) {
      if (_snapLineMs != null) setState(() => _snapLineMs = null);
      return candidateMs;
    }
    final thresholdMs = (9.0 / _pps * 1000).round().clamp(30, 350);
    int? best;
    var bestDist = thresholdMs + 1;
    for (final pt in _snapTargets(ignoreId: ignoreId)) {
      final d = (candidateMs - pt).abs();
      if (d <= thresholdMs && d < bestDist) {
        bestDist = d;
        best = pt;
      }
    }
    if (best != null) {
      if (_snapLineMs != best) {
        HapticFeedback.selectionClick();
        setState(() => _snapLineMs = best);
      }
      return best;
    }
    if (_snapLineMs != null) setState(() => _snapLineMs = null);
    return candidateMs;
  }

  void _clearSnapLine() {
    if (_snapLineMs != null) setState(() => _snapLineMs = null);
  }

  Widget _quickActionsBar() {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(
          top: BorderSide(color: context.border, width: 0.8),
          bottom: BorderSide(color: context.border, width: 0.8),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        children: [
          _quickChip(
            icon: Icons.open_in_full_rounded,
            label: _stretchMode ? 'Stretch: ON' : 'Stretch',
            active: _stretchMode,
            accent: AppColors.brandPink,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _stretchMode = !_stretchMode);
            },
          ),
          _quickChip(
            icon: Icons.vertical_align_center_rounded,
            label: _snapEnabled ? 'Snap: ON' : 'Snap',
            active: _snapEnabled,
            accent: AppColors.brandBlue,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _snapEnabled = !_snapEnabled);
            },
          ),
          if (widget.onSplitAtPlayhead != null)
            _quickChip(
              icon: Icons.content_cut_rounded,
              label: 'Split',
              onTap: widget.onSplitAtPlayhead!,
            ),
          if (widget.onAlignToPlayhead != null)
            _quickChip(
              icon: Icons.align_horizontal_left_rounded,
              label: 'Align Playhead',
              onTap: widget.onAlignToPlayhead!,
            ),
          if (widget.onFitDuration != null)
            _quickChip(
              icon: Icons.fit_screen_rounded,
              label: 'Fit Timeline',
              onTap: widget.onFitDuration!,
            ),
          if (widget.onOpenAiGrade != null)
            _quickChip(
              icon: Icons.auto_awesome_rounded,
              label: 'AI Grade',
              active: true,
              accent: AppColors.brandPink,
              onTap: widget.onOpenAiGrade!,
            ),
          if (widget.onDuplicateSelected != null)
            _quickChip(
              icon: Icons.copy_all_rounded,
              label: 'Duplicate',
              onTap: widget.onDuplicateSelected!,
            ),
          _quickChip(
            icon: Icons.zoom_out_rounded,
            label: 'Zoom -',
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _pps = (_pps * 0.75).clamp(2.0, 320.0));
              WidgetsBinding.instance.addPostFrameCallback((_) => _followPlayhead());
            },
          ),
          _quickChip(
            icon: Icons.zoom_in_rounded,
            label: 'Zoom +',
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _pps = (_pps * 1.33).clamp(2.0, 320.0));
              WidgetsBinding.instance.addPostFrameCallback((_) => _followPlayhead());
            },
          ),
        ],
      ),
    );
  }

  Widget _quickChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    Color? accent,
  }) {
    final activeColor = accent ?? AppColors.brandBlue;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: active ? activeColor.withValues(alpha: 0.18) : context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: active ? activeColor : context.border,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: active ? activeColor : context.textSecondary),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: active ? activeColor : context.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final total = p.durationMs;
    return LayoutBuilder(builder: (context, box) {
      final half = box.maxWidth / 2;
      final contentW = _x(total);
      return Column(
        children: [
          _quickActionsBar(),
          Expanded(
            child: GestureDetector(
              onScaleStart: (_) => _ppsAtScaleStart = _pps,
              onScaleUpdate: (d) {
                if (d.pointerCount < 2) return;
                setState(() => _pps = (_ppsAtScaleStart * d.horizontalScale).clamp(2.0, 320.0));
                WidgetsBinding.instance.addPostFrameCallback((_) => _followPlayhead());
              },
              child: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n is ScrollStartNotification && n.dragDetails != null) {
                        _userScrolling = true;
                        if (widget.playback.playing) widget.playback.pause();
                      } else if (n is ScrollEndNotification) {
                        _userScrolling = false;
                      }
                      return false;
                    },
                    child: SingleChildScrollView(
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: SizedBox(
                        width: contentW + half * 2,
                        child: Stack(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(height: 20, child: _ruler(half, total)),
                                const SizedBox(height: 4),
                                SizedBox(height: _clipH + 6, child: _clipRow(half)),
                                const SizedBox(height: 4),
                                SizedBox(height: _rowH, child: _textRow(half)),
                                const SizedBox(height: 3),
                                SizedBox(height: _rowH, child: _audioRow(half)),
                                if (widget.onSelectOverlay != null) ...[
                                  const SizedBox(height: 3),
                                  SizedBox(height: _rowH - 2, child: _overlayRow(half)),
                                ],
                                if (widget.onSelectEffect != null) ...[
                                  const SizedBox(height: 3),
                                  SizedBox(height: _rowH - 2, child: _effectRow(half)),
                                ],
                              ],
                            ),
                            if (_snapLineMs != null)
                              Positioned(
                                left: half + _x(_snapLineMs!),
                                top: 0,
                                bottom: 0,
                                child: IgnorePointer(
                                  child: Container(
                                    width: 1.8,
                                    decoration: BoxDecoration(
                                      color: AppColors.brandPink,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.brandPink.withValues(alpha: 0.7),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Playhead
                  Positioned(
                    left: half - 1,
                    top: 16,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        width: 2,
                        decoration: BoxDecoration(
                          color: AppColors.brandWhite,
                          borderRadius: BorderRadius.circular(1),
                          boxShadow: [BoxShadow(color: AppColors.brandBlack.withValues(alpha: 0.4), blurRadius: 3)],
                        ),
                      ),
                    ),
                  ),
                  if (_order != null) Positioned.fill(child: _reorderStrip()),
                  // Add clip
                  if (_order == null)
                    Positioned(
                      right: 10,
                      top: 24 + (_clipH - 38) / 2 + 2,
                      child: Material(
                        color: AppColors.brandWhite,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        elevation: 2,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            widget.onAddClip();
                          },
                          child: const SizedBox(width: 38, height: 38, child: Icon(Icons.add_rounded, color: AppColors.brandBlack, size: 24)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _ruler(double half, int total) {
    return CustomPaint(
      size: Size(_x(total) + half * 2, 22),
      painter: _RulerPainter(
        left: half,
        pps: _pps,
        totalMs: total,
        color: context.textMuted,
        style: GoogleFonts.inter(fontSize: 10, color: context.textMuted, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _clipRow(double half) {
    final p = widget.project;
    final allMuted = p.clips.where((c) => !c.isImage).every((c) => c.muted);
    final children = <Widget>[
      // Leading tools, like the reference: mute all + cover.
      Positioned(
        left: math.max(0, half - 132),
        top: 4,
        child: Row(
          children: [
            _leadButton(allMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, allMuted ? 'Unmute' : 'Mute clip',
                widget.onToggleMuteAll),
            const SizedBox(width: 8),
            _leadButton(Icons.image_outlined, 'Cover', widget.onCover),
          ],
        ),
      ),
    ];
    var start = 0;
    for (final clip in p.clips) {
      final w = _x(clip.outDurationMs);
      final selected = clip.id == widget.selectedClipId;
      children.add(Positioned(
        left: half + _x(start),
        top: 4,
        width: math.max(2, w),
        height: _clipH,
        child: GestureDetector(
          onTap: () => widget.onSelectClip(selected ? null : clip.id),
          onLongPress: widget.onReorderClips == null || p.clips.length < 2
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  if (widget.playback.playing) widget.playback.pause();
                  setState(() => _order = [...p.clips]);
                },
          child: _ClipStrip(clip: clip, width: w, pps: _pps, selected: selected),
        ),
      ));
      if (selected) {
        children.add(_handleImpl(half + _x(start) - 14, clip, true));
        children.add(_handleImpl(half + _x(start) + w, clip, false));
      }
      start += clip.outDurationMs;
    }
    return Stack(clipBehavior: Clip.none, children: children);
  }

  /// Equal-size clip tiles to drag into a new order; Done commits it.
  Widget _reorderStrip() {
    final order = _order!;
    return Container(
      color: context.surface,
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.drag_indicator_rounded, size: 16, color: context.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Drag clips to change their order',
                    style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: () => setState(() => _order = null),
                child: Text('Cancel', style: GoogleFonts.inter(color: context.textMuted, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  final changed = [for (var i = 0; i < order.length; i++) order[i].id != widget.project.clips[i].id].any((d) => d);
                  if (changed) widget.onReorderClips?.call(order);
                  setState(() => _order = null);
                },
                child: Text('Done', style: GoogleFonts.inter(color: AppColors.brandBlue, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          SizedBox(
            height: 80,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              itemCount: order.length,
              proxyDecorator: (child, _, _) => Material(color: Colors.transparent, elevation: 6, child: child),
              onReorderItem: (from, to) {
                HapticFeedback.selectionClick();
                setState(() {
                  final c = order.removeAt(from);
                  order.insert(to, c);
                });
              },
              itemBuilder: (context, i) {
                final clip = order[i];
                return ReorderableDragStartListener(
                  key: ValueKey(clip.id),
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 64,
                      child: Column(
                        children: [
                          SizedBox(
                            width: 64,
                            height: 56,
                            child: _ClipStrip(clip: clip, width: 64, pps: _pps, selected: false),
                          ),
                          const SizedBox(height: 3),
                          Text('${i + 1} · ${studioClock(clip.outDurationMs)}',
                              style: GoogleFonts.inter(color: context.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _leadButton(IconData icon, String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 58,
          height: _clipH,
          decoration: BoxDecoration(color: context.surfaceMid, borderRadius: BorderRadius.circular(AppRadius.sm)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: context.textPrimary),
              const SizedBox(height: 3),
              Text(label, style: GoogleFonts.inter(fontSize: 9.5, color: context.textSecondary, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  Widget _handleImpl(double left, StudioClip clip, bool isLeft) {
    final p = widget.project;
    final clipIdx = p.clips.indexWhere((c) => c.id == clip.id);
    final clipStartOut = clipIdx >= 0 ? p.clipStartMs(clipIdx) : 0;

    return Positioned(
      left: left,
      top: 4,
      width: 14,
      height: _clipH,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragUpdate: (d) {
          final current = widget.project.clips.firstWhere((c) => c.id == clip.id, orElse: () => clip);
          final deltaOut = d.delta.dx / _pps * 1000;
          if (current.isImage) {
            final rawNext = (current.imageDurationMs + (isLeft ? -deltaOut : deltaOut)).round().clamp(500, 60000);
            final snappedEnd = _snapMs(clipStartOut + rawNext, ignoreId: current.id);
            final next = (snappedEnd - clipStartOut).clamp(500, 60000);
            widget.onTrimPreview(current.copyWith(imageDurationMs: next));
            return;
          }

          // Time-Stretch Mode OR dragging right handle beyond sourceDurationMs stretches clip via speed!
          final srcLen = math.max(300, current.endMs - current.startMs);
          final wantStretch = _stretchMode || (!isLeft && current.endMs >= current.sourceDurationMs && deltaOut > 0);
          if (wantStretch) {
            final curOut = current.outDurationMs;
            final rawNewOut = (curOut + (isLeft ? -deltaOut : deltaOut)).round().clamp(300, srcLen * 5);
            final snappedEnd = _snapMs(clipStartOut + rawNewOut, ignoreId: current.id);
            final newOut = (snappedEnd - clipStartOut).clamp(300, srcLen * 5);
            final newSpeed = (srcLen / newOut).clamp(0.2, 4.0);
            widget.onTrimPreview(current.copyWith(speed: double.parse(newSpeed.toStringAsFixed(3))));
            return;
          }

          final deltaSrc = (deltaOut * current.speed).round();
          if (isLeft) {
            final s = (current.startMs + deltaSrc).clamp(0, current.endMs - 300);
            widget.onTrimPreview(current.copyWith(startMs: s));
          } else {
            final rawE = (current.endMs + deltaSrc).clamp(current.startMs + 300, current.sourceDurationMs);
            final rawOutEnd = clipStartOut + ((rawE - current.startMs) / current.speed).round();
            final snappedOutEnd = _snapMs(rawOutEnd, ignoreId: current.id);
            final snappedE = (current.startMs + (snappedOutEnd - clipStartOut) * current.speed)
                .round()
                .clamp(current.startMs + 300, current.sourceDurationMs);
            widget.onTrimPreview(current.copyWith(endMs: snappedE));
          }
        },
        onHorizontalDragEnd: (_) {
          _clearSnapLine();
          widget.onTrimCommit();
        },
        child: Container(
          decoration: BoxDecoration(
            color: _stretchMode ? AppColors.brandPink : AppColors.brandWhite,
            borderRadius: BorderRadius.horizontal(
              left: Radius.circular(isLeft ? 6 : 0),
              right: Radius.circular(isLeft ? 0 : 6),
            ),
          ),
          child: Center(
            child: Container(
              width: 2,
              height: 16,
              color: (_stretchMode ? AppColors.brandWhite : AppColors.brandBlack).withValues(alpha: 0.75),
            ),
          ),
        ),
      ),
    );
  }

  Widget _textRow(double half) {
    final p = widget.project;
    if (p.texts.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(left: half),
        child: _addChip(Icons.title_rounded, 'Add text', widget.onAddText),
      );
    }
    final maxMs = math.max(1000, p.durationMs);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final t in p.texts)
          Positioned(
            left: half + _x(t.startMs),
            width: math.max(18, _x(t.endMs - t.startMs)),
            top: 0,
            bottom: 0,
            child: _trackChip(
              label: t.text.replaceAll('\n', ' '),
              icon: t.isCaption ? Icons.closed_caption_rounded : (t.isSticker ? Icons.emoji_emotions_outlined : Icons.title_rounded),
              color: t.isCaption ? AppColors.brandPink : AppColors.brandBlue,
              selected: t.id == widget.selectedTextId,
              onTap: () => widget.onSelectText(t.id == widget.selectedTextId ? null : t.id),
              onMoveDeltaMs: widget.onUpdateText == null
                  ? null
                  : (deltaMs, commit) {
                      final cur = widget.project.texts.firstWhere((x) => x.id == t.id, orElse: () => t);
                      final dur = math.max(200, cur.endMs - cur.startMs);
                      final rawStart = (cur.startMs + deltaMs).clamp(0, math.max(0, maxMs - dur)).toInt();
                      final snappedStart = commit ? rawStart : _snapMs(rawStart, ignoreId: cur.id);
                      if (commit) _clearSnapLine();
                      widget.onUpdateText!(cur.shifted(snappedStart - cur.startMs), commit: commit);
                    },
              onStretchLeftDeltaMs: widget.onUpdateText == null
                  ? null
                  : (deltaMs, commit) {
                      final cur = widget.project.texts.firstWhere((x) => x.id == t.id, orElse: () => t);
                      final rawStart = (cur.startMs + deltaMs).clamp(0, cur.endMs - 200);
                      final nextStart = commit ? rawStart : _snapMs(rawStart, ignoreId: cur.id).clamp(0, cur.endMs - 200);
                      if (commit) _clearSnapLine();
                      widget.onUpdateText!(cur.copyWith(startMs: nextStart), commit: commit);
                    },
              onStretchRightDeltaMs: widget.onUpdateText == null
                  ? null
                  : (deltaMs, commit) {
                      final cur = widget.project.texts.firstWhere((x) => x.id == t.id, orElse: () => t);
                      final rawEnd = (cur.endMs + deltaMs).clamp(cur.startMs + 200, maxMs);
                      final nextEnd = commit ? rawEnd : _snapMs(rawEnd, ignoreId: cur.id).clamp(cur.startMs + 200, maxMs);
                      if (commit) _clearSnapLine();
                      widget.onUpdateText!(cur.copyWith(endMs: nextEnd), commit: commit);
                    },
            ),
          ),
      ],
    );
  }

  Widget _audioRow(double half) {
    final p = widget.project;
    if (p.audios.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(left: half),
        child: _addChip(Icons.music_note_rounded, 'Add audio', widget.onAddAudio),
      );
    }
    final maxMs = math.max(1000, p.durationMs);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final a in p.audios)
          Positioned(
            left: half + _x(a.offsetMs),
            width: math.max(18, _x(a.durationMs)),
            top: 0,
            bottom: 0,
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                _trackChip(
                  label: a.title,
                  icon: Icons.graphic_eq_rounded,
                  color: AppColors.textMuted,
                  selected: a.id == widget.selectedAudioId,
                  onTap: () => widget.onSelectAudio(a.id == widget.selectedAudioId ? null : a.id),
                  onMoveDeltaMs: widget.onUpdateAudio == null
                      ? null
                      : (deltaMs, commit) {
                          final cur = widget.project.audios.firstWhere((x) => x.id == a.id, orElse: () => a);
                          final rawOffset = (cur.offsetMs + deltaMs).clamp(0, math.max(0, maxMs - 200)).toInt();
                          final nextOffset = commit ? rawOffset : _snapMs(rawOffset, ignoreId: cur.id);
                          if (commit) _clearSnapLine();
                          widget.onUpdateAudio!(cur.copyWith(offsetMs: nextOffset), commit: commit);
                        },
                  onStretchLeftDeltaMs: widget.onUpdateAudio == null
                      ? null
                      : (deltaMs, commit) {
                          final cur = widget.project.audios.firstWhere((x) => x.id == a.id, orElse: () => a);
                          final nextStart = (cur.startMs + deltaMs).clamp(0, cur.endMs - 300);
                          final moved = nextStart - cur.startMs;
                          if (commit) _clearSnapLine();
                          widget.onUpdateAudio!(
                            cur.copyWith(startMs: nextStart, offsetMs: (cur.offsetMs + moved).clamp(0, maxMs)),
                            commit: commit,
                          );
                        },
                  onStretchRightDeltaMs: widget.onUpdateAudio == null
                      ? null
                      : (deltaMs, commit) {
                          final cur = widget.project.audios.firstWhere((x) => x.id == a.id, orElse: () => a);
                          final maxSrc = cur.sourceDurationMs > 0 ? cur.sourceDurationMs : maxMs;
                          final rawEnd = (cur.endMs + deltaMs).clamp(cur.startMs + 300, maxSrc);
                          final snappedTimelineEnd = commit
                              ? (cur.offsetMs + (rawEnd - cur.startMs))
                              : _snapMs(cur.offsetMs + (rawEnd - cur.startMs), ignoreId: cur.id);
                          final nextEnd = (cur.startMs + (snappedTimelineEnd - cur.offsetMs)).clamp(cur.startMs + 300, maxSrc);
                          if (commit) _clearSnapLine();
                          widget.onUpdateAudio!(cur.copyWith(endMs: nextEnd), commit: commit);
                        },
                ),
                // Beat markers.
                for (final b in a.timelineBeats)
                  Positioned(
                    left: _x(b - a.offsetMs) - 1.5,
                    bottom: 2,
                    child: IgnorePointer(
                      child: Container(
                        width: 3,
                        height: 3,
                        decoration: const BoxDecoration(color: AppColors.brandPink, shape: BoxShape.circle),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _overlayRow(double half) {
    final p = widget.project;
    if (p.overlays.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(left: half),
        child: _addChip(Icons.picture_in_picture_alt_rounded, 'Add overlay', widget.onAddOverlay ?? () {}),
      );
    }
    final maxMs = math.max(1000, p.durationMs);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final o in p.overlays)
          Positioned(
            left: half + _x(o.offsetMs),
            width: math.max(18, _x(o.durationMs)),
            top: 0,
            bottom: 0,
            child: _trackChip(
              label: o.isImage ? 'Photo overlay' : 'Video overlay',
              icon: o.isImage ? Icons.image_outlined : Icons.picture_in_picture_alt_rounded,
              color: AppColors.brandBlue,
              selected: o.id == widget.selectedOverlayId,
              onTap: () => widget.onSelectOverlay!(o.id == widget.selectedOverlayId ? null : o.id),
              onMoveDeltaMs: widget.onUpdateOverlay == null
                  ? null
                  : (deltaMs, commit) {
                      final cur = widget.project.overlays.firstWhere((x) => x.id == o.id, orElse: () => o);
                      final rawOffset = (cur.offsetMs + deltaMs).clamp(0, math.max(0, maxMs - 200)).toInt();
                      final nextOffset = commit ? rawOffset : _snapMs(rawOffset, ignoreId: cur.id);
                      if (commit) _clearSnapLine();
                      widget.onUpdateOverlay!(cur.copyWith(offsetMs: nextOffset), commit: commit);
                    },
              onStretchLeftDeltaMs: widget.onUpdateOverlay == null
                  ? null
                  : (deltaMs, commit) {
                      final cur = widget.project.overlays.firstWhere((x) => x.id == o.id, orElse: () => o);
                      if (cur.isImage) {
                        final rawOffset = (cur.offsetMs + deltaMs).clamp(0, cur.endOnTimeline - 300);
                        final nextOffset = commit ? rawOffset : _snapMs(rawOffset, ignoreId: cur.id).clamp(0, cur.endOnTimeline - 300);
                        final nextDur = (cur.endOnTimeline - nextOffset).clamp(300, 60000);
                        if (commit) _clearSnapLine();
                        widget.onUpdateOverlay!(cur.copyWith(offsetMs: nextOffset, imageDurationMs: nextDur), commit: commit);
                      } else {
                        final nextStart = (cur.startMs + deltaMs).clamp(0, cur.endMs - 300);
                        final moved = nextStart - cur.startMs;
                        if (commit) _clearSnapLine();
                        widget.onUpdateOverlay!(
                          cur.copyWith(startMs: nextStart, offsetMs: (cur.offsetMs + moved).clamp(0, maxMs)),
                          commit: commit,
                        );
                      }
                    },
              onStretchRightDeltaMs: widget.onUpdateOverlay == null
                  ? null
                  : (deltaMs, commit) {
                      final cur = widget.project.overlays.firstWhere((x) => x.id == o.id, orElse: () => o);
                      if (cur.isImage) {
                        final rawDur = (cur.imageDurationMs + deltaMs).clamp(300, 60000);
                        final snappedEnd = commit ? (cur.offsetMs + rawDur) : _snapMs(cur.offsetMs + rawDur, ignoreId: cur.id);
                        final nextDur = (snappedEnd - cur.offsetMs).clamp(300, 60000);
                        if (commit) _clearSnapLine();
                        widget.onUpdateOverlay!(cur.copyWith(imageDurationMs: nextDur), commit: commit);
                      } else {
                        final maxSrc = cur.sourceDurationMs > 0 ? cur.sourceDurationMs : maxMs;
                        final rawEnd = (cur.endMs + deltaMs).clamp(cur.startMs + 300, maxSrc);
                        final snappedEnd = commit
                            ? (cur.offsetMs + (rawEnd - cur.startMs))
                            : _snapMs(cur.offsetMs + (rawEnd - cur.startMs), ignoreId: cur.id);
                        final nextEnd = (cur.startMs + (snappedEnd - cur.offsetMs)).clamp(cur.startMs + 300, maxSrc);
                        if (commit) _clearSnapLine();
                        widget.onUpdateOverlay!(cur.copyWith(endMs: nextEnd), commit: commit);
                      }
                    },
            ),
          ),
      ],
    );
  }

  Widget _effectRow(double half) {
    final p = widget.project;
    if (p.effects.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(left: half),
        child: _addChip(Icons.auto_fix_high_rounded, 'Add effect', widget.onAddEffect ?? () {}),
      );
    }
    final maxMs = math.max(1000, p.durationMs);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final e in p.effects)
          Positioned(
            left: half + _x(e.startMs),
            width: math.max(18, _x(e.endMs - e.startMs)),
            top: 0,
            bottom: 0,
            child: _trackChip(
              label: StudioEffects.byId(e.effectId)?.name ?? 'Effect',
              icon: StudioEffects.byId(e.effectId)?.icon ?? Icons.auto_fix_high_rounded,
              color: AppColors.textSecondary,
              selected: e.id == widget.selectedEffectId,
              onTap: () => widget.onSelectEffect!(e.id == widget.selectedEffectId ? null : e.id),
              onMoveDeltaMs: widget.onUpdateEffect == null
                  ? null
                  : (deltaMs, commit) {
                      final cur = widget.project.effects.firstWhere((x) => x.id == e.id, orElse: () => e);
                      final dur = math.max(200, cur.endMs - cur.startMs);
                      final rawStart = (cur.startMs + deltaMs).clamp(0, math.max(0, maxMs - dur)).toInt();
                      final nextStart = commit ? rawStart : _snapMs(rawStart, ignoreId: cur.id);
                      if (commit) _clearSnapLine();
                      widget.onUpdateEffect!(cur.copyWith(startMs: nextStart, endMs: nextStart + dur), commit: commit);
                    },
              onStretchLeftDeltaMs: widget.onUpdateEffect == null
                  ? null
                  : (deltaMs, commit) {
                      final cur = widget.project.effects.firstWhere((x) => x.id == e.id, orElse: () => e);
                      final rawStart = (cur.startMs + deltaMs).clamp(0, cur.endMs - 200);
                      final nextStart = commit ? rawStart : _snapMs(rawStart, ignoreId: cur.id).clamp(0, cur.endMs - 200);
                      if (commit) _clearSnapLine();
                      widget.onUpdateEffect!(cur.copyWith(startMs: nextStart), commit: commit);
                    },
              onStretchRightDeltaMs: widget.onUpdateEffect == null
                  ? null
                  : (deltaMs, commit) {
                      final cur = widget.project.effects.firstWhere((x) => x.id == e.id, orElse: () => e);
                      final rawEnd = (cur.endMs + deltaMs).clamp(cur.startMs + 200, maxMs);
                      final nextEnd = commit ? rawEnd : _snapMs(rawEnd, ignoreId: cur.id).clamp(cur.startMs + 200, maxMs);
                      if (commit) _clearSnapLine();
                      widget.onUpdateEffect!(cur.copyWith(endMs: nextEnd), commit: commit);
                    },
            ),
          ),
      ],
    );
  }

  Widget _addChip(IconData icon, String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: context.surfaceMid, borderRadius: BorderRadius.circular(AppRadius.xs)),
          child: Row(
            children: [
              Icon(Icons.add_rounded, size: 14, color: context.textSecondary),
              const SizedBox(width: 4),
              Text(label, style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  Widget _trackChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
    void Function(int deltaMs, bool commit)? onMoveDeltaMs,
    void Function(int deltaMs, bool commit)? onStretchLeftDeltaMs,
    void Function(int deltaMs, bool commit)? onStretchRightDeltaMs,
  }) {
    Widget chipBody = GestureDetector(
      onTap: onTap,
      onHorizontalDragUpdate: onMoveDeltaMs == null
          ? null
          : (d) {
              final deltaMs = (d.delta.dx / _pps * 1000).round();
              if (deltaMs != 0) onMoveDeltaMs(deltaMs, false);
            },
      onHorizontalDragEnd: onMoveDeltaMs == null ? null : (_) => onMoveDeltaMs(0, true),
      child: Container(
        margin: const EdgeInsets.only(right: 1),
        padding: EdgeInsets.symmetric(horizontal: selected ? 10 : 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: selected ? 0.95 : 0.72),
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: selected ? Border.all(color: AppColors.brandWhite, width: 1.4) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 11, color: AppColors.brandWhite),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 10, color: AppColors.brandWhite, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );

    if (!selected || (onStretchLeftDeltaMs == null && onStretchRightDeltaMs == null)) {
      return chipBody;
    }

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        chipBody,
        if (onStretchLeftDeltaMs != null)
          Positioned(
            left: -5,
            top: 0,
            bottom: 0,
            width: 12,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onHorizontalDragUpdate: (d) {
                final deltaMs = (d.delta.dx / _pps * 1000).round();
                if (deltaMs != 0) onStretchLeftDeltaMs(deltaMs, false);
              },
              onHorizontalDragEnd: (_) => onStretchLeftDeltaMs(0, true),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.brandWhite,
                  borderRadius: BorderRadius.horizontal(left: Radius.circular(4)),
                ),
                child: Center(
                  child: Container(width: 1.5, height: 10, color: AppColors.brandBlack),
                ),
              ),
            ),
          ),
        if (onStretchRightDeltaMs != null)
          Positioned(
            right: -5,
            top: 0,
            bottom: 0,
            width: 12,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onHorizontalDragUpdate: (d) {
                final deltaMs = (d.delta.dx / _pps * 1000).round();
                if (deltaMs != 0) onStretchRightDeltaMs(deltaMs, false);
              },
              onHorizontalDragEnd: (_) => onStretchRightDeltaMs(0, true),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.brandWhite,
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
                ),
                child: Center(
                  child: Container(width: 1.5, height: 10, color: AppColors.brandBlack),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ClipStrip extends StatelessWidget {
  final StudioClip clip;
  final double width;
  final double pps;
  final bool selected;

  const _ClipStrip({required this.clip, required this.width, required this.pps, required this.selected});

  @override
  Widget build(BuildContext context) {
    const tileW = 40.0;
    final tiles = math.max(1, (width / tileW).ceil());
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: selected ? AppColors.brandWhite : AppColors.brandBlack, width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<List<String>>(
            future: StudioMedia.thumbnails(clip),
            builder: (context, snap) {
              final thumbs = snap.data ?? const <String>[];
              if (thumbs.isEmpty) return ColoredBox(color: context.surfaceMid);
              return Row(
                children: [
                  for (var i = 0; i < tiles; i++)
                    SizedBox(
                      width: i == tiles - 1 ? width - tileW * (tiles - 1) : tileW,
                      child: Image.file(
                        File(thumbs[_thumbIndex(i, tileW, thumbs.length)]),
                        fit: BoxFit.cover,
                        height: double.infinity,
                        cacheHeight: 120,
                        gaplessPlayback: true,
                      ),
                    ),
                ],
              );
            },
          ),
          Positioned(
            left: 4,
            bottom: 2,
            child: Row(
              children: [
                if (clip.muted) const Icon(Icons.volume_off_rounded, size: 11, color: AppColors.brandWhite),
                if (clip.speed != 1)
                  Text('${clip.speed.toStringAsFixed(clip.speed % 1 == 0 ? 0 : 2)}x ',
                      style: GoogleFonts.inter(fontSize: 9.5, color: AppColors.brandWhite, fontWeight: FontWeight.w800)),
                Text(studioClockFine(clip.outDurationMs),
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      color: AppColors.brandWhite,
                      fontWeight: FontWeight.w700,
                      shadows: const [Shadow(blurRadius: 3)],
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _thumbIndex(int tile, double tileW, int count) {
    if (clip.isImage || count <= 1) return 0;
    final outMs = (tile + 0.5) * tileW / pps * 1000;
    final srcMs = clip.startMs + outMs * clip.speed;
    final step = clip.sourceDurationMs / count;
    return (srcMs / step).floor().clamp(0, count - 1);
  }
}

class _RulerPainter extends CustomPainter {
  final double left;
  final double pps;
  final int totalMs;
  final Color color;
  final TextStyle style;

  _RulerPainter({required this.left, required this.pps, required this.totalMs, required this.color, required this.style});

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = color;
    final secondsPerLabel = pps >= 120 ? 1 : (pps >= 48 ? 2 : (pps >= 24 ? 5 : (pps >= 10 ? 10 : (pps >= 4 ? 30 : 60))));
    // Dots every second, thinned out when zoomed far out (long videos).
    final tick = pps >= 10 ? 1 : (pps >= 4 ? 5 : 10);
    final totalS = (totalMs / 1000).ceil();
    for (var s = 0; s <= totalS; s += tick) {
      final x = left + s * pps;
      if (s % secondsPerLabel == 0) {
        final tp = TextPainter(text: TextSpan(text: studioClock(s * 1000), style: style), textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, 2));
      } else {
        canvas.drawCircle(Offset(x, 9), 1.4, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) => old.pps != pps || old.totalMs != totalMs || old.color != color;
}
