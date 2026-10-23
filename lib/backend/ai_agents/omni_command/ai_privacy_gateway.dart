import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'model_routing_layer.dart';

enum DataClassification {
  PUBLIC,
  PRIVATE,
  SENSITIVE,
  ENCRYPTED,
  USER_APPROVED_AI_CONTEXT,
}

enum AiPermission {
  ALLOW_ALL,
  ALLOW_ZERO_RETENTION_ONLY,
  DENY_ALL,
}

class ProviderPolicy {
  final List<String> allowedProviders;
  final bool requiresZeroRetention;
  final bool requiresSpecificRegion;
  final String? region;

  const ProviderPolicy({
    required this.allowedProviders,
    this.requiresZeroRetention = true,
    this.requiresSpecificRegion = false,
    this.region,
  });
}

class AiRequestPayload {
  final String userId;
  final String sessionId;
  final DataClassification classification;
  final AiPermission aiPermission;
  final bool conversationPermission;
  final ProviderPolicy providerPolicy;
  final TaskClass taskType;
  final String prompt;

  const AiRequestPayload({
    required this.userId,
    required this.sessionId,
    required this.classification,
    required this.aiPermission,
    required this.conversationPermission,
    required this.providerPolicy,
    required this.taskType,
    required this.prompt,
  });
}

final aiPrivacyGatewayProvider = Provider<AiPrivacyGateway>((ref) {
  final router = ref.watch(modelRouterProvider);
  return AiPrivacyGateway(router);
});

class AiPrivacyGateway {
  final ModelRouter _router;

  AiPrivacyGateway(this._router);

  Future<String> executeRequest(AiRequestPayload payload) async {
    // 1. Verify Global Permission
    if (payload.aiPermission == AiPermission.DENY_ALL) {
      throw Exception('AI processing is globally disabled by user.');
    }

    // 2. Verify Conversation-level Permission
    if (!payload.conversationPermission) {
      throw Exception('AI processing is disabled for this specific conversation.');
    }

    // 3. Evaluate Data Classification against Policies
    bool enforceZeroRetention = payload.providerPolicy.requiresZeroRetention;
    
    if (payload.classification == DataClassification.SENSITIVE || 
        payload.classification == DataClassification.PRIVATE) {
      // Force zero retention for sensitive/private data regardless of base policy
      enforceZeroRetention = true;
    }

    if (payload.classification == DataClassification.ENCRYPTED) {
      throw Exception('Encrypted data cannot be sent to external AI providers.');
    }
    
    if (payload.aiPermission == AiPermission.ALLOW_ZERO_RETENTION_ONLY) {
      enforceZeroRetention = true;
    }

    // 4. Route request via ModelRouter
    try {
      final response = await _router.executeWithRouting(
        task: payload.taskType,
        prompt: payload.prompt,
        allowedProviders: payload.providerPolicy.allowedProviders,
        requireZeroDataRetention: enforceZeroRetention,
      );
      
      // 5. Log audit event (Simulated)
      _logAuditEvent(payload, 'SUCCESS');
      
      return response;
    } catch (e) {
      _logAuditEvent(payload, 'FAILED', error: e.toString());
      rethrow;
    }
  }
  
  void _logAuditEvent(AiRequestPayload payload, String status, {String? error}) {
    // In production, write this to an immutable audit log sink (e.g. BigQuery or a secured Firestore collection)
    print('AUDIT [AI_GATEWAY]: User \${payload.userId} | Session \${payload.sessionId} | '
          'Class: \${payload.classification.name} | Status: \$status | Error: \$error');
  }
}
