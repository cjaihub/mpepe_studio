import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../backend/ai_brain_service.dart';
import '../../backend/security/oneova_ai_gateway.dart';
import '../../backend/security/secure_api_key_vault.dart';
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

/// Emitted when cloud providers are unreachable or cooling down and Local Ova
/// stepped in so the user still gets an immediate answer plus recovery actions.
class OvaLlmDegraded extends OvaLlmEvent {
  final OvaAiDiagnostic diagnostic;
  OvaLlmDegraded(this.diagnostic);
}

class OvaLlmError extends OvaLlmEvent {
  final String message;
  OvaLlmError(this.message);
}

class _StreamAttemptOutcome {
  final bool emitted;
  final bool offline;
  final int? statusCode;
  final OvaAiDiagnostic? diagnostic;

  const _StreamAttemptOutcome({
    required this.emitted,
    this.offline = false,
    this.statusCode,
    this.diagnostic,
  });
}

/// Streams chat completions with tool calling and multi-provider failover:
/// 1. User's saved OpenRouter key (OpenAI SSE + free-model fallback)
/// 2. Signed-in Oneova Cloud Proxy (`aiProxy` → OpenRouter, App Check + 401 refresh + 5xx cooldown)
/// 3. Instant Local Ova Smart Synthesis via [AIBrainService] + [OvaLlmDegraded]
/// No model keys live in the app; the Gemini API is never called directly.
class OvaLlmClient {
  final AIBrainService brain;
  final SecureKeyVault vault;
  final http.Client? _httpClient;

  OvaLlmClient(this.brain, this.vault, [this._httpClient]);

  static const _openRouterModel = 'google/gemini-2.5-flash';

  /// Ova is always ready to answer—via user key, keyless Firebase AI, signed-in
  /// proxy, or instant Local Ova synthesis.
  Future<bool> hasKey() async => true;

  Stream<OvaLlmEvent> stream({
    required String system,
    required List<Map<String, dynamic>> history,
    required List<OvaToolSpec> tools,
    String? imageBase64,
  }) async* {
    final cleanHistory = AIBrainService.sanitizeChatMessages(history);
    OvaAiDiagnostic? lastDiagnostic;

    // ── Stage 1: User-supplied OpenRouter API Key ───────────────────────
    var orKey = brain.openRouterKey;
    if (orKey.isEmpty) orKey = await vault.getOpenRouterApiKey();
    if (orKey.isNotEmpty) {
      for (final model in const [
        _openRouterModel,
        'meta-llama/llama-3.3-70b-instruct:free',
      ]) {
        var outcome = const _StreamAttemptOutcome(emitted: false);
        yield* _live(
          (sink) => _collectOpenRouter(
            key: orKey,
            model: model,
            system: system,
            history: cleanHistory,
            tools: tools,
            imageBase64: imageBase64,
            sink: sink,
          ),
          (o) => outcome = o,
        );
        if (outcome.emitted) return;
        if (outcome.diagnostic != null) lastDiagnostic = outcome.diagnostic;
        if (outcome.offline || outcome.statusCode == 401) break;
      }
      if (lastDiagnostic?.kind == OvaAiIssueKind.offline) {
        yield* _emitLocalFallback(cleanHistory, system, imageBase64, lastDiagnostic);
        return;
      }
    }

    // ── Stage 4: Signed-in Oneova Cloud Proxy (`aiProxy`) ───────────────
    if (OneovaAiGateway.canCall('')) {
      final buffer = <OvaLlmEvent>[];
      var outcome = const _StreamAttemptOutcome(emitted: false);
      yield* _live(
        (sink) => _collectOpenRouter(
          key: '',
          model: _openRouterModel,
          system: system,
          history: cleanHistory,
          tools: tools,
          imageBase64: imageBase64,
          sink: sink,
        ),
        (o) => outcome = o,
      );
      if (outcome.emitted) {
        OneovaAiGateway.recordProxySuccess();
        return;
      }

      // Refresh expired Firebase ID token once on 401
      if (!outcome.emitted && outcome.statusCode == 401) {
        final refreshed = await OneovaAiGateway.bearer('', forceRefresh: true);
        if (refreshed.isNotEmpty) {
          buffer.clear();
          outcome = await _collectOpenRouter(
            key: '',
            model: _openRouterModel,
            system: system,
            history: cleanHistory,
            tools: tools,
            imageBase64: imageBase64,
            overrideBearer: refreshed,
            sink: buffer.add,
          );
        }
      }

      if (outcome.emitted) {
        OneovaAiGateway.recordProxySuccess();
        for (final ev in buffer) {
          yield ev;
        }
        return;
      }

      if (outcome.statusCode != null) {
        OneovaAiGateway.recordProxyFailure(outcome.statusCode!);
      }
      if (outcome.diagnostic != null) {
        lastDiagnostic ??= outcome.diagnostic;
      }
    } else if (OneovaAiGateway.signedIn && OneovaAiGateway.isProxyCoolingDown) {
      lastDiagnostic ??= OvaAiDiagnostic(
        kind: OvaAiIssueKind.cloudUnavailable,
        badgeLabel: 'Cloud AI Busy · Local Ova',
        detail:
            'Oneova Cloud AI is temporarily unavailable (${OneovaAiGateway.lastProxyErrorStatus ?? 503}). Local Ova answered above—tap Retry or add a personal AI key in AI Settings.',
        httpStatus: OneovaAiGateway.lastProxyErrorStatus,
      );
    }

    // ── Stage 5: Instant Local Ova Synthesis + Diagnostic ───────────────
    yield* _emitLocalFallback(cleanHistory, system, imageBase64, lastDiagnostic);
  }

