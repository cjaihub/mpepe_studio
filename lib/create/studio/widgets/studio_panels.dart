import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/studio_project.dart';
import '../services/studio_color.dart';
import '../services/studio_media.dart';
import 'studio_text_editor_sheet.dart';
import 'studio_ui.dart';

/// Header shared by every bottom panel: title, optional action, done check.
class StudioPanel extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback onDone;
  final Widget? action;

  const StudioPanel({super.key, required this.title, required this.child, required this.onDone, this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 42,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Text(title, style: GoogleFonts.inter(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                const Spacer(),
                ?action,
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.check_rounded, color: context.textPrimary),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onDone();
                  },
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.border),
          child,
        ],
      ),
    );
  }
}

class StudioTextAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const StudioTextAction({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        icon: Icon(icon, size: 16, color: context.textSecondary),
        label: Text(label, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

/// Filter looks for one clip, with intensity and apply-to-all.
class StudioFiltersPanel extends StatefulWidget {
  final StudioClip clip;
  final ValueChanged<StudioClip> onLive;
  final VoidCallback onCommit;
  final VoidCallback onApplyAll;
  final VoidCallback onDone;

  const StudioFiltersPanel({
    super.key,
    required this.clip,
    required this.onLive,
    required this.onCommit,
    required this.onApplyAll,
    required this.onDone,
  });

  @override
  State<StudioFiltersPanel> createState() => _StudioFiltersPanelState();
}

class _StudioFiltersPanelState extends State<StudioFiltersPanel> {
  String _group = 'Featured';

  @override
  Widget build(BuildContext context) {
    final groups = StudioColor.filters.map((f) => f.group).toSet().toList();
    final items = StudioColor.filters.where((f) => f.group == _group || f.id == 'none').toList();
    final clip = widget.clip;
    return StudioPanel(
      title: 'Filters',
      onDone: widget.onDone,
      action: StudioTextAction(icon: Icons.layers_outlined, label: 'Apply to all', onTap: widget.onApplyAll),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                for (final g in groups)
                  GestureDetector(
                    onTap: () => setState(() => _group = g),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                      child: Text(g,
                          style: GoogleFonts.inter(
                            color: g == _group ? context.textPrimary : context.textMuted,
                            fontSize: 13,
                            fontWeight: g == _group ? FontWeight.w800 : FontWeight.w600,
                          )),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 96,
            child: FutureBuilder<List<String>>(
              future: StudioMedia.thumbnails(clip),
              builder: (context, snap) {
                final thumbs = snap.data ?? const <String>[];
                final thumb = thumbs.isEmpty ? null : thumbs[thumbs.length ~/ 2];
                return ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final f in items)
                      _FilterTile(
                        filter: f,
                        thumb: thumb,
                        selected: clip.filterId == f.id,
                        onTap: () {
                          widget.onLive(clip.copyWith(filterId: f.id, filterIntensity: 1));
                          widget.onCommit();
                        },
                      ),
                  ],
                );
              },
            ),
          ),
          if (clip.filterId != 'none')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: StudioSliderRow(
                label: 'Intensity',
                value: clip.filterIntensity * 100,
                min: 0,
                max: 100,
                format: (v) => '${v.round()}',
                onChanged: (v) => widget.onLive(clip.copyWith(filterIntensity: v / 100)),
                onChangeEnd: (_) => widget.onCommit(),
              ),
            )
          else
            const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _FilterTile extends StatelessWidget {
  final StudioFilter filter;
  final String? thumb;
  final bool selected;
  final VoidCallback onTap;

  const _FilterTile({required this.filter, required this.thumb, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget img = thumb == null
        ? ColoredBox(color: context.surfaceMid)
        : Image.file(File(thumb!), fit: BoxFit.cover, cacheHeight: 160, gaplessPlayback: true);
    if (filter.id != 'none') img = ColorFiltered(colorFilter: ColorFilter.matrix(filter.matrix), child: img);
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: selected ? AppColors.brandBlue : AppColors.brandBlue.withValues(alpha: 0), width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: filter.id == 'none'
                  ? Stack(fit: StackFit.expand, children: [
                      img,
                      ColoredBox(color: AppColors.brandBlack.withValues(alpha: 0.45)),
                      const Icon(Icons.block_rounded, color: AppColors.brandWhite, size: 22),
                    ])
                  : img,
            ),
            const SizedBox(height: 4),
            Text(filter.name,
                style: GoogleFonts.inter(
                  color: selected ? AppColors.brandBlue : context.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      ),
    );
  }
}

/// Manual color and tone: the color matrix keys plus highlights, shadows,
/// whites, blacks, vibrance, sharpen, grain and vignette (Look engine).
class StudioAdjustPanel extends StatefulWidget {
  final StudioClip clip;
  final ValueChanged<StudioClip> onLive;
  final VoidCallback onCommit;
  final VoidCallback onApplyAll;
  final VoidCallback onDone;

  const StudioAdjustPanel({
    super.key,
    required this.clip,
    required this.onLive,
    required this.onCommit,
    required this.onApplyAll,
    required this.onDone,
  });

  @override
  State<StudioAdjustPanel> createState() => _StudioAdjustPanelState();
}

class _StudioAdjustPanelState extends State<StudioAdjustPanel> {
  String _key = 'brightness';

  static const _meta = <String, (String, IconData)>{
    'brightness': ('Brightness', Icons.wb_sunny_outlined),
    'contrast': ('Contrast', Icons.contrast_rounded),
    'saturation': ('Saturation', Icons.water_drop_outlined),
    'exposure': ('Exposure', Icons.exposure_rounded),
    'warmth': ('Warmth', Icons.thermostat_rounded),
    'tint': ('Tint', Icons.palette_outlined),
    'fade': ('Fade', Icons.blur_on_rounded),
    'highlights': ('Highlights', Icons.brightness_high_outlined),
    'shadows': ('Shadows', Icons.brightness_low_outlined),
    'whites': ('Whites', Icons.wb_incandescent_outlined),
    'blacks': ('Blacks', Icons.dark_mode_outlined),
    'vibrance': ('Vibrance', Icons.color_lens_outlined),
    'sharpen': ('Sharpen', Icons.details_rounded),
    'grain': ('Grain', Icons.grain_rounded),
    'vignette': ('Vignette', Icons.vignette_outlined),
  };

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    final value = clip.adjust.valueOf(_key);
    return StudioPanel(
      title: 'Adjust',
      onDone: widget.onDone,
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StudioTextAction(
            icon: Icons.refresh_rounded,
            label: 'Reset',
            onTap: () {
              widget.onLive(clip.copyWith(adjust: const StudioAdjust()));
              widget.onCommit();
            },
          ),
          StudioTextAction(icon: Icons.layers_outlined, label: 'Apply to all', onTap: widget.onApplyAll),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 82,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              children: [
                for (final e in _meta.entries)
                  GestureDetector(
                    onTap: () => setState(() => _key = e.key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: context.surfaceMid,
                              border: Border.all(
                                color: e.key == _key ? AppColors.brandBlue : context.border,
                                width: e.key == _key ? 2 : 1,
                              ),
                            ),
                            child: Icon(e.value.$2,
                                size: 20,
                                color: clip.adjust.valueOf(e.key) != 0 ? AppColors.brandBlue : context.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          Text(e.value.$1,
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                color: e.key == _key ? context.textPrimary : context.textSecondary,
                                fontWeight: FontWeight.w600,
                              )),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: StudioSliderRow(
              label: _meta[_key]!.$1,
              value: value * 100,
              min: _key == 'fade' || StudioAdjust.positiveKeys.contains(_key) ? 0 : -100,
              max: 100,
              format: (v) => '${v.round()}',
              onChanged: (v) => widget.onLive(clip.copyWith(adjust: clip.adjust.withValue(_key, v / 100))),
              onChangeEnd: (_) => widget.onCommit(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Generic one-slider panel (speed, volume, photo duration).
class StudioSliderPanel extends StatelessWidget {
  final String title;
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double) format;
  final ValueChanged<double> onLive;
  final VoidCallback onCommit;
  final VoidCallback onDone;
  final List<(String, double)> presets;
  final Widget? footer;

  const StudioSliderPanel({
    super.key,
    required this.title,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onLive,
    required this.onCommit,
    required this.onDone,
    this.divisions,
    this.presets = const [],
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      title: title,
      onDone: onDone,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (presets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final p in presets)
                      ChoiceChip(
                        label: Text(p.$1),
                        selected: (value - p.$2).abs() < 0.001,
                        visualDensity: VisualDensity.compact,
                        labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                        selectedColor: AppColors.brandBlue.withValues(alpha: 0.18),
                        onSelected: (_) {
                          onLive(p.$2);
                          onCommit();
                        },
                      ),
                  ],
                ),
              ),
            StudioSliderRow(
              label: label,
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              format: format,
              onChanged: onLive,
              onChangeEnd: (_) => onCommit(),
            ),
            ?footer,
          ],
        ),
      ),
    );
  }
}

/// Canvas shape + how each clip sits in it.
class StudioAspectPanel extends StatelessWidget {
  final StudioAspect aspect;
  final bool fill;
  final ValueChanged<StudioAspect> onAspect;
  final ValueChanged<bool> onFill;
  final VoidCallback onDone;

  const StudioAspectPanel({
    super.key,
    required this.aspect,
    required this.fill,
    required this.onAspect,
    required this.onFill,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      title: 'Aspect ratio',
      onDone: onDone,
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Fill', style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          Switch.adaptive(value: fill, activeTrackColor: AppColors.brandBlue, onChanged: onFill),
        ],
      ),
      child: SizedBox(
        height: 92,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          children: [
            for (final a in StudioAspect.values)
              GestureDetector(
                onTap: () => onAspect(a),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: Container(
                            width: a.ratio == 0 ? 30 : (a.ratio >= 1 ? 40 : 40 * a.ratio),
                            height: a.ratio == 0 ? 30 : (a.ratio >= 1 ? 40 / a.ratio : 40),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: a == aspect ? AppColors.brandBlue : context.textSecondary, width: 1.6),
                            ),
                            child: a.ratio == 0
                                ? Icon(Icons.crop_original_rounded,
                                    size: 16, color: a == aspect ? AppColors.brandBlue : context.textSecondary)
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(a.label,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: a == aspect ? AppColors.brandBlue : context.textSecondary,
                            fontWeight: FontWeight.w700,
                          )),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Rotate, flip, zoom and fit/fill for one clip.
class StudioTransformPanel extends StatelessWidget {
  final StudioClip clip;
  final ValueChanged<StudioClip> onLive;
  final VoidCallback onCommit;
  final VoidCallback onDone;

  const StudioTransformPanel({super.key, required this.clip, required this.onLive, required this.onCommit, required this.onDone});

  void _set(StudioClip c) {
    onLive(c);
    onCommit();
  }

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      title: 'Transform',
      onDone: onDone,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                StudioToolButton(
                  icon: Icons.rotate_90_degrees_cw_outlined,
                  label: 'Rotate',
                  onTap: () => _set(clip.copyWith(rotation: (clip.rotation + 90) % 360)),
                ),
                StudioToolButton(
                  icon: Icons.flip_rounded,
                  label: 'Mirror',
                  active: clip.flipH,
                  onTap: () => _set(clip.copyWith(flipH: !clip.flipH)),
                ),
                StudioToolButton(
                  icon: Icons.flip_camera_android_rounded,
                  label: 'Flip',
                  active: clip.flipV,
                  onTap: () => _set(clip.copyWith(flipV: !clip.flipV)),
                ),
                StudioToolButton(
                  icon: clip.fill ? Icons.fit_screen_rounded : Icons.crop_free_rounded,
                  label: clip.fill ? 'Fill' : 'Fit',
                  active: clip.fill,
                  onTap: () => _set(clip.copyWith(fill: !clip.fill)),
                ),
              ],
            ),
            StudioSliderRow(
              label: 'Zoom',
              value: clip.zoom,
              min: 1,
              max: 3,
              format: (v) => '${v.toStringAsFixed(1)}x',
              onChanged: (v) => onLive(clip.copyWith(zoom: v)),
              onChangeEnd: (_) => onCommit(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Crop on the uncropped frame: drag the box to move it, the corners to
/// resize it, or snap to a ratio.
class StudioCropEditor extends StatefulWidget {
  final StudioClip clip;
  final Widget frame;
  final ValueChanged<StudioCrop> onChanged;

  const StudioCropEditor({super.key, required this.clip, required this.frame, required this.onChanged});

  @override
  State<StudioCropEditor> createState() => _StudioCropEditorState();
}

class _StudioCropEditorState extends State<StudioCropEditor> {
  late StudioCrop _crop = widget.clip.crop;

  @override
  void didUpdateWidget(covariant StudioCropEditor old) {
    super.didUpdateWidget(old);
    if (old.clip.crop != widget.clip.crop) _crop = widget.clip.crop;
  }

  @override
  Widget build(BuildContext context) {
    final sw = widget.clip.sourceWidth > 0 ? widget.clip.sourceWidth.toDouble() : 9.0;
    final sh = widget.clip.sourceHeight > 0 ? widget.clip.sourceHeight.toDouble() : 16.0;
    return LayoutBuilder(builder: (context, box) {
      var w = box.maxWidth - 32;
      var h = w * sh / sw;
      if (h > box.maxHeight - 32) {
        h = box.maxHeight - 32;
        w = h * sw / sh;
      }
      final rect = Rect.fromLTRB(_crop.l * w, _crop.t * h, _crop.r * w, _crop.b * h);
      void update(Rect r) {
        final minW = w * 0.1, minH = h * 0.1;
        var nr = Rect.fromLTRB(
          r.left.clamp(0.0, w - minW),
          r.top.clamp(0.0, h - minH),
          r.right.clamp(minW, w),
          r.bottom.clamp(minH, h),
        );
        if (nr.width < minW || nr.height < minH) return;
        setState(() => _crop = StudioCrop(l: nr.left / w, t: nr.top / h, r: nr.right / w, b: nr.bottom / h));
      }

      Widget corner(Alignment a) => Positioned(
            left: (a.x < 0 ? rect.left : rect.right) - 14,
            top: (a.y < 0 ? rect.top : rect.bottom) - 14,
            child: GestureDetector(
              onPanUpdate: (d) => update(Rect.fromLTRB(
                a.x < 0 ? rect.left + d.delta.dx : rect.left,
                a.y < 0 ? rect.top + d.delta.dy : rect.top,
                a.x > 0 ? rect.right + d.delta.dx : rect.right,
                a.y > 0 ? rect.bottom + d.delta.dy : rect.bottom,
              )),
              onPanEnd: (_) => widget.onChanged(_crop),
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(color: AppColors.brandWhite, borderRadius: BorderRadius.circular(3)),
                ),
              ),
            ),
          );

      return Center(
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: widget.frame),
              Positioned.fill(
                child: IgnorePointer(child: CustomPaint(painter: _CropShade(rect))),
              ),
              Positioned.fromRect(
                rect: rect,
                child: GestureDetector(
                  onPanUpdate: (d) {
                    final dx = d.delta.dx.clamp(-rect.left, w - rect.right);
                    final dy = d.delta.dy.clamp(-rect.top, h - rect.bottom);
                    update(rect.shift(Offset(dx, dy)));
                  },
                  onPanEnd: (_) => widget.onChanged(_crop),
                  child: Container(decoration: BoxDecoration(border: Border.all(color: AppColors.brandWhite, width: 1.5))),
                ),
              ),
              corner(Alignment.topLeft),
              corner(Alignment.topRight),
              corner(Alignment.bottomLeft),
              corner(Alignment.bottomRight),
            ],
          ),
        ),
      );
    });
  }
}

