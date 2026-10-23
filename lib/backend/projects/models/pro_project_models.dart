import 'package:uuid/uuid.dart';
import '../../mask_engine/universal_mask_models.dart';
import 'keyframe_models.dart';
import 'effect_models.dart';

enum MediaType { video, audio, image, text, generator, adjustment }
enum TrackType { video, audio, adjustment }
enum TransitionType { none, crossDissolve, dipToBlack, dipToWhite, wipe, fade, push, slide, zoom }

class ProProject {
  final String id;
  final String title;
  final DateTime createdAt;
  DateTime updatedAt;
  final ProjectSettings settings;
  final List<Sequence> sequences;
  String? activeSequenceId;

  ProProject({
    String? id,
    required this.title,
    required this.settings,
    List<Sequence>? sequences,
    this.activeSequenceId,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        sequences = sequences ?? [];

  ProProject copyWith({
    String? title,
    DateTime? updatedAt,
    ProjectSettings? settings,
    List<Sequence>? sequences,
    String? activeSequenceId,
  }) {
    return ProProject(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      settings: settings ?? this.settings,
      sequences: sequences ?? this.sequences,
      activeSequenceId: activeSequenceId ?? this.activeSequenceId,
    );
  }
}

class ProjectSettings {
  final int width;
  final int height;
  final double frameRate;
  final String colorSpace; // 'Rec.709', 'HDR'
  
  const ProjectSettings({
    required this.width,
    required this.height,
    required this.frameRate,
    this.colorSpace = 'Rec.709',
  });

  Map<String, dynamic> toJson() => {
    'width': width,
    'height': height,
    'frameRate': frameRate,
    'colorSpace': colorSpace,
  };

  factory ProjectSettings.fromJson(Map<String, dynamic> json) => ProjectSettings(
    width: json['width'] ?? 1080,
    height: json['height'] ?? 1920,
    frameRate: (json['frameRate'] ?? 30.0).toDouble(),
    colorSpace: json['colorSpace'] ?? 'Rec.709',
  );
}

class Sequence {
  final String id;
  final String name;
  final ProjectSettings settings;
  final List<Track> tracks;
  final List<Marker> markers;

  Sequence({
    String? id,
    required this.name,
    required this.settings,
    List<Track>? tracks,
    List<Marker>? markers,
  })  : id = id ?? const Uuid().v4(),
        tracks = tracks ?? [],
        markers = markers ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'settings': settings.toJson(),
    'tracks': tracks.map((t) => t.toJson()).toList(),
    // 'markers': markers.map((m) => m.toJson()).toList(),
  };

  factory Sequence.fromJson(Map<String, dynamic> json) => Sequence(
    id: json['id'],
    name: json['name'] ?? '',
    settings: json['settings'] != null ? ProjectSettings.fromJson(json['settings']) : const ProjectSettings(width: 1080, height: 1920, frameRate: 30),
    tracks: (json['tracks'] as List<dynamic>?)?.map((t) => Track.fromJson(t)).toList(),
  );
}

class Track {
  final String id;
  final String name;
  final TrackType type;
  final bool isLocked;
  final bool isHidden;
  final List<Clip> clips;
  final List<TimelineTransition> transitions;

  Track({
    String? id,
    required this.name,
    required this.type,
    this.isLocked = false,
    this.isHidden = false,
    List<Clip>? clips,
    List<TimelineTransition>? transitions,
  })  : id = id ?? const Uuid().v4(),
        clips = clips ?? [],
        transitions = transitions ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.index,
    'isLocked': isLocked,
    'isHidden': isHidden,
    'clips': clips.map((c) => c.toJson()).toList(),
    'transitions': transitions.map((t) => t.toJson()).toList(),
  };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: json['id'],
    name: json['name'] ?? '',
    type: TrackType.values[json['type'] ?? 0],
    isLocked: json['isLocked'] ?? false,
    isHidden: json['isHidden'] ?? false,
    clips: (json['clips'] as List<dynamic>?)?.map((c) => Clip.fromJson(c)).toList(),
    transitions: (json['transitions'] as List<dynamic>?)?.map((t) => TimelineTransition.fromJson(t)).toList(),
  );
}

