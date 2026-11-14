import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
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

/// Manual & AI color grading and correction: Correction sliders, 3-Way Color
/// Wheels (Lift/Gamma/Gain), Tone Curves, and AI Color Director.
class StudioAdjustPanel extends StatefulWidget {
  final StudioClip clip;
  final ValueChanged<StudioClip> onLive;
  final VoidCallback onCommit;
  final VoidCallback onApplyAll;
  final VoidCallback onDone;
  final int initialTab;

  const StudioAdjustPanel({
    super.key,
    required this.clip,
    required this.onLive,
    required this.onCommit,
    required this.onApplyAll,
    required this.onDone,
    this.initialTab = 0,
  });

  @override
  State<StudioAdjustPanel> createState() => _StudioAdjustPanelState();
}

class _StudioAdjustPanelState extends State<StudioAdjustPanel> {
  late int _tab = widget.initialTab; // 0 = Correction, 1 = Wheels, 2 = Curves, 3 = AI Grade
  String _key = 'exposure';
  int _wheelIndex = 0; // 0 = Lift (Shadows), 1 = Gamma (Midtones), 2 = Gain (Highlights)
  final TextEditingController _aiCtrl = TextEditingController();
  bool _aiBusy = false;
  String? _aiSummary;

  static const _meta = <String, (String, IconData)>{
    'exposure': ('Exposure', Icons.exposure_rounded),
    'brightness': ('Brightness', Icons.wb_sunny_outlined),
    'contrast': ('Contrast', Icons.contrast_rounded),
    'highlights': ('Highlights', Icons.brightness_high_outlined),
    'shadows': ('Shadows', Icons.brightness_low_outlined),
    'whites': ('Whites', Icons.wb_incandescent_outlined),
    'blacks': ('Blacks', Icons.dark_mode_outlined),
    'warmth': ('Temp', Icons.thermostat_rounded),
    'tint': ('Tint', Icons.palette_outlined),
    'saturation': ('Saturation', Icons.water_drop_outlined),
    'vibrance': ('Vibrance', Icons.color_lens_outlined),
    'hue': ('Hue', Icons.invert_colors_on_rounded),
    'clarity': ('Clarity', Icons.hdr_strong_rounded),
    'dehaze': ('Dehaze', Icons.wb_twilight_rounded),
    'fade': ('Fade', Icons.blur_on_rounded),
    'sharpen': ('Sharpen', Icons.details_rounded),
    'grain': ('Grain', Icons.grain_rounded),
    'vignette': ('Vignette', Icons.vignette_outlined),
  };

  @override
  void dispose() {
    _aiCtrl.dispose();
    super.dispose();
  }

  void _autoCorrect() {
    HapticFeedback.mediumImpact();
    final clip = widget.clip;
    final next = clip.adjust.withValues({
      'exposure': 0.08,
      'brightness': 0.03,
      'contrast': 0.14,
      'highlights': -0.18,
      'shadows': 0.22,
      'whites': 0.08,
      'blacks': -0.06,
      'warmth': 0.05,
      'vibrance': 0.18,
      'saturation': 0.06,
      'clarity': 0.15,
      'sharpen': 0.16,
    });
    widget.onLive(clip.copyWith(adjust: next));
    widget.onCommit();
    setState(() => _aiSummary = 'Auto-Corrected: +8 Exp, +14 Contrast, +22 Shadows, +18 Vibrance');
  }

