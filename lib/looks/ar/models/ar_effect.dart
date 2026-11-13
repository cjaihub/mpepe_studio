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
  background,

  /// A physically based glTF model worn at an [ArAnchor] (rendered natively).
  model3d,

  /// Procedural CapCut/TikTok-style VFX drawn along tracked face & body pose.
  vfx;

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
///
/// Every field is drawn live on the tracked face (Dart preview) and in the
/// native recorder (`ArOverlayPainter.kt` / `ArGlPipeline.kt`), so photos and
/// videos match what the camera showed.
@immutable
class ArMakeup {
  static const _none = Color(0x00000000);

  final Color lipColor;
  final double lipOpacity;

  /// 0 matte … 1 high-shine gloss highlight on the lower lip.
  final double lipGloss;
  final Color blushColor;
  final double blushOpacity;

  /// Iris tint (and glow color).
  final Color eyeColor;
  final double eyeOpacity;
  final double eyeGlow;
  final Color shadowColor;
  final double shadowOpacity;
  final Color linerColor;
  final double linerOpacity;

  /// Liner thickness, 0 fine … 1 bold.
  final double linerWidth;

  /// Winged tip length, 0 none … 1 dramatic.
  final double linerWing;
  final Color browColor;
  final double browOpacity;

  /// Brow thickness, 0 thin … 1 bold.
  final double browWidth;

  /// Skin tint over the face (eyes, brows and lips left clear).
  final Color foundationColor;
  final double foundationOpacity;
  final double contourOpacity;
  final double highlightOpacity;

  /// Skin smoothing strength (blurs skin only, not eyes/brows/lips).
  final double smoothing;

  const ArMakeup({
    this.lipColor = _none,
    this.lipOpacity = 0,
    this.lipGloss = 0,
    this.blushColor = _none,
    this.blushOpacity = 0,
    this.eyeColor = _none,
    this.eyeOpacity = 0,
    this.eyeGlow = 0,
    this.shadowColor = _none,
    this.shadowOpacity = 0,
    this.linerColor = _none,
    this.linerOpacity = 0,
    this.linerWidth = 0.35,
    this.linerWing = 0,
    this.browColor = _none,
    this.browOpacity = 0,
    this.browWidth = 0.5,
    this.foundationColor = _none,
    this.foundationOpacity = 0,
    this.contourOpacity = 0,
    this.highlightOpacity = 0,
    this.smoothing = 0,
  });

  bool get isEmpty =>
      lipOpacity == 0 &&
      blushOpacity == 0 &&
      eyeOpacity == 0 &&
      eyeGlow == 0 &&
      shadowOpacity == 0 &&
      linerOpacity == 0 &&
      browOpacity == 0 &&
      foundationOpacity == 0 &&
      contourOpacity == 0 &&
      highlightOpacity == 0 &&
      smoothing == 0;

  ArMakeup copyWith({
    Color? lipColor,
    double? lipOpacity,
    double? lipGloss,
    Color? blushColor,
    double? blushOpacity,
    Color? eyeColor,
    double? eyeOpacity,
    double? eyeGlow,
    Color? shadowColor,
    double? shadowOpacity,
    Color? linerColor,
    double? linerOpacity,
    double? linerWidth,
    double? linerWing,
    Color? browColor,
    double? browOpacity,
    double? browWidth,
    Color? foundationColor,
    double? foundationOpacity,
    double? contourOpacity,
    double? highlightOpacity,
    double? smoothing,
  }) =>
      ArMakeup(
        lipColor: lipColor ?? this.lipColor,
        lipOpacity: lipOpacity ?? this.lipOpacity,
        lipGloss: lipGloss ?? this.lipGloss,
        blushColor: blushColor ?? this.blushColor,
        blushOpacity: blushOpacity ?? this.blushOpacity,
        eyeColor: eyeColor ?? this.eyeColor,
        eyeOpacity: eyeOpacity ?? this.eyeOpacity,
        eyeGlow: eyeGlow ?? this.eyeGlow,
        shadowColor: shadowColor ?? this.shadowColor,
        shadowOpacity: shadowOpacity ?? this.shadowOpacity,
        linerColor: linerColor ?? this.linerColor,
        linerOpacity: linerOpacity ?? this.linerOpacity,
        linerWidth: linerWidth ?? this.linerWidth,
        linerWing: linerWing ?? this.linerWing,
        browColor: browColor ?? this.browColor,
        browOpacity: browOpacity ?? this.browOpacity,
        browWidth: browWidth ?? this.browWidth,
        foundationColor: foundationColor ?? this.foundationColor,
        foundationOpacity: foundationOpacity ?? this.foundationOpacity,
        contourOpacity: contourOpacity ?? this.contourOpacity,
        highlightOpacity: highlightOpacity ?? this.highlightOpacity,
        smoothing: smoothing ?? this.smoothing,
      );

  static Color _color(Object? v) {
    if (v is String) {
      final hex = v.replaceFirst('#', '');
      final n = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
      if (n != null) return Color(n);
    }
    if (v is int) return Color(v);
    return _none;
  }

