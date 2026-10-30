import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../../models/oneova_look.dart';
import '../controllers/photo_grading_controller.dart';
import '../models/photo_grading_models.dart';
import 'photo_color_wheels_widget.dart';

/// Professional multi-node grading deck providing precision parameter control.
class PhotoProNodesDeck extends ConsumerStatefulWidget {
  final PhotoGradingState state;

  const PhotoProNodesDeck({
    super.key,
    required this.state,
  });

  @override
  ConsumerState<PhotoProNodesDeck> createState() => _PhotoProNodesDeckState();
}

class _PhotoProNodesDeckState extends ConsumerState<PhotoProNodesDeck> {
  String _activeHslBand = 'red';

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(photoGradingControllerProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.outline : AppColors.lightBorder;
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;

    final look = widget.state.currentLook;
    final activeTab = widget.state.activeProTab;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(top: BorderSide(color: borderColor, width: 1.0)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Node Tabs Carousel
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: PhotoProNodeTab.values.length,
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final tab = PhotoProNodeTab.values[index];
                final isSelected = activeTab == tab;

                return InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    controller.setActiveProTab(tab);
                  },
                  borderRadius: BorderRadius.circular(6.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.brandBlue
                          : (isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight),
                      borderRadius: BorderRadius.circular(6.0),
                      border: Border.all(
                        color: isSelected ? AppColors.brandBlue : borderColor,
                        width: 1.0,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      tab.label,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? Colors.white : textPrimary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Active Node Controls
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: switch (activeTab) {
                PhotoProNodeTab.primary => _buildPrimaryControls(look, controller),
                PhotoProNodeTab.wheels => PhotoColorWheelsWidget(
                    wheels: look.wheels,
                    onWheelsChanged: (w) => controller.updateWheels(
                      lift: w.lift,
                      gamma: w.gamma,
                      gain: w.gain,
                      offset: w.offset,
                    ),
                  ),
                PhotoProNodeTab.color => _buildColorControls(look, controller),
                PhotoProNodeTab.curves => _buildCurvesControls(look, controller),
                PhotoProNodeTab.hsl => _buildHslControls(look, controller),
                PhotoProNodeTab.film => _buildFilmControls(look, controller),
                PhotoProNodeTab.detail => _buildDetailControls(look, controller),
                PhotoProNodeTab.optics => _buildOpticsControls(look, controller),
                PhotoProNodeTab.boostBeauty => _buildBoostBeautyControls(look, controller),
                PhotoProNodeTab.background => _buildBackgroundControls(look, controller),
                PhotoProNodeTab.masks => _buildMasksControls(look, controller),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryControls(OneovaLook look, PhotoGradingController controller) {
    return Column(
      children: [
        _buildSlider('Exposure', look.primary.exposure, -2.0, 2.0, '${look.primary.exposure.toStringAsFixed(2)} EV', (v) => controller.updatePrimary(exposure: v)),
        _buildSlider('Contrast', look.primary.contrast, 0.5, 2.0, '${look.primary.contrast.toStringAsFixed(2)}x', (v) => controller.updatePrimary(contrast: v)),
        _buildSlider('Highlights', look.primary.highlights, -1.0, 1.0, '${(look.primary.highlights * 100).toInt()}%', (v) => controller.updatePrimary(highlights: v)),
        _buildSlider('Shadows', look.primary.shadows, -1.0, 1.0, '${(look.primary.shadows * 100).toInt()}%', (v) => controller.updatePrimary(shadows: v)),
        _buildSlider('Whites', look.primary.whites, -1.0, 1.0, '${(look.primary.whites * 100).toInt()}%', (v) => controller.updatePrimary(whites: v)),
        _buildSlider('Blacks', look.primary.blacks, -1.0, 1.0, '${(look.primary.blacks * 100).toInt()}%', (v) => controller.updatePrimary(blacks: v)),
      ],
    );
  }

  Widget _buildColorControls(OneovaLook look, PhotoGradingController controller) {
    return Column(
      children: [
        _buildSlider('Temperature', look.color.temperature, -100.0, 100.0, '${look.color.temperature.toInt()}', (v) => controller.updateColor(temperature: v)),
        _buildSlider('Tint', look.color.tint, -100.0, 100.0, '${look.color.tint.toInt()}', (v) => controller.updateColor(tint: v)),
        _buildSlider('Vibrance', look.color.vibrance, -1.0, 1.0, '${(look.color.vibrance * 100).toInt()}%', (v) => controller.updateColor(vibrance: v)),
        _buildSlider('Saturation', look.color.saturation, 0.0, 2.0, '${(look.color.saturation * 100).toInt()}%', (v) => controller.updateColor(saturation: v)),
        _buildSlider('Color Boost', look.color.colorBoost, -1.0, 1.0, '${(look.color.colorBoost * 100).toInt()}%', (v) => controller.updateColor(colorBoost: v)),
      ],
    );
  }

  Widget _buildCurvesControls(OneovaLook look, PhotoGradingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['Master RGB', 'Red', 'Green', 'Blue'].map((channel) {
              return Chip(
                label: Text(channel, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600)),
                backgroundColor: AppColors.brandBlue.withValues(alpha: 0.15),
                side: const BorderSide(color: AppColors.brandBlue, width: 1.0),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: AppColors.outline, width: 1.0),
            ),
            alignment: Alignment.center,
            child: Text(
              'Interactive Spline Curve Graph (0..255)',
              style: GoogleFonts.inter(fontSize: 11.0, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHslControls(OneovaLook look, PhotoGradingController controller) {
    final bands = ['red', 'orange', 'yellow', 'green', 'aqua', 'blue', 'purple', 'magenta'];
    final activeBandData = switch (_activeHslBand) {
      'red' => look.hsl.red,
      'orange' => look.hsl.orange,
      'yellow' => look.hsl.yellow,
      'green' => look.hsl.green,
      'aqua' => look.hsl.aqua,
      'blue' => look.hsl.blue,
      'purple' => look.hsl.purple,
      _ => look.hsl.magenta,
    };

    return Column(
      children: [
        // Band selector chips
        Wrap(
          spacing: 6.0,
          children: bands.map((band) {
            final isSelected = _activeHslBand == band;
            return ChoiceChip(
              label: Text(
                band[0].toUpperCase() + band.substring(1),
                style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600),
              ),
              selected: isSelected,
              onSelected: (_) => setState(() => _activeHslBand = band),
              selectedColor: AppColors.brandBlue,
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        _buildSlider('Hue Shift', activeBandData.hue, -180.0, 180.0, '${activeBandData.hue.toInt()}°', (v) => controller.updateHslBand(_activeHslBand, hue: v)),
        _buildSlider('Saturation', activeBandData.sat, -1.0, 1.0, '${(activeBandData.sat * 100).toInt()}%', (v) => controller.updateHslBand(_activeHslBand, sat: v)),
        _buildSlider('Luminance', activeBandData.lum, -1.0, 1.0, '${(activeBandData.lum * 100).toInt()}%', (v) => controller.updateHslBand(_activeHslBand, lum: v)),
      ],
    );
  }

  Widget _buildFilmControls(OneovaLook look, PhotoGradingController controller) {
    return Column(
      children: [
        _buildSlider('Halation', look.film.halation, 0.0, 1.0, '${(look.film.halation * 100).toInt()}%', (v) => controller.updateFilm(halation: v)),
        _buildSlider('Bloom', look.film.bloom, 0.0, 1.0, '${(look.film.bloom * 100).toInt()}%', (v) => controller.updateFilm(bloom: v)),
        _buildSlider('Grain Intensity', look.film.grain, 0.0, 1.0, '${(look.film.grain * 100).toInt()}%', (v) => controller.updateFilm(grain: v)),
        _buildSlider('Grain Roughness', look.film.grainRoughness, 0.0, 1.0, '${(look.film.grainRoughness * 100).toInt()}%', (v) => controller.updateFilm(grainRoughness: v)),
        _buildSlider('Film Fade', look.film.fade, 0.0, 1.0, '${(look.film.fade * 100).toInt()}%', (v) => controller.updateFilm(fade: v)),
      ],
    );
  }

  Widget _buildDetailControls(OneovaLook look, PhotoGradingController controller) {
    return Column(
      children: [
        _buildSlider('Sharpen', look.detail.sharpen, 0.0, 1.0, '${(look.detail.sharpen * 100).toInt()}%', (v) => controller.updateDetail(sharpen: v)),
        _buildSlider('Clarity', look.detail.clarity, -1.0, 1.0, '${(look.detail.clarity * 100).toInt()}%', (v) => controller.updateDetail(clarity: v)),
        _buildSlider('Texture', look.detail.texture, -1.0, 1.0, '${(look.detail.texture * 100).toInt()}%', (v) => controller.updateDetail(texture: v)),
        _buildSlider('Dehaze', look.detail.dehaze, -1.0, 1.0, '${(look.detail.dehaze * 100).toInt()}%', (v) => controller.updateDetail(dehaze: v)),
      ],
    );
  }

  Widget _buildOpticsControls(OneovaLook look, PhotoGradingController controller) {
    return Column(
      children: [
        _buildSlider('Vignette', look.optics.vignette, 0.0, 1.0, '${(look.optics.vignette * 100).toInt()}%', (v) => controller.updateOptics(vignette: v)),
        _buildSlider('Chromatic Aberration', look.optics.chromaticAberration, 0.0, 1.0, '${(look.optics.chromaticAberration * 100).toInt()}%', (v) => controller.updateOptics(chromaticAberration: v)),
        _buildSlider('Lens Distortion', look.optics.lensDistortion, -1.0, 1.0, '${(look.optics.lensDistortion * 100).toInt()}%', (v) => controller.updateOptics(lensDistortion: v)),
      ],
    );
  }

  Widget _buildBoostBeautyControls(OneovaLook look, PhotoGradingController controller) {
    final bb = look.boostBeauty;
    return Column(
      children: [
        SwitchListTile(
          dense: true,
          title: Text('Boost Beauty Active', style: GoogleFonts.inter(fontSize: 12.0, fontWeight: FontWeight.w600)),
          value: bb.isEnabled,
          activeThumbColor: AppColors.brandPink,
          onChanged: (val) => controller.updateBoostBeauty(isEnabled: val),
        ),
        _buildSlider('Smooth Skin', bb.smoothSkin, 0.0, 1.0, '${(bb.smoothSkin * 100).toInt()}%', (v) => controller.updateBoostBeauty(smoothSkin: v)),
        _buildSlider('Even Tone', bb.evenTone, 0.0, 1.0, '${(bb.evenTone * 100).toInt()}%', (v) => controller.updateBoostBeauty(evenTone: v)),
        _buildSlider('Eye Brighten', bb.eyeBrighten, 0.0, 1.0, '${(bb.eyeBrighten * 100).toInt()}%', (v) => controller.updateBoostBeauty(eyeBrighten: v)),
        _buildSlider('Teeth Whitening', bb.teethWhitening, 0.0, 1.0, '${(bb.teethWhitening * 100).toInt()}%', (v) => controller.updateBoostBeauty(teethWhitening: v)),
        _buildSlider('Face Slim', bb.faceSlim, 0.0, 1.0, '${(bb.faceSlim * 100).toInt()}%', (v) => controller.updateBoostBeauty(faceSlim: v)),
      ],
    );
  }

  Widget _buildBackgroundControls(OneovaLook look, PhotoGradingController controller) {
    final bg = look.background;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['none', 'blur', 'color', 'replace'].map((m) {
            final isSelected = bg.mode == m;
            return ChoiceChip(
              label: Text(m.toUpperCase(), style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600)),
              selected: isSelected,
              onSelected: (_) => controller.updateBackground(mode: m),
              selectedColor: AppColors.brandBlue,
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        if (bg.mode == 'blur')
          _buildSlider('Depth Blur', bg.blurLevel, 0.0, 1.0, '${(bg.blurLevel * 100).toInt()}%', (v) => controller.updateBackground(blurLevel: v)),
      ],
    );
  }

  Widget _buildMasksControls(OneovaLook look, PhotoGradingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['Skin/Face', 'Hair', 'Sky', 'Subject'].map((mask) {
              return Chip(
                avatar: const Icon(Icons.auto_fix_high_rounded, size: 14, color: AppColors.brandPink),
                label: Text(mask, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600)),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text('Semantic masks target grades to specific image segments', style: GoogleFonts.inter(fontSize: 11.0, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, String display, ValueChanged<double> onChanged) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final textMuted = isDark ? AppColors.textMuted : AppColors.lightTextMuted;

    return Row(
      children: [
        SizedBox(
          width: 85,
          child: Text(label, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w500, color: textPrimary)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
              activeTrackColor: AppColors.brandBlue,
              inactiveTrackColor: isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0),
              thumbColor: AppColors.brandBlue,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                onChanged(v);
              },
            ),
          ),
        ),
        SizedBox(
          width: 55,
          child: Text(display, textAlign: TextAlign.end, style: GoogleFonts.inter(fontSize: 11.0, fontWeight: FontWeight.w600, color: textMuted)),
        ),
      ],
    );
  }
}
