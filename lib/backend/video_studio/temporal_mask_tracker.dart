import 'package:flutter/foundation.dart';
import '../mask_engine/universal_mask_models.dart';
import '../mask_engine/mask_quality_metrics.dart';

/// The requested UI operations for temporal propagation.
enum TrackingDirection {
  trackForward,
  trackBackward,
  trackEntireClip,
}

/// Real-time status payload sent to the UI during video tracking.
class TrackingStatusPayload {
  final bool isTracking;
  final bool needsCorrection;
  final double currentFrameTime;
  final double lastSuccessfulFrameTime;
  final String? message;
  
  /// The live Mask node generated for the current frame.
  final UniversalMask? activeMask;

  const TrackingStatusPayload({
    required this.isTracking,
    this.needsCorrection = false,
    required this.currentFrameTime,
    required this.lastSuccessfulFrameTime,
    this.message,
    this.activeMask,
  });
}

/// Advanced subsystem extending the UniversalMask engine into 4D space (Video/Time).
class TemporalMaskTracker {
  
  /// Simulates a stream of tracked masks. In production, this binds to the C++/FFI layer
  /// running optical flow or models like SAM 2 Video on the background thread.
  /// 
  /// REQUIREMENT: When tracking confidence drops: pause automatic propagation.
  /// REQUIREMENT: Show: "Tracking needs correction".
  /// REQUIREMENT: Do not continue silently with an incorrect mask.
  static Stream<TrackingStatusPayload> executeTemporalTracking({
    required UniversalMask initialKeyframeMask,
    required double startFrameTime,
    required TrackingDirection direction,
    required double clipDuration,
  }) async* {
    
    // Safety check: a tracked mask must have a tracking reference ID
    final trackingId = initialKeyframeMask.trackingReference ?? 'TEMPORAL_ID_\${DateTime.now().millisecondsSinceEpoch}';

    double currentTime = startFrameTime;
    double lastSafeTime = startFrameTime;
    bool movingForward = direction == TrackingDirection.trackForward || direction == TrackingDirection.trackEntireClip;
    
    // We update the original mask to indicate it is now a temporal anchor
    UniversalMask currentMask = initialKeyframeMask.copyWith(
      sourceType: MaskSourceType.tracked,
      trackingReference: trackingId,
      parameters: {
        ...initialKeyframeMask.parameters,
        'is_keyframe': true, // User manual/initial corrections are keyframes
      }
    );

    yield TrackingStatusPayload(
      isTracking: true,
      currentFrameTime: currentTime,
      lastSuccessfulFrameTime: lastSafeTime,
      activeMask: currentMask,
    );

    // Mock temporal propagation loop
    while (currentTime >= 0.0 && currentTime <= clipDuration) {
      await Future.delayed(const Duration(milliseconds: 30)); // Mocking frame processing time

      // Advance time based on FPS (e.g. 24fps = 0.041s per frame)
      currentTime += movingForward ? 0.041 : -0.041;

      // 1. Ask the AI engine to propagate the mask to the new frame, 
      // utilizing occlusion handling and re-identification logic.
      final propagatedMask = currentMask.copyWith(
        id: '\${trackingId}_FRAME_\$currentTime',
        sourceType: MaskSourceType.tracked,
        parameters: {
          ...currentMask.parameters,
          'is_keyframe': false, // AI interpolated frames are not keyframes
          'occlusion_state': 'visible', // 'occluded', 'disappeared', 're-identified'
        }
      );

      // 2. Evaluate the health of the propagated mask
      final quality = MaskQualityEngine.evaluateMaskQuality(
        mask: propagatedMask,
        rawModelOutput: {
          'is_calibrated_confidence': true,
          // Simulate a tracking failure at frame 2.0 (Confidence drops drastically)
          'model_confidence': (currentTime > 2.0 && currentTime < 2.5) ? 0.3 : 0.95,
          'tracking_stability': (currentTime > 2.0 && currentTime < 2.5) ? 0.2 : 0.9,
        },
      );

      // 3. Strict Failure Gate
      // If the mask degrades, we MUST halt and request human intervention.
      if (quality.semanticLabel == ConfidenceLabel.needsRefinement) {
        debugPrint("TEMPORAL TRACKER: Mask confidence dropped below threshold at frame \$currentTime. Pausing propagation.");
        
        yield TrackingStatusPayload(
          isTracking: false,
          needsCorrection: true,
          currentFrameTime: currentTime,
          lastSuccessfulFrameTime: lastSafeTime,
          message: 'Tracking needs correction',
          activeMask: propagatedMask, // Show them the broken mask so they can fix it
        );
        
        // Break the loop. The UI must wait for the user to draw a correction stroke,
        // generate a new Keyframe Mask, and call `executeTemporalTracking` again.
        return; 
      }

      // Tracking was successful
      lastSafeTime = currentTime;
      currentMask = propagatedMask; // Update state for the next frame prediction

      yield TrackingStatusPayload(
        isTracking: true,
        currentFrameTime: currentTime,
        lastSuccessfulFrameTime: lastSafeTime,
        activeMask: currentMask,
      );
    }

    // Clip reached
    yield TrackingStatusPayload(
      isTracking: false,
      currentFrameTime: currentTime,
      lastSuccessfulFrameTime: lastSafeTime,
      message: 'Tracking complete',
    );
  }
}