  Stream<OvaLlmEvent> _emitLocalFallback(
    List<Map<String, dynamic>> cleanHistory,
    String system,
    String? imageBase64,
    OvaAiDiagnostic? preferredDiagnostic,
  ) async* {
    final res = await brain.processRequest(
      cleanHistory,
      screenBase64: imageBase64,
      userContextPrompt: system,
    );
    if (res is AiTextResponse) {
      if (res.text.trim().isNotEmpty) {
        yield OvaTextDelta(res.text);
      }
      final diag = preferredDiagnostic ?? res.diagnostic;
      if (diag != null) {
        yield OvaLlmDegraded(diag);
      }
      return;
    }
    if (res is AiToolCallResponse) {
      final mapped = <OvaToolCall>[];
      for (final c in res.toolCalls) {
        if (c is Map) {
          final fn = c['function'] as Map? ?? const {};
          final name = (fn['name'] ?? '').toString();
          if (name.isNotEmpty) {
            mapped.add(
              OvaToolCall(
                (c['id'] ?? 'call_${DateTime.now().microsecondsSinceEpoch}').toString(),
                name,
                _decodeArgs((fn['arguments'] ?? '{}').toString()),
              ),
            );
          }
        }
      }
      if (mapped.isNotEmpty) {
        yield OvaToolCallsEvent(mapped);
        return;
      }
    }
  }

  // ── OpenRouter / Proxy (OpenAI-compatible SSE) ─────────────────────────

