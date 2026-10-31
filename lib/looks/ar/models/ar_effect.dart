import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Where an effect is pinned on the subject (or the scene).
enum ArAnchor {
  eyes('Eyes'),
  forehead('Forehead'),
  headTop('Head top'),
  hair('Hair'),
  nose('Nose'),
  mouth('Mouth'),
  chin('Chin / beard'),
  face('Full face'),
  neck('Neck'),
  torso('Body / clothes'),
  world('Background (world)'),
  screen('Background (scene)');

  final String label;
  const ArAnchor(this.label);

  static ArAnchor parse(Object? v) =>
      values.firstWhere((a) => a.name == v, orElse: () => ArAnchor.face);

  bool get needsFace => index <= ArAnchor.neck.index;
  bool get needsBody => this == ArAnchor.torso;
}

/// How an effect renders.
enum ArEffectKind {
  /// A transparent PNG pinned to an [ArAnchor].
  sprite,

  /// Colors drawn along face contours (lips, blush, eyes, brows).
  makeup,

  /// A scene that replaces the background behind the person.
  background;

  static ArEffectKind parse(Object? v) =>
      values.firstWhere((k) => k.name == v, orElse: () => ArEffectKind.sprite);
}

/// Browsing categories in the effects picker.
enum ArEffectCategory {
  glasses('Glasses', Icons.visibility_outlined),
  eyes('Eyes', Icons.remove_red_eye_outlined),
  makeup('Makeup', Icons.brush_outlined),
  hats('Hats', Icons.school_outlined),
  hair('Hair', Icons.face_retouching_natural),
  beards('Beards', Icons.face_outlined),
  masks('Masks', Icons.theater_comedy_outlined),
  jewelry('Jewelry', Icons.diamond_outlined),
  clothes('Clothes', Icons.checkroom_outlined),
  stickers('Stickers', Icons.auto_awesome_outlined),
  world('World', Icons.view_in_ar_outlined),
  backgrounds('Backgrounds', Icons.landscape_outlined);

  final String label;
  final IconData icon;
  const ArEffectCategory(this.label, this.icon);

  static ArEffectCategory parse(Object? v) =>
      values.firstWhere((c) => c.name == v, orElse: () => ArEffectCategory.stickers);
}

enum ArAudience {
  unisex('Everyone'),
  girls('Girls'),
  boys('Boys');

  final String label;
  const ArAudience(this.label);

  static ArAudience parse(Object? v) =>
      values.firstWhere((a) => a.name == v, orElse: () => ArAudience.unisex);
}

/// Colors for [ArEffectKind.makeup] effects. Opacity 0 means "not drawn".
@immutable
class ArMakeup {
  final Color lipColor;
  final double lipOpacity;
  final Color blushColor;
  final double blushOpacity;
  final Color eyeColor;
  final double eyeOpacity;
  final double eyeGlow;
  final Color linerColor;
  final double linerOpacity;
  final Color browColor;
  final double browOpacity;

  const ArMakeup({
    this.lipColor = const Color(0x00000000),
    this.lipOpacity = 0,
    this.blushColor = const Color(0x00000000),
    this.blushOpacity = 0,
    this.eyeColor = const Color(0x00000000),
    this.eyeOpacity = 0,
    this.eyeGlow = 0,
    this.linerColor = const Color(0x00000000),
    this.linerOpacity = 0,
    this.browColor = const Color(0x00000000),
    this.browOpacity = 0,
  });

  static Color _color(Object? v) {
    if (v is String) {
      final hex = v.replaceFirst('#', '');
      final n = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
      if (n != null) return Color(n);
    }
    return const Color(0x00000000);
  }