class _CropShade extends CustomPainter {
  final Rect rect;
  _CropShade(this.rect);

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Paint()..color = AppColors.brandBlack.withValues(alpha: 0.55);
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(path, shade);
    final grid = Paint()
      ..color = AppColors.brandWhite.withValues(alpha: 0.35)
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }
  }

  @override
  bool shouldRepaint(_CropShade old) => old.rect != rect;
}

/// Ratio presets for the crop box (relative to the source frame).
StudioCrop studioCropForRatio(StudioClip clip, double? ratio) {
  if (ratio == null) return const StudioCrop();
  final sw = clip.sourceWidth > 0 ? clip.sourceWidth.toDouble() : 9.0;
  final sh = clip.sourceHeight > 0 ? clip.sourceHeight.toDouble() : 16.0;
  final src = sw / sh;
  if (src > ratio) {
    final w = ratio / src;
    return StudioCrop(l: (1 - w) / 2, t: 0, r: (1 + w) / 2, b: 1);
  }
  final h = src / ratio;
  return StudioCrop(l: 0, t: (1 - h) / 2, r: 1, b: (1 + h) / 2);
}

/// Text editor sheet (templates, font, style, animation, layout). Returns
/// null on cancel. See [showStudioTextEditor] for the full result.
Future<StudioText?> showStudioTextSheet(BuildContext context, StudioText initial, {String title = 'Text', int maxEndMs = 0}) async {
  final edit = await showStudioTextEditor(context, initial, title: title, maxEndMs: maxEndMs);
  return edit?.text;
}

