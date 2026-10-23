import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../backend/security/secure_api_key_vault.dart';

enum ModelCategory {
  all,
  vision,
  reasoning,
  free,
}

class OpenRouterModel {
  final String id;
  final String name;
  final String provider;
  final String description;
  final int contextLength;
  final bool isVision;
  final bool isReasoning;
  final bool isFree;
  final String? pricingPrompt;
  final String? pricingCompletion;

  const OpenRouterModel({
    required this.id,
    required this.name,
    required this.provider,
    this.description = '',
    this.contextLength = 4096,
    this.isVision = false,
    this.isReasoning = false,
    this.isFree = false,
    this.pricingPrompt,
    this.pricingCompletion,
  });

  factory OpenRouterModel.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? 'unknown';
    final name = json['name'] as String? ?? id;
    final description = json['description'] as String? ?? '';
    final contextLength = (json['context_length'] as num?)?.toInt() ?? 4096;

    final architecture = json['architecture'] as Map<String, dynamic>? ?? {};
    final modality = (architecture['modality'] as String? ?? '').toLowerCase();
    final inputModalities = (architecture['input_modalities'] as List<dynamic>?)
            ?.map((e) => e.toString().toLowerCase())
            .toList() ??
        [];

    final supportedParams = (json['supported_parameters'] as List<dynamic>?)
            ?.map((e) => e.toString().toLowerCase())
            .toList() ??
        [];

    final pricing = json['pricing'] as Map<String, dynamic>? ?? {};
    final promptPrice = pricing['prompt']?.toString() ?? '';
    final completionPrice = pricing['completion']?.toString() ?? '';

    final lowerId = id.toLowerCase();
    final lowerName = name.toLowerCase();

    // Provider parsing
    final providerId = id.contains('/') ? id.split('/').first.toLowerCase() : 'other';
    final provider = _capitalize(providerId);

    // Multimodal / Vision detection:
    // 1. input_modalities contains 'image' or 'multimodal'
    // 2. modality contains 'image->text', 'text+image->text', or 'image'
    // 3. known vision model families (gemini, gpt-4o, claude-3, pixtral, llama-vision, qwen-vl, etc.)
    final bool isVision = inputModalities.contains('image') ||
        inputModalities.contains('multimodal') ||
        modality.contains('image') ||
        lowerId.contains('vision') ||
        lowerId.contains('pixtral') ||
        lowerId.contains('gpt-4o') ||
        lowerId.contains('gemini') ||
        lowerId.contains('claude-3') ||
        lowerId.contains('qwen-vl') ||
        lowerId.contains('vl-') ||
        lowerName.contains('vision') ||
        lowerName.contains('multimodal');

    // Reasoning detection:
    final bool isReasoning = supportedParams.contains('include_reasoning') ||
        lowerId.contains('r1') ||
        lowerId.contains('o1') ||
        lowerId.contains('o3') ||
        lowerId.contains('sonnet') ||
        lowerId.contains('reasoning') ||
        lowerName.contains('reasoning');

    // Free detection:
    final bool isFree = lowerId.endsWith(':free') ||
        (promptPrice == '0' && completionPrice == '0');

    return OpenRouterModel(
      id: id,
      name: name,
      provider: provider,
      description: description,
      contextLength: contextLength,
      isVision: isVision,
      isReasoning: isReasoning,
      isFree: isFree,
      pricingPrompt: promptPrice.isNotEmpty && promptPrice != '0' ? promptPrice : null,
      pricingCompletion: completionPrice.isNotEmpty && completionPrice != '0' ? completionPrice : null,
    );
  }
}

