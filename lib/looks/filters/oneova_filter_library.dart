import 'package:flutter/foundation.dart';

import '../models/oneova_look.dart';

/// One Oneova filter: an original colour grade built on the Oneova Look
/// engine. `LookCompiler` bakes it into a 33³ 3D LUT (plus curves), the same
/// LUT the camera preview, the Studio preview and the Media3 export sample,
/// so a filter looks identical everywhere.
@immutable
class OneovaFilter {
  final String id;
  final String name;
  final String category;
  final String base;
  final String variant;
  final List<String> tags;
  final OneovaLook look;

  const OneovaFilter({
    required this.id,
    required this.name,
    required this.category,
    required this.base,
    required this.variant,
    required this.tags,
    required this.look,
  });

  /// Lower-case words searched by [OneovaFilterLibrary.search].
  String get searchText => '$name $category $variant ${tags.join(' ')}'.toLowerCase();
}

/// A base grade before variants: deltas from neutral.
@immutable
class _Recipe {
  final String key;
  final String name;
  final List<String> tags;
  final double temp, tint, sat, vib;
  final double con, exp, hi, sh, wh, bl;
  final double fade, grain, vig, sharpen;
  final double matte, curve;
  final List<double> lift, gain;
  final Map<String, List<double>> hsl;

  const _Recipe(
    this.key,
    this.name, {
    this.tags = const [],
    this.temp = 0,
    this.tint = 0,
    this.sat = 1,
    this.vib = 0,
    this.con = 1,
    this.exp = 0,
    this.hi = 0,
    this.sh = 0,
    this.wh = 0,
    this.bl = 0,
    this.fade = 0,
    this.grain = 0,
    this.vig = 0,
    this.sharpen = 0,
    this.matte = 0,
    this.curve = 0,
    this.lift = const [0, 0, 0],
    this.gain = const [0, 0, 0],
    this.hsl = const {},
  });

  _Recipe mod({
    double? k,
    double dTemp = 0,
    double satMul = 1,
    double dVib = 0,
    double conMul = 1,
    double dExp = 0,
    double dSh = 0,
    double dBl = 0,
    double dFade = 0,
    double dGrain = 0,
    double dVig = 0,
    double dMatte = 0,
  }) {
    final s = k ?? 1.0;
    double l(double neutral, double v) => neutral + (v - neutral) * s;
    return _Recipe(
      key,
      name,
      tags: tags,
      temp: l(0, temp) + dTemp,
      tint: l(0, tint),
      sat: (l(1, sat) * satMul).clamp(0.0, 2.0),
      vib: (l(0, vib) + dVib).clamp(-1.0, 1.0),
      con: (l(1, con) * conMul).clamp(0.6, 1.8),
      exp: l(0, exp) + dExp,
      hi: l(0, hi),
      sh: (l(0, sh) + dSh).clamp(-1.0, 1.0),
      wh: l(0, wh),
      bl: (l(0, bl) + dBl).clamp(-1.0, 1.0),
      fade: (l(0, fade) + dFade).clamp(0.0, 1.0),
      grain: (l(0, grain) + dGrain).clamp(0.0, 1.0),
      vig: (l(0, vig) + dVig).clamp(0.0, 1.0),
      sharpen: l(0, sharpen),
      matte: (l(0, matte) + dMatte).clamp(0.0, 0.25),
      curve: l(0, curve),
      lift: [for (final v in lift) v * s],
      gain: [for (final v in gain) v * s],
      hsl: {
        for (final e in hsl.entries) e.key: [for (final v in e.value) v * s],
      },
    );
  }

