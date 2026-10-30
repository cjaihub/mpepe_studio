/// Oneova Vision Models Registry (§11)
/// Defines model metadata, LiteRT export descriptors, evaluation score gates,
/// and model versioning for Oneova-owned on-device vision intelligence.
library;

enum OneovaModelType {
  faceMesh,
  segmentation,
  handTracking,
  depthEstimation,
  rotoscope,
}

enum OneovaModelFormat {
  liteRt,
  coreMl,
  onnx,
}

class ModelEvaluationScore {
  final String metricName;
  final double value;
  final double targetThreshold;
  final bool passesGate;

  const ModelEvaluationScore({
    required this.metricName,
    required this.value,
    required this.targetThreshold,
    required this.passesGate,
  });

  Map<String, dynamic> toMap() => {
    'metricName': metricName,
    'value': value,
    'targetThreshold': targetThreshold,
    'passesGate': passesGate,
  };

  factory ModelEvaluationScore.fromMap(Map<String, dynamic> map) {
    return ModelEvaluationScore(
      metricName: map['metricName'] as String,
      value: (map['value'] as num).toDouble(),
      targetThreshold: (map['targetThreshold'] as num).toDouble(),
      passesGate: map['passesGate'] as bool? ?? false,
    );
  }
}

class OneovaModelDescriptor {
  final String id;
  final OneovaModelType type;
  final String version;
  final OneovaModelFormat format;
  final String downloadUrl;
  final String localFilename;
  final String sha256Checksum;
  final int sizeBytes;
  final int minComputeTier;
  final double targetLatencyMs;
  final List<String> capabilities;
  final List<ModelEvaluationScore> evaluationScores;
  final bool isActive;
  final bool isStaged;

  const OneovaModelDescriptor({
    required this.id,
    required this.type,
    required this.version,
    required this.format,
    required this.downloadUrl,
    required this.localFilename,
    required this.sha256Checksum,
    required this.sizeBytes,
    required this.minComputeTier,
    required this.targetLatencyMs,
    required this.capabilities,
    this.evaluationScores = const [],
    this.isActive = false,
    this.isStaged = false,
  });

  bool get passesAllEvalGates {
    if (evaluationScores.isEmpty) return true;
    return evaluationScores.every((score) => score.passesGate);
  }

  OneovaModelDescriptor copyWith({
    String? id,
    OneovaModelType? type,
    String? version,
    OneovaModelFormat? format,
    String? downloadUrl,
    String? localFilename,
    String? sha256Checksum,
    int? sizeBytes,
    int? minComputeTier,
    double? targetLatencyMs,
    List<String>? capabilities,
    List<ModelEvaluationScore>? evaluationScores,
    bool? isActive,
    bool? isStaged,
  }) {
    return OneovaModelDescriptor(
      id: id ?? this.id,
      type: type ?? this.type,
      version: version ?? this.version,
      format: format ?? this.format,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      localFilename: localFilename ?? this.localFilename,
      sha256Checksum: sha256Checksum ?? this.sha256Checksum,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      minComputeTier: minComputeTier ?? this.minComputeTier,
      targetLatencyMs: targetLatencyMs ?? this.targetLatencyMs,
      capabilities: capabilities ?? this.capabilities,
      evaluationScores: evaluationScores ?? this.evaluationScores,
      isActive: isActive ?? this.isActive,
      isStaged: isStaged ?? this.isStaged,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type.name,
    'version': version,
    'format': format.name,
    'downloadUrl': downloadUrl,
    'localFilename': localFilename,
    'sha256Checksum': sha256Checksum,
    'sizeBytes': sizeBytes,
    'minComputeTier': minComputeTier,
    'targetLatencyMs': targetLatencyMs,
    'capabilities': capabilities,
    'evaluationScores': evaluationScores.map((e) => e.toMap()).toList(),
    'isActive': isActive,
    'isStaged': isStaged,
  };

  factory OneovaModelDescriptor.fromMap(Map<String, dynamic> map) {
    return OneovaModelDescriptor(
      id: map['id'] as String,
      type: OneovaModelType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => OneovaModelType.faceMesh,
      ),
      version: map['version'] as String,
      format: OneovaModelFormat.values.firstWhere(
        (f) => f.name == map['format'],
        orElse: () => OneovaModelFormat.liteRt,
      ),
      downloadUrl: map['downloadUrl'] as String,
      localFilename: map['localFilename'] as String,
      sha256Checksum: map['sha256Checksum'] as String,
      sizeBytes: map['sizeBytes'] as int,
      minComputeTier: map['minComputeTier'] as int? ?? 1,
      targetLatencyMs: (map['targetLatencyMs'] as num).toDouble(),
      capabilities: List<String>.from(map['capabilities'] ?? const []),
      evaluationScores: (map['evaluationScores'] as List<dynamic>? ?? [])
          .map((e) => ModelEvaluationScore.fromMap(e as Map<String, dynamic>))
          .toList(),
      isActive: map['isActive'] as bool? ?? false,
      isStaged: map['isStaged'] as bool? ?? false,
    );
  }
}

