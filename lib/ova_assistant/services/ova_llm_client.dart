import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../backend/ai_brain_service.dart';
import '../../backend/security/secure_api_key_vault.dart';
import '../../backend/security/oneova_ai_gateway.dart';
import 'ova_tool_registry.dart';

/// One tool call requested by the model.
class OvaToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> args;
  const OvaToolCall(this.id, this.name, this.args);
}

sealed class OvaLlmEvent {}

class OvaTextDelta extends OvaLlmEvent {
  final String text;
  OvaTextDelta(this.text);
}

class OvaToolCallsEvent extends OvaLlmEvent {
  final List<OvaToolCall> calls;
  OvaToolCallsEvent(this.calls);
}

class OvaLlmError extends OvaLlmEvent {
  final String message;
  OvaLlmError(this.message);
}

/// Streams chat completions with tool calling.
/// Uses OpenRouter when a key is set, otherwise Gemini directly.
/// History is kept in OpenAI chat format and converted for Gemini.
class OvaLlmClient {
  final AIBrainService brain;
  final SecureKeyVault vault;
  OvaLlmClient(this.brain, this.vault);

  static const _openRouterModel = 'google/gemini-2.5-flash';

  Future<bool> hasKey() async {
    if (OneovaAiGateway.canCall(brain.openRouterKey)) return true;
    if ((await vault.getOpenRouterApiKey()).isNotEmpty) return true;
    return (await vault.getGeminiApiKey()).isNotEmpty;
  }

  Stream<OvaLlmEvent> stream({
    required String system,
    required List<Map<String, dynamic>> history,
    required List<OvaToolSpec> tools,
    String? imageBase64,
  }) async* {
    var orKey = brain.openRouterKey;
    if (orKey.isEmpty) orKey = await vault.getOpenRouterApiKey();
    if (OneovaAiGateway.canCall(orKey)) {
      yield* _openRouter(orKey, system, history, tools, imageBase64);
      return;
    }
    final gKey = await vault.getGeminiApiKey();
    if (gKey.isNotEmpty) {
      yield* _gemini(gKey, system, history, tools, imageBase64);
      return;
    }
    yield OvaLlmError('no_key');
  }

  // ── OpenRouter (OpenAI-compatible SSE) ─────────────────────────────────