  Future<void> _applyAiPrompt(String rawPrompt) async {
    final prompt = rawPrompt.trim();
    if (prompt.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _aiBusy = true);
    final p = prompt.toLowerCase();
    final clip = widget.clip;

    // 1. Deterministic instant studio-grade color recipe based on intent
    Map<String, double> updates;
    String lookId = clip.lookId;
    double lookInt = clip.lookIntensity;
    String summary;

    if (p.contains('teal') || p.contains('blockbuster') || p.contains('cinema')) {
      updates = {
        'exposure': 0.04,
        'contrast': 0.18,
        'highlights': -0.20,
        'shadows': 0.14,
        'warmth': 0.08,
        'vibrance': 0.22,
        'clarity': 0.16,
        'liftR': -0.18,
        'liftG': 0.04,
        'liftB': 0.24,
        'gainR': 0.22,
        'gainG': 0.06,
        'gainB': -0.18,
        'curvePreset': 1,
        'vignette': 0.18,
      };
      lookId = 'teal_orange';
      lookInt = 0.78;
      summary = 'AI Teal & Orange Cinema (Shadow Cyan Lift + Warm Highlight Gain + S-Curve)';
    } else if (p.contains('golden') || p.contains('sunset') || p.contains('warm')) {
      updates = {
        'exposure': 0.08,
        'contrast': 0.10,
        'highlights': -0.16,
        'shadows': 0.20,
        'warmth': 0.34,
        'tint': 0.06,
        'vibrance': 0.24,
        'gainR': 0.24,
        'gainG': 0.10,
        'gainB': -0.20,
        'gammaR': 0.08,
        'gammaG': 0.03,
        'gammaB': -0.06,
      };
      lookId = 'golden_hour';
      lookInt = 0.80;
      summary = 'AI Golden Hour Sunlight (+34 Warmth, Golden Highlight Gain, Lifted Shadows)';
    } else if (p.contains('skin') || p.contains('melanin') || p.contains('portrait') || p.contains('studio')) {
      updates = {
        'exposure': 0.06,
        'contrast': 0.06,
        'highlights': -0.14,
        'shadows': 0.24,
        'warmth': 0.10,
        'vibrance': 0.16,
        'saturation': -0.02,
        'gammaR': 0.06,
        'gammaG': 0.02,
        'gammaB': -0.04,
        'sharpen': 0.14,
      };
      lookId = 'melanin';
      lookInt = 0.85;
      summary = 'AI Studio Skin & Melanin Luxe (Soft Highlights, Warm Midtones, Lifted Shadows)';
    } else if (p.contains('noir') || p.contains('black') || p.contains('b&w') || p.contains('mono')) {
      updates = {
        'contrast': 0.32,
        'highlights': 0.10,
        'shadows': -0.14,
        'whites': 0.18,
        'blacks': -0.24,
        'saturation': -1.0,
        'clarity': 0.25,
        'grain': 0.18,
        'vignette': 0.28,
        'curvePreset': 4,
      };
      lookId = 'bw_high';
      lookInt = 0.90;
      summary = 'AI Silver Noir Monochrome (Crushed Blacks, Crisp Whites, Film Grain)';
    } else if (p.contains('cyber') || p.contains('neon') || p.contains('night')) {
      updates = {
        'exposure': -0.04,
        'contrast': 0.24,
        'highlights': 0.12,
        'blacks': -0.16,
        'warmth': -0.22,
        'tint': 0.26,
        'vibrance': 0.34,
        'saturation': 0.18,
        'liftR': 0.08,
        'liftG': -0.10,
        'liftB': 0.28,
        'gainR': 0.22,
        'gainG': -0.08,
        'gainB': 0.26,
        'curvePreset': 1,
      };
      lookId = 'neon_city';
      lookInt = 0.82;
      summary = 'AI Cyberpunk Neon (Electric Blue/Magenta Split-Tone + High Contrast)';
    } else if (p.contains('kodak') || p.contains('vintage') || p.contains('film') || p.contains('matte')) {
      updates = {
        'exposure': 0.04,
        'contrast': -0.06,
        'highlights': -0.18,
        'shadows': 0.16,
        'warmth': 0.16,
        'fade': 0.18,
        'grain': 0.24,
        'vignette': 0.20,
        'liftR': 0.06,
        'liftG': 0.04,
        'liftB': -0.04,
        'curvePreset': 2,
      };
      lookId = 'kodak';
      lookInt = 0.85;
      summary = 'AI Kodak 2383 Matte Film (Lifted Black Curve, Warm Grain, Soft Roll-off)';
    } else if (p.contains('hdr') || p.contains('pop') || p.contains('vivid') || p.contains('crisp')) {
      updates = {
        'exposure': 0.06,
        'contrast': 0.20,
        'highlights': -0.22,
        'shadows': 0.28,
        'whites': 0.14,
        'blacks': -0.10,
        'vibrance': 0.32,
        'saturation': 0.14,
        'clarity': 0.28,
        'dehaze': 0.20,
        'sharpen': 0.26,
        'curvePreset': 3,
      };
      lookId = 'pop';
      lookInt = 0.80;
      summary = 'AI Vivid HDR Pop (+28 Clarity, +20 Dehaze, +32 Vibrance, Dynamic Range Boost)';
    } else {
      updates = {
        'exposure': 0.08,
        'contrast': 0.15,
        'highlights': -0.18,
        'shadows': 0.22,
        'whites': 0.08,
        'blacks': -0.08,
        'warmth': 0.06,
        'vibrance': 0.20,
        'clarity': 0.16,
        'sharpen': 0.15,
        'curvePreset': 1,
      };
      summary = 'AI Optical Balance & Grade ("$prompt")';
    }

    // Apply immediately so the user sees zero-latency grading
    var gradedClip = clip.copyWith(
      lookId: lookId,
      lookIntensity: lookInt,
      adjust: clip.adjust.withValues(updates),
    );
    widget.onLive(gradedClip);
    widget.onCommit();

    // Also query cloud AI grading endpoint if online to refine parameters
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('gradeCommand', options: HttpsCallableOptions(timeout: const Duration(seconds: 5)))
          .call<Map<String, dynamic>>({'command': prompt, 'current': gradedClip.adjust.toJson()});
      final data = res.data;
      final remoteAdjust = data['adjust'];
      if (remoteAdjust is Map && mounted) {
        final merged = <String, double>{...updates};
        for (final e in remoteAdjust.entries) {
          if (e.key is String && StudioAdjust.keys.contains(e.key) && e.value is num) {
            merged[e.key as String] = (e.value as num).toDouble();
          }
        }
        gradedClip = gradedClip.copyWith(adjust: gradedClip.adjust.withValues(merged));
        widget.onLive(gradedClip);
        widget.onCommit();
      }
    } catch (_) {
      // Offline or function unavailable: local deterministic AI grade is already applied.
    }

