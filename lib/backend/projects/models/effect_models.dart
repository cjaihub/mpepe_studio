import 'package:uuid/uuid.dart';
import 'keyframe_models.dart';

enum EffectCategory {
  blur,
  sharpen,
  light,
  color,
  distortion,
  stylize,
  film,
  optical,
  keying,
  transform,
  motion,
}

enum BlendMode {
  normal,
  multiply,
  screen,
  overlay,
  softLight,
  hardLight,
  darken,
  lighten,
  difference,
  add,
  subtract,
  color,
  luminosity,
}

abstract class EffectParameters {
  Map<String, dynamic> toJson();
  
  EffectParameters copyWith();
}

class GaussianBlurParameters implements EffectParameters {
  final double radius;
  final double quality;
  
  GaussianBlurParameters({this.radius = 10.0, this.quality = 1.0});

  @override
  Map<String, dynamic> toJson() => {'radius': radius, 'quality': quality};

  @override
  GaussianBlurParameters copyWith({double? radius, double? quality}) {
    return GaussianBlurParameters(
      radius: radius ?? this.radius,
      quality: quality ?? this.quality,
    );
  }
  
  factory GaussianBlurParameters.fromJson(Map<String, dynamic> json) => GaussianBlurParameters(
    radius: (json['radius'] ?? 10.0).toDouble(),
    quality: (json['quality'] ?? 1.0).toDouble(),
  );
}

class GlowParameters implements EffectParameters {
  final double threshold;
  final double radius;
  final double intensity;
  final String color;
  
  GlowParameters({
    this.threshold = 0.5,
    this.radius = 20.0,
    this.intensity = 1.0,
    this.color = '#FFFFFF',
  });

  @override
  Map<String, dynamic> toJson() => {
    'threshold': threshold,
    'radius': radius,
    'intensity': intensity,
    'color': color,
  };

  @override
  GlowParameters copyWith({
    double? threshold,
    double? radius,
    double? intensity,
    String? color,
  }) {
    return GlowParameters(
      threshold: threshold ?? this.threshold,
      radius: radius ?? this.radius,
      intensity: intensity ?? this.intensity,
      color: color ?? this.color,
    );
  }
  
  factory GlowParameters.fromJson(Map<String, dynamic> json) => GlowParameters(
    threshold: (json['threshold'] ?? 0.5).toDouble(),
    radius: (json['radius'] ?? 20.0).toDouble(),
    intensity: (json['intensity'] ?? 1.0).toDouble(),
    color: json['color'] ?? '#FFFFFF',
  );
}

class FilmGrainParameters implements EffectParameters {
  final double amount;
  final double size;
  final double softness;
  final bool monochrome;
  
  FilmGrainParameters({
    this.amount = 0.5,
    this.size = 1.0,
    this.softness = 0.5,
    this.monochrome = true,
  });

  @override
  Map<String, dynamic> toJson() => {
    'amount': amount,
    'size': size,
    'softness': softness,
    'monochrome': monochrome,
  };

  @override
  FilmGrainParameters copyWith({
    double? amount,
    double? size,
    double? softness,
    bool? monochrome,
  }) {
    return FilmGrainParameters(
      amount: amount ?? this.amount,
      size: size ?? this.size,
      softness: softness ?? this.softness,
      monochrome: monochrome ?? this.monochrome,
    );
  }
  
  factory FilmGrainParameters.fromJson(Map<String, dynamic> json) => FilmGrainParameters(
    amount: (json['amount'] ?? 0.5).toDouble(),
    size: (json['size'] ?? 1.0).toDouble(),
    softness: (json['softness'] ?? 0.5).toDouble(),
    monochrome: json['monochrome'] ?? true,
  );
}

class ChromaticAberrationParameters implements EffectParameters {
  final double redShift;
  final double blueShift;
  final double amount;
  final double centerX;
  final double centerY;
  
  ChromaticAberrationParameters({
    this.redShift = 2.0,
    this.blueShift = -2.0,
    this.amount = 1.0,
    this.centerX = 0.5,
    this.centerY = 0.5,
  });

