import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/studio_project.dart';

/// An original Oneova text template: typography + in/out/loop animation.
/// Everything is drawn by `StudioTextPainter` and moved by
/// `StudioTextAnimator`, so a template exports exactly as it previews.
class StudioTextTemplate {
  final String id;
  final String name;
  final String category;
  final String sample;
  final StudioTypeStyle type;
  final StudioTextAnim anim;

  /// Font size as a fraction of the canvas width.
  final double size;
  final List<String> tags;

  const StudioTextTemplate(
    this.id,
    this.name,
    this.category,
    this.sample,
    this.type,
    this.anim, {
    this.size = 0.075,
    this.tags = const [],
  });

  bool get forCaptions => category == 'Captions';

  /// Applies this template to [t], keeping its text, timing and position.
  StudioText applyTo(StudioText t) => t.copyWith(type: type, anim: anim, size: t.isSticker ? t.size : size, templateId: id);

  bool matches(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return true;
    return name.toLowerCase().contains(s) ||
        category.toLowerCase().contains(s) ||
        type.font.toLowerCase().contains(s) ||
        tags.any((t) => t.contains(s)) ||
        anim.inId.contains(s) ||
        anim.loopId.contains(s);
  }
}

// Template palette (content colors of the templates themselves).
const _white = 0xFFFFFFFF;
const _black = 0xFF000000;
const _ink = 0xFF0B0B0F;
const _blue = 0xFF0C4FA8;
const _sky = 0xFF3D8BFF;
const _pink = 0xFFFF2D87;
const _yellow = 0xFFFFD60A;
const _cyan = 0xFF00E5FF;
const _lime = 0xFFB6FF3B;
const _orange = 0xFFFF8A00;
const _purple = 0xFF8B5CF6;
const _gold = 0xFFFFC857;
const _cream = 0xFFFFF4E0;
const _mint = 0xFF5EF2C2;
const _coral = 0xFFFF6B6B;
const _shadow = 0x8C000000;

const _none = StudioTextAnim();

StudioTextAnim _a(String i, [String o = 'fade', String l = 'none', int inMs = 500, int outMs = 400, int loopMs = 1200]) =>
    StudioTextAnim(inId: i, outId: o, loopId: l, inMs: inMs, outMs: outMs, loopMs: loopMs);

class StudioTextTemplates {
  StudioTextTemplates._();

  static const categories = [
    'Trending',
    'Titles',
    'Social',
    'Neon',
    'Bold',
    'Minimal',
    'Elegant',
    'Retro',
    'Handwritten',
    'Kinetic',
    'Lower thirds',
    'Captions',
    'Celebrate',
  ];

