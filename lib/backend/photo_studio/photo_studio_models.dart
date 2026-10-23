import '../mask_engine/universal_mask_models.dart';

enum AdjustmentType {
  EXPOSURE, CONTRAST, GAMMA, HIGHLIGHTS, SHADOWS, WHITES, BLACKS,
  TEMPERATURE, TINT, VIBRANCE, SATURATION, HUE, HSL, COLOR_MIXER,
  TEXTURE, CLARITY, DEHAZE, SHARPNESS, NOISE_REDUCTION,
  DISTORTION, CHROMATIC_ABERRATION, VIGNETTE, PROFILE_CORRECTION, PERSPECTIVE,
  CURVES_RGB, CURVES_RED, CURVES_GREEN, CURVES_BLUE, CURVES_PARAMETRIC,
  COLOR_WHEELS_SHADOWS, COLOR_WHEELS_MIDTONES, COLOR_WHEELS_HIGHLIGHTS,
  SPLIT_TONING, COLOR_BALANCE, LUMINANCE, SELECTIVE_COLOR, POINT_COLOR,
}



enum CropAspectRatio {
  free,
  original,
  square1x1,
  ratio4x5,
  ratio9x16,
  ratio16x9,
  custom,
}

class CropConfiguration {
  final CropAspectRatio ratio;
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotationDegrees;

  const CropConfiguration({
    this.ratio = CropAspectRatio.free,
    this.x = 0.0,
    this.y = 0.0,
    this.width = 1.0,
    this.height = 1.0,
    this.rotationDegrees = 0.0,
  });

  CropConfiguration copyWith({
    CropAspectRatio? ratio,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotationDegrees,
  }) {
    return CropConfiguration(
      ratio: ratio ?? this.ratio,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    );
  }
}

class PhotoAsset {
  final String id;
  final String uri;
  final String format; // 'RAW', 'JPEG', 'HEIC'
  final int width;
  final int height;

  const PhotoAsset({
    required this.id,
    required this.uri,
    required this.format,
    required this.width,
    required this.height,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'uri': uri,
    'format': format,
    'width': width,
    'height': height,
  };
}

class PhotoLayer {
  final String id;
  final String name;
  final String? assetId; // Null for adjustment layers
  final List<PhotoAdjustment> adjustments;
  final MaskGraph? maskGraph;
  final double opacity;
  final String blendMode; // e.g., 'normal', 'multiply'
  final bool isVisible;

  const PhotoLayer({
    required this.id,
    required this.name,
    this.assetId,
    required this.adjustments,
    this.maskGraph,
    this.opacity = 1.0,
    this.blendMode = 'normal',
    this.isVisible = true,
  });

  PhotoLayer copyWith({
    String? id,
    String? name,
    String? assetId,
    List<PhotoAdjustment>? adjustments,
    MaskGraph? maskGraph,
    double? opacity,
    String? blendMode,
    bool? isVisible,
  }) {
    return PhotoLayer(
      id: id ?? this.id,
      name: name ?? this.name,
      assetId: assetId ?? this.assetId,
      adjustments: adjustments ?? this.adjustments,
      maskGraph: maskGraph ?? this.maskGraph,
      opacity: opacity ?? this.opacity,
      blendMode: blendMode ?? this.blendMode,
      isVisible: isVisible ?? this.isVisible,
    );
  }
}

class PhotoAdjustment {
  final String id;
  final AdjustmentType type;
  final Map<String, dynamic> parameters;
  final bool isEnabled;

  const PhotoAdjustment({
    required this.id,
    required this.type,
    required this.parameters,
    this.isEnabled = true,
  });

  PhotoAdjustment copyWith({
    String? id,
    AdjustmentType? type,
    Map<String, dynamic>? parameters,
    bool? isEnabled,
  }) {
    return PhotoAdjustment(
      id: id ?? this.id,
      type: type ?? this.type,
      parameters: parameters ?? this.parameters,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}



class EditGraph {
  final List<PhotoLayer> layers;
  final CropConfiguration crop;
  
  const EditGraph({
    required this.layers,
    this.crop = const CropConfiguration(),
  });

  EditGraph copyWith({
    List<PhotoLayer>? layers,
    CropConfiguration? crop,
  }) {
    return EditGraph(
      layers: layers ?? this.layers,
      crop: crop ?? this.crop,
    );
  }
}

class EditorCommand {
  final String commandId;
  final String projectId;
  final String mediaId;
  final String? maskId;
  final String? previousVersion;
  final String? newVersion;
  final String operation;
  final Map<String, dynamic> parameters;
  final DateTime timestamp;
  final String source; // 'user' or 'ai'

  const EditorCommand({
    required this.commandId,
    required this.projectId,
    required this.mediaId,
    this.maskId,
    this.previousVersion,
    this.newVersion,
    required this.operation,
    required this.parameters,
    required this.timestamp,
    required this.source,
  });

  Map<String, dynamic> toJson() => {
    'command_id': commandId,
    'project_id': projectId,
    'media_id': mediaId,
    'mask_id': maskId,
    'previous_version': previousVersion,
    'new_version': newVersion,
    'operation': operation,
    'parameters': parameters,
    'timestamp': timestamp.toIso8601String(),
    'source': source,
  };
}

class EditSnapshot {
  final String id;
  final DateTime timestamp;
  final String description;
  final EditGraph graph;
  final EditorCommand? command;

  const EditSnapshot({
    required this.id,
    required this.timestamp,
    required this.description,
    required this.graph,
    this.command,
  });
}

class PhotoPreset {
  final String id;
  final String name;
  final String category;
  final EditGraph graph;

  const PhotoPreset({
    required this.id,
    required this.name,
    required this.category,
    required this.graph,
  });
}

class ExportConfiguration {
  final String format; // 'JPEG', 'PNG', 'TIFF'
  final int quality;
  final int? maxWidth;
  final int? maxHeight;
  final bool preserveExif;

  const ExportConfiguration({
    this.format = 'JPEG',
    this.quality = 90,
    this.maxWidth,
    this.maxHeight,
    this.preserveExif = true,
  });
}

class PhotoProject {
  final String id;
  final String name;
  final PhotoAsset originalAsset;
  final EditGraph currentGraph;
  final List<EditSnapshot> history;
  final int currentHistoryIndex;
  
  // Versions are essentially named snapshots representing major milestones (e.g., "B&W Edit")
  final List<EditSnapshot> versions; 
  
  // For backend conflict resolution
  final String backendVersion;

  const PhotoProject({
    required this.id,
    required this.name,
    required this.originalAsset,
    required this.currentGraph,
    this.history = const [],
    this.currentHistoryIndex = -1,
    this.versions = const [],
    this.backendVersion = '1',
  });

  PhotoProject copyWith({
    String? id,
    String? name,
    PhotoAsset? originalAsset,
    EditGraph? currentGraph,
    List<EditSnapshot>? history,
    int? currentHistoryIndex,
    List<EditSnapshot>? versions,
    String? backendVersion,
  }) {
    return PhotoProject(
      id: id ?? this.id,
      name: name ?? this.name,
      originalAsset: originalAsset ?? this.originalAsset,
      currentGraph: currentGraph ?? this.currentGraph,
      history: history ?? this.history,
      currentHistoryIndex: currentHistoryIndex ?? this.currentHistoryIndex,
      versions: versions ?? this.versions,
      backendVersion: backendVersion ?? this.backendVersion,
    );
  }
}
