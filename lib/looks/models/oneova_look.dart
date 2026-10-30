import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'look_param_ranges.dart';

/// Normalized 2D point for parametric curve control.
@immutable
class CurvePoint {
  final double x;
  final double y;

  const CurvePoint(this.x, this.y);

  Map<String, dynamic> toMap() => {'x': x, 'y': y};

  factory CurvePoint.fromMap(Map<String, dynamic> map) {
    return CurvePoint(
      (map['x'] as num?)?.toDouble() ?? 0.0,
      (map['y'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CurvePoint &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => x.hashCode ^ y.hashCode;
}

/// 3-way color wheel adjustments (Lift, Gamma, Gain, Offset).
@immutable
class ColorWheel {
  final double r;
  final double g;
  final double b;
  final double lum;

  const ColorWheel({
    this.r = 0.0,
    this.g = 0.0,
    this.b = 0.0,
    this.lum = 0.0,
  });

  bool get isNeutral => r == 0.0 && g == 0.0 && b == 0.0 && lum == 0.0;

  ColorWheel copyWith({double? r, double? g, double? b, double? lum}) {
    return ColorWheel(
      r: r ?? this.r,
      g: g ?? this.g,
      b: b ?? this.b,
      lum: lum ?? this.lum,
    );
  }

  Map<String, dynamic> toMap() => {'r': r, 'g': g, 'b': b, 'lum': lum};

  factory ColorWheel.fromMap(Map<String, dynamic> map) {
    return ColorWheel(
      r: (map['r'] as num?)?.toDouble() ?? 0.0,
      g: (map['g'] as num?)?.toDouble() ?? 0.0,
      b: (map['b'] as num?)?.toDouble() ?? 0.0,
      lum: (map['lum'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorWheel &&
          r == other.r &&
          g == other.g &&
          b == other.b &&
          lum == other.lum;

  @override
  int get hashCode => Object.hash(r, g, b, lum);
}

/// HSL band adjustment (Hue shift, Saturation shift, Luminance shift).
@immutable
class HslBand {
  final double hue; // -180.0 to 180.0
  final double sat; // -1.0 to 1.0
  final double lum; // -1.0 to 1.0

  const HslBand({this.hue = 0.0, this.sat = 0.0, this.lum = 0.0});

  bool get isNeutral => hue == 0.0 && sat == 0.0 && lum == 0.0;

  HslBand copyWith({double? hue, double? sat, double? lum}) {
    return HslBand(
      hue: hue ?? this.hue,
      sat: sat ?? this.sat,
      lum: lum ?? this.lum,
    );
  }

  Map<String, dynamic> toMap() => {'hue': hue, 'sat': sat, 'lum': lum};

  factory HslBand.fromMap(Map<String, dynamic> map) {
    return HslBand(
      hue: (map['hue'] as num?)?.toDouble() ?? 0.0,
      sat: (map['sat'] as num?)?.toDouble() ?? 0.0,
      lum: (map['lum'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HslBand && hue == other.hue && sat == other.sat && lum == other.lum;

  @override
  int get hashCode => Object.hash(hue, sat, lum);
}

/// A 3D or 1D LUT layer within the LUT stack.
@immutable
class LutItem {
  final String id;
  final String name;
  final String pathOrUrl;
  final int size; // 17, 33, 65
  final double intensity; // 0.0 to 1.0
  final bool isEnabled;

  const LutItem({
    required this.id,
    required this.name,
    required this.pathOrUrl,
    this.size = 33,
    this.intensity = 1.0,
    this.isEnabled = true,
  });

  LutItem copyWith({
    String? id,
    String? name,
    String? pathOrUrl,
    int? size,
    double? intensity,
    bool? isEnabled,
  }) {
    return LutItem(
      id: id ?? this.id,
      name: name ?? this.name,
      pathOrUrl: pathOrUrl ?? this.pathOrUrl,
      size: size ?? this.size,
      intensity: intensity ?? this.intensity,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'pathOrUrl': pathOrUrl,
        'size': size,
        'intensity': intensity,
        'isEnabled': isEnabled,
      };

  factory LutItem.fromMap(Map<String, dynamic> map) {
    return LutItem(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'LUT',
      pathOrUrl: map['pathOrUrl'] as String? ?? '',
      size: (map['size'] as num?)?.toInt() ?? 33,
      intensity: (map['intensity'] as num?)?.toDouble() ?? 1.0,
      isEnabled: map['isEnabled'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LutItem &&
          id == other.id &&
          pathOrUrl == other.pathOrUrl &&
          size == other.size &&
          intensity == other.intensity &&
          isEnabled == other.isEnabled;

  @override
  int get hashCode => Object.hash(id, pathOrUrl, size, intensity, isEnabled);
}

/// Primary exposure, contrast, and tonality adjustments.
@immutable
class LookPrimary {
  final double exposure; // -2.0 to 2.0
  final double contrast; // 0.5 to 2.0 (neutral 1.0)
  final double pivot; // 0.0 to 1.0 (neutral 0.435)
  final double highlights; // -1.0 to 1.0
  final double shadows; // -1.0 to 1.0
  final double whites; // -1.0 to 1.0
  final double blacks; // -1.0 to 1.0
  final double brightness; // -1.0 to 1.0

  const LookPrimary({
    this.exposure = 0.0,
    this.contrast = 1.0,
    this.pivot = 0.435,
    this.highlights = 0.0,
    this.shadows = 0.0,
    this.whites = 0.0,
    this.blacks = 0.0,
    this.brightness = 0.0,
  });

  bool get isNeutral =>
      exposure == 0.0 &&
      contrast == 1.0 &&
      pivot == 0.435 &&
      highlights == 0.0 &&
      shadows == 0.0 &&
      whites == 0.0 &&
      blacks == 0.0 &&
      brightness == 0.0;

  LookPrimary copyWith({
    double? exposure,
    double? contrast,
    double? pivot,
    double? highlights,
    double? shadows,
    double? whites,
    double? blacks,
    double? brightness,
  }) {
    return LookPrimary(
      exposure: exposure ?? this.exposure,
      contrast: contrast ?? this.contrast,
      pivot: pivot ?? this.pivot,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      whites: whites ?? this.whites,
      blacks: blacks ?? this.blacks,
      brightness: brightness ?? this.brightness,
    );
  }

  Map<String, dynamic> toMap() => {
        'exposure': exposure,
        'contrast': contrast,
        'pivot': pivot,
        'highlights': highlights,
        'shadows': shadows,
        'whites': whites,
        'blacks': blacks,
        'brightness': brightness,
      };

  factory LookPrimary.fromMap(Map<String, dynamic> map) {
    return LookPrimary(
      exposure: (map['exposure'] as num?)?.toDouble() ?? 0.0,
      contrast: (map['contrast'] as num?)?.toDouble() ?? 1.0,
      pivot: (map['pivot'] as num?)?.toDouble() ?? 0.435,
      highlights: (map['highlights'] as num?)?.toDouble() ?? 0.0,
      shadows: (map['shadows'] as num?)?.toDouble() ?? 0.0,
      whites: (map['whites'] as num?)?.toDouble() ?? 0.0,
      blacks: (map['blacks'] as num?)?.toDouble() ?? 0.0,
      brightness: (map['brightness'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LookPrimary &&
          exposure == other.exposure &&
          contrast == other.contrast &&
          pivot == other.pivot &&
          highlights == other.highlights &&
          shadows == other.shadows &&
          whites == other.whites &&
          blacks == other.blacks &&
          brightness == other.brightness;

  @override
  int get hashCode => Object.hash(exposure, contrast, pivot, highlights,
      shadows, whites, blacks, brightness);
}

/// Global color balance and saturation.
@immutable
class LookColor {
  final double temperature; // -100.0 to 100.0 (Kelvin bias)
  final double tint; // -100.0 to 100.0 (Green-Magenta bias)
  final double vibrance; // -1.0 to 1.0
  final double saturation; // 0.0 to 2.0 (neutral 1.0)
  final double colorBoost; // 0.0 to 2.0 (neutral 1.0)

  const LookColor({
    this.temperature = 0.0,
    this.tint = 0.0,
    this.vibrance = 0.0,
    this.saturation = 1.0,
    this.colorBoost = 1.0,
  });

  bool get isNeutral =>
      temperature == 0.0 &&
      tint == 0.0 &&
      vibrance == 0.0 &&
      saturation == 1.0 &&
      colorBoost == 1.0;

  LookColor copyWith({
    double? temperature,
    double? tint,
    double? vibrance,
    double? saturation,
    double? colorBoost,
  }) {
    return LookColor(
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      vibrance: vibrance ?? this.vibrance,
      saturation: saturation ?? this.saturation,
      colorBoost: colorBoost ?? this.colorBoost,
    );
  }

  Map<String, dynamic> toMap() => {
        'temperature': temperature,
        'tint': tint,
        'vibrance': vibrance,
        'saturation': saturation,
        'colorBoost': colorBoost,
      };

  factory LookColor.fromMap(Map<String, dynamic> map) {
    return LookColor(
      temperature: (map['temperature'] as num?)?.toDouble() ?? 0.0,
      tint: (map['tint'] as num?)?.toDouble() ?? 0.0,
      vibrance: (map['vibrance'] as num?)?.toDouble() ?? 0.0,
      saturation: (map['saturation'] as num?)?.toDouble() ?? 1.0,
      colorBoost: (map['colorBoost'] as num?)?.toDouble() ?? 1.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LookColor &&
          temperature == other.temperature &&
          tint == other.tint &&
          vibrance == other.vibrance &&
          saturation == other.saturation &&
          colorBoost == other.colorBoost;

  @override
  int get hashCode =>
      Object.hash(temperature, tint, vibrance, saturation, colorBoost);
}

/// Complete Color Wheels stage.
@immutable
class LookWheels {
  final ColorWheel lift;
  final ColorWheel gamma;
  final ColorWheel gain;
  final ColorWheel offset;

  const LookWheels({
    this.lift = const ColorWheel(),
    this.gamma = const ColorWheel(),
    this.gain = const ColorWheel(),
    this.offset = const ColorWheel(),
  });

  bool get isNeutral =>
      lift.isNeutral && gamma.isNeutral && gain.isNeutral && offset.isNeutral;

  LookWheels copyWith({
    ColorWheel? lift,
    ColorWheel? gamma,
    ColorWheel? gain,
    ColorWheel? offset,
  }) {
    return LookWheels(
      lift: lift ?? this.lift,
      gamma: gamma ?? this.gamma,
      gain: gain ?? this.gain,
      offset: offset ?? this.offset,
    );
  }

  Map<String, dynamic> toMap() => {
        'lift': lift.toMap(),
        'gamma': gamma.toMap(),
        'gain': gain.toMap(),
        'offset': offset.toMap(),
      };

  factory LookWheels.fromMap(Map<String, dynamic> map) {
    return LookWheels(
      lift: map['lift'] is Map<String, dynamic>
          ? ColorWheel.fromMap(map['lift'] as Map<String, dynamic>)
          : const ColorWheel(),
      gamma: map['gamma'] is Map<String, dynamic>
          ? ColorWheel.fromMap(map['gamma'] as Map<String, dynamic>)
          : const ColorWheel(),
      gain: map['gain'] is Map<String, dynamic>
          ? ColorWheel.fromMap(map['gain'] as Map<String, dynamic>)
          : const ColorWheel(),
      offset: map['offset'] is Map<String, dynamic>
          ? ColorWheel.fromMap(map['offset'] as Map<String, dynamic>)
          : const ColorWheel(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LookWheels &&
          lift == other.lift &&
          gamma == other.gamma &&
          gain == other.gain &&
          offset == other.offset;

  @override
  int get hashCode => Object.hash(lift, gamma, gain, offset);
}

/// Parametric spline and color curves.
@immutable
class LookCurves {
  final List<CurvePoint> master;
  final List<CurvePoint> red;
  final List<CurvePoint> green;
  final List<CurvePoint> blue;
  final List<CurvePoint> hueVsHue;
  final List<CurvePoint> hueVsSat;
  final List<CurvePoint> hueVsLum;
  final List<CurvePoint> lumVsSat;

  const LookCurves({
    this.master = const [CurvePoint(0, 0), CurvePoint(1, 1)],
    this.red = const [CurvePoint(0, 0), CurvePoint(1, 1)],
    this.green = const [CurvePoint(0, 0), CurvePoint(1, 1)],
    this.blue = const [CurvePoint(0, 0), CurvePoint(1, 1)],
    this.hueVsHue = const [],
    this.hueVsSat = const [],
    this.hueVsLum = const [],
    this.lumVsSat = const [],
  });

  bool get isNeutral {
    return (master.length <= 2) &&
        (red.length <= 2) &&
        (green.length <= 2) &&
        (blue.length <= 2) &&
        hueVsHue.isEmpty &&
        hueVsSat.isEmpty &&
        hueVsLum.isEmpty &&
        lumVsSat.isEmpty;
  }

  Map<String, dynamic> toMap() => {
        'master': master.map((p) => p.toMap()).toList(),
        'red': red.map((p) => p.toMap()).toList(),
        'green': green.map((p) => p.toMap()).toList(),
        'blue': blue.map((p) => p.toMap()).toList(),
        'hueVsHue': hueVsHue.map((p) => p.toMap()).toList(),
        'hueVsSat': hueVsSat.map((p) => p.toMap()).toList(),
        'hueVsLum': hueVsLum.map((p) => p.toMap()).toList(),
        'lumVsSat': lumVsSat.map((p) => p.toMap()).toList(),
      };

  factory LookCurves.fromMap(Map<String, dynamic> map) {
    List<CurvePoint> parsePoints(dynamic raw) {
      if (raw is List) {
        return raw
            .whereType<Map<String, dynamic>>()
            .map(CurvePoint.fromMap)
            .toList();
      }
      return const [CurvePoint(0, 0), CurvePoint(1, 1)];
    }

    return LookCurves(
      master: parsePoints(map['master']),
      red: parsePoints(map['red']),
      green: parsePoints(map['green']),
      blue: parsePoints(map['blue']),
      hueVsHue: parsePoints(map['hueVsHue']),
      hueVsSat: parsePoints(map['hueVsSat']),
      hueVsLum: parsePoints(map['hueVsLum']),
      lumVsSat: parsePoints(map['lumVsSat']),
    );
  }
}

/// 8 HSL Color Mixer bands.
@immutable
class LookHsl {
  final HslBand red;
  final HslBand orange;
  final HslBand yellow;
  final HslBand green;
  final HslBand aqua;
  final HslBand blue;
  final HslBand purple;
  final HslBand magenta;

  const LookHsl({
    this.red = const HslBand(),
    this.orange = const HslBand(),
    this.yellow = const HslBand(),
    this.green = const HslBand(),
    this.aqua = const HslBand(),
    this.blue = const HslBand(),
    this.purple = const HslBand(),
    this.magenta = const HslBand(),
  });

  bool get isNeutral =>
      red.isNeutral &&
      orange.isNeutral &&
      yellow.isNeutral &&
      green.isNeutral &&
      aqua.isNeutral &&
      blue.isNeutral &&
      purple.isNeutral &&
      magenta.isNeutral;

  /// Bands in hue order (red 0°, orange 30°, yellow 60°, green 120°,
  /// aqua 180°, blue 240°, purple 270°, magenta 300°).
  List<(String, HslBand)> get bands => [
        ('red', red),
        ('orange', orange),
        ('yellow', yellow),
        ('green', green),
        ('aqua', aqua),
        ('blue', blue),
        ('purple', purple),
        ('magenta', magenta),
      ];

  Map<String, dynamic> toMap() => {
        'red': red.toMap(),
        'orange': orange.toMap(),
        'yellow': yellow.toMap(),
        'green': green.toMap(),
        'aqua': aqua.toMap(),
        'blue': blue.toMap(),
        'purple': purple.toMap(),
        'magenta': magenta.toMap(),
      };

  factory LookHsl.fromMap(Map<String, dynamic> map) {
    HslBand parse(String key) {
      if (map[key] is Map<String, dynamic>) {
        return HslBand.fromMap(map[key] as Map<String, dynamic>);
      }
      return const HslBand();
    }

    return LookHsl(
      red: parse('red'),
      orange: parse('orange'),
      yellow: parse('yellow'),
      green: parse('green'),
      aqua: parse('aqua'),
      blue: parse('blue'),
      purple: parse('purple'),
      magenta: parse('magenta'),
    );
  }
}

/// Film stock emulation, halation, grain, and bloom.
@immutable
class LookFilm {
  final String emulationProfile; // e.g. "kodak_portra_400", "fuji_pro_400h"
  final double halation; // 0.0 to 1.0
  final double bloom; // 0.0 to 1.0
  final double grain; // 0.0 to 1.0
  final double grainRoughness; // 0.0 to 1.0
  final double fade; // 0.0 to 1.0 (lifted blacks)

  const LookFilm({
    this.emulationProfile = '',
    this.halation = 0.0,
    this.bloom = 0.0,
    this.grain = 0.0,
    this.grainRoughness = 0.5,
    this.fade = 0.0,
  });

  bool get isNeutral =>
      emulationProfile.isEmpty &&
      halation == 0.0 &&
      bloom == 0.0 &&
      grain == 0.0 &&
      fade == 0.0;

  LookFilm copyWith({
    String? emulationProfile,
    double? halation,
    double? bloom,
    double? grain,
    double? grainRoughness,
    double? fade,
  }) {
    return LookFilm(
      emulationProfile: emulationProfile ?? this.emulationProfile,
      halation: halation ?? this.halation,
      bloom: bloom ?? this.bloom,
      grain: grain ?? this.grain,
      grainRoughness: grainRoughness ?? this.grainRoughness,
      fade: fade ?? this.fade,
    );
  }

  Map<String, dynamic> toMap() => {
        'emulationProfile': emulationProfile,
        'halation': halation,
        'bloom': bloom,
        'grain': grain,
        'grainRoughness': grainRoughness,
        'fade': fade,
      };

  factory LookFilm.fromMap(Map<String, dynamic> map) {
    return LookFilm(
      emulationProfile: map['emulationProfile'] as String? ?? '',
      halation: (map['halation'] as num?)?.toDouble() ?? 0.0,
      bloom: (map['bloom'] as num?)?.toDouble() ?? 0.0,
      grain: (map['grain'] as num?)?.toDouble() ?? 0.0,
      grainRoughness: (map['grainRoughness'] as num?)?.toDouble() ?? 0.5,
      fade: (map['fade'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Sharpness, clarity, texture, and noise reduction.
@immutable
class LookDetail {
  final double sharpen; // 0.0 to 1.0
  final double clarity; // -1.0 to 1.0
  final double texture; // -1.0 to 1.0
  final double dehaze; // -1.0 to 1.0

  const LookDetail({
    this.sharpen = 0.0,
    this.clarity = 0.0,
    this.texture = 0.0,
    this.dehaze = 0.0,
  });

  bool get isNeutral =>
      sharpen == 0.0 && clarity == 0.0 && texture == 0.0 && dehaze == 0.0;

  LookDetail copyWith({
    double? sharpen,
    double? clarity,
    double? texture,
    double? dehaze,
  }) {
    return LookDetail(
      sharpen: sharpen ?? this.sharpen,
      clarity: clarity ?? this.clarity,
      texture: texture ?? this.texture,
      dehaze: dehaze ?? this.dehaze,
    );
  }

  Map<String, dynamic> toMap() => {
        'sharpen': sharpen,
        'clarity': clarity,
        'texture': texture,
        'dehaze': dehaze,
      };

  factory LookDetail.fromMap(Map<String, dynamic> map) {
    return LookDetail(
      sharpen: (map['sharpen'] as num?)?.toDouble() ?? 0.0,
      clarity: (map['clarity'] as num?)?.toDouble() ?? 0.0,
      texture: (map['texture'] as num?)?.toDouble() ?? 0.0,
      dehaze: (map['dehaze'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Lens, vignette, chromatic aberration, and optics effects.
@immutable
class LookOptics {
  final double vignette; // 0.0 to 1.0
  final double chromaticAberration; // 0.0 to 1.0
  final double lensDistortion; // -1.0 to 1.0

  const LookOptics({
    this.vignette = 0.0,
    this.chromaticAberration = 0.0,
    this.lensDistortion = 0.0,
  });

  bool get isNeutral =>
      vignette == 0.0 && chromaticAberration == 0.0 && lensDistortion == 0.0;

  LookOptics copyWith({
    double? vignette,
    double? chromaticAberration,
    double? lensDistortion,
  }) {
    return LookOptics(
      vignette: vignette ?? this.vignette,
      chromaticAberration: chromaticAberration ?? this.chromaticAberration,
      lensDistortion: lensDistortion ?? this.lensDistortion,
    );
  }

  Map<String, dynamic> toMap() => {
        'vignette': vignette,
        'chromaticAberration': chromaticAberration,
        'lensDistortion': lensDistortion,
      };

  factory LookOptics.fromMap(Map<String, dynamic> map) {
    return LookOptics(
      vignette: (map['vignette'] as num?)?.toDouble() ?? 0.0,
      chromaticAberration:
          (map['chromaticAberration'] as num?)?.toDouble() ?? 0.0,
      lensDistortion: (map['lensDistortion'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Creative stylistic effects (light leaks, glitch, VHS, split).
@immutable
class LookFx {
  final String lightLeakPreset;
  final double lightLeakIntensity; // 0.0 to 1.0
  final double glitch; // 0.0 to 1.0
  final double vhs; // 0.0 to 1.0
  final double rgbSplit; // 0.0 to 1.0

  const LookFx({
    this.lightLeakPreset = '',
    this.lightLeakIntensity = 0.0,
    this.glitch = 0.0,
    this.vhs = 0.0,
    this.rgbSplit = 0.0,
  });

  bool get isNeutral =>
      lightLeakPreset.isEmpty &&
      lightLeakIntensity == 0.0 &&
      glitch == 0.0 &&
      vhs == 0.0 &&
      rgbSplit == 0.0;

  Map<String, dynamic> toMap() => {
        'lightLeakPreset': lightLeakPreset,
        'lightLeakIntensity': lightLeakIntensity,
        'glitch': glitch,
        'vhs': vhs,
        'rgbSplit': rgbSplit,
      };

  factory LookFx.fromMap(Map<String, dynamic> map) {
    return LookFx(
      lightLeakPreset: map['lightLeakPreset'] as String? ?? '',
      lightLeakIntensity:
          (map['lightLeakIntensity'] as num?)?.toDouble() ?? 0.0,
      glitch: (map['glitch'] as num?)?.toDouble() ?? 0.0,
      vhs: (map['vhs'] as num?)?.toDouble() ?? 0.0,
      rgbSplit: (map['rgbSplit'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Boost Beauty configuration (MediaPipe 478-point face mesh).
@immutable
class BoostBeautyConfig {
  final bool isEnabled;
  final double smoothSkin; // 0.0 to 1.0
  final double evenTone; // 0.0 to 1.0
  final double eyeBrighten; // 0.0 to 1.0
  final double eyeEnlarge; // 0.0 to 1.0
  final double teethWhitening; // 0.0 to 1.0
  final double faceSlim; // 0.0 to 1.0 (governed by Natural Guard)
  final double jawSlim; // 0.0 to 1.0
  final double noseSlim; // 0.0 to 1.0
  final double autoBoostLevel; // 0.0 to 1.0

  const BoostBeautyConfig({
    this.isEnabled = false,
    this.smoothSkin = 0.0,
    this.evenTone = 0.0,
    this.eyeBrighten = 0.0,
    this.eyeEnlarge = 0.0,
    this.teethWhitening = 0.0,
    this.faceSlim = 0.0,
    this.jawSlim = 0.0,
    this.noseSlim = 0.0,
    this.autoBoostLevel = 0.0,
  });

  bool get isNeutral =>
      !isEnabled ||
      (smoothSkin == 0.0 &&
          evenTone == 0.0 &&
          eyeBrighten == 0.0 &&
          eyeEnlarge == 0.0 &&
          teethWhitening == 0.0 &&
          faceSlim == 0.0 &&
          jawSlim == 0.0 &&
          noseSlim == 0.0 &&
          autoBoostLevel == 0.0);

  BoostBeautyConfig copyWith({
    bool? isEnabled,
    double? smoothSkin,
    double? evenTone,
    double? eyeBrighten,
    double? eyeEnlarge,
    double? teethWhitening,
    double? faceSlim,
    double? jawSlim,
    double? noseSlim,
    double? autoBoostLevel,
  }) {
    return BoostBeautyConfig(
      isEnabled: isEnabled ?? this.isEnabled,
      smoothSkin: smoothSkin ?? this.smoothSkin,
      evenTone: evenTone ?? this.evenTone,
      eyeBrighten: eyeBrighten ?? this.eyeBrighten,
      eyeEnlarge: eyeEnlarge ?? this.eyeEnlarge,
      teethWhitening: teethWhitening ?? this.teethWhitening,
      faceSlim: faceSlim ?? this.faceSlim,
      jawSlim: jawSlim ?? this.jawSlim,
      noseSlim: noseSlim ?? this.noseSlim,
      autoBoostLevel: autoBoostLevel ?? this.autoBoostLevel,
    );
  }

  Map<String, dynamic> toMap() => {
        'isEnabled': isEnabled,
        'smoothSkin': smoothSkin,
        'evenTone': evenTone,
        'eyeBrighten': eyeBrighten,
        'eyeEnlarge': eyeEnlarge,
        'teethWhitening': teethWhitening,
        'faceSlim': faceSlim,
        'jawSlim': jawSlim,
        'noseSlim': noseSlim,
        'autoBoostLevel': autoBoostLevel,
      };

  factory BoostBeautyConfig.fromMap(Map<String, dynamic> map) {
    return BoostBeautyConfig(
      isEnabled: map['isEnabled'] as bool? ?? false,
      smoothSkin: (map['smoothSkin'] as num?)?.toDouble() ?? 0.0,
      evenTone: (map['evenTone'] as num?)?.toDouble() ?? 0.0,
      eyeBrighten: (map['eyeBrighten'] as num?)?.toDouble() ?? 0.0,
      eyeEnlarge: (map['eyeEnlarge'] as num?)?.toDouble() ?? 0.0,
      teethWhitening: (map['teethWhitening'] as num?)?.toDouble() ?? 0.0,
      faceSlim: (map['faceSlim'] as num?)?.toDouble() ?? 0.0,
      jawSlim: (map['jawSlim'] as num?)?.toDouble() ?? 0.0,
      noseSlim: (map['noseSlim'] as num?)?.toDouble() ?? 0.0,
      autoBoostLevel: (map['autoBoostLevel'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Background replacement and depth-aware blur.
@immutable
class BackgroundEffectConfig {
  final String mode; // 'none', 'blur', 'replace', 'color', 'greenScreen'
  final double blurLevel; // 0.0 to 1.0
  final String replaceUrl;
  final String colorHex;

  const BackgroundEffectConfig({
    this.mode = 'none',
    this.blurLevel = 0.5,
    this.replaceUrl = '',
    this.colorHex = '#000000',
  });

  bool get isNeutral => mode == 'none';

  BackgroundEffectConfig copyWith({
    String? mode,
    double? blurLevel,
    String? replaceUrl,
    String? colorHex,
  }) {
    return BackgroundEffectConfig(
      mode: mode ?? this.mode,
      blurLevel: blurLevel ?? this.blurLevel,
      replaceUrl: replaceUrl ?? this.replaceUrl,
      colorHex: colorHex ?? this.colorHex,
    );
  }

  Map<String, dynamic> toMap() => {
        'mode': mode,
        'blurLevel': blurLevel,
        'replaceUrl': replaceUrl,
        'colorHex': colorHex,
      };

  factory BackgroundEffectConfig.fromMap(Map<String, dynamic> map) {
    return BackgroundEffectConfig(
      mode: map['mode'] as String? ?? 'none',
      blurLevel: (map['blurLevel'] as num?)?.toDouble() ?? 0.5,
      replaceUrl: map['replaceUrl'] as String? ?? '',
      colorHex: map['colorHex'] as String? ?? '#000000',
    );
  }
}

/// Adaptive guards (Highlight Guard, Skin Tone Protect, Auto-Exposure Assist).
@immutable
class AdaptiveRulesConfig {
  final bool autoExposureAssist;
  final bool skinToneProtect;
  final bool highlightGuard;

  const AdaptiveRulesConfig({
    this.autoExposureAssist = false,
    this.skinToneProtect = true,
    this.highlightGuard = true,
  });

  Map<String, dynamic> toMap() => {
        'autoExposureAssist': autoExposureAssist,
        'skinToneProtect': skinToneProtect,
        'highlightGuard': highlightGuard,
      };

  factory AdaptiveRulesConfig.fromMap(Map<String, dynamic> map) {
    return AdaptiveRulesConfig(
      autoExposureAssist: map['autoExposureAssist'] as bool? ?? false,
      skinToneProtect: map['skinToneProtect'] as bool? ?? true,
      highlightGuard: map['highlightGuard'] as bool? ?? true,
    );
  }
}

/// Comprehensive OneovaLook Model (Version 2).
/// The single universal format for Live, Camera, Photo and Video.
@immutable
class OneovaLook {
  final int schemaVersion;
  final String id;
  final String name;
  final String ownerUid;
  final List<String> categories; // e.g. ['cinematic', 'portrait', 'trending']
  final List<String> tags;
  final String thumbnailUrl;
  final String source; // 'catalog', 'user', 'ai', 'remix', 'market'
  final String? parentLookId;
  final String? priceRef;
  final int minDeviceTier; // 1 = Low, 2 = Mid, 3 = High, 4 = Pro
  final double intensity; // Master intensity 0.0 to 1.0

  // Grading Nodes
  final LookPrimary primary;
  final LookColor color;
  final LookWheels wheels;
  final LookCurves curves;
  final LookHsl hsl;
  final List<LutItem> lutStack;
  final LookFilm film;
  final LookDetail detail;
  final LookOptics optics;
  final LookFx fx;

  // Modern Vision & Retouch Stages
  final BoostBeautyConfig boostBeauty;
  final BackgroundEffectConfig background;
  final AdaptiveRulesConfig adaptive;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const OneovaLook({
    this.schemaVersion = 2,
    this.id = 'neutral',
    this.name = 'Neutral',
    this.ownerUid = '',
    this.categories = const ['natural'],
    this.tags = const [],
    this.thumbnailUrl = '',
    this.source = 'user',
    this.parentLookId,
    this.priceRef,
    this.minDeviceTier = 1,
    this.intensity = 1.0,
    this.primary = const LookPrimary(),
    this.color = const LookColor(),
    this.wheels = const LookWheels(),
    this.curves = const LookCurves(),
    this.hsl = const LookHsl(),
    this.lutStack = const [],
    this.film = const LookFilm(),
    this.detail = const LookDetail(),
    this.optics = const LookOptics(),
    this.fx = const LookFx(),
    this.boostBeauty = const BoostBeautyConfig(),
    this.background = const BackgroundEffectConfig(),
    this.adaptive = const AdaptiveRulesConfig(),
    this.createdAt,
    this.updatedAt,
  });

  /// True if the look fits the default Live/Camera budget. Use
  /// `isRealtimeCompatibleWith(LookRealtimeBudget.fromRemoteConfig())`
  /// (look_param_ranges.dart) for the server-tuned budget.
  bool get isRealtimeCompatible =>
      isRealtimeCompatibleWith(const LookRealtimeBudget());

  /// True if all grading and retouch nodes are in their default neutral states.
  bool get isNeutral =>
      primary.isNeutral &&
      color.isNeutral &&
      wheels.isNeutral &&
      curves.isNeutral &&
      hsl.isNeutral &&
      film.isNeutral &&
      detail.isNeutral &&
      optics.isNeutral &&
      fx.isNeutral &&
      boostBeauty.isNeutral &&
      background.isNeutral;

  OneovaLook copyWith({
    int? schemaVersion,
    String? id,
    String? name,
    String? ownerUid,
    List<String>? categories,
    List<String>? tags,
    String? thumbnailUrl,
    String? source,
    String? parentLookId,
    String? priceRef,
    int? minDeviceTier,
    double? intensity,
    LookPrimary? primary,
    LookColor? color,
    LookWheels? wheels,
    LookCurves? curves,
    LookHsl? hsl,
    List<LutItem>? lutStack,
    LookFilm? film,
    LookDetail? detail,
    LookOptics? optics,
    LookFx? fx,
    BoostBeautyConfig? boostBeauty,
    BackgroundEffectConfig? background,
    AdaptiveRulesConfig? adaptive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return OneovaLook(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      id: id ?? this.id,
      name: name ?? this.name,
      ownerUid: ownerUid ?? this.ownerUid,
      categories: categories ?? this.categories,
      tags: tags ?? this.tags,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      source: source ?? this.source,
      parentLookId: parentLookId ?? this.parentLookId,
      priceRef: priceRef ?? this.priceRef,
      minDeviceTier: minDeviceTier ?? this.minDeviceTier,
      intensity: intensity ?? this.intensity,
      primary: primary ?? this.primary,
      color: color ?? this.color,
      wheels: wheels ?? this.wheels,
      curves: curves ?? this.curves,
      hsl: hsl ?? this.hsl,
      lutStack: lutStack ?? this.lutStack,
      film: film ?? this.film,
      detail: detail ?? this.detail,
      optics: optics ?? this.optics,
      fx: fx ?? this.fx,
      boostBeauty: boostBeauty ?? this.boostBeauty,
      background: background ?? this.background,
      adaptive: adaptive ?? this.adaptive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'schemaVersion': schemaVersion,
      'id': id,
      'name': name,
      'ownerUid': ownerUid,
      'categories': categories,
      'tags': tags,
      'thumbnailUrl': thumbnailUrl,
      'source': source,
      'parentLookId': parentLookId,
      'priceRef': priceRef,
      'minDeviceTier': minDeviceTier,
      'intensity': intensity,
      'primary': primary.toMap(),
      'color': color.toMap(),
      'wheels': wheels.toMap(),
      'curves': curves.toMap(),
      'hsl': hsl.toMap(),
      'lutStack': lutStack.map((e) => e.toMap()).toList(),
      'film': film.toMap(),
      'detail': detail.toMap(),
      'optics': optics.toMap(),
      'fx': fx.toMap(),
      'boostBeauty': boostBeauty.toMap(),
      'background': background.toMap(),
      'adaptive': adaptive.toMap(),
      'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
      'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  factory OneovaLook.fromMap(Map<String, dynamic> map) {
    return OneovaLook(
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 2,
      id: map['id'] as String? ?? 'look_${DateTime.now().millisecondsSinceEpoch}',
      name: map['name'] as String? ?? 'Natural Clean',
      ownerUid: map['ownerUid'] as String? ?? '',
      categories: (map['categories'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['natural'],
      tags: (map['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      thumbnailUrl: map['thumbnailUrl'] as String? ?? '',
      source: map['source'] as String? ?? 'user',
      parentLookId: map['parentLookId'] as String?,
      priceRef: map['priceRef'] as String?,
      minDeviceTier: (map['minDeviceTier'] as num?)?.toInt() ?? 1,
      intensity: (map['intensity'] as num?)?.toDouble() ?? 1.0,
      primary: map['primary'] is Map<String, dynamic>
          ? LookPrimary.fromMap(map['primary'] as Map<String, dynamic>)
          : const LookPrimary(),
      color: map['color'] is Map<String, dynamic>
          ? LookColor.fromMap(map['color'] as Map<String, dynamic>)
          : const LookColor(),
      wheels: map['wheels'] is Map<String, dynamic>
          ? LookWheels.fromMap(map['wheels'] as Map<String, dynamic>)
          : const LookWheels(),
      curves: map['curves'] is Map<String, dynamic>
          ? LookCurves.fromMap(map['curves'] as Map<String, dynamic>)
          : const LookCurves(),
      hsl: map['hsl'] is Map<String, dynamic>
          ? LookHsl.fromMap(map['hsl'] as Map<String, dynamic>)
          : const LookHsl(),
      lutStack: (map['lutStack'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(LutItem.fromMap)
              .toList() ??
          const [],
      film: map['film'] is Map<String, dynamic>
          ? LookFilm.fromMap(map['film'] as Map<String, dynamic>)
          : const LookFilm(),
      detail: map['detail'] is Map<String, dynamic>
          ? LookDetail.fromMap(map['detail'] as Map<String, dynamic>)
          : const LookDetail(),
      optics: map['optics'] is Map<String, dynamic>
          ? LookOptics.fromMap(map['optics'] as Map<String, dynamic>)
          : const LookOptics(),
      fx: map['fx'] is Map<String, dynamic>
          ? LookFx.fromMap(map['fx'] as Map<String, dynamic>)
          : const LookFx(),
      boostBeauty: map['boostBeauty'] is Map<String, dynamic>
          ? BoostBeautyConfig.fromMap(map['boostBeauty'] as Map<String, dynamic>)
          : const BoostBeautyConfig(),
      background: map['background'] is Map<String, dynamic>
          ? BackgroundEffectConfig.fromMap(
              map['background'] as Map<String, dynamic>)
          : const BackgroundEffectConfig(),
      adaptive: map['adaptive'] is Map<String, dynamic>
          ? AdaptiveRulesConfig.fromMap(map['adaptive'] as Map<String, dynamic>)
          : const AdaptiveRulesConfig(),
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());

  factory OneovaLook.fromJson(String source) =>
      OneovaLook.fromMap(json.decode(source) as Map<String, dynamic>);
}
