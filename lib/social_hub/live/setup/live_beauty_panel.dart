// Studio Effects, Cinema Looks, Key Lighting & Beauty Retouch panel for Go-Live setup.
// Every preset and slider updates the live camera preview in real time.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../looks/live/live_look_presets.dart';
import '../../../shared/theme/app_theme.dart';
import 'live_setup_config.dart';

enum _EffectsTab {
  beauty('Beauty', Icons.auto_awesome_rounded),
  looks('Cinema Looks', Icons.palette_rounded),
  lighting('Studio Light', Icons.flare_rounded);

  const _EffectsTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum _BeautyGroup {
  skin('Skin', Icons.face_retouching_natural_rounded),
  face('Face', Icons.face_rounded),
  eyes('Eyes & smile', Icons.visibility_rounded);

  const _BeautyGroup(this.label, this.icon);
  final String label;
  final IconData icon;
}

class LiveBeautyPanel extends StatefulWidget {
  const LiveBeautyPanel({
    super.key,
    required this.enabled,
    required this.beauty,
    this.lookId = 'neutral',
    this.lightingId = 'natural',
    required this.onEnabled,
    required this.onChanged,
    this.onLookChanged,
    this.onLightingChanged,
    required this.onCommit,
  });

  final bool enabled;
  final LiveBeauty beauty;
  final String lookId;
  final String lightingId;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<LiveBeauty> onChanged;
  final ValueChanged<String>? onLookChanged;
  final ValueChanged<String>? onLightingChanged;
  final VoidCallback onCommit;

  @override
  State<LiveBeautyPanel> createState() => _LiveBeautyPanelState();
}

class _LiveBeautyPanelState extends State<LiveBeautyPanel> {
  _EffectsTab _tab = _EffectsTab.beauty;
  _BeautyGroup _group = _BeautyGroup.skin;

  List<(String, double, LiveBeauty Function(double))> _sliders(LiveBeauty b) => switch (_group) {
        _BeautyGroup.skin => [
            ('Smooth', b.smooth, (v) => b.copyWith(smooth: v)),
            ('Even tone', b.tone, (v) => b.copyWith(tone: v)),
            ('Glow', b.glow, (v) => b.copyWith(glow: v)),
          ],
        _BeautyGroup.face => [
            ('Slim face', b.slim, (v) => b.copyWith(slim: v)),
            ('Jawline', b.jaw, (v) => b.copyWith(jaw: v)),
            ('Nose', b.nose, (v) => b.copyWith(nose: v)),
          ],
        _BeautyGroup.eyes => [
            ('Bigger eyes', b.eyes, (v) => b.copyWith(eyes: v)),
            ('Bright eyes', b.eyeLight, (v) => b.copyWith(eyeLight: v)),
            ('White smile', b.teeth, (v) => b.copyWith(teeth: v)),
          ],
      };

  void _pickBeauty(LiveBeauty b) {
    HapticFeedback.selectionClick();
    if (!widget.enabled) widget.onEnabled(true);
    widget.onChanged(b);
    widget.onCommit();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled;
    final b = widget.beauty;
    final hasEffects = on || widget.lookId != 'neutral' || widget.lightingId != 'natural';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: hasEffects ? AppColors.brandPink.withValues(alpha: 0.45) : context.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Compact top tab bar: Beauty | Cinema Looks | Studio Light + Beauty switch
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    children: [
                      for (final t in _EffectsTab.values)
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _tab = t);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              height: 30,
                              decoration: BoxDecoration(
                                color: _tab == t ? AppColors.brandBlue : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(t.icon, size: 13, color: _tab == t ? Colors.white : context.textMuted),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      t.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: _tab == t ? Colors.white : context.textSecondary,
                                      ),
                                    ),
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
              const SizedBox(width: 8),
              SizedBox(
                height: 30,
                child: Transform.scale(
                  scale: 0.82,
                  child: Switch.adaptive(
                    value: on,
                    activeTrackColor: AppColors.brandPink,
                    onChanged: (v) {
                      HapticFeedback.selectionClick();
                      widget.onEnabled(v);
                      widget.onCommit();
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_tab == _EffectsTab.looks)
            _buildLooksSection(context)
          else if (_tab == _EffectsTab.lighting)
            _buildLightingSection(context)
          else
            _buildBeautySection(context, on, b),
        ],
      ),
    );
  }

