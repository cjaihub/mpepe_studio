import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../../models/oneova_look.dart';
import '../controllers/photo_grading_controller.dart';
import '../models/photo_grading_models.dart';

/// Streamlined Simple Mode grading deck for creators.
///
/// Features a preset look carousel, master intensity slider, and primary macro sliders.
class PhotoSimpleGradingDeck extends ConsumerWidget {
  final PhotoGradingState state;

  const PhotoSimpleGradingDeck({
    super.key,
    required this.state,
  });

  static final List<OneovaLook> _starterPresets = [
    const OneovaLook(
      id: 'look_cinematic_gold',
      name: 'Cinematic Gold',
      categories: ['cinematic'],
      primary: LookPrimary(exposure: 0.15, contrast: 1.15, highlights: -0.15, shadows: 0.1),
      color: LookColor(temperature: 18.0, tint: -4.0, vibrance: 0.2, saturation: 1.05),
      film: LookFilm(emulationProfile: 'kodak_gold_200', halation: 0.25, grain: 0.12),
    ),
    const OneovaLook(
      id: 'look_clean_portrait',
      name: 'Clean Portrait',
      categories: ['portrait'],
      primary: LookPrimary(exposure: 0.2, contrast: 1.05, highlights: -0.1, shadows: 0.15),
      color: LookColor(temperature: 5.0, tint: 2.0, vibrance: 0.15, saturation: 1.0),
      boostBeauty: BoostBeautyConfig(isEnabled: true, smoothSkin: 0.45, evenTone: 0.35, eyeBrighten: 0.3),
    ),
    const OneovaLook(
      id: 'look_vintage_16mm',
      name: '16mm Vintage',
      categories: ['film'],
      primary: LookPrimary(exposure: -0.1, contrast: 1.25, whites: -0.15, blacks: 0.2),
      color: LookColor(temperature: -8.0, tint: 12.0, saturation: 0.9),
      film: LookFilm(emulationProfile: 'fuji_pro_400h', halation: 0.4, grain: 0.35, fade: 0.15),
      optics: LookOptics(vignette: 0.35, chromaticAberration: 0.2),
    ),
    const OneovaLook(
      id: 'look_monolith_bw',
      name: 'Monolith B&W',
      categories: ['bw'],
      primary: LookPrimary(exposure: 0.05, contrast: 1.35, shadows: -0.2, whites: 0.1),
      color: LookColor(saturation: 0.0),
      film: LookFilm(emulationProfile: 'ilford_hp5', grain: 0.28),
    ),
    const OneovaLook(
      id: 'look_cyberpunk_neon',
      name: 'Cyberpunk Neon',
      categories: ['creative'],
      primary: LookPrimary(contrast: 1.3, shadows: 0.1, highlights: -0.2),
      color: LookColor(temperature: -24.0, tint: 26.0, vibrance: 0.45, saturation: 1.25),
      film: LookFilm(bloom: 0.4, halation: 0.3),
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(photoGradingControllerProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final look = state.currentLook;

    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.outline : AppColors.lightBorder;
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(top: BorderSide(color: borderColor, width: 1.0)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Preset Carousel
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _starterPresets.length + 1,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  // Neutral / Reset
                  final isNeutral = look.isNeutral;
                  return InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      controller.resetToBaseline();
                    },
                    borderRadius: BorderRadius.circular(8.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isNeutral
                            ? AppColors.brandBlue.withValues(alpha: 0.2)
                            : (isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight),
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(
                          color: isNeutral ? AppColors.brandBlue : borderColor,
                          width: 1.0,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Original Neutral',
                        style: GoogleFonts.inter(
                          fontSize: 12.0,
                          fontWeight: FontWeight.w600,
                          color: isNeutral ? AppColors.brandBlue : textPrimary,
                        ),
                      ),
                    ),
                  );
                }

                final preset = _starterPresets[index - 1];
                final isSelected = look.id == preset.id;
                return InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    controller.applyPreset(preset, intensity: look.intensity);
                  },
                  borderRadius: BorderRadius.circular(8.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.brandBlue.withValues(alpha: 0.2)
                          : (isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight),
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(
                        color: isSelected ? AppColors.brandBlue : borderColor,
                        width: 1.0,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected) ...[
                          const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.brandBlue),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          preset.name,
                          style: GoogleFonts.inter(
                            fontSize: 12.0,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? AppColors.brandBlue : textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          // Master Look Intensity Slider
          _buildMacroSlider(
            context: context,
            label: 'Look Intensity',
            value: look.intensity,
            min: 0.0,
            max: 1.0,
            displayValue: '${(look.intensity * 100).toInt()}%',
            activeColor: AppColors.brandBlue,
            onChanged: (val) => controller.setLookIntensity(val),
          ),

          const SizedBox(height: 6),

          // Exposure Slider
          _buildMacroSlider(
            context: context,
            label: 'Exposure',
            value: look.primary.exposure,
            min: -2.0,
            max: 2.0,
            displayValue: '${look.primary.exposure > 0 ? "+" : ""}${look.primary.exposure.toStringAsFixed(2)} EV',
            activeColor: AppColors.brandPink,
            onChanged: (val) => controller.updatePrimary(exposure: val),
          ),

          const SizedBox(height: 6),

          // Warmth (Temperature)
          _buildMacroSlider(
            context: context,
            label: 'Warmth',
            value: look.color.temperature,
            min: -100.0,
            max: 100.0,
            displayValue: '${look.color.temperature.toInt()}',
            activeColor: Colors.amberAccent,
            onChanged: (val) => controller.updateColor(temperature: val),
          ),

          const SizedBox(height: 6),

          // Contrast
          _buildMacroSlider(
            context: context,
            label: 'Contrast',
            value: look.primary.contrast,
            min: 0.5,
            max: 2.0,
            displayValue: '${look.primary.contrast.toStringAsFixed(2)}x',
            activeColor: Colors.tealAccent,
            onChanged: (val) => controller.updatePrimary(contrast: val),
          ),

          const SizedBox(height: 6),

          // Boost Beauty Glow
          _buildMacroSlider(
            context: context,
            label: 'Boost Beauty',
            value: look.boostBeauty.smoothSkin,
            min: 0.0,
            max: 1.0,
            displayValue: '${(look.boostBeauty.smoothSkin * 100).toInt()}%',
            activeColor: AppColors.brandPink,
            onChanged: (val) => controller.updateBoostBeauty(
              isEnabled: val > 0.01,
              smoothSkin: val,
              evenTone: val * 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroSlider({
    required BuildContext context,
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required Color activeColor,
    required ValueChanged<double> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final textMuted = isDark ? AppColors.textMuted : AppColors.lightTextMuted;

    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12.0,
              fontWeight: FontWeight.w500,
              color: textPrimary,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
              activeTrackColor: activeColor,
              inactiveTrackColor: isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0),
              thumbColor: activeColor,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: (val) {
                HapticFeedback.selectionClick();
                onChanged(val);
              },
            ),
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(
            displayValue,
            textAlign: TextAlign.end,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
