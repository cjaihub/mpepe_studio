import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';

/// mm:ss for durations in ms.
String studioClock(int ms) {
  final s = (ms / 1000).floor();
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

/// mm:ss.d for the editor's time readout.
String studioClockFine(int ms) => '${studioClock(ms)}.${((ms % 1000) ~/ 100)}';

class StudioSheetHandle extends StatelessWidget {
  const StudioSheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          width: 36,
          height: 4,
          decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(AppRadius.full)),
        ),
      );
}

class StudioPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final IconData? icon;

  const StudioPrimaryButton({super.key, required this.label, this.onTap, this.busy = false, this.icon});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: AppColors.brandBlue,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: enabled
              ? () {
                  HapticFeedback.lightImpact();
                  onTap!();
                }
              : null,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            child: busy
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandWhite))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[Icon(icon, size: 16, color: AppColors.brandWhite), const SizedBox(width: 6)],
                      Text(label,
                          style: GoogleFonts.inter(color: AppColors.brandWhite, fontSize: 14, fontWeight: FontWeight.w700)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Icon over label, as in the editor's tool bars.
class StudioToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? color;
  final String? badge;

  const StudioToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.color,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.brandBlue : (color ?? context.textPrimary);
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(
        width: 70,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 24, color: fg),
                  if (badge != null)
                    Positioned(
                      right: -14,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.brandPink, borderRadius: BorderRadius.circular(AppRadius.xs)),
                        child: Text(badge!,
                            style: GoogleFonts.inter(color: AppColors.brandWhite, fontSize: 8.5, fontWeight: FontWeight.w800)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: fg, fontSize: 11, fontWeight: FontWeight.w600, height: 1.15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Labeled slider row used in the adjust/volume/speed panels.
class StudioSliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final int? divisions;

  const StudioSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
    this.onChangeEnd,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(label, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              activeTrackColor: AppColors.brandBlue,
              inactiveTrackColor: context.border,
              thumbColor: AppColors.brandWhite,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8, elevation: 2),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(format(value),
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

/// Cancel / confirm dialog; resolves true only on confirm.
Future<bool> studioConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: c.border)),
      title: Text(title, style: GoogleFonts.inter(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text(message, style: GoogleFonts.inter(color: c.textSecondary, fontSize: 13, height: 1.4)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text('Cancel', style: GoogleFonts.inter(color: c.textSecondary, fontWeight: FontWeight.w600)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirmLabel,
              style: GoogleFonts.inter(
                color: destructive ? AppColors.brandPink : AppColors.brandBlue,
                fontWeight: FontWeight.w700,
              )),
        ),
      ],
    ),
  );
  return ok == true;
}