/// Curated high-performance models (always ready even offline)
final List<OpenRouterModel> kCuratedOpenRouterModels = [
  const OpenRouterModel(
    id: 'auto',
    name: '✨ Auto Select (Best for Task)',
    provider: 'Auto',
    description: 'Intelligently routes to Gemini 2.5 Flash for vision/screenshots and Claude 3.5 Sonnet for reasoning.',
    contextLength: 1048576,
    isVision: true,
    isReasoning: true,
    isFree: false,
  ),
  // Top Vision Models
  const OpenRouterModel(
    id: 'google/gemini-2.5-flash',
    name: 'Google: Gemini 2.5 Flash',
    provider: 'Google',
    description: 'Premier ultra-fast multimodal model. High fidelity screenshot & vision understanding with 1M context.',
    contextLength: 1048576,
    isVision: true,
    isReasoning: true,
    isFree: false,
  ),
  const OpenRouterModel(
    id: 'google/gemini-2.0-flash-exp:free',
    name: 'Google: Gemini 2.0 Flash (Free)',
    provider: 'Google',
    description: 'High-speed multimodal vision model with 1M context, completely free of charge.',
    contextLength: 1048576,
    isVision: true,
    isReasoning: false,
    isFree: true,
  ),
  const OpenRouterModel(
    id: 'openai/gpt-4o',
    name: 'OpenAI: GPT-4o',
    provider: 'OpenAI',
    description: 'Flagship omni multimodal model with state-of-the-art vision comprehension and tool calling.',
    contextLength: 128000,
    isVision: true,
    isReasoning: true,
    isFree: false,
  ),
  const OpenRouterModel(
    id: 'openai/gpt-4o-mini',
    name: 'OpenAI: GPT-4o Mini',
    provider: 'OpenAI',
    description: 'Fast, lightweight multimodal vision model with high efficiency.',
    contextLength: 128000,
    isVision: true,
    isReasoning: false,
    isFree: false,
  ),
  const OpenRouterModel(
    id: 'anthropic/claude-3.5-sonnet',
    name: 'Anthropic: Claude 3.5 Sonnet',
    provider: 'Anthropic',
    description: 'Leading benchmark in multimodal vision, diagram parsing, and complex reasoning.',
    contextLength: 200000,
    isVision: true,
    isReasoning: true,
    isFree: false,
  ),
  const OpenRouterModel(
    id: 'meta-llama/llama-3.2-11b-vision-instruct',
    name: 'Meta: Llama 3.2 11B Vision',
    provider: 'Meta',
    description: 'Open-weights high performance image and document visual reasoning.',
    contextLength: 128000,
    isVision: true,
    isReasoning: false,
    isFree: false,
  ),
  const OpenRouterModel(
    id: 'meta-llama/llama-3.2-11b-vision-instruct:free',
    name: 'Meta: Llama 3.2 11B Vision (Free)',
    provider: 'Meta',
    description: 'Free community tier for Llama 3.2 visual analysis.',
    contextLength: 128000,
    isVision: true,
    isReasoning: false,
    isFree: true,
  ),
  const OpenRouterModel(
    id: 'mistralai/pixtral-12b',
    name: 'Mistral: Pixtral 12B',
    provider: 'Mistral',
    description: 'Native multimodal vision architecture from Mistral AI.',
    contextLength: 128000,
    isVision: true,
    isReasoning: false,
    isFree: false,
  ),
  const OpenRouterModel(
    id: 'qwen/qwen-2-vl-72b-instruct',
    name: 'Qwen: Qwen 2 VL 72B',
    provider: 'Qwen',
    description: 'Top-tier visual question answering, OCR, and document understanding.',
    contextLength: 32768,
    isVision: true,
    isReasoning: true,
    isFree: false,
  ),
  // Top Reasoning Models
  const OpenRouterModel(
    id: 'deepseek/deepseek-r1',
    name: 'DeepSeek: R1',
    provider: 'Deepseek',
    description: 'Advanced open reasoning model with chain-of-thought verification.',
    contextLength: 64000,
    isVision: false,
    isReasoning: true,
    isFree: false,
  ),
  const OpenRouterModel(
    id: 'deepseek/deepseek-r1:free',
    name: 'DeepSeek: R1 (Free)',
    provider: 'Deepseek',
    description: 'Free community tier for DeepSeek R1 reasoning.',
    contextLength: 64000,
    isVision: false,
    isReasoning: true,
    isFree: true,
  ),
  const OpenRouterModel(
    id: 'meta-llama/llama-3-8b-instruct:free',
    name: 'Meta: Llama 3 8B (Free)',
    provider: 'Meta',
    description: 'Fast, free general conversational model.',
    contextLength: 8192,
    isVision: false,
    isReasoning: false,
    isFree: true,
  ),
];