  static final List<StudioTextTemplate> all = [
    // ── Trending ─────────────────────────────────────────────────────────
    StudioTextTemplate('tr_punch', 'Punch', 'Trending', 'WAIT FOR IT',
        const StudioTypeStyle(font: 'Anton', weight: 400, uppercase: true, stroke: 0.12, shadowColor: _black, shadowBlur: 0.02, shadowDx: 0.05, shadowDy: 0.07),
        _a('pop', 'pop', 'pulse', 420, 300, 900), size: 0.11, tags: ['hook', 'viral']),
    StudioTextTemplate('tr_sticker', 'Sticker label', 'Trending', 'new drop',
        const StudioTypeStyle(font: 'Poppins', weight: 800, color: _ink, bg: StudioTextBg.pill, bgColor: _yellow, shadowBlur: 0),
        _a('elastic', 'pop', 'wiggle', 700, 300, 1600), size: 0.07, tags: ['label', 'badge']),
    StudioTextTemplate('tr_hook', 'Hook line', 'Trending', 'Nobody talks about this',
        const StudioTypeStyle(font: 'Montserrat', weight: 900, bg: StudioTextBg.perLine, bgColor: _white, color: _ink, shadowBlur: 0),
        _a('words', 'fade', 'none', 900), size: 0.068, tags: ['story', 'hook']),
    StudioTextTemplate('tr_glitch', 'Glitchy', 'Trending', 'LOADING...',
        const StudioTypeStyle(font: 'Space Mono', weight: 700, uppercase: true, color: _cyan, shadowColor: _pink, shadowBlur: 0.01, shadowDx: 0.06),
        _a('typewriter', 'typewriter', 'shake', 900, 500, 500), size: 0.07, tags: ['tech', 'glitch']),
    StudioTextTemplate('tr_pov', 'POV', 'Trending', 'POV: you finally did it',
        const StudioTypeStyle(font: 'Inter', weight: 800, bg: StudioTextBg.box, bgColor: 0xE6000000, shadowBlur: 0),
        _a('rise', 'sink'), size: 0.06, tags: ['pov', 'story']),
    StudioTextTemplate('tr_wow', 'Big reveal', 'Trending', 'WOW',
        const StudioTypeStyle(font: 'Bungee', weight: 400, color: _yellow, color2: _orange, stroke: 0.1, strokeColor: _ink, shadowColor: _ink, shadowBlur: 0.01, shadowDy: 0.1),
        _a('zoom_out', 'zoom_in', 'heartbeat', 500, 350, 1000), size: 0.16, tags: ['reaction']),
    StudioTextTemplate('tr_link', 'Link in bio', 'Trending', 'link in bio',
        const StudioTypeStyle(font: 'DM Sans', weight: 700, color: _white, bg: StudioTextBg.pill, bgColor: _pink, shadowBlur: 0),
        _a('slide_up', 'slide_down', 'bounce', 450, 350, 1000), size: 0.06, tags: ['cta', 'bio']),
    StudioTextTemplate('tr_part', 'Part 2', 'Trending', 'PART 2',
        const StudioTypeStyle(font: 'Archivo Black', weight: 400, uppercase: true, stroke: 0.14, strokeColor: _blue, shadowBlur: 0),
        _a('whip', 'slide_left', 'none', 500), size: 0.1, tags: ['series']),
    StudioTextTemplate('tr_wait', 'Countdown', 'Trending', '3 . 2 . 1',
        const StudioTypeStyle(font: 'Rubik Mono One', weight: 400, color: _lime, shadowColor: _black, shadowBlur: 0.3),
        _a('words', 'fade', 'pulse', 1200, 300, 600), size: 0.085, tags: ['timer']),

    // ── Titles ───────────────────────────────────────────────────────────
    StudioTextTemplate('ti_cinema', 'Cinema', 'Titles', 'THE JOURNEY',
        const StudioTypeStyle(font: 'Cinzel', weight: 700, uppercase: true, letterSpacing: 0.25, color: _cream, shadowBlur: 0.4, shadowColor: _shadow),
        _a('fade', 'fade', 'breathe', 1400, 900, 4000), size: 0.075, tags: ['film', 'intro']),
    StudioTextTemplate('ti_block', 'Block title', 'Titles', 'CHAPTER ONE',
        const StudioTypeStyle(font: 'Bebas Neue', weight: 400, uppercase: true, letterSpacing: 0.08, color: _ink, bg: StudioTextBg.bar, bgColor: _white, shadowBlur: 0),
        _a('unfold', 'fold', 'none', 500, 400), size: 0.1, tags: ['chapter']),
    StudioTextTemplate('ti_epic', 'Epic', 'Titles', 'LEGENDARY',
        const StudioTypeStyle(font: 'Cinzel Decorative', weight: 700, uppercase: true, color: _gold, color2: _orange, shadowColor: _black, shadowBlur: 0.5),
        _a('zoom_out', 'fade', 'breathe', 1200, 700, 3000), size: 0.085, tags: ['trailer', 'gold']),
    StudioTextTemplate('ti_slab', 'Slab', 'Titles', 'Built Different',
        const StudioTypeStyle(font: 'Alfa Slab One', weight: 400, color: _white, stroke: 0.08, strokeColor: _blue, shadowColor: _blue, shadowBlur: 0.01, shadowDx: 0.06, shadowDy: 0.06),
        _a('drop', 'sink', 'none', 700), size: 0.09, tags: ['sport']),
    StudioTextTemplate('ti_split', 'Wide', 'Titles', 'S U M M E R',
        const StudioTypeStyle(font: 'Syne', weight: 800, uppercase: true, letterSpacing: 0.4, color: _white, shadowBlur: 0.25),
        _a('stretch', 'stretch', 'none', 700, 500), size: 0.07, tags: ['season']),
    StudioTextTemplate('ti_tall', 'Tall', 'Titles', 'AFTER DARK',
        const StudioTypeStyle(font: 'Big Shoulders', weight: 900, uppercase: true, letterSpacing: 0.04, color: _white, shadowBlur: 0.3),
        _a('slide_up', 'slide_up', 'none', 600, 400), size: 0.12, tags: ['night']),
    StudioTextTemplate('ti_orbit', 'Orbit', 'Titles', 'LAUNCH DAY',
        const StudioTypeStyle(font: 'Orbitron', weight: 800, uppercase: true, letterSpacing: 0.12, color: _sky, color2: _white, glow: true, shadowColor: _sky, shadowBlur: 0.25),
        _a('spin', 'spin', 'float', 800, 600, 2400), size: 0.075, tags: ['space', 'tech']),
    StudioTextTemplate('ti_unbound', 'Unbound', 'Titles', 'Make it yours',
        const StudioTypeStyle(font: 'Unbounded', weight: 800, color: _white, color2: _mint, shadowBlur: 0.2),
        _a('tilt', 'fall', 'none', 600, 500), size: 0.075, tags: ['modern']),
    StudioTextTemplate('ti_frame', 'Framed', 'Titles', 'EPISODE 04',
        const StudioTypeStyle(font: 'Oswald', weight: 600, uppercase: true, letterSpacing: 0.2, color: _white, bg: StudioTextBg.frame, bgColor: _white, shadowBlur: 0),
        _a('zoom_in', 'zoom_out', 'none', 600, 400), size: 0.06, tags: ['episode']),
    StudioTextTemplate('ti_mega', 'Mega', 'Titles', 'GAME ON',
        const StudioTypeStyle(font: 'Titan One', weight: 400, uppercase: true, color: _lime, stroke: 0.12, strokeColor: _ink, shadowColor: _ink, shadowBlur: 0.01, shadowDy: 0.12),
        _a('elastic', 'pop', 'jelly', 800, 300, 1400), size: 0.12, tags: ['gaming']),

    // ── Social ───────────────────────────────────────────────────────────
    StudioTextTemplate('so_follow', 'Follow me', 'Social', 'Follow for part 2',
        const StudioTypeStyle(font: 'Poppins', weight: 700, color: _white, bg: StudioTextBg.pill, bgColor: _blue, shadowBlur: 0),
        _a('pop', 'pop', 'pulse', 450, 300, 1100), size: 0.058, tags: ['cta', 'follow']),
    StudioTextTemplate('so_like', 'Double tap', 'Social', 'double tap if you agree',
        const StudioTypeStyle(font: 'Nunito', weight: 900, color: _pink, bg: StudioTextBg.pill, bgColor: _white, shadowBlur: 0),
        _a('elastic', 'fade', 'heartbeat', 700, 300, 1000), size: 0.055, tags: ['like']),
    StudioTextTemplate('so_comment', 'Comment bait', 'Social', 'Comment your city',
        const StudioTypeStyle(font: 'Lexend', weight: 700, color: _ink, bg: StudioTextBg.box, bgColor: _white, shadowBlur: 0),
        _a('slide_right', 'slide_left'), size: 0.058, tags: ['comment']),
    StudioTextTemplate('so_tag', 'Tag a friend', 'Social', 'tag someone who needs this',
        const StudioTypeStyle(font: 'Quicksand', weight: 700, color: _white, bg: StudioTextBg.perLine, bgColor: _purple, shadowBlur: 0),
        _a('words', 'fade', 'none', 1000), size: 0.056, tags: ['tag']),
    StudioTextTemplate('so_save', 'Save this', 'Social', 'SAVE THIS',
        const StudioTypeStyle(font: 'Archivo Black', weight: 400, uppercase: true, color: _yellow, stroke: 0.1, strokeColor: _ink, shadowBlur: 0),
        _a('drop', 'fade', 'wiggle', 700, 300, 1500), size: 0.09, tags: ['save']),
    StudioTextTemplate('so_handle', 'Handle', 'Social', '@yourname',
        const StudioTypeStyle(font: 'Inter', weight: 700, color: _white, shadowColor: _shadow, shadowBlur: 0.3),
        _a('fade', 'fade', 'none', 600), size: 0.05, tags: ['username']),
    StudioTextTemplate('so_live', 'Going live', 'Social', 'LIVE TONIGHT 8PM',
        const StudioTypeStyle(font: 'Montserrat', weight: 900, uppercase: true, color: _white, bg: StudioTextBg.box, bgColor: _pink, shadowBlur: 0),
        _a('flip_x', 'flip_x', 'flash', 500, 400, 1600), size: 0.06, tags: ['live']),
    StudioTextTemplate('so_question', 'Ask me', 'Social', 'Ask me anything',
        const StudioTypeStyle(font: 'Fredoka', weight: 600, color: _ink, bg: StudioTextBg.pill, bgColor: _mint, shadowBlur: 0),
        _a('pop', 'pop', 'float', 450, 300, 2000), size: 0.06, tags: ['qa']),

    // ── Neon ─────────────────────────────────────────────────────────────
    StudioTextTemplate('ne_pink', 'Neon pink', 'Neon', 'open late',
        const StudioTypeStyle(font: 'Monoton', weight: 400, color: _white, glow: true, shadowColor: _pink, shadowBlur: 0.3),
        _a('fade', 'fade', 'flash', 800, 500, 2600), size: 0.08, tags: ['glow', 'night']),
    StudioTextTemplate('ne_blue', 'Neon blue', 'Neon', 'night drive',
        const StudioTypeStyle(font: 'Audiowide', weight: 400, color: _white, glow: true, shadowColor: _sky, shadowBlur: 0.3),
        _a('fade', 'fade', 'breathe', 800, 500, 2400), size: 0.075, tags: ['glow']),
    StudioTextTemplate('ne_lime', 'Acid', 'Neon', 'RAVE',
        const StudioTypeStyle(font: 'Righteous', weight: 400, uppercase: true, color: _lime, glow: true, shadowColor: _lime, shadowBlur: 0.25),
        _a('zoom_in', 'zoom_out', 'pulse', 400, 300, 500), size: 0.12, tags: ['party']),
    StudioTextTemplate('ne_tube', 'Tube', 'Neon', 'Good vibes only',
        const StudioTypeStyle(font: 'Kaushan Script', weight: 400, color: _cream, glow: true, shadowColor: _orange, shadowBlur: 0.3),
        _a('typewriter', 'fade', 'breathe', 1200, 500, 3000), size: 0.08, tags: ['vibes']),
    StudioTextTemplate('ne_cyber', 'Cyber', 'Neon', 'SYSTEM ONLINE',
        const StudioTypeStyle(font: 'Orbitron', weight: 700, uppercase: true, letterSpacing: 0.15, color: _cyan, glow: true, shadowColor: _cyan, shadowBlur: 0.2),
        _a('typewriter', 'typewriter', 'shake', 900, 600, 400), size: 0.06, tags: ['tech']),
    StudioTextTemplate('ne_violet', 'Violet', 'Neon', 'dream state',
        const StudioTypeStyle(font: 'Comfortaa', weight: 700, color: _white, glow: true, shadowColor: _purple, shadowBlur: 0.35),
        _a('rise', 'sink', 'float', 900, 600, 3000), size: 0.075, tags: ['dreamy']),
    StudioTextTemplate('ne_sign', 'Sign', 'Neon', 'OPEN',
        const StudioTypeStyle(font: 'Bungee Outline', weight: 400, uppercase: true, color: _pink, glow: true, shadowColor: _pink, shadowBlur: 0.25, bg: StudioTextBg.frame, bgColor: _pink),
        _a('fade', 'fade', 'blink', 300, 300, 1800), size: 0.1, tags: ['shop']),
    StudioTextTemplate('ne_mint', 'Mint glow', 'Neon', 'fresh',
        const StudioTypeStyle(font: 'Pacifico', weight: 400, color: _white, glow: true, shadowColor: _mint, shadowBlur: 0.3),
        _a('pop', 'fade', 'breathe', 600, 500, 2400), size: 0.09, tags: ['fresh']),

    // ── Bold ─────────────────────────────────────────────────────────────
    StudioTextTemplate('bo_impact', 'Impact', 'Bold', 'NO EXCUSES',
        const StudioTypeStyle(font: 'Anton', weight: 400, uppercase: true, color: _white, stroke: 0.08, strokeColor: _ink, shadowBlur: 0),
        _a('zoom_out', 'zoom_in', 'none', 350, 300), size: 0.12, tags: ['gym', 'motivation']),
    StudioTextTemplate('bo_yellow', 'Highlighter', 'Bold', 'READ THIS',
        const StudioTypeStyle(font: 'Archivo Black', weight: 400, uppercase: true, color: _ink, bg: StudioTextBg.perLine, bgColor: _yellow, shadowBlur: 0),
        _a('slide_right', 'slide_left', 'none', 400, 300), size: 0.08, tags: ['important']),
    StudioTextTemplate('bo_comic', 'Comic', 'Bold', 'BOOM!',
        const StudioTypeStyle(font: 'Bangers', weight: 400, uppercase: true, letterSpacing: 0.05, color: _yellow, color2: _orange, stroke: 0.12, strokeColor: _ink, shadowColor: _ink, shadowBlur: 0.01, shadowDx: 0.08, shadowDy: 0.08),
        _a('elastic', 'pop', 'shake', 700, 300, 300), size: 0.14, tags: ['comic', 'sfx']),
    StudioTextTemplate('bo_stack', 'Stacked', 'Bold', 'BIG\nNEWS',
        const StudioTypeStyle(font: 'Bebas Neue', weight: 400, uppercase: true, lineHeight: 0.92, color: _white, shadowColor: _black, shadowBlur: 0.01, shadowDx: 0.05, shadowDy: 0.05),
        _a('slide_up', 'slide_down', 'none', 500, 400), size: 0.14, tags: ['news']),
    StudioTextTemplate('bo_pink', 'Pink punch', 'Bold', 'GIRL BOSS',
        const StudioTypeStyle(font: 'Lilita One', weight: 400, uppercase: true, color: _white, stroke: 0.14, strokeColor: _pink, shadowBlur: 0),
        _a('pop', 'pop', 'pulse', 450, 300, 900), size: 0.11, tags: ['pink']),
    StudioTextTemplate('bo_blue', 'Blue block', 'Bold', 'LEVEL UP',
        const StudioTypeStyle(font: 'Russo One', weight: 400, uppercase: true, color: _white, bg: StudioTextBg.box, bgColor: _blue, shadowBlur: 0),
        _a('flip_y', 'flip_y', 'none', 500, 400), size: 0.085, tags: ['brand']),
    StudioTextTemplate('bo_shadow', 'Long shadow', 'Bold', 'STAY HUNGRY',
        const StudioTypeStyle(font: 'Black Ops One', weight: 400, uppercase: true, color: _cream, shadowColor: _coral, shadowBlur: 0.01, shadowDx: 0.1, shadowDy: 0.1),
        _a('whip', 'slide_right', 'none', 600, 400), size: 0.095, tags: ['grind']),
    StudioTextTemplate('bo_luck', 'Lucky', 'Bold', 'JACKPOT',
        const StudioTypeStyle(font: 'Luckiest Guy', weight: 400, uppercase: true, color: _gold, color2: _orange, stroke: 0.1, strokeColor: _ink, shadowBlur: 0),
        _a('drop', 'pop', 'jelly', 800, 300, 1200), size: 0.12, tags: ['win']),
    StudioTextTemplate('bo_staat', 'Statement', 'Bold', 'FACTS ONLY',
        const StudioTypeStyle(font: 'Staatliches', weight: 400, uppercase: true, letterSpacing: 0.06, color: _white, bg: StudioTextBg.underline, bgColor: _pink, shadowBlur: 0),
        _a('words', 'fade', 'none', 700), size: 0.1, tags: ['opinion']),

    // ── Minimal ──────────────────────────────────────────────────────────
    StudioTextTemplate('mi_clean', 'Clean', 'Minimal', 'less, but better',
        const StudioTypeStyle(font: 'Inter', weight: 500, color: _white, shadowBlur: 0.2),
        _a('fade', 'fade', 'none', 700, 600), size: 0.055, tags: ['simple']),
    StudioTextTemplate('mi_mono', 'Mono', 'Minimal', 'day 01 / 365',
        const StudioTypeStyle(font: 'Space Mono', weight: 400, color: _white, shadowBlur: 0.2, letterSpacing: 0.05),
        _a('typewriter', 'typewriter', 'none', 800, 500), size: 0.05, tags: ['diary', 'code']),
    StudioTextTemplate('mi_thin', 'Thin', 'Minimal', 'quiet morning',
        const StudioTypeStyle(font: 'Raleway', weight: 300, letterSpacing: 0.15, color: _white, shadowBlur: 0.25),
        _a('rise', 'sink', 'none', 900, 700), size: 0.06, tags: ['calm']),
    StudioTextTemplate('mi_tag', 'Tag', 'Minimal', 'Lagos, 6:42 AM',
        const StudioTypeStyle(font: 'DM Sans', weight: 600, color: _ink, bg: StudioTextBg.box, bgColor: 0xEBFFFFFF, shadowBlur: 0),
        _a('slide_right', 'fade'), size: 0.045, tags: ['location', 'time']),
    StudioTextTemplate('mi_line', 'Underlined', 'Minimal', 'note to self',
        const StudioTypeStyle(font: 'Lexend', weight: 500, color: _white, bg: StudioTextBg.underline, bgColor: _sky, shadowBlur: 0),
        _a('fade', 'fade'), size: 0.055, tags: ['note']),
    StudioTextTemplate('mi_left', 'Journal', 'Minimal', 'what I learned\nthis week',
        const StudioTypeStyle(font: 'Josefin Sans', weight: 600, align: 0, color: _white, shadowBlur: 0.2),
        _a('slide_right', 'fade', 'none', 600), size: 0.06, tags: ['journal']),
    StudioTextTemplate('mi_glass', 'Frosted', 'Minimal', 'soft focus',
        const StudioTypeStyle(font: 'Nunito', weight: 700, color: _white, bg: StudioTextBg.pill, bgColor: 0x59FFFFFF, shadowBlur: 0),
        _a('zoom_in', 'zoom_out', 'none', 600), size: 0.055, tags: ['glass']),
    StudioTextTemplate('mi_caps', 'Spaced caps', 'Minimal', 'COLLECTION',
        const StudioTypeStyle(font: 'Montserrat', weight: 500, uppercase: true, letterSpacing: 0.35, color: _white, shadowBlur: 0.15),
        _a('stretch', 'fade', 'none', 800), size: 0.05, tags: ['fashion']),

    // ── Elegant ──────────────────────────────────────────────────────────
    StudioTextTemplate('el_serif', 'Editorial', 'Elegant', 'The Art of Slow Living',
        const StudioTypeStyle(font: 'Playfair Display', weight: 700, italic: true, color: _cream, shadowBlur: 0.25),
        _a('fade', 'fade', 'none', 1000, 700), size: 0.07, tags: ['magazine']),
    StudioTextTemplate('el_vogue', 'Couture', 'Elegant', 'COUTURE',
        const StudioTypeStyle(font: 'Bodoni Moda', weight: 700, uppercase: true, letterSpacing: 0.18, color: _white, shadowBlur: 0.2),
        _a('zoom_out', 'fade', 'none', 1200, 800), size: 0.09, tags: ['fashion']),
    StudioTextTemplate('el_gold', 'Gold script', 'Elegant', 'Forever',
        const StudioTypeStyle(font: 'Great Vibes', weight: 400, color: _gold, color2: _orange, shadowColor: _shadow, shadowBlur: 0.2),
        _a('fade', 'fade', 'breathe', 1200, 800, 3200), size: 0.12, tags: ['wedding', 'love']),
    StudioTextTemplate('el_garamond', 'Classic', 'Elegant', 'Once upon a time',
        const StudioTypeStyle(font: 'Cormorant Garamond', weight: 600, italic: true, color: _white, shadowBlur: 0.25),
        _a('typewriter', 'fade', 'none', 1500, 800), size: 0.075, tags: ['story']),
    StudioTextTemplate('el_marcellus', 'Monument', 'Elegant', 'ROME',
        const StudioTypeStyle(font: 'Marcellus', weight: 400, uppercase: true, letterSpacing: 0.4, color: _cream, shadowBlur: 0.3),
        _a('rise', 'sink', 'none', 1000, 700), size: 0.1, tags: ['travel']),
    StudioTextTemplate('el_yeseva', 'Boutique', 'Elegant', 'Spring Edit',
        const StudioTypeStyle(font: 'Yeseva One', weight: 400, color: _ink, bg: StudioTextBg.box, bgColor: _cream, shadowBlur: 0),
        _a('unfold', 'fold', 'none', 600, 500), size: 0.07, tags: ['shop']),
    StudioTextTemplate('el_dm', 'Display', 'Elegant', 'Golden hour',
        const StudioTypeStyle(font: 'DM Serif Display', weight: 400, color: _white, color2: _gold, shadowBlur: 0.3),
        _a('fade', 'fade', 'float', 1000, 700, 4000), size: 0.09, tags: ['sunset']),
    StudioTextTemplate('el_sacramento', 'Signature', 'Elegant', 'with love',
        const StudioTypeStyle(font: 'Sacramento', weight: 400, color: _white, shadowBlur: 0.25),
        _a('typewriter', 'fade', 'none', 1400, 700), size: 0.11, tags: ['signature']),

    // ── Retro ────────────────────────────────────────────────────────────
    StudioTextTemplate('re_arcade', 'Arcade', 'Retro', 'PRESS START',
        const StudioTypeStyle(font: 'Press Start 2P', weight: 400, uppercase: true, color: _yellow, shadowColor: _pink, shadowBlur: 0.01, shadowDx: 0.12, shadowDy: 0.12),
        _a('typewriter', 'fade', 'blink', 900, 300, 1000), size: 0.045, tags: ['game', 'pixel']),
    StudioTextTemplate('re_vhs', 'VHS', 'Retro', 'REC ●',
        const StudioTypeStyle(font: 'VT323', weight: 400, uppercase: true, color: _white, shadowColor: _cyan, shadowBlur: 0.01, shadowDx: 0.05),
        _a('fade', 'fade', 'flash', 300, 300, 1200), size: 0.09, tags: ['camcorder']),
    StudioTextTemplate('re_70s', 'Groovy', 'Retro', 'far out',
        const StudioTypeStyle(font: 'Shrikhand', weight: 400, color: _orange, stroke: 0.06, strokeColor: _cream, shadowColor: _coral, shadowBlur: 0.01, shadowDx: 0.07, shadowDy: 0.07),
        _a('swing', 'fall', 'swing', 900, 500, 2000), size: 0.1, tags: ['70s']),
    StudioTextTemplate('re_diner', 'Diner', 'Retro', 'Open 24/7',
        const StudioTypeStyle(font: 'Lobster', weight: 400, color: _cream, stroke: 0.08, strokeColor: _coral, shadowBlur: 0),
        _a('pop', 'pop', 'none', 500, 300), size: 0.09, tags: ['food']),
    StudioTextTemplate('re_80s', 'Synth', 'Retro', 'MIAMI 1986',
        const StudioTypeStyle(font: 'Audiowide', weight: 400, uppercase: true, color: _pink, color2: _cyan, shadowColor: _purple, shadowBlur: 0.01, shadowDy: 0.08),
        _a('zoom_out', 'zoom_in', 'float', 800, 500, 2400), size: 0.08, tags: ['80s', 'synthwave']),
    StudioTextTemplate('re_pixel', 'Pixel', 'Retro', 'level complete',
        const StudioTypeStyle(font: 'Silkscreen', weight: 400, color: _lime, bg: StudioTextBg.box, bgColor: _ink, shadowBlur: 0),
        _a('typewriter', 'typewriter', 'none', 800, 500), size: 0.055, tags: ['game']),
    StudioTextTemplate('re_poster', 'Poster', 'Retro', 'SUMMER JAM',
        const StudioTypeStyle(font: 'Rubik Mono One', weight: 400, uppercase: true, color: _coral, stroke: 0.06, strokeColor: _cream, shadowBlur: 0),
        _a('stretch', 'stretch', 'none', 600, 400), size: 0.08, tags: ['music']),
    StudioTextTemplate('re_type', 'Typewriter', 'Retro', 'Dear diary,',
        const StudioTypeStyle(font: 'Courier Prime', weight: 700, color: _ink, bg: StudioTextBg.box, bgColor: _cream, shadowBlur: 0),
        _a('typewriter', 'typewriter', 'none', 1200, 600), size: 0.055, tags: ['letter']),
    StudioTextTemplate('re_major', 'Mono major', 'Retro', 'future archive',
        const StudioTypeStyle(font: 'Major Mono Display', weight: 400, color: _white, shadowBlur: 0.25),
        _a('typewriter', 'fade', 'none', 1000, 500), size: 0.06, tags: ['mono']),

    // ── Handwritten ──────────────────────────────────────────────────────
    StudioTextTemplate('ha_marker', 'Marker', 'Handwritten', 'my fav spot',
        const StudioTypeStyle(font: 'Permanent Marker', weight: 400, color: _white, shadowBlur: 0.2),
        _a('pop', 'fade', 'wiggle', 500, 400, 2000), size: 0.08, tags: ['casual']),
    StudioTextTemplate('ha_note', 'Sticky note', 'Handwritten', 'remember this!',
        const StudioTypeStyle(font: 'Caveat', weight: 700, color: _ink, bg: StudioTextBg.box, bgColor: _yellow, shadowBlur: 0),
        _a('drop', 'fall', 'swing', 700, 500, 2600), size: 0.08, tags: ['note']),
    StudioTextTemplate('ha_dance', 'Dancing', 'Handwritten', 'Sunday mood',
        const StudioTypeStyle(font: 'Dancing Script', weight: 700, color: _white, shadowBlur: 0.25),
        _a('typewriter', 'fade', 'none', 1100, 600), size: 0.09, tags: ['mood']),
    StudioTextTemplate('ha_chalk', 'Chalk', 'Handwritten', 'today\'s menu',
        const StudioTypeStyle(font: 'Shadows Into Light', weight: 400, color: _white, shadowBlur: 0.1),
        _a('typewriter', 'typewriter', 'none', 1000, 600), size: 0.08, tags: ['food', 'menu']),
    StudioTextTemplate('ha_rock', 'Scribble', 'Handwritten', 'no way!!',
        const StudioTypeStyle(font: 'Rock Salt', weight: 400, color: _yellow, shadowBlur: 0.2),
        _a('elastic', 'pop', 'shake', 700, 300, 400), size: 0.07, tags: ['reaction']),
    StudioTextTemplate('ha_amatic', 'Sketchbook', 'Handwritten', 'HANDMADE WITH LOVE',
        const StudioTypeStyle(font: 'Amatic SC', weight: 700, color: _white, shadowBlur: 0.2, letterSpacing: 0.05),
        _a('words', 'fade', 'none', 1000), size: 0.09, tags: ['craft']),
    StudioTextTemplate('ha_satisfy', 'Brush', 'Handwritten', 'Weekend',
        const StudioTypeStyle(font: 'Satisfy', weight: 400, color: _pink, stroke: 0.06, strokeColor: _white, shadowBlur: 0),
        _a('zoom_in', 'fade', 'float', 700, 500, 2600), size: 0.11, tags: ['weekend']),
    StudioTextTemplate('ha_pacifico', 'Surf', 'Handwritten', 'beach day',
        const StudioTypeStyle(font: 'Pacifico', weight: 400, color: _cream, shadowColor: _sky, shadowBlur: 0.01, shadowDx: 0.05, shadowDy: 0.06),
        _a('slide_up', 'sink', 'sway', 700, 500, 2400), size: 0.09, tags: ['summer']),

    // ── Kinetic ──────────────────────────────────────────────────────────
    StudioTextTemplate('ki_bounce', 'Bouncy', 'Kinetic', 'LET\'S GO',
        const StudioTypeStyle(font: 'Fredoka', weight: 700, uppercase: true, color: _white, stroke: 0.1, strokeColor: _blue, shadowBlur: 0),
        _a('drop', 'fall', 'bounce', 800, 500, 700), size: 0.1, tags: ['energy']),
    StudioTextTemplate('ki_spin', 'Spinner', 'Kinetic', 'NEW',
        const StudioTypeStyle(font: 'Righteous', weight: 400, uppercase: true, color: _ink, bg: StudioTextBg.pill, bgColor: _lime, shadowBlur: 0),
        _a('spin', 'spin', 'swing', 700, 500, 1400), size: 0.08, tags: ['badge']),
    StudioTextTemplate('ki_jelly', 'Jelly', 'Kinetic', 'squish',
        const StudioTypeStyle(font: 'Chewy', weight: 400, color: _pink, stroke: 0.1, strokeColor: _white, shadowBlur: 0),
        _a('elastic', 'pop', 'jelly', 900, 300, 900), size: 0.11, tags: ['fun']),
    StudioTextTemplate('ki_whip', 'Whip pan', 'Kinetic', 'NEXT UP',
        const StudioTypeStyle(font: 'Teko', weight: 600, uppercase: true, letterSpacing: 0.05, color: _white, shadowBlur: 0.2),
        _a('whip', 'slide_left', 'none', 450, 300), size: 0.12, tags: ['transition']),
    StudioTextTemplate('ki_heart', 'Heartbeat', 'Kinetic', 'LOVE IT',
        const StudioTypeStyle(font: 'Baloo 2', weight: 800, uppercase: true, color: _white, bg: StudioTextBg.pill, bgColor: _pink, shadowBlur: 0),
        _a('pop', 'pop', 'heartbeat', 500, 300, 1000), size: 0.075, tags: ['love']),
    StudioTextTemplate('ki_shake', 'Shaky', 'Kinetic', 'EARTHQUAKE',
        const StudioTypeStyle(font: 'Anton', weight: 400, uppercase: true, color: _orange, stroke: 0.08, strokeColor: _ink, shadowBlur: 0),
        _a('zoom_out', 'fade', 'shake', 300, 300, 300), size: 0.11, tags: ['impact']),
    StudioTextTemplate('ki_float', 'Floaty', 'Kinetic', 'on cloud nine',
        const StudioTypeStyle(font: 'Comfortaa', weight: 700, color: _white, shadowBlur: 0.3),
        _a('rise', 'slide_up', 'float', 900, 600, 2600), size: 0.07, tags: ['dreamy']),
    StudioTextTemplate('ki_flip', 'Flip card', 'Kinetic', 'BEFORE',
        const StudioTypeStyle(font: 'Oswald', weight: 700, uppercase: true, color: _ink, bg: StudioTextBg.box, bgColor: _white, shadowBlur: 0),
        _a('flip_x', 'flip_x', 'none', 500, 400), size: 0.08, tags: ['before', 'after']),
    StudioTextTemplate('ki_swing', 'Hanging sign', 'Kinetic', 'come in',
        const StudioTypeStyle(font: 'Lobster', weight: 400, color: _white, bg: StudioTextBg.box, bgColor: _blue, shadowBlur: 0),
        _a('drop', 'fall', 'swing', 900, 500, 2200), size: 0.075, tags: ['shop']),

    // ── Lower thirds ─────────────────────────────────────────────────────
    StudioTextTemplate('lt_name', 'Name bar', 'Lower thirds', 'Ada Okafor · Founder',
        const StudioTypeStyle(font: 'Inter', weight: 700, align: 0, color: _white, bg: StudioTextBg.bar, bgColor: _blue, shadowBlur: 0),
        _a('slide_right', 'slide_left', 'none', 500, 400), size: 0.045, tags: ['interview', 'name']),
    StudioTextTemplate('lt_news', 'Breaking', 'Lower thirds', 'BREAKING: Big news today',
        const StudioTypeStyle(font: 'Barlow Condensed', weight: 800, uppercase: true, align: 0, color: _white, bg: StudioTextBg.bar, bgColor: _pink, shadowBlur: 0),
        _a('unfold', 'fold', 'none', 500, 400), size: 0.045, tags: ['news']),
    StudioTextTemplate('lt_location', 'Location', 'Lower thirds', 'Nairobi, Kenya',
        const StudioTypeStyle(font: 'Montserrat', weight: 700, align: 0, color: _ink, bg: StudioTextBg.pill, bgColor: _white, shadowBlur: 0),
        _a('slide_right', 'fade', 'none', 500, 400), size: 0.045, tags: ['travel', 'place']),
    StudioTextTemplate('lt_step', 'Step', 'Lower thirds', 'Step 1 — Prep',
        const StudioTypeStyle(font: 'Poppins', weight: 700, align: 0, color: _white, bg: StudioTextBg.box, bgColor: 0xD9000000, shadowBlur: 0),
        _a('slide_up', 'slide_down', 'none', 450, 350), size: 0.05, tags: ['tutorial', 'recipe']),
    StudioTextTemplate('lt_quote', 'Quote', 'Lower thirds', '"Start before you\'re ready."',
        const StudioTypeStyle(font: 'Playfair Display', weight: 600, italic: true, color: _white, bg: StudioTextBg.underline, bgColor: _gold, shadowBlur: 0.2),
        _a('fade', 'fade', 'none', 800, 600), size: 0.055, tags: ['quote']),
    StudioTextTemplate('lt_price', 'Price tag', 'Lower thirds', '₦25,000 · DM to order',
        const StudioTypeStyle(font: 'DM Sans', weight: 800, color: _ink, bg: StudioTextBg.pill, bgColor: _lime, shadowBlur: 0),
        _a('pop', 'pop', 'pulse', 450, 300, 1600), size: 0.05, tags: ['shop', 'price', 'sell']),
    StudioTextTemplate('lt_credit', 'Credit', 'Lower thirds', 'music: original sound',
        const StudioTypeStyle(font: 'Inter', weight: 500, align: 0, color: _white, shadowBlur: 0.25),
        _a('fade', 'fade', 'none', 600, 500), size: 0.038, tags: ['credit']),
    StudioTextTemplate('lt_tip', 'Pro tip', 'Lower thirds', 'PRO TIP: shoot in daylight',
        const StudioTypeStyle(font: 'Lexend', weight: 700, color: _white, bg: StudioTextBg.box, bgColor: _purple, shadowBlur: 0),
        _a('slide_left', 'slide_right', 'none', 500, 400), size: 0.045, tags: ['tip']),

    // ── Captions ─────────────────────────────────────────────────────────
    StudioTextTemplate('ca_classic', 'Classic', 'Captions', 'this is how it sounds',
        const StudioTypeStyle(font: 'Inter', weight: 800, bg: StudioTextBg.box, bgColor: 0xB8000000, shadowBlur: 0),
        _none, size: 0.055, tags: ['subtitle']),
    StudioTextTemplate('ca_karaoke', 'Karaoke', 'Captions', 'every word lights up',
        const StudioTypeStyle(font: 'Montserrat', weight: 900, stroke: 0.12, highlightColor: _yellow, shadowBlur: 0),
        _none, size: 0.06, tags: ['karaoke', 'highlight', 'word']),
    StudioTextTemplate('ca_popwords', 'Pop words', 'Captions', 'words pop as you speak',
        const StudioTypeStyle(font: 'Poppins', weight: 800, stroke: 0.1, highlightColor: _pink, shadowBlur: 0),
        _a('words', 'fade', 'none', 10000, 200), size: 0.06, tags: ['word', 'reveal']),
    StudioTextTemplate('ca_bold', 'Creator', 'Captions', 'THIS CHANGED EVERYTHING',
        const StudioTypeStyle(font: 'Anton', weight: 400, uppercase: true, stroke: 0.1, highlightColor: _lime, shadowBlur: 0),
        _a('pop', 'none', 'none', 200), size: 0.075, tags: ['bold', 'shorts']),
    StudioTextTemplate('ca_clean', 'Clean', 'Captions', 'soft and simple',
        const StudioTypeStyle(font: 'Inter', weight: 600, shadowColor: 0xCC000000, shadowBlur: 0.25),
        _a('fade', 'fade', 'none', 150, 150), size: 0.05, tags: ['minimal']),
    StudioTextTemplate('ca_pill', 'Bubble', 'Captions', 'chatty bubble captions',
        const StudioTypeStyle(font: 'Nunito', weight: 800, color: _ink, bg: StudioTextBg.pill, bgColor: _white, highlightColor: _blue, shadowBlur: 0),
        _a('pop', 'none', 'none', 200), size: 0.052, tags: ['bubble']),
    StudioTextTemplate('ca_lines', 'Strip', 'Captions', 'each line gets a strip',
        const StudioTypeStyle(font: 'Lexend', weight: 700, bg: StudioTextBg.perLine, bgColor: _blue, highlightColor: _yellow, shadowBlur: 0),
        _none, size: 0.05, tags: ['line']),
    StudioTextTemplate('ca_neon', 'Glow', 'Captions', 'glowing night captions',
        const StudioTypeStyle(font: 'Poppins', weight: 700, glow: true, shadowColor: _pink, shadowBlur: 0.2, highlightColor: _cyan),
        _none, size: 0.055, tags: ['neon']),
    StudioTextTemplate('ca_type', 'Typed', 'Captions', 'typed out live',
        const StudioTypeStyle(font: 'Space Mono', weight: 700, color: _white, bg: StudioTextBg.box, bgColor: 0xCC000000, shadowBlur: 0),
        _a('typewriter', 'none', 'none', 600), size: 0.045, tags: ['typewriter']),
    StudioTextTemplate('ca_comic', 'Comic', 'Captions', 'LOUD AND PROUD',
        const StudioTypeStyle(font: 'Bangers', weight: 400, uppercase: true, letterSpacing: 0.04, color: _yellow, stroke: 0.12, strokeColor: _ink, highlightColor: _white, shadowBlur: 0),
        _a('elastic', 'none', 'none', 300), size: 0.08, tags: ['comic']),

    // ── Celebrate ────────────────────────────────────────────────────────
    StudioTextTemplate('ce_bday', 'Birthday', 'Celebrate', 'Happy Birthday!',
        const StudioTypeStyle(font: 'Lobster', weight: 400, color: _gold, color2: _pink, stroke: 0.06, strokeColor: _white, shadowBlur: 0),
        _a('elastic', 'pop', 'heartbeat', 900, 300, 1400), size: 0.1, tags: ['party', 'birthday']),
    StudioTextTemplate('ce_congrats', 'Congrats', 'Celebrate', 'CONGRATS!',
        const StudioTypeStyle(font: 'Bungee', weight: 400, uppercase: true, color: _lime, stroke: 0.08, strokeColor: _ink, shadowColor: _pink, shadowBlur: 0.01, shadowDy: 0.08),
        _a('drop', 'pop', 'bounce', 800, 300, 800), size: 0.1, tags: ['win', 'graduation']),
    StudioTextTemplate('ce_wedding', 'Wedding', 'Celebrate', 'Mr & Mrs',
        const StudioTypeStyle(font: 'Great Vibes', weight: 400, color: _white, glow: true, shadowColor: _gold, shadowBlur: 0.2),
        _a('fade', 'fade', 'breathe', 1400, 900, 3600), size: 0.13, tags: ['love', 'wedding']),
    StudioTextTemplate('ce_newyear', 'New year', 'Celebrate', '2027',
        const StudioTypeStyle(font: 'Monoton', weight: 400, color: _gold, glow: true, shadowColor: _gold, shadowBlur: 0.3),
        _a('zoom_out', 'zoom_in', 'flash', 900, 400, 2000), size: 0.15, tags: ['countdown']),
    StudioTextTemplate('ce_eid', 'Festive', 'Celebrate', 'Happy holidays',
        const StudioTypeStyle(font: 'Marcellus', weight: 400, color: _cream, color2: _gold, shadowColor: _shadow, shadowBlur: 0.3),
        _a('rise', 'fade', 'float', 1000, 700, 3200), size: 0.085, tags: ['holiday', 'eid', 'christmas']),
    StudioTextTemplate('ce_win', 'We did it', 'Celebrate', 'WE DID IT!',
        const StudioTypeStyle(font: 'Luckiest Guy', weight: 400, uppercase: true, color: _white, stroke: 0.12, strokeColor: _blue, shadowBlur: 0),
        _a('pop', 'pop', 'jelly', 600, 300, 900), size: 0.11, tags: ['win', 'team']),
    StudioTextTemplate('ce_thanks', 'Thank you', 'Celebrate', 'thank you',
        const StudioTypeStyle(font: 'Dancing Script', weight: 700, color: _white, bg: StudioTextBg.pill, bgColor: _pink, shadowBlur: 0),
        _a('typewriter', 'fade', 'none', 1000, 600), size: 0.08, tags: ['thanks', 'grateful']),
    StudioTextTemplate('ce_launch', 'Launch', 'Celebrate', 'IT\'S HERE',
        const StudioTypeStyle(font: 'Russo One', weight: 400, uppercase: true, color: _white, color2: _sky, glow: true, shadowColor: _blue, shadowBlur: 0.25),
        _a('zoom_out', 'zoom_in', 'pulse', 600, 400, 1100), size: 0.1, tags: ['launch', 'product']),
    StudioTextTemplate('ce_baby', 'Baby news', 'Celebrate', 'it\'s a girl!',
        const StudioTypeStyle(font: 'Baloo 2', weight: 800, color: _pink, bg: StudioTextBg.pill, bgColor: _white, shadowBlur: 0),
        _a('elastic', 'pop', 'float', 900, 300, 2400), size: 0.08, tags: ['baby', 'family']),
  ];