  Future<_StreamAttemptOutcome> _collectOpenRouter({
    required String key,
    required String model,
    required String system,
    required List<Map<String, dynamic>> history,
    required List<OvaToolSpec> tools,
    required String? imageBase64,
    required void Function(OvaLlmEvent) sink,
    String? overrideBearer,
  }) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': system},
      ...history,
    ];
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      final lastUser = messages.lastIndexWhere((m) => m['role'] == 'user');
      if (lastUser >= 0) {
        messages[lastUser] = {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': (messages[lastUser]['content'] ?? '').toString()},
            {'type': 'image_url', 'image_url': {'url': 'data:image/png;base64,$imageBase64'}},
          ],
        };
      }
    }

    final bearer = overrideBearer ?? await OneovaAiGateway.bearer(key);
    if (bearer.isEmpty) {
      return const _StreamAttemptOutcome(emitted: false);
    }

    final req = http.Request('POST', OneovaAiGateway.chatUri(key))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $bearer',
        'HTTP-Referer': 'https://oneova.studio',
        'X-Title': 'Oneova',
        ...await OneovaAiGateway.appCheckHeader(key),
      })
      ..body = jsonEncode({
        'model': model,
        'stream': true,
        'messages': messages,
        'tools': tools.map((t) => t.toOpenAi()).toList(),
      });

    final client = _httpClient ?? http.Client();
    final ownsClient = _httpClient == null;
    try {
      final res = await client.send(req).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString();
        return _StreamAttemptOutcome(
          emitted: false,
          statusCode: res.statusCode,
          diagnostic: OneovaAiGateway.classifyHttpFailure(
            res.statusCode,
            body,
            usingUserKey: key.isNotEmpty,
          ),
        );
      }

      var emittedAny = false;
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
        final firstChoice = choices.first as Map;
        final delta = (firstChoice['delta'] as Map?) ?? (firstChoice['message'] as Map?) ?? const {};
        final content = delta['content'];
        if (content is String && content.isNotEmpty) {
          emittedAny = true;
          sink(OvaTextDelta(content));
        }
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
        emittedAny = true;
        sink(OvaToolCallsEvent(calls.values.map((p) => p.build()).toList()));
      }
      return _StreamAttemptOutcome(emitted: emittedAny);
    } on SocketException {
      return const _StreamAttemptOutcome(
        emitted: false,
        offline: true,
        diagnostic: OvaAiDiagnostic(
          kind: OvaAiIssueKind.offline,
          badgeLabel: 'Offline Mode · Local Ova',
          detail: 'No internet connection detected. Local Ova answered above—tap Retry when back online.',
        ),
      );
    } on TimeoutException {
      return const _StreamAttemptOutcome(
        emitted: false,
        statusCode: 504,
        diagnostic: OvaAiDiagnostic(
          kind: OvaAiIssueKind.cloudUnavailable,
          badgeLabel: 'Cloud AI Timeout · Local Ova',
          detail: 'Cloud AI timed out. Local Ova answered above—tap Retry or add an AI key in AI Settings.',
          httpStatus: 504,
        ),
      );
    } catch (e) {
      debugPrint('[OvaLlmClient] OpenRouter error: $e');
      return const _StreamAttemptOutcome(
        emitted: false,
        diagnostic: OvaAiDiagnostic(
          kind: OvaAiIssueKind.cloudUnavailable,
          badgeLabel: 'Cloud AI Busy · Local Ova',
          detail: 'Could not reach Cloud AI right now. Local Ova answered above—tap Retry or check AI Settings.',
        ),
      );
    } finally {
      if (ownsClient) client.close();
    }
  }

  Stream<OvaLlmEvent> _live(
    Future<_StreamAttemptOutcome> Function(void Function(OvaLlmEvent) sink) run,
    void Function(_StreamAttemptOutcome) done,
  ) async* {
    final c = StreamController<OvaLlmEvent>();
    final held = <OvaLlmEvent>[];
    var outcome = const _StreamAttemptOutcome(emitted: false);
    unawaited(run((ev) {
      if (ev is OvaLlmError || ev is OvaLlmDegraded) {
        held.add(ev);
      } else if (!c.isClosed) {
        c.add(ev);
      }
    }).then((o) => outcome = o, onError: (_) {}).whenComplete(c.close));
    yield* c.stream;
    if (outcome.emitted) {
      for (final ev in held) {
        yield ev;
      }
    }
    done(outcome);
  }

  static Map<String, dynamic> _decodeArgs(String raw) {
    try {
      final v = jsonDecode(raw.isEmpty ? '{}' : raw);
      return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
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
