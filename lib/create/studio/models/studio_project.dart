import 'dart:math' as math;

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Where the finished export goes after the editor.
enum StudioTarget { post, story, device }

/// Canvas shape of the project. `original` follows the first clip.
enum StudioAspect {
  original('Original', 0),
  portrait('9:16', 9 / 16),
  square('1:1', 1),
  feed('4:5', 4 / 5),
  classic('3:4', 3 / 4),
  landscape('16:9', 16 / 9);

  final String label;
  final double ratio;
  const StudioAspect(this.label, this.ratio);
}

/// Per-clip color adjustments, each -1..1 (0 = untouched).
class StudioAdjust {
  final double brightness;
  final double contrast;
  final double saturation;
  final double exposure;
  final double warmth;
  final double tint;
  final double fade;

  const StudioAdjust({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.exposure = 0,
    this.warmth = 0,
    this.tint = 0,
    this.fade = 0,
  });

  static const keys = ['brightness', 'contrast', 'saturation', 'exposure', 'warmth', 'tint', 'fade'];

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
  final String filterId;
  final double filterIntensity;
  final StudioAdjust adjust;
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
    this.filterId = 'none',
    this.filterIntensity = 1,
    this.adjust = const StudioAdjust(),
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
    String? filterId,
    double? filterIntensity,
    StudioAdjust? adjust,
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
        filterId: filterId ?? this.filterId,
        filterIntensity: filterIntensity ?? this.filterIntensity,
        adjust: adjust ?? this.adjust,
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
        'filterId': filterId,
        'filterIntensity': filterIntensity,
        'adjust': adjust.toJson(),
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
        filterId: m['filterId'] as String? ?? 'none',
        filterIntensity: (m['filterIntensity'] as num?)?.toDouble() ?? 1,
        adjust: StudioAdjust.fromJson((m['adjust'] as Map?)?.cast<String, dynamic>()),
        crop: StudioCrop.fromJson((m['crop'] as Map?)?.cast<String, dynamic>()),
        rotation: (m['rotation'] as num?)?.toInt() ?? 0,
        flipH: m['flipH'] == true,
        flipV: m['flipV'] == true,
        zoom: (m['zoom'] as num?)?.toDouble() ?? 1,
        fill: m['fill'] == true,
      );
}

/// Visual style of a text layer or caption.
enum StudioTextStyle {
  plain('Plain'),
  box('Box'),
  outline('Outline'),
  glow('Glow'),
  bold('Bold pop');

  final String label;
  const StudioTextStyle(this.label);
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
  final int color;
  final StudioTextStyle style;
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
    this.color = 0xFFFFFFFF,
    this.style = StudioTextStyle.plain,
    this.isCaption = false,
    this.isSticker = false,
  });

  factory StudioText.create({
    required String text,
    required int startMs,
    required int endMs,
    bool isCaption = false,
    bool isSticker = false,
    StudioTextStyle style = StudioTextStyle.plain,
  }) =>
      StudioText(
        id: _uuid.v4(),
        text: text,
        startMs: startMs,
        endMs: endMs,
        y: isCaption ? 0.62 : 0,
        size: isSticker ? 0.16 : (isCaption ? 0.055 : 0.07),
        style: isCaption ? StudioTextStyle.box : style,
        isCaption: isCaption,
        isSticker: isSticker,
      );

  StudioText copyWith({
    String? text,
    int? startMs,
    int? endMs,
    double? x,
    double? y,
    double? size,
    int? color,
    StudioTextStyle? style,
  }) =>
      StudioText(
        id: id,
        text: text ?? this.text,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        x: x ?? this.x,
        y: y ?? this.y,
        size: size ?? this.size,
        color: color ?? this.color,
        style: style ?? this.style,
        isCaption: isCaption,
        isSticker: isSticker,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'startMs': startMs,
        'endMs': endMs,
        'x': x,
        'y': y,
        'size': size,
        'color': color,
        'style': style.name,
        'isCaption': isCaption,
        'isSticker': isSticker,
      };

  factory StudioText.fromJson(Map<String, dynamic> m) => StudioText(
        id: m['id'] as String,
        text: m['text'] as String? ?? '',
        startMs: (m['startMs'] as num?)?.toInt() ?? 0,
        endMs: (m['endMs'] as num?)?.toInt() ?? 0,
        x: (m['x'] as num?)?.toDouble() ?? 0,
        y: (m['y'] as num?)?.toDouble() ?? 0,
        size: (m['size'] as num?)?.toDouble() ?? 0.07,
        color: (m['color'] as num?)?.toInt() ?? 0xFFFFFFFF,
        style: StudioTextStyle.values.firstWhere((s) => s.name == m['style'], orElse: () => StudioTextStyle.plain),
        isCaption: m['isCaption'] == true,
        isSticker: m['isSticker'] == true,
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

  const StudioAudio({
    required this.id,
    required this.path,
    required this.title,
    required this.sourceDurationMs,
    required this.startMs,
    required this.endMs,
    required this.offsetMs,
    this.volume = 1,
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

  StudioAudio copyWith({int? startMs, int? endMs, int? offsetMs, double? volume, String? title}) => StudioAudio(
        id: id,
        path: path,
        title: title ?? this.title,
        sourceDurationMs: sourceDurationMs,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        offsetMs: offsetMs ?? this.offsetMs,
        volume: volume ?? this.volume,
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

  /// Output time of the cover frame.
  final int coverMs;
  final String? thumbnailPath;

  /// Short side picked in the export sheet (0 = best for the media).
  final int exportShortSide;

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
    this.coverMs = 0,
    this.thumbnailPath,
    this.exportShortSide = 0,
  });

  factory StudioProject.create({required bool isPhoto, List<StudioClip> clips = const [], int exportShortSide = 0}) {
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
        coverMs: coverMs ?? this.coverMs,
        thumbnailPath: thumbnailPath ?? this.thumbnailPath,
        exportShortSide: exportShortSide ?? this.exportShortSide,
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
        'coverMs': coverMs,
        'thumbnailPath': thumbnailPath,
        'exportShortSide': exportShortSide,
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
        coverMs: (m['coverMs'] as num?)?.toInt() ?? 0,
        thumbnailPath: m['thumbnailPath'] as String?,
        exportShortSide: (m['exportShortSide'] as num?)?.toInt() ?? 0,
      );
}