  static StudioTextTemplate? byId(String? id) => id == null ? null : all.where((t) => t.id == id).firstOrNull;

  static List<StudioTextTemplate> inCategory(String c) => all.where((t) => t.category == c).toList();

  static Set<String> get fonts => {for (final t in all) t.type.font};
}

/// Favorite and recently used templates, kept on this device.
class StudioTemplatePrefs {
  StudioTemplatePrefs._();

  static const _favKey = 'studio_text_favorites';
  static const _recentKey = 'studio_text_recent';

  static Future<Set<String>> favorites() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_favKey) ?? const []).toSet();
  }

  static Future<Set<String>> toggleFavorite(String id) async {
    final p = await SharedPreferences.getInstance();
    final set = (p.getStringList(_favKey) ?? const []).toSet();
    set.contains(id) ? set.remove(id) : set.add(id);
    await p.setStringList(_favKey, set.toList());
    return set;
  }

  static Future<List<String>> recent() async {
    final p = await SharedPreferences.getInstance();
    try {
      return (jsonDecode(p.getString(_recentKey) ?? '[]') as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> markUsed(String id) async {
    final p = await SharedPreferences.getInstance();
    final list = [id, ...(await recent()).where((x) => x != id)].take(16).toList();
    await p.setString(_recentKey, jsonEncode(list));
  }
}