class Clip {
  final String id;
  final String sourceMediaId;
  final MediaType type;
  
  // Timeline timing
  double startTime; // Where it starts on the timeline
  double duration; // How long it plays on the timeline
  
  // Source timing
  double sourceStart; // Where in the source media it begins

  // Properties
  TransformState transform;
  BlendMode blendMode;
  ColorState color; // Base Grade
  List<ColorState> secondaryColorStates; // Secondary masked grades
  AudioState audio;
  
  // Effects & Masks
  List<EffectState> effects;
  List<UniversalMask> masks;
  List<Keyframe> keyframes;
  List<TrackingData> tracking;

  Clip({
    String? id,
    required this.sourceMediaId,
    required this.type,
    required this.startTime,
    required this.duration,
    required this.sourceStart,
    TransformState? transform,
    this.blendMode = BlendMode.normal,
    ColorState? color,
    List<ColorState>? secondaryColorStates,
    AudioState? audio,
    List<EffectState>? effects,
    List<UniversalMask>? masks,
    List<Keyframe>? keyframes,
    List<TrackingData>? tracking,
  })  : id = id ?? const Uuid().v4(),
        transform = transform ?? TransformState(),
        color = color ?? ColorState(),
        secondaryColorStates = secondaryColorStates ?? [],
        audio = audio ?? AudioState(),
        effects = effects ?? [],
        masks = masks ?? [],
        keyframes = keyframes ?? [],
        tracking = tracking ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceMediaId': sourceMediaId,
    'type': type.index,
    'startTime': startTime,
    'duration': duration,
    'sourceStart': sourceStart,
    'transform': transform.toJson(),
    'blendMode': blendMode.index,
    'color': color.toJson(),
    'secondaryColorStates': secondaryColorStates.map((c) => c.toJson()).toList(),
    'audio': audio.toJson(),
    'effects': effects.map((e) => e.toJson()).toList(),
    'masks': masks.map((m) => m.toJson()).toList(),
    'keyframes': keyframes.map((k) => k.toJson()).toList(),
    'tracking': tracking.map((t) => t.toJson()).toList(),
  };

  factory Clip.fromJson(Map<String, dynamic> json) => Clip(
    id: json['id'],
    sourceMediaId: json['sourceMediaId'] ?? '',
    type: MediaType.values[json['type'] ?? 0],
    startTime: (json['startTime'] ?? 0.0).toDouble(),
    duration: (json['duration'] ?? 1.0).toDouble(),
    sourceStart: (json['sourceStart'] ?? 0.0).toDouble(),
    transform: json['transform'] != null ? TransformState.fromJson(json['transform']) : null,
    blendMode: json['blendMode'] != null ? BlendMode.values[json['blendMode']] : BlendMode.normal,
    color: json['color'] != null ? ColorState.fromJson(json['color']) : null,
    secondaryColorStates: (json['secondaryColorStates'] as List<dynamic>?)?.map((c) => ColorState.fromJson(c)).toList(),
    audio: json['audio'] != null ? AudioState.fromJson(json['audio']) : null,
    effects: (json['effects'] as List<dynamic>?)?.map((e) => EffectState.fromJson(e)).toList(),
    masks: (json['masks'] as List<dynamic>?)?.map((m) => UniversalMask.fromJson(m)).toList(),
    keyframes: (json['keyframes'] as List<dynamic>?)?.map((k) => Keyframe.fromJson(k)).toList(),
    tracking: (json['tracking'] as List<dynamic>?)?.map((t) => TrackingData.fromJson(t)).toList(),
  );
}

class TransformState {
  double positionX;
  double positionY;
  double scaleX;
  double scaleY;
  double rotation;
  double opacity;