  OneovaLook build(String id, String label, String category) {
    HslBand band(String k) {
      final v = hsl[k];
      return v == null ? const HslBand() : HslBand(hue: v[0], sat: v[1], lum: v.length > 2 ? v[2] : 0);
    }

    // Matte lifts the blacks and rolls off the whites; curve > 0 is an S-curve.
    final master = (matte == 0 && curve == 0)
        ? const [CurvePoint(0, 0), CurvePoint(1, 1)]
        : [
            CurvePoint(0, matte),
            CurvePoint(0.25, (0.25 - 0.045 * curve + matte * 0.55).clamp(0.0, 1.0)),
            CurvePoint(0.75, (0.75 + 0.045 * curve - matte * 0.2).clamp(0.0, 1.0)),
            CurvePoint(1, 1 - matte * 0.3),
          ];
    return OneovaLook(
      id: id,
      name: label,
      source: 'oneova',
      categories: [category.toLowerCase()],
      tags: tags,
      primary: LookPrimary(
        exposure: exp,
        contrast: con,
        highlights: hi.clamp(-1.0, 1.0),
        shadows: sh,
        whites: wh.clamp(-1.0, 1.0),
        blacks: bl,
      ),
      color: LookColor(temperature: temp.clamp(-100.0, 100.0), tint: tint.clamp(-100.0, 100.0), vibrance: vib, saturation: sat),
      wheels: LookWheels(
        lift: ColorWheel(r: lift[0], g: lift[1], b: lift[2]),
        gain: ColorWheel(r: gain[0], g: gain[1], b: gain[2]),
      ),
      curves: LookCurves(master: master),
      hsl: LookHsl(
        red: band('red'),
        orange: band('orange'),
        yellow: band('yellow'),
        green: band('green'),
        aqua: band('aqua'),
        blue: band('blue'),
        purple: band('purple'),
        magenta: band('magenta'),
      ),
      film: LookFilm(fade: fade, grain: grain),
      detail: LookDetail(sharpen: sharpen),
      optics: LookOptics(vignette: vig),
    );
  }
}

class _Variant {
  final String key;
  final String label;
  final List<String> tags;
  final _Recipe Function(_Recipe r) apply;
  const _Variant(this.key, this.label, this.tags, this.apply);
}

/// The Oneova filter library: hand-tuned base grades in each category, each
/// with twelve graded variants (soft, bold, warm, cool, faded, matte, bright,
/// deep, punch, grain, muted). Every name and grade is Oneova's own.
class OneovaFilterLibrary {
  OneovaFilterLibrary._();

  static const prefix = 'ov_';

  static final List<_Variant> _variants = [
    _Variant('', '', const [], (r) => r),
    _Variant('soft', 'Soft', const ['soft', 'subtle', 'light'], (r) => r.mod(k: 0.55)),
    _Variant('bold', 'Bold', const ['bold', 'strong', 'intense'], (r) => r.mod(k: 1.35)),
    _Variant('warm', 'Warm', const ['warm', 'sunny'], (r) => r.mod(dTemp: 12)),
    _Variant('cool', 'Cool', const ['cool', 'cold', 'blue'], (r) => r.mod(dTemp: -12)),
    _Variant('faded', 'Faded', const ['faded', 'vintage', 'washed'], (r) => r.mod(dFade: 0.14, satMul: 0.9)),
    _Variant('matte', 'Matte', const ['matte', 'flat'], (r) => r.mod(dMatte: 0.07, conMul: 0.94)),
    _Variant('bright', 'Bright', const ['bright', 'airy', 'light'], (r) => r.mod(dExp: 0.15, dSh: 0.1)),
    _Variant('deep', 'Deep', const ['deep', 'dark', 'rich'], (r) => r.mod(dExp: -0.12, dBl: -0.1, conMul: 1.05)),
    _Variant('punch', 'Punch', const ['punchy', 'colorful', 'saturated'], (r) => r.mod(dVib: 0.18, satMul: 1.08)),
    _Variant('grain', 'Grain', const ['grain', 'film', 'texture'], (r) => r.mod(dGrain: 0.25, dVig: 0.15)),
    _Variant('muted', 'Muted', const ['muted', 'calm', 'desaturated'], (r) => r.mod(satMul: 0.75, dVib: -0.1)),
  ];

