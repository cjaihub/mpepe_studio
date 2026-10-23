import 'package:uuid/uuid.dart';

enum TrackType { video, audio, text, effect }
enum EffectType { color, mask, filter }
enum TransitionType { crossfade, dipToBlack, wipe }

class ClipTransform {
  final double cropX, cropY, cropWidth, cropHeight;
  final double rotationDegrees;
  final double speed;
  final double volume;

  const ClipTransform({
    this.cropX = 0, this.cropY = 0, this.cropWidth = 1, this.cropHeight = 1,
    this.rotationDegrees = 0,
    this.speed = 1.0,
    this.volume = 1.0,
  });

  ClipTransform copyWith({
    double? cropX, double? cropY, double? cropWidth, double? cropHeight,
    double? rotationDegrees, double? speed, double? volume,
  }) {
    return ClipTransform(
      cropX: cropX ?? this.cropX,
      cropY: cropY ?? this.cropY,
      cropWidth: cropWidth ?? this.cropWidth,
      cropHeight: cropHeight ?? this.cropHeight,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
    );
  }

  Map<String, dynamic> toMap() => {
    'cropX': cropX, 'cropY': cropY, 'cropWidth': cropWidth, 'cropHeight': cropHeight,
    'rotationDegrees': rotationDegrees, 'speed': speed, 'volume': volume,
  };

  factory ClipTransform.fromMap(Map<String, dynamic> map) {
    return ClipTransform(
      cropX: map['cropX'] ?? 0.0,
      cropY: map['cropY'] ?? 0.0,
      cropWidth: map['cropWidth'] ?? 1.0,
      cropHeight: map['cropHeight'] ?? 1.0,
      rotationDegrees: map['rotationDegrees'] ?? 0.0,
      speed: map['speed'] ?? 1.0,
      volume: map['volume'] ?? 1.0,
    );
  }
}

class ClipEffect {
  final String id;
  final EffectType type;
  final Map<String, dynamic> parameters;

  ClipEffect({required this.id, required this.type, required this.parameters});

  Map<String, dynamic> toMap() => {
    'id': id, 'type': type.name, 'parameters': parameters,
  };

  factory ClipEffect.fromMap(Map<String, dynamic> map) {
    return ClipEffect(
      id: map['id'],
      type: EffectType.values.byName(map['type']),
      parameters: Map<String, dynamic>.from(map['parameters'] ?? {}),
    );
  }
}

class Clip {
  final String id;
  final String sourceMediaId; // Never destructively modified
  final Duration sourceStartTime;
  final Duration sourceEndTime;
  final Duration timelineStartTime;
  final ClipTransform transform;
  final List<ClipEffect> effects;
  final String? transitionOut;

  Clip({
    String? id,
    required this.sourceMediaId,
    required this.sourceStartTime,
    required this.sourceEndTime,
    required this.timelineStartTime,
    this.transform = const ClipTransform(),
    this.effects = const [],
    this.transitionOut,
  }) : id = id ?? const Uuid().v4();

  Duration get duration => (sourceEndTime - sourceStartTime) * (1 / transform.speed);

