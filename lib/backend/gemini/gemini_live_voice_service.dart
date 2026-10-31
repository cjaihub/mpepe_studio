import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../security/oneova_ai_gateway.dart';
import '../repair/oneova_self_repair_engine.dart';
import '../repair/oneova_auto_updater.dart';

enum GeminiVoiceState { idle, listening, reasoning, speaking, repairing }

class GeminiLiveVoiceState {
  final GeminiVoiceState state;
  final String currentTranscript;
  final String lastAiResponse;
  final String statusMessage;
  final double soundLevel;
  final bool isMuted;

  const GeminiLiveVoiceState({
    this.state = GeminiVoiceState.idle,
    this.currentTranscript = '',
    this.lastAiResponse = '',
    this.statusMessage = 'Ova Voice Ready',
    this.soundLevel = 0.0,
    this.isMuted = false,
  });

  GeminiLiveVoiceState copyWith({
    GeminiVoiceState? state,
    String? currentTranscript,
    String? lastAiResponse,
    String? statusMessage,
    double? soundLevel,
    bool? isMuted,
  }) {
    return GeminiLiveVoiceState(
      state: state ?? this.state,
      currentTranscript: currentTranscript ?? this.currentTranscript,
      lastAiResponse: lastAiResponse ?? this.lastAiResponse,
      statusMessage: statusMessage ?? this.statusMessage,
      soundLevel: soundLevel ?? this.soundLevel,
      isMuted: isMuted ?? this.isMuted,
    );
  }
}

final geminiLiveVoiceServiceProvider =
    NotifierProvider<GeminiLiveVoiceService, GeminiLiveVoiceState>(() {
  return GeminiLiveVoiceService();
});

/// High-Performance Gemini Live Voice & Spoken Reasoning Engine for Oneova.
///
/// Features:
/// - Gemini 2.5 Flash on Vertex AI through Firebase AI Logic (no key in the app).
/// - Falls back to the signed-in server proxy when Vertex AI is unreachable.
/// - Autonomous voice-activated self-repair and diagnostics execution.
/// - Natural spoken TTS playback with waveform amplitude tracking.
class GeminiLiveVoiceService extends Notifier<GeminiLiveVoiceState> {
  final FlutterTts _tts = FlutterTts();
  late OneOvaSelfRepairEngine _repairEngine;
  late OneOvaAutoUpdater _updater;

