// Beauty controls for the go-live setup: one-tap looks plus fine sliders
// grouped by Skin / Face / Eyes & smile. Changes preview on the camera
// track as soon as a slider is released or a look is picked.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import 'live_setup_config.dart';

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
    required this.onEnabled,
    required this.onChanged,
    required this.onCommit,
  });

  final bool enabled;
  final LiveBeauty beauty;
  final ValueChanged<bool> onEnabled;

  /// Every slider tick (UI only).
  final ValueChanged<LiveBeauty> onChanged;

  /// Apply to the camera (slider released, look picked, reset).
  final VoidCallback onCommit;

  @override
  State<LiveBeautyPanel> createState() => _LiveBeautyPanelState();
}

class _LiveBeautyPanelState extends State<LiveBeautyPanel> {
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

  void _pick(LiveBeauty b) {
    HapticFeedback.selectionClick();
    widget.onChanged(b);
    widget.onCommit();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled;
    final b = widget.beauty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: on ? AppColors.brandPink.withValues(alpha: 0.45) : context.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Header + master switch.
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: on
                    ? const LinearGradient(colors: [AppColors.brandPink, AppColors.brandBlue])
                    : null,
                color: on ? null : context.surfaceMid,
              ),
              child: Icon(Icons.auto_awesome_rounded, size: 19, color: on ? Colors.white : context.textMuted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Beauty',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: context.textPrimary)),
                const SizedBox(height: 2),
                Text(on ? 'Live on your camera now' : 'Skin, face and eyes, kept natural',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12, color: context.textMuted)),
              ]),
            ),
            Switch.adaptive(
              value: on,
              activeTrackColor: AppColors.brandPink,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                widget.onEnabled(v);
              },
            ),
          ]),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !on
              ? const SizedBox(width: double.infinity)
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Divider(height: 1, color: context.border),
                  // One-tap looks.
                  SizedBox(
                    height: 86,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      children: [
                        for (final (name, icon, look) in LiveBeauty.presets)
                          _LookChip(name: name, icon: icon, selected: b == look, onTap: () => _pick(look)),
                        _LookChip(
                          name: 'Clear',
                          icon: Icons.block_rounded,
                          selected: b == const LiveBeauty(),
                          onTap: () => _pick(const LiveBeauty()),
                        ),
                      ],
                    ),
                  ),
                  // Group switch.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: context.surfaceMid,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(children: [
                        for (final g in _BeautyGroup.values)
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _group = g);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                height: 34,
                                decoration: BoxDecoration(
                                  color: _group == g ? AppColors.brandBlue : Colors.transparent,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Icon(g.icon, size: 15, color: _group == g ? Colors.white : context.textMuted),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(g.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: _group == g ? Colors.white : context.textSecondary)),
                                  ),
                                ]),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final (label, value, apply) in _sliders(b))
                    _BeautySlider(
                      label: label,
                      value: value,
                      onChanged: (v) => widget.onChanged(apply(v)),
                      onChangeEnd: (_) => widget.onCommit(),
                    ),
                  const SizedBox(height: 8),
                ]),
        ),
      ]),
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
        padding: const EdgeInsets.only(right: 10),
        child: Semantics(
          button: true,
          selected: selected,
          label: '$name look',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: onTap,
            child: SizedBox(
              width: 58,
              child: Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppColors.brandPink.withValues(alpha: 0.14) : context.surfaceMid,
                    border: Border.all(color: selected ? AppColors.brandPink : context.border, width: selected ? 2 : 1),
                  ),
                  child: Icon(icon, size: 20, color: selected ? AppColors.brandPink : context.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected ? context.textPrimary : context.textMuted)),
              ]),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
      child: Row(children: [
        SizedBox(
          width: 92,
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: context.textSecondary)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: AppColors.brandPink,
              inactiveTrackColor: context.surfaceMid,
              thumbColor: Colors.white,
              overlayColor: AppColors.brandPink.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9, elevation: 2),
            ),
            child: Slider(value: v, onChanged: onChanged, onChangeEnd: onChangeEnd),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text('${(v * 100).round()}',
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: context.textMuted)),
        ),
      ]),
    );
  }
}