    if (mounted) {
      setState(() {
        _aiBusy = false;
        _aiSummary = summary;
        _aiCtrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    return StudioPanel(
      title: 'Color Grade & Correction',
      onDone: widget.onDone,
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StudioTextAction(
            icon: Icons.auto_fix_high_rounded,
            label: 'Auto',
            onTap: _autoCorrect,
          ),
          StudioTextAction(
            icon: Icons.refresh_rounded,
            label: 'Reset',
            onTap: () {
              widget.onLive(clip.copyWith(adjust: const StudioAdjust()));
              widget.onCommit();
              setState(() => _aiSummary = null);
            },
          ),
          StudioTextAction(icon: Icons.layers_outlined, label: 'Apply all', onTap: widget.onApplyAll),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mode Sub-Tabs: Correction | Wheels | Curves | AI Grade
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: Row(
              children: [
                _modeTab(0, Icons.tune_rounded, 'Correction'),
                const SizedBox(width: 6),
                _modeTab(1, Icons.album_outlined, 'Color Wheels'),
                const SizedBox(width: 6),
                _modeTab(2, Icons.show_chart_rounded, 'Curves'),
                const SizedBox(width: 6),
                _modeTab(3, Icons.auto_awesome_rounded, 'AI Grade'),
              ],
            ),
          ),
          if (_tab == 0) _buildCorrectionTab(clip),
          if (_tab == 1) _buildColorWheelsTab(clip),
          if (_tab == 2) _buildCurvesTab(clip),
          if (_tab == 3) _buildAiGradeTab(clip),
        ],
      ),
    );
  }

  Widget _modeTab(int idx, IconData icon, String label) {
    final active = _tab == idx;
    final isAi = idx == 3;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _tab = idx);
        },
        child: Container(
          height: 30,
          decoration: BoxDecoration(
            color: active
                ? (isAi ? AppColors.brandPink : AppColors.brandBlue)
                : context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: active
                  ? (isAi ? AppColors.brandPink : AppColors.brandBlue)
                  : context.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: active
                    ? AppColors.brandWhite
                    : (isAi ? AppColors.brandPink : context.textSecondary),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: active ? AppColors.brandWhite : context.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCorrectionTab(StudioClip clip) {
    final value = clip.adjust.valueOf(_key);
    final isPositiveOnly = _key == 'fade' || StudioAdjust.positiveKeys.contains(_key);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 76,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            children: [
              for (final e in _meta.entries)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _key = e.key);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: context.surfaceMid,
                            border: Border.all(
                              color: e.key == _key ? AppColors.brandBlue : context.border,
                              width: e.key == _key ? 2 : 1,
                            ),
                          ),
                          child: Icon(
                            e.value.$2,
                            size: 19,
                            color: clip.adjust.valueOf(e.key) != 0 ? AppColors.brandBlue : context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          e.value.$1,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: e.key == _key ? context.textPrimary : context.textSecondary,
                            fontWeight: e.key == _key ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: StudioSliderRow(
            label: _meta[_key]!.$1,
            value: value * 100,
            min: isPositiveOnly ? 0 : -100,
            max: 100,
            format: (v) => '${v.round()}',
            onChanged: (v) => widget.onLive(clip.copyWith(adjust: clip.adjust.withValue(_key, v / 100))),
            onChangeEnd: (_) => widget.onCommit(),
          ),
        ),
      ],
    );
  }

  Widget _buildColorWheelsTab(StudioClip clip) {
    final a = clip.adjust;
    final (rKey, gKey, bKey, title) = switch (_wheelIndex) {
      0 => ('liftR', 'liftG', 'liftB', 'Lift · Shadows'),
      1 => ('gammaR', 'gammaG', 'gammaB', 'Gamma · Midtones'),
      _ => ('gainR', 'gainG', 'gainB', 'Gain · Highlights'),
    };
    final r = a.valueOf(rKey);
    final g = a.valueOf(gKey);
    final b = a.valueOf(bKey);

    void setRgb(double nr, double ng, double nb, {bool commit = false}) {
      widget.onLive(clip.copyWith(
        adjust: a.withValues({
          rKey: nr.clamp(-1.0, 1.0),
          gKey: ng.clamp(-1.0, 1.0),
          bKey: nb.clamp(-1.0, 1.0),
        }),
      ));
      if (commit) widget.onCommit();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (final w in const [(0, 'Shadows (Lift)'), (1, 'Midtones (Gamma)'), (2, 'Highlights (Gain)')])
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _wheelIndex = w.$1),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      decoration: BoxDecoration(
                        color: _wheelIndex == w.$1 ? AppColors.brandBlue.withValues(alpha: 0.16) : context.surfaceMid,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(
                          color: _wheelIndex == w.$1 ? AppColors.brandBlue : context.border,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        w.$2,
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: _wheelIndex == w.$1 ? FontWeight.w800 : FontWeight.w600,
                          color: _wheelIndex == w.$1 ? AppColors.brandBlue : context.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Interactive 2D Color Wheel Puck
              _StudioColorWheelPad(
                r: r,
                g: g,
                b: b,
                size: 98,
                onChanged: (nr, ng, nb) => setRgb(nr, ng, nb),
                onEnd: () => widget.onCommit(),
              ),
              const SizedBox(width: 12),
              // Fine RGB Channel Sliders for active wheel
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: context.textPrimary),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setRgb(0, 0, 0, commit: true),
                          child: Text(
                            'Zero wheel',
                            style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.brandPink),
                          ),
                        ),
                      ],
                    ),
                    _compactChannelSlider('Red', r, const Color(0xFFEF4444), (v) => setRgb(v, g, b), () => widget.onCommit()),
                    _compactChannelSlider('Green', g, const Color(0xFF22C55E), (v) => setRgb(r, v, b), () => widget.onCommit()),
                    _compactChannelSlider('Blue', b, const Color(0xFF3B82F6), (v) => setRgb(r, g, v), () => widget.onCommit()),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _compactChannelSlider(String label, double val, Color color, ValueChanged<double> onChanged, VoidCallback onEnd) {
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(label, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                activeTrackColor: color,
                inactiveTrackColor: context.border,
                thumbColor: color,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: val.clamp(-1.0, 1.0),
                min: -1.0,
                max: 1.0,
                onChanged: onChanged,
                onChangeEnd: (_) => onEnd(),
              ),
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              '${(val * 100).round()}',
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: context.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurvesTab(StudioClip clip) {
    final a = clip.adjust;
    final activePreset = a.curvePreset.round();
    const presets = <(int, String, List<Offset>)>[
      (0, 'Linear', [Offset(0, 0), Offset(0.33, 0.33), Offset(0.66, 0.66), Offset(1, 1)]),
      (1, 'S-Curve', [Offset(0, 0), Offset(0.25, 0.16), Offset(0.75, 0.84), Offset(1, 1)]),
      (2, 'Matte Lift', [Offset(0, 0.12), Offset(0.3, 0.28), Offset(0.75, 0.76), Offset(1, 0.92)]),
      (3, 'Crisp Hi', [Offset(0, 0), Offset(0.35, 0.31), Offset(0.75, 0.88), Offset(1, 1)]),
      (4, 'Noir Crush', [Offset(0, 0), Offset(0.22, 0.05), Offset(0.65, 0.72), Offset(1, 0.98)]),
    ];
    final currentPts = presets.firstWhere((p) => p.$1 == activePreset, orElse: () => presets.first).$3;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final p in presets)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(p.$2),
                      selected: activePreset == p.$1,
                      visualDensity: VisualDensity.compact,
                      selectedColor: AppColors.brandBlue,
                      backgroundColor: context.surfaceMid,
                      labelStyle: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: activePreset == p.$1 ? AppColors.brandWhite : context.textSecondary,
                      ),
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        widget.onLive(clip.copyWith(adjust: a.withValue('curvePreset', p.$1.toDouble())));
                        widget.onCommit();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: context.border),
                ),
                child: CustomPaint(
                  painter: _ToneCurvePreviewPainter(points: currentPts, color: AppColors.brandBlue, gridColor: context.border),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _compactChannelSlider(
                      'Blacks',
                      a.blacks,
                      context.textPrimary,
                      (v) => widget.onLive(clip.copyWith(adjust: a.withValue('blacks', v))),
                      () => widget.onCommit(),
                    ),
                    _compactChannelSlider(
                      'Shadows',
                      a.shadows,
                      context.textSecondary,
                      (v) => widget.onLive(clip.copyWith(adjust: a.withValue('shadows', v))),
                      () => widget.onCommit(),
                    ),
                    _compactChannelSlider(
                      'Hilights',
                      a.highlights,
                      AppColors.brandBlue,
                      (v) => widget.onLive(clip.copyWith(adjust: a.withValue('highlights', v))),
                      () => widget.onCommit(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAiGradeTab(StudioClip clip) {
    const chips = <(String, IconData)>[
      ('Teal & Orange Cinema', Icons.movie_filter_rounded),
      ('Golden Hour Sunlight', Icons.wb_sunny_rounded),
      ('Studio Skin & Melanin', Icons.face_retouching_natural_rounded),
      ('Vivid HDR Pop', Icons.hdr_auto_rounded),
      ('Kodak 2383 Matte Film', Icons.camera_roll_outlined),
      ('Cyberpunk Neon Night', Icons.nightlight_round),
      ('Silver Noir B&W', Icons.contrast_rounded),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in chips)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      avatar: Icon(c.$2, size: 14, color: AppColors.brandPink),
                      label: Text(c.$1),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: context.surfaceMid,
                      side: BorderSide(color: context.border),
                      labelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: context.textPrimary),
                      onPressed: _aiBusy ? null : () => _applyAiPrompt(c.$1),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _aiCtrl,
                    style: GoogleFonts.inter(fontSize: 12, color: context.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Ask AI Colorist (e.g. "Warm sunset with teal shadows")',
                      hintStyle: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted),
                      filled: true,
                      fillColor: context.surfaceMid,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: BorderSide(color: context.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: BorderSide(color: context.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: const BorderSide(color: AppColors.brandPink),
                      ),
                    ),
                    onSubmitted: _applyAiPrompt,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandPink,
                    foregroundColor: AppColors.brandWhite,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  onPressed: _aiBusy
                      ? null
                      : () => _applyAiPrompt(_aiCtrl.text.trim().isEmpty ? 'Auto Optical Balance' : _aiCtrl.text),
                  icon: _aiBusy
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandWhite),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 15),
                  label: Text('Grade', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
          if (_aiSummary != null) ...[
            const SizedBox(height: 6),
            Text(
              _aiSummary!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.brandPink),
            ),
          ],
        ],
      ),
    );
  }
}

