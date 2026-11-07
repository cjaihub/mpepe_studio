/// Typography and animation of a Studio text layer. Everything here is drawn
/// by `StudioTextPainter` (preview and export) and animated by
/// `StudioTextAnimator`, so a layer looks the same in the editor and in the
/// exported file.
library;

/// Shape drawn behind the text.
enum StudioTextBg {
  none('None'),
  box('Box'),
  pill('Pill'),
  bar('Bar'),
  underline('Underline'),
  frame('Frame'),
  perLine('Per line');

  final String label;
  const StudioTextBg(this.label);

  static StudioTextBg byName(String? n) => values.firstWhere((v) => v.name == n, orElse: () => none);
}

/// Look of a text layer. Sizes are fractions of the font size so a style
/// scales with the layer.
class StudioTypeStyle {
  final String font;
  final int weight;
  final bool italic;
  final int color;

  /// Second fill color for a vertical gradient (0 = solid).
  final int color2;
  final int strokeColor;

  /// Outline width as a fraction of the font size (0 = none).
  final double stroke;
  final int shadowColor;

  /// Shadow blur / offset as fractions of the font size (blur 0 = no shadow).
  final double shadowBlur;
  final double shadowDx;
  final double shadowDy;

  /// Neon-style glow in [shadowColor] (two soft shadows).
  final bool glow;
  final StudioTextBg bg;
  final int bgColor;

  /// Letter spacing in em.
  final double letterSpacing;
  final double lineHeight;
  final bool uppercase;

  /// 0 left, 1 center, 2 right.
  final int align;

  /// Color of the spoken word in word-timed captions (0 = no highlight).
  final int highlightColor;

  const StudioTypeStyle({
    this.font = 'Inter',
    this.weight = 700,
    this.italic = false,
    this.color = 0xFFFFFFFF,
    this.color2 = 0,
    this.strokeColor = 0xFF000000,
    this.stroke = 0,
    this.shadowColor = 0x8C000000,
    this.shadowBlur = 0.18,
    this.shadowDx = 0,
    this.shadowDy = 0,
    this.glow = false,
    this.bg = StudioTextBg.none,
    this.bgColor = 0xB8000000,
    this.letterSpacing = -0.01,
    this.lineHeight = 1.18,
    this.uppercase = false,
    this.align = 1,
    this.highlightColor = 0,
  });

  StudioTypeStyle copyWith({
    String? font,
    int? weight,
    bool? italic,
    int? color,
    int? color2,
    int? strokeColor,
    double? stroke,
    int? shadowColor,
    double? shadowBlur,
    double? shadowDx,
    double? shadowDy,
    bool? glow,
    StudioTextBg? bg,
    int? bgColor,
    double? letterSpacing,
    double? lineHeight,
    bool? uppercase,
    int? align,
    int? highlightColor,
  }) =>
      StudioTypeStyle(
        font: font ?? this.font,
        weight: weight ?? this.weight,
        italic: italic ?? this.italic,
        color: color ?? this.color,
        color2: color2 ?? this.color2,
        strokeColor: strokeColor ?? this.strokeColor,
        stroke: stroke ?? this.stroke,
        shadowColor: shadowColor ?? this.shadowColor,
        shadowBlur: shadowBlur ?? this.shadowBlur,
        shadowDx: shadowDx ?? this.shadowDx,
        shadowDy: shadowDy ?? this.shadowDy,
        glow: glow ?? this.glow,
        bg: bg ?? this.bg,
        bgColor: bgColor ?? this.bgColor,
        letterSpacing: letterSpacing ?? this.letterSpacing,
        lineHeight: lineHeight ?? this.lineHeight,
        uppercase: uppercase ?? this.uppercase,
        align: align ?? this.align,
        highlightColor: highlightColor ?? this.highlightColor,
      );

