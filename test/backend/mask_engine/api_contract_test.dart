import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/mask_engine/api/mask_engine_repository.dart';
import 'package:oneova/backend/mask_engine/cv_inference_service.dart';
import 'package:oneova/backend/mask_engine/intersection_orchestrator.dart';
import 'package:oneova/backend/mask_engine/universal_mask_models.dart';
import 'package:oneova/backend/mask_engine/mask_layer_manager.dart';
import 'package:oneova/backend/photo_studio/photo_studio_engine.dart';
import 'package:oneova/backend/photo_studio/nlp_color_orchestrator.dart';

import 'package:oneova/backend/photo_studio/photo_studio_models.dart';

class MockPhotoProjectNotifier extends PhotoProjectNotifier {
  @override
  PhotoProject get currentState => const PhotoProject(
    id: 'test_project',
    name: 'Test Project',
    originalAsset: PhotoAsset(id: 'test_asset', uri: '', format: 'RAW', width: 1000, height: 1000),
    currentGraph: EditGraph(
      layers: [
        PhotoLayer(
          id: 'global_layer',
          name: 'Global Adjustments',
          adjustments: [],
          maskGraph: null,
        )
      ],
    ),
  );

  @override
  void updateMaskGraph(String layerId, MaskGraph graph, {EditorCommand? command}) {}
}

void main() {
  group('FLUTTER API CONTRACT VERIFICATION', () {
    late MaskEngineRepository repository;
    
    setUp(() {
      final layerManager = MaskLayerManager();
      final graph = MaskGraph(id: 'TEST_GRAPH');
      final orchestrator = IntersectionOrchestrator(activeGraph: graph);
      final nlp = NlpColorOrchestrator(
        layerManager: layerManager, 
        intersectionOrchestrator: orchestrator
      );
      final cv = CvInferenceService();

      repository = MaskEngineRepository(
        layerManager: layerManager,
        projectNotifier: MockPhotoProjectNotifier(),
        intersectionOrchestrator: orchestrator,
        nlpOrchestrator: nlp,
        cvService: cv,
      );
    });

    test('Frontend can correctly issue a Semantic Target selection', () async {
      expect(repository.activeLayers.length, 0);

      // Simulate UI hitting the "Select Person" button
      await repository.addSemanticMask('media_123', 'person');

      // The Repository must correctly mutate the underlying backend state
      expect(repository.activeLayers.length, 1);
      expect(repository.activeLayers.first.name, 'person');
      expect(repository.activeLayers.first.activeMask?.sourceType, MaskSourceType.ai);
    });

    test('Frontend can push NLP logic which safely drives Intersection & Mask layers', () async {
      expect(repository.activeLayers.length, 0);

      // Simulate UI passing prompt from enhanced_comment_input.dart
      await repository.executeNaturalLanguageCommand('media_123', 'Keep skin untouched');

      // The NLP Orchestrator should parse "skin", identify it as protection, 
      // generate a layer, and set operation to subtract
      expect(repository.activeLayers.length, 1);
      expect(repository.activeLayers.first.name, 'skin');
      expect(repository.activeLayers.first.activeMask?.operation, MaskOperation.subtract);
    });

    test('Frontend can retrieve GPU Telemetry', () {
      final telemetry = repository.gpuHealth;
      expect(telemetry.vramUsageMb, greaterThan(0));
      expect(telemetry.queueDepth, 0);
    });
  });
}
