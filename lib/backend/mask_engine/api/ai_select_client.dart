import 'dart:ui';
import 'package:flutter/foundation.dart';

/// Represents the exhaustive list of /ai/select/ operations
enum AiSelectorType {
  subject,
  person,
  face,
  skin,
  hair,
  eyes,
  mouth,
  teeth,
  object,
  background,
  sky,
  depth,
  color,
  luminance,
  custom
}

extension AiSelectorTypeExtension on AiSelectorType {
  String get endpoint => '/ai/select/\${name.toLowerCase()}';
}

/// The structured request payload sent to the backend.
/// 
/// REQUIREMENT: Never expose model credentials to mobile clients.
/// Notice that there are NO API keys or model selection parameters here.
/// The backend securely holds the credentials and decides which model to route to.
class AiSelectRequest {
  final String mediaId;
  final String? frameId;
  final AiSelectorType selectorType;
  final String? prompt;
  final List<Offset>? interactionPoints;
  final List<Rect>? interactionBoxes;
  final String? existingMaskId;
  final Map<String, dynamic> parameters;

  const AiSelectRequest({
    required this.mediaId,
    this.frameId,
    required this.selectorType,
    this.prompt,
    this.interactionPoints,
    this.interactionBoxes,
    this.existingMaskId,
    this.parameters = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'media_id': mediaId,
      'frame_id': frameId,
      'selector_type': selectorType.name,
      'prompt': prompt,
      'interaction_points': interactionPoints?.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      'interaction_boxes': interactionBoxes?.map((b) => {'left': b.left, 'top': b.top, 'right': b.right, 'bottom': b.bottom}).toList(),
      'existing_mask_id': existingMaskId,
      'parameters': parameters,
    };
  }
}

/// The structured response payload returned by the backend.
class AiSelectResponse {
  final String maskId;
  final int maskVersion;
  final String model;
  final String modelVersion;
  final double confidence; // Confidence/quality metric
  final String? previewUrl; // Low-res fast proxy URL
  final String processingStatus;

  const AiSelectResponse({
    required this.maskId,
    required this.maskVersion,
    required this.model,
    required this.modelVersion,
    required this.confidence,
    this.previewUrl,
    required this.processingStatus,
  });

  factory AiSelectResponse.fromJson(Map<String, dynamic> json) {
    return AiSelectResponse(
      maskId: json['mask_id'] ?? '',
      maskVersion: json['mask_version'] ?? 1,
      model: json['model'] ?? 'unknown_model',
      modelVersion: json['model_version'] ?? '1.0',
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      previewUrl: json['preview'],
      processingStatus: json['processing_status'] ?? 'completed',
    );
  }
}

/// The dedicated backend client for interacting with the /ai/select/ microservice.
class AiSelectClient {
  final String baseUrl;
  final String authToken; // User auth token, NOT a model credential.

  AiSelectClient({
    required this.baseUrl,
    required this.authToken,
  });

  /// Executes the segmentation request against the secure backend.
  Future<AiSelectResponse> executeSelection(AiSelectRequest request) async {
    final _ = Uri.parse('\$baseUrl\${request.selectorType.endpoint}');
    
    debugPrint("AI SELECT: Dispatching request to \$endpointUrl");
    
    try {
      // In a real implementation, this hits the backend microservice.
      // The backend validates the user's authToken, retrieves the secure OpenAI/OpenRouter 
      // or custom CV model credentials from a secure Secret Manager, and proxies the request.
      
      /*
      final response = await http.post(
        endpointUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer \$authToken', 
        },
        body: jsonEncode(request.toJson()),
      );

      if (response.statusCode == 200) {
        return AiSelectResponse.fromJson(jsonDecode(response.body));
      } else {
        throw Exception("Backend failed to process selection: \${response.body}");
      }
      */

      // Simulated network delay and successful response for development
      await Future.delayed(const Duration(milliseconds: 800));
      return AiSelectResponse(
        maskId: 'MASK_\${DateTime.now().millisecondsSinceEpoch}',
        maskVersion: 1,
        model: request.selectorType == AiSelectorType.custom ? 'openrouter_semantic_v2' : 'oneova_deterministic_cv',
        modelVersion: '2.1.0',
        confidence: 0.94,
        previewUrl: 'https://onerova.studio/previews/proxy_\${request.mediaId}.webp',
        processingStatus: 'fast_preview_ready',
      );

    } catch (e) {
      debugPrint("AI SELECT ERROR: \$e");
      rethrow;
    }
  }
}
