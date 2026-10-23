import 'dart:convert';

/// Text overlay layer for non-destructive creator editing (Oneova Studio / Mobile standard)
class OneovaTextOverlay {
  final String id;
  final String text;
  final double x; // Normalized 0.0 - 1.0
  final double y; // Normalized 0.0 - 1.0
  final double scale;
  final double fontSize;
  final int colorHex;
  final int? backgroundColorHex;
  final bool isBold;

  const OneovaTextOverlay({
    required this.id,
    required this.text,
    this.x = 0.5,
    this.y = 0.4,
    this.scale = 1.0,
    this.fontSize = 24.0,
    this.colorHex = 0xFFFFFFFF,
    this.backgroundColorHex,
    this.isBold = true,
  });

  OneovaTextOverlay copyWith({
    String? id,
    String? text,
    double? x,
    double? y,
    double? scale,
    double? fontSize,
    int? colorHex,
    int? backgroundColorHex,
    bool? isBold,
  }) {
    return OneovaTextOverlay(
      id: id ?? this.id,
      text: text ?? this.text,
      x: x ?? this.x,
      y: y ?? this.y,
      scale: scale ?? this.scale,
      fontSize: fontSize ?? this.fontSize,
      colorHex: colorHex ?? this.colorHex,
      backgroundColorHex: backgroundColorHex ?? this.backgroundColorHex,
      isBold: isBold ?? this.isBold,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'text': text,
    'x': x,
    'y': y,
    'scale': scale,
    'fontSize': fontSize,
    'colorHex': colorHex,
    'backgroundColorHex': backgroundColorHex,
    'isBold': isBold,
  };

  factory OneovaTextOverlay.fromMap(Map<String, dynamic> map) => OneovaTextOverlay(
    id: map['id'] ?? '',
    text: map['text'] ?? '',
    x: (map['x'] as num?)?.toDouble() ?? 0.5,
    y: (map['y'] as num?)?.toDouble() ?? 0.4,
    scale: (map['scale'] as num?)?.toDouble() ?? 1.0,
    fontSize: (map['fontSize'] as num?)?.toDouble() ?? 24.0,
    colorHex: map['colorHex'] as int? ?? 0xFFFFFFFF,
    backgroundColorHex: map['backgroundColorHex'] as int?,
    isBold: map['isBold'] as bool? ?? true,
  );
}

/// Oneova Studio primary color grade & film LUT metadata
class OneovaColorGrade {
  final double exposure;   // -1.0 to 1.0 (default 0.0)
  final double contrast;   // 0.5 to 1.5 (default 1.0)
  final double saturation; // 0.0 to 2.0 (default 1.0)
  final double temperature;// -1.0 to 1.0 (default 0.0)
  final double tint;       // -1.0 to 1.0 (default 0.0)
  final String lutPreset;  // 'default', 'cinematic', 'warm_gold', 'noir', 'cyber_pink', 'vibrant'

  const OneovaColorGrade({
    this.exposure = 0.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.temperature = 0.0,
    this.tint = 0.0,
    this.lutPreset = 'default',
  });

  OneovaColorGrade copyWith({
    double? exposure,
    double? contrast,
    double? saturation,
    double? temperature,
    double? tint,
    String? lutPreset,
  }) {
    return OneovaColorGrade(
      exposure: exposure ?? this.exposure,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      lutPreset: lutPreset ?? this.lutPreset,
    );
  }

  Map<String, dynamic> toMap() => {
    'exposure': exposure,
    'contrast': contrast,
    'saturation': saturation,
    'temperature': temperature,
    'tint': tint,
    'lutPreset': lutPreset,
  };

  factory OneovaColorGrade.fromMap(Map<String, dynamic> map) => OneovaColorGrade(
    exposure: (map['exposure'] as num?)?.toDouble() ?? 0.0,
    contrast: (map['contrast'] as num?)?.toDouble() ?? 1.0,
    saturation: (map['saturation'] as num?)?.toDouble() ?? 1.0,
    temperature: (map['temperature'] as num?)?.toDouble() ?? 0.0,
    tint: (map['tint'] as num?)?.toDouble() ?? 0.0,
    lutPreset: map['lutPreset'] as String? ?? 'default',
  );
}

/// Dual audio channel mix (Original microphone track + soundtrack overlay)
class OneovaAudioMix {
  final double originalVolume; // 0.0 to 1.0
  final double musicVolume;    // 0.0 to 1.0
  final String? musicTitle;
  final String? musicAssetPath;

  const OneovaAudioMix({
    this.originalVolume = 1.0,
    this.musicVolume = 0.8,
    this.musicTitle,
    this.musicAssetPath,
  });

  OneovaAudioMix copyWith({
    double? originalVolume,
    double? musicVolume,
    String? musicTitle,
    String? musicAssetPath,
  }) {
    return OneovaAudioMix(
      originalVolume: originalVolume ?? this.originalVolume,
      musicVolume: musicVolume ?? this.musicVolume,
      musicTitle: musicTitle ?? this.musicTitle,
      musicAssetPath: musicAssetPath ?? this.musicAssetPath,
    );
  }

  Map<String, dynamic> toMap() => {
    'originalVolume': originalVolume,
    'musicVolume': musicVolume,
    'musicTitle': musicTitle,
    'musicAssetPath': musicAssetPath,
  };

