import 'dart:math' as math;

import '../models/studio_project.dart';

/// Transform of a text layer at one moment. Offsets are fractions of the
/// canvas (x of the width, y of the height, y down), rotation in degrees
/// clockwise. The preview applies it with a Transform; the export samples it
/// into keyframes for the Media3 overlay, so both move the same way.
class StudioAnimFrame {
  double alpha = 1;
  double sx = 1;
  double sy = 1;
  double dx = 0;
  double dy = 0;
  double rot = 0;

  /// Visible part of the text, 0..1 (typewriter / word reveals).
  double reveal = 1;

  /// 0 = whole text, 1 = characters, 2 = words, 3 = words as spoken.
  int revealMode = 0;
}

/// One animation preset.
class StudioAnimDef {
  final String id;
  final String label;
  const StudioAnimDef(this.id, this.label);
}

double _outCubic(double t) => 1 - math.pow(1 - t, 3).toDouble();
double _inCubic(double t) => t * t * t;
double _outBack(double t) {
  const c1 = 1.70158, c3 = c1 + 1;
  return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2);
}

double _inBack(double t) {
  const c1 = 1.70158, c3 = c1 + 1;
  return c3 * t * t * t - c1 * t * t;
}

double _outElastic(double t) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  const c4 = 2 * math.pi / 3;
  return math.pow(2, -10 * t) * math.sin((t * 10 - 0.75) * c4) + 1;
}

double _outBounce(double t) {
  const n1 = 7.5625, d1 = 2.75;
  if (t < 1 / d1) return n1 * t * t;
  if (t < 2 / d1) return n1 * (t -= 1.5 / d1) * t + 0.75;
  if (t < 2.5 / d1) return n1 * (t -= 2.25 / d1) * t + 0.9375;
  return n1 * (t -= 2.625 / d1) * t + 0.984375;
}

class StudioTextAnimator {
  StudioTextAnimator._();

  static const ins = <StudioAnimDef>[
    StudioAnimDef('none', 'None'),
    StudioAnimDef('fade', 'Fade'),
    StudioAnimDef('rise', 'Rise'),
    StudioAnimDef('slide_up', 'Slide up'),
    StudioAnimDef('slide_down', 'Slide down'),
    StudioAnimDef('slide_left', 'Slide left'),
    StudioAnimDef('slide_right', 'Slide right'),
    StudioAnimDef('pop', 'Pop'),
    StudioAnimDef('zoom_in', 'Zoom in'),
    StudioAnimDef('zoom_out', 'Zoom out'),
    StudioAnimDef('drop', 'Drop'),
    StudioAnimDef('spin', 'Spin'),
    StudioAnimDef('flip_x', 'Flip'),
    StudioAnimDef('flip_y', 'Flip up'),
    StudioAnimDef('stretch', 'Stretch'),
    StudioAnimDef('elastic', 'Elastic'),
    StudioAnimDef('swing', 'Swing'),
    StudioAnimDef('whip', 'Whip'),
    StudioAnimDef('unfold', 'Unfold'),
    StudioAnimDef('tilt', 'Tilt'),
    StudioAnimDef('typewriter', 'Typewriter'),
    StudioAnimDef('words', 'Word by word'),
  ];

  static const outs = <StudioAnimDef>[
    StudioAnimDef('none', 'None'),
    StudioAnimDef('fade', 'Fade'),
    StudioAnimDef('sink', 'Sink'),
    StudioAnimDef('slide_up', 'Slide up'),
    StudioAnimDef('slide_down', 'Slide down'),
    StudioAnimDef('slide_left', 'Slide left'),
    StudioAnimDef('slide_right', 'Slide right'),
    StudioAnimDef('pop', 'Pop out'),
    StudioAnimDef('zoom_in', 'Zoom in'),
    StudioAnimDef('zoom_out', 'Zoom out'),
    StudioAnimDef('spin', 'Spin'),
    StudioAnimDef('flip_x', 'Flip'),
    StudioAnimDef('flip_y', 'Flip down'),
    StudioAnimDef('stretch', 'Stretch'),
    StudioAnimDef('fall', 'Fall'),
    StudioAnimDef('fold', 'Fold'),
    StudioAnimDef('typewriter', 'Erase'),
    StudioAnimDef('words', 'Word by word'),
  ];

  static const loops = <StudioAnimDef>[
    StudioAnimDef('none', 'None'),
    StudioAnimDef('pulse', 'Pulse'),
    StudioAnimDef('breathe', 'Breathe'),
    StudioAnimDef('float', 'Float'),
    StudioAnimDef('sway', 'Sway'),
    StudioAnimDef('wiggle', 'Wiggle'),
    StudioAnimDef('swing', 'Swing'),
    StudioAnimDef('shake', 'Shake'),
    StudioAnimDef('blink', 'Blink'),
    StudioAnimDef('heartbeat', 'Heartbeat'),
    StudioAnimDef('jelly', 'Jelly'),
    StudioAnimDef('spin', 'Spin'),
    StudioAnimDef('bounce', 'Bounce'),
    StudioAnimDef('flash', 'Flash'),
  ];

