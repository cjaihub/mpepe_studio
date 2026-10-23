import 'package:flutter/foundation.dart';
import 'universal_mask_models.dart';
import '../projects/models/keyframe_models.dart';

/// Represents a uniquely identified temporal target across 4D video space.
class TemporalIdentity {
  final String identityId;
  final String semanticName; // e.g. "Person 1"
  final Map<String, TemporalIdentity> subIdentities; // e.g. { "face": ..., "shirt": ... }
  
  bool isPresentInCurrentFrame;
  int framesSinceLastSeen;
  final String baselineReidEmbeddingHash; // Mock vector for re-identification

  TemporalIdentity({
    required this.identityId,
    required this.semanticName,
    this.subIdentities = const {},
    this.isPresentInCurrentFrame = true,
    this.framesSinceLastSeen = 0,
    required this.baselineReidEmbeddingHash,
  });
}

/// Thrown when the Re-ID algorithm drops below the confidence threshold,
/// pausing the engine to request user validation.
class AmbiguousIdentityException implements Exception {
  final String message;
  final TemporalIdentity lostIdentity;

  AmbiguousIdentityException(this.lostIdentity) 
      : message = "Ambiguous Re-Identification for '\${lostIdentity.semanticName}'. User correction required.";
}

/// A dedicated 4D tracking engine ensuring stability across video frames.
/// 
/// REQUIREMENT: The semantic hierarchy must remain stable across frames.
/// REQUIREMENT: Never silently swap Person 1 and Person 2.
class TemporalVideoTracker {
  
  // The stable root identities being tracked (e.g. Person 1, Person 2)
  final Map<String, TemporalIdentity> _activeIdentities = {};
  
  // Minimum cosine similarity required to automatically reconnect an identity
  static const double _strictReIdThreshold = 0.92;

  /// Registers a hierarchical structure for temporal tracking.
  /// Example: Person 1 -> [face, skin, hair, shirt, pants]
  void registerIdentityHierarchy(UniversalMask rootMask, List<UniversalMask> childrenMasks) {
    final identity = TemporalIdentity(
      identityId: rootMask.id,
      semanticName: rootMask.name,
      baselineReidEmbeddingHash: 'VECTOR_\${rootMask.id}',
      subIdentities: {
        for (var child in childrenMasks)
          child.name: TemporalIdentity(
            identityId: child.id,
            semanticName: child.name,
            baselineReidEmbeddingHash: 'VECTOR_\${child.id}',
          )
      },
    );
    
    _activeIdentities[identity.identityId] = identity;
    debugPrint("TEMPORAL TRACKER: Registered stable hierarchy for '\${identity.semanticName}' with \${identity.subIdentities.length} sub-components.");
  }

  /// Evaluates the next frame from the CV inference pipeline.
  /// Returns a map of identityId to TrackingData for this frame.
  Future<Map<String, TrackingData>> processNextFrame({
    required double time,
    required List<Map<String, dynamic>> detectedSubjects, 
  }) async {
    Map<String, TrackingData> frameTracking = {};
    for (final identity in _activeIdentities.values) {
      
      // Simulate attempting to find the identity in the new frame
      final match = _findSubjectMatch(identity, detectedSubjects);

      if (match != null) {
        // Subject remains in frame, update tracking natively
        identity.isPresentInCurrentFrame = true;
        identity.framesSinceLastSeen = 0;
        _updateSubIdentities(identity, match['sub_components']);
        
        frameTracking[identity.identityId] = TrackingData(
          targetType: 'subject',
          points: {time: {'x': match['x'] ?? 0.0, 'y': match['y'] ?? 0.0, 'scale': match['scale'] ?? 1.0}},
          confidence: 0.95,
        );
      } else {
        // Subject left the frame or is heavily occluded
        identity.isPresentInCurrentFrame = false;
        identity.framesSinceLastSeen++;
        
        debugPrint("TEMPORAL TRACKER: '\${identity.semanticName}' lost at time \$time. (Missing for \${identity.framesSinceLastSeen} frames).");
      }
    }
    return frameTracking;
  }

  /// REQUIREMENT: If the subject leaves frame and returns: attempt controlled re-identification.
  /// REQUIREMENT: If ambiguous: pause and request correction. Never silently swap.
  void attemptReIdentification(TemporalIdentity lostIdentity, Map<String, dynamic> newlyDetectedCandidate) {
    debugPrint("TEMPORAL TRACKER: Attempting Re-ID for '\${lostIdentity.semanticName}'...");

    // Mock embedding cosine similarity check
    final double confidenceScore = _calculateSimilarity(
      lostIdentity.baselineReidEmbeddingHash, 
      newlyDetectedCandidate['embedding_hash']
    );

    if (confidenceScore >= _strictReIdThreshold) {
      // Safe, confident reconnection
      debugPrint("TEMPORAL TRACKER: Successful Re-ID (Score: \$confidenceScore). Reconnecting '\${lostIdentity.semanticName}'.");
      lostIdentity.isPresentInCurrentFrame = true;
      lostIdentity.framesSinceLastSeen = 0;
    } else {
      // Too ambiguous (e.g. Person 1 and Person 2 look similar, or lighting changed heavily)
      // Throw exception to freeze the tracker and prompt the UI
      debugPrint("TEMPORAL TRACKER: Re-ID Ambiguous (Score: \$confidenceScore). Halting tracker.");
      throw AmbiguousIdentityException(lostIdentity);
    }
  }

  Map<String, dynamic>? _findSubjectMatch(TemporalIdentity identity, List<Map<String, dynamic>> subjects) {
    // In production, uses Intersection over Union (IoU) of bounding boxes 
    // and optical flow to confidently track continuous presence.
    // Simulating a successful continuous track for this frame:
    if (identity.framesSinceLastSeen > 0) return null; // Already lost
    return {'id': identity.identityId, 'sub_components': [], 'x': 0.5, 'y': 0.5, 'scale': 1.0}; 
  }

  void _updateSubIdentities(TemporalIdentity parent, List<dynamic> subComponents) {
    // Because the parent is stabilized, the children (face, hair, shirt) 
    // are strictly constrained within the parent's bounding box,
    // maintaining the structural hierarchy safely.
  }

  double _calculateSimilarity(String baselineHash, String candidateHash) {
    // Mock similarity
    return 0.85; // Simulated low-confidence score representing ambiguity
  }
}
