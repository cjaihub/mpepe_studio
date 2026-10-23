import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../hub/messaging/openrouter_models_provider.dart';

enum AiTaskType {
  chat,
  reasoning,
  vision,
  imageEdit,
  imageGeneration,
  videoAnalysis,
  audio,
  transcription,
  tts,
  embedding,
  reranking,
}

class ModelRegistry {
  final List<OpenRouterModel> _models = List.from(kCuratedOpenRouterModels);
  bool _initialized = false;
  DateTime? _lastFetch;

  Future<void> fetchCatalogIfNeeded() async {
    if (_initialized && _lastFetch != null && DateTime.now().difference(_lastFetch!).inHours < 1) {
      return;
    }
    try {
      final response = await http.get(Uri.parse('https://openrouter.ai/api/v1/models'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> modelList = data['data'] ?? [];
        _models.clear();
        _models.addAll(kCuratedOpenRouterModels);

        for (var m in modelList) {
          try {
            final parsed = OpenRouterModel.fromJson(m as Map<String, dynamic>);
            if (!_models.any((existing) => existing.id == parsed.id)) {
              _models.add(parsed);
            }
          } catch (_) {}
        }
        _initialized = true;
        _lastFetch = DateTime.now();
      }
    } catch (e) {
      debugPrint("Failed to fetch OpenRouter models: $e");
    }
  }

  List<OpenRouterModel> get models => _models;
}

class CapabilityResolver {
  final ModelRegistry registry;

  CapabilityResolver(this.registry);

  List<OpenRouterModel> resolveCompatibleModels(AiTaskType taskType) {
    return registry.models.where((model) {
      if (model.id == 'auto') return false; // Routing resolves actual underlying models

      switch (taskType) {
        case AiTaskType.chat:
          return true;
        case AiTaskType.reasoning:
          return model.isReasoning || model.id.contains('sonnet') || model.id.contains('r1') || model.id.contains('gpt-4o');
        case AiTaskType.vision:
        case AiTaskType.videoAnalysis:
          return model.isVision;
        case AiTaskType.imageGeneration:
        case AiTaskType.imageEdit:
          return model.id.contains('diffusion') || model.id.contains('image') || model.id.contains('flux');
        case AiTaskType.audio:
        case AiTaskType.transcription:
          return model.id.contains('whisper') || model.id.contains('audio') || model.id.contains('gpt-4o');
        case AiTaskType.tts:
          return model.id.contains('tts') || model.id.contains('speech');
        case AiTaskType.embedding:
          return model.id.contains('embedding') || model.id.contains('embed');
        case AiTaskType.reranking:
          return model.id.contains('rerank');
      }
    }).toList();
  }
}

class FallbackPolicy {
  final int maxRetries;
  final Duration initialDelay;

  FallbackPolicy({
    this.maxRetries = 3,
    this.initialDelay = const Duration(seconds: 1),
  });

  Future<T> executeWithFallback<T>(
    List<OpenRouterModel> compatibleModels,
    Future<T> Function(OpenRouterModel model) executor,
  ) async {
    if (compatibleModels.isEmpty) {
      throw Exception("No compatible models found for the requested task.");
    }

    int attempts = 0;
    while (attempts < maxRetries && attempts < compatibleModels.length) {
      final model = compatibleModels[attempts];
      try {
        return await executor(model);
      } catch (e) {
        attempts++;
        debugPrint("Model ${model.id} failed. Attempt $attempts/$maxRetries. Error: $e");
        if (attempts >= maxRetries || attempts >= compatibleModels.length) {
          rethrow;
        }
        await Future.delayed(initialDelay * attempts);
      }
    }
    throw Exception("All compatible models failed.");
  }
}

class ModelRouter {
  final ModelRegistry registry;
  final CapabilityResolver resolver;
  final FallbackPolicy fallbackPolicy;

  ModelRouter({
    required this.registry,
    required this.resolver,
    required this.fallbackPolicy,
  });

  Future<T> routeTask<T>(
    AiTaskType taskType,
    Future<T> Function(OpenRouterModel model) executor,
  ) async {
    await registry.fetchCatalogIfNeeded();
    final compatibleModels = resolver.resolveCompatibleModels(taskType);

    // Sort models prioritizing top tier models
    compatibleModels.sort((a, b) {
      if (taskType == AiTaskType.vision || taskType == AiTaskType.videoAnalysis) {
        if (a.id.contains('gemini-2.5-flash') || a.id.contains('gpt-4o')) return -1;
        if (b.id.contains('gemini-2.5-flash') || b.id.contains('gpt-4o')) return 1;
      }
      if (taskType == AiTaskType.reasoning) {
        if (a.id.contains('claude-3.5-sonnet') || a.id.contains('deepseek-r1')) return -1;
        if (b.id.contains('claude-3.5-sonnet') || b.id.contains('deepseek-r1')) return 1;
      }
      return 0;
    });

    return fallbackPolicy.executeWithFallback<T>(compatibleModels, executor);
  }
}

final aiModelRegistryProvider = Provider((ref) => ModelRegistry());
final aiCapabilityResolverProvider = Provider((ref) => CapabilityResolver(ref.read(aiModelRegistryProvider)));
final aiFallbackPolicyProvider = Provider((ref) => FallbackPolicy());
final aiModelRouterProvider = Provider((ref) {
  return ModelRouter(
    registry: ref.read(aiModelRegistryProvider),
    resolver: ref.read(aiCapabilityResolverProvider),
    fallbackPolicy: ref.read(aiFallbackPolicyProvider),
  );
});
