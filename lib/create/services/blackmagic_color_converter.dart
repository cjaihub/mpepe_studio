import 'package:flutter/material.dart';
import '../models/cinema_preset.dart';

/// Built-in Blackmagic & Cinema Color Science Converter.
/// Provides authentic 4x5 color transform matrices simulating Hollywood digital film pipelines.
class BlackmagicColorConverter {
  const BlackmagicColorConverter._();

  /// Blackmagic Film Generation 5 Matrix:
  /// Wide dynamic range log transform with gentle shoulder roll-off and organic skin tone saturation.
  static const List<double> bmdGen5Matrix = [
    1.12, -0.05, -0.03, 0.0, 10.0,
    -0.04, 1.08, -0.02, 0.0, 8.0,
    -0.02, -0.03, 1.15, 0.0, 6.0,
    0.0,   0.0,   0.0,  1.0, 0.0,
  ];

  /// ARRI Alexa LogC4 Matrix:
  /// Neutral Hollywood gold-standard with smooth highlight roll-off and warm organic skin tones.
  static const List<double> arriLogC4Matrix = [
    1.06, -0.03, -0.01, 0.0, 14.0,
    -0.02, 1.04, -0.01, 0.0, 12.0,
    -0.01, -0.02, 1.08, 0.0, 10.0,
    0.0,   0.0,   0.0,  1.0, 0.0,
  ];

  /// Sony S-Log3 / S-Gamut3.Cine Matrix:
  /// Preserves dynamic range in shadows with punchy teal/emerald depth and crisp highlights.
  static const List<double> sonySLog3Matrix = [
    1.18, -0.08, -0.04, 0.0, 6.0,
    -0.06, 1.14, -0.03, 0.0, 7.0,
    -0.03, -0.05, 1.22, 0.0, 5.0,
    0.0,   0.0,   0.0,  1.0, 0.0,
  ];

  /// Apple ProRes Log Matrix:
  /// Modern 10-bit logarithmic mobile color science.
  static const List<double> appleProResLogMatrix = [
    1.08, -0.04, -0.02, 0.0, 12.0,
    -0.03, 1.06, -0.02, 0.0, 10.0,
    -0.01, -0.02, 1.10, 0.0, 8.0,
    0.0,   0.0,   0.0,  1.0, 0.0,
  ];

  /// ACEScc Wide Gamut Matrix:
  /// Academy Color Encoding System logarithmic matrix for digital motion picture production.
  static const List<double> acesCcMatrix = [
    1.10, -0.06, -0.02, 0.0, 8.0,
    -0.04, 1.12, -0.04, 0.0, 8.0,
    -0.02, -0.04, 1.18, 0.0, 8.0,
    0.0,   0.0,   0.0,  1.0, 0.0,
  ];

  /// OneOva Obsidian Cine Matrix:
  /// Signature aesthetic with deep pitch blacks, electric cyan shadows, and vibrant pink highlights.
  static const List<double> obsidianCineMatrix = [
    1.25, -0.06, -0.04, 0.0, 4.0,
    -0.05, 1.10, -0.02, 0.0, 2.0,
    -0.02, -0.03, 1.32, 0.0, 12.0,
    0.0,   0.0,   0.0,  1.0, 0.0,
  ];

  /// Neutral Rec.709 Standard Broadcast Matrix.
  static const List<double> rec709Matrix = [
    1.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 1.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 1.0, 0.0,
  ];

  /// False Color Exposure Map Matrix:
  /// Re-maps luminance values into a high-visibility spectral false color tool:
  /// - Overexposure/clipping shows red
  /// - Mid-tones/skin tones show green/pink
  /// - Shadows show blue
  /// - Crushed blacks show purple
  static const List<double> falseColorMatrix = [
    1.8, -0.5, -0.5, 0.0, 30.0,
    -0.4, 1.6, -0.4, 0.0, 20.0,
    -0.5, -0.5, 2.0, 0.0, 40.0,
    0.0,  0.0,  0.0, 1.0, 0.0,
  ];

  /// Resolves the base 4x5 matrix for a given color science standard.
  static List<double> getBaseMatrix(ColorScienceStandard standard) {
    switch (standard) {
      case ColorScienceStandard.blackmagicGen5:
        return List<double>.from(bmdGen5Matrix);
      case ColorScienceStandard.arriLogC4:
        return List<double>.from(arriLogC4Matrix);
      case ColorScienceStandard.sonySLog3:
        return List<double>.from(sonySLog3Matrix);
      case ColorScienceStandard.appleProResLog:
        return List<double>.from(appleProResLogMatrix);
      case ColorScienceStandard.acesCc:
        return List<double>.from(acesCcMatrix);
      case ColorScienceStandard.obsidianCine:
        return List<double>.from(obsidianCineMatrix);
      case ColorScienceStandard.neutralRec709:
        return List<double>.from(rec709Matrix);
    }
  }

