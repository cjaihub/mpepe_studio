import 'package:flutter_riverpod/flutter_riverpod.dart';

enum TaskClass {
  CHAT,
  REASONING,
  VISION,
  IMAGE_EDIT,
  IMAGE_GENERATION,
  VIDEO_ANALYSIS,
  AUDIO,
  TRANSCRIPTION,
  TTS,
  EMBEDDING,
  RERANKING,
}

class AiModel {
  final String id;
  final String provider;
  final List<TaskClass> capabilities;
  final double contextWindow;
  final double costPer1k;
  final bool isZeroDataRetention;

  const AiModel({
    required this.id,
    required this.provider,
    required this.capabilities,
    required this.contextWindow,
    required this.costPer1k,
    this.isZeroDataRetention = false,
  });
}

class FallbackPolicy {
  final int maxRetries;
  final bool fallbackOnRateLimit;
  final bool fallbackOnDowntime;
  
  const FallbackPolicy({
    this.maxRetries = 3,
    this.fallbackOnRateLimit = true,
    this.fallbackOnDowntime = true,
  });
}

class ModelRegistry {
  // In a real app, this would fetch from OpenRouter's model endpoint and cache it.
  // For now, we simulate the OpenRouter catalog.
  final List<AiModel> _catalog = const [
    AiModel(
      id: 'openai/gpt-4o',
      provider: 'openai',
      capabilities: [TaskClass.CHAT, TaskClass.REASONING, TaskClass.VISION],
      contextWindow: 128000,
      costPer1k: 0.005,
      isZeroDataRetention: true,
    ),
    AiModel(
      id: 'anthropic/claude-3.5-sonnet',
      provider: 'anthropic',
      capabilities: [TaskClass.CHAT, TaskClass.REASONING, TaskClass.VISION],
      contextWindow: 200000,
      costPer1k: 0.003,
      isZeroDataRetention: true,
    ),
    AiModel(
      id: 'google/gemini-pro-1.5',
      provider: 'google',
      capabilities: [TaskClass.CHAT, TaskClass.REASONING, TaskClass.VISION, TaskClass.VIDEO_ANALYSIS],
      contextWindow: 2000000,
      costPer1k: 0.001,
      isZeroDataRetention: false,
    ),
    AiModel(
      id: 'stability/stable-diffusion-xl',
      provider: 'stability',
      capabilities: [TaskClass.IMAGE_GENERATION, TaskClass.IMAGE_EDIT],
      contextWindow: 0,
      costPer1k: 0.02,
    ),
    AiModel(
      id: 'jina/jina-embeddings-v2',
      provider: 'jina',
      capabilities: [TaskClass.EMBEDDING],
      contextWindow: 8192,
      costPer1k: 0.0001,
    )
  ];

  List<AiModel> getAvailableModels() => _catalog;
}

class CapabilityResolver {
  final ModelRegistry registry;

  CapabilityResolver(this.registry);

  List<AiModel> resolveForTask(TaskClass task) {
    return registry.getAvailableModels().where((model) => model.capabilities.contains(task)).toList();
  }
}

final modelRouterProvider = Provider<ModelRouter>((ref) {
  final registry = ModelRegistry();
  final resolver = CapabilityResolver(registry);
  return ModelRouter(resolver);
});

class ModelRouter {
  final CapabilityResolver resolver;
  final FallbackPolicy defaultFallback = const FallbackPolicy();

  ModelRouter(this.resolver);

  Future<String> executeWithRouting({
    required TaskClass task,
    required String prompt,
    List<String>? allowedProviders,
    bool requireZeroDataRetention = false,
  }) async {
    // 1. Resolve candidates
    List<AiModel> candidates = resolver.resolveForTask(task);

    // 2. Apply strict filters (Privacy/Permissions)
    if (allowedProviders != null) {
      candidates = candidates.where((m) => allowedProviders.contains(m.provider)).toList();
    }
    if (requireZeroDataRetention) {
      candidates = candidates.where((m) => m.isZeroDataRetention).toList();
    }

    if (candidates.isEmpty) {
      throw Exception('No compatible models found for task: \$task given current constraints.');
    }

    // 3. Sort by cost or user preference (simplistic cost sorting here)
    candidates.sort((a, b) => a.costPer1k.compareTo(b.costPer1k));

    // 4. Execution loop with fallback
    for (int attempt = 0; attempt < candidates.length; attempt++) {
      final model = candidates[attempt];
      try {
        return await _invokeOpenRouterAPI(model.id, prompt);
      } catch (e) {
        // Log failure
        print('Model \${model.id} failed: \$e');
        
        // Apply fallback policy logic
        if (!defaultFallback.fallbackOnDowntime && e.toString().contains('500')) {
          rethrow;
        }
        
        if (attempt == candidates.length - 1) {
          throw Exception('All fallback models exhausted for task: \$task');
        }
        // Continue to next candidate
      }
    }
    throw Exception('Routing failed.');
  }

  Future<String> _invokeOpenRouterAPI(String modelId, String prompt) async {
    // Simulate network call
    await Future.delayed(const Duration(milliseconds: 500));
    // Simulate failure randomly
    if (modelId == 'openai/gpt-4o' && DateTime.now().second % 2 == 0) {
      throw Exception('Simulated Rate Limit 429');
    }
    return 'Response from \$modelId for prompt: \$prompt';
  }
}
