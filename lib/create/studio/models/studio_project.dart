import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import 'studio_text_style.dart';
import '../../../backend/social/models/remix_source.dart';
export '../../../backend/social/models/remix_source.dart' show RemixSource;

export 'studio_text_style.dart';

const _uuid = Uuid();

/// Where the finished export goes after the editor.
enum StudioTarget { post, story, device }

/// Canvas shape of the project. `original` follows the first clip.
enum StudioAspect {
  original('Original', 0),
  portrait('9:16 Shorts', 9 / 16),
  square('1:1', 1),
  feed('4:5', 4 / 5),
  classic('3:4', 3 / 4),
  landscape('16:9 Full', 16 / 9);

  final String label;
  final double ratio;
  const StudioAspect(this.label, this.ratio);
}

/// Per-clip color adjustments, each -1..1 (0 = untouched; detail keys 0..1).
///
/// The first group is a color matrix (`StudioColor`); the tone/detail group
/// runs through the Oneova Look engine (`StudioLooks`). Both are baked into
/// exports.
class StudioAdjust {
  final double brightness;
  final double contrast;
  final double saturation;
  final double exposure;
  final double warmth;
  final double tint;
  final double fade;
  final double highlights;
  final double shadows;
  final double whites;
  final double blacks;
  final double vibrance;
  final double sharpen;
  final double grain;
  final double vignette;

  const StudioAdjust({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.exposure = 0,
    this.warmth = 0,
    this.tint = 0,
    this.fade = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.whites = 0,
    this.blacks = 0,
    this.vibrance = 0,
    this.sharpen = 0,
    this.grain = 0,
    this.vignette = 0,
  });

  /// Matrix keys (color), then Look-engine keys (tone and detail).
  static const colorKeys = ['brightness', 'contrast', 'saturation', 'exposure', 'warmth', 'tint', 'fade'];
  static const toneKeys = ['highlights', 'shadows', 'whites', 'blacks', 'vibrance'];
  static const detailKeys = ['sharpen', 'grain', 'vignette'];
  static const keys = [...colorKeys, ...toneKeys, ...detailKeys];

  /// Keys that only go 0..1.
  static const positiveKeys = detailKeys;

  bool get hasLookKeys => [...toneKeys, ...detailKeys].any((k) => valueOf(k) != 0);

  bool get isIdentity => toJson().values.every((v) => v == 0);

  double valueOf(String key) => (toJson()[key] as double?) ?? 0;

  StudioAdjust withValue(String key, double v) {
    final m = toJson()..[key] = v;
    return StudioAdjust.fromJson(m);
  }

  Map<String, dynamic> toJson() => {
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'exposure': exposure,
        'warmth': warmth,
        'tint': tint,
        'fade': fade,
        'highlights': highlights,
        'shadows': shadows,
        'whites': whites,
        'blacks': blacks,
        'vibrance': vibrance,
        'sharpen': sharpen,
        'grain': grain,
        'vignette': vignette,
      };

  factory StudioAdjust.fromJson(Map<String, dynamic>? m) {
    double v(String k) => (m?[k] as num?)?.toDouble() ?? 0;
    return StudioAdjust(
      brightness: v('brightness'),
      contrast: v('contrast'),
      saturation: v('saturation'),
      exposure: v('exposure'),
      warmth: v('warmth'),
      tint: v('tint'),
      fade: v('fade'),
      highlights: v('highlights'),
      shadows: v('shadows'),
      whites: v('whites'),
      blacks: v('blacks'),
      vibrance: v('vibrance'),
      sharpen: v('sharpen'),
      grain: v('grain'),
      vignette: v('vignette'),
    );
  }
}

/// Face & skin retouch for a clip, each 0..1 (warm and chin -1..1). Skin
/// tools work on any skin; eyes, teeth and reshape follow tracked faces.
class StudioRetouch {
  final double smooth;
  final double even;
  final double bright;
  final double warm;
  final double eyes;
  final double teeth;
  final double slim;
  final double bigEyes;
  final double nose;
  final double chin;

  const StudioRetouch({
    this.smooth = 0,
    this.even = 0,
    this.bright = 0,
    this.warm = 0,
    this.eyes = 0,
    this.teeth = 0,
    this.slim = 0,
    this.bigEyes = 0,
    this.nose = 0,
    this.chin = 0,
  });

  static const skinKeys = ['smooth', 'even', 'bright', 'warm'];
  static const faceKeys = ['eyes', 'teeth', 'slim', 'bigEyes', 'nose', 'chin'];
  static const keys = [...skinKeys, ...faceKeys];

  /// Keys that go -1..1.
  static const signedKeys = ['warm', 'chin'];