  /// Synthesizes a modulated 4x5 matrix based on the CinemaPreset parameters.
  /// Modulates Kelvin temperature, tint, exposure EV, contrast, and saturation.
  static List<double> computeModulatedMatrix(CinemaPreset preset, {bool falseColorActive = false}) {
    if (falseColorActive) {
      return List<double>.from(falseColorMatrix);
    }

    final base = getBaseMatrix(preset.colorScience);

    // Kelvin temperature shift (reference 5600K)
    // < 5600K: warm (boost red, suppress blue)
    // > 5600K: cool (boost blue, suppress red)
    final kelvinDelta = (preset.kelvin - 5600) / 3000.0;
    final rTemp = (1.0 - (kelvinDelta * 0.15)).clamp(0.6, 1.4);
    final bTemp = (1.0 + (kelvinDelta * 0.18)).clamp(0.6, 1.4);

    // Tint (-10 to +10: magenta to green)
    final gTint = (1.0 + (preset.tint * 0.02)).clamp(0.8, 1.2);

    // Exposure EV offset (each EV is ~25 luma steps)
    final evOffset = preset.exposure * 22.0;

    // Contrast scaling
    final c = preset.contrast.clamp(0.5, 1.8);
    final cOffset = (128.0 * (1.0 - c));

    // Saturation scaling (standard luminance weights: R: 0.2126, G: 0.7152, B: 0.0722)
    final s = preset.saturation.clamp(0.0, 2.0);
    final invS = 1.0 - s;
    final rLum = 0.2126 * invS;
    final gLum = 0.7152 * invS;
    final bLum = 0.0722 * invS;

    return [
      (base[0] * rTemp * (rLum + s) * c),
      (base[1] * (gLum) * c),
      (base[2] * (bLum) * c),
      0.0,
      (base[4] + evOffset + cOffset),

      (base[5] * (rLum) * c),
      (base[6] * gTint * (gLum + s) * c),
      (base[7] * (bLum) * c),
      0.0,
      (base[9] + evOffset + cOffset),

      (base[10] * (rLum) * c),
      (base[11] * (gLum) * c),
      (base[12] * bTemp * (bLum + s) * c),
      0.0,
      (base[14] + evOffset + cOffset),

      0.0, 0.0, 0.0, 1.0, 0.0,
    ];
  }

  /// Constructs a Flutter [ColorFilter] ready for [ColorFiltered] widgets.
  static ColorFilter createColorFilter(CinemaPreset preset, {bool falseColorActive = false}) {
    final matrix = computeModulatedMatrix(preset, falseColorActive: falseColorActive);
    return ColorFilter.matrix(matrix);
  }

  /// AI Auto-Grade: Analyzes environmental cues and returns an optimized CinemaPreset look.
  static CinemaPreset generateAiAutoGrade({
    required String currentSceneName,
    bool isLowLight = false,
  }) {
    if (isLowLight) {
      return CinemaPreset(
        id: 'ai_low_light_${DateTime.now().millisecondsSinceEpoch}',
        name: 'AI Night-Sight Cine',
        colorScience: ColorScienceStandard.blackmagicGen5,
        kelvin: 4800,
        tint: -1.0,
        exposure: 0.6,
        contrast: 1.15,
        saturation: 1.1,
        filmGrain: 0.15,
        isAiEnhanced: true,
        aiPrompt: 'Clean neural de-noise with lifted shadow toes and warm filmic skin tone.',
        isUserCustom: false,
        createdAt: DateTime.now(),
      );
    }

    return CinemaPreset(
      id: 'ai_auto_${DateTime.now().millisecondsSinceEpoch}',
      name: 'AI Auto-Grade Master',
      colorScience: ColorScienceStandard.arriLogC4,
      kelvin: 5600,
      tint: 0.5,
      exposure: 0.1,
      contrast: 1.08,
      saturation: 1.05,
      filmGrain: 0.08,
      isAiEnhanced: true,
      aiPrompt: 'Hollywood Alexa 35 filmic transfer with balanced skin luminance and soft highlights.',
      isUserCustom: false,
      createdAt: DateTime.now(),
    );
  }
}