class SelectedAiModelNotifier extends Notifier<OpenRouterModel> {
  @override
  OpenRouterModel build() {
    return kCuratedOpenRouterModels.first;
  }

  void updateModel(OpenRouterModel model) {
    state = model;
    try {
      ref.read(secureKeyVaultProvider).setPreferredOpenRouterModel(model.id);
    } catch (e) {
      debugPrint('[SelectedAiModelNotifier] Failed to persist preferred model: $e');
    }
  }
}

final selectedAiModelProvider = NotifierProvider<SelectedAiModelNotifier, OpenRouterModel>(SelectedAiModelNotifier.new);

/// Fetches full live catalog of 400+ models from OpenRouter and merges with curated defaults.
final openRouterModelsProvider = FutureProvider<List<OpenRouterModel>>((ref) async {
  try {
    final uri = Uri.parse('https://openrouter.ai/api/v1/models');
    final response = await http.get(uri).timeout(const Duration(seconds: 12));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic> dataModels = data['data'] ?? [];

      final Map<String, OpenRouterModel> modelMap = {};

      // Seed with curated models first
      for (final m in kCuratedOpenRouterModels) {
        modelMap[m.id] = m;
      }

      // Add all live models from OpenRouter
      for (final m in dataModels) {
        try {
          final parsed = OpenRouterModel.fromJson(m as Map<String, dynamic>);
          // Preserve curated rich descriptions if available
          if (modelMap.containsKey(parsed.id)) {
            final curated = modelMap[parsed.id]!;
            modelMap[parsed.id] = OpenRouterModel(
              id: parsed.id,
              name: curated.name,
              provider: parsed.provider,
              description: curated.description.isNotEmpty ? curated.description : parsed.description,
              contextLength: parsed.contextLength,
              isVision: parsed.isVision || curated.isVision,
              isReasoning: parsed.isReasoning || curated.isReasoning,
              isFree: parsed.isFree || curated.isFree,
              pricingPrompt: parsed.pricingPrompt,
              pricingCompletion: parsed.pricingCompletion,
            );
          } else {
            modelMap[parsed.id] = parsed;
          }
        } catch (e) {
          // Skip malformed model entries gracefully
        }
      }

      final list = modelMap.values.toList();
      // Sort: Recommended auto first, then Vision models, then others
      list.sort((a, b) {
        if (a.id == 'auto') return -1;
        if (b.id == 'auto') return 1;
        if (a.isVision && !b.isVision) return -1;
        if (!a.isVision && b.isVision) return 1;
        return a.name.compareTo(b.name);
      });

      return list;
    }
  } catch (e) {
    debugPrint('[openRouterModelsProvider] Remote catalog fetch fallback: $e');
  }

  // Graceful offline fallback to curated models
  return kCuratedOpenRouterModels;
});

/// Grouped models provider by Provider Name
final openRouterGroupedModelsProvider = Provider<AsyncValue<Map<String, List<OpenRouterModel>>>>((ref) {
  final modelsAsync = ref.watch(openRouterModelsProvider);

  return modelsAsync.whenData((models) {
    final Map<String, List<OpenRouterModel>> grouped = {
      'Recommended': [models.firstWhere((m) => m.id == 'auto', orElse: () => kCuratedOpenRouterModels.first)],
    };

    for (final m in models) {
      if (m.id == 'auto') continue;
      final provider = m.provider;
      if (!grouped.containsKey(provider)) {
        grouped[provider] = [];
      }
      grouped[provider]!.add(m);
    }

    return grouped;
  });
});

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}