  bool get isIdentity => toJson().values.every((v) => v == 0);

  /// Needs tracked faces (eyes, teeth, reshape).
  bool get needsFaces => faceKeys.any((k) => valueOf(k) != 0);

  double valueOf(String k) => (toJson()[k] as double?) ?? 0;
  StudioRetouch withValue(String k, double v) => StudioRetouch.fromJson(toJson()..[k] = v);

  /// Shader order: smooth, even, bright, warm, eyes, teeth, slim, bigEyes, nose, chin.
  List<double> get params => [smooth, even, bright, warm, eyes, teeth, slim, bigEyes, nose, chin];

  Map<String, dynamic> toJson() => {
        'smooth': smooth,
        'even': even,
        'bright': bright,
        'warm': warm,
        'eyes': eyes,
        'teeth': teeth,
        'slim': slim,
        'bigEyes': bigEyes,
        'nose': nose,
        'chin': chin,
      };

  factory StudioRetouch.fromJson(Map<String, dynamic>? m) {
    double v(String k) => (m?[k] as num?)?.toDouble() ?? 0;
    return StudioRetouch(
      smooth: v('smooth'),
      even: v('even'),
      bright: v('bright'),
      warm: v('warm'),
      eyes: v('eyes'),
      teeth: v('teeth'),
      slim: v('slim'),
      bigEyes: v('bigEyes'),
      nose: v('nose'),
      chin: v('chin'),
    );
  }
}

/// Normalized crop rectangle (0..1, top-left origin) on the source frame.
class StudioCrop {
  final double l, t, r, b;
  const StudioCrop({this.l = 0, this.t = 0, this.r = 1, this.b = 1});

  bool get isFull => l <= 0.001 && t <= 0.001 && r >= 0.999 && b >= 0.999;

  Map<String, dynamic> toJson() => {'l': l, 't': t, 'r': r, 'b': b};

  factory StudioCrop.fromJson(Map<String, dynamic>? m) => StudioCrop(
        l: (m?['l'] as num?)?.toDouble() ?? 0,
        t: (m?['t'] as num?)?.toDouble() ?? 0,
        r: (m?['r'] as num?)?.toDouble() ?? 1,
        b: (m?['b'] as num?)?.toDouble() ?? 1,
      );
}

/// One video or photo on the main track.
class StudioClip {
  final String id;
  final String path;
  final bool isImage;
  final int sourceDurationMs;
  final int sourceWidth;
  final int sourceHeight;
  final double sourceFps;
  final bool hasAudio;
  final int startMs;
  final int endMs;
  final int imageDurationMs;
  final double speed;
  final double volume;
  final bool muted;

  /// Voice clean-up strength 0..1 (rumble cut, gate, presence, compressor), applied in the export.
  final double voiceClean;

  /// Stabilize strength 0..1 (camera path smoothed, slight zoom).
  final double stabilize;
  final String filterId;
  final double filterIntensity;

  /// Oneova Look preset (`StudioLooks`), graded on the GPU in preview and export.
  final String lookId;
  final double lookIntensity;
  final StudioAdjust adjust;
  final StudioRetouch retouch;
  final StudioCrop crop;
  final int rotation;
  final bool flipH;
  final bool flipV;
  final double zoom;
  final bool fill;

  const StudioClip({
    required this.id,
    required this.path,
    required this.isImage,
    required this.sourceDurationMs,
    required this.sourceWidth,
    required this.sourceHeight,
    this.sourceFps = 30,
    this.hasAudio = true,
    this.startMs = 0,
    required this.endMs,
    this.imageDurationMs = 3000,
    this.speed = 1,
    this.volume = 1,
    this.muted = false,
    this.voiceClean = 0,
    this.stabilize = 0,
    this.filterId = 'none',
    this.filterIntensity = 1,
    this.lookId = 'none',
    this.lookIntensity = 1,
    this.adjust = const StudioAdjust(),
    this.retouch = const StudioRetouch(),
    this.crop = const StudioCrop(),
    this.rotation = 0,
    this.flipH = false,
    this.flipV = false,
    this.zoom = 1,
    this.fill = false,
  });

  factory StudioClip.create({
    required String path,
    required bool isImage,
    required int durationMs,
    required int width,
    required int height,
    double fps = 30,
    bool hasAudio = true,
    int startMs = 0,
    int? endMs,
  }) =>
      StudioClip(
        id: _uuid.v4(),
        path: path,
        isImage: isImage,
        sourceDurationMs: isImage ? 0 : durationMs,
        sourceWidth: width,
        sourceHeight: height,
        sourceFps: fps,
        hasAudio: !isImage && hasAudio,
        startMs: isImage ? 0 : startMs,
        endMs: isImage ? 0 : (endMs ?? durationMs),
      );