/// Emoji stickers burned into the video like text layers.
const studioStickers = <String>[
  '🔥', '😂', '😍', '🥰', '😎', '🤩', '👏', '🙌', '💯', '✨', '🎉', '❤️', //
  '💙', '💖', '⭐', '🌟', '⚡', '🎵', '🎬', '📍', '👀', '🤝', '💪', '🙏', //
  '😭', '😅', '🤔', '😱', '👑', '💎', '🛍️', '📦', '🏷️', '✅', '❌', '➡️', //
];

Future<String?> showStudioStickerSheet(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const StudioSheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Stickers', style: GoogleFonts.inter(color: ctx.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 6,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                for (final s in studioStickers)
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: () => Navigator.pop(ctx, s),
                    child: Center(child: Text(s, style: const TextStyle(fontSize: 30))),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

/// Parses SubRip (.srt) captions into (startMs, endMs, text).
List<(int, int, String)> parseSrt(String srt) {
  final out = <(int, int, String)>[];
  final time = RegExp(r'(\d+):(\d+):(\d+)[,.](\d+)\s*-->\s*(\d+):(\d+):(\d+)[,.](\d+)');
  for (final block in srt.replaceAll('\r', '').split(RegExp(r'\n\s*\n'))) {
    final lines = block.trim().split('\n');
    final i = lines.indexWhere((l) => time.hasMatch(l));
    if (i < 0) continue;
    final m = time.firstMatch(lines[i])!;
    int ms(int o) =>
        int.parse(m.group(o)!) * 3600000 +
        int.parse(m.group(o + 1)!) * 60000 +
        int.parse(m.group(o + 2)!) * 1000 +
        int.parse(m.group(o + 3)!.padRight(3, '0').substring(0, 3));
    final text = lines.sublist(i + 1).join('\n').replaceAll(RegExp(r'<[^>]+>'), '').trim();
    if (text.isEmpty) continue;
    out.add((ms(1), math.max(ms(1) + 200, ms(5)), text));
  }
  return out;
}
