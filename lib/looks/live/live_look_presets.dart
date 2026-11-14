import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/oneova_look.dart';

/// Color looks a host can put on the live camera (GPU track processor + real-time shader matrix).
/// Shared by the Go-Live Setup Wizard, the Live Control Hub, and the Studio Stage.
const liveLookPresets = <OneovaLook>[
  OneovaLook(id: 'neutral', name: 'Natural'),
  OneovaLook(
    id: 'portrait_glow',
    name: 'Portrait Glow',
    primary: LookPrimary(exposure: 0.14, contrast: 1.06, highlights: 0.12, shadows: 0.08),
    color: LookColor(temperature: 8.0, tint: 3.0, saturation: 1.10, vibrance: 0.18),
    film: LookFilm(bloom: 0.22),
  ),
  OneovaLook(
    id: 'golden_hour',
    name: 'Golden Hour',
    primary: LookPrimary(exposure: 0.16, contrast: 1.12, highlights: 0.08, shadows: 0.06),
    color: LookColor(temperature: 24.0, tint: 5.0, saturation: 1.18, vibrance: 0.25),
    film: LookFilm(bloom: 0.25),
  ),
  OneovaLook(
    id: 'velvet_studio',
    name: 'Velvet Studio',
    primary: LookPrimary(exposure: 0.06, contrast: 1.18, highlights: -0.06, shadows: 0.04),
    color: LookColor(temperature: -6.0, tint: 12.0, saturation: 1.14, vibrance: 0.22),
    optics: LookOptics(vignette: 0.22),
  ),
  OneovaLook(
    id: 'cinematic',
    name: 'Cinematic',
    primary: LookPrimary(exposure: 0.05, contrast: 1.22, highlights: -0.10, shadows: -0.04),
    color: LookColor(temperature: -8.0, tint: -2.0, saturation: 1.08, vibrance: 0.24),
    optics: LookOptics(vignette: 0.26),
  ),
  OneovaLook(
    id: 'cyber_neon',
    name: 'Cyber Neon',
    primary: LookPrimary(exposure: 0.08, contrast: 1.24, highlights: 0.10, shadows: -0.05),
    color: LookColor(temperature: -16.0, tint: 18.0, saturation: 1.28, vibrance: 0.30),
    film: LookFilm(bloom: 0.30),
    optics: LookOptics(vignette: 0.28),
  ),
  OneovaLook(
    id: 'crisp_daylight',
    name: 'Crisp Studio',
    primary: LookPrimary(exposure: 0.18, contrast: 1.10, highlights: 0.06, shadows: 0.10),
    color: LookColor(temperature: -5.0, tint: 0.0, saturation: 1.06, vibrance: 0.15),
  ),
  OneovaLook(
    id: 'moody_film',
    name: 'Moody Film',
    primary: LookPrimary(exposure: -0.02, contrast: 1.28, shadows: -0.12, blacks: 0.05),
    color: LookColor(temperature: 4.0, saturation: 0.78, vibrance: -0.10),
    film: LookFilm(grain: 0.15, fade: 0.08),
    optics: LookOptics(vignette: 0.34),
  ),
];

/// Studio key-lighting & atmosphere presets that illuminate the camera feed live.
@immutable
class LiveStudioLightingPreset {
  final String id;
  final String name;
  final IconData icon;
  final Color primaryColor;
  final Color secondaryColor;
  final double intensity;
  final double vignette;

  const LiveStudioLightingPreset({
    required this.id,
    required this.name,
    required this.icon,
    required this.primaryColor,
    required this.secondaryColor,
    this.intensity = 0.0,
    this.vignette = 0.0,
  });
}