  static String label(List<StudioAnimDef> list, String id) => list.firstWhere((d) => d.id == id, orElse: () => list.first).label;

  /// Whether [t] moves or changes over time.
  static bool isAnimated(StudioText t) => !t.anim.isStatic || (t.words.isNotEmpty && t.type.highlightColor != 0);

  /// Frame of [t] at output time [ms] (absolute timeline time).
  static StudioAnimFrame at(StudioText t, int ms) {
    final f = StudioAnimFrame();
    f.rot = t.rotation;
    final a = t.anim;
    final dur = math.max(1, t.endMs - t.startMs);
    final local = (ms - t.startMs).clamp(0, dur);
    var inMs = a.inId == 'none' ? 0 : a.inMs;
    var outMs = a.outId == 'none' ? 0 : a.outMs;
    if (inMs + outMs > dur) {
      final k = dur / (inMs + outMs);
      inMs = (inMs * k).floor();
      outMs = (outMs * k).floor();
    }

    if (a.loopId != 'none' && a.loopMs > 0) _loop(f, a.loopId, (local % a.loopMs) / a.loopMs);
    if (inMs > 0 && local < inMs) {
      _in(f, a.inId, local / inMs, t);
    } else if (outMs > 0 && local > dur - outMs) {
      _out(f, a.outId, (local - (dur - outMs)) / outMs);
    }
    if (f.revealMode == 0 && a.inId == 'words' && t.words.isNotEmpty && inMs > 0) {
      // Word-timed captions keep revealing as the words are spoken.
      f.revealMode = 3;
    }
    return f;
  }

  static void _in(StudioAnimFrame f, String id, double p, StudioText t) {
    final e = _outCubic(p);
    switch (id) {
      case 'fade':
        f.alpha *= p;
      case 'rise':
        f.dy += 0.08 * (1 - e);
        f.alpha *= e;
      case 'slide_up':
        f.dy += 0.25 * (1 - e);
        f.alpha *= math.min(1, p * 3);
      case 'slide_down':
        f.dy -= 0.25 * (1 - e);
        f.alpha *= math.min(1, p * 3);
      case 'slide_left':
        f.dx += 0.35 * (1 - e);
        f.alpha *= math.min(1, p * 3);
      case 'slide_right':
        f.dx -= 0.35 * (1 - e);
        f.alpha *= math.min(1, p * 3);
      case 'pop':
        final s = math.max(0.0, _outBack(p));
        f.sx *= s;
        f.sy *= s;
        f.alpha *= math.min(1, p * 4);
      case 'zoom_in':
        f.sx *= 0.3 + 0.7 * e;
        f.sy *= 0.3 + 0.7 * e;
        f.alpha *= e;
      case 'zoom_out':
        f.sx *= 1.8 - 0.8 * e;
        f.sy *= 1.8 - 0.8 * e;
        f.alpha *= e;
      case 'drop':
        f.dy -= 0.3 * (1 - _outBounce(p));
        f.alpha *= math.min(1, p * 4);
      case 'spin':
        f.rot -= 180 * (1 - e);
        f.sx *= 0.2 + 0.8 * e;
        f.sy *= 0.2 + 0.8 * e;
        f.alpha *= e;
      case 'flip_x':
        f.sx *= math.max(0.0, _outBack(p));
        f.alpha *= math.min(1, p * 3);
      case 'flip_y':
        f.sy *= math.max(0.0, _outBack(p));
        f.alpha *= math.min(1, p * 3);
      case 'stretch':
        f.sx *= 1.6 - 0.6 * e;
        f.sy *= 0.6 + 0.4 * e;
        f.alpha *= e;
      case 'elastic':
        final s = math.max(0.0, _outElastic(p));
        f.sx *= s;
        f.sy *= s;
      case 'swing':
        f.rot -= 30 * (1 - _outElastic(p));
        f.alpha *= math.min(1, p * 4);
      case 'whip':
        f.dx += 0.6 * (1 - _outBack(p));
        f.alpha *= math.min(1, p * 5);
      case 'unfold':
        f.sy *= e;
        f.alpha *= e;
      case 'tilt':
        f.rot += 12 * (1 - e);
        f.dy += 0.05 * (1 - e);
        f.alpha *= e;
      case 'typewriter':
        f.reveal = p;
        f.revealMode = 1;
      case 'words':
        f.reveal = p;
        f.revealMode = t.words.isNotEmpty ? 3 : 2;
    }
  }