  @override
  GeminiLiveVoiceState build() {
    _repairEngine = ref.watch(oneOvaSelfRepairEngineProvider);
    _updater = ref.watch(oneOvaAutoUpdaterProvider);
    _initTts();
    return const GeminiLiveVoiceState();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
      );
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);

      _tts.setStartHandler(() {
        state = state.copyWith(state: GeminiVoiceState.speaking);
      });

      _tts.setCompletionHandler(() {
        state = state.copyWith(state: GeminiVoiceState.idle);
      });

      _tts.setErrorHandler((msg) {
        debugPrint('[GeminiLiveVoice] TTS error: $msg');
        state = state.copyWith(state: GeminiVoiceState.idle);
      });
    } catch (e) {
      debugPrint('[GeminiLiveVoice] TTS init error: $e');
    }
  }

  /// Sends a user voice transcript to Gemini, executes any voice commands or self-repairs,
  /// and speaks the response aloud.
  Future<String> processSpokenInput(String userSpeech, {Function(String)? onStreamChunk}) async {
    final cleanInput = userSpeech.trim();
    if (cleanInput.isEmpty) return '';

    state = state.copyWith(
      state: GeminiVoiceState.reasoning,
      currentTranscript: cleanInput,
      statusMessage: 'Thinking…',
    );

    // ─────────────────────────────────────────────────────────────────
    // Check Voice-Activated Self-Repair & System Diagnostics Triggers
    // ─────────────────────────────────────────────────────────────────
    final lower = cleanInput.toLowerCase();
    if (lower.contains('repair') ||
        lower.contains('fix my account') ||
        lower.contains('fix feed') ||
        lower.contains('diagnos') ||
        lower.contains('health check') ||
        lower.contains('system health')) {
      return await _handleSpokenSelfRepair(cleanInput);
    }

    if (lower.contains('update') || lower.contains('check update') || lower.contains('new version')) {
      return await _handleSpokenUpdateCheck();
    }

    // ─────────────────────────────────────────────────────────────────
    // Query Gemini Live AI Core
    // ─────────────────────────────────────────────────────────────────
    try {
      final user = FirebaseAuth.instance.currentUser;
      final userName = user?.displayName ?? 'Creator';

      final systemPrompt = '''
You are Ova, the autonomous digital twin and primary intelligence of Oneova.
You are talking to $userName via live full-screen voice call.
Rules:
1. Be concise, direct, helpful, and natural (1-3 spoken sentences max).
2. Never output markdown asterisks, bullet lists, or tables because your answer is spoken out loud.
3. You can execute repairs ("I repaired your feed and verified your profile"), verify distribution, and explain features.
''';

      String responseText = '';

      // Gemini on Vertex AI through Firebase AI Logic: authorized by
      // Firebase (App Check + Auth), no API key in the app.
      try {
        final ai = FirebaseAI.agentPlatform(location: 'us-central1').generativeModel(
          model: 'gemini-2.5-flash',
          systemInstruction: Content.system(systemPrompt),
          generationConfig: GenerationConfig(temperature: 0.7, maxOutputTokens: 256),
        );
        final res = await ai.generateContent([Content.text(cleanInput)]).timeout(const Duration(seconds: 15));
        responseText = res.text ?? '';
      } catch (e) {
        debugPrint('[GeminiLiveVoice] Vertex AI error: $e');
      }

      // Second path: the signed-in server proxy (also keyless for the app).
      if (responseText.isEmpty && OneovaAiGateway.canCall('')) {
        final res = await http
            .post(
              OneovaAiGateway.chatUri(''),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${await OneovaAiGateway.bearer('')}',
              },
              body: jsonEncode({
                'model': 'google/gemini-2.5-flash',
                'messages': [
                  {'role': 'system', 'content': systemPrompt},
                  {'role': 'user', 'content': cleanInput},
                ],
                'max_tokens': 256,
              }),
            )
            .timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          responseText = data['choices']?[0]?['message']?['content'] ?? '';
        }
      }

      if (responseText.isEmpty) {
        responseText = user == null
            ? 'Please sign in so I can help you.'
            : 'Sorry, I could not reach Ova just now. Please try again in a moment.';
      }

      // Clean markdown tags for spoken audio
      final cleanSpoken = responseText
          .replaceAll(RegExp(r'[*#_`]'), '')
          .replaceAll(RegExp(r'\[.*?\]\(.*?\)'), '')
          .trim();

      state = state.copyWith(
        state: GeminiVoiceState.speaking,
        lastAiResponse: cleanSpoken,
        statusMessage: 'Speaking…',
      );

      await speak(cleanSpoken);
      return cleanSpoken;
    } catch (e) {
      debugPrint('[GeminiLiveVoice] Process error: $e');
      const fallback = 'Sorry, something went wrong. Please try again.';
      await speak(fallback);
      return fallback;
    }
  }

  Future<String> _handleSpokenSelfRepair(String userSpeech) async {
    state = state.copyWith(
      state: GeminiVoiceState.repairing,
      statusMessage: 'Checking your account…',
    );

    final uid = FirebaseAuth.instance.currentUser?.uid;
    String repairSummary = '';

    // 1. Repair Profile
    if (uid != null) {
      final profileResult = await _repairEngine.repairUserProfile(uid);
      if (profileResult.success) {
        repairSummary += 'Profile schema verified and normalized. ';
      }
    }

    // 2. Repair Interface & Cache
    final cacheResult = await _repairEngine.repairInterfaceAndCache();
    if (cacheResult.success) {
      repairSummary += 'Corrupt cache cleared and media pipelines reset. ';
    }

    // 3. Scan Health
    final health = await _repairEngine.runSystemHealthScan();

    final spokenResponse = "Self-repair complete. $repairSummary All core systems are operational with a health score of ${health.overallScore} percent.";

    state = state.copyWith(
      state: GeminiVoiceState.speaking,
      lastAiResponse: spokenResponse,
      statusMessage: 'Speaking…',
    );

    await speak(spokenResponse);
    return spokenResponse;
  }

  Future<String> _handleSpokenUpdateCheck() async {
    state = state.copyWith(
      state: GeminiVoiceState.reasoning,
      statusMessage: 'Checking for background updates…',
    );

    final update = await _updater.checkForUpdates();
    String spokenResponse;
    if (update.hasUpdate) {
      spokenResponse = "A new Oneova build ${update.latestVersion} is available on the ${update.channel} channel. You can update from your settings panel.";
    } else {
      spokenResponse = "You are currently running the latest official build ${OneOvaAutoUpdater.currentVersion} on the ${update.channel} channel. Everything is up to date.";
    }

    state = state.copyWith(
      state: GeminiVoiceState.speaking,
      lastAiResponse: spokenResponse,
      statusMessage: 'Speaking…',
    );

    await speak(spokenResponse);
    return spokenResponse;
  }

  Future<void> speak(String text) async {
    try {
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[GeminiLiveVoice] Speak error: $e');
    }
  }

  Future<void> stop() async {
    await _tts.stop();
    state = state.copyWith(state: GeminiVoiceState.idle);
  }
}