  static double _d(Object? v) => ((v as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);

  factory ArMakeup.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const ArMakeup();
    return ArMakeup(
      lipColor: _color(m['lipColor']),
      lipOpacity: _d(m['lipOpacity']),
      blushColor: _color(m['blushColor']),
      blushOpacity: _d(m['blushOpacity']),
      eyeColor: _color(m['eyeColor']),
      eyeOpacity: _d(m['eyeOpacity']),
      eyeGlow: _d(m['eyeGlow']),
      linerColor: _color(m['linerColor']),
      linerOpacity: _d(m['linerOpacity']),
      browColor: _color(m['browColor']),
      browOpacity: _d(m['browOpacity']),
    );
  }
}

/// One effect from the Firestore `ar_effects` catalog.
@immutable
class ArEffect {
  final String id;
  final String name;
  final String description;
  final ArEffectKind kind;
  final ArEffectCategory category;
  final ArAudience audience;
  final ArAnchor anchor;
  final List<String> tags;

  /// Sprite width relative to the anchor's reference width (face or shoulders).
  final double scale;

  /// Offsets in reference-width units, in the face's own (rolled) frame.
  final double offsetX;
  final double offsetY;

  final String? assetUrl;
  final String? thumbUrl;
  final ArMakeup makeup;
  final String creatorUid;
  final String creatorName;
  final String source; // 'ai' | 'upload'
  final bool listed;
  final int usageCount;
  final int favoriteCount;
  final DateTime? createdAt;

  const ArEffect({
    required this.id,
    required this.name,
    this.description = '',
    required this.kind,
    required this.category,
    this.audience = ArAudience.unisex,
    required this.anchor,
    this.tags = const [],
    this.scale = 1,
    this.offsetX = 0,
    this.offsetY = 0,
    this.assetUrl,
    this.thumbUrl,
    this.makeup = const ArMakeup(),
    required this.creatorUid,
    this.creatorName = '',
    this.source = 'ai',
    this.listed = false,
    this.usageCount = 0,
    this.favoriteCount = 0,
    this.createdAt,
  });

  bool get needsFace => kind == ArEffectKind.makeup || anchor.needsFace;
  bool get needsBody => kind == ArEffectKind.sprite && anchor.needsBody;
  bool get needsMask => kind == ArEffectKind.background;
  bool get isWorld => kind == ArEffectKind.sprite && anchor == ArAnchor.world;

  /// Effects that can be worn together share nothing but the slot key.
  String get slot => switch (kind) {
        ArEffectKind.makeup => 'makeup',
        ArEffectKind.background => 'background',
        ArEffectKind.sprite => anchor == ArAnchor.world ? 'world:$id' : anchor.name,
      };

  factory ArEffect.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    double num0(Object? v, double fallback) => (v as num?)?.toDouble() ?? fallback;
    return ArEffect(
      id: doc.id,
      name: (d['name'] as String?) ?? 'Effect',
      description: (d['description'] as String?) ?? '',
      kind: ArEffectKind.parse(d['kind']),
      category: ArEffectCategory.parse(d['category']),
      audience: ArAudience.parse(d['audience']),
      anchor: ArAnchor.parse(d['anchor']),
      tags: List<String>.from((d['tags'] as List?) ?? const []),
      scale: num0(d['scale'], 1).clamp(0.2, 4.0),
      offsetX: num0(d['offsetX'], 0).clamp(-2.0, 2.0),
      offsetY: num0(d['offsetY'], 0).clamp(-3.0, 3.0),
      assetUrl: d['assetUrl'] as String?,
      thumbUrl: (d['thumbUrl'] as String?) ?? d['assetUrl'] as String?,
      makeup: ArMakeup.fromMap((d['makeup'] as Map?)?.cast<String, dynamic>()),
      creatorUid: (d['creatorUid'] as String?) ?? '',
      creatorName: (d['creatorName'] as String?) ?? '',
      source: (d['source'] as String?) ?? 'ai',
      listed: d['listed'] == true,
      usageCount: (d['usageCount'] as num?)?.toInt() ?? 0,
      favoriteCount: (d['favoriteCount'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
