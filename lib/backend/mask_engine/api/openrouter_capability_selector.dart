import 'package:flutter/foundation.dart';

/// Represents the exhaustive capabilities a model advertises.
class ModelCapabilityMetadata {
  final String modelId;
  final bool supportsEditing; // inpainting/outpainting
  final bool supportsMultiReference; // > 1 reference images
  final bool supportsImageUnderstanding; // vision/VLM
  final int maxImageWidth;
  final int maxImageHeight;
  final double costPerMegapixel; // relative pricing
  final double averageLatencySeconds; // relative speed
  final bool isPrivacyCompliant; // No data retention/training

  const ModelCapabilityMetadata({
    required this.modelId,
    required this.supportsEditing,
    required this.supportsMultiReference,
    required this.supportsImageUnderstanding,
    required this.maxImageWidth,
    required this.maxImageHeight,
    required this.costPerMegapixel,
    required this.averageLatencySeconds,
    required this.isPrivacyCompliant,
  });
}

/// The specific requirements and constraints for the current AI task.
class AiTaskConstraints {
  final String taskType; // 'fast preview', 'high quality generation', 'reference edit', 'multi-reference', 'image understanding'
  final int requestedWidth;
  final int requestedHeight;
  final int numberOfReferences;
  final bool requiresEditing;
  final double maxLatencySeconds; // e.g. 2.0 for fast proxy, 15.0 for high quality
  final bool prioritizeQuality;
  final double maxBudgetPerGeneration;
  final bool requiresStrictPrivacy;

  const AiTaskConstraints({
    required this.taskType,
    required this.requestedWidth,
    required this.requestedHeight,
    required this.numberOfReferences,
    required this.requiresEditing,
    required this.maxLatencySeconds,
    required this.prioritizeQuality,
    required this.maxBudgetPerGeneration,
    required this.requiresStrictPrivacy,
  });
}

class CapabilityNotAvailableException implements Exception {
  final String message;
  CapabilityNotAvailableException([this.message = "CAPABILITY_NOT_AVAILABLE"]);
  @override
  String toString() => message;
}

/// Advanced engine that dynamically routes requests to the appropriate OpenRouter model
/// strictly based on mathematical capability matching, completely avoiding hardcoded endpoints.
class OpenRouterCapabilitySelector {
  
  // Simulated runtime registry of OpenRouter models and their advertised capabilities.
  // In production, this would be periodically fetched from the OpenRouter API.
  static final List<ModelCapabilityMetadata> _modelRegistry = [
    const ModelCapabilityMetadata(
      modelId: 'openrouter/stabilityai/stable-diffusion-xl',
      supportsEditing: true,
      supportsMultiReference: false,
      supportsImageUnderstanding: false,
      maxImageWidth: 1024,
      maxImageHeight: 1024,
      costPerMegapixel: 0.005,
      averageLatencySeconds: 4.5,
      isPrivacyCompliant: true,
    ),
    const ModelCapabilityMetadata(
      modelId: 'openrouter/fast-proxy-model/v1',
      supportsEditing: false,
      supportsMultiReference: false,
      supportsImageUnderstanding: false,
      maxImageWidth: 512,
      maxImageHeight: 512,
      costPerMegapixel: 0.001,
      averageLatencySeconds: 0.8,
      isPrivacyCompliant: true,
    ),
    const ModelCapabilityMetadata(
      modelId: 'openrouter/anthropic/claude-3.5-sonnet',
      supportsEditing: false,
      supportsMultiReference: true,
      supportsImageUnderstanding: true,
      maxImageWidth: 4096,
      maxImageHeight: 4096,
      costPerMegapixel: 0.015,
      averageLatencySeconds: 6.0,
      isPrivacyCompliant: true,
    ),
    const ModelCapabilityMetadata(
      modelId: 'openrouter/proprietary/high-res-editor',
      supportsEditing: true,
      supportsMultiReference: true,
      supportsImageUnderstanding: false,
      maxImageWidth: 2048,
      maxImageHeight: 2048,
      costPerMegapixel: 0.05,
      averageLatencySeconds: 12.0,
      isPrivacyCompliant: false, // Trains on user data
    ),
  ];

  /// Evaluates the task constraints against the capability registry and returns the optimal model ID.
  /// 
  /// REQUIREMENT: If no compatible model exists, return CAPABILITY_NOT_AVAILABLE.
  /// REQUIREMENT: Never make an incompatible API call simply to attempt a feature.
  static String resolveOptimalModel(AiTaskConstraints constraints) {
    debugPrint("CAPABILITY ROUTER: Evaluating models for task: \${constraints.taskType}...");

    List<ModelCapabilityMetadata> eligibleModels = _modelRegistry.where((model) {
      // 1. Strict Parameter Checks (Eliminators)
      if (constraints.requiresStrictPrivacy && !model.isPrivacyCompliant) return false;
      if (constraints.requiresEditing && !model.supportsEditing) return false;
      if (constraints.numberOfReferences > 1 && !model.supportsMultiReference) return false;
      if (constraints.taskType == 'image understanding' && !model.supportsImageUnderstanding) return false;
      
      // 2. Geometry & Budget Checks
      if (constraints.requestedWidth > model.maxImageWidth || constraints.requestedHeight > model.maxImageHeight) return false;
      if (model.averageLatencySeconds > constraints.maxLatencySeconds) return false;
      if (model.costPerMegapixel > constraints.maxBudgetPerGeneration) return false;

      return true;
    }).toList();

    // 3. Absolute Constraint Failure State
    if (eligibleModels.isEmpty) {
      debugPrint("CAPABILITY ROUTER: No models passed the strict capability checks. Aborting.");
      throw CapabilityNotAvailableException();
    }

    // 4. Quality vs Speed Optimization
    if (constraints.prioritizeQuality) {
      // Sort by cost/capability (proxy for quality) descending
      eligibleModels.sort((a, b) => b.costPerMegapixel.compareTo(a.costPerMegapixel));
    } else {
      // Sort by latency ascending for fast previews
      eligibleModels.sort((a, b) => a.averageLatencySeconds.compareTo(b.averageLatencySeconds));
    }

    final selectedModel = eligibleModels.first.modelId;
    debugPrint("CAPABILITY ROUTER: Successfully resolved optimal model -> \$selectedModel");
    
    return selectedModel;
  }
}