  static double _d(Object? v, [double fallback = 0]) =>
      ((v as num?)?.toDouble() ?? fallback).clamp(0.0, 1.0);

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  factory ArMakeup.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const ArMakeup();
    return ArMakeup(
      lipColor: _color(m['lipColor']),
      lipOpacity: _d(m['lipOpacity']),
      lipGloss: _d(m['lipGloss']),
      blushColor: _color(m['blushColor']),
      blushOpacity: _d(m['blushOpacity']),
      eyeColor: _color(m['eyeColor']),
      eyeOpacity: _d(m['eyeOpacity']),
      eyeGlow: _d(m['eyeGlow']),
      shadowColor: _color(m['shadowColor']),
      shadowOpacity: _d(m['shadowOpacity']),
      linerColor: _color(m['linerColor']),
      linerOpacity: _d(m['linerOpacity']),
      linerWidth: _d(m['linerWidth'], 0.35),
      linerWing: _d(m['linerWing']),
      browColor: _color(m['browColor']),
      browOpacity: _d(m['browOpacity']),
      browWidth: _d(m['browWidth'], 0.5),
      foundationColor: _color(m['foundationColor']),
      foundationOpacity: _d(m['foundationOpacity']),
      contourOpacity: _d(m['contourOpacity']),
      highlightOpacity: _d(m['highlightOpacity']),
      smoothing: _d(m['smoothing']),
    );
  }

  /// JSON-friendly form (hex colors), e.g. for the AI makeup callable.
  Map<String, Object> toJson() => {
        'lipColor': _hex(lipColor),
        'lipOpacity': lipOpacity,
        'lipGloss': lipGloss,
        'blushColor': _hex(blushColor),
        'blushOpacity': blushOpacity,
        'eyeColor': _hex(eyeColor),
        'eyeOpacity': eyeOpacity,
        'eyeGlow': eyeGlow,
        'shadowColor': _hex(shadowColor),
        'shadowOpacity': shadowOpacity,
        'linerColor': _hex(linerColor),
        'linerOpacity': linerOpacity,
        'linerWidth': linerWidth,
        'linerWing': linerWing,
        'browColor': _hex(browColor),
        'browOpacity': browOpacity,
        'browWidth': browWidth,
        'foundationColor': _hex(foundationColor),
        'foundationOpacity': foundationOpacity,
        'contourOpacity': contourOpacity,
        'highlightOpacity': highlightOpacity,
        'smoothing': smoothing,
      };

  /// What the native recorder reads (ARGB ints for colors).
  Map<String, Object> toNative() => {
        'lipColor': lipColor.toARGB32(),
        'lipOpacity': lipOpacity,
        'lipGloss': lipGloss,
        'blushColor': blushColor.toARGB32(),
        'blushOpacity': blushOpacity,
        'eyeColor': eyeColor.toARGB32(),
        'eyeOpacity': eyeOpacity,
        'eyeGlow': eyeGlow,
        'shadowColor': shadowColor.toARGB32(),
        'shadowOpacity': shadowOpacity,
        'linerColor': linerColor.toARGB32(),
        'linerOpacity': linerOpacity,
        'linerWidth': linerWidth,
        'linerWing': linerWing,
        'browColor': browColor.toARGB32(),
        'browOpacity': browOpacity,
        'browWidth': browWidth,
        'foundationColor': foundationColor.toARGB32(),
        'foundationOpacity': foundationOpacity,
        'contourOpacity': contourOpacity,
        'highlightOpacity': highlightOpacity,
        'smoothing': smoothing,
      };
}

/// How a 3D model sits at its anchor: alignment in degrees and depth in metres.
@immutable
class ArModelFit {
  final double rotX;
  final double rotY;
  final double rotZ;
  final double offsetZ;

  const ArModelFit({this.rotX = 0, this.rotY = 0, this.rotZ = 0, this.offsetZ = 0});

  factory ArModelFit.fromMap(Map<String, dynamic>? m) {
    double n(String k) => (m?[k] as num?)?.toDouble() ?? 0;
    return ArModelFit(rotX: n('rotX'), rotY: n('rotY'), rotZ: n('rotZ'), offsetZ: n('offsetZ').clamp(-0.2, 0.2));
  }

  Map<String, double> toMap() => {'rotX': rotX, 'rotY': rotY, 'rotZ': rotZ, 'offsetZ': offsetZ};
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

  /// [ArEffectKind.model3d]: the .glb file and how the model is aligned.
  final String? modelUrl;
  final ArModelFit modelFit;

  /// Credit for openly licensed assets (e.g. "CC BY 4.0").
  final String license;
  final String attribution;
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
    this.modelUrl,
    this.modelFit = const ArModelFit(),
    this.license = '',
    this.attribution = '',
    this.makeup = const ArMakeup(),
    required this.creatorUid,
    this.creatorName = '',
    this.source = 'ai',
    this.listed = false,
    this.usageCount = 0,
    this.favoriteCount = 0,
    this.createdAt,
  });

  bool get needsFace => kind == ArEffectKind.makeup || kind == ArEffectKind.vfx || anchor.needsFace;
  bool get needsBody => (kind == ArEffectKind.sprite || kind == ArEffectKind.vfx) && anchor.needsBody;
  bool get needsMask => kind == ArEffectKind.background;
  bool get isWorld => kind == ArEffectKind.sprite && anchor == ArAnchor.world;

  /// Effects that can be worn together share nothing but the slot key.
  String get slot => switch (kind) {
        ArEffectKind.makeup => 'makeup',
        ArEffectKind.background => 'background',
        ArEffectKind.vfx => 'vfx',
        ArEffectKind.sprite => anchor == ArAnchor.world ? 'world:$id' : anchor.name,
        ArEffectKind.model3d => anchor.name,
      };

  bool get is3d => kind == ArEffectKind.model3d;

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
      modelUrl: d['modelUrl'] as String?,
      modelFit: ArModelFit.fromMap((d['model'] as Map?)?.cast<String, dynamic>()),
      license: (d['license'] as String?) ?? '',
      attribution: (d['attribution'] as String?) ?? '',
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
