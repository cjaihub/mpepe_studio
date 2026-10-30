import 'package:flutter/foundation.dart';
import '../../models/oneova_look.dart';

/// Named snapshot of complete live broadcast settings (`users/{uid}/liveProfiles/{id}`).
@immutable
class LiveProfile {
  final String id;
  final String name;
  final String description;
  final String? lookId;
  final OneovaLook? customLook;
  final BoostBeautyConfig beauty;
  final String resolution; // '720p', '1080p', '4K'
  final int fps; // 30, 60
  final bool isHdr;
  final bool noiseSuppression;
  final bool echoCancellation;
  final bool voiceEnhance;
  final DateTime updatedAt;

  const LiveProfile({
    required this.id,
    required this.name,
    this.description = '',
    this.lookId,
    this.customLook,
    this.beauty = const BoostBeautyConfig(),
    this.resolution = '1080p',
    this.fps = 30,
    this.isHdr = false,
    this.noiseSuppression = true,
    this.echoCancellation = true,
    this.voiceEnhance = true,
    required this.updatedAt,
  });

  LiveProfile copyWith({
    String? id,
    String? name,
    String? description,
    String? lookId,
    OneovaLook? customLook,
    BoostBeautyConfig? beauty,
    String? resolution,
    int? fps,
    bool? isHdr,
    bool? noiseSuppression,
    bool? echoCancellation,
    bool? voiceEnhance,
    DateTime? updatedAt,
  }) {
    return LiveProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      lookId: lookId ?? this.lookId,
      customLook: customLook ?? this.customLook,
      beauty: beauty ?? this.beauty,
      resolution: resolution ?? this.resolution,
      fps: fps ?? this.fps,
      isHdr: isHdr ?? this.isHdr,
      noiseSuppression: noiseSuppression ?? this.noiseSuppression,
      echoCancellation: echoCancellation ?? this.echoCancellation,
      voiceEnhance: voiceEnhance ?? this.voiceEnhance,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'lookId': lookId,
        if (customLook != null) 'customLook': customLook!.toMap(),
        'beauty': beauty.toMap(),
        'resolution': resolution,
        'fps': fps,
        'isHdr': isHdr,
        'noiseSuppression': noiseSuppression,
        'echoCancellation': echoCancellation,
        'voiceEnhance': voiceEnhance,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory LiveProfile.fromMap(Map<String, dynamic> map, {String? id}) {
    return LiveProfile(
      id: id ?? map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Untitled Profile',
      description: map['description'] as String? ?? '',
      lookId: map['lookId'] as String?,
      customLook: map['customLook'] is Map<String, dynamic>
          ? OneovaLook.fromMap(map['customLook'] as Map<String, dynamic>)
          : null,
      beauty: map['beauty'] is Map<String, dynamic>
          ? BoostBeautyConfig.fromMap(map['beauty'] as Map<String, dynamic>)
          : const BoostBeautyConfig(),
      resolution: map['resolution'] as String? ?? '1080p',
      fps: (map['fps'] as num?)?.toInt() ?? 30,
      isHdr: map['isHdr'] as bool? ?? false,
      noiseSuppression: map['noiseSuppression'] as bool? ?? true,
      echoCancellation: map['echoCancellation'] as bool? ?? true,
      voiceEnhance: map['voiceEnhance'] as bool? ?? true,
      updatedAt: map['updatedAt'] is String
          ? DateTime.tryParse(map['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// A live broadcast scene (`users/{uid}/liveScenes/{id}`).
/// Combines Look, beauty, background, overlay, and audio preset for 1-tap switching.
@immutable
class LiveScene {
  final String id;
  final String name;
  final int order;
  final String? lookId;
  final OneovaLook? look;
  final BoostBeautyConfig beauty;
  final BackgroundEffectConfig background;
  final String audioPreset; // 'voice', 'music', 'podcast', 'studio'
  final String transitionStyle; // 'crossfade', 'cut', 'smooth'
  final Duration transitionDuration;

  const LiveScene({
    required this.id,
    required this.name,
    this.order = 0,
    this.lookId,
    this.look,
    this.beauty = const BoostBeautyConfig(),
    this.background = const BackgroundEffectConfig(),
    this.audioPreset = 'studio',
    this.transitionStyle = 'crossfade',
    this.transitionDuration = const Duration(milliseconds: 300),
  });

  LiveScene copyWith({
    String? id,
    String? name,
    int? order,
    String? lookId,
    OneovaLook? look,
    BoostBeautyConfig? beauty,
    BackgroundEffectConfig? background,
    String? audioPreset,
    String? transitionStyle,
    Duration? transitionDuration,
  }) {
    return LiveScene(
      id: id ?? this.id,
      name: name ?? this.name,
      order: order ?? this.order,
      lookId: lookId ?? this.lookId,
      look: look ?? this.look,
      beauty: beauty ?? this.beauty,
      background: background ?? this.background,
      audioPreset: audioPreset ?? this.audioPreset,
      transitionStyle: transitionStyle ?? this.transitionStyle,
      transitionDuration: transitionDuration ?? this.transitionDuration,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'order': order,
        'lookId': lookId,
        if (look != null) 'look': look!.toMap(),
        'beauty': beauty.toMap(),
        'background': background.toMap(),
        'audioPreset': audioPreset,
        'transitionStyle': transitionStyle,
        'transitionMs': transitionDuration.inMilliseconds,
      };

  factory LiveScene.fromMap(Map<String, dynamic> map, {String? id}) {
    return LiveScene(
      id: id ?? map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Scene',
      order: (map['order'] as num?)?.toInt() ?? 0,
      lookId: map['lookId'] as String?,
      look: map['look'] is Map<String, dynamic>
          ? OneovaLook.fromMap(map['look'] as Map<String, dynamic>)
          : null,
      beauty: map['beauty'] is Map<String, dynamic>
          ? BoostBeautyConfig.fromMap(map['beauty'] as Map<String, dynamic>)
          : const BoostBeautyConfig(),
      background: map['background'] is Map<String, dynamic>
          ? BackgroundEffectConfig.fromMap(map['background'] as Map<String, dynamic>)
          : const BackgroundEffectConfig(),
      audioPreset: map['audioPreset'] as String? ?? 'studio',
      transitionStyle: map['transitionStyle'] as String? ?? 'crossfade',
      transitionDuration: Duration(
        milliseconds: (map['transitionMs'] as num?)?.toInt() ?? 300,
      ),
    );
  }
}

/// Stream Health metrics gathered live from WebRTC and Device Thermal Governor.
@immutable
class LiveHealthMetrics {
  final int bitrateKbps;
  final double fps;
  final double droppedFramesPct;
  final double gpuFrameMs;
  final double thermalHeadroom;
  final String thermalLevelName; // 'nominal', 'fair', 'serious', 'critical'
  final double batteryLevel;
  final bool isCharging;
  final int activeMitigationTier;

  const LiveHealthMetrics({
    this.bitrateKbps = 0,
    this.fps = 0.0,
    this.droppedFramesPct = 0.0,
    this.gpuFrameMs = 0.0,
    this.thermalHeadroom = 0.0,
    this.thermalLevelName = 'nominal',
    this.batteryLevel = 1.0,
    this.isCharging = false,
    this.activeMitigationTier = 0,
  });

  bool get isHealthy =>
      droppedFramesPct < 5.0 &&
      thermalHeadroom < 0.85 &&
      fps >= 24.0;
}

/// Non-intrusive alert chip from AI Live Director.
@immutable
class LiveDirectorAlert {
  final String id;
  final String title;
  final String explanation;
  final bool isFixable;
  final OneovaLook? proposedFix;

  const LiveDirectorAlert({
    required this.id,
    required this.title,
    required this.explanation,
    this.isFixable = true,
    this.proposedFix,
  });
}
