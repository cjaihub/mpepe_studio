import '../projects/models/keyframe_models.dart';

enum MaskType {
  MANUAL, SUBJECT, PERSON, FACE, SKIN, HAIR, EYES, IRIS, EYEBROWS, LIPS, 
  MOUTH, TEETH, NOSE, EARS, BODY, CLOTHING, SKY, BACKGROUND, OBJECT, 
  GROUND, VEHICLE, ANIMAL, FOOD, PLANT, ARCHITECTURE, LUMINANCE, COLOR, 
  DEPTH, CUSTOM
}

enum MaskSourceType {
  manual,
  ai,
  imported,
  generated,
  tracked,
  depth,
  color,
  luminance,
  vector,
  bitmap,
  procedural,
}

enum MaskOperation {
  add, subtract, intersect, exclude, xor, invert, feather, expand, contract, 
  blur, density, opacity, smooth, sharpen, grow, shrink, edge_refine,
}

/// The Canonical Mask Entity.
/// Non-destructive, procedural, and version-controlled.
/// Shared across Photo Studio, Video Studio, Design Studio, AI Editing, etc.
class UniversalMask {
  final String id;
  final String name;
  final String projectId;
  final String mediaId;
  final MaskType maskType;
  final MaskSourceType sourceType;
  final int version;
  final bool enabled;
  final bool visibility;
  final String? parentMaskId;
  
  // Storage References (Compact & Procedural)
  // We do not store every derived mask as a permanently rendered bitmap.
  final String? geometryReference;
  final String? bitmapReference;
  final String? vectorReference;
  
  final String? sourceAssetId;
  final String? sourceClipId;
  
  final Map<String, dynamic> parameters;
  final String? trackingReference;
  final String? modelReference;
  final double confidence;
  final List<TrackingData> tracking;
  final List<Keyframe> keyframes;
  
  // For Video / Temporal masking
  final double? frameStart;
  final double? frameEnd;
  
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  // Render & Operation state (kept for engine computation graph)
  final MaskOperation operation;
  final String blendMode;
  final bool inversion;
  final double feather;
  final double edge;
  final double expansion;
  final double contract;
  final double density;
  final double opacity;
  final List<String> childrenIds;

  const UniversalMask({
    required this.id,
    this.name = 'Mask',
    required this.projectId,
    required this.mediaId,
    required this.maskType,
    required this.sourceType,
    this.version = 1,
    this.enabled = true,
    this.visibility = true,
    this.parentMaskId,
    this.geometryReference,
    this.bitmapReference,
    this.vectorReference,
    this.sourceAssetId,
    this.sourceClipId,
    this.parameters = const {},
    this.trackingReference,
    this.modelReference,
    this.confidence = 1.0,
    this.tracking = const [],
    this.keyframes = const [],
    this.frameStart,
    this.frameEnd,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.operation = MaskOperation.add,
    this.blendMode = 'normal',
    this.inversion = false,
    this.feather = 0.0,
    this.edge = 0.0,
    this.expansion = 0.0,
    this.contract = 0.0,
    this.density = 1.0,
    this.opacity = 1.0,
    this.childrenIds = const [],
  });

  UniversalMask copyWith({
    String? id,
    String? name,
    String? projectId,
    String? mediaId,
    MaskType? maskType,
    MaskSourceType? sourceType,
    int? version,
    bool? enabled,
    bool? visibility,
    String? parentMaskId,
    String? geometryReference,
    String? bitmapReference,
    String? vectorReference,
    String? sourceAssetId,
    String? sourceClipId,
    Map<String, dynamic>? parameters,
    String? trackingReference,
    String? modelReference,
    double? confidence,
    List<TrackingData>? tracking,
    List<Keyframe>? keyframes,
    double? frameStart,
    double? frameEnd,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    MaskOperation? operation,
    String? blendMode,
    bool? inversion,
    double? feather,
    double? edge,
    double? expansion,
    double? contract,
    double? density,
    double? opacity,
    List<String>? childrenIds,
  }) {
    return UniversalMask(
      id: id ?? this.id,
      name: name ?? this.name,
      projectId: projectId ?? this.projectId,
      mediaId: mediaId ?? this.mediaId,
      maskType: maskType ?? this.maskType,
      sourceType: sourceType ?? this.sourceType,
      version: version ?? this.version,
      enabled: enabled ?? this.enabled,
      visibility: visibility ?? this.visibility,
      parentMaskId: parentMaskId ?? this.parentMaskId,
      geometryReference: geometryReference ?? this.geometryReference,
      bitmapReference: bitmapReference ?? this.bitmapReference,
      vectorReference: vectorReference ?? this.vectorReference,
      sourceAssetId: sourceAssetId ?? this.sourceAssetId,
      sourceClipId: sourceClipId ?? this.sourceClipId,
      parameters: parameters ?? this.parameters,
      trackingReference: trackingReference ?? this.trackingReference,
      modelReference: modelReference ?? this.modelReference,
      confidence: confidence ?? this.confidence,
      tracking: tracking ?? this.tracking,
      keyframes: keyframes ?? this.keyframes,
      frameStart: frameStart ?? this.frameStart,
      frameEnd: frameEnd ?? this.frameEnd,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      operation: operation ?? this.operation,
      blendMode: blendMode ?? this.blendMode,
      inversion: inversion ?? this.inversion,
      feather: feather ?? this.feather,
      edge: edge ?? this.edge,
      expansion: expansion ?? this.expansion,
      contract: contract ?? this.contract,
      density: density ?? this.density,
      opacity: opacity ?? this.opacity,
      childrenIds: childrenIds ?? this.childrenIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'projectId': projectId,
      'mediaId': mediaId,
      'maskType': maskType.name,
      'sourceType': sourceType.name,
      'version': version,
      'enabled': enabled,
      'visibility': visibility,
      'parentMaskId': parentMaskId,
      'geometryReference': geometryReference,
      'bitmapReference': bitmapReference,
      'vectorReference': vectorReference,
      'sourceAssetId': sourceAssetId,
      'sourceClipId': sourceClipId,
      'parameters': parameters,
      'trackingReference': trackingReference,
      'modelReference': modelReference,
      'confidence': confidence,
      'frameStart': frameStart,
      'frameEnd': frameEnd,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'deletedAt': deletedAt?.toIso8601String(),
      'operation': operation.name,
      'blendMode': blendMode,
      'inversion': inversion,
      'feather': feather,
      'edge': edge,
      'expansion': expansion,
      'contract': contract,
      'density': density,
      'opacity': opacity,
      'childrenIds': childrenIds,
    };
  }

