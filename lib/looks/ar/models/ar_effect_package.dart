import 'package:flutter/foundation.dart';

/// Categories for AR lenses and effects.
enum ArCategory {
  trending('Trending', '🔥'),
  makeup('Beauty & Makeup', '💄'),
  masks('Face Masks', '🎭'),
  fx3d('3D & Stickers', '✨'),
  backgrounds('Virtual Sets', '🎬');

  final String label;
  final String icon;
  const ArCategory(this.label, this.icon);
}

/// Gesture or facial trigger conditions for dynamic AR behaviors.
enum ArTriggerType {
  smile('smile', 'Smile Trigger', '😊'),
  mouthOpen('mouth_open', 'Open Mouth', '😮'),
  peaceSign('peace_sign', 'Peace Gesture', '✌️'),
  openPalm('open_palm', 'Open Palm', '✋'),
  thumbsUp('thumbs_up', 'Thumbs Up', '👍'),
  tapScreen('tap_screen', 'Tap Screen', '👆');

  final String key;
  final String label;
  final String emoji;
  const ArTriggerType(this.key, this.label, this.emoji);

  static ArTriggerType? fromKey(String key) {
    for (final t in values) {
      if (t.key == key) return t;
    }
    return null;
  }
}

/// Rendering layer type within an AR effect package.
enum ArLayerType {
  faceMask2d,
  sticker3d,
  makeup,
  hairColor,
  segmentationBg,
  cloneGhost,
}

/// Layer definition within an effect package.
@immutable
class ArEffectLayer {
  final String id;
  final ArLayerType type;
  final String assetPath;
  final int? anchorLandmarkIndex;
  final List<double> offset; // [x, y, z]
  final List<double> scale; // [x, y, z]
  final double opacity;
  final String? triggerRequired;

  const ArEffectLayer({
    required this.id,
    required this.type,
    required this.assetPath,
    this.anchorLandmarkIndex,
    this.offset = const [0.0, 0.0, 0.0],
    this.scale = const [1.0, 1.0, 1.0],
    this.opacity = 1.0,
    this.triggerRequired,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'asset_path': assetPath,
      if (anchorLandmarkIndex != null) 'anchor_landmark': anchorLandmarkIndex,
      'offset': offset,
      'scale': scale,
      'opacity': opacity,
      if (triggerRequired != null) 'trigger_required': triggerRequired,
    };
  }

  factory ArEffectLayer.fromJson(Map<String, dynamic> json) {
    return ArEffectLayer(
      id: json['id'] as String,
      type: ArLayerType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ArLayerType.sticker3d,
      ),
      assetPath: json['asset_path'] as String,
      anchorLandmarkIndex: json['anchor_landmark'] as int?,
      offset: (json['offset'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ??
          const [0.0, 0.0, 0.0],
      scale: (json['scale'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ??
          const [1.0, 1.0, 1.0],
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      triggerRequired: json['trigger_required'] as String?,
    );
  }
}

/// Specification for a packaged `.oneovafx` bundle.
@immutable
class OneovaEffectPackage {
  final String id;
  final String name;
  final int version;
  final String author;
  final ArCategory category;
  final String thumbnailUrl;
  final List<ArEffectLayer> layers;
  final Map<String, dynamic> customParameters;

  const OneovaEffectPackage({
    required this.id,
    required this.name,
    this.version = 1,
    required this.author,
    required this.category,
    required this.thumbnailUrl,
    required this.layers,
    this.customParameters = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'author': author,
      'category': category.name,
      'thumbnail_url': thumbnailUrl,
      'layers': layers.map((l) => l.toJson()).toList(),
      'parameters': customParameters,
    };
  }

  factory OneovaEffectPackage.fromJson(Map<String, dynamic> json) {
    return OneovaEffectPackage(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as int? ?? 1,
      author: json['author'] as String? ?? 'Oneova Studio',
      category: ArCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => ArCategory.trending,
      ),
      thumbnailUrl: json['thumbnail_url'] as String,
      layers: (json['layers'] as List<dynamic>?)
              ?.map((l) => ArEffectLayer.fromJson(l as Map<String, dynamic>))
              .toList() ??
          const [],
      customParameters: json['parameters'] as Map<String, dynamic>? ?? const {},
    );
  }

  /// Official built-in Oneova AR starter lenses.
  static const List<OneovaEffectPackage> starterLenses = [
    OneovaEffectPackage(
      id: 'lens_cyber_visor',
      name: 'Cyberpunk Visor',
      author: 'Oneova Core FX',
      category: ArCategory.fx3d,
      thumbnailUrl: 'assets/lenses/thumbs/cyber_visor.jpg',
      layers: [
        ArEffectLayer(
          id: 'visor_3d',
          type: ArLayerType.sticker3d,
          assetPath: 'assets/lenses/models/visor_neon.glb',
          anchorLandmarkIndex: 10, // Forehead anchor
          offset: [0.0, -0.02, 0.05],
          scale: [1.1, 1.1, 1.1],
        ),
      ],
      customParameters: {'glow_intensity': 1.5, 'visor_color': '#0C4FA8'},
    ),
    OneovaEffectPackage(
      id: 'lens_gloss_glam',
      name: 'Gloss Glam & Contour',
      author: 'Boost Beauty Team',
      category: ArCategory.makeup,
      thumbnailUrl: 'assets/lenses/thumbs/gloss_glam.jpg',
      layers: [
        ArEffectLayer(
          id: 'makeup_layer',
          type: ArLayerType.makeup,
          assetPath: 'assets/lenses/textures/makeup_contour_v2.png',
          opacity: 0.85,
        ),
      ],
      customParameters: {
        'lipstick_color': '#FF2D87',
        'lipstick_opacity': 0.75,
        'blush_opacity': 0.40,
        'eyeliner_opacity': 0.90,
      },
    ),
    OneovaEffectPackage(
      id: 'lens_neon_wings',
      name: 'Neon Angel & Halo',
      author: 'Oneova AR Studio',
      category: ArCategory.fx3d,
      thumbnailUrl: 'assets/lenses/thumbs/neon_wings.jpg',
      layers: [
        ArEffectLayer(
          id: 'halo_head',
          type: ArLayerType.sticker3d,
          assetPath: 'assets/lenses/models/halo_ring.glb',
          anchorLandmarkIndex: 10,
          offset: [0.0, -0.15, 0.0],
        ),
      ],
      customParameters: {'halo_spin_speed': 1.0},
    ),
    OneovaEffectPackage(
      id: 'lens_peace_sparks',
      name: 'Peace Gesture Sparks',
      author: 'Interactive Labs',
      category: ArCategory.trending,
      thumbnailUrl: 'assets/lenses/thumbs/peace_sparks.jpg',
      layers: [
        ArEffectLayer(
          id: 'hand_spark_emitter',
          type: ArLayerType.sticker3d,
          assetPath: 'assets/lenses/particles/sparks.json',
          anchorLandmarkIndex: 8, // Index finger tip
          triggerRequired: 'peace_sign',
        ),
      ],
    ),
    OneovaEffectPackage(
      id: 'lens_cyber_studio',
      name: 'Cyber Virtual Studio',
      author: 'Virtual Production',
      category: ArCategory.backgrounds,
      thumbnailUrl: 'assets/lenses/thumbs/cyber_studio.jpg',
      layers: [
        ArEffectLayer(
          id: 'stage_bg',
          type: ArLayerType.segmentationBg,
          assetPath: 'assets/lenses/backgrounds/cyber_stage.mp4',
        ),
      ],
    ),
  ];
}