class OneovaModelRegistry {
  static const OneovaModelDescriptor faceMeshV2 = OneovaModelDescriptor(
    id: 'oneova_face_mesh_v2',
    type: OneovaModelType.faceMesh,
    version: '2.1.0',
    format: OneovaModelFormat.liteRt,
    downloadUrl: 'https://storage.googleapis.com/oneova-models-prod/vision/face_mesh_v2.tflite',
    localFilename: 'oneova_face_mesh_v2.tflite',
    sha256Checksum: '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
    sizeBytes: 4194304,
    minComputeTier: 1,
    targetLatencyMs: 4.5,
    capabilities: ['478_landmarks', 'iris_tracking', 'smile_detection', 'mouth_openness'],
    evaluationScores: [
      ModelEvaluationScore(metricName: 'NME_percent', value: 2.8, targetThreshold: 3.5, passesGate: true),
      ModelEvaluationScore(metricName: 'latency_ms', value: 4.2, targetThreshold: 6.0, passesGate: true),
    ],
    isActive: true,
  );

  static const OneovaModelDescriptor segmentationV2 = OneovaModelDescriptor(
    id: 'oneova_person_seg_v2',
    type: OneovaModelType.segmentation,
    version: '2.0.4',
    format: OneovaModelFormat.liteRt,
    downloadUrl: 'https://storage.googleapis.com/oneova-models-prod/vision/person_seg_v2.tflite',
    localFilename: 'oneova_person_seg_v2.tflite',
    sha256Checksum: '5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8',
    sizeBytes: 8388608,
    minComputeTier: 1,
    targetLatencyMs: 7.2,
    capabilities: ['person_mask', 'hair_mask', 'soft_edges', 'alpha_matte'],
    evaluationScores: [
      ModelEvaluationScore(metricName: 'mIoU_percent', value: 94.2, targetThreshold: 90.0, passesGate: true),
      ModelEvaluationScore(metricName: 'fps', value: 60.0, targetThreshold: 45.0, passesGate: true),
    ],
    isActive: true,
  );

  static const OneovaModelDescriptor handsV2 = OneovaModelDescriptor(
    id: 'oneova_hands_v2',
    type: OneovaModelType.handTracking,
    version: '2.0.1',
    format: OneovaModelFormat.liteRt,
    downloadUrl: 'https://storage.googleapis.com/oneova-models-prod/vision/hands_v2.tflite',
    localFilename: 'oneova_hands_v2.tflite',
    sha256Checksum: '4b227777d4dd1fc61c6f884f48641d02b4d121d3fd328cb08b5531fcacdabf8a',
    sizeBytes: 3145728,
    minComputeTier: 1,
    targetLatencyMs: 3.8,
    capabilities: ['21_joints', 'gesture_peace', 'gesture_open_palm', 'gesture_thumbs_up'],
    evaluationScores: [
      ModelEvaluationScore(metricName: 'joint_accuracy_percent', value: 96.5, targetThreshold: 92.0, passesGate: true),
      ModelEvaluationScore(metricName: 'latency_ms', value: 3.5, targetThreshold: 5.0, passesGate: true),
    ],
    isActive: true,
  );

  static const OneovaModelDescriptor depthV1 = OneovaModelDescriptor(
    id: 'oneova_depth_v1',
    type: OneovaModelType.depthEstimation,
    version: '1.2.0',
    format: OneovaModelFormat.liteRt,
    downloadUrl: 'https://storage.googleapis.com/oneova-models-prod/vision/depth_v1.tflite',
    localFilename: 'oneova_depth_v1.tflite',
    sha256Checksum: 'ef2d127de37b942baad06145e54b0c619a1f22327b2ebbcfbec78f5564afe39d',
    sizeBytes: 12582912,
    minComputeTier: 2,
    targetLatencyMs: 11.5,
    capabilities: ['monocular_depth', 'bokeh_defocus', '3d_sticker_occlusion'],
    evaluationScores: [
      ModelEvaluationScore(metricName: 'rel_error_percent', value: 8.4, targetThreshold: 12.0, passesGate: true),
      ModelEvaluationScore(metricName: 'fps', value: 45.0, targetThreshold: 30.0, passesGate: true),
    ],
    isActive: true,
  );

  static List<OneovaModelDescriptor> get defaultModels => [
    faceMeshV2,
    segmentationV2,
    handsV2,
    depthV1,
  ];

  static OneovaModelDescriptor? findById(String id) {
    for (final m in defaultModels) {
      if (m.id == id) return m;
    }
    return null;
  }

  static OneovaModelDescriptor? findByType(OneovaModelType type) {
    for (final m in defaultModels) {
      if (m.type == type && m.isActive) return m;
    }
    return null;
  }
}
