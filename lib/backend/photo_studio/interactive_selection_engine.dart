import 'package:flutter/foundation.dart';
import 'dart:ui';
import '../mask_engine/universal_mask_models.dart';

/// The type of physical interaction the user performed.
enum InteractiveInputType {
  tap,           // Single point
  tapModifier,   // Point with Add/Subtract intention
  brush,         // Series of points (stroke)
  box,           // Bounding box
  polygon,       // Enclosed lasso
  text,          // NLP prompt
}

/// The logical intent of the interaction.
enum SelectionIntent {
  newSelection, // Clears history, starts fresh
  add,          // Expands the mask
  subtract,     // Chips away at the mask
}

/// A structured payload representing one step in an iterative selection loop.
class InteractiveInput {
  final InteractiveInputType type;
  final SelectionIntent intent;
  
  /// The physical data (Offset for tap, Rect for box, List<Offset> for brush/polygon, String for text)
  final dynamic payload;

  const InteractiveInput({
    required this.type,
    required this.intent,
    required this.payload,
  });

  Map<String, dynamic> toJson() {
    // Serialization for the FFI/Network boundary
    dynamic serializedPayload;
    if (payload is Offset) {
      serializedPayload = {'x': (payload as Offset).dx, 'y': (payload as Offset).dy};
    } else if (payload is Rect) {
      final r = payload as Rect;
      serializedPayload = {'l': r.left, 't': r.top, 'r': r.right, 'b': r.bottom};
    } else if (payload is List<Offset>) {
      serializedPayload = (payload as List<Offset>).map((p) => {'x': p.dx, 'y': p.dy}).toList();
    } else if (payload is String) {
      serializedPayload = payload;
    }

    return {
      'type': type.name,
      'intent': intent.name,
      'data': serializedPayload,
    };
  }
}

/// Advanced engine managing stateful, iterative segmentation loops (e.g. SAM 2).
class InteractiveSelectionEngine {
  
  /// Processes a new user interaction and refines the current mask state.
  /// 
  /// REQUIREMENT: Each additional user interaction refines the existing mask.
  /// REQUIREMENT: Do not regenerate from scratch unnecessarily.
  static Future<UniversalMask> processInteractiveInput({
    required String projectId,
    required String mediaId,
    required InteractiveInput input,
    required UniversalMask? previousMaskState, // Crucial for stateful refinement
  }) async {
    
    // Construct the payload for the AI Decoder
    final Map<String, dynamic> inferencePayload = {
      'new_prompt': input.toJson(),
    };

    // To prevent unnecessary cold-starts and full-image encoding, we feed the
    // mathematical history of the mask (e.g. SAM's previous mask logits) back into the engine.
    if (previousMaskState != null && input.intent != SelectionIntent.newSelection) {
      inferencePayload['previous_mask_logits_ref'] = previousMaskState.id;
      inferencePayload['is_iterative_refinement'] = true;
      debugPrint("AI SELECT ENGINE: Feeding previous mask state (\${previousMaskState.id}) into decoder for efficient refinement.");
    } else {
      inferencePayload['is_iterative_refinement'] = false;
      debugPrint("AI SELECT ENGINE: Cold start. Generating new object mask from scratch.");
    }

    // Simulate fast inference against the image embeddings
    final bool success = await _executeInteractiveSegmentation(inferencePayload);
    
    if (!success) {
      throw Exception("AI Select failed to resolve a boundary from the interaction.");
    }

    // Output the newly refined state
    return UniversalMask(
      id: 'INTERACTIVE_AI_\${DateTime.now().millisecondsSinceEpoch}',
      projectId: projectId,
      mediaId: mediaId,
      maskType: MaskType.CUSTOM,
      sourceType: MaskSourceType.ai,
      operation: MaskOperation.add, // The AI natively outputs the resolved positive mask
      parameters: {
        'interaction_history': [
          if (previousMaskState != null) ...?previousMaskState.parameters['interaction_history'],
          inferencePayload['new_prompt'],
        ],
        'model': 'Interactive_SAM2_Decoder',
      },
      createdBy: 'interactive_selection_engine',
      createdAt: previousMaskState?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Mock network/FFI layer to the segmentation decoder.
  static Future<bool> _executeInteractiveSegmentation(Map<String, dynamic> payload) async {
    await Future.delayed(const Duration(milliseconds: 80)); // 80ms target for 12fps real-time interactive feel
    return true; 
  }
}
