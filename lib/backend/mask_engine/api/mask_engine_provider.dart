import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova/backend/mask_engine/api/mask_engine_repository.dart';
import 'package:oneova/backend/mask_engine/cv_inference_service.dart';
import 'package:oneova/backend/mask_engine/intersection_orchestrator.dart';
import 'package:oneova/backend/mask_engine/mask_layer_manager.dart';
import 'package:oneova/backend/mask_engine/universal_mask_models.dart';
import 'package:oneova/backend/photo_studio/nlp_color_orchestrator.dart';
import 'package:oneova/hub/screens/photo_studio/photo_studio_screen.dart';

// The singleton LayerManager we'll use for the session
final maskLayerManagerProvider = Provider<MaskLayerManager>((ref) {
  return MaskLayerManager();
});

final maskEngineProvider = Provider<MaskEngineRepository>((ref) {
  final layerManager = ref.watch(maskLayerManagerProvider);
  final projectNotifier = ref.watch(activePhotoProjectProvider.notifier);
  
  final orchestrator = IntersectionOrchestrator(activeGraph: MaskGraph(id: 'GLOBAL_MASK_GRAPH'));
  final nlp = NlpColorOrchestrator(
    layerManager: layerManager, 
    intersectionOrchestrator: orchestrator,
  );
  final cv = CvInferenceService();
  
  return MaskEngineRepository(
    layerManager: layerManager,
    projectNotifier: projectNotifier,
    intersectionOrchestrator: orchestrator,
    nlpOrchestrator: nlp,
    cvService: cv,
  );
});
