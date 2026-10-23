import 'package:flutter/foundation.dart';
import '../cv_inference_service.dart';
import '../intersection_orchestrator.dart';
import '../mask_layer_manager.dart';
import '../universal_mask_models.dart';
import '../../photo_studio/nlp_color_orchestrator.dart';
import '../../photo_studio/photo_studio_engine.dart';
import '../../photo_studio/photo_studio_models.dart';
import 'package:uuid/uuid.dart';

/// The strict API Contract connecting the Flutter Frontend to the Certified Backend.
/// 
/// FLUTTER DOMAIN + REPOSITORIES:
/// Widgets MUST NOT directly instantiate engine components. They must route
/// all requests through this repository to guarantee mathematical integrity,
/// automatic version control snapshots, and correct GPU queuing.
class MaskEngineRepository {
  final MaskLayerManager _layerManager;
  final PhotoProjectNotifier _projectNotifier;
  final IntersectionOrchestrator _intersectionOrchestrator;
  final NlpColorOrchestrator _nlpOrchestrator;
  final CvInferenceService _cvService;
  final _uuid = const Uuid();

  MaskEngineRepository({
    required this._layerManager,
    required this._projectNotifier,
    required this._intersectionOrchestrator,
    required this._nlpOrchestrator,
    required this._cvService,
  });

  // ==========================================
  // STATE EXPOSURE
  // ==========================================
  
  /// The active layers driving the UI Canvas
  List<MaskLayer> get activeLayers => _layerManager.layers;
  
  /// Synchronize the layer manager from the canonical project graph (e.g. after Undo/Redo)
  void syncFromProject(PhotoProject project) {
    if (project.currentGraph.layers.isEmpty) return;
    final graph = project.currentGraph.layers.first.maskGraph;
    if (graph == null) return;
    
    // Simplistic synchronization - replacing active layers with nodes from the graph
    _layerManager.layers.clear();
    for (var node in graph.nodes.values) {
      _layerManager.layers.add(MaskLayer(
        id: node.id,
        name: node.parameters['semantic_target'] ?? 'Mask',
        activeMask: node,
      ));
    }
  }

  // ==========================================
  // API CONTRACT: Semantic Actions
  // ==========================================