  /// Category → hand-tuned base grades.
  static const Map<String, List<_Recipe>> _bases = {
    'Portrait': [
      _Recipe('honey_skin', 'Honey Skin', tags: ['skin', 'warm', 'face'], temp: 8, vib: 0.1, sh: 0.15, hi: -0.08, hsl: {'orange': [0, 0.04, 0.08]}),
      _Recipe('velvet', 'Velvet', tags: ['soft', 'skin'], temp: 5, sat: 0.95, con: 0.95, fade: 0.06, sh: 0.1),
      _Recipe('rosewater', 'Rosewater', tags: ['pink', 'skin'], temp: 4, tint: 6, exp: 0.06, sat: 0.96, lift: [0.02, 0, 0.01]),
      _Recipe('studio_key', 'Studio Key', tags: ['clean', 'sharp'], con: 1.1, wh: 0.08, bl: -0.08, sharpen: 0.25),
      _Recipe('daylight', 'Daylight Clean', tags: ['natural', 'clean'], exp: 0.05, vib: 0.08, sh: 0.06),
      _Recipe('cocoa', 'Cocoa', tags: ['warm', 'brown'], temp: 12, con: 1.05, sat: 0.92, gain: [0.02, 0.01, 0]),
      _Recipe('porcelain', 'Porcelain', tags: ['bright', 'skin'], exp: 0.1, con: 0.96, sat: 0.9, hsl: {'orange': [0, -0.08, 0.1], 'red': [0, -0.06, 0]}),
    ],
    'Melanin': [
      _Recipe('bronze', 'Bronze', tags: ['deep skin', 'warm', 'glow'], temp: 10, con: 1.06, sh: 0.22, hi: -0.08, vib: 0.16, hsl: {'orange': [0, 0.08, 0.08]}),
      _Recipe('mahogany', 'Mahogany', tags: ['deep skin', 'rich'], temp: 8, tint: 2, con: 1.1, sh: 0.18, bl: -0.06, hsl: {'red': [0, 0.06, 0.04], 'orange': [0, 0.06, 0.1]}),
      _Recipe('amber_dusk', 'Amber Dusk', tags: ['deep skin', 'golden'], temp: 16, sh: 0.2, vib: 0.12, gain: [0.03, 0.015, -0.02]),
      _Recipe('onyx_silk', 'Onyx Silk', tags: ['deep skin', 'smooth'], con: 1.04, sh: 0.26, hi: -0.12, sat: 0.98, sharpen: 0.1),
      _Recipe('sahel_sun', 'Sahel Sun', tags: ['deep skin', 'sun'], temp: 14, exp: 0.06, sh: 0.16, vib: 0.1, hsl: {'yellow': [0, 0.06, 0]}),
      _Recipe('copper_glow', 'Copper Glow', tags: ['deep skin', 'copper'], temp: 12, tint: 4, sh: 0.2, vib: 0.14, lift: [0.015, 0.005, 0]),
    ],
    'Cinema': [
      _Recipe('marquee', 'Marquee', tags: ['teal', 'orange', 'blockbuster'], temp: 6, con: 1.12, hi: -0.15, sh: 0.1, vib: 0.15, lift: [-0.03, 0.01, 0.05], gain: [0.05, 0.01, -0.05], hsl: {'orange': [0, 0.15, 0], 'blue': [-10, 0.1, 0], 'aqua': [15, 0, 0]}, vig: 0.25),
      _Recipe('afterdark', 'Afterdark', tags: ['night', 'cool'], temp: -14, tint: 4, exp: -0.1, con: 1.18, bl: -0.2, hi: -0.1, sat: 0.9, lift: [0, 0, 0.04], vig: 0.35),
      _Recipe('epic_horizon', 'Epic Horizon', tags: ['epic', 'contrast'], con: 1.22, hi: -0.25, sh: 0.12, wh: 0.1, bl: -0.15, sat: 0.92, vib: 0.1, curve: 0.6, sharpen: 0.2, vig: 0.3),
      _Recipe('steel_city', 'Steel City', tags: ['cool', 'urban', 'desaturated'], temp: -10, sat: 0.7, con: 1.15, lift: [0, 0.01, 0.03], vig: 0.2),
      _Recipe('indie_reel', 'Indie Reel', tags: ['warm', 'indie'], temp: 10, sat: 0.88, fade: 0.1, con: 1.05, grain: 0.12),
      _Recipe('greenroom', 'Greenroom', tags: ['green', 'thriller'], tint: -8, sat: 0.82, con: 1.15, bl: -0.1, lift: [0, 0.02, 0.01], vig: 0.3),
      _Recipe('westbound', 'Westbound', tags: ['western', 'dusty', 'warm'], temp: 22, sat: 0.8, con: 1.1, fade: 0.08, gain: [0.04, 0.02, -0.04], grain: 0.1),
    ],
    'Film': [
      _Recipe('emulsion', 'Emulsion 200', tags: ['film', 'warm'], temp: 6, sat: 0.92, curve: 0.5, fade: 0.06, grain: 0.15, gain: [0.02, 0.01, -0.01]),
      _Recipe('pastel_print', 'Pastel Print', tags: ['film', 'soft'], exp: 0.08, sat: 0.85, matte: 0.06, fade: 0.1, grain: 0.1),
      _Recipe('expired_roll', 'Expired Roll', tags: ['film', 'vintage', 'magenta'], tint: 10, temp: 8, sat: 0.8, fade: 0.18, grain: 0.25, lift: [0.03, 0, 0.02]),
      _Recipe('slide_64', 'Slide 64', tags: ['film', 'saturated'], con: 1.18, sat: 1.15, curve: 0.7, bl: -0.08),
      _Recipe('warm_negative', 'Warm Negative', tags: ['film', 'warm'], temp: 14, con: 1.04, matte: 0.04, grain: 0.14, hsl: {'green': [8, -0.1, 0]}),
      _Recipe('cross_lab', 'Cross Lab', tags: ['film', 'cross process'], tint: -6, con: 1.12, lift: [0, 0.02, 0.05], gain: [0.04, 0.03, -0.05], sat: 1.05),
      _Recipe('cinestock', 'Cinestock', tags: ['film', 'cinematic'], temp: 4, con: 1.08, curve: 0.4, matte: 0.03, grain: 0.18, hsl: {'aqua': [10, 0, 0], 'orange': [0, 0.06, 0]}),
    ],
    'Street': [
      _Recipe('asphalt', 'Asphalt', tags: ['urban', 'gritty'], sat: 0.75, con: 1.2, bl: -0.12, sharpen: 0.3, vig: 0.2),
      _Recipe('concrete_pop', 'Concrete Pop', tags: ['urban', 'color pop'], sat: 0.85, vib: 0.25, con: 1.1),
      _Recipe('metro_teal', 'Metro Teal', tags: ['urban', 'teal'], temp: -6, con: 1.1, lift: [-0.02, 0.01, 0.03], hsl: {'aqua': [10, 0.1, 0], 'yellow': [-10, 0, 0]}),
      _Recipe('neon_puddle', 'Neon Puddle', tags: ['urban', 'night', 'neon'], temp: -8, tint: 8, con: 1.15, vib: 0.2, bl: -0.1, hsl: {'magenta': [0, 0.2, 0], 'blue': [0, 0.15, 0]}),
      _Recipe('grit', 'Grit', tags: ['gritty', 'contrast'], con: 1.28, sat: 0.8, grain: 0.3, sharpen: 0.35, vig: 0.3),
      _Recipe('rooftop', 'Rooftop', tags: ['urban', 'sky'], exp: 0.05, hi: -0.2, vib: 0.12, hsl: {'blue': [0, 0.12, -0.08]}),
    ],
    'Nature': [
      _Recipe('canopy', 'Canopy', tags: ['green', 'forest'], vib: 0.15, hsl: {'green': [-8, 0.15, 0], 'yellow': [-6, 0.1, 0]}, con: 1.06),
      _Recipe('highland', 'Highland', tags: ['mountain', 'cool'], temp: -6, con: 1.1, hi: -0.18, hsl: {'green': [10, -0.05, -0.05], 'blue': [0, 0.1, -0.05]}),
      _Recipe('savanna', 'Savanna', tags: ['warm', 'grass', 'africa'], temp: 14, sat: 0.95, hsl: {'yellow': [-8, 0.12, 0.04], 'green': [-15, -0.1, 0]}, gain: [0.03, 0.015, -0.03]),
      _Recipe('baobab', 'Baobab', tags: ['earthy', 'africa'], temp: 10, sat: 0.88, con: 1.08, fade: 0.05, hsl: {'orange': [0, 0.1, 0], 'green': [-10, -0.15, 0]}),
      _Recipe('fern', 'Fern', tags: ['green', 'fresh'], tint: -4, vib: 0.2, exp: 0.05, hsl: {'green': [0, 0.2, 0.05]}),
      _Recipe('monsoon', 'Monsoon', tags: ['rain', 'moody', 'green'], temp: -8, sat: 0.8, con: 1.08, hsl: {'green': [15, -0.1, -0.05]}, fade: 0.06),
    ],
    'Ocean': [
      _Recipe('lagoon', 'Lagoon', tags: ['blue', 'water', 'beach'], temp: -4, vib: 0.18, hsl: {'aqua': [-6, 0.2, 0.04], 'blue': [0, 0.12, 0]}),
      _Recipe('coral', 'Coral', tags: ['warm', 'beach'], temp: 8, tint: 4, vib: 0.15, hsl: {'orange': [0, 0.1, 0.04], 'aqua': [0, 0.1, 0]}),
      _Recipe('tidepool', 'Tidepool', tags: ['teal', 'water'], temp: -10, tint: -3, con: 1.06, hsl: {'aqua': [8, 0.15, 0], 'green': [20, 0, 0]}),
      _Recipe('deep_reef', 'Deep Reef', tags: ['blue', 'deep'], temp: -12, exp: -0.06, con: 1.12, bl: -0.08, hsl: {'blue': [0, 0.2, -0.08]}),
      _Recipe('zanzibar', 'Zanzibar', tags: ['beach', 'tropical', 'africa'], temp: 6, vib: 0.22, exp: 0.06, hsl: {'aqua': [-4, 0.2, 0.06], 'yellow': [0, 0.08, 0.04]}),
      _Recipe('sea_glass', 'Sea Glass', tags: ['pastel', 'water'], temp: -4, sat: 0.85, matte: 0.05, exp: 0.08, hsl: {'aqua': [0, 0.1, 0.08]}),
    ],
    'Golden Hour': [
      _Recipe('sunset_strip', 'Sunset Strip', tags: ['sunset', 'warm', 'orange'], temp: 20, tint: 4, vib: 0.15, hi: -0.1, gain: [0.04, 0.01, -0.03]),
      _Recipe('ember', 'Ember', tags: ['warm', 'red'], temp: 24, tint: 6, con: 1.08, sat: 1.05, hsl: {'red': [0, 0.08, 0]}, vig: 0.2),
      _Recipe('marigold', 'Marigold', tags: ['yellow', 'warm'], temp: 18, hsl: {'yellow': [-6, 0.14, 0.05], 'orange': [0, 0.08, 0]}, exp: 0.04),
      _Recipe('last_light', 'Last Light', tags: ['sunset', 'soft'], temp: 16, fade: 0.08, hi: -0.18, sh: 0.1, sat: 0.95),
      _Recipe('kilima_gold', 'Kilima Gold', tags: ['mountain', 'golden', 'africa'], temp: 18, con: 1.06, hi: -0.15, gain: [0.03, 0.02, -0.03], hsl: {'blue': [0, -0.05, -0.05]}),
      _Recipe('dune', 'Dune', tags: ['desert', 'sand'], temp: 22, sat: 0.85, con: 1.05, hsl: {'orange': [-4, 0.08, 0.06], 'blue': [0, -0.15, 0]}),
    ],
    'Night': [
      _Recipe('midnight', 'Midnight', tags: ['night', 'blue'], temp: -16, exp: -0.05, con: 1.12, bl: -0.12, lift: [0, 0, 0.03]),
      _Recipe('city_lights', 'City Lights', tags: ['night', 'warm lights'], temp: -6, con: 1.1, hsl: {'orange': [0, 0.15, 0.06], 'blue': [0, 0.1, 0]}, vib: 0.1),
      _Recipe('moonlit', 'Moonlit', tags: ['night', 'silver'], temp: -12, sat: 0.6, con: 1.06, exp: 0.04),
      _Recipe('afterglow', 'Afterglow', tags: ['night', 'purple'], tint: 10, temp: -4, vib: 0.15, hsl: {'purple': [0, 0.15, 0], 'magenta': [0, 0.1, 0]}),
      _Recipe('lantern', 'Lantern', tags: ['night', 'warm'], temp: 14, exp: 0.06, sh: 0.15, hi: -0.1, vig: 0.25),
      _Recipe('starlit', 'Starlit', tags: ['night', 'clean'], sh: 0.18, bl: -0.1, con: 1.08, temp: -8, sharpen: 0.15),
    ],
    'Food': [
      _Recipe('fresh_market', 'Fresh Market', tags: ['food', 'fresh'], vib: 0.2, exp: 0.05, sharpen: 0.2, hsl: {'green': [0, 0.12, 0], 'red': [0, 0.08, 0]}),
      _Recipe('spice', 'Spice', tags: ['food', 'warm'], temp: 10, sat: 1.08, con: 1.06, hsl: {'orange': [0, 0.12, 0], 'red': [0, 0.1, 0]}),
      _Recipe('brunch', 'Brunch', tags: ['food', 'bright'], exp: 0.12, temp: 6, sh: 0.12, con: 0.98),
      _Recipe('citrus', 'Citrus', tags: ['food', 'yellow'], temp: 6, tint: -3, vib: 0.18, hsl: {'yellow': [0, 0.15, 0.04]}),
      _Recipe('grill', 'Grill', tags: ['food', 'smoky'], temp: 14, con: 1.12, bl: -0.08, sat: 1.02, vig: 0.25),
      _Recipe('sweet_tooth', 'Sweet Tooth', tags: ['food', 'pastel', 'dessert'], tint: 5, exp: 0.1, sat: 0.95, matte: 0.04, hsl: {'magenta': [0, 0.08, 0.04]}),
    ],
    'Retro': [
      _Recipe('instant_77', 'Instant 77', tags: ['retro', 'instant'], temp: 10, tint: 4, sat: 0.85, matte: 0.08, fade: 0.1, lift: [0, 0.01, 0.03], vig: 0.2),
      _Recipe('cassette', 'Cassette', tags: ['retro', 'warm'], temp: 16, sat: 0.78, fade: 0.14, grain: 0.2),
      _Recipe('disco_fade', 'Disco Fade', tags: ['retro', 'magenta'], tint: 10, sat: 0.9, fade: 0.12, hsl: {'magenta': [0, 0.15, 0], 'purple': [0, 0.1, 0]}),
      _Recipe('arcade', 'Arcade', tags: ['retro', 'neon'], con: 1.15, vib: 0.25, tint: 6, hsl: {'blue': [0, 0.2, 0]}),
      _Recipe('super_eight', 'Super Eight', tags: ['retro', 'film'], temp: 12, sat: 0.85, grain: 0.35, vig: 0.4, fade: 0.08),
      _Recipe('postcard', 'Postcard', tags: ['retro', 'travel'], temp: 8, sat: 1.05, matte: 0.05, hsl: {'blue': [-6, 0.1, 0], 'aqua': [0, 0.1, 0]}),
    ],
    'Mono': [
      _Recipe('charcoal', 'Charcoal', tags: ['black and white', 'bw'], sat: 0, con: 1.2, bl: -0.12),
      _Recipe('ink', 'Ink', tags: ['black and white', 'bw', 'contrast'], sat: 0, con: 1.45, bl: -0.25, wh: 0.15, vig: 0.4),
      _Recipe('silver_screen', 'Silver Screen', tags: ['black and white', 'bw', 'cinema'], sat: 0, con: 1.1, curve: 0.6, grain: 0.15),
      _Recipe('selenium', 'Selenium', tags: ['toned', 'bw'], sat: 0.12, temp: -20, con: 1.15),
      _Recipe('paper_white', 'Paper White', tags: ['black and white', 'bw', 'soft'], sat: 0, exp: 0.1, con: 0.9, matte: 0.05),
      _Recipe('sepia_story', 'Sepia Story', tags: ['sepia', 'toned', 'vintage'], sat: 0.18, temp: 40, fade: 0.1, grain: 0.15),
    ],
    'Pastel': [
      _Recipe('cotton_candy', 'Cotton Candy', tags: ['pastel', 'pink'], tint: 8, exp: 0.1, sat: 0.8, matte: 0.06, hsl: {'magenta': [0, 0.1, 0.06]}),
      _Recipe('mint', 'Mint', tags: ['pastel', 'green'], tint: -6, exp: 0.08, sat: 0.82, matte: 0.05, hsl: {'green': [10, 0.05, 0.06]}),
      _Recipe('lavender_haze', 'Lavender Haze', tags: ['pastel', 'purple'], tint: 8, temp: -6, sat: 0.8, fade: 0.1, hsl: {'purple': [0, 0.1, 0.05]}),
      _Recipe('peach_cream', 'Peach Cream', tags: ['pastel', 'peach'], temp: 10, tint: 5, exp: 0.08, sat: 0.88, matte: 0.05),
      _Recipe('sky_pastel', 'Sky Pastel', tags: ['pastel', 'blue'], temp: -8, exp: 0.1, sat: 0.85, matte: 0.06, hsl: {'blue': [0, 0, 0.08]}),
      _Recipe('blush', 'Blush', tags: ['pastel', 'pink', 'skin'], tint: 6, temp: 4, exp: 0.06, sat: 0.9, lift: [0.02, 0, 0.015]),
    ],
    'Neon': [
      _Recipe('cyberglow', 'Cyberglow', tags: ['neon', 'cyan', 'magenta'], con: 1.2, vib: 0.3, tint: 8, lift: [0, 0.01, 0.05], hsl: {'magenta': [0, 0.2, 0], 'aqua': [0, 0.2, 0]}),
      _Recipe('ultraviolet', 'Ultraviolet', tags: ['neon', 'purple'], tint: 14, temp: -10, con: 1.15, hsl: {'purple': [0, 0.25, 0], 'blue': [10, 0.15, 0]}),
      _Recipe('electric_lime', 'Electric Lime', tags: ['neon', 'green'], tint: -10, vib: 0.3, con: 1.12, hsl: {'green': [-10, 0.25, 0.05], 'yellow': [-10, 0.2, 0]}),
      _Recipe('vapor', 'Vapor', tags: ['neon', 'pastel', 'vaporwave'], tint: 10, temp: -6, matte: 0.06, sat: 1.1, hsl: {'magenta': [0, 0.15, 0.05], 'aqua': [0, 0.15, 0.05]}),
      _Recipe('laser_pink', 'Laser Pink', tags: ['neon', 'pink'], tint: 12, con: 1.15, vib: 0.2, hsl: {'magenta': [0, 0.25, 0], 'red': [10, 0.1, 0]}),
      _Recipe('synth', 'Synth', tags: ['neon', 'retro'], tint: 8, con: 1.18, bl: -0.12, lift: [0.01, 0, 0.05], gain: [0.04, 0, 0.02], vig: 0.3),
    ],
    'Moody': [
      _Recipe('overcast', 'Overcast', tags: ['moody', 'grey'], sat: 0.7, con: 0.96, fade: 0.08, temp: -6),
      _Recipe('ashen', 'Ashen', tags: ['moody', 'desaturated'], sat: 0.55, con: 1.1, bl: -0.08, lift: [0, 0.005, 0.015]),
      _Recipe('forest_mist', 'Forest Mist', tags: ['moody', 'green'], sat: 0.75, exp: -0.06, hsl: {'green': [20, -0.3, 0], 'blue': [0, -0.2, 0]}, fade: 0.1, vig: 0.3),
      _Recipe('storm', 'Storm', tags: ['moody', 'dark', 'blue'], temp: -12, exp: -0.12, con: 1.15, hi: -0.3, sat: 0.8, vig: 0.35),
      _Recipe('hush', 'Hush', tags: ['moody', 'soft'], sat: 0.8, con: 0.92, exp: -0.04, matte: 0.06),
      _Recipe('velvet_dark', 'Velvet Dark', tags: ['moody', 'rich'], exp: -0.1, con: 1.12, bl: -0.15, temp: 6, sat: 0.9, vig: 0.35),
    ],
    'Travel': [
      _Recipe('medina', 'Medina', tags: ['travel', 'warm', 'city'], temp: 14, sat: 0.95, con: 1.06, hsl: {'orange': [0, 0.1, 0.04], 'blue': [-6, 0.08, 0]}),
      _Recipe('safari', 'Safari', tags: ['travel', 'wildlife', 'africa'], temp: 12, con: 1.08, sat: 0.9, hsl: {'yellow': [-6, 0.1, 0], 'green': [-12, -0.1, 0]}, sharpen: 0.2),
      _Recipe('alpine', 'Alpine', tags: ['travel', 'snow', 'cool'], temp: -8, exp: 0.08, con: 1.1, hi: -0.15, hsl: {'blue': [0, 0.12, 0]}),
      _Recipe('island_hop', 'Island Hop', tags: ['travel', 'beach', 'tropical'], vib: 0.22, exp: 0.05, hsl: {'aqua': [0, 0.18, 0.04], 'green': [0, 0.1, 0]}),
      _Recipe('old_town', 'Old Town', tags: ['travel', 'vintage'], temp: 10, sat: 0.82, fade: 0.08, con: 1.04, grain: 0.1),
      _Recipe('desert_road', 'Desert Road', tags: ['travel', 'desert', 'road trip'], temp: 18, con: 1.1, sat: 0.88, hi: -0.12, gain: [0.03, 0.015, -0.03]),
    ],
    'Pop': [
      _Recipe('candy_pop', 'Candy Pop', tags: ['colorful', 'bright'], sat: 1.25, vib: 0.2, con: 1.08, exp: 0.04),
      _Recipe('prism', 'Prism', tags: ['colorful', 'rainbow'], vib: 0.3, con: 1.1, hsl: {'red': [0, 0.1, 0], 'blue': [0, 0.1, 0], 'green': [0, 0.1, 0]}),
      _Recipe('festival', 'Festival', tags: ['colorful', 'party'], sat: 1.2, tint: 4, con: 1.12, vig: 0.15),
      _Recipe('kanga', 'Kanga', tags: ['colorful', 'africa', 'print'], sat: 1.18, vib: 0.15, con: 1.1, temp: 6, hsl: {'yellow': [0, 0.12, 0], 'red': [0, 0.1, 0]}),
      _Recipe('carnival', 'Carnival', tags: ['colorful', 'warm'], sat: 1.22, temp: 8, con: 1.1, hsl: {'magenta': [0, 0.12, 0]}),
      _Recipe('bloom', 'Bloom', tags: ['flowers', 'colorful'], vib: 0.25, exp: 0.06, hsl: {'magenta': [0, 0.15, 0], 'purple': [0, 0.12, 0], 'red': [0, 0.08, 0]}),
    ],
    'Dream': [
      _Recipe('ivory', 'Ivory', tags: ['wedding', 'soft', 'bright'], exp: 0.12, temp: 4, sat: 0.9, con: 0.94, matte: 0.04),
      _Recipe('champagne', 'Champagne', tags: ['wedding', 'golden'], temp: 10, exp: 0.08, sat: 0.92, gain: [0.02, 0.015, -0.01], hi: -0.1),
      _Recipe('veil', 'Veil', tags: ['wedding', 'airy'], exp: 0.14, con: 0.9, fade: 0.08, sat: 0.88),
      _Recipe('petal', 'Petal', tags: ['soft', 'pink'], tint: 5, exp: 0.08, sat: 0.94, hsl: {'red': [0, -0.04, 0.05], 'magenta': [0, 0.06, 0.05]}),
      _Recipe('halo', 'Halo', tags: ['glow', 'bright'], exp: 0.1, hi: -0.2, sh: 0.15, con: 0.95, sat: 1.02),
      _Recipe('silk', 'Silk', tags: ['soft', 'smooth'], con: 0.92, sh: 0.12, sat: 0.95, matte: 0.03, temp: 3),
    ],
  };

