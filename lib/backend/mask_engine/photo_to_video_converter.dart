import 'package:flutter/foundation.dart';
import 'mask_layer_manager.dart';
import 'temporal_video_tracker.dart';
import 'universal_mask_models.dart';
import 'cv_inference_service.dart';

/// Handles the complex transition of lifting static mathematical properties
/// from a Photo project and transposing them into 4D Temporal space.
class PhotoToVideoConverter {
  final TemporalVideoTracker tracker;
  final CvInferenceService cvEngine;

  PhotoToVideoConverter({
    required this.tracker,
    required this.cvEngine,
  });

  /// Upgrades a static MaskLayer stack into a living video tracking state.
  /// 
  /// REQUIREMENT: Do not reuse a static image mask blindly. Generate video tracking state.
  Future<void> convertPhotoMasksToVideoTracking(
    MaskLayerManager staticPhotoManager, 
    String targetVideoId,
  ) async {
    debugPrint("PHOTO TO VIDEO: Initiating conversion sequence for video '\$targetVideoId'...");

    final activeLayers = staticPhotoManager.layers;

    if (activeLayers.isEmpty) {
      debugPrint("PHOTO TO VIDEO: No active masks to convert.");
      return;
    }

    // 1. Identify semantic roots vs procedural dependencies.
    // E.g., we want to track "Person", not track a "Red Color Range". The procedural
    // color range will be mathematically reapplied AFTER the Semantic Person is tracked.
    final semanticLayers = activeLayers.where((layer) => 
      layer.activeMask != null && 
      layer.activeMask!.sourceType == MaskSourceType.ai
    ).toList();

    debugPrint("PHOTO TO VIDEO: Extracted \${semanticLayers.length} semantic anchor layers.");

    // 2. Register these anchors with the Temporal Video Tracker to establish Re-ID embeddings.
    for (final semanticLayer in semanticLayers) {
      // In a real scenario, we might extract face, skin, hair layers as children of this root.
      // For this example, we treat each top-level semantic layer as an isolated TemporalIdentity.
      tracker.registerIdentityHierarchy(semanticLayer.activeMask!, []);
    }

    // 3. Command the CV Engine to generate the actual 4D video tracking state.
    debugPrint("PHOTO TO VIDEO: Discarding static mask raster data. Generating fresh 4D Video Tracking State...");
    
    final cvTrackingJobs = semanticLayers.map((layer) {
      return CvJob(
        jobId: 'TRACK_\${layer.id}',
        capability: CvCapability.videoTracking,
        payload: {
          'video_id': targetVideoId,
          'semantic_target': layer.activeMask!.parameters['semantic_query'] ?? layer.name,
          'initial_geometry': layer.activeMask!.parameters['geometry'], // Anchor bounds
        },
      );
    }).toList();

    // Submit batch processing to compute optical flow / temporal coherence
    try {
      final results = await cvEngine.submitBatch(cvTrackingJobs);
      debugPrint("PHOTO TO VIDEO: Successfully generated \${results.length} 4D tracking states.");
      
      // 4. Update the Mask layers with the new Video mask references
      for (int i = 0; i < semanticLayers.length; i++) {
        final originalLayer = semanticLayers[i];
        final trackedResult = results[i];

        // We update the UniversalMask parameters to switch from 'static' to 'tracked'
        originalLayer.activeMask!.parameters['video_tracking_state_id'] = trackedResult['geometry_hash'];
        originalLayer.activeMask!.parameters['is_temporal'] = true;
      }
      
    } catch (e) {
      debugPrint("PHOTO TO VIDEO ERROR: Failed to compute video tracking states. \$e");
      // Handle fallback or prompt user
      rethrow;
    }
  }
}