  TransformState({
    this.positionX = 0,
    this.positionY = 0,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.rotation = 0,
    this.opacity = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'positionX': positionX,
    'positionY': positionY,
    'scaleX': scaleX,
    'scaleY': scaleY,
    'rotation': rotation,
    'opacity': opacity,
  };

  factory TransformState.fromJson(Map<String, dynamic> json) => TransformState(
    positionX: (json['positionX'] ?? 0.0).toDouble(),
    positionY: (json['positionY'] ?? 0.0).toDouble(),
    scaleX: (json['scaleX'] ?? 1.0).toDouble(),
    scaleY: (json['scaleY'] ?? 1.0).toDouble(),
    rotation: (json['rotation'] ?? 0.0).toDouble(),
    opacity: (json['opacity'] ?? 1.0).toDouble(),
  );
}

class CurveNode {
  double x;
  double y;
  CurveNode(this.x, this.y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  factory CurveNode.fromJson(Map<String, dynamic> json) => CurveNode(
    (json['x'] ?? 0.0).toDouble(),
    (json['y'] ?? 0.0).toDouble(),
  );
}

class ColorCurve {
  List<CurveNode> nodes;
  ColorCurve({List<CurveNode>? nodes}) : nodes = nodes ?? [CurveNode(0, 0), CurveNode(1, 1)];

  Map<String, dynamic> toJson() => {
    'nodes': nodes.map((n) => n.toJson()).toList(),
  };

  factory ColorCurve.fromJson(Map<String, dynamic> json) {
    if (json['nodes'] == null) return ColorCurve();
    return ColorCurve(
      nodes: (json['nodes'] as List).map((n) => CurveNode.fromJson(n)).toList(),
    );
  }
}

class ColorWheel {
  double hue;
  double saturation;
  double luminance;
  ColorWheel({this.hue = 0, this.saturation = 0, this.luminance = 0});

  Map<String, dynamic> toJson() => {
    'hue': hue,
    'saturation': saturation,
    'luminance': luminance,
  };

  factory ColorWheel.fromJson(Map<String, dynamic> json) => ColorWheel(
    hue: (json['hue'] ?? 0.0).toDouble(),
    saturation: (json['saturation'] ?? 0.0).toDouble(),
    luminance: (json['luminance'] ?? 0.0).toDouble(),
  );
}

class HslGroup {
  double hue;
  double saturation;
  double luminance;
  HslGroup({this.hue = 0, this.saturation = 0, this.luminance = 0});

  Map<String, dynamic> toJson() => {
    'hue': hue,
    'saturation': saturation,
    'luminance': luminance,
  };

  factory HslGroup.fromJson(Map<String, dynamic> json) => HslGroup(
    hue: (json['hue'] ?? 0.0).toDouble(),
    saturation: (json['saturation'] ?? 0.0).toDouble(),
    luminance: (json['luminance'] ?? 0.0).toDouble(),
  );
}

class LutStage {
  String id;
  String name;
  String path;
  double intensity;
  bool isEnabled;

  LutStage({
    required this.id,
    required this.name,
    required this.path,
    this.intensity = 1.0,
    this.isEnabled = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'intensity': intensity,
    'isEnabled': isEnabled,
  };

  factory LutStage.fromJson(Map<String, dynamic> json) => LutStage(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    path: json['path'] ?? '',
    intensity: (json['intensity'] ?? 1.0).toDouble(),
    isEnabled: json['isEnabled'] ?? true,
  );
}

class ColorState {
  // Basic Correction
  double exposure;
  double contrast;
  double highlights;
  double shadows;
  double whites;
  double blacks;
  double temperature;
  double tint;
  double saturation;
  double vibrance;
  
  // Advanced Details
  double clarity;
  double texture;
  double dehaze;
  double sharpening;
  double fade;
  double grain;
  double vignette;
  
  // HDR Workflow
  double hdrSpecular;
  double hdrLight;
  double hdrGlobal;

  // Curves
  ColorCurve masterCurve;
  ColorCurve redCurve;
  ColorCurve greenCurve;
  ColorCurve blueCurve;

  // Wheels
  ColorWheel lift;
  ColorWheel gamma;
  ColorWheel gain;
  ColorWheel offset;

  // HSL
  Map<String, HslGroup> hsl;

  // LUT Stack
  List<LutStage> lutStack;
  
  // Mask linking (Color adjustments can target a specific mask by ID)
  String? targetMaskId;

