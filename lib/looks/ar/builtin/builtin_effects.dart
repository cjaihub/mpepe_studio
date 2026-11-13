import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/ar_effect.dart';
import 'builtin_art.dart';

/// One built-in effect: its catalog entry plus how its art is drawn.
class BuiltInEffect {
  final ArEffect effect;
  final ArtPainter? art;
  final double aspect;

  const BuiltInEffect(this.effect, {this.art, this.aspect = 1});

  bool get hasArt => art != null;
}

/// Effects that ship with the app. They are drawn in code (no downloads, no
/// Firestore), work offline, and run through the same tracking, preview,
/// photo baking and native video recording as catalog effects.
class BuiltInEffects {
  BuiltInEffects._();

  static const prefix = 'builtin_';

  static bool isBuiltIn(String id) => id.startsWith(prefix);

  static final List<BuiltInEffect> all = [
    // Glasses — centered between the eyes, about one face wide.
    _sprite('round_specs', 'Round specs', ArEffectCategory.glasses, ArAnchor.eyes, BuiltInArt.roundGlasses, 0.36, tags: ['glasses', 'gold', 'vintage']),
    _sprite('aviators', 'Aviators', ArEffectCategory.glasses, ArAnchor.eyes, BuiltInArt.aviators, 0.36, scale: 1.05, tags: ['sunglasses', 'pilot', 'cool']),
    _sprite('cat_eye', 'Cat-eye frames', ArEffectCategory.glasses, ArAnchor.eyes, BuiltInArt.catEye, 0.36, audience: ArAudience.girls, tags: ['glasses', 'pink', 'retro']),
    _sprite('heart_shades', 'Heart shades', ArEffectCategory.glasses, ArAnchor.eyes, BuiltInArt.heartShades, 0.36, audience: ArAudience.girls, tags: ['sunglasses', 'love', 'pink']),
    _sprite('star_shades', 'Star shades', ArEffectCategory.glasses, ArAnchor.eyes, BuiltInArt.starShades, 0.36, scale: 1.05, tags: ['sunglasses', 'party', 'gold']),
    _sprite('nerd_frames', 'Bold frames', ArEffectCategory.glasses, ArAnchor.eyes, BuiltInArt.nerdGlasses, 0.36, tags: ['glasses', 'black', 'nerd']),
    _sprite('cyber_visor', 'Cyber visor', ArEffectCategory.glasses, ArAnchor.eyes, BuiltInArt.cyberVisor, 0.36, scale: 1.08, tags: ['neon', 'future', 'blue']),
    _sprite('pixel_shades', 'Pixel shades', ArEffectCategory.glasses, ArAnchor.eyes, BuiltInArt.pixelShades, 0.36, scale: 1.02, tags: ['meme', 'pixel', 'cool']),

    // Head — bottom edge sits on the hair above the hairline.
    _hat('crown', 'Gold crown', BuiltInArt.crown, 0.62, scale: 0.75, gap: 0.14, tags: ['king', 'queen', 'royal', 'gold']),
    _hat('tiara', 'Tiara', BuiltInArt.tiara, 0.45, scale: 0.7, gap: 0.12, audience: ArAudience.girls, tags: ['princess', 'crystal', 'royal']),
    _hat('halo', 'Halo', BuiltInArt.halo, 0.4, scale: 0.75, gap: 0.3, tags: ['angel', 'glow', 'gold']),
    _hat('devil_horns', 'Devil horns', BuiltInArt.devilHorns, 0.5, scale: 0.85, gap: 0.08, tags: ['devil', 'red', 'halloween']),
    _hat('cat_ears', 'Cat ears', BuiltInArt.catEars, 0.5, scale: 0.95, gap: 0.08, audience: ArAudience.girls, tags: ['cat', 'cute', 'kitty']),
    _hat('bunny_ears', 'Bunny ears', BuiltInArt.bunnyEars, 0.95, scale: 0.85, gap: 0.08, tags: ['bunny', 'rabbit', 'cute']),
    _hat('flower_crown', 'Flower crown', BuiltInArt.flowerCrown, 0.4, scale: 0.85, gap: 0.05, audience: ArAudience.girls, tags: ['flowers', 'spring', 'boho']),
    _hat('party_hat', 'Party hat', BuiltInArt.partyHat, 1.1, scale: 0.5, gap: 0.12, tags: ['birthday', 'party', 'celebrate']),
    _hat('cap', 'Blue cap', BuiltInArt.cap, 0.7, scale: 0.85, gap: -0.1, audience: ArAudience.boys, tags: ['hat', 'cap', 'street']),

    // Masks.
    _sprite('butterfly_mask', 'Butterfly mask', ArEffectCategory.masks, ArAnchor.eyes, BuiltInArt.butterflyMask, 0.55, scale: 1.2, audience: ArAudience.girls, tags: ['masquerade', 'butterfly', 'purple']),
    _sprite('hero_mask', 'Hero mask', ArEffectCategory.masks, ArAnchor.eyes, BuiltInArt.heroMask, 0.45, scale: 1.12, audience: ArAudience.boys, tags: ['superhero', 'mask', 'dark']),
    _sprite('clown_nose', 'Clown nose', ArEffectCategory.stickers, ArAnchor.nose, BuiltInArt.clownNose, 1, scale: 0.6, tags: ['funny', 'clown', 'red']),
    _sprite('cat_nose', 'Cat nose & whiskers', ArEffectCategory.masks, ArAnchor.nose, BuiltInArt.catNose, 0.5, scale: 3.2, offsetY: 0.06, tags: ['cat', 'whiskers', 'cute']),
    _sprite('tiger_paint', 'Tiger paint', ArEffectCategory.masks, ArAnchor.face, BuiltInArt.tigerPaint, 1.25, tags: ['tiger', 'face paint', 'stripes']),
    _sprite('freckles', 'Freckles', ArEffectCategory.makeup, ArAnchor.face, BuiltInArt.freckles, 1.25, audience: ArAudience.girls, tags: ['freckles', 'cute', 'natural']),
    _sprite('glitter_tears', 'Glitter tears', ArEffectCategory.makeup, ArAnchor.face, BuiltInArt.glitterTears, 1.25, audience: ArAudience.girls, tags: ['glitter', 'sparkle', 'euphoria']),

    // Facial hair.
    _sprite('full_beard', 'Full beard', ArEffectCategory.beards, ArAnchor.chin, BuiltInArt.fullBeard, 0.9, scale: 1.05, offsetY: 0.06, audience: ArAudience.boys, tags: ['beard', 'hair', 'brown']),
    _sprite('goatee', 'Goatee', ArEffectCategory.beards, ArAnchor.chin, BuiltInArt.goatee, 1.1, scale: 0.45, offsetY: 0.12, audience: ArAudience.boys, tags: ['beard', 'goatee']),
    _sprite('mustache', 'Handlebar mustache', ArEffectCategory.beards, ArAnchor.mouth, BuiltInArt.mustache, 0.4, scale: 1.1, offsetY: -0.09, audience: ArAudience.boys, tags: ['mustache', 'moustache', 'gentleman']),

    // Neck.
    _sprite('gold_chain', 'Gold chain', ArEffectCategory.jewelry, ArAnchor.neck, BuiltInArt.goldChain, 0.45, offsetY: 0.18, tags: ['chain', 'gold', 'bling']),
    _sprite('pearls', 'Pearl necklace', ArEffectCategory.jewelry, ArAnchor.neck, BuiltInArt.pearls, 0.45, offsetY: 0.18, audience: ArAudience.girls, tags: ['pearls', 'necklace', 'elegant']),
    _sprite('bow_tie', 'Bow tie', ArEffectCategory.clothes, ArAnchor.neck, BuiltInArt.bowTie, 0.5, scale: 0.5, offsetY: 0.3, audience: ArAudience.boys, tags: ['bow tie', 'formal', 'suit']),

    // World (stays put in the room; drag/pinch to place).
    _sprite('floating_hearts', 'Floating hearts', ArEffectCategory.world, ArAnchor.world, BuiltInArt.floatingHearts, 1, tags: ['hearts', 'love', 'pink']),
    _sprite('sparkles', 'Sparkles', ArEffectCategory.world, ArAnchor.world, BuiltInArt.sparkles, 1, tags: ['sparkle', 'stars', 'magic']),
    _sprite('bubbles', 'Bubbles', ArEffectCategory.world, ArAnchor.world, BuiltInArt.bubbles, 1, tags: ['bubbles', 'water', 'fun']),
    _sprite('neon_love', 'Neon LOVE sign', ArEffectCategory.world, ArAnchor.world, BuiltInArt.neonLove, 0.75, scale: 1.3, tags: ['neon', 'sign', 'love']),

    // Backgrounds (replace what's behind the person).
    _scene('studio_blue', 'Blue studio', BuiltInArt.bgStudioBlue, tags: ['studio', 'blue', 'clean']),
    _scene('white_studio', 'White studio', BuiltInArt.bgWhiteStudio, tags: ['studio', 'white', 'clean']),
    _scene('sunset', 'Sunset', BuiltInArt.bgSunset, tags: ['sunset', 'beach', 'warm']),
    _scene('neon_grid', 'Neon grid', BuiltInArt.bgNeonGrid, tags: ['synthwave', 'retro', 'neon']),
    _scene('bokeh', 'City bokeh', BuiltInArt.bgBokeh, tags: ['lights', 'night', 'city']),
    _scene('starry_night', 'Starry night', BuiltInArt.bgStarryNight, tags: ['stars', 'night', 'moon']),
    _scene('pastel', 'Pastel dream', BuiltInArt.bgPastel, tags: ['pastel', 'soft', 'cute']),
    _scene('nebula', 'Deep space', BuiltInArt.bgNebula, tags: ['space', 'galaxy', 'nebula']),
    _scene('ocean', 'Ocean', BuiltInArt.bgOcean, tags: ['sea', 'water', 'blue']),

    // CapCut / TikTok-grade Body & Face VFX (tracked live on face mesh + full-body/hand pose).
    _vfx('vfx_neon_aura', 'Neon Body Aura', ArAnchor.torso, tags: ['vfx', 'neon', 'body', 'aura', 'outline', 'capcut']),
    _vfx('vfx_cyber_hud', 'Cyber Face Scanner', ArAnchor.face, tags: ['vfx', 'cyber', 'hud', 'scanner', 'mesh', 'neon']),
    _vfx('vfx_angel_glow', 'Angel Halo Glow', ArAnchor.face, tags: ['vfx', 'angel', 'halo', 'glow', 'wings']),
    _vfx('vfx_soul_clone', 'Soul Twin Clone', ArAnchor.face, tags: ['vfx', 'clone', 'soul', 'twin', 'tiktok']),
    _vfx('vfx_hand_sparks', 'Hand Energy Pulse', ArAnchor.torso, tags: ['vfx', 'hands', 'magic', 'sparks', 'gesture']),

    // Makeup looks (drawn on the face mesh; editable in Makeup Studio).
    ...looks.entries.map((e) => BuiltInEffect(ArEffect(
          id: '$prefix${e.key}',
          name: e.value.$1,
          kind: ArEffectKind.makeup,
          category: e.value.$3,
          audience: e.value.$4,
          anchor: ArAnchor.face,
          tags: e.value.$5,
          makeup: e.value.$2,
          creatorUid: '',
          creatorName: 'Oneova',
          source: 'builtin',
          listed: true,
        ))),
  ];