  Widget _buildLooksSection(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: liveLookPresets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final look = liveLookPresets[i];
          final selected = widget.lookId == look.id || (look.id == 'neutral' && widget.lookId.isEmpty);
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onLookChanged?.call(look.id);
              widget.onCommit();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? AppColors.brandBlue.withValues(alpha: 0.14) : context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: selected ? AppColors.brandBlue : context.border,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    look.id == 'neutral' ? Icons.tonality_rounded : Icons.movie_filter_rounded,
                    size: 16,
                    color: selected ? AppColors.brandBlue : context.textSecondary,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    look.name,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? context.textPrimary : context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLightingSection(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: liveLightingPresets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final light = liveLightingPresets[i];
          final selected = widget.lightingId == light.id || (light.id == 'natural' && widget.lightingId.isEmpty);
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onLightingChanged?.call(light.id);
              widget.onCommit();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? AppColors.brandPink.withValues(alpha: 0.14) : context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: selected ? AppColors.brandPink : context.border,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    light.icon,
                    size: 16,
                    color: selected ? AppColors.brandPink : context.textSecondary,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    light.name,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? context.textPrimary : context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBeautySection(BuildContext context, bool on, LiveBeauty b) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Compact one-tap beauty presets row
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final (name, icon, look) in LiveBeauty.presets)
                _LookChip(
                  name: name,
                  icon: icon,
                  selected: on && b == look,
                  onTap: () => _pickBeauty(look),
                ),
              _LookChip(
                name: 'Clear',
                icon: Icons.block_rounded,
                selected: !on || b == const LiveBeauty(),
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onChanged(const LiveBeauty());
                  widget.onCommit();
                },
              ),
            ],
          ),
        ),
        if (on) ...[
          const SizedBox(height: 8),
          // Compact Skin / Face / Eyes & smile sub-tabs
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                for (final g in _BeautyGroup.values)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _group = g);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        height: 26,
                        decoration: BoxDecoration(
                          color: _group == g ? AppColors.brandPink : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(g.icon, size: 12, color: _group == g ? Colors.white : context.textMuted),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                g.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _group == g ? Colors.white : context.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          for (final (label, value, apply) in _sliders(b))
            _BeautySlider(
              label: label,
              value: value,
              onChanged: (v) {
                widget.onChanged(apply(v));
                widget.onCommit();
              },
              onChangeEnd: (_) => widget.onCommit(),
            ),
        ],
      ],
    );
  }
}

class _LookChip extends StatelessWidget {
  const _LookChip({required this.name, required this.icon, required this.selected, required this.onTap});
  final String name;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: selected ? AppColors.brandPink.withValues(alpha: 0.14) : context.surfaceMid,
              border: Border.all(color: selected ? AppColors.brandPink : context.border, width: selected ? 1.5 : 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: selected ? AppColors.brandPink : context.textSecondary),
                const SizedBox(width: 4),
                Text(
                  name,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? context.textPrimary : context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _BeautySlider extends StatelessWidget {
  const _BeautySlider({required this.label, required this.value, required this.onChanged, required this.onChangeEnd});
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.textSecondary),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: AppColors.brandPink,
                inactiveTrackColor: context.surfaceMid,
                thumbColor: Colors.white,
                overlayColor: AppColors.brandPink.withValues(alpha: 0.12),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7, elevation: 1.5),
              ),
              child: Slider(value: v, onChanged: onChanged, onChangeEnd: onChangeEnd),
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '${(v * 100).round()}',
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: context.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
