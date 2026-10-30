import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/studio_project.dart';
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
  final ValueChanged<String?> onSelectClip;
  final ValueChanged<String?> onSelectText;
  final ValueChanged<String?> onSelectAudio;

  /// Live trim while dragging a handle (not yet committed to history).
  final void Function(StudioClip clip) onTrimPreview;
  final VoidCallback onTrimCommit;
  final VoidCallback onAddClip;
  final VoidCallback onAddAudio;
  final VoidCallback onAddText;
  final VoidCallback onCover;
  final VoidCallback onToggleMuteAll;

  const StudioTimeline({
    super.key,
    required this.playback,
    required this.project,
    required this.selectedClipId,
    required this.selectedTextId,
    required this.selectedAudioId,
    required this.onSelectClip,
    required this.onSelectText,
    required this.onSelectAudio,
    required this.onTrimPreview,
    required this.onTrimCommit,
    required this.onAddClip,
    required this.onAddAudio,
    required this.onAddText,
    required this.onCover,
    required this.onToggleMuteAll,
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

  static const _clipH = 54.0;
  static const _rowH = 26.0;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final total = p.durationMs;
    return LayoutBuilder(builder: (context, box) {
      final half = box.maxWidth / 2;
      final contentW = _x(total);
      return GestureDetector(
        onScaleStart: (_) => _ppsAtScaleStart = _pps,
        onScaleUpdate: (d) {
          if (d.pointerCount < 2) return;
          setState(() => _pps = (_ppsAtScaleStart * d.horizontalScale).clamp(16.0, 320.0));
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 22, child: _ruler(half, total)),
                      const SizedBox(height: 6),
                      SizedBox(height: _clipH + 8, child: _clipRow(half)),
                      const SizedBox(height: 6),
                      SizedBox(height: _rowH, child: _textRow(half)),
                      const SizedBox(height: 4),
                      SizedBox(height: _rowH, child: _audioRow(half)),
                    ],
                  ),
                ),
              ),
            ),
            // Playhead
            Positioned(
              left: half - 1,
              top: 18,
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
            // Add clip
            Positioned(
              right: 10,
              top: 28 + (_clipH - 40) / 2 + 4,
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
                  child: const SizedBox(width: 40, height: 40, child: Icon(Icons.add_rounded, color: AppColors.brandBlack, size: 26)),
                ),
              ),
            ),
          ],
        ),
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
            final next = (current.imageDurationMs + (isLeft ? -deltaOut : deltaOut)).round().clamp(500, 60000);
            widget.onTrimPreview(current.copyWith(imageDurationMs: next));
            return;
          }
          final deltaSrc = (deltaOut * current.speed).round();
          if (isLeft) {
            final s = (current.startMs + deltaSrc).clamp(0, current.endMs - 300);
            widget.onTrimPreview(current.copyWith(startMs: s));
          } else {
            final e = (current.endMs + deltaSrc).clamp(current.startMs + 300, current.sourceDurationMs);
            widget.onTrimPreview(current.copyWith(endMs: e));
          }
        },
        onHorizontalDragEnd: (_) => widget.onTrimCommit(),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.brandWhite,
            borderRadius: BorderRadius.horizontal(
              left: Radius.circular(isLeft ? 6 : 0),
              right: Radius.circular(isLeft ? 0 : 6),
            ),
          ),
          child: Center(
            child: Container(width: 2, height: 16, color: AppColors.brandBlack.withValues(alpha: 0.6)),
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
    return Stack(children: [
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
          ),
        ),
    ]);
  }

  Widget _audioRow(double half) {
    final p = widget.project;
    if (p.audios.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(left: half),
        child: _addChip(Icons.music_note_rounded, 'Add audio', widget.onAddAudio),
      );
    }
    return Stack(children: [
      for (final a in p.audios)
        Positioned(
          left: half + _x(a.offsetMs),
          width: math.max(18, _x(a.durationMs)),
          top: 0,
          bottom: 0,
          child: _trackChip(
            label: a.title,
            icon: Icons.graphic_eq_rounded,
            color: const Color(0xFF2E7D5B),
            selected: a.id == widget.selectedAudioId,
            onTap: () => widget.onSelectAudio(a.id == widget.selectedAudioId ? null : a.id),
          ),
        ),
    ]);
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
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 1),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: selected ? 0.95 : 0.7),
            borderRadius: BorderRadius.circular(AppRadius.xs),
            border: selected ? Border.all(color: AppColors.brandWhite, width: 1.2) : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: 12, color: AppColors.brandWhite),
              const SizedBox(width: 4),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.brandWhite, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
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
    final secondsPerLabel = pps >= 120 ? 1 : (pps >= 48 ? 2 : (pps >= 24 ? 5 : 10));
    final totalS = (totalMs / 1000).ceil();
    for (var s = 0; s <= totalS; s++) {
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
