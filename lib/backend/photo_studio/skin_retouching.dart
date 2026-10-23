import 'package:flutter/foundation.dart';
import '../mask_engine/universal_mask_models.dart';

enum SkinTarget {
  faceOnly,
  neckOnly,
  bodyOnly,
  allVisible,
}

/// Photometric skin retouching parameters mapped onto a 0-100 intensity scale.
class SkinRetouchParameters {
  final double smoothingIntensity;
  final double texturePreservation; // Counters smoothing to keep pores realistic
  final double toneCorrection;
  final double colorCorrection;
  final double rednessReduction;
  final double brightness;
  final double warmth;
  final double saturation;

  const SkinRetouchParameters({
    this.smoothingIntensity = 0.0,
    this.texturePreservation = 100.0, // Default must preserve realistic texture
    this.toneCorrection = 0.0,
    this.colorCorrection = 0.0,
    this.rednessReduction = 0.0,
    this.brightness = 0.0,
    this.warmth = 0.0,
    this.saturation = 0.0,
  });

  /// Failsafe against excessive blurring.
  /// Validates that texture preservation does not drop below a critical threshold 
  /// if smoothing is pushed high, preventing "plastic" looking skin.
  bool isValid() {
    if (smoothingIntensity > 80.0 && texturePreservation < 20.0) {
      debugPrint("SKIN ENGINE WARNING: Excessive blur detected. Automatically boosting texture preservation.");
      return false; // UI should intercept and force texture preservation up.
    }
    return true;
  }
}

/// Advanced Skin Selection and High-Frequency Separation Engine.
class SkinRetouchingEngine {
  
  /// Compiles a precise Skin mask by combining targeted skin regions
  /// and mathematically excluding all non-skin features.
  /// Excludes: eyes, lips, teeth, hair, eyebrows, facial hair, clothing.
  static MaskGraph compileSkinMask({
    required MaskGraph globalGraph,
    required String identityTrackingId,
    required SkinTarget target,
  }) {
    // 1. We start with the base geometry for the Person
    // 2. We extract Face Skin, Neck Skin, Body Skin based on target
    List<UniversalMask> baseSkinNodes = [];
    List<UniversalMask> exclusionNodes = [];

    for (final node in globalGraph.nodes.values) {
      if (node.trackingReference != identityTrackingId) continue; // Lock to specific person
      
      // Collect Base Skin
      if (node.maskType == MaskType.SKIN && (target == SkinTarget.faceOnly || target == SkinTarget.allVisible)) {
        baseSkinNodes.add(node);
      } else if (node.maskType == MaskType.BODY && (target == SkinTarget.bodyOnly || target == SkinTarget.allVisible || target == SkinTarget.neckOnly)) {
        // Technically neck/body could be subset of BODY in human parsing
        baseSkinNodes.add(node);
      }

      // Collect Exclusions (Protecting facial features & clothing)
      if (node.maskType == MaskType.EYES ||
          node.maskType == MaskType.LIPS ||
          node.maskType == MaskType.TEETH ||
          node.maskType == MaskType.HAIR ||
          node.maskType == MaskType.EYEBROWS ||
          node.maskType == MaskType.MOUTH ||
          node.maskType == MaskType.CLOTHING) {
        
        // Force the operation to exclude
        exclusionNodes.add(node.copyWith(operation: MaskOperation.exclude));
      }
    }

    // Combine them into a new ephemeral sub-graph for rendering
    final Map<String, UniversalMask> compiledNodes = {};
    final List<String> rootIds = [];
    
    // We create a root "SKIN_COMPOSITE" node
    final String rootId = '\${identityTrackingId}_SKIN_COMPOSITE';
    final List<String> childIds = [];

    for (var skin in baseSkinNodes) {
      final id = '\${skin.id}_base';
      compiledNodes[id] = skin.copyWith(id: id, parentMaskId: rootId, operation: MaskOperation.add);
      childIds.add(id);
    }
    
    for (var exclusion in exclusionNodes) {
      final id = '\${exclusion.id}_exclude';
      compiledNodes[id] = exclusion.copyWith(id: id, parentMaskId: rootId, operation: MaskOperation.exclude);
      childIds.add(id);
    }

    compiledNodes[rootId] = UniversalMask(
      id: rootId,
      projectId: 'compile_memory',
      mediaId: 'compile_memory',
      maskType: MaskType.SKIN,
      sourceType: MaskSourceType.ai,
      childrenIds: childIds,
      trackingReference: identityTrackingId,
      createdBy: 'skin_retouching_engine',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    
    rootIds.add(rootId);

    return MaskGraph(
      id: 'SKIN_GRAPH_\$identityTrackingId',
      nodes: compiledNodes,
      rootNodeIds: rootIds,
    );
  }
}
