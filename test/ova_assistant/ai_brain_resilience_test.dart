import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oneova/backend/ai_brain_service.dart';
import 'package:oneova/backend/project_repository.dart';
import 'package:oneova/backend/remote_connect_service.dart';
import 'package:oneova/backend/security/oneova_ai_gateway.dart';
import 'package:oneova/backend/security/secure_api_key_vault.dart';
import 'package:oneova/backend/tiktok_automation_service.dart';
import 'package:oneova/hub/hub_ai_screen.dart';
import 'package:oneova/ova_assistant/services/ova_agentic_orchestrator.dart';
import 'package:oneova/ova_assistant/services/ova_llm_client.dart';
import 'package:oneova/providers/settings_provider.dart';
import 'package:oneova/settings/screens/ai_settings_screen.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestSettingsNotifier extends SettingsNotifier {
  @override
  Future<Map<String, dynamic>> build() async => {
        'ai': {
          'defaultModel': 'gemini-2.5-flash',
          'assistantTone': 'Professional',
          'autoAggressiveness': 0.5,
        },
      };
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const {});
  GoogleFonts.config.allowRuntimeFetching = false;
  if (!dotenv.isInitialized) {
    await dotenv.load(mergeWith: {'ONEOVA_SYSTEM_UPDATE_CHANNEL': 'stable'});
  }

  setUp(() {
    OneovaAiGateway.resetCooldown();
    FlutterSecureStorage.setMockInitialValues({});
  });

  AIBrainService buildBrain({
    required SecureKeyVault vault,
    required http.Client client,
  }) {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final remote = container.read(remoteConnectProvider.notifier);
    return AIBrainService(
      remote,
      TikTokAutomationService(),
      ProjectRepository(),
      vault,
      client,
    );
  }

  group('OneovaAiGateway & Model Normalization', () {
    test('strips raw HTML from 503 proxy pages and trips circuit-breaker cooldown', () {
      const html503 =
          '<html><head><title>503 Server Error</title></head><body><h1>Error: Server Error</h1></body></html>';
      final diag = OneovaAiGateway.classifyHttpFailure(503, html503);

      expect(diag.kind, OvaAiIssueKind.cloudUnavailable);
      expect(diag.badgeLabel, 'Cloud AI Busy');
      expect(diag.detail, isNot(contains('<html>')));
      expect(diag.detail, contains('503'));

      expect(OneovaAiGateway.isProxyCoolingDown, isFalse);
      OneovaAiGateway.recordProxyFailure(503);
      expect(OneovaAiGateway.isProxyCoolingDown, isTrue);
      expect(OneovaAiGateway.lastProxyErrorStatus, 503);

      OneovaAiGateway.resetCooldown();
      expect(OneovaAiGateway.isProxyCoolingDown, isFalse);
    });

    test('upgrades retired Gemini & invalid OpenRouter model IDs automatically', () {
      expect(SecureKeyVault.normalizeGeminiModel('gemini-2.5-flash'), 'gemini-2.5-flash');
      expect(SecureKeyVault.normalizeGeminiModel('gemini-2.0-flash'), 'gemini-2.0-flash');
      expect(SecureKeyVault.normalizeGeminiModel('gemini-1.5-pro'), 'gemini-1.5-pro');
      expect(SecureKeyVault.normalizeGeminiModel(''), 'gemini-2.5-flash');

      expect(
        AIBrainService.normalizeOpenRouterModel('anthropic/claude-sonnet-5'),
        'google/gemini-2.5-flash',
      );
      expect(
        AIBrainService.normalizeOpenRouterModel('gemini-1.5-pro'),
        'google/gemini-2.5-flash',
      );
    });
  });

  group('AIBrainService Schema Sanitization & Multi-Provider Failover', () {
    test('sanitizeChatMessages converts non-JSON AgenticProcedurePlan & strips UI keys cleanly', () {
      final plan = AgenticProcedurePlan(
        id: 'plan_1',
        type: AgenticProcedureType.reelExportAndBoost,
        title: 'Reel Export & Boost',
        steps: [
          AgenticStep(
            id: 's1',
            title: 'Analyze Hook',
            description: 'Checking first 2 seconds.',
          ),
        ],
        summary: 'Reel optimized for vertical retention.',
      );

      final rawMessages = <Map<String, dynamic>>[
        {'role': 'user', 'content': 'Boost my reel'},
        {
          'role': 'assistant',
          'type': 'agentic_plan',
          'plan': plan, // Non-JSON custom Dart object that previously crashed jsonEncode!
        },
        {
          'role': 'assistant',
          'type': 'widget',
          'widgetType': 'chart',
          'data': {'title': 'Retention Curve'},
        },
        {
          'role': 'assistant',
          'content': 'Ready for next step.',
          'type': 'text',
          'origin': 'Overlay',
          'diagnostic': const OvaAiDiagnostic(
            kind: OvaAiIssueKind.offline,
            badgeLabel: 'Offline',
            detail: 'Offline',
          ),
          'retryPrompt': 'Boost my reel',
        },
      ];

      final cleaned = AIBrainService.sanitizeChatMessages(rawMessages);
      expect(() => jsonEncode(cleaned), returnsNormally);
      expect(cleaned.length, 4);
      expect(cleaned[1]['role'], 'assistant');
      expect(cleaned[1]['content'], isA<String>());
      expect(cleaned[1].containsKey('plan'), isFalse);
      expect(cleaned[3].containsKey('diagnostic'), isFalse);
      expect(cleaned[3].containsKey('origin'), isFalse);
    });

    test('succeeds via user Gemini API key (gemini-2.5-flash) even if first model returns 404', () async {
      FlutterSecureStorage.setMockInitialValues({
        'oneova_secure_gemini_key': 'AIzaSyTestUserKey123456',
      });
      final vault = SecureKeyVault();
      final requestedUrls = <String>[];

      final client = MockClient((req) async {
        requestedUrls.add(req.url.toString());
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'Live Gemini 2.5 Flash studio answer!'}
                  ]
                }
              }
            ]
          }),
          200,
        );
      });

      final brain = buildBrain(vault: vault, client: client);
      final res = await brain.processRequest([
        {'role': 'user', 'content': 'Give me a 1-line hook'}
      ]);

      expect(res, isA<AiTextResponse>());
      final textRes = res as AiTextResponse;
      expect(textRes.isDegraded, isFalse);
      expect(textRes.text, 'Live Gemini 2.5 Flash studio answer!');
      expect(requestedUrls.first, contains('models/gemini-2.5-flash:generateContent'));
    });

    test('fails over across OpenRouter fallback models on 503 and succeeds without error', () async {
      FlutterSecureStorage.setMockInitialValues({
        'oneova_secure_openrouter_key': 'sk-or-v1-test-user-key-9999',
      });
      final vault = SecureKeyVault();
      final modelsTried = <String>[];

      final client = MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final model = body['model'] as String;
        modelsTried.add(model);
        if (modelsTried.length == 1) {
          return http.Response('<html><body>503 Service Unavailable</body></html>', 503);
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Recovered via fallback OpenRouter model!'}
              }
            ]
          }),
          200,
        );
      });

      final brain = buildBrain(vault: vault, client: client);
      final res = await brain.processRequest([
        {'role': 'user', 'content': 'Write a studio bio'}
      ]);

      expect(res, isA<AiTextResponse>());
      final textRes = res as AiTextResponse;
      expect(textRes.isDegraded, isFalse);
      expect(textRes.text, 'Recovered via fallback OpenRouter model!');
      expect(modelsTried.length, 2);
    });

    test('never returns "Unable to reach AI Brain" when offline—returns helpful Local Ova + diagnostic', () async {
      FlutterSecureStorage.setMockInitialValues({
        'oneova_secure_openrouter_key': 'sk-or-v1-offline-test',
      });
      final vault = SecureKeyVault();
      final client = MockClient((_) async {
        throw const SocketException('Network unreachable');
      });

      final brain = buildBrain(vault: vault, client: client);
      final res = await brain.processRequest([
        {'role': 'user', 'content': 'Help me plan a viral reel script'}
      ]);

      expect(res, isA<AiTextResponse>());
      final textRes = res as AiTextResponse;
      expect(textRes.text, isNot(contains('Unable to reach AI Brain')));
      expect(textRes.text, contains('Oneova Reel Blueprint'));
      expect(textRes.isDegraded, isTrue);
      expect(textRes.diagnostic?.kind, OvaAiIssueKind.offline);
    });
  });

  group('OvaLlmClient Overlay Streaming Resilience', () {
    test('falls back cleanly to Local Ova + OvaLlmDegraded when upstream returns HTML 503', () async {
      FlutterSecureStorage.setMockInitialValues({
        'oneova_secure_openrouter_key': 'sk-or-v1-test-503',
      });
      final vault = SecureKeyVault();
      final client = MockClient((_) async {
        return http.Response('<html><head><title>503</title></head><body>Down</body></html>', 503);
      });

      final brain = buildBrain(vault: vault, client: client);
      final llm = OvaLlmClient(brain, vault, client);

      final events = await llm
          .stream(
            system: 'You are Ova.',
            history: [
              {'role': 'user', 'content': 'Help me plan my week'}
            ],
            tools: const [],
          )
          .toList();

      final deltas = events.whereType<OvaTextDelta>().map((e) => e.text).join();
      final degraded = events.whereType<OvaLlmDegraded>().toList();
      final rawErrors = events.whereType<OvaLlmError>().toList();

      expect(rawErrors, isEmpty);
      expect(deltas, isNot(contains('<html>')));
      expect(deltas, isNot(contains('Unable to reach AI Brain')));
      expect(deltas, contains('Weekly Creator Plan'));
      expect(degraded, hasLength(1));
    });
  });

  group('Dual-Mode UI Verification (HubAiScreen & AiSettingsScreen)', () {
    for (final mode in [('Light', AppTheme.lightTheme), ('Dark', AppTheme.darkTheme)]) {
      testWidgets('HubAiScreen renders Local Ova answer + Retry / AI Settings / Health Check in ${mode.$1} mode',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(430, 932));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final mockClient = MockClient((req) async => http.Response('{}', 503));
        final container = ProviderContainer(
          overrides: [
            aiBrainProvider.overrideWith((ref) => buildBrain(
                  vault: SecureKeyVault(),
                  client: mockClient,
                )),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: mode.$2,
              home: const HubAiScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 250));

        // Tap Weekly Planner card which triggers _sendMessage
        await tester.tap(find.text('Weekly Planner'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        expect(find.textContaining('Unable to reach AI Brain'), findsNothing);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('AI Settings'), findsOneWidget);
        expect(find.text('Health Check'), findsOneWidget);
      });

      testWidgets('AiSettingsScreen exposes Gemini key, OpenRouter key & Connection Test in ${mode.$1} mode',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(430, 932));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsProvider.overrideWith(_TestSettingsNotifier.new),
            ],
            child: MaterialApp(
              theme: mode.$2,
              home: const AiSettingsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Ova Brain & Credentials'), findsOneWidget);
        expect(find.text('Google Gemini API Key'), findsOneWidget);
        expect(find.text('OpenRouter API Key'), findsOneWidget);
        expect(find.text('Test AI Brain Connection'), findsOneWidget);
      });
    }
  });
}
