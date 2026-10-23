import 'package:flutter/foundation.dart';

/// Represents the physical hardware constraints required to load a CV model.
class CvHardwareRequirements {
  final int minVramMb;
  final List<String> computeArchitectures; // e.g., ['CUDA', 'MPS', 'CPU']

  const CvHardwareRequirements({
    required this.minVramMb,
    required this.computeArchitectures,
  });
}

/// The exhaustive manifest defining a local or remote CV model's capabilities and metrics.
class CvModelManifest {
  final String name;
  final String version;
  final String task; // e.g., 'segmentation', 'tracking', 'depth_estimation'
  final List<String> inputRequirements; // e.g., ['rgb_tensor_1024x1024', 'interaction_point']
  final String outputType; // e.g., 'binary_mask_tensor', 'depth_map'
  final CvHardwareRequirements hardwareRequirements;
  final String license;
  final String status; // 'active', 'loading', 'cached', 'offline'
  
  // Benchmarking & Telemetry
  final double benchmarkQualityScore; // e.g., 0.94 mIoU (Mean Intersection over Union)
  final double expectedLatencyMs;
  final int requiredMemoryMb; // Active VRAM footprint when loaded

  const CvModelManifest({
    required this.name,
    required this.version,
    required this.task,
    required this.inputRequirements,
    required this.outputType,
    required this.hardwareRequirements,
    required this.license,
    required this.status,
    required this.benchmarkQualityScore,
    required this.expectedLatencyMs,
    required this.requiredMemoryMb,
  });
}

/// A centralized registry tracking all available CV models across the worker pool.
class CvModelRegistry {
  final Map<String, CvModelManifest> _registeredModels = {};

  /// Populates the registry with the default suite of ONEROVA CV models.
  void initializeDefaultRegistry() {
    registerModel(
      const CvModelManifest(
        name: 'SAM 2 (Segment Anything)',
        version: '2.1.0',
        task: 'segmentation',
        inputRequirements: ['rgb_tensor', 'interaction_point_or_box'],
        outputType: 'binary_mask_tensor',
        hardwareRequirements: CvHardwareRequirements(
          minVramMb: 4000,
          computeArchitectures: ['CUDA', 'MPS'], // Needs GPU acceleration
        ),
        license: 'Apache 2.0',
        status: 'cached', // Kept warm by default
        benchmarkQualityScore: 0.98,
        expectedLatencyMs: 45.0,
        requiredMemoryMb: 3500,
      ),
    );

    registerModel(
      const CvModelManifest(
        name: 'ONEROVA FaceMesh Fast',
        version: '1.4.2',
        task: 'face_landmarks',
        inputRequirements: ['rgb_tensor_256x256'],
        outputType: 'mesh_geometry_468',
        hardwareRequirements: CvHardwareRequirements(
          minVramMb: 500,
          computeArchitectures: ['CUDA', 'MPS', 'CPU', 'NPU'], // Highly optimized
        ),
        license: 'Proprietary',
        status: 'active',
        benchmarkQualityScore: 0.92,
        expectedLatencyMs: 12.0,
        requiredMemoryMb: 150,
      ),
    );

    registerModel(
      const CvModelManifest(
        name: 'MiDaS Depth V3',
        version: '3.1',
        task: 'depth_estimation',
        inputRequirements: ['rgb_tensor_384x384'],
        outputType: 'depth_map_tensor',
        hardwareRequirements: CvHardwareRequirements(
          minVramMb: 2000,
          computeArchitectures: ['CUDA', 'MPS'],
        ),
        license: 'MIT',
        status: 'offline', // Loaded on demand
        benchmarkQualityScore: 0.89,
        expectedLatencyMs: 120.0,
        requiredMemoryMb: 1800,
      ),
    );
  }

  /// Adds or updates a model in the local registry.
  void registerModel(CvModelManifest model) {
    _registeredModels[model.name] = model;
    debugPrint("CV REGISTRY: Registered model '\${model.name}' v\${model.version}");
  }

  /// Retrieves a model explicitly by name.
  CvModelManifest? getModel(String name) {
    return _registeredModels[name];
  }

  /// Dynamically queries the registry for the best available model for a specific task
  /// that fits within the current VRAM budget.
  CvModelManifest? resolveOptimalModelForTask({
    required String task,
    required int availableVramMb,
    bool prioritizeSpeed = false,
  }) {
    debugPrint("CV REGISTRY: Resolving optimal model for task: \$task");
    
    // Filter by task and hardware limits
    List<CvModelManifest> candidates = _registeredModels.values.where((model) {
      return model.task == task && model.hardwareRequirements.minVramMb <= availableVramMb;
    }).toList();

    if (candidates.isEmpty) {
      debugPrint("CV REGISTRY: WARNING - No models available for \$task under \${availableVramMb}MB VRAM.");
      return null;
    }

    // Sort by requested priority
    if (prioritizeSpeed) {
      candidates.sort((a, b) => a.expectedLatencyMs.compareTo(b.expectedLatencyMs));
    } else {
      // Prioritize benchmark quality score descending
      candidates.sort((a, b) => b.benchmarkQualityScore.compareTo(a.benchmarkQualityScore));
    }

    debugPrint("CV REGISTRY: Selected '\${candidates.first.name}' for \$task execution.");
    return candidates.first;
  }
}