  /// Length of this clip on the output timeline.
  int get outDurationMs => isImage ? imageDurationMs : ((endMs - startMs) / speed).round();

  /// Source size after rotation and crop.
  double get displayAspect {
    final w = sourceWidth <= 0 ? 9.0 : sourceWidth.toDouble();
    final h = sourceHeight <= 0 ? 16.0 : sourceHeight.toDouble();
    final cw = w * (crop.r - crop.l);
    final ch = h * (crop.b - crop.t);
    final turned = rotation % 180 != 0;
    return turned ? ch / cw : cw / ch;
  }

  /// Output time inside this clip -> source position.
  int sourceMsAt(int localOutMs) => isImage ? 0 : (startMs + localOutMs * speed).round().clamp(startMs, endMs);

  StudioClip copyWith({
    String? id,
    String? path,
    bool? isImage,
    int? sourceDurationMs,
    int? sourceWidth,
    int? sourceHeight,
    double? sourceFps,
    bool? hasAudio,
    int? startMs,
    int? endMs,
    int? imageDurationMs,
    double? speed,
    double? volume,
    bool? muted,
    double? voiceClean,
    double? stabilize,
    String? filterId,
    double? filterIntensity,
    String? lookId,
    double? lookIntensity,
    StudioAdjust? adjust,
    StudioRetouch? retouch,
    StudioCrop? crop,
    int? rotation,
    bool? flipH,
    bool? flipV,
    double? zoom,
    bool? fill,
  }) =>
      StudioClip(
        id: id ?? this.id,
        path: path ?? this.path,
        isImage: isImage ?? this.isImage,
        sourceDurationMs: sourceDurationMs ?? this.sourceDurationMs,
        sourceWidth: sourceWidth ?? this.sourceWidth,
        sourceHeight: sourceHeight ?? this.sourceHeight,
        sourceFps: sourceFps ?? this.sourceFps,
        hasAudio: hasAudio ?? this.hasAudio,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        imageDurationMs: imageDurationMs ?? this.imageDurationMs,
        speed: speed ?? this.speed,
        volume: volume ?? this.volume,
        muted: muted ?? this.muted,
        voiceClean: voiceClean ?? this.voiceClean,
        stabilize: stabilize ?? this.stabilize,
        filterId: filterId ?? this.filterId,
        filterIntensity: filterIntensity ?? this.filterIntensity,
        lookId: lookId ?? this.lookId,
        lookIntensity: lookIntensity ?? this.lookIntensity,
        adjust: adjust ?? this.adjust,
        retouch: retouch ?? this.retouch,
        crop: crop ?? this.crop,
        rotation: rotation ?? this.rotation,
        flipH: flipH ?? this.flipH,
        flipV: flipV ?? this.flipV,
        zoom: zoom ?? this.zoom,
        fill: fill ?? this.fill,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'isImage': isImage,
        'sourceDurationMs': sourceDurationMs,
        'sourceWidth': sourceWidth,
        'sourceHeight': sourceHeight,
        'sourceFps': sourceFps,
        'hasAudio': hasAudio,
        'startMs': startMs,
        'endMs': endMs,
        'imageDurationMs': imageDurationMs,
        'speed': speed,
        'volume': volume,
        'muted': muted,
        'voiceClean': voiceClean,
        'stabilize': stabilize,
        'filterId': filterId,
        'filterIntensity': filterIntensity,
        'lookId': lookId,
        'lookIntensity': lookIntensity,
        'adjust': adjust.toJson(),
        if (!retouch.isIdentity) 'retouch': retouch.toJson(),
        'crop': crop.toJson(),
        'rotation': rotation,
        'flipH': flipH,
        'flipV': flipV,
        'zoom': zoom,
        'fill': fill,
      };

