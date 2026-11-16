import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../security/secure_api_key_vault.dart';
import '../security/oneova_ai_gateway.dart';

final openRouterAgentServiceProvider = Provider<OpenRouterAgentService>((ref) {
  final vault = ref.watch(secureKeyVaultProvider);
  return OpenRouterAgentService(vault: vault);
});

class OpenRouterAgentService {
  final SecureKeyVault? _vault;

  OpenRouterAgentService({this._vault});

  /// Resolves the OpenRouter API key from SecureKeyVault, dotenv, or compile-time env.
  Future<String> _resolveApiKey() async {
    if (_vault != null) {
      final key = await _vault.getOpenRouterApiKey();
      if (key.trim().isNotEmpty) return key.trim();
    }
    return '';
  }

  /// Resolves preferred model from vault or defaults to fast instructor.
  Future<String> _resolveModel({String? requestedModel}) async {
    if (requestedModel != null && requestedModel.isNotEmpty) {
      return requestedModel;
    }
    if (_vault != null) {
      final model = await _vault.getPreferredOpenRouterModel();
      if (model.isNotEmpty) return model;
    }
    return 'meta-llama/llama-3-8b-instruct:free';
  }

  /// Generates a cinematic 'look' (color grading, filter parameters) based on a user prompt.
  Future<Map<String, dynamic>> generateLookParameters(String prompt) async {
    final key = await _resolveApiKey();
    if (!OneovaAiGateway.canCall(key)) {
      // Return fallback parameters for development if no key is provided
      return {
        'temperature': 0.8,
        'tint': 0.1,
        'exposure': 0.2,
        'contrast': 1.1,
        'saturation': 1.2,
      };
    }

    try {
      final model = await _resolveModel();
      final response = await http.post(
        OneovaAiGateway.chatUri(key),
        headers: {
          'Authorization': 'Bearer ${await OneovaAiGateway.bearer(key)}',
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://oneova.app',
          'X-Title': 'Oneova',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {
              'role': 'system',
              'content': 'You are an expert video colorist. Based on the user prompt, output ONLY a JSON object with properties: temperature (0.0 to 2.0), tint (-1.0 to 1.0), exposure (-2.0 to 2.0), contrast (0.0 to 2.0), saturation (0.0 to 2.0).'
            },
            {
              'role': 'user',
              'content': prompt
            }
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final contentString = data['choices'][0]['message']['content'] as String;
        // Parse the JSON output from the LLM
        final Map<String, dynamic> parameters = jsonDecode(contentString);
        return parameters;
      }
    } catch (e) {
      debugPrint('[OpenRouterAgentService] Look parameter error: $e');
    }
    
    return {};
  }

  /// Generic method to query the agent with a custom system and user prompt.
  /// Supports optional [imageBase64] for multimodal vision analysis (e.g. video frame).
  Future<String?> queryAgent(
    String systemPrompt,
    String userPrompt, {
    String? model,
    String? imageBase64,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final key = await _resolveApiKey();
    if (!OneovaAiGateway.canCall(key)) {
      return null;
    }

    try {
      final selectedModel = imageBase64 != null && imageBase64.isNotEmpty
          ? (model ?? 'google/gemini-2.5-flash')
          : await _resolveModel(requestedModel: model);
      final appCheck = await OneovaAiGateway.appCheckHeader(key);
      final dynamic userContent = (imageBase64 != null && imageBase64.isNotEmpty)
          ? [
              {'type': 'text', 'text': userPrompt},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,$imageBase64'},
              },
            ]
          : userPrompt;

      final response = await http.post(
        OneovaAiGateway.chatUri(key),
        headers: {
          'Authorization': 'Bearer ${await OneovaAiGateway.bearer(key)}',
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://oneova.app',
          'X-Title': 'Oneova',
          ...appCheck,
        },
        body: jsonEncode({
          'model': selectedModel,
          'messages': [
            {
              'role': 'system',
              'content': systemPrompt,
            },
            {
              'role': 'user',
              'content': userContent,
            }
          ],
        }),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        OneovaAiGateway.recordProxySuccess();
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'] as String;
      } else {
        OneovaAiGateway.recordProxyFailure(response.statusCode);
        debugPrint('[OpenRouterAgentService] HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[OpenRouterAgentService] queryAgent error: $e');
    }
    return null;
  }
}

