import 'package:flutter/foundation.dart';
import '../mask_engine/universal_mask_models.dart';

/// Depth-based spatial segmentation regions.
enum SceneDepthRegion {
  background,
  foreground,
  subject, // Primary focal point(s)
}

/// Photometric and Geometric parameters for spatial background control.
class BackgroundRetouchParameters {
  final double blur; // Synthetic shallow depth-of-field
  final double exposure; // Negative to darken, Positive to lighten
  final double saturation; // Negative to desaturate and isolate subject
  final double colorGrade; // Hue/tint shift
  final double depthTreatment; // Atmospheric perspective fading based on distance

  /// AI Generative / Destructive actions
  final bool replace; 
  final bool remove; // Generates an alpha transparency cutout

  const BackgroundRetouchParameters({
    this.blur = 0.0,
    this.exposure = 0.0,
    this.saturation = 0.0,
    this.colorGrade = 0.0,
    this.depthTreatment = 0.0,
    this.replace = false,
    this.remove = false,
  });
  
  bool get isDestructive => replace || remove;
}

/// Advanced subsystem for spatial scene separation and depth treatments.
class BackgroundSegmentationEngine {
  
  /// Extracts the precise spatial layer (Background, Foreground, or Subject)
  /// using graph traversal and inverse subtraction.
  static MaskGraph compileSceneMask({
    required MaskGraph globalGraph,
    required SceneDepthRegion targetRegion,
  }) {
    final Map<String, UniversalMask> compiledNodes = {};
    final List<String> rootIds = [];
    final List<String> childIds = [];

    // In a production graph, subjects and backgrounds are clearly tagged.
    // To select the background perfectly, we usually take the BACKGROUND node,
    // and explicitly subtract any bleeding SUBJECT or FOREGROUND nodes.
    
    List<UniversalMask> targetNodes = [];
    List<UniversalMask> exclusionNodes = [];

    for (final node in globalGraph.nodes.values) {
      if (targetRegion == SceneDepthRegion.background) {
        if (node.maskType == MaskType.BACKGROUND || node.maskType == MaskType.SKY) {
          targetNodes.add(node);
        } else if (node.maskType == MaskType.SUBJECT || node.maskType == MaskType.PERSON || node.maskType == MaskType.OBJECT) {
          exclusionNodes.add(node.copyWith(operation: MaskOperation.exclude));
        }
      } 
      else if (targetRegion == SceneDepthRegion.foreground) {
        if (node.maskType == MaskType.GROUND) { // Or specific foreground depth maps
          targetNodes.add(node);
        } else if (node.maskType == MaskType.SUBJECT || node.maskType == MaskType.PERSON) {
          exclusionNodes.add(node.copyWith(operation: MaskOperation.exclude));
        }
      }
      else if (targetRegion == SceneDepthRegion.subject) {
        if (node.maskType == MaskType.SUBJECT || node.maskType == MaskType.PERSON) {
          targetNodes.add(node);
        }
      }
    }

    final String rootId = 'SCENE_COMPOSITE_\${targetRegion.name}_\${DateTime.now().millisecondsSinceEpoch}';

    // 1. Add targets
    for (var target in targetNodes) {
      final id = '\${target.id}_base';
      compiledNodes[id] = target.copyWith(
        id: id,
        parentMaskId: rootId,
        operation: MaskOperation.add,
      );
      childIds.add(id);
    }

    // 2. Add exclusions to perfect the boundary
    for (var exclusion in exclusionNodes) {
      final id = '\${exclusion.id}_exclude';
      compiledNodes[id] = exclusion.copyWith(
        id: id,
        parentMaskId: rootId,
        operation: MaskOperation.exclude,
      );
      childIds.add(id);
    }

    // 3. Construct Root
    compiledNodes[rootId] = UniversalMask(
      id: rootId,
      projectId: 'compile_memory',
      mediaId: 'compile_memory',
      maskType: MaskType.BACKGROUND, // Or SUBJECT depending on target
      sourceType: MaskSourceType.ai,
      childrenIds: childIds,
      createdBy: 'background_segmentation_engine',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    rootIds.add(rootId);

    return MaskGraph(
      id: 'SCENE_GRAPH_\${targetRegion.name}',
      nodes: compiledNodes,
      rootNodeIds: rootIds,
    );
  }

  /// Interactive safety flow controller.
  /// REQUIREMENT: Show mask overlay before destructive/generative action.
  static Map<String, dynamic> executeWithPreviewSafeguard({
    required MaskGraph targetMask,
    required BackgroundRetouchParameters params,
    required bool hasUserConfirmedOverlay,
  }) {
    // If the action is safe (photometric only), execute immediately.
    if (!params.isDestructive) {
      return {
        'status': 'executed',
        'requires_ui_preview': false,
      };
    }
    
    // If the action is destructive (Replace / Remove) but the user hasn't seen the mask yet
    if (params.isDestructive && !hasUserConfirmedOverlay) {
      debugPrint("BACKGROUND ENGINE: Intercepting destructive action. Requesting mandatory mask overlay preview.");
      
      // Halt execution and return a directive to the UI to render the mask in red overlay mode.
      return {
        'status': 'halted',
        'requires_ui_preview': true,
        'preview_mask_id': targetMask.id,
        'message': 'Please confirm the mask boundary before removing the background.'
      };
    }
    
    // User has viewed the overlay and hit confirm.
    return {
      'status': 'executed_destructive',
      'requires_ui_preview': false,
    };
  }
}