  factory StudioClip.fromJson(Map<String, dynamic> m) => StudioClip(
        id: m['id'] as String,
        path: m['path'] as String,
        isImage: m['isImage'] == true,
        sourceDurationMs: (m['sourceDurationMs'] as num?)?.toInt() ?? 0,
        sourceWidth: (m['sourceWidth'] as num?)?.toInt() ?? 0,
        sourceHeight: (m['sourceHeight'] as num?)?.toInt() ?? 0,
        sourceFps: (m['sourceFps'] as num?)?.toDouble() ?? 30,
        hasAudio: m['hasAudio'] != false,
        startMs: (m['startMs'] as num?)?.toInt() ?? 0,
        endMs: (m['endMs'] as num?)?.toInt() ?? 0,
        imageDurationMs: (m['imageDurationMs'] as num?)?.toInt() ?? 3000,
        speed: (m['speed'] as num?)?.toDouble() ?? 1,
        volume: (m['volume'] as num?)?.toDouble() ?? 1,
        muted: m['muted'] == true,
        voiceClean: (m['voiceClean'] as num?)?.toDouble() ?? 0,
        stabilize: (m['stabilize'] as num?)?.toDouble() ?? 0,
        filterId: m['filterId'] as String? ?? 'none',
        filterIntensity: (m['filterIntensity'] as num?)?.toDouble() ?? 1,
        lookId: m['lookId'] as String? ?? 'none',
        lookIntensity: (m['lookIntensity'] as num?)?.toDouble() ?? 1,
        adjust: StudioAdjust.fromJson((m['adjust'] as Map?)?.cast<String, dynamic>()),
        retouch: StudioRetouch.fromJson((m['retouch'] as Map?)?.cast<String, dynamic>()),
        crop: StudioCrop.fromJson((m['crop'] as Map?)?.cast<String, dynamic>()),
        rotation: (m['rotation'] as num?)?.toInt() ?? 0,
        flipH: m['flipH'] == true,
        flipV: m['flipV'] == true,
        zoom: (m['zoom'] as num?)?.toDouble() ?? 1,
        fill: m['fill'] == true,
      );
}

/// Quick text styles from the first Studio version (kept so older projects
/// open; mapped onto [StudioTypeStyle]).
enum StudioTextStyle {
  plain('Plain'),
  box('Box'),
  outline('Outline'),
  glow('Glow'),
  bold('Bold pop');

  final String label;
  const StudioTextStyle(this.label);

  StudioTypeStyle toType(int color) => switch (this) {
        StudioTextStyle.plain => StudioTypeStyle(color: color),
        StudioTextStyle.box => StudioTypeStyle(
            color: color,
            weight: 800,
            shadowBlur: 0,
            bg: StudioTextBg.box,
            bgColor: Color32.luminance(color) > 0.5 ? 0xB8000000 : 0xB8FFFFFF,
          ),
        StudioTextStyle.outline => StudioTypeStyle(color: color, weight: 800, stroke: 0.1, shadowBlur: 0),
        StudioTextStyle.glow => StudioTypeStyle(color: color, weight: 800, glow: true, shadowColor: color, shadowBlur: 0.45),
        StudioTextStyle.bold => StudioTypeStyle(
            color: color,
            weight: 900,
            stroke: 0.16,
            shadowColor: 0xFF000000,
            shadowBlur: 0.01,
            shadowDx: 0.06,
            shadowDy: 0.08,
            letterSpacing: -0.025,
          ),
      };
}

/// Tiny color helpers that keep the model free of Flutter imports.
class Color32 {
  Color32._();

  static double luminance(int argb) {
    double ch(int v) {
      final c = v / 255;
      return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * ch((argb >> 16) & 0xFF) + 0.7152 * ch((argb >> 8) & 0xFF) + 0.0722 * ch(argb & 0xFF);
  }
}

/// Text, sticker (emoji) or caption burned into the video over a time range.
class StudioText {
  final String id;
  final String text;
  final int startMs;
  final int endMs;

  /// Center of the layer, -1..1 on both axes (y down), like Flutter's Alignment.
  final double x;
  final double y;

  /// Font size as a fraction of the canvas width.
  final double size;

  /// Extra rotation in degrees (clockwise).
  final double rotation;
  final StudioTypeStyle type;
  final StudioTextAnim anim;

  /// Template this layer came from (for the picker's "in use" mark).
  final String? templateId;

  /// Word timing for auto captions (output time).
  final List<StudioWord> words;

  /// Language code of [text] when known (auto captions / translation).
  final String? lang;
  final bool isCaption;
  final bool isSticker;

  const StudioText({
    required this.id,
    required this.text,
    required this.startMs,
    required this.endMs,
    this.x = 0,
    this.y = 0,
    this.size = 0.07,
    this.rotation = 0,
    this.type = const StudioTypeStyle(),
    this.anim = const StudioTextAnim(),
    this.templateId,
    this.words = const [],
    this.lang,
    this.isCaption = false,
    this.isSticker = false,
  });

  /// Text color (shortcut for [type].color).
  int get color => type.color;