  /// Makeup and eye looks: id → (name, makeup, category, audience, tags).
  static final Map<String, (String, ArMakeup, ArEffectCategory, ArAudience, List<String>)> looks = {
    'natural_glow': (
      'Natural glow',
      const ArMakeup(lipColor: Color(0xFFC77D78), lipOpacity: 0.35, lipGloss: 0.3, blushColor: Color(0xFFF29A8E), blushOpacity: 0.35, highlightOpacity: 0.35, smoothing: 0.45, browColor: Color(0xFF4A3426), browOpacity: 0.25),
      ArEffectCategory.makeup, ArAudience.girls, ['natural', 'nude', 'glow', 'everyday'],
    ),
    'classic_red': (
      'Classic red',
      const ArMakeup(lipColor: Color(0xFFC8102E), lipOpacity: 0.85, linerColor: Color(0xFF111111), linerOpacity: 0.9, linerWidth: 0.5, linerWing: 0.6, smoothing: 0.35, browColor: Color(0xFF2E2018), browOpacity: 0.35),
      ArEffectCategory.makeup, ArAudience.girls, ['red lips', 'glam', 'classic', 'winged liner'],
    ),
    'berry_kiss': (
      'Berry kiss',
      const ArMakeup(lipColor: Color(0xFF8E1F4A), lipOpacity: 0.75, lipGloss: 0.4, blushColor: Color(0xFFD46A8C), blushOpacity: 0.3, shadowColor: Color(0xFF7A3B5A), shadowOpacity: 0.35, smoothing: 0.3),
      ArEffectCategory.makeup, ArAudience.girls, ['berry', 'plum', 'lips'],
    ),
    'coral_sunset': (
      'Coral sunset',
      const ArMakeup(lipColor: Color(0xFFFF6F61), lipOpacity: 0.65, lipGloss: 0.6, blushColor: Color(0xFFFF8A65), blushOpacity: 0.45, shadowColor: Color(0xFFE08A4F), shadowOpacity: 0.35, highlightOpacity: 0.4, smoothing: 0.35),
      ArEffectCategory.makeup, ArAudience.girls, ['coral', 'summer', 'peach'],
    ),
    'pink_doll': (
      'Pink doll',
      const ArMakeup(lipColor: Color(0xFFFF5C9E), lipOpacity: 0.7, lipGloss: 0.8, blushColor: Color(0xFFFF7AB6), blushOpacity: 0.6, shadowColor: Color(0xFFFF9EC7), shadowOpacity: 0.45, linerColor: Color(0xFF3A1F2E), linerOpacity: 0.7, linerWing: 0.3, smoothing: 0.5),
      ArEffectCategory.makeup, ArAudience.girls, ['pink', 'doll', 'cute', 'kawaii'],
    ),
    'smoky_night': (
      'Smoky night',
      const ArMakeup(lipColor: Color(0xFFA46A63), lipOpacity: 0.4, shadowColor: Color(0xFF2B2B33), shadowOpacity: 0.75, linerColor: Color(0xFF000000), linerOpacity: 1, linerWidth: 0.8, linerWing: 0.5, contourOpacity: 0.4, smoothing: 0.3),
      ArEffectCategory.makeup, ArAudience.girls, ['smoky eye', 'night', 'dramatic'],
    ),
    'gothic': (
      'Gothic',
      const ArMakeup(lipColor: Color(0xFF2A0A1E), lipOpacity: 0.9, shadowColor: Color(0xFF3B1030), shadowOpacity: 0.7, linerColor: Color(0xFF000000), linerOpacity: 1, linerWidth: 0.9, linerWing: 0.8, foundationColor: Color(0xFFF1E6E2), foundationOpacity: 0.35, browColor: Color(0xFF111111), browOpacity: 0.5),
      ArEffectCategory.makeup, ArAudience.unisex, ['goth', 'dark', 'black lips'],
    ),
    'gold_glam': (
      'Gold glam',
      const ArMakeup(lipColor: Color(0xFFB5655A), lipOpacity: 0.55, lipGloss: 0.7, shadowColor: Color(0xFFD4A017), shadowOpacity: 0.6, linerColor: Color(0xFF3A2410), linerOpacity: 0.8, linerWing: 0.5, highlightOpacity: 0.65, contourOpacity: 0.35, smoothing: 0.4),
      ArEffectCategory.makeup, ArAudience.girls, ['gold', 'glam', 'shimmer'],
    ),
    'k_beauty': (
      'Glass skin',
      const ArMakeup(lipColor: Color(0xFFE86A7A), lipOpacity: 0.5, lipGloss: 0.9, blushColor: Color(0xFFFFA8A0), blushOpacity: 0.4, highlightOpacity: 0.5, smoothing: 0.6),
      ArEffectCategory.makeup, ArAudience.girls, ['k-beauty', 'glass skin', 'dewy', 'gradient lips'],
    ),
    'sculpt': (
      'Sculpt & contour',
      const ArMakeup(contourOpacity: 0.7, highlightOpacity: 0.55, browColor: Color(0xFF3A2A1E), browOpacity: 0.35, smoothing: 0.3),
      ArEffectCategory.makeup, ArAudience.unisex, ['contour', 'sculpt', 'cheekbones'],
    ),
    'groomed': (
      'Groomed',
      const ArMakeup(smoothing: 0.4, browColor: Color(0xFF2A1E16), browOpacity: 0.25, browWidth: 0.6, contourOpacity: 0.25),
      ArEffectCategory.makeup, ArAudience.boys, ['clean', 'skin', 'grooming', 'natural'],
    ),
    'fresh_skin': (
      'Fresh skin',
      const ArMakeup(smoothing: 0.7, highlightOpacity: 0.25),
      ArEffectCategory.makeup, ArAudience.unisex, ['smooth', 'skin', 'beauty', 'retouch'],
    ),
    'bold_brows': (
      'Bold brows',
      const ArMakeup(browColor: Color(0xFF241812), browOpacity: 0.7, browWidth: 0.85),
      ArEffectCategory.makeup, ArAudience.unisex, ['brows', 'eyebrows', 'bold'],
    ),
    // Eyes.
    'ocean_eyes': ('Ocean eyes', const ArMakeup(eyeColor: Color(0xFF2F8FFF), eyeOpacity: 0.75), ArEffectCategory.eyes, ArAudience.unisex, ['blue eyes', 'lenses', 'iris']),
    'emerald_eyes': ('Emerald eyes', const ArMakeup(eyeColor: Color(0xFF1FAF6B), eyeOpacity: 0.75), ArEffectCategory.eyes, ArAudience.unisex, ['green eyes', 'lenses', 'iris']),
    'honey_eyes': ('Honey eyes', const ArMakeup(eyeColor: Color(0xFFC88A2E), eyeOpacity: 0.7), ArEffectCategory.eyes, ArAudience.unisex, ['hazel', 'brown eyes', 'lenses']),
    'violet_eyes': ('Violet eyes', const ArMakeup(eyeColor: Color(0xFF9B5CFF), eyeOpacity: 0.75), ArEffectCategory.eyes, ArAudience.unisex, ['purple eyes', 'lenses', 'fantasy']),
    'ice_eyes': ('Ice eyes', const ArMakeup(eyeColor: Color(0xFFB8D8F0), eyeOpacity: 0.8), ArEffectCategory.eyes, ArAudience.unisex, ['grey eyes', 'ice', 'cold']),
    'cyber_glow': ('Cyber glow', const ArMakeup(eyeColor: Color(0xFF00E5FF), eyeOpacity: 0.6, eyeGlow: 0.85), ArEffectCategory.eyes, ArAudience.unisex, ['glowing eyes', 'neon', 'robot']),
    'demon_glow': ('Demon glow', const ArMakeup(eyeColor: Color(0xFFFF1A1A), eyeOpacity: 0.7, eyeGlow: 0.8), ArEffectCategory.eyes, ArAudience.unisex, ['red eyes', 'glowing', 'halloween']),
    'golden_glow': ('Golden glow', const ArMakeup(eyeColor: Color(0xFFFFC400), eyeOpacity: 0.6, eyeGlow: 0.7), ArEffectCategory.eyes, ArAudience.unisex, ['gold eyes', 'glowing', 'magic']),
  };