const liveLightingPresets = <LiveStudioLightingPreset>[
  LiveStudioLightingPreset(
    id: 'natural',
    name: 'Natural',
    icon: Icons.wb_incandescent_outlined,
    primaryColor: Color(0x00000000),
    secondaryColor: Color(0x00000000),
    intensity: 0.0,
    vignette: 0.0,
  ),
  LiveStudioLightingPreset(
    id: 'warm_ring',
    name: 'Warm Ring',
    icon: Icons.light_mode_rounded,
    primaryColor: Color(0xFFFFE4B5),
    secondaryColor: Color(0xFFFF9E5E),
    intensity: 0.22,
    vignette: 0.14,
  ),
  LiveStudioLightingPreset(
    id: 'dual_neon',
    name: 'Studio Dual',
    icon: Icons.flare_rounded,
    primaryColor: Color(0xFF0C4FA8),
    secondaryColor: Color(0xFFFF2D87),
    intensity: 0.28,
    vignette: 0.22,
  ),
  LiveStudioLightingPreset(
    id: 'sunset_rim',
    name: 'Sunset Rim',
    icon: Icons.wb_twilight_rounded,
    primaryColor: Color(0xFFFF7A3D),
    secondaryColor: Color(0xFFFF2D87),
    intensity: 0.26,
    vignette: 0.18,
  ),
  LiveStudioLightingPreset(
    id: 'cyber_halo',
    name: 'Cyber Halo',
    icon: Icons.blur_circular_rounded,
    primaryColor: Color(0xFF00D2FF),
    secondaryColor: Color(0xFF0C4FA8),
    intensity: 0.26,
    vignette: 0.20,
  ),
  LiveStudioLightingPreset(
    id: 'spotlight',
    name: 'Stage Spot',
    icon: Icons.highlight_rounded,
    primaryColor: Color(0xFFFFFFFF),
    secondaryColor: Color(0xFF0A0A0A),
    intensity: 0.24,
    vignette: 0.42,
  ),
];

LiveStudioLightingPreset lightingPresetById(String id) {
  for (final p in liveLightingPresets) {
    if (p.id == id) return p;
  }
  return liveLightingPresets.first;
}

OneovaLook lookPresetById(String id) {
  for (final l in liveLookPresets) {
    if (l.id == id) return l;
  }
  return liveLookPresets.first;
}

/// Computes a real-time 4x5 ColorFilter matrix from [look] and [beauty].
List<double> computeLiveColorMatrix(OneovaLook look, BoostBeautyConfig beauty) {
  final p = look.primary;
  final c = look.color;
  final bOn = beauty.isEnabled && !beauty.isNeutral;

  // Exposure & Beauty radiance/glow lift
  final beautyLift = bOn
      ? (beauty.smoothSkin * 0.05 +
          beauty.evenTone * 0.06 +
          beauty.autoBoostLevel * 0.10 +
          beauty.teethWhitening * 0.04)
      : 0.0;
  final expGain = math.pow(2.0, p.exposure * 0.45 + beautyLift).toDouble();

  // Contrast (incorporating eyeBrighten clarity + look contrast)
  final eyeContrast = bOn ? (beauty.eyeBrighten * 0.08 + beauty.eyeEnlarge * 0.03) : 0.0;
  final contrast = (p.contrast + eyeContrast).clamp(0.6, 1.8);
  final translate = (1.0 - contrast) * 128.0 +
      (p.brightness + p.shadows * 0.22 + p.highlights * 0.15 + (bOn ? beauty.smoothSkin * 0.04 : 0.0)) * 42.0;

  // Saturation (incorporating vibrance + beauty evenTone warmth)
  final sat = (c.saturation + c.vibrance * 0.45 + (bOn ? beauty.evenTone * 0.08 : 0.0)).clamp(0.0, 2.0);
  const lumR = 0.2126;
  const lumG = 0.7152;
  const lumB = 0.0722;

  final sr = (1.0 - sat) * lumR;
  final sg = (1.0 - sat) * lumG;
  final sb = (1.0 - sat) * lumB;

  // Temperature (warm amber R+/B- or cool cyan R-/B+) & Tint (magenta G-/R+B+)
  final temp = c.temperature / 100.0 + (bOn ? beauty.evenTone * 0.06 : 0.0);
  final tint = c.tint / 100.0 + (bOn ? beauty.autoBoostLevel * 0.04 : 0.0);

  final rScale = expGain * contrast * (1.0 + temp * 0.22 + tint * 0.08);
  final gScale = expGain * contrast * (1.0 - tint * 0.14 + temp * 0.03);
  final bScale = expGain * contrast * (1.0 - temp * 0.24 + tint * 0.12);

  final rOffset = translate + temp * 14.0 + (bOn ? beauty.teethWhitening * 6.0 : 0.0);
  final gOffset = translate - tint * 8.0 + (bOn ? beauty.smoothSkin * 3.5 : 0.0);
  final bOffset = translate - temp * 14.0 + tint * 9.0 + (bOn ? beauty.teethWhitening * 7.5 : 0.0);

  return <double>[
    rScale * (sr + sat), rScale * sg, rScale * sb, 0, rOffset,
    gScale * sr, gScale * (sg + sat), gScale * sb, 0, gOffset,
    bScale * sr, bScale * sg, bScale * (sb + sat), 0, bOffset,
    0, 0, 0, 1, 0,
  ];
}