  static List<String> get categories => _bases.keys.toList(growable: false);

  static List<OneovaFilter>? _all;
  static Map<String, OneovaFilter>? _byId;

  /// Every filter, in category order (base, then its variants).
  static List<OneovaFilter> get all => _all ??= _generate();

  static Map<String, OneovaFilter> get _index => _byId ??= {for (final f in all) f.id: f};

  static List<OneovaFilter> _generate() {
    final out = <OneovaFilter>[];
    for (final entry in _bases.entries) {
      for (final base in entry.value) {
        for (final v in _variants) {
          final id = v.key.isEmpty ? '$prefix${base.key}' : '$prefix${base.key}_${v.key}';
          final label = v.label.isEmpty ? base.name : '${base.name} ${v.label}';
          final recipe = v.apply(base);
          out.add(OneovaFilter(
            id: id,
            name: label,
            category: entry.key,
            base: base.name,
            variant: v.label,
            tags: [...base.tags, ...v.tags],
            look: recipe.build(id, label, entry.key),
          ));
        }
      }
    }
    return List.unmodifiable(out);
  }

  static bool isFilterId(String id) => id.startsWith(prefix);

  static OneovaFilter? byId(String id) => _index[id];

  static List<OneovaFilter> inCategory(String category) => all.where((f) => f.category == category).toList();

  /// Every word in [query] must start a word of the name, category, variant
  /// or tags ("ink" finds Ink, not pink). Name matches come first.
  static List<OneovaFilter> search(String query, {Iterable<OneovaFilter>? within}) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final pool = within ?? all;
    if (words.isEmpty) return pool.toList();
    final split = RegExp(r'[^a-z0-9]+');
    final hits = <(int, int, OneovaFilter)>[];
    var i = 0;
    for (final f in pool) {
      final tokens = f.searchText.split(split);
      if (words.every((w) => tokens.any((t) => t.startsWith(w)))) {
        final name = f.name.toLowerCase();
        final nameTokens = name.split(split);
        final rank = name.startsWith(words.first)
            ? 0
            : words.every((w) => nameTokens.any((t) => t.startsWith(w)))
                ? 1
                : 2;
        hits.add((rank, i, f));
      }
      i++;
    }
    hits.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    return [for (final h in hits) h.$3];
  }
}