  Clip copyWith({
    String? id, String? sourceMediaId,
    Duration? sourceStartTime, Duration? sourceEndTime,
    Duration? timelineStartTime,
    ClipTransform? transform,
    List<ClipEffect>? effects,
    String? transitionOut,
  }) {
    return Clip(
      id: id ?? this.id,
      sourceMediaId: sourceMediaId ?? this.sourceMediaId,
      sourceStartTime: sourceStartTime ?? this.sourceStartTime,
      sourceEndTime: sourceEndTime ?? this.sourceEndTime,
      timelineStartTime: timelineStartTime ?? this.timelineStartTime,
      transform: transform ?? this.transform,
      effects: effects ?? this.effects,
      transitionOut: transitionOut ?? this.transitionOut,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'sourceMediaId': sourceMediaId,
    'sourceStartTime': sourceStartTime.inMilliseconds,
    'sourceEndTime': sourceEndTime.inMilliseconds,
    'timelineStartTime': timelineStartTime.inMilliseconds,
    'transform': transform.toMap(),
    'effects': effects.map((e) => e.toMap()).toList(),
    'transitionOut': transitionOut,
  };

  factory Clip.fromMap(Map<String, dynamic> map) {
    return Clip(
      id: map['id'],
      sourceMediaId: map['sourceMediaId'],
      sourceStartTime: Duration(milliseconds: map['sourceStartTime']),
      sourceEndTime: Duration(milliseconds: map['sourceEndTime']),
      timelineStartTime: Duration(milliseconds: map['timelineStartTime']),
      transform: ClipTransform.fromMap(map['transform']),
      effects: (map['effects'] as List?)?.map((e) => ClipEffect.fromMap(e)).toList() ?? [],
      transitionOut: map['transitionOut'],
    );
  }
}

class Track {
  final String id;
  final TrackType type;
  final List<Clip> clips;
  final bool isMuted;
  final bool isHidden;

  Track({
    String? id,
    required this.type,
    this.clips = const [],
    this.isMuted = false,
    this.isHidden = false,
  }) : id = id ?? const Uuid().v4();

  Track copyWith({
    String? id, TrackType? type, List<Clip>? clips,
    bool? isMuted, bool? isHidden,
  }) {
    return Track(
      id: id ?? this.id,
      type: type ?? this.type,
      clips: clips ?? this.clips,
      isMuted: isMuted ?? this.isMuted,
      isHidden: isHidden ?? this.isHidden,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id, 'type': type.name,
    'clips': clips.map((c) => c.toMap()).toList(),
    'isMuted': isMuted, 'isHidden': isHidden,
  };

  factory Track.fromMap(Map<String, dynamic> map) {
    return Track(
      id: map['id'],
      type: TrackType.values.byName(map['type']),
      clips: (map['clips'] as List?)?.map((c) => Clip.fromMap(c)).toList() ?? [],
      isMuted: map['isMuted'] ?? false,
      isHidden: map['isHidden'] ?? false,
    );
  }
}

class Timeline {
  final List<Track> tracks;

  const Timeline({this.tracks = const []});

  Timeline copyWith({List<Track>? tracks}) {
    return Timeline(tracks: tracks ?? this.tracks);
  }

  Map<String, dynamic> toMap() => {
    'tracks': tracks.map((t) => t.toMap()).toList(),
  };

  factory Timeline.fromMap(Map<String, dynamic> map) {
    return Timeline(
      tracks: (map['tracks'] as List?)?.map((t) => Track.fromMap(t)).toList() ?? [],
    );
  }
}

class VideoProject {
  final String id;
  final String ownerId;
  final String name;
  final Timeline timeline;
  final DateTime updatedAt;
  final Map<String, dynamic> metadata;

  VideoProject({
    String? id,
    required this.ownerId,
    required this.name,
    this.timeline = const Timeline(),
    DateTime? updatedAt,
    this.metadata = const {},
  }) : id = id ?? const Uuid().v4(), updatedAt = updatedAt ?? DateTime.now();

  VideoProject copyWith({
    String? id, String? ownerId, String? name,
    Timeline? timeline, DateTime? updatedAt, Map<String, dynamic>? metadata,
  }) {
    return VideoProject(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      name: name ?? this.name,
      timeline: timeline ?? this.timeline,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id, 'ownerId': ownerId, 'name': name,
    'timeline': timeline.toMap(),
    'updatedAt': updatedAt.toIso8601String(),
    'metadata': metadata,
  };

  factory VideoProject.fromMap(Map<String, dynamic> map) {
    return VideoProject(
      id: map['id'],
      ownerId: map['ownerId'],
      name: map['name'],
      timeline: Timeline.fromMap(map['timeline'] ?? {}),
      updatedAt: DateTime.parse(map['updatedAt']),
      metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
    );
  }
}
