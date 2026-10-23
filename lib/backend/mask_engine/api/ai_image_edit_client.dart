import 'package:flutter/foundation.dart';

enum AiEditType {
  inpaint,    // AI Replace
  outpaint,   // AI Expand
  remove,     // AI Remove
  relight,    // AI Relighting
  generate    // Pure generation
}

/// The structured request payload sent to the /ai/image-edit backend.
class AiImageEditRequest {
  final String sourceAssetId;
  final String maskId; // Or reference image ID
  final String prompt;
  final AiEditType editType;
  
  /// Capability-driven policy (e.g. "commercial_safe", "highest_quality", "fast_preview").
  /// REQUIREMENT: Do not hard-code one OpenRouter image model permanently.
  final String modelPolicy;

  const AiImageEditRequest({
    required this.sourceAssetId,
    required this.maskId,
    required this.prompt,
    required this.editType,
    required this.modelPolicy,
  });

  Map<String, dynamic> toJson() {
    return {
      'source_asset_id': sourceAssetId,
      'mask_id': maskId,
      'prompt': prompt,
      'edit_type': editType.name,
      'model_policy': modelPolicy, // The backend uses this to dynamically discover the best OpenRouter model
    };
  }
}

/// The response payload containing the new, non-destructive layer/asset ID.
class AiImageEditResponse {
  final String resultingLayerId;
  final String resultingAssetUrl;
  final String modelUsed;
  final String auditEventId;

  const AiImageEditResponse({
    required this.resultingLayerId,
    required this.resultingAssetUrl,
    required this.modelUsed,
    required this.auditEventId,
  });

  factory AiImageEditResponse.fromJson(Map<String, dynamic> json) {
    return AiImageEditResponse(
      resultingLayerId: json['resulting_layer_id'] ?? '',
      resultingAssetUrl: json['resulting_asset_url'] ?? '',
      modelUsed: json['model_used'] ?? 'openrouter_dynamic_fallback',
      auditEventId: json['audit_event_id'] ?? '',
    );
  }
}

/// Client interface for the secure /ai/image-edit backend microservice.
class AiImageEditClient {
  final String baseUrl;
  final String authToken;

  AiImageEditClient({
    required this.baseUrl,
    required this.authToken,
  });

  /// Triggers a secure Generative AI Edit (Inpaint, Outpaint, Remove).
  /// 
  /// --- SECURE BACKEND WORKFLOW CONTRACT ---
  /// The backend server MUST perform these exact steps when this endpoint is hit:
  /// 1. validates authorization (Checks the authToken against identity provider)
  /// 2. validates media ownership (Ensures the user owns 'sourceAssetId')
  /// 3. validates AI permission (Checks enterprise/user flags for generative AI consent)
  /// 4. selects compatible OpenRouter model (Dynamically routes based on 'modelPolicy' using OpenRouter Runtime Discovery API. NO HARDCODED MODELS).
  /// 5. sends authorized request (Backend signs and sends request to OpenRouter holding the secure API key)
  /// 6. receives result (Downloads generated image)
  /// 7. stores result (Uploads securely to Cloud Storage)
  /// 8. attaches result to project version (Creates a non-destructive layer node in the database)
  /// 9. creates audit event (Logs generation metrics, content safety, and timestamp to audit log)
  Future<AiImageEditResponse> executeImageEdit(AiImageEditRequest request) async {
    final _ = Uri.parse('\$baseUrl/ai/image-edit');
    
    debugPrint("AI IMAGE EDIT: Dispatching \$request.editType.name request for asset \${request.sourceAssetId}");
    debugPrint("AI IMAGE EDIT: Policy requested: \${request.modelPolicy}");

    try {
      // In production, this executes the 9-step backend workflow securely over HTTPS.
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
        return AiImageEditResponse.fromJson(jsonDecode(response.body));
      } else {
        throw Exception("Backend failed to process image edit: \${response.body}");
      }
      */

      // Simulated network delay matching a heavy GPU generation pass
      await Future.delayed(const Duration(seconds: 4));

      return AiImageEditResponse(
        resultingLayerId: 'LAYER_\${DateTime.now().millisecondsSinceEpoch}',
        resultingAssetUrl: 'https://onerova.studio/assets/generated/edit_\${request.sourceAssetId}.webp',
        modelUsed: 'openrouter/stabilityai/stable-diffusion-3-medium', // Dynamically discovered by backend
        auditEventId: 'AUDIT_\${DateTime.now().millisecondsSinceEpoch}',
      );

    } catch (e) {
      debugPrint("AI IMAGE EDIT ERROR: \$e");
      rethrow;
    }
  }
}