class _StudioColorWheelPad extends StatelessWidget {
  final double r;
  final double g;
  final double b;
  final double size;
  final void Function(double r, double g, double b) onChanged;
  final VoidCallback onEnd;

  const _StudioColorWheelPad({
    required this.r,
    required this.g,
    required this.b,
    required this.size,
    required this.onChanged,
    required this.onEnd,
  });

  void _updateFromOffset(Offset local) {
    final radius = size / 2;
    final dx = ((local.dx - radius) / radius).clamp(-1.0, 1.0);
    final dy = ((local.dy - radius) / radius).clamp(-1.0, 1.0);
    final dist = math.min(1.0, math.sqrt(dx * dx + dy * dy));
    final angle = math.atan2(dy, dx);
    var deg = angle * 180 / math.pi;
    if (deg < 0) deg += 360;
    final c = HSVColor.fromAHSV(1.0, deg, dist, 1.0).toColor();
    // Convert color tint on wheel to signed RGB offsets (-1..1) around neutral
    final nr = ((c.r - 0.5) * 2 * dist).clamp(-1.0, 1.0);
    final ng = ((c.g - 0.5) * 2 * dist).clamp(-1.0, 1.0);
    final nb = ((c.b - 0.5) * 2 * dist).clamp(-1.0, 1.0);
    onChanged(nr, ng, nb);
  }