  /// Triggers a smart semantic selection (e.g. user clicked "Person").
  /// This automatically generates a root graph node and adds it to the layer stack.
  Future<void> addSemanticMask(String mediaId, String semanticTarget) async {
    debugPrint("API: addSemanticMask($semanticTarget)");
    
    // Submit real CV Job to the engine
    final job = CvJob(
      jobId: 'JOB_\${DateTime.now().millisecondsSinceEpoch}',
      capability: CvCapability.semanticSegmentation,
      payload: {'target': semanticTarget, 'media_id': mediaId},
    );
    
    final result = await _cvService.submitJob(job);
    
    final newMask = UniversalMask(
      id: 'MASK_\${DateTime.now().millisecondsSinceEpoch}',
      projectId: 'auto',
      mediaId: mediaId,
      maskType: MaskType.CUSTOM,
      sourceType: MaskSourceType.ai,
      operation: MaskOperation.add,
      parameters: {
        'semantic_target': semanticTarget,
        'normalized_path': result['normalized_path'], // Inject the geometry result
      },
      geometryReference: result['geometry_hash'],
      createdBy: 'frontend_api',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Update active UI state
    _layerManager.addLayer(MaskLayer(
      id: newMask.id,
      name: semanticTarget,
      activeMask: newMask,
    ));

    final command = EditorCommand(
      commandId: _uuid.v4(),
      projectId: _projectNotifier.currentState.id,
      mediaId: mediaId,
      maskId: newMask.id,
      previousVersion: _projectNotifier.currentState.backendVersion,
      newVersion: _uuid.v4(),
      operation: 'AI Generate Mask',
      parameters: {'target': semanticTarget},
      timestamp: DateTime.now(),
      source: 'ai',
    );
    
    _projectNotifier.updateMaskGraph(
      _projectNotifier.currentState.currentGraph.layers.first.id,
      MaskGraph(
        id: 'GLOBAL_MASK_GRAPH', 
        nodes: { for (var l in _layerManager.layers) if (l.activeMask != null) l.activeMask!.id: l.activeMask! }
      ),
      command: command,
    );
  }

  Future<void> addPointMask(String mediaId, double normalizedX, double normalizedY) async {
    debugPrint("API: addPointMask(\$normalizedX, \$normalizedY)");
    
    final job = CvJob(
      jobId: 'JOB_\${DateTime.now().millisecondsSinceEpoch}',
      capability: CvCapability.semanticSegmentation,
      payload: {'target': 'point', 'x': normalizedX, 'y': normalizedY, 'media_id': mediaId},
    );
    
    final result = await _cvService.submitJob(job);
    
    final newMask = UniversalMask(
      id: 'MASK_\${DateTime.now().millisecondsSinceEpoch}',
      projectId: 'auto',
      mediaId: mediaId,
      maskType: MaskType.CUSTOM,
      sourceType: MaskSourceType.ai,
      operation: MaskOperation.add,
      parameters: {
        'semantic_target': 'Point Selection',
        'normalized_path': result['normalized_path'],
      },
      geometryReference: result['geometry_hash'],
      createdBy: 'frontend_api',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    
    _layerManager.addLayer(MaskLayer(
      id: newMask.id,
      name: 'Tap Selection',
      activeMask: newMask,
    ));
    
    final command = EditorCommand(
      commandId: _uuid.v4(),
      projectId: _projectNotifier.currentState.id,
      mediaId: mediaId,
      maskId: newMask.id,
      previousVersion: _projectNotifier.currentState.backendVersion,
      newVersion: _uuid.v4(),
      operation: 'Select Subject',
      parameters: {'type': 'point', 'x': normalizedX, 'y': normalizedY},
      timestamp: DateTime.now(),
      source: 'user',
    );

    _projectNotifier.updateMaskGraph(
      _projectNotifier.currentState.currentGraph.layers.first.id,
      MaskGraph(
        id: 'GLOBAL_MASK_GRAPH', 
        nodes: { for (var l in _layerManager.layers) if (l.activeMask != null) l.activeMask!.id: l.activeMask! }
      ),
      command: command,
    );
  }

  Future<void> addStrokeMask(String mediaId, List<Map<String, double>> strokePoints, {MaskOperation operation = MaskOperation.add}) async {
    debugPrint("API: addStrokeMask(${strokePoints.length} points, operation: $operation)");
    
    final job = CvJob(
      jobId: 'JOB_\${DateTime.now().millisecondsSinceEpoch}',
      capability: CvCapability.semanticSegmentation,
      payload: {'target': 'stroke', 'points': strokePoints, 'media_id': mediaId},
    );
    
    final result = await _cvService.submitJob(job);
    
    final newMask = UniversalMask(
      id: 'MASK_\${DateTime.now().millisecondsSinceEpoch}',
      projectId: 'auto',
      mediaId: mediaId,
      maskType: MaskType.CUSTOM,
      sourceType: MaskSourceType.ai,
      operation: operation,
      parameters: {
        'semantic_target': 'Brush Stroke',
        'normalized_path': result['normalized_path'],
      },
      geometryReference: result['geometry_hash'],
      createdBy: 'frontend_api',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    
    _layerManager.addLayer(MaskLayer(
      id: newMask.id,
      name: 'Brush Stroke',
      activeMask: newMask,
    ));
    
    final command = EditorCommand(
      commandId: _uuid.v4(),
      projectId: _projectNotifier.currentState.id,
      mediaId: mediaId,
      maskId: newMask.id,
      previousVersion: _projectNotifier.currentState.backendVersion,
      newVersion: _uuid.v4(),
      operation: 'Add Brush',
      parameters: {'points': strokePoints.length},
      timestamp: DateTime.now(),
      source: 'user',
    );

    _projectNotifier.updateMaskGraph(
      _projectNotifier.currentState.currentGraph.layers.first.id,
      MaskGraph(
        id: 'GLOBAL_MASK_GRAPH', 
        nodes: { for (var l in _layerManager.layers) if (l.activeMask != null) l.activeMask!.id: l.activeMask! }
      ),
      command: command,
    );
  }

  // ==========================================
  // API CONTRACT: NLP Orchestration
  // ==========================================

  /// Parses natural language from the user into actionable graphs.
  /// Example: "Make the red shirt deeper"
  Future<void> executeNaturalLanguageCommand(String mediaId, String command) async {
    debugPrint("API: executeNaturalLanguageCommand('$command')");
    await _nlpOrchestrator.executeColorCommand(command, mediaId);
    
    final editorCommand = EditorCommand(
      commandId: _uuid.v4(),
      projectId: _projectNotifier.currentState.id,
      mediaId: mediaId,
      previousVersion: _projectNotifier.currentState.backendVersion,
      newVersion: _uuid.v4(),
      operation: 'AI Replace',
      parameters: {'nlp_command': command},
      timestamp: DateTime.now(),
      source: 'ai',
    );

    _projectNotifier.updateMaskGraph(
      _projectNotifier.currentState.currentGraph.layers.first.id,
      MaskGraph(
        id: 'GLOBAL_MASK_GRAPH', 
        nodes: { for (var l in _layerManager.layers) if (l.activeMask != null) l.activeMask!.id: l.activeMask! }
      ),
      command: editorCommand,
    );
  }

  // ==========================================
  // API CONTRACT: Versioning (Undo/Redo)
  // ==========================================

  void restoreVersion(int versionNumber) {
    debugPrint("API: restoreVersion($versionNumber) -> Handled via canonical PhotoProject history now.");
  }

  // ==========================================
  // API CONTRACT: Telemetry & GPU Health
  // ==========================================

  CvTelemetry get gpuHealth => _cvService.fetchTelemetry();
}