  factory OneovaAudioMix.fromMap(Map<String, dynamic> map) => OneovaAudioMix(
    originalVolume: (map['originalVolume'] as num?)?.toDouble() ?? 1.0,
    musicVolume: (map['musicVolume'] as num?)?.toDouble() ?? 0.8,
    musicTitle: map['musicTitle'] as String?,
    musicAssetPath: map['musicAssetPath'] as String?,
  );
}

/// Canonical Draft Project Model for Oneova Studio
class OneovaDraft {
  final String id;
  final String title;
  final String mediaPath; // Permanent file path on disk
  final String? thumbnailPath;
  final bool isVideo;
  final double durationSeconds;
  final double trimStartSeconds;
  final double trimEndSeconds;
  final double speedMultiplier;
  final double aspectRatio; // 9/16 = 0.5625, 1/1 = 1.0, 16/9 = 1.7778
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<OneovaTextOverlay> textOverlays;
  final OneovaColorGrade colorGrade;
  final OneovaAudioMix audioMix;
  final Map<String, dynamic> aiMetadata;
  final String? caption;
  final List<String> tags;

  const OneovaDraft({
    required this.id,
    required this.title,
    required this.mediaPath,
    this.thumbnailPath,
    required this.isVideo,
    this.durationSeconds = 0.0,
    this.trimStartSeconds = 0.0,
    this.trimEndSeconds = 0.0,
    this.speedMultiplier = 1.0,
    this.aspectRatio = 9 / 16,
    required this.createdAt,
    required this.updatedAt,
    this.textOverlays = const [],
    this.colorGrade = const OneovaColorGrade(),
    this.audioMix = const OneovaAudioMix(),
    this.aiMetadata = const {},
    this.caption,
    this.tags = const [],
  });

  double get effectiveDuration =>
      (trimEndSeconds > trimStartSeconds)
          ? (trimEndSeconds - trimStartSeconds) / speedMultiplier
          : (durationSeconds > 0 ? durationSeconds / speedMultiplier : 0.0);

  OneovaDraft copyWith({
    String? id,
    String? title,
    String? mediaPath,
    String? thumbnailPath,
    bool? isVideo,
    double? durationSeconds,
    double? trimStartSeconds,
    double? trimEndSeconds,
    double? speedMultiplier,
    double? aspectRatio,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<OneovaTextOverlay>? textOverlays,
    OneovaColorGrade? colorGrade,
    OneovaAudioMix? audioMix,
    Map<String, dynamic>? aiMetadata,
    String? caption,
    List<String>? tags,
  }) {
    return OneovaDraft(
      id: id ?? this.id,
      title: title ?? this.title,
      mediaPath: mediaPath ?? this.mediaPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      isVideo: isVideo ?? this.isVideo,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      trimStartSeconds: trimStartSeconds ?? this.trimStartSeconds,
      trimEndSeconds: trimEndSeconds ?? this.trimEndSeconds,
      speedMultiplier: speedMultiplier ?? this.speedMultiplier,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      textOverlays: textOverlays ?? this.textOverlays,
      colorGrade: colorGrade ?? this.colorGrade,
      audioMix: audioMix ?? this.audioMix,
      aiMetadata: aiMetadata ?? this.aiMetadata,
      caption: caption ?? this.caption,
      tags: tags ?? this.tags,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'mediaPath': mediaPath,
    'thumbnailPath': thumbnailPath,
    'isVideo': isVideo,
    'durationSeconds': durationSeconds,
    'trimStartSeconds': trimStartSeconds,
    'trimEndSeconds': trimEndSeconds,
    'speedMultiplier': speedMultiplier,
    'aspectRatio': aspectRatio,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'textOverlays': textOverlays.map((t) => t.toMap()).toList(),
    'colorGrade': colorGrade.toMap(),
    'audioMix': audioMix.toMap(),
    'aiMetadata': aiMetadata,
    'caption': caption,
    'tags': tags,
  };

  factory OneovaDraft.fromMap(Map<String, dynamic> map) => OneovaDraft(
    id: map['id'] ?? '',
    title: map['title'] ?? 'Untitled Draft',
    mediaPath: map['mediaPath'] ?? '',
    thumbnailPath: map['thumbnailPath'] as String?,
    isVideo: map['isVideo'] as bool? ?? true,
    durationSeconds: (map['durationSeconds'] as num?)?.toDouble() ?? 0.0,
    trimStartSeconds: (map['trimStartSeconds'] as num?)?.toDouble() ?? 0.0,
    trimEndSeconds: (map['trimEndSeconds'] as num?)?.toDouble() ?? 0.0,
    speedMultiplier: (map['speedMultiplier'] as num?)?.toDouble() ?? 1.0,
    aspectRatio: (map['aspectRatio'] as num?)?.toDouble() ?? (9 / 16),
    createdAt: map['createdAt'] != null ? DateTime.parse(map['createdAt']) : DateTime.now(),
    updatedAt: map['updatedAt'] != null ? DateTime.parse(map['updatedAt']) : DateTime.now(),
    textOverlays: (map['textOverlays'] as List<dynamic>?)
            ?.map((e) => OneovaTextOverlay.fromMap(Map<String, dynamic>.from(e)))
            .toList() ??
        const [],
    colorGrade: map['colorGrade'] != null
        ? OneovaColorGrade.fromMap(Map<String, dynamic>.from(map['colorGrade']))
        : const OneovaColorGrade(),
    audioMix: map['audioMix'] != null
        ? OneovaAudioMix.fromMap(Map<String, dynamic>.from(map['audioMix']))
        : const OneovaAudioMix(),
    aiMetadata: Map<String, dynamic>.from(map['aiMetadata'] ?? {}),
    caption: map['caption'] as String?,
    tags: List<String>.from(map['tags'] ?? []),
  );

  String toJson() => jsonEncode(toMap());
  factory OneovaDraft.fromJson(String source) => OneovaDraft.fromMap(jsonDecode(source));
}