  factory StudioText.create({
    required String text,
    required int startMs,
    required int endMs,
    bool isCaption = false,
    bool isSticker = false,
    StudioTextStyle style = StudioTextStyle.plain,
    StudioTypeStyle? type,
    StudioTextAnim anim = const StudioTextAnim(),
    String? templateId,
    List<StudioWord> words = const [],
    String? lang,
  }) =>
      StudioText(
        id: _uuid.v4(),
        text: text,
        startMs: startMs,
        endMs: endMs,
        y: isCaption ? 0.62 : 0,
        size: isSticker ? 0.16 : (isCaption ? 0.055 : 0.07),
        type: type ?? (isCaption ? StudioTextStyle.box : style).toType(0xFFFFFFFF),
        anim: anim,
        templateId: templateId,
        words: words,
        lang: lang,
        isCaption: isCaption,
        isSticker: isSticker,
      );

  StudioText copyWith({
    String? id,
    String? text,
    int? startMs,
    int? endMs,
    double? x,
    double? y,
    double? size,
    double? rotation,
    int? color,
    StudioTextStyle? style,
    StudioTypeStyle? type,
    StudioTextAnim? anim,
    String? templateId,
    List<StudioWord>? words,
    String? lang,
  }) {
    var t = type ?? this.type;
    if (style != null) t = style.toType(color ?? t.color);
    if (color != null) t = t.copyWith(color: color);
    return StudioText(
      id: id ?? this.id,
      text: text ?? this.text,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      x: x ?? this.x,
      y: y ?? this.y,
      size: size ?? this.size,
      rotation: rotation ?? this.rotation,
      type: t,
      anim: anim ?? this.anim,
      templateId: templateId ?? this.templateId,
      words: words ?? this.words,
      lang: lang ?? this.lang,
      isCaption: isCaption,
      isSticker: isSticker,
    );
  }

  /// Shifts the layer (and its word timing) by [deltaMs].
  StudioText shifted(int deltaMs) => copyWith(
        startMs: startMs + deltaMs,
        endMs: endMs + deltaMs,
        words: [for (final w in words) StudioWord(w.text, w.startMs + deltaMs, w.endMs + deltaMs)],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'startMs': startMs,
        'endMs': endMs,
        'x': x,
        'y': y,
        'size': size,
        'rotation': rotation,
        'type': type.toJson(),
        'anim': anim.toJson(),
        'templateId': templateId,
        if (words.isNotEmpty) 'words': [for (final w in words) w.toJson()],
        'lang': lang,
        'isCaption': isCaption,
        'isSticker': isSticker,
      };

  factory StudioText.fromJson(Map<String, dynamic> m) {
    final typeJson = (m['type'] as Map?)?.cast<String, dynamic>();
    final legacy = StudioTextStyle.values.firstWhere((s) => s.name == m['style'], orElse: () => StudioTextStyle.plain);
    return StudioText(
      id: m['id'] as String,
      text: m['text'] as String? ?? '',
      startMs: (m['startMs'] as num?)?.toInt() ?? 0,
      endMs: (m['endMs'] as num?)?.toInt() ?? 0,
      x: (m['x'] as num?)?.toDouble() ?? 0,
      y: (m['y'] as num?)?.toDouble() ?? 0,
      size: (m['size'] as num?)?.toDouble() ?? 0.07,
      rotation: (m['rotation'] as num?)?.toDouble() ?? 0,
      type: typeJson != null ? StudioTypeStyle.fromJson(typeJson) : legacy.toType((m['color'] as num?)?.toInt() ?? 0xFFFFFFFF),
      anim: StudioTextAnim.fromJson((m['anim'] as Map?)?.cast<String, dynamic>()),
      templateId: m['templateId'] as String?,
      words: [for (final w in (m['words'] as List? ?? const [])) StudioWord.fromJson((w as Map).cast<String, dynamic>())],
      lang: m['lang'] as String?,
      isCaption: m['isCaption'] == true,
      isSticker: m['isSticker'] == true,
    );
  }
}

/// A picture-in-picture layer: a photo or video placed over the main track.
class StudioOverlay {
  final String id;
  final String path;
  final bool isImage;
  final int sourceDurationMs;
  final int sourceWidth;
  final int sourceHeight;
  final bool hasAudio;

  /// Source trim (video).
  final int startMs;
  final int endMs;

  /// Timeline start and, for photos, how long it shows.
  final int offsetMs;
  final int imageDurationMs;

  /// Center, -1..1 (y down), like text layers.
  final double x;
  final double y;

  /// Width as a fraction of the canvas width.
  final double scale;
  final double rotation;
  final double opacity;
  final double volume;
  final bool muted;