  @override
  Map<String, dynamic> toJson() => {
    'redShift': redShift,
    'blueShift': blueShift,
    'amount': amount,
    'centerX': centerX,
    'centerY': centerY,
  };

  @override
  ChromaticAberrationParameters copyWith({
    double? redShift,
    double? blueShift,
    double? amount,
    double? centerX,
    double? centerY,
  }) {
    return ChromaticAberrationParameters(
      redShift: redShift ?? this.redShift,
      blueShift: blueShift ?? this.blueShift,
      amount: amount ?? this.amount,
      centerX: centerX ?? this.centerX,
      centerY: centerY ?? this.centerY,
    );
  }
  
  factory ChromaticAberrationParameters.fromJson(Map<String, dynamic> json) => ChromaticAberrationParameters(
    redShift: (json['redShift'] ?? 2.0).toDouble(),
    blueShift: (json['blueShift'] ?? -2.0).toDouble(),
    amount: (json['amount'] ?? 1.0).toDouble(),
    centerX: (json['centerX'] ?? 0.5).toDouble(),
    centerY: (json['centerY'] ?? 0.5).toDouble(),
  );
}

class ChromaKeyParameters implements EffectParameters {
  final String keyColor;
  final double similarity;
  final double smoothness;
  final double spillReduction;
  
  ChromaKeyParameters({
    this.keyColor = '#00FF00',
    this.similarity = 0.4,
    this.smoothness = 0.1,
    this.spillReduction = 0.5,
  });

  @override
  Map<String, dynamic> toJson() => {
    'keyColor': keyColor,
    'similarity': similarity,
    'smoothness': smoothness,
    'spillReduction': spillReduction,
  };

  @override
  ChromaKeyParameters copyWith({
    String? keyColor,
    double? similarity,
    double? smoothness,
    double? spillReduction,
  }) {
    return ChromaKeyParameters(
      keyColor: keyColor ?? this.keyColor,
      similarity: similarity ?? this.similarity,
      smoothness: smoothness ?? this.smoothness,
      spillReduction: spillReduction ?? this.spillReduction,
    );
  }
  
  factory ChromaKeyParameters.fromJson(Map<String, dynamic> json) => ChromaKeyParameters(
    keyColor: json['keyColor'] ?? '#00FF00',
    similarity: (json['similarity'] ?? 0.4).toDouble(),
    smoothness: (json['smoothness'] ?? 0.1).toDouble(),
    spillReduction: (json['spillReduction'] ?? 0.5).toDouble(),
  );
}

class SharpenParameters implements EffectParameters {
  final double intensity;
  final double radius;
  
  SharpenParameters({
    this.intensity = 0.5,
    this.radius = 1.0,
  });

  @override
  Map<String, dynamic> toJson() => {
    'intensity': intensity,
    'radius': radius,
  };

  @override
  SharpenParameters copyWith({
    double? intensity,
    double? radius,
  }) {
    return SharpenParameters(
      intensity: intensity ?? this.intensity,
      radius: radius ?? this.radius,
    );
  }
  
  factory SharpenParameters.fromJson(Map<String, dynamic> json) => SharpenParameters(
    intensity: (json['intensity'] ?? 0.5).toDouble(),
    radius: (json['radius'] ?? 1.0).toDouble(),
  );
}

class MotionPresetParameters implements EffectParameters {
  final String presetId;
  final double scaleOffset;
  final double rotationOffset;
  
  MotionPresetParameters({
    this.presetId = 'zoom_in',
    this.scaleOffset = 1.2,
    this.rotationOffset = 0.0,
  });

  @override
  Map<String, dynamic> toJson() => {
    'presetId': presetId,
    'scaleOffset': scaleOffset,
    'rotationOffset': rotationOffset,
  };

  @override
  MotionPresetParameters copyWith({
    String? presetId,
    double? scaleOffset,
    double? rotationOffset,
  }) {
    return MotionPresetParameters(
      presetId: presetId ?? this.presetId,
      scaleOffset: scaleOffset ?? this.scaleOffset,
      rotationOffset: rotationOffset ?? this.rotationOffset,
    );
  }
  
