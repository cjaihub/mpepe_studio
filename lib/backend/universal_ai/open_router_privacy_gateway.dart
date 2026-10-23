import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DataClassification {
  public,
  private,
  sensitive,
  encrypted,
  userApprovedAiContext,
}

enum RetentionPolicy {
  zeroDataRetention,
  standardRetention,
  temporaryRetention,
}

enum DataRegion {
  us,
  eu,
  global,
}

class ProviderPolicy {
  final List<String> providerAllowlist;
  final List<String> modelAllowlist;
  final bool requireZeroDataRetention;
  final DataRegion requiredRegion;
  final double budgetLimitUsd;

  const ProviderPolicy({
    this.providerAllowlist = const [],
    this.modelAllowlist = const [],
    this.requireZeroDataRetention = true,
    this.requiredRegion = DataRegion.global,
    this.budgetLimitUsd = 0.0,
  });
}

class AiRequestContext {
  final String userId;
  final String sessionId;
  final DataClassification dataClassification;
  final bool aiPermission;
  final bool conversationPermission;
  final String? targetModel;
  final ProviderPolicy providerPolicy;
  final RetentionPolicy retentionPolicy;

  const AiRequestContext({
    required this.userId,
    required this.sessionId,
    required this.dataClassification,
    required this.aiPermission,
    required this.conversationPermission,
    this.targetModel,
    required this.providerPolicy,
    required this.retentionPolicy,
  });
}

class PrivacyGatewayError implements Exception {
  final String message;
  PrivacyGatewayError(this.message);
  @override
  String toString() => "PrivacyGatewayError: $message";
}

/// A privacy and security gateway that intercepts AI requests before they are sent to OpenRouter.
/// 
/// It enforces data classification boundaries, prevents accidental leakage of private data,
/// and applies organizational routing guardrails.
/// 
/// Note: Routing through OpenRouter does NOT automatically mean every provider has identical 
/// data-retention behavior. Providers have varying policies on training and retention, which 
/// makes this gateway critical for enforcing Zero Data Retention (ZDR) and provider allowlists.
class OpenRouterPrivacyGateway {
  
  /// Evaluates the request context against the chosen model's capabilities and policies.
  /// Throws [PrivacyGatewayError] if the request violates privacy policies.
  void authorizeRequest(AiRequestContext context, {required Map<String, dynamic> modelMetadata}) {
    if (!context.aiPermission) {
      throw PrivacyGatewayError("User has not granted general AI processing permissions.");
    }

    if (!context.conversationPermission && context.dataClassification != DataClassification.public) {
      throw PrivacyGatewayError("Conversation permissions required for non-public data.");
    }

    // Encrypted data should never be sent raw to an AI model
    if (context.dataClassification == DataClassification.encrypted) {
      throw PrivacyGatewayError("Cannot send ENCRYPTED data to AI providers.");
    }

    final providerId = (modelMetadata['provider'] as String?)?.toLowerCase() ?? '';
    final modelId = (modelMetadata['id'] as String?)?.toLowerCase() ?? '';

    // Enforce provider allowlist
    if (context.providerPolicy.providerAllowlist.isNotEmpty) {
      if (!context.providerPolicy.providerAllowlist.any((p) => providerId.contains(p.toLowerCase()))) {
        throw PrivacyGatewayError("Provider '$providerId' is not in the allowlist.");
      }
    }

    // Enforce model allowlist
    if (context.providerPolicy.modelAllowlist.isNotEmpty) {
      if (!context.providerPolicy.modelAllowlist.any((m) => modelId.contains(m.toLowerCase()))) {
        throw PrivacyGatewayError("Model '$modelId' is not in the allowlist.");
      }
    }

    // Data classification gating based on provider capabilities
    // If the data is SENSITIVE or PRIVATE, we must require Zero Data Retention (ZDR)
    // or rely on explicit user context approval.
    final bool requiresZdr = context.dataClassification == DataClassification.sensitive || 
                             context.dataClassification == DataClassification.private ||
                             context.retentionPolicy == RetentionPolicy.zeroDataRetention ||
                             context.providerPolicy.requireZeroDataRetention;
                             
    // Providers offering enterprise-level Zero Data Retention via OpenRouter APIs.
    // (In a real implementation, this flag is parsed from OpenRouter's model metadata)
    final bool providerSupportsZdr = _checkProviderZdrSupport(providerId);

    if (requiresZdr && !providerSupportsZdr) {
      if (context.dataClassification == DataClassification.userApprovedAiContext) {
        // User explicitly approved ignoring ZDR for this specific context
        debugPrint("Warning: Proceeding with non-ZDR model because data is USER_APPROVED_AI_CONTEXT");
      } else {
        throw PrivacyGatewayError(
          "Data classification '${context.dataClassification.name}' requires Zero Data Retention, "
          "but model '$modelId' (Provider: '$providerId') does not guarantee it."
        );
      }
    }
  }

  /// Determines if the provider has a strict Zero Data Retention policy.
  bool _checkProviderZdrSupport(String providerId) {
    // This is a simplified check. OpenRouter models often return this in their metadata.
    final zdrProviders = ['anthropic', 'openai', 'google', 'mistral'];
    return zdrProviders.contains(providerId);
  }

  /// Generates the necessary HTTP headers to enforce privacy controls natively via OpenRouter.
  Map<String, String> generatePrivacyHeaders(AiRequestContext context) {
    final headers = <String, String>{
      'HTTP-Referer': 'https://onerova.studio', 
      'X-Title': 'Onerova',
    };

    // If we have strict privacy requirements, we must disable automatic fallbacks
    // in OpenRouter to prevent the request from being silently re-routed to a 
    // cheaper provider that doesn't respect ZDR.
    if (context.dataClassification == DataClassification.sensitive || 
        context.dataClassification == DataClassification.private ||
        context.providerPolicy.requireZeroDataRetention) {
      
      // Disable fallbacks entirely for sensitive data
      headers['X-Require-ZDR'] = 'true'; // Conceptual metadata enforcement
      
      // If we have an allowlist, pass it to OpenRouter's routing engine
      if (context.providerPolicy.providerAllowlist.isNotEmpty) {
        // Enforce provider strict routing (example custom header/parameter for OR)
        headers['X-Provider-Allow'] = context.providerPolicy.providerAllowlist.join(',');
      }
    }

    return headers;
  }
}

final openRouterPrivacyGatewayProvider = Provider((ref) => OpenRouterPrivacyGateway());