  const StudioOverlay({
    required this.id,
    required this.path,
    required this.isImage,
    required this.sourceDurationMs,
    required this.sourceWidth,
    required this.sourceHeight,
    this.hasAudio = false,
    this.startMs = 0,
    this.endMs = 0,
    this.offsetMs = 0,
    this.imageDurationMs = 3000,
    this.x = 0.45,
    this.y = -0.45,
    this.scale = 0.4,
    this.rotation = 0,
    this.opacity = 1,
    this.volume = 1,
    this.muted = false,
  });

  factory StudioOverlay.fromClip(StudioClip c, {required int offsetMs, int? maxMs}) {
    final src = c.isImage ? 0 : c.endMs - c.startMs;
    final int end = c.isImage ? 0 : c.startMs + (maxMs == null ? src : math.min(src, maxMs));
    return StudioOverlay(
      id: _uuid.v4(),
      path: c.path,
      isImage: c.isImage,
      sourceDurationMs: c.sourceDurationMs,
      sourceWidth: c.sourceWidth,
      sourceHeight: c.sourceHeight,
      hasAudio: c.hasAudio,
      startMs: c.startMs,
      endMs: end,
      offsetMs: offsetMs,
      imageDurationMs: maxMs == null ? 3000 : math.min(3000, maxMs).toInt(),
    );
  }

  int get durationMs => isImage ? imageDurationMs : endMs - startMs;
  int get endOnTimeline => offsetMs + durationMs;

  /// Source width / height.
  double get aspect => sourceWidth <= 0 || sourceHeight <= 0 ? 16 / 9 : sourceWidth / sourceHeight;

  StudioOverlay copyWith({
    int? startMs,
    int? endMs,
    int? offsetMs,
    int? imageDurationMs,
    double? x,
    double? y,
    double? scale,
    double? rotation,
    double? opacity,
    double? volume,
    bool? muted,
  }) =>
      StudioOverlay(
        id: id,
        path: path,
        isImage: isImage,
        sourceDurationMs: sourceDurationMs,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        hasAudio: hasAudio,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        offsetMs: offsetMs ?? this.offsetMs,
        imageDurationMs: imageDurationMs ?? this.imageDurationMs,
        x: x ?? this.x,
        y: y ?? this.y,
        scale: scale ?? this.scale,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
        volume: volume ?? this.volume,
        muted: muted ?? this.muted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'isImage': isImage,
        'sourceDurationMs': sourceDurationMs,
        'sourceWidth': sourceWidth,
        'sourceHeight': sourceHeight,
        'hasAudio': hasAudio,
        'startMs': startMs,
        'endMs': endMs,
        'offsetMs': offsetMs,
        'imageDurationMs': imageDurationMs,
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
        'opacity': opacity,
        'volume': volume,
        'muted': muted,
      };

  factory StudioOverlay.fromJson(Map<String, dynamic> m) {
    double d(String k, double def) => (m[k] as num?)?.toDouble() ?? def;
    int i(String k, int def) => (m[k] as num?)?.toInt() ?? def;
    return StudioOverlay(
      id: m['id'] as String,
      path: m['path'] as String,
      isImage: m['isImage'] == true,
      sourceDurationMs: i('sourceDurationMs', 0),
      sourceWidth: i('sourceWidth', 0),
      sourceHeight: i('sourceHeight', 0),
      hasAudio: m['hasAudio'] == true,
      startMs: i('startMs', 0),
      endMs: i('endMs', 0),
      offsetMs: i('offsetMs', 0),
      imageDurationMs: i('imageDurationMs', 3000),
      x: d('x', 0.45),
      y: d('y', -0.45),
      scale: d('scale', 0.4),
      rotation: d('rotation', 0),
      opacity: d('opacity', 1),
      volume: d('volume', 1),
      muted: m['muted'] == true,
    );
  }
}

/// A timed visual effect over the whole frame (`StudioEffects` catalog),
/// baked into exports by the native Studio FX shader.
class StudioEffect {
  final String id;
  final String effectId;
  final int startMs;
  final int endMs;
  final double amount;

  const StudioEffect({required this.id, required this.effectId, required this.startMs, required this.endMs, this.amount = 0.7});

  factory StudioEffect.create({required String effectId, required int startMs, required int endMs, double amount = 0.7}) =>
      StudioEffect(id: _uuid.v4(), effectId: effectId, startMs: startMs, endMs: endMs, amount: amount);

  StudioEffect copyWith({String? effectId, int? startMs, int? endMs, double? amount}) => StudioEffect(
        id: id,
        effectId: effectId ?? this.effectId,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        amount: amount ?? this.amount,
      );

  Map<String, dynamic> toJson() => {'id': id, 'effectId': effectId, 'startMs': startMs, 'endMs': endMs, 'amount': amount};