  ColorState({
    this.exposure = 0,
    this.contrast = 1.0,
    this.highlights = 0,
    this.shadows = 0,
    this.whites = 0,
    this.blacks = 0,
    this.temperature = 0,
    this.tint = 0,
    this.saturation = 1.0,
    this.vibrance = 1.0,
    this.clarity = 0,
    this.texture = 0,
    this.dehaze = 0,
    this.sharpening = 0,
    this.fade = 0,
    this.grain = 0,
    this.vignette = 0,
    this.hdrSpecular = 0,
    this.hdrLight = 0,
    this.hdrGlobal = 0,
    this.targetMaskId,
    ColorCurve? masterCurve,
    ColorCurve? redCurve,
    ColorCurve? greenCurve,
    ColorCurve? blueCurve,
    ColorWheel? lift,
    ColorWheel? gamma,
    ColorWheel? gain,
    ColorWheel? offset,
    Map<String, HslGroup>? hsl,
    List<LutStage>? lutStack,
  })  : masterCurve = masterCurve ?? ColorCurve(),
        redCurve = redCurve ?? ColorCurve(),
        greenCurve = greenCurve ?? ColorCurve(),
        blueCurve = blueCurve ?? ColorCurve(),
        lift = lift ?? ColorWheel(),
        gamma = gamma ?? ColorWheel(),
        gain = gain ?? ColorWheel(),
        offset = offset ?? ColorWheel(),
        hsl = hsl ?? {
          'Red': HslGroup(),
          'Orange': HslGroup(),
          'Yellow': HslGroup(),
          'Green': HslGroup(),
          'Cyan': HslGroup(),
          'Blue': HslGroup(),
          'Purple': HslGroup(),
          'Magenta': HslGroup(),
        },
        lutStack = lutStack ?? [];

  Map<String, dynamic> toJson() => {
    'exposure': exposure,
    'contrast': contrast,
    'highlights': highlights,
    'shadows': shadows,
    'whites': whites,
    'blacks': blacks,
    'temperature': temperature,
    'tint': tint,
    'saturation': saturation,
    'vibrance': vibrance,
    'clarity': clarity,
    'texture': texture,
    'dehaze': dehaze,
    'sharpening': sharpening,
    'fade': fade,
    'grain': grain,
    'vignette': vignette,
    'hdrSpecular': hdrSpecular,
    'hdrLight': hdrLight,
    'hdrGlobal': hdrGlobal,
    'targetMaskId': targetMaskId,
    'masterCurve': masterCurve.toJson(),
    'redCurve': redCurve.toJson(),
    'greenCurve': greenCurve.toJson(),
    'blueCurve': blueCurve.toJson(),
    'lift': lift.toJson(),
    'gamma': gamma.toJson(),
    'gain': gain.toJson(),
    'offset': offset.toJson(),
    'hsl': hsl.map((k, v) => MapEntry(k, v.toJson())),
    'lutStack': lutStack.map((l) => l.toJson()).toList(),
  };

