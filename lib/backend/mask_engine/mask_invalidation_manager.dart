import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'universal_mask_models.dart';

/// Represents the precise physical and temporal geometry of the source media.
class MediaGeometryState {
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;
  final double rotationDegrees;
  final double lensCorrectionProfile;
  final double timelineAlignmentOffset;
  final String sourceMediaVersion; // e.g. v1.mp4 vs v2_color_graded.mp4

  const MediaGeometryState({
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
    required this.rotationDegrees,
    required this.lensCorrectionProfile,
    required this.timelineAlignmentOffset,
    required this.sourceMediaVersion,
  });

  /// Computes a deterministic SHA-256 hash of the spatial and temporal geometry.
  String computeGeometryHash() {
    final payload = '\$cropLeft|\$cropTop|\$cropRight|\$cropBottom|\$rotationDegrees|\$lensCorrectionProfile|\$timelineAlignmentOffset|\$sourceMediaVersion';
    final bytes = utf8.encode(payload);
    return sha256.convert(bytes).toString();
  }
}

/// The available user responses when a mask is flagged as geometrically stale.
enum InvalidationResolutionOption {
  regenerate, // Tosses the mask and re-runs the AI inference on the new geometry
  keepOld,    // Forcefully applies the old mask (User accepts potential misalignment)
  review,     // Opens the Mask Inspector for manual brush refinement
}

/// A payload sent to the UI alerting the user to a stale mask.
class MaskInvalidationAlert {
  final String maskId;
  final String maskName;
  final String message;
  final List<InvalidationResolutionOption> availableOptions;

  const MaskInvalidationAlert({
    required this.maskId,
    required this.maskName,
    this.message = 'Mask needs regeneration.',
    this.availableOptions = const [
      InvalidationResolutionOption.regenerate,
      InvalidationResolutionOption.keepOld,
      InvalidationResolutionOption.review,
    ],
  });
}

/// Advanced subsystem tracking the spatial/temporal validity of AI masks.
class MaskInvalidationManager {
  
  /// Binds the current geometric state to a newly generated mask.
  /// This should be called immediately before saving the mask to the graph.
  static Map<String, dynamic> bindGeometryHash(Map<String, dynamic> existingParameters, MediaGeometryState state) {
    final payload = Map<String, dynamic>.from(existingParameters);
    payload['source_geometry_hash'] = state.computeGeometryHash();
    return payload;
  }

  /// Evaluates whether the mask is still geometrically accurate against the current timeline/canvas state.
  /// 
  /// REQUIREMENT: If the user changes crop, rotation, frame geometry, lens correction, 
  /// timeline alignment, or source media version, the system must determine whether 
  /// the existing mask remains valid.
  static MaskInvalidationAlert? evaluateMaskValidity({
    required UniversalMask mask,
    required String maskName,
    required MediaGeometryState currentMediaState,
  }) {
    final storedHash = mask.parameters['source_geometry_hash'];
    
    // If it lacks a hash, it's a legacy mask or manually drawn mask that we can't mathematically verify.
    if (storedHash == null) return null;

    final currentHash = currentMediaState.computeGeometryHash();

    // REQUIREMENT: Never silently attach a stale mask to new geometry.
    if (storedHash != currentHash) {
      debugPrint("INVALIDATION ENGINE: Mask \${mask.id} is stale. Source geometry hash mismatch.");
      
      return MaskInvalidationAlert(
        maskId: mask.id,
        maskName: maskName,
        message: 'Mask needs regeneration.',
      );
    }

    // Mask is perfectly aligned
    return null;
  }

  /// Executes the user's chosen resolution path.
  static Future<void> resolveInvalidation({
    required String maskId,
    required InvalidationResolutionOption choice,
    required Function(String id) onRegenerate,
    required Function(String id) onKeepOld,
    required Function(String id) onReview,
  }) async {
    switch (choice) {
      case InvalidationResolutionOption.regenerate:
        debugPrint("INVALIDATION ENGINE: User requested AI Regeneration for mask \$maskId.");
        await onRegenerate(maskId);
        break;
      case InvalidationResolutionOption.keepOld:
        debugPrint("INVALIDATION ENGINE: User explicitly forced stale mask \$maskId to remain.");
        await onKeepOld(maskId);
        break;
      case InvalidationResolutionOption.review:
        debugPrint("INVALIDATION ENGINE: Routing user to Review/Brush UI for mask \$maskId.");
        await onReview(maskId);
        break;
    }
  }
}