  factory StudioEffect.fromJson(Map<String, dynamic> m) => StudioEffect(
        id: m['id'] as String,
        effectId: m['effectId'] as String? ?? 'blur',
        startMs: (m['startMs'] as num?)?.toInt() ?? 0,
        endMs: (m['endMs'] as num?)?.toInt() ?? 0,
        amount: (m['amount'] as num?)?.toDouble() ?? 0.7,
      );
}

/// Extra audio mixed under the video: music, voice-over or audio extracted
/// from a clip.
class StudioAudio {
  final String id;
  final String path;
  final String title;
  final int sourceDurationMs;
  final int startMs;
  final int endMs;
  final int offsetMs;
  final double volume;

  /// Beats found in the source (source ms).
  final List<int> beatsMs;
  final double bpm;

  const StudioAudio({
    required this.id,
    required this.path,
    required this.title,
    required this.sourceDurationMs,
    required this.startMs,
    required this.endMs,
    required this.offsetMs,
    this.volume = 1,
    this.beatsMs = const [],
    this.bpm = 0,
  });

  factory StudioAudio.create({
    required String path,
    required String title,
    required int durationMs,
    int startMs = 0,
    int? endMs,
    int offsetMs = 0,
  }) =>
      StudioAudio(
        id: _uuid.v4(),
        path: path,
        title: title,
        sourceDurationMs: durationMs,
        startMs: startMs,
        endMs: endMs ?? durationMs,
        offsetMs: offsetMs,
      );

  int get durationMs => endMs - startMs;

  /// Beats on the output timeline, inside this track's trim.
  List<int> get timelineBeats => [
        for (final b in beatsMs)
          if (b >= startMs && b < endMs) offsetMs + b - startMs,
      ];

  StudioAudio copyWith({int? startMs, int? endMs, int? offsetMs, double? volume, String? title, List<int>? beatsMs, double? bpm}) => StudioAudio(
        id: id,
        path: path,
        title: title ?? this.title,
        sourceDurationMs: sourceDurationMs,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        offsetMs: offsetMs ?? this.offsetMs,
        volume: volume ?? this.volume,
        beatsMs: beatsMs ?? this.beatsMs,
        bpm: bpm ?? this.bpm,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'title': title,
        'sourceDurationMs': sourceDurationMs,
        'startMs': startMs,
        'endMs': endMs,
        'offsetMs': offsetMs,
        'volume': volume,
        if (beatsMs.isNotEmpty) 'beatsMs': beatsMs,
        if (bpm > 0) 'bpm': bpm,
      };

  factory StudioAudio.fromJson(Map<String, dynamic> m) => StudioAudio(
        id: m['id'] as String,
        path: m['path'] as String,
        title: m['title'] as String? ?? 'Audio',
        sourceDurationMs: (m['sourceDurationMs'] as num?)?.toInt() ?? 0,
        startMs: (m['startMs'] as num?)?.toInt() ?? 0,
        endMs: (m['endMs'] as num?)?.toInt() ?? 0,
        offsetMs: (m['offsetMs'] as num?)?.toInt() ?? 0,
        volume: (m['volume'] as num?)?.toDouble() ?? 1,
        beatsMs: [for (final b in (m['beatsMs'] as List? ?? const [])) (b as num).toInt()],
        bpm: (m['bpm'] as num?)?.toDouble() ?? 0,
      );
}

/// A saved Studio edit: the timeline plus everything layered on it.
class StudioProject {
  final String id;
  final String title;
  final bool isPhoto;
  final DateTime createdAt;
  final DateTime updatedAt;
  final StudioAspect aspect;
  final List<StudioClip> clips;
  final List<StudioText> texts;
  final List<StudioAudio> audios;
  final List<StudioEffect> effects;
  final List<StudioOverlay> overlays;

  /// Output time of the cover frame.
  final int coverMs;
  final String? thumbnailPath;

  /// Short side picked in the export sheet (0 = best for the media).
  final int exportShortSide;

  /// Set when this project remixes someone's post.
  final RemixSource? remixOf;

  const StudioProject({
    required this.id,
    required this.title,
    required this.isPhoto,
    required this.createdAt,
    required this.updatedAt,
    this.aspect = StudioAspect.original,
    this.clips = const [],
    this.texts = const [],
    this.audios = const [],
    this.effects = const [],
    this.overlays = const [],
    this.coverMs = 0,
    this.thumbnailPath,
    this.exportShortSide = 0,
    this.remixOf,
  });