/// Real-time GPU visual grade, beauty diffusion, face-sculpt framing & studio key light wrapper.
/// Wraps any camera preview or live broadcast [child] so effects are 100% live-affecting.
class LiveVideoEffectLayer extends StatelessWidget {
  final Widget child;
  final OneovaLook look;
  final BoostBeautyConfig beauty;
  final String lightingId;

  const LiveVideoEffectLayer({
    super.key,
    required this.child,
    required this.look,
    required this.beauty,
    this.lightingId = 'natural',
  });

  bool get _isIdentity =>
      (look.id == 'neutral' || look.id.isEmpty) &&
      look.primary.isNeutral &&
      look.color.isNeutral &&
      look.optics.isNeutral &&
      look.film.isNeutral &&
      beauty.isNeutral &&
      (lightingId == 'natural' || lightingId.isEmpty);

  @override
  Widget build(BuildContext context) {
    if (_isIdentity) return child;

    final matrix = computeLiveColorMatrix(look, beauty);
    final light = lightingPresetById(lightingId);
    final bOn = beauty.isEnabled && !beauty.isNeutral;

    // Subtle optical face-slim / jawline framing when slim/jaw/eyes are active
    final slimX = bOn ? (1.0 - (beauty.faceSlim * 0.045 + beauty.jawSlim * 0.025)).clamp(0.92, 1.0) : 1.0;
    final zoomY = bOn ? (1.0 + (beauty.faceSlim * 0.035 + beauty.eyeEnlarge * 0.025)).clamp(1.0, 1.07) : 1.0;

    Widget current = ColorFiltered(
      colorFilter: ColorFilter.matrix(matrix),
      child: child,
    );

    if (slimX != 1.0 || zoomY != 1.0) {
      current = ClipRect(
        child: Transform.scale(
          scaleX: slimX * zoomY,
          scaleY: zoomY,
          alignment: Alignment.center,
          child: current,
        ),
      );
    }

    final bloomAlpha = ((bOn ? (beauty.smoothSkin * 0.14 + beauty.autoBoostLevel * 0.18) : 0.0) +
            look.film.bloom * 0.22)
        .clamp(0.0, 0.32);
    final vignetteAlpha = (look.optics.vignette * 0.55 + light.vignette).clamp(0.0, 0.65);

    return Stack(
      fit: StackFit.expand,
      children: [
        current,
        // Beauty soft-skin radial glow & catchlight diffusion
        if (bloomAlpha > 0.01)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.15),
                  radius: 0.85,
                  colors: [
                    const Color(0xFFFFF4EA).withValues(alpha: bloomAlpha * 0.65),
                    const Color(0xFFFFD6E8).withValues(alpha: bloomAlpha * 0.28),
                    const Color(0x00000000),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
        // Studio Key Lighting directional rim & key glow
        if (light.intensity > 0.01)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    light.primaryColor.withValues(alpha: light.intensity * 0.72),
                    const Color(0x00000000),
                    light.secondaryColor.withValues(alpha: light.intensity * 0.68),
                  ],
                  stops: const [0.0, 0.48, 1.0],
                ),
              ),
            ),
          ),
        // Cinema & Stage Spotlight Vignette
        if (vignetteAlpha > 0.01)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.08),
                  radius: 0.92,
                  colors: [
                    const Color(0x00000000),
                    const Color(0xFF05070D).withValues(alpha: vignetteAlpha),
                  ],
                  stops: const [0.48, 1.0],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