  @override
  Widget build(BuildContext context) {
    final radius = size / 2;
    // Approximate puck position from (r, g, b)
    final px = (r - b * 0.5 - g * 0.5).clamp(-1.0, 1.0);
    final py = ((b - g) * 0.866).clamp(-1.0, 1.0);

    return GestureDetector(
      onPanDown: (d) => _updateFromOffset(d.localPosition),
      onPanUpdate: (d) => _updateFromOffset(d.localPosition),
      onPanEnd: (_) => onEnd(),
      onDoubleTap: () {
        onChanged(0, 0, 0);
        onEnd();
      },
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: context.border, width: 1.5),
                gradient: const SweepGradient(
                  colors: [
                    Color(0xFFFF3B30),
                    Color(0xFFFFCC00),
                    Color(0xFF34C759),
                    Color(0xFF5AC8FA),
                    Color(0xFF007AFF),
                    Color(0xFFAF52DE),
                    Color(0xFFFF3B30),
                  ],
                ),
              ),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0xEE1E1E24), Color(0x331E1E24)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: radius + px * (radius - 10) - 7,
              top: radius + py * (radius - 10) - 7,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brandWhite,
                  border: Border.all(color: AppColors.brandBlack, width: 2),
                  boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToneCurvePreviewPainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final Color gridColor;

  const _ToneCurvePreviewPainter({required this.points, required this.color, required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    final gPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(Offset(size.width * i / 3, 0), Offset(size.width * i / 3, size.height), gPaint);
      canvas.drawLine(Offset(0, size.height * i / 3), Offset(size.width, size.height * i / 3), gPaint);
    }
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), gPaint);

    if (points.length < 2) return;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = points[i].dx * size.width;
      final y = (1 - points[i].dy) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    for (final pt in points) {
      canvas.drawCircle(
        Offset(pt.dx * size.width, (1 - pt.dy) * size.height),
        3.0,
        Paint()..color = AppColors.brandWhite,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ToneCurvePreviewPainter old) => old.points != points || old.color != color;
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