  factory StudioProject.create({required bool isPhoto, List<StudioClip> clips = const [], int exportShortSide = 0, RemixSource? remixOf}) {
    final now = DateTime.now();
    return StudioProject(
      id: _uuid.v4(),
      title: isPhoto ? 'Photo edit' : 'Video project',
      isPhoto: isPhoto,
      createdAt: now,
      updatedAt: now,
      aspect: StudioAspect.original,
      clips: clips,
      exportShortSide: exportShortSide,
      remixOf: remixOf,
    );
  }

  int get durationMs => clips.fold(0, (sum, c) => sum + c.outDurationMs);

  /// Output start of clip [index].
  int clipStartMs(int index) {
    var t = 0;
    for (var i = 0; i < index && i < clips.length; i++) {
      t += clips[i].outDurationMs;
    }
    return t;
  }

  /// Clip index under output time [ms] (last clip when past the end).
  int clipIndexAt(int ms) {
    var t = 0;
    for (var i = 0; i < clips.length; i++) {
      final d = clips[i].outDurationMs;
      if (ms < t + d) return i;
      t += d;
    }
    return clips.isEmpty ? -1 : clips.length - 1;
  }

  /// Canvas width / height.
  double get canvasAspect {
    if (aspect != StudioAspect.original) return aspect.ratio;
    if (clips.isEmpty) return 9 / 16;
    return clips.first.displayAspect;
  }

  /// Highest frame rate among the clips (what an export can keep).
  double get maxSourceFps => clips.where((c) => !c.isImage).fold(0.0, (m, c) => math.max(m, c.sourceFps));

  /// Largest source short side (what an export can keep without upscaling).
  int get maxSourceShortSide =>
      clips.fold(0, (m, c) => math.max(m, math.min(c.sourceWidth, c.sourceHeight)));

  StudioProject copyWith({
    String? title,
    StudioAspect? aspect,
    List<StudioClip>? clips,
    List<StudioText>? texts,
    List<StudioAudio>? audios,
    List<StudioEffect>? effects,
    List<StudioOverlay>? overlays,
    int? coverMs,
    String? thumbnailPath,
    int? exportShortSide,
    DateTime? updatedAt,
  }) =>
      StudioProject(
        id: id,
        title: title ?? this.title,
        isPhoto: isPhoto,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        aspect: aspect ?? this.aspect,
        clips: clips ?? this.clips,
        texts: texts ?? this.texts,
        audios: audios ?? this.audios,
        effects: effects ?? this.effects,
        overlays: overlays ?? this.overlays,
        coverMs: coverMs ?? this.coverMs,
        thumbnailPath: thumbnailPath ?? this.thumbnailPath,
        exportShortSide: exportShortSide ?? this.exportShortSide,
        remixOf: remixOf,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isPhoto': isPhoto,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'aspect': aspect.name,
        'clips': clips.map((c) => c.toJson()).toList(),
        'texts': texts.map((t) => t.toJson()).toList(),
        'audios': audios.map((a) => a.toJson()).toList(),
        'effects': effects.map((e) => e.toJson()).toList(),
        'overlays': overlays.map((o) => o.toJson()).toList(),
        'coverMs': coverMs,
        'thumbnailPath': thumbnailPath,
        'exportShortSide': exportShortSide,
        if (remixOf != null) 'remixOf': remixOf!.toJson(),
      };

  factory StudioProject.fromJson(Map<String, dynamic> m) => StudioProject(
        id: m['id'] as String,
        title: m['title'] as String? ?? 'Project',
        isPhoto: m['isPhoto'] == true,
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['createdAt'] as num?)?.toInt() ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch((m['updatedAt'] as num?)?.toInt() ?? 0),
        aspect: StudioAspect.values.firstWhere((a) => a.name == m['aspect'], orElse: () => StudioAspect.original),
        clips: [for (final c in (m['clips'] as List? ?? const [])) StudioClip.fromJson((c as Map).cast<String, dynamic>())],
        texts: [for (final t in (m['texts'] as List? ?? const [])) StudioText.fromJson((t as Map).cast<String, dynamic>())],
        audios: [for (final a in (m['audios'] as List? ?? const [])) StudioAudio.fromJson((a as Map).cast<String, dynamic>())],
        effects: [for (final e in (m['effects'] as List? ?? const [])) StudioEffect.fromJson((e as Map).cast<String, dynamic>())],
        overlays: [for (final o in (m['overlays'] as List? ?? const [])) StudioOverlay.fromJson((o as Map).cast<String, dynamic>())],
        coverMs: (m['coverMs'] as num?)?.toInt() ?? 0,
        thumbnailPath: m['thumbnailPath'] as String?,
        remixOf: RemixSource.fromJson(m['remixOf']),
        exportShortSide: (m['exportShortSide'] as num?)?.toInt() ?? 0,
      );
}