  factory MotionPresetParameters.fromJson(Map<String, dynamic> json) => MotionPresetParameters(
    presetId: json['presetId'] ?? 'zoom_in',
    scaleOffset: (json['scaleOffset'] ?? 1.2).toDouble(),
    rotationOffset: (json['rotationOffset'] ?? 0.0).toDouble(),
  );
}

class GenericEffectParameters implements EffectParameters {
  final Map<String, dynamic> data;
  GenericEffectParameters(this.data);
  
  @override
  Map<String, dynamic> toJson() => data;
  
  @override
  GenericEffectParameters copyWith() => GenericEffectParameters(Map.from(data));
  
  factory GenericEffectParameters.fromJson(Map<String, dynamic> json) => GenericEffectParameters(json);
}

class EffectState {
  final String id;
  final String type; // e.g. 'gaussian_blur'
  final String name;
  final bool enabled;
  final double opacity;
  final BlendMode blendMode;
  final EffectParameters parameters;
  final String? maskId;
  final String? trackingId;
  final List<Keyframe> keyframes;
  final int order;
  final int version;
  final Map<String, dynamic> metadata;

  EffectState({
    String? id,
    required this.type,
    required this.name,
    this.enabled = true,
    this.opacity = 1.0,
    this.blendMode = BlendMode.normal,
    required this.parameters,
    this.maskId,
    this.trackingId,
    List<Keyframe>? keyframes,
    this.order = 0,
    this.version = 1,
    Map<String, dynamic>? metadata,
  })  : id = id ?? const Uuid().v4(),
        keyframes = keyframes ?? [],
        metadata = metadata ?? {};

  EffectState copyWith({
    String? id,
    String? type,
    String? name,
    bool? enabled,
    double? opacity,
    BlendMode? blendMode,
    EffectParameters? parameters,
    String? maskId,
    String? trackingId,
    List<Keyframe>? keyframes,
    int? order,
    int? version,
    Map<String, dynamic>? metadata,
  }) {
    return EffectState(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      opacity: opacity ?? this.opacity,
      blendMode: blendMode ?? this.blendMode,
      parameters: parameters ?? this.parameters.copyWith(),
      maskId: maskId ?? this.maskId,
      trackingId: trackingId ?? this.trackingId,
      keyframes: keyframes ?? List.from(this.keyframes),
      order: order ?? this.order,
      version: version ?? this.version,
      metadata: metadata ?? Map.from(this.metadata),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'name': name,
    'enabled': enabled,
    'opacity': opacity,
    'blendMode': blendMode.index,
    'parameters': parameters.toJson(),
    'maskId': maskId,
    'trackingId': trackingId,
    'keyframes': keyframes.map((k) => k.toJson()).toList(),
    'order': order,
    'version': version,
    'metadata': metadata,
  };

  factory EffectState.fromJson(Map<String, dynamic> json) {
    EffectParameters parseParameters(String type, Map<String, dynamic> data) {
      switch (type) {
        case 'gaussian_blur':
          return GaussianBlurParameters.fromJson(data);
        case 'glow':
          return GlowParameters.fromJson(data);
        case 'film_grain':
          return FilmGrainParameters.fromJson(data);
        case 'chromatic_aberration':
          return ChromaticAberrationParameters.fromJson(data);
        case 'chroma_key':
          return ChromaKeyParameters.fromJson(data);
        case 'sharpen':
          return SharpenParameters.fromJson(data);
        case 'motion_preset':
          return MotionPresetParameters.fromJson(data);
        default:
          return GenericEffectParameters.fromJson(data);
      }
    }

    return EffectState(
      id: json['id'],
      type: json['type'] ?? 'unknown',
      name: json['name'] ?? 'Effect',
      enabled: json['enabled'] ?? true,
      opacity: (json['opacity'] ?? 1.0).toDouble(),
      blendMode: BlendMode.values[json['blendMode'] ?? 0],
      parameters: parseParameters(json['type'] ?? '', json['parameters'] ?? {}),
      maskId: json['maskId'],
      trackingId: json['trackingId'],
      keyframes: (json['keyframes'] as List<dynamic>?)?.map((k) => Keyframe.fromJson(k)).toList(),
      order: json['order'] ?? 0,
      version: json['version'] ?? 1,
      metadata: json['metadata'] ?? {},
    );
  }
}
