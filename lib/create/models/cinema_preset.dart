import 'dart:convert';

/// Cinema color profile standards supported by the OneOva optical engine.
enum ColorScienceStandard {
  blackmagicGen5,
  arriLogC4,
  sonySLog3,
  appleProResLog,
  acesCc,
  obsidianCine,
  neutralRec709,
}

extension ColorScienceStandardExtension on ColorScienceStandard {
  String get displayName {
    switch (this) {
      case ColorScienceStandard.blackmagicGen5:
        return 'Oneova Cinema Film';
      case ColorScienceStandard.arriLogC4:
        return 'Oneova Log Cinema';
      case ColorScienceStandard.sonySLog3:
        return 'Oneova Dynamic Cine';
      case ColorScienceStandard.appleProResLog:
        return 'Oneova Studio ProRes';
      case ColorScienceStandard.acesCc:
        return 'Oneova ACEScc Wide';
      case ColorScienceStandard.obsidianCine:
        return 'Oneova Obsidian Prime';
      case ColorScienceStandard.neutralRec709:
        return 'Oneova Natural 709';
    }
  }

  String get shortTag {
    switch (this) {
      case ColorScienceStandard.blackmagicGen5:
        return 'ONEOVA CINE';
      case ColorScienceStandard.arriLogC4:
        return 'ONEOVA LOG';
      case ColorScienceStandard.sonySLog3:
        return 'ONEOVA DYN';
      case ColorScienceStandard.appleProResLog:
        return 'ONEOVA PRO';
      case ColorScienceStandard.acesCc:
        return 'ONEOVA ACES';
      case ColorScienceStandard.obsidianCine:
        return 'OBSIDIAN';
      case ColorScienceStandard.neutralRec709:
        return 'REC.709';
    }
  }

  String get description {
    switch (this) {
      case ColorScienceStandard.blackmagicGen5:
        return 'Oneova Wide Gamut logarithmic curve with soft shoulder rolloff and organic skin tones.';
      case ColorScienceStandard.arriLogC4:
        return 'Oneova Hollywood standard film curve calibrated for natural highlight roll-off and skin fidelity.';
      case ColorScienceStandard.sonySLog3:
        return 'Oneova Cinema-line broad dynamic range curve maximizing shadow retention and rich greens.';
      case ColorScienceStandard.appleProResLog:
        return '10-bit logarithmic mobile color science built for post-production grading flexibility.';
      case ColorScienceStandard.acesCc:
        return 'Academy Color Encoding System standard for visual effects and wide-gamut workflows.';
      case ColorScienceStandard.obsidianCine:
        return 'Oneova signature cinematic aesthetic with deep obsidian blacks and electric accents.';
      case ColorScienceStandard.neutralRec709:
        return 'Standard broadcast color space with linear contrast.';
    }
  }
}

/// A complete cinema preset encapsulating color science, adjustments, and AI enhancement.
class CinemaPreset {
  final String id;
  final String name;
  final ColorScienceStandard colorScience;
  final int kelvin; // 3200 to 8000
  final double tint; // -10.0 to +10.0
  final double exposure; // -2.0 to +2.0 EV
  final double contrast; // 0.5 to 1.8
  final double saturation; // 0.0 to 2.0
  final double filmGrain; // 0.0 to 1.0
  final bool isAiEnhanced;
  final String aiPrompt;
  final bool isUserCustom;
  final DateTime createdAt;

  const CinemaPreset({
    required this.id,
    required this.name,
    required this.colorScience,
    this.kelvin = 5600,
    this.tint = 0.0,
    this.exposure = 0.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.filmGrain = 0.0,
    this.isAiEnhanced = false,
    this.aiPrompt = '',
    this.isUserCustom = false,
    required this.createdAt,
  });

  CinemaPreset copyWith({
    String? id,
    String? name,
    ColorScienceStandard? colorScience,
    int? kelvin,
    double? tint,
    double? exposure,
    double? contrast,
    double? saturation,
    double? filmGrain,
    bool? isAiEnhanced,
    String? aiPrompt,
    bool? isUserCustom,
    DateTime? createdAt,
  }) {
    return CinemaPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      colorScience: colorScience ?? this.colorScience,
      kelvin: kelvin ?? this.kelvin,
      tint: tint ?? this.tint,
      exposure: exposure ?? this.exposure,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      filmGrain: filmGrain ?? this.filmGrain,
      isAiEnhanced: isAiEnhanced ?? this.isAiEnhanced,
      aiPrompt: aiPrompt ?? this.aiPrompt,
      isUserCustom: isUserCustom ?? this.isUserCustom,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'colorScience': colorScience.name,
      'kelvin': kelvin,
      'tint': tint,
      'exposure': exposure,
      'contrast': contrast,
      'saturation': saturation,
      'filmGrain': filmGrain,
      'isAiEnhanced': isAiEnhanced,
      'aiPrompt': aiPrompt,
      'isUserCustom': isUserCustom,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory CinemaPreset.fromMap(Map<String, dynamic> map) {
    return CinemaPreset(
      id: map['id'] as String? ?? 'custom_preset',
      name: map['name'] as String? ?? 'Custom Look',
      colorScience: ColorScienceStandard.values.firstWhere(
        (e) => e.name == map['colorScience'],
        orElse: () => ColorScienceStandard.blackmagicGen5,
      ),
      kelvin: (map['kelvin'] as num?)?.toInt() ?? 5600,
      tint: (map['tint'] as num?)?.toDouble() ?? 0.0,
      exposure: (map['exposure'] as num?)?.toDouble() ?? 0.0,
      contrast: (map['contrast'] as num?)?.toDouble() ?? 1.0,
      saturation: (map['saturation'] as num?)?.toDouble() ?? 1.0,
      filmGrain: (map['filmGrain'] as num?)?.toDouble() ?? 0.0,
      isAiEnhanced: map['isAiEnhanced'] as bool? ?? false,
      aiPrompt: map['aiPrompt'] as String? ?? '',
      isUserCustom: map['isUserCustom'] as bool? ?? true,
      createdAt: map['createdAt'] != null ? DateTime.parse(map['createdAt'] as String) : DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());

  factory CinemaPreset.fromJson(String source) => CinemaPreset.fromMap(json.decode(source) as Map<String, dynamic>);
}