  static final Map<String, BuiltInEffect> _byId = {for (final b in all) b.effect.id: b};

  static BuiltInEffect? byId(String id) => _byId[id];

  /// Renders the effect's art at full size (sprites 512 px, scenes 720×1280).
  static Future<ui.Image> image(String id) {
    final b = _byId[id];
    if (b == null || b.art == null) throw ArgumentError('No built-in art for $id');
    final scene = b.effect.kind == ArEffectKind.background;
    return BuiltInArt.render(id, b.art!, b.aspect, width: scene ? 720 : 512);
  }

  /// Small render for picker tiles.
  static Future<ui.Image> thumb(String id) {
    final b = _byId[id]!;
    return BuiltInArt.render(id, b.art!, b.aspect, width: 160);
  }

  /// Filters like the Firestore catalog query (search over name and tags).
  static List<ArEffect> filter({String search = '', ArEffectCategory? category, ArAudience? audience}) {
    final words = search.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 2).toList();
    return [
      for (final b in all)
        if ((category == null || b.effect.category == category) &&
            (audience == null ||
                audience == ArAudience.unisex ||
                b.effect.audience == audience ||
                b.effect.audience == ArAudience.unisex) &&
            words.every((w) {
              final hay = '${b.effect.name} ${b.effect.tags.join(' ')} ${b.effect.category.name}'.toLowerCase();
              return hay.contains(w);
            }))
          b.effect,
    ];
  }

  // ── Builders ────────────────────────────────────────────────────────────

  static BuiltInEffect _sprite(
    String key,
    String name,
    ArEffectCategory category,
    ArAnchor anchor,
    ArtPainter art,
    double aspect, {
    double scale = 1,
    double offsetX = 0,
    double offsetY = 0,
    ArAudience audience = ArAudience.unisex,
    List<String> tags = const [],
  }) =>
      BuiltInEffect(
        ArEffect(
          id: '$prefix$key',
          name: name,
          kind: ArEffectKind.sprite,
          category: category,
          audience: audience,
          anchor: anchor,
          tags: tags,
          scale: scale,
          offsetX: offsetX,
          offsetY: offsetY,
          creatorUid: '',
          creatorName: 'Oneova',
          source: 'builtin',
          listed: true,
        ),
        art: art,
        aspect: aspect,
      );

  /// Head-top sprite whose bottom edge sits [gap] face-widths above the
  /// forehead point. The painter centers head-top sprites 0.42 face widths
  /// above the forehead at a base width of 1.25 face widths.
  static BuiltInEffect _hat(
    String key,
    String name,
    ArtPainter art,
    double aspect, {
    double scale = 1,
    double gap = 0.1,
    ArAudience audience = ArAudience.unisex,
    List<String> tags = const [],
  }) {
    final height = 1.25 * scale * aspect;
    return _sprite(key, name, ArEffectCategory.hats, ArAnchor.headTop, art, aspect,
        scale: scale, offsetY: 0.42 - gap - height / 2, audience: audience, tags: tags);
  }

  static BuiltInEffect _scene(String key, String name, ArtPainter art, {List<String> tags = const []}) => BuiltInEffect(
        ArEffect(
          id: '$prefix$key',
          name: name,
          kind: ArEffectKind.background,
          category: ArEffectCategory.backgrounds,
          anchor: ArAnchor.screen,
          tags: tags,
          creatorUid: '',
          creatorName: 'Oneova',
          source: 'builtin',
          listed: true,
        ),
        art: art,
        aspect: 16 / 9,
      );

  static BuiltInEffect _vfx(String key, String name, ArAnchor anchor, {List<String> tags = const []}) => BuiltInEffect(
        ArEffect(
          id: '$prefix$key',
          name: name,
          kind: ArEffectKind.vfx,
          category: ArEffectCategory.stickers,
          anchor: anchor,
          tags: tags,
          creatorUid: '',
          creatorName: 'Oneova',
          source: 'builtin',
          listed: true,
        ),
      );
}