  factory ColorState.fromJson(Map<String, dynamic> json) {
    return ColorState(
      exposure: (json['exposure'] ?? 0.0).toDouble(),
      contrast: (json['contrast'] ?? 1.0).toDouble(),
      highlights: (json['highlights'] ?? 0.0).toDouble(),
      shadows: (json['shadows'] ?? 0.0).toDouble(),
      whites: (json['whites'] ?? 0.0).toDouble(),
      blacks: (json['blacks'] ?? 0.0).toDouble(),
      temperature: (json['temperature'] ?? 0.0).toDouble(),
      tint: (json['tint'] ?? 0.0).toDouble(),
      saturation: (json['saturation'] ?? 1.0).toDouble(),
      vibrance: (json['vibrance'] ?? 1.0).toDouble(),
      clarity: (json['clarity'] ?? 0.0).toDouble(),
      texture: (json['texture'] ?? 0.0).toDouble(),
      dehaze: (json['dehaze'] ?? 0.0).toDouble(),
      sharpening: (json['sharpening'] ?? 0.0).toDouble(),
      fade: (json['fade'] ?? 0.0).toDouble(),
      grain: (json['grain'] ?? 0.0).toDouble(),
      vignette: (json['vignette'] ?? 0.0).toDouble(),
      hdrSpecular: (json['hdrSpecular'] ?? 0.0).toDouble(),
      hdrLight: (json['hdrLight'] ?? 0.0).toDouble(),
      hdrGlobal: (json['hdrGlobal'] ?? 0.0).toDouble(),
      targetMaskId: json['targetMaskId'],
      masterCurve: json['masterCurve'] != null ? ColorCurve.fromJson(json['masterCurve']) : null,
      redCurve: json['redCurve'] != null ? ColorCurve.fromJson(json['redCurve']) : null,
      greenCurve: json['greenCurve'] != null ? ColorCurve.fromJson(json['greenCurve']) : null,
      blueCurve: json['blueCurve'] != null ? ColorCurve.fromJson(json['blueCurve']) : null,
      lift: json['lift'] != null ? ColorWheel.fromJson(json['lift']) : null,
      gamma: json['gamma'] != null ? ColorWheel.fromJson(json['gamma']) : null,
      gain: json['gain'] != null ? ColorWheel.fromJson(json['gain']) : null,
      offset: json['offset'] != null ? ColorWheel.fromJson(json['offset']) : null,
      hsl: (json['hsl'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, HslGroup.fromJson(v)),
      ),
      lutStack: (json['lutStack'] as List<dynamic>?)?.map((v) => LutStage.fromJson(v)).toList(),
    );
  }
}

class ColorPreset {
  final String id;
  final String name;
  final String category;
  final ColorState state;

  ColorPreset({
    String? id,
    required this.name,
    this.category = 'Custom',
    required this.state,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'state': state.toJson(),
  };

  factory ColorPreset.fromJson(Map<String, dynamic> json) => ColorPreset(
    id: json['id'],
    name: json['name'] ?? 'Preset',
    category: json['category'] ?? 'Custom',
    state: ColorState.fromJson(json['state'] ?? {}),
  );
}

class AudioState {
  double volume; // db
  double pan; // -1 to 1
  bool isMuted;

  AudioState({
    this.volume = 0,
    this.pan = 0,
    this.isMuted = false,
  });

  Map<String, dynamic> toJson() => {
    'volume': volume,
    'pan': pan,
    'isMuted': isMuted,
  };

  factory AudioState.fromJson(Map<String, dynamic> json) => AudioState(
    volume: (json['volume'] ?? 0.0).toDouble(),
    pan: (json['pan'] ?? 0.0).toDouble(),
    isMuted: json['isMuted'] ?? false,
  );
}

class Marker {
  final double time;
  final String name;
  final String color;

  Marker({required this.time, required this.name, this.color = 'blue'});
}

class TimelineTransition {
  final String id;
  final TransitionType type;
  final double duration;
  final Map<String, dynamic> parameters;
  final List<Keyframe> keyframes;
  final Map<String, dynamic> metadata;

  // Represents the timeline relationship
  final String? fromClipId;
  final String? toClipId;

  TimelineTransition({
    String? id,
    required this.type,
    this.duration = 1.0,
    this.parameters = const {},
    this.keyframes = const [],
    this.metadata = const {},
    this.fromClipId,
    this.toClipId,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.index,
    'duration': duration,
    'parameters': parameters,
    'keyframes': keyframes.map((k) => k.toJson()).toList(),
    'metadata': metadata,
    'fromClipId': fromClipId,
    'toClipId': toClipId,
  };

  factory TimelineTransition.fromJson(Map<String, dynamic> json) => TimelineTransition(
    id: json['id'],
    type: TransitionType.values[json['type'] ?? 0],
    duration: (json['duration'] ?? 1.0).toDouble(),
    parameters: json['parameters'] ?? {},
    keyframes: (json['keyframes'] as List<dynamic>?)?.map((k) => Keyframe.fromJson(k)).toList() ?? [],
    metadata: json['metadata'] ?? {},
    fromClipId: json['fromClipId'],
    toClipId: json['toClipId'],
  );
}