  static void _out(StudioAnimFrame f, String id, double q) {
    final ei = _inCubic(q);
    switch (id) {
      case 'fade':
        f.alpha *= 1 - q;
      case 'sink':
        f.dy += 0.08 * ei;
        f.alpha *= 1 - q;
      case 'slide_up':
        f.dy -= 0.25 * ei;
        f.alpha *= 1 - ei;
      case 'slide_down':
        f.dy += 0.25 * ei;
        f.alpha *= 1 - ei;
      case 'slide_left':
        f.dx -= 0.35 * ei;
        f.alpha *= 1 - ei;
      case 'slide_right':
        f.dx += 0.35 * ei;
        f.alpha *= 1 - ei;
      case 'pop':
        final s = math.max(0.0, 1 - _inBack(q));
        f.sx *= s;
        f.sy *= s;
        f.alpha *= 1 - q * q * q;
      case 'zoom_in':
        f.sx *= 1 + 0.8 * ei;
        f.sy *= 1 + 0.8 * ei;
        f.alpha *= 1 - q;
      case 'zoom_out':
        f.sx *= 1 - 0.7 * ei;
        f.sy *= 1 - 0.7 * ei;
        f.alpha *= 1 - q;
      case 'spin':
        f.rot += 180 * ei;
        f.sx *= 1 - 0.8 * ei;
        f.sy *= 1 - 0.8 * ei;
        f.alpha *= 1 - q;
      case 'flip_x':
        f.sx *= 1 - ei;
      case 'flip_y':
        f.sy *= 1 - ei;
      case 'stretch':
        f.sx *= 1 + 0.6 * ei;
        f.sy *= 1 - 0.4 * ei;
        f.alpha *= 1 - q;
      case 'fall':
        f.dy += 0.4 * ei * ei;
        f.rot += 15 * ei;
        f.alpha *= 1 - q;
      case 'fold':
        f.sy *= 1 - ei;
        f.alpha *= 1 - q * 0.5;
      case 'typewriter':
        f.reveal = 1 - q;
        f.revealMode = 1;
      case 'words':
        f.reveal = 1 - q;
        f.revealMode = 2;
    }
  }

  static void _loop(StudioAnimFrame f, String id, double ph) {
    final w = ph * 2 * math.pi;
    switch (id) {
      case 'pulse':
        final s = 1 + 0.06 * math.sin(w);
        f.sx *= s;
        f.sy *= s;
      case 'breathe':
        final s = 1 + 0.03 * math.sin(w);
        f.sx *= s;
        f.sy *= s;
        f.alpha *= 0.9 + 0.1 * math.sin(w);
      case 'float':
        f.dy += 0.012 * math.sin(w);
      case 'sway':
        f.dx += 0.015 * math.sin(w);
      case 'wiggle':
        f.rot += 4 * math.sin(w * 2);
      case 'swing':
        f.rot += 8 * math.sin(w);
      case 'shake':
        f.dx += 0.006 * math.sin(w * 6);
        f.dy += 0.004 * math.cos(w * 5);
      case 'blink':
        f.alpha *= ph < 0.5 ? 1 : 0.25;
      case 'heartbeat':
        double bump(double c) => math.max(0.0, 1 - ((ph - c).abs() / 0.08));
        final s = 1 + 0.12 * math.max(bump(0.1), bump(0.3) * 0.7);
        f.sx *= s;
        f.sy *= s;
      case 'jelly':
        f.sx *= 1 + 0.06 * math.sin(w);
        f.sy *= 1 - 0.06 * math.sin(w);
      case 'spin':
        f.rot += 360 * ph;
      case 'bounce':
        f.dy -= 0.03 * math.sin(math.pi * ph).abs();
      case 'flash':
        f.alpha *= ph < 0.12 ? 0.15 : 1;
    }
  }

  /// Display string (with the style's case).
  static String display(StudioText t) {
    final s = t.text.isEmpty ? ' ' : t.text;
    return t.type.uppercase ? s.toUpperCase() : s;
  }

  static final _wordSplit = RegExp(r'\s+');

  /// Number of words in the displayed text.
  static int wordCount(StudioText t) => display(t).trim().split(_wordSplit).where((w) => w.isNotEmpty).length;

  /// Characters (mode 1) or words (2, 3) visible for [f], or null when the
  /// whole text shows. Character reveals step at most 40 times so exports keep
  /// few distinct frames; the preview uses the same steps.
  static int? visibleUnits(StudioText t, StudioAnimFrame f, int ms) {
    switch (f.revealMode) {
      case 1:
        final total = display(t).runes.length;
        if (total <= 0) return null;
        final steps = math.min(total, 40);
        return ((f.reveal * steps).round() / steps * total).round().clamp(0, total);
      case 2:
        final total = wordCount(t);
        return (f.reveal * total).ceil().clamp(0, total);
      case 3:
        final total = wordCount(t);
        final spoken = t.words.where((w) => w.startMs <= ms).length;
        final mapped = t.words.isEmpty ? total : (spoken * total / t.words.length).round();
        // Never hide words the out animation already showed.
        return f.reveal >= 1 ? mapped.clamp(0, total) : math.min(mapped, (f.reveal * total).ceil()).clamp(0, total);
    }
    return null;
  }

  /// Index (in displayed words) of the word being spoken at [ms], or -1.
  static int activeWord(StudioText t, int ms) {
    if (t.words.isEmpty || t.type.highlightColor == 0) return -1;
    var idx = -1;
    for (var i = 0; i < t.words.length; i++) {
      if (t.words[i].startMs <= ms) idx = i;
    }
    if (idx < 0) return -1;
    final total = wordCount(t);
    if (total == t.words.length) return idx;
    return (idx * total / t.words.length).floor().clamp(0, total - 1);
  }
}