  factory UniversalMask.fromJson(Map<String, dynamic> json) {
    return UniversalMask(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Mask',
      projectId: json['projectId'] as String,
      mediaId: json['mediaId'] as String,
      maskType: MaskType.values.firstWhere((e) => e.name == json['maskType'], orElse: () => MaskType.CUSTOM),
      sourceType: MaskSourceType.values.firstWhere((e) => e.name == json['sourceType'], orElse: () => MaskSourceType.manual),
      version: json['version'] as int? ?? 1,
      enabled: json['enabled'] as bool? ?? true,
      visibility: json['visibility'] as bool? ?? true,
      parentMaskId: json['parentMaskId'] as String?,
      geometryReference: json['geometryReference'] as String?,
      bitmapReference: json['bitmapReference'] as String?,
      vectorReference: json['vectorReference'] as String?,
      sourceAssetId: json['sourceAssetId'] as String?,
      sourceClipId: json['sourceClipId'] as String?,
      parameters: json['parameters'] as Map<String, dynamic>? ?? const {},
      trackingReference: json['trackingReference'] as String?,
      modelReference: json['modelReference'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      frameStart: (json['frameStart'] as num?)?.toDouble(),
      frameEnd: (json['frameEnd'] as num?)?.toDouble(),
      createdBy: json['createdBy'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: json['deletedAt'] != null ? DateTime.parse(json['deletedAt'] as String) : null,
      operation: MaskOperation.values.firstWhere((e) => e.name == json['operation'], orElse: () => MaskOperation.add),
      blendMode: json['blendMode'] as String? ?? 'normal',
      inversion: json['inversion'] as bool? ?? false,
      feather: (json['feather'] as num?)?.toDouble() ?? 0.0,
      edge: (json['edge'] as num?)?.toDouble() ?? 0.0,
      expansion: (json['expansion'] as num?)?.toDouble() ?? 0.0,
      contract: (json['contract'] as num?)?.toDouble() ?? 0.0,
      density: (json['density'] as num?)?.toDouble() ?? 1.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      childrenIds: (json['childrenIds'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
    );
  }
}

class MaskGraph {
  final String id;
  /// Flat map of all nodes in the DAG for O(1) lookup
  final Map<String, UniversalMask> nodes;
  /// The root level masks that don't have parents
  final List<String> rootNodeIds;
  
  MaskGraph({
    required this.id,
    Map<String, UniversalMask>? nodes,
    List<String>? rootNodeIds,
  }) : nodes = nodes ?? {},
       rootNodeIds = rootNodeIds ?? [];
       
  void addNode(UniversalMask node) {
    nodes[node.id] = node;
    // If it has no parent, it's a root node
    if (node.parentMaskId == null) {
      if (!rootNodeIds.contains(node.id)) {
        rootNodeIds.add(node.id);
      }
    }
  }

  void addEdge(String parentId, String childId) {
    if (nodes.containsKey(parentId) && nodes.containsKey(childId)) {
      // For UniversalMask, children are managed by childrenIds list.
      // But childrenIds is a final list in UniversalMask. We need to create a copy.
      final parent = nodes[parentId]!;
      final newChildren = List<String>.from(parent.childrenIds)..add(childId);
      nodes[parentId] = parent.copyWith(childrenIds: newChildren);
    }
  }
  
  MaskGraph copyWith({
    String? id,
    Map<String, UniversalMask>? nodes,
    List<String>? rootNodeIds,
  }) {
    return MaskGraph(
      id: id ?? this.id,
      nodes: nodes ?? Map.from(this.nodes),
      rootNodeIds: rootNodeIds ?? List.from(this.rootNodeIds),
    );
  }
}

/// A non-destructive set of color parameters applied to a mask layer.
class ColorGradingPayload {
  final double? exposure;
  final double? temperature;
  final double? tint;
  final double? contrast;
  final double? highlights;
  final double? shadows;
  final double? saturation;

  const ColorGradingPayload({
    this.exposure,
    this.temperature,
    this.tint,
    this.contrast,
    this.highlights,
    this.shadows,
    this.saturation,
  });

  ColorGradingPayload copyWith({
    double? exposure,
    double? temperature,
    double? tint,
    double? contrast,
    double? highlights,
    double? shadows,
    double? saturation,
  }) {
    return ColorGradingPayload(
      exposure: exposure ?? this.exposure,
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      contrast: contrast ?? this.contrast,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      saturation: saturation ?? this.saturation,
    );
  }
}