  Stream<OvaLlmEvent> _openRouter(
    String key,
    String system,
    List<Map<String, dynamic>> history,
    List<OvaToolSpec> tools,
    String? imageBase64,
  ) async* {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': system},
      ...history,
    ];
    if (imageBase64 != null) {
      final lastUser = messages.lastIndexWhere((m) => m['role'] == 'user');
      if (lastUser >= 0) {
        messages[lastUser] = {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': messages[lastUser]['content']},
            {'type': 'image_url', 'image_url': {'url': 'data:image/png;base64,$imageBase64'}},
          ],
        };
      }
    }
    final bearer = await OneovaAiGateway.bearer(key);
    final req = http.Request('POST', OneovaAiGateway.chatUri(key))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $bearer',
        'HTTP-Referer': 'https://oneova.studio',
        'X-Title': 'Oneova',
      })
      ..body = jsonEncode({
        'model': _openRouterModel,
        'stream': true,
        'messages': messages,
        'tools': tools.map((t) => t.toOpenAi()).toList(),
      });

    final client = http.Client();
    try {
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString();
        yield OvaLlmError('AI service error ${res.statusCode}: ${_short(body)}');
        return;
      }
      final calls = <int, _PartialCall>{};
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data == '[DONE]') break;
        Map<String, dynamic> json;
        try {
          json = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        final choices = json['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final delta = (choices.first as Map)['delta'] as Map? ?? const {};
        final content = delta['content'];
        if (content is String && content.isNotEmpty) yield OvaTextDelta(content);
        final tc = delta['tool_calls'];
        if (tc is List) {
          for (final c in tc) {
            final m = c as Map;
            final idx = (m['index'] as num?)?.toInt() ?? 0;
            final p = calls.putIfAbsent(idx, _PartialCall.new);
            if (m['id'] is String) p.id = m['id'] as String;
            final fn = m['function'] as Map?;
            if (fn?['name'] is String) p.name += fn!['name'] as String;
            if (fn?['arguments'] is String) p.args.write(fn!['arguments'] as String);
          }
        }
      }
      if (calls.isNotEmpty) {
        yield OvaToolCallsEvent(calls.values.map((p) => p.build()).toList());
      }
    } on TimeoutException {
      yield OvaLlmError('The AI service took too long to answer.');
    } catch (e) {
      debugPrint('[OvaLlmClient] OpenRouter error: $e');
      yield OvaLlmError('Could not reach the AI service. Check your connection.');
    } finally {
      client.close();
    }
  }

  // ── Gemini (streamGenerateContent SSE) ─────────────────────────────────

  Stream<OvaLlmEvent> _gemini(
    String key,
    String system,
    List<Map<String, dynamic>> history,
    List<OvaToolSpec> tools,
    String? imageBase64,
  ) async* {
    final model = await vault.getPreferredGeminiModel();
    final contents = <Map<String, dynamic>>[];
    for (final m in history) {
      switch (m['role']) {
        case 'user':
          contents.add({
            'role': 'user',
            'parts': [
              {'text': m['content']},
            ],
          });
          break;
        case 'assistant':
          final parts = <Map<String, dynamic>>[];
          final text = m['content'];
          if (text is String && text.isNotEmpty) parts.add({'text': text});
          for (final c in (m['tool_calls'] as List? ?? const [])) {
            final fn = (c as Map)['function'] as Map;
            parts.add({
              'functionCall': {'name': fn['name'], 'args': _decodeArgs(fn['arguments'] as String? ?? '{}')},
            });
          }
          if (parts.isNotEmpty) contents.add({'role': 'model', 'parts': parts});
          break;
        case 'tool':
          contents.add({
            'role': 'user',
            'parts': [
              {
                'functionResponse': {
                  'name': m['name'],
                  'response': {'result': m['content']},
                },
              },
            ],
          });
          break;
      }
    }
    if (imageBase64 != null) {
      final lastUser = contents.lastIndexWhere((c) => c['role'] == 'user');
      if (lastUser >= 0) {
        (contents[lastUser]['parts'] as List).add({
          'inlineData': {'mimeType': 'image/png', 'data': imageBase64},
        });
      }
    }

    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:streamGenerateContent?alt=sse&key=$key');
    final req = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
        'contents': contents,
        'tools': [
          {'functionDeclarations': tools.map((t) => t.toGemini()).toList()},
        ],
      });

    final client = http.Client();
    try {
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString();
        yield OvaLlmError('AI service error ${res.statusCode}: ${_short(body)}');
        return;
      }
      final calls = <OvaToolCall>[];
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        Map<String, dynamic> json;
        try {
          json = jsonDecode(line.substring(5).trim()) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        final cands = json['candidates'] as List?;
        if (cands == null || cands.isEmpty) continue;
        final parts = ((cands.first as Map)['content'] as Map?)?['parts'] as List? ?? const [];
        for (final p in parts) {
          final part = p as Map;
          if (part['text'] is String) yield OvaTextDelta(part['text'] as String);
          final fc = part['functionCall'];
          if (fc is Map) {
            calls.add(OvaToolCall(
              'g${DateTime.now().microsecondsSinceEpoch}_${calls.length}',
              fc['name'] as String,
              Map<String, dynamic>.from((fc['args'] as Map?) ?? const {}),
            ));
          }
        }
      }
      if (calls.isNotEmpty) yield OvaToolCallsEvent(calls);
    } on TimeoutException {
      yield OvaLlmError('The AI service took too long to answer.');
    } catch (e) {
      debugPrint('[OvaLlmClient] Gemini error: $e');
      yield OvaLlmError('Could not reach the AI service. Check your connection.');
    } finally {
      client.close();
    }
  }

  static Map<String, dynamic> _decodeArgs(String raw) {
    try {
      final v = jsonDecode(raw.isEmpty ? '{}' : raw);
      return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static String _short(String body) => body.length > 160 ? '${body.substring(0, 160)}…' : body;
}

class _PartialCall {
  String id = '';
  String name = '';
  final StringBuffer args = StringBuffer();

  OvaToolCall build() => OvaToolCall(
        id.isEmpty ? 'call_${DateTime.now().microsecondsSinceEpoch}' : id,
        name,
        OvaLlmClient._decodeArgs(args.toString()),
      );
}