  Map<String, dynamic> toJson() => {
        'font': font,
        'weight': weight,
        'italic': italic,
        'color': color,
        'color2': color2,
        'strokeColor': strokeColor,
        'stroke': stroke,
        'shadowColor': shadowColor,
        'shadowBlur': shadowBlur,
        'shadowDx': shadowDx,
        'shadowDy': shadowDy,
        'glow': glow,
        'bg': bg.name,
        'bgColor': bgColor,
        'letterSpacing': letterSpacing,
        'lineHeight': lineHeight,
        'uppercase': uppercase,
        'align': align,
        'highlightColor': highlightColor,
      };

  factory StudioTypeStyle.fromJson(Map<String, dynamic> m) {
    const d = StudioTypeStyle();
    double n(String k, double def) => (m[k] as num?)?.toDouble() ?? def;
    int i(String k, int def) => (m[k] as num?)?.toInt() ?? def;
    return StudioTypeStyle(
      font: m['font'] as String? ?? d.font,
      weight: i('weight', d.weight),
      italic: m['italic'] == true,
      color: i('color', d.color),
      color2: i('color2', d.color2),
      strokeColor: i('strokeColor', d.strokeColor),
      stroke: n('stroke', d.stroke),
      shadowColor: i('shadowColor', d.shadowColor),
      shadowBlur: n('shadowBlur', d.shadowBlur),
      shadowDx: n('shadowDx', d.shadowDx),
      shadowDy: n('shadowDy', d.shadowDy),
      glow: m['glow'] == true,
      bg: StudioTextBg.byName(m['bg'] as String?),
      bgColor: i('bgColor', d.bgColor),
      letterSpacing: n('letterSpacing', d.letterSpacing),
      lineHeight: n('lineHeight', d.lineHeight),
      uppercase: m['uppercase'] == true,
      align: i('align', d.align),
      highlightColor: i('highlightColor', d.highlightColor),
    );
  }
}

/// In / out / loop animation of a text layer (ids from `StudioTextAnimator`).
class StudioTextAnim {
  final String inId;
  final String outId;
  final String loopId;
  final int inMs;
  final int outMs;

  /// One loop cycle.
  final int loopMs;

  const StudioTextAnim({
    this.inId = 'none',
    this.outId = 'none',
    this.loopId = 'none',
    this.inMs = 500,
    this.outMs = 400,
    this.loopMs = 1200,
  });

  bool get isStatic => inId == 'none' && outId == 'none' && loopId == 'none';

  StudioTextAnim copyWith({String? inId, String? outId, String? loopId, int? inMs, int? outMs, int? loopMs}) => StudioTextAnim(
        inId: inId ?? this.inId,
        outId: outId ?? this.outId,
        loopId: loopId ?? this.loopId,
        inMs: inMs ?? this.inMs,
        outMs: outMs ?? this.outMs,
        loopMs: loopMs ?? this.loopMs,
      );

  Map<String, dynamic> toJson() => {'in': inId, 'out': outId, 'loop': loopId, 'inMs': inMs, 'outMs': outMs, 'loopMs': loopMs};

  factory StudioTextAnim.fromJson(Map<String, dynamic>? m) => StudioTextAnim(
        inId: m?['in'] as String? ?? 'none',
        outId: m?['out'] as String? ?? 'none',
        loopId: m?['loop'] as String? ?? 'none',
        inMs: (m?['inMs'] as num?)?.toInt() ?? 500,
        outMs: (m?['outMs'] as num?)?.toInt() ?? 400,
        loopMs: (m?['loopMs'] as num?)?.toInt() ?? 1200,
      );
}

/// A spoken word in a caption, on the output timeline.
class StudioWord {
  final String text;
  final int startMs;
  final int endMs;
  const StudioWord(this.text, this.startMs, this.endMs);

  Map<String, dynamic> toJson() => {'w': text, 's': startMs, 'e': endMs};

  factory StudioWord.fromJson(Map<String, dynamic> m) =>
      StudioWord(m['w'] as String? ?? '', (m['s'] as num?)?.toInt() ?? 0, (m['e'] as num?)?.toInt() ?? 0);
}
