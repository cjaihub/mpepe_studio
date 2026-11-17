import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../shared/audio/cloud_dictation.dart';
import '../../shared/audio/mic_coordinator.dart';
import '../../shared/audio/ova_vertex_audio_engine.dart';
import '../../shared/audio/speech_hub.dart';

import '../../backend/repair/oneova_auto_updater.dart';
import '../../backend/repair/oneova_self_repair_engine.dart';
import '../../backend/security/oneova_ai_gateway.dart';
import '../core/ova_tool_result.dart';
import '../widgets/ova_fluid_voice_orb.dart';
import 'ova_account_context.dart';
import 'ova_chat_controller.dart';
import 'ova_geo_tools.dart';
import 'ova_llm_client.dart';
import 'ova_local_intents.dart';
import 'ova_memory_tools.dart';
import 'ova_native_service.dart';
import 'ova_notification_memory_service.dart';
import 'ova_shared_history_service.dart';
import 'ova_task_center.dart';
import 'ova_tool_registry.dart';
import '../../backend/ai_agents/omni_command/omni_assistant_service.dart';

/// Natural Vertex Live voices available across Ova Voice, Overlay Voice, and Calls.
const List<({String id, String label, String tone})> kOvaVertexVoices = [
  (id: 'Aoede', label: 'Aoede', tone: 'Warm & Kind'),
  (id: 'Puck', label: 'Puck', tone: 'Bright & Friendly'),
  (id: 'Kore', label: 'Kore', tone: 'Calm & Clear'),
  (id: 'Charon', label: 'Charon', tone: 'Deep & Steady'),
  (id: 'Fenrir', label: 'Fenrir', tone: 'Rich & Expressive'),
  (id: 'Zephyr', label: 'Zephyr', tone: 'Soft & Gentle'),
];

enum OvaVoicePhase {
  idle,
  listening,
  thinking,
  speaking,
  paused,
}

class OvaVoiceSessionState {
  final OvaVoicePhase phase;
  final String userTranscript;
  final String assistantReply;
  final double amplitude;
  final bool isMicMuted;
  final bool captionsEnabled;
  final bool audioEnabled;
  final bool voiceEnhanced;
  final bool wakeCallEnabled;
  final bool isVertexLiveConnected;
  final String voiceName;
  final String? friendlyActivity;
  final double speechRate;
  final String? errorMessage;
  final String? pendingRoute;

  const OvaVoiceSessionState({
    this.phase = OvaVoicePhase.idle,
    this.userTranscript = '',
    this.assistantReply = '',
    this.amplitude = 0.0,
    this.isMicMuted = false,
    this.captionsEnabled = true,
    this.audioEnabled = true,
    this.voiceEnhanced = true,
    this.wakeCallEnabled = true,
    this.isVertexLiveConnected = false,
    this.voiceName = 'Aoede',
    this.friendlyActivity,
    this.speechRate = 0.50,
    this.errorMessage,
    this.pendingRoute,
  });

  bool get isActive => phase != OvaVoicePhase.idle;
  bool get isPaused => phase == OvaVoicePhase.paused;

  OvaOrbMode get orbMode => switch (phase) {
        OvaVoicePhase.idle => OvaOrbMode.idle,
        OvaVoicePhase.listening =>
          isMicMuted ? OvaOrbMode.idle : OvaOrbMode.listening,
        OvaVoicePhase.thinking => OvaOrbMode.thinking,
        OvaVoicePhase.speaking => OvaOrbMode.speaking,
        OvaVoicePhase.paused => OvaOrbMode.paused,
      };

  /// Warm, human-friendly status label with zero technical jargon.
  String get statusLabel {
    if (friendlyActivity != null && friendlyActivity!.trim().isNotEmpty) {
      return friendlyActivity!;
    }
    return switch (phase) {
      OvaVoicePhase.idle =>
        wakeCallEnabled ? 'Say "Hey Ova" or tap mic' : 'Tap the mic to talk',
      OvaVoicePhase.listening =>
        isMicMuted ? 'Microphone is muted' : 'Listening to you…',
      OvaVoicePhase.thinking => 'Looking into that for you…',
      OvaVoicePhase.speaking => 'Speaking with you…',
      OvaVoicePhase.paused =>
        wakeCallEnabled ? 'Resting · Say "Hey Ova" anytime' : 'Paused · Tap to continue',
    };
  }

  OvaVoiceSessionState copyWith({
    OvaVoicePhase? phase,
    String? userTranscript,
    String? assistantReply,
    double? amplitude,
    bool? isMicMuted,
    bool? captionsEnabled,
    bool? audioEnabled,
    bool? voiceEnhanced,
    bool? wakeCallEnabled,
    bool? isVertexLiveConnected,
    String? voiceName,
    String? friendlyActivity,
    bool clearActivity = false,
    double? speechRate,
    String? errorMessage,
    bool clearError = false,
    String? pendingRoute,
    bool clearRoute = false,
  }) {
    return OvaVoiceSessionState(
      phase: phase ?? this.phase,
      userTranscript: userTranscript ?? this.userTranscript,
      assistantReply: assistantReply ?? this.assistantReply,
      amplitude: amplitude ?? this.amplitude,
      isMicMuted: isMicMuted ?? this.isMicMuted,
      captionsEnabled: captionsEnabled ?? this.captionsEnabled,
      audioEnabled: audioEnabled ?? this.audioEnabled,
      voiceEnhanced: voiceEnhanced ?? this.voiceEnhanced,
      wakeCallEnabled: wakeCallEnabled ?? this.wakeCallEnabled,
      isVertexLiveConnected:
          isVertexLiveConnected ?? this.isVertexLiveConnected,
      voiceName: voiceName ?? this.voiceName,
      friendlyActivity:
          clearActivity ? null : (friendlyActivity ?? this.friendlyActivity),
      speechRate: speechRate ?? this.speechRate,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pendingRoute: clearRoute ? null : (pendingRoute ?? this.pendingRoute),
    );
  }
}

final ovaMainVoiceSessionProvider =
    NotifierProvider<OvaMainVoiceSessionNotifier, OvaVoiceSessionState>(
  OvaMainVoiceSessionNotifier.new,
);

final ovaOverlayVoiceSessionProvider =
    NotifierProvider<OvaOverlayVoiceSessionNotifier, OvaVoiceSessionState>(
  OvaOverlayVoiceSessionNotifier.new,
);

class OvaMainVoiceSessionNotifier extends OvaVoiceSessionBaseNotifier {
  @override
  bool get isOverlaySurface => false;
}

class OvaOverlayVoiceSessionNotifier extends OvaVoiceSessionBaseNotifier {
  @override
  bool get isOverlaySurface => true;
}

/// Real-Time Vertex Live Voice Engine (`FirebaseAI.agentPlatform`) shared across
/// Ova Main Voice and Ova Overlay Voice, backed by the same conversation history
/// and Firestore database as `OvaChatController` (`ovaChatProvider`) and
/// `OvaSharedHistoryNotifier` (`ovaSharedHistoryProvider`).
abstract class OvaVoiceSessionBaseNotifier extends Notifier<OvaVoiceSessionState> {
  bool get isOverlaySurface;

  static const String _vertexLocation = 'us-central1';
  static const List<String> _liveModels = [
    'gemini-live-2.5-flash-preview-native-audio-09-2025',
    'gemini-2.0-flash-exp',
    'gemini-2.0-flash',
  ];

  // Vertex Live bidirectional audio session + hardware PCM stream
  LiveSession? _liveSession;
  final AudioRecorder _pcmRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _pcmMicSub;
  bool _pcmPlayerReady = false;
  String _partialUserTranscript = '';
  String _partialAssistantTranscript = '';
  OvaToolResult? _lastTurnToolResult;

  // Fallback dictation + wake-word standby when Vertex Live stream is resting
  final SpeechHub _speech = SpeechHub.instance;
  CloudDictation? _cloud;
  MicLease? _lease;
  bool _heldByOtherApp = false;
  bool _usingCloud = false;
  bool _committingCloud = false;
  bool _wakeStandbyListening = false;
  AppLifecycleListener? _lifecycle;
  final List<Map<String, dynamic>> _voiceHistory = [];

  bool _speechReady = false;
  bool _disposed = false;
  String? _activeThreadId;
  String? _pendingQuestion;
  Timer? _silenceTimer;
  String? _currentTaskId;
  OvaWorkspaceId _workspace = OvaWorkspaceId.personal;
  OvaInvocationContext _invocation = const OvaInvocationContext();
  BuildContext? _permissionContext;

  @override
  OvaVoiceSessionState build() {
    _disposed = false;
    if (!isOverlaySurface) {
      _lifecycle = AppLifecycleListener(onPause: () {
        if (!_disposed && state.isActive && !state.isPaused && !state.wakeCallEnabled) {
          state = state.copyWith(phase: OvaVoicePhase.paused, amplitude: 0.0);
          unawaited(_stopHardware());
        }
      });
    }
    // Background task completion announcement in friendly human words
    ref.listen<OvaTaskState>(ovaTaskCenterProvider, (prev, next) {
      final f = next.justFinished;
      if (f == null || prev?.justFinished?.id == f.id || f.id == _currentTaskId) return;
      if (_disposed || !state.isActive || state.isPaused) return;
      final friendly = f.status == OvaTaskStatus.done
          ? 'All done with ${f.title}.'
          : 'I couldn\'t quite finish ${f.title}, let me know if you\'d like me to try again.';
      unawaited(_announce(friendly));
    });
    ref.onDispose(() {
      _disposed = true;
      _lifecycle?.dispose();
      unawaited(_cloud?.dispose());
      unawaited(_pcmRecorder.dispose());
      _stopHardware();
    });
    return const OvaVoiceSessionState();
  }

  void configureContext({
    OvaWorkspaceId? workspace,
    OvaInvocationContext? invocation,
    BuildContext? permissionContext,
  }) {
    if (workspace != null) _workspace = workspace;
    if (invocation != null) _invocation = invocation;
    if (permissionContext != null) _permissionContext = permissionContext;
  }

  void consumePendingRoute() {
    if (state.pendingRoute != null) {
      state = state.copyWith(clearRoute: true);
    }
  }

  Future<void> setVoiceName(String name) async {
    if (!kOvaVertexVoices.any((v) => v.id == name) || state.voiceName == name) return;
    HapticFeedback.selectionClick();
    state = state.copyWith(voiceName: name);
    if (state.isActive && !state.isPaused) {
      await _reconnectVertexLive();
    }
  }

  Future<void> toggleWakeCall() async {
    HapticFeedback.selectionClick();
    final next = !state.wakeCallEnabled;
    state = state.copyWith(wakeCallEnabled: next);
    if (next) {
      await OvaNativeService().startBackgroundAssistant();
      if (state.phase == OvaVoicePhase.paused || state.phase == OvaVoicePhase.idle) {
        unawaited(_startWakeWordStandby());
      }
    } else {
      await OvaNativeService().stopBackgroundAssistant();
      if (_wakeStandbyListening) {
        _wakeStandbyListening = false;
        await _speech.cancel(this);
      }
    }
  }

  Future<void> _ensurePcmPlayer() async {
    if (_pcmPlayerReady) return;
    try {
      await FlutterPcmSound.setup(sampleRate: 24000, channelCount: 1);
      _pcmPlayerReady = true;
    } catch (e) {
      debugPrint('[OvaVoiceSession] PCM player setup notice: $e');
    }
  }

  Future<void> _speakViaVertexNativeAudio(String line) async {
    try {
      await OvaVertexAudioEngine.instance.speak(
        line,
        voiceName: state.voiceName,
        languageCode: WidgetsBinding.instance.platformDispatcher.locale.languageCode,
        onComplete: () {
          if (_disposed) return;
          if (state.phase == OvaVoicePhase.speaking && _liveSession == null) {
            if (!state.isMicMuted && !state.isPaused) {
              unawaited(_beginFallbackListening());
            } else {
              state = state.copyWith(phase: OvaVoicePhase.listening, amplitude: 0.0);
            }
          }
        },
      );
    } catch (_) {
      if (!_disposed && state.phase == OvaVoicePhase.speaking) {
        if (!state.isMicMuted && !state.isPaused) {
          unawaited(_beginFallbackListening());
        } else {
          state = state.copyWith(phase: OvaVoicePhase.listening, amplitude: 0.0);
        }
      }
    }
  }

  /// Starts or resumes a real-time Vertex Live voice session, sharing the exact
  /// same conversation history and database thread as Chat (`ovaChatProvider`).
  Future<void> startSession({
    OvaWorkspaceId workspace = OvaWorkspaceId.personal,
    OvaInvocationContext invocation = const OvaInvocationContext(),
    BuildContext? permissionContext,
  }) async {
    _workspace = workspace;
    _invocation = invocation;
    _permissionContext = permissionContext;
    _wakeStandbyListening = false;
    OneovaAiGateway.resetCooldown();

    // Sync with the unified Chat controller & shared Firestore history so
    // Voice and Chat always work on the same conversation.
    _syncHistoryFromSharedChat();

    unawaited(OvaAccountContext.instance.warm());
    unawaited(OvaMemoryTools.instance.warm());
    unawaited(OvaNotificationMemoryService.instance.warm());

    final chatCtrl = ref.read(ovaChatProvider);
    _activeThreadId = chatCtrl.activeThreadId ??
        _activeThreadId ??
        ref
            .read(ovaSharedHistoryProvider.notifier)
            .newThreadId('ova_unified');
    chatCtrl.activeThreadId = _activeThreadId;

    HapticFeedback.lightImpact();
    if (state.wakeCallEnabled) {
      unawaited(OvaNativeService().startBackgroundAssistant());
    }

    state = state.copyWith(
      phase: OvaVoicePhase.listening,
      isMicMuted: false,
      clearError: true,
      clearActivity: true,
    );

    final micOk = await _requestMicAndLease();
    if (!micOk || _disposed) return;

    // 1. Connect to real Vertex Live bidirectional audio model first!
    final liveConnected = await _connectVertexLive();
    if (liveConnected) {
      state = state.copyWith(
        phase: OvaVoicePhase.listening,
        isVertexLiveConnected: true,
        clearError: true,
      );
      _armSilence();
      return;
    }

    // 2. If Vertex Live WebSocket couldn't open (e.g. strict firewall/offline),
    // seamlessly fall back to hardware CloudDictation + OvaLlmClient.
    state = state.copyWith(isVertexLiveConnected: false);
    await _beginFallbackListening();
  }

  void _syncHistoryFromSharedChat() {
    try {
      final chatCtrl = ref.read(ovaChatProvider);
      if (chatCtrl.recentHistory.isNotEmpty) {
        _voiceHistory
          ..clear()
          ..addAll(chatCtrl.recentHistory.take(16));
        _activeThreadId = chatCtrl.activeThreadId;
        return;
      }
      if (_voiceHistory.isEmpty) {
        final turns = ref.read(ovaSharedHistoryProvider).turns;
        if (turns.isNotEmpty) {
          final latestThreadId = turns.first.threadId;
          final threadTurns = turns
              .where((t) => t.threadId == latestThreadId)
              .take(8)
              .toList()
              .reversed;
          for (final t in threadTurns) {
            if (t.query.isNotEmpty) {
              _voiceHistory.add({'role': 'user', 'content': t.query});
            }
            if (t.response.isNotEmpty) {
              _voiceHistory.add({'role': 'assistant', 'content': t.response});
            }
          }
          _activeThreadId = latestThreadId;
          chatCtrl.activeThreadId = latestThreadId;
        }
      }
    } catch (e) {
      debugPrint('[OvaVoiceSession] history sync notice: $e');
    }
  }

  Future<bool> _requestMicAndLease() async {
    try {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        if (!_disposed) {
          state = state.copyWith(
            phase: OvaVoicePhase.listening,
            isMicMuted: true,
            errorMessage: micStatus.isPermanentlyDenied
                ? 'Microphone access is turned off. Please enable it in Settings so we can talk.'
                : 'Please allow microphone access to talk with Ova.',
          );
        }
        return false;
      }
    } catch (_) {}

    return _ensureMicLease();
  }

  String _preferredLiveModel() {
    try {
      final m = FirebaseRemoteConfig.instance.getString('ova_live_voice_model').trim();
      if (m.isNotEmpty) return m;
    } catch (_) {}
    return _liveModels.first;
  }

  String _buildVertexLiveSystemInstruction() {
    final recentLines = _voiceHistory
        .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
        .take(8)
        .map((m) => '${m['role'] == 'user' ? 'User' : 'Ova'}: ${m['content']}')
        .join('\n');
    final recentSummary =
        recentLines.isEmpty ? '' : '\nRecent conversation context (same thread as chat):\n$recentLines';

    String styleBlock = '';
    try {
      styleBlock = '\n${ref.read(omniAssistantServiceProvider.notifier).generateSystemPromptAdditions()}';
    } catch (_) {}

    return '''
You are Ova, the warm, kind, and intelligent real-time voice companion inside Oneova (${_workspace.label} workspace).
You share the exact same memory, tools, and conversation thread as the user's text chat.

How to communicate:
- Speak naturally, warmly, and kindly like a thoughtful human friend and personal concierge.
- Never use technical jargon, tool names, JSON, coordinates, API terms, or robotic phrases.
- Keep spoken answers concise (1 to 3 natural sentences) unless the user asks for a detailed explanation.
- Reply in the exact language the user speaks to you.
- Whenever the user asks to find places near them ("what's near me"), fly to a place on the map, get directions, check notifications, set reminders, message someone, or control their phone/computer, call the matching tool right away and tell them warmly what you found or did.

${_liveContext(_currentTaskId ?? '')}$styleBlock$recentSummary
''';
  }

  Future<bool> _connectVertexLive() async {
    await _closeVertexLiveSession();
    await _ensurePcmPlayer();

    final registry = ref.read(ovaToolRegistryProvider);
    final toolDecls = registry.specs.map((s) => s.toFunctionDeclaration()).toList();
    final candidates = {_preferredLiveModel(), ..._liveModels}.toList();

    for (final candidate in candidates) {
      if (_disposed) return false;
      try {
        final liveModel = FirebaseAI.agentPlatform(location: _vertexLocation)
            .liveGenerativeModel(
          model: candidate,
          systemInstruction: Content.system(_buildVertexLiveSystemInstruction()),
          tools: [Tool.functionDeclarations(toolDecls)],
          liveGenerationConfig: LiveGenerationConfig(
            speechConfig: SpeechConfig(voiceName: state.voiceName),
            responseModalities: [ResponseModalities.audio],
            inputAudioTranscription: AudioTranscriptionConfig(),
            outputAudioTranscription: AudioTranscriptionConfig(),
            contextWindowCompression: ContextWindowCompressionConfig(
              slidingWindow: SlidingWindow(),
            ),
          ),
        );

        final session = await liveModel.connect().timeout(const Duration(seconds: 10));
        if (_disposed) {
          unawaited(session.close().catchError((_) {}));
          return false;
        }
        _liveSession = session;
        _partialUserTranscript = '';
        _partialAssistantTranscript = '';
        unawaited(_receiveVertexLive(session));

        final micStarted = await _startVertexPcmMic();
        if (!micStarted) {
          await _closeVertexLiveSession();
          return false;
        }
        debugPrint('[OvaVoiceSession] Connected to Vertex Live model: $candidate (voice: ${state.voiceName})');
        return true;
      } catch (e) {
        debugPrint('[OvaVoiceSession] Vertex Live model $candidate failed: $e');
        await _closeVertexLiveSession();
      }
    }
    return false;
  }

  Future<void> _reconnectVertexLive() async {
    if (_disposed || !state.isActive || state.isPaused) return;
    await _connectVertexLive();
  }

  Future<bool> _startVertexPcmMic() async {
    try {
      await _pcmMicSub?.cancel();
      _pcmMicSub = null;
      if (!await _pcmRecorder.hasPermission()) return false;

      final stream = await _pcmRecorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          noiseSuppress: state.voiceEnhanced,
          echoCancel: state.voiceEnhanced,
          autoGain: state.voiceEnhanced,
          androidConfig: const AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceCommunication,
          ),
        ),
      );

      _pcmMicSub = stream.listen((pcmBytes) {
        if (_disposed || state.isMicMuted || state.isPaused) return;
        final s = _liveSession;
        if (s == null) return;

        // Compute real-time RMS voice level for the fluid orb
        final level = _computePcmLevel(pcmBytes);
        if (state.phase == OvaVoicePhase.listening) {
          state = state.copyWith(amplitude: level);
          if (level > 0.22) _armSilence();
        }
        unawaited(
          s.sendAudioRealtime(InlineDataPart('audio/pcm', pcmBytes)).catchError((_) {}),
        );
      });
      return true;
    } catch (e) {
      debugPrint('[OvaVoiceSession] PCM mic start failed: $e');
      return false;
    }
  }

  double _computePcmLevel(Uint8List pcm16) {
    if (pcm16.length < 4) return 0.05;
    final bd = ByteData.sublistView(pcm16);
    final samples = pcm16.length ~/ 2;
    final step = math.max(1, samples ~/ 64);
    double sumSquares = 0;
    int count = 0;
    for (int i = 0; i < samples; i += step) {
      final s = bd.getInt16(i * 2, Endian.little) / 32768.0;
      sumSquares += s * s;
      count++;
    }
    if (count == 0) return 0.05;
    final rms = math.sqrt(sumSquares / count);
    return (rms * 3.8).clamp(0.04, 1.0);
  }

  Future<void> _receiveVertexLive(LiveSession session) async {
    try {
      await for (final response in session.receive()) {
        if (_disposed || !identical(session, _liveSession)) return;
        await _handleVertexLiveMessage(response.message);
      }
    } catch (e) {
      debugPrint('[OvaVoiceSession] Vertex Live stream ended: $e');
    }
    if (!_disposed && identical(session, _liveSession)) {
      _liveSession = null;
      if (state.isActive && !state.isPaused && !state.isMicMuted) {
        // Auto-recover session or fall back smoothly
        final reconnected = await _connectVertexLive();
        if (!reconnected && !_disposed && state.isActive && !state.isPaused) {
          state = state.copyWith(isVertexLiveConnected: false);
          await _beginFallbackListening();
        }
      }
    }
  }

  Future<void> _handleVertexLiveMessage(LiveServerMessage message) async {
    // 1. Live Tool Call execution (Maps, What's Near Me, Fly To, Notifications, etc.)
    if (message is LiveServerToolCall) {
      final calls = message.functionCalls ?? const <FunctionCall>[];
      if (calls.isEmpty) return;

      final registry = ref.read(ovaToolRegistryProvider);
      final tasks = ref.read(ovaTaskCenterProvider.notifier);
      final responses = <FunctionResponse>[];

      for (final call in calls) {
        final friendly = friendlyOvaStepLabel(call.name, call.args);
        state = state.copyWith(
          phase: OvaVoicePhase.thinking,
          friendlyActivity: '$friendly…',
          amplitude: 0.32,
        );

        final taskId = tasks.start(friendly, source: isOverlaySurface ? 'ova' : 'ai_lab');
        _currentTaskId = taskId;
        final stepIdx = tasks.addStep(taskId, friendly, Icons.auto_awesome_rounded);

        Map<String, Object?> toolResultMap;
        try {
          final spec = registry.spec(call.name);
          if (spec == null) {
            toolResultMap = {'ok': false, 'summary': 'That action is not available right now.'};
            tasks.updateStep(taskId, stepIdx, OvaStepStatus.failed);
            tasks.finish(taskId, ok: false);
          } else {
            final res = await registry.run(
              call.name,
              call.args,
              _permissionContext,
              _invocation,
            );
            _lastTurnToolResult = res;
            if (res.navigateTo != null) {
              state = state.copyWith(pendingRoute: res.navigateTo);
            }
            tasks.updateStep(
              taskId,
              stepIdx,
              res.ok ? OvaStepStatus.done : OvaStepStatus.failed,
            );
            tasks.finish(taskId, ok: res.ok, summary: res.summary);
            toolResultMap = {
              'ok': res.ok,
              'title': res.title,
              'summary': res.summary,
              if (res.navigateTo != null) 'navigateTo': res.navigateTo,
            };
          }
        } catch (e) {
          tasks.updateStep(taskId, stepIdx, OvaStepStatus.failed);
          tasks.finish(taskId, ok: false);
          toolResultMap = {'ok': false, 'summary': 'Could not complete that step right now.'};
        }

        responses.add(FunctionResponse(call.name, toolResultMap, id: call.id));
      }

      try {
        await _liveSession?.sendToolResponse(responses);
      } catch (e) {
        debugPrint('[OvaVoiceSession] sendToolResponse error: $e');
      }
      state = state.copyWith(clearActivity: true);
      return;
    }

    if (message is! LiveServerContent) return;

    // 2. Live User Speech Transcription
    final heard = message.inputTranscription?.text;
    if (heard != null && heard.isNotEmpty) {
      _partialUserTranscript += heard;
      state = state.copyWith(
        userTranscript: _partialUserTranscript.trim(),
        clearError: true,
      );
      _armSilence();
    }

    // 3. Live Native Audio Stream from Vertex Live
    for (final part in message.modelTurn?.parts ?? const <Part>[]) {
      if (part is InlineDataPart && part.mimeType.startsWith('audio')) {
        if (state.phase != OvaVoicePhase.speaking) {
          state = state.copyWith(
            phase: OvaVoicePhase.speaking,
            clearActivity: true,
          );
        }
        if (state.audioEnabled && _pcmPlayerReady) {
          final b = part.bytes;
          final speakAmp = _computePcmLevel(b);
          state = state.copyWith(amplitude: speakAmp.clamp(0.18, 0.95));
          FlutterPcmSound.feed(
            PcmArrayInt16(
              bytes: b.buffer.asByteData(b.offsetInBytes, b.lengthInBytes),
            ),
          );
        }
      } else if (part is TextPart && part.text.trim().isNotEmpty) {
        _partialAssistantTranscript += part.text;
        state = state.copyWith(
          assistantReply: _partialAssistantTranscript.trim(),
        );
      }
    }

    // 4. Live Output Audio Transcription
    final said = message.outputTranscription?.text;
    if (said != null && said.isNotEmpty) {
      _partialAssistantTranscript += said;
      state = state.copyWith(
        assistantReply: _partialAssistantTranscript.trim(),
      );
    }

    // 5. Turn Complete -> Persist to unified Chat + Shared Firestore History!
    if (message.turnComplete == true || message.interrupted == true) {
      final finalUser = _partialUserTranscript.trim();
      final finalAi = _partialAssistantTranscript.trim();
      final toolRes = _lastTurnToolResult;
      _partialUserTranscript = '';
      _partialAssistantTranscript = '';
      _lastTurnToolResult = null;

      if (finalUser.isNotEmpty || finalAi.isNotEmpty || toolRes != null) {
        await _persistUnifiedTurn(
          userText: finalUser,
          assistantText: finalAi.isNotEmpty
              ? finalAi
              : (toolRes?.summary ?? ''),
          toolResult: toolRes,
        );
      }

      if (finalAi.endsWith('?')) {
        _pendingQuestion = finalAi;
      } else if (finalUser.isNotEmpty) {
        _pendingQuestion = null;
      }

      if (!_disposed && !state.isPaused) {
        state = state.copyWith(
          phase: OvaVoicePhase.listening,
          amplitude: 0.06,
          clearActivity: true,
        );
        _armSilence();
      }
    }
  }

  /// Saves a completed voice turn to BOTH `ovaChatProvider` (so switching to
  /// Chat shows the exact same messages & map/tool cards) AND `ovaSharedHistoryProvider`
  /// (Firestore `users/{uid}/ai_interactions`).
  Future<void> _persistUnifiedTurn({
    required String userText,
    required String assistantText,
    OvaToolResult? toolResult,
    bool persistToFirestore = true,
  }) async {
    final u = userText.trim();
    final a = assistantText.trim();
    if (u.isEmpty && a.isEmpty && toolResult == null) return;

    if (u.isNotEmpty) {
      _voiceHistory.add({'role': 'user', 'content': u});
    }
    if (a.isNotEmpty) {
      _voiceHistory.add({'role': 'assistant', 'content': a});
    }
    if (_voiceHistory.length > 20) {
      _voiceHistory.removeRange(0, _voiceHistory.length - 20);
    }

    // 1. Sync to shared Firestore history
    if (u.isNotEmpty || a.isNotEmpty) {
      _activeThreadId = await ref.read(ovaSharedHistoryProvider.notifier).recordTurn(
            query: u.isNotEmpty ? u : (toolResult?.title ?? 'Voice command'),
            response: a.isNotEmpty ? a : (toolResult?.summary ?? ''),
            source: OvaOriginSource.voice,
            workspace: _workspace,
            threadId: _activeThreadId,
            persistToFirestore: persistToFirestore,
          );
    }

    // 2. Sync to in-memory OvaChatController so Chat and Voice are one conversation!
    try {
      ref.read(ovaChatProvider).recordVoiceTurn(
            userText: u,
            assistantText: a,
            toolResult: toolResForChat(toolResult),
            threadId: _activeThreadId,
          );
    } catch (e) {
      debugPrint('[OvaVoiceSession] Chat sync notice: $e');
    }
  }

  OvaToolResult? toolResForChat(OvaToolResult? r) => r;

  Future<void> _closeVertexLiveSession() async {
    await _pcmMicSub?.cancel();
    _pcmMicSub = null;
    try {
      if (await _pcmRecorder.isRecording()) {
        await _pcmRecorder.stop();
      }
    } catch (_) {}
    final s = _liveSession;
    _liveSession = null;
    if (s != null) {
      try {
        await s.close();
      } catch (_) {}
    }
  }

  void _armSilence() {
    _silenceTimer?.cancel();
    if (_disposed) return;
    _silenceTimer = Timer(
      Duration(seconds: _pendingQuestion != null ? 55 : 110),
      () {
        if (_disposed || state.phase != OvaVoicePhase.listening || state.isPaused) {
          return;
        }
        state = state.copyWith(
          phase: OvaVoicePhase.paused,
          amplitude: 0.0,
          clearActivity: true,
          assistantReply: _pendingQuestion != null
              ? 'Whenever you\'re ready, just say "Hey Ova" or tap the mic.'
              : 'I\'m resting right here. Say "Hey Ova" or tap the mic anytime.',
        );
        unawaited(_enterStandbyOrStop());
      },
    );
  }

  Future<void> _enterStandbyOrStop() async {
    await _closeVertexLiveSession();
    await _cloud?.cancel();
    if (state.wakeCallEnabled && !_disposed) {
      await _startWakeWordStandby();
    } else {
      await _stopHardware();
    }
  }

  /// Low-power wake-word standby ("Hey Ova" / "Ova") so Ova can be summoned
  /// hands-free while resting or working in the background.
  Future<void> _startWakeWordStandby() async {
    if (_disposed || !state.wakeCallEnabled || _wakeStandbyListening) return;
    if (state.phase == OvaVoicePhase.listening && _liveSession != null) return;

    if (!_speechReady) {
      _speechReady = await _speech.ensureReady();
    }
    if (!_speechReady || _disposed) return;

    _wakeStandbyListening = true;
    try {
      await _speech.listen(
        owner: this,
        options: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: stt.ListenMode.dictation,
        ),
        onStatus: (status) {
          if (_disposed || !_wakeStandbyListening) return;
          if ((status == 'done' || status == 'notListening') &&
              state.wakeCallEnabled &&
              (state.isPaused || state.phase == OvaVoicePhase.idle)) {
            Future.delayed(const Duration(milliseconds: 600), () {
              if (!_disposed &&
                  _wakeStandbyListening &&
                  state.wakeCallEnabled &&
                  (state.isPaused || state.phase == OvaVoicePhase.idle)) {
                _wakeStandbyListening = false;
                unawaited(_startWakeWordStandby());
              }
            });
          }
        },
        onError: (_) {},
        onSoundLevel: (_) {},
        onResult: (result) {
          if (_disposed || !_wakeStandbyListening) return;
          final words = result.recognizedWords.trim().toLowerCase();
          if (_containsWakeWord(words)) {
            _wakeStandbyListening = false;
            unawaited(_speech.stop(this));
            HapticFeedback.mediumImpact();
            final remainder = _stripWakeWord(result.recognizedWords.trim());
            unawaited(
              startSession(
                workspace: _workspace,
                invocation: _invocation,
                permissionContext: _permissionContext,
              ).then((_) {
                if (remainder.length > 3) {
                  unawaited(submitSpokenUtterance(remainder));
                }
              }),
            );
          }
        },
      );
    } catch (_) {
      _wakeStandbyListening = false;
    }
  }

  static bool _containsWakeWord(String lower) {
    return RegExp(r'\b(hey ova|hello ova|hi ova|ok ova|okay ova|wake up ova|ova)\b')
        .hasMatch(lower);
  }

  static String _stripWakeWord(String raw) {
    return raw
        .replaceFirst(
          RegExp(
            r'^(hey|hello|hi|ok|okay|wake up)?\s*ova[,.:!\s]*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  // ── Fallback Listening (CloudDictation + OvaLlmClient) when Vertex Live WS is unavailable ──

  Future<void> _beginFallbackListening() async {
    if (_disposed || state.isPaused || state.isMicMuted) return;
    if (!await _ensureMicLease()) return;

    if (!_speechReady) {
      _speechReady = await _speech.ensureReady();
    }
    if (_disposed || state.isPaused || state.phase == OvaVoicePhase.idle) return;
    state = state.copyWith(phase: OvaVoicePhase.listening, clearError: true);
    _armSilence();
    if (_speechReady) {
      await _listenPass();
    } else {
      await _cloudListenPass();
    }
  }

  Future<bool> _ensureMicLease() async {
    if (_lease?.isActive ?? false) return true;
    final got = await MicCoordinator.instance.acquire(
      MicUser.assistant,
      onPreempted: () async {
        _lease = null;
        _usingCloud = false;
        await _closeVertexLiveSession();
        await _speech.cancel(this);
        await _cloud?.cancel();
        try {
          await OvaVertexAudioEngine.instance.stop();
        } catch (_) {}
        if (!_disposed && state.isActive && !state.isPaused) {
          state = state.copyWith(phase: OvaVoicePhase.paused, amplitude: 0.0);
        }
      },
      onInterruption: (i) {
        if (_disposed || !state.isActive) return;
        if (i == MicInterruption.heldByOtherApp) {
          _heldByOtherApp = true;
          _usingCloud = false;
          unawaited(_closeVertexLiveSession());
          unawaited(_speech.cancel(this));
          unawaited(_cloud?.cancel());
          state = state.copyWith(
            amplitude: 0.0,
            errorMessage:
                'Another app is using the microphone right now. I\'ll continue as soon as it\'s free.',
          );
        } else if (_heldByOtherApp) {
          _heldByOtherApp = false;
          state = state.copyWith(clearError: true);
          if (state.phase == OvaVoicePhase.listening && !state.isMicMuted) {
            unawaited(startSession(
              workspace: _workspace,
              invocation: _invocation,
              permissionContext: _permissionContext,
            ));
          }
        }
      },
    );
    if (got is MicBusy) {
      if (!_disposed) {
        state = state.copyWith(
          phase: OvaVoicePhase.listening,
          isMicMuted: true,
          errorMessage: got.message,
        );
      }
      return false;
    }
    _lease = got as MicLease;
    return true;
  }

  Future<void> _releaseLease() async {
    final lease = _lease;
    _lease = null;
    _heldByOtherApp = false;
    await lease?.release();
  }

  static const _endOfPassErrors = {'error_no_match', 'error_speech_timeout'};
  static const _permissionErrors = {
    'error_permission',
    'error_insufficient_permissions',
  };

  Future<void> _cloudListenPass() async {
    if (_disposed || state.isMicMuted || state.isPaused || _heldByOtherApp) return;
    if (!(_lease?.isActive ?? false)) return;
    await _speech.cancel(this);
    _usingCloud = true;
    _cloud ??= CloudDictation();
    final ok = await _cloud!.start(
      autoStopOnSilence: true,
      onLevel: (level) {
        if (_disposed || state.phase != OvaVoicePhase.listening) return;
        state = state.copyWith(amplitude: level.clamp(0.04, 1.0));
      },
      onSilenceCommit: () {
        if (!_disposed) unawaited(_commitCloudUtterance());
      },
    );
    if (!ok) {
      _usingCloud = false;
      if (!_disposed) {
        state = state.copyWith(
          phase: OvaVoicePhase.listening,
          isMicMuted: true,
          errorMessage:
              'I couldn\'t access the microphone right now. Please check your mic settings.',
        );
      }
      await _releaseLease();
    }
  }

  Future<void> _commitCloudUtterance() async {
    if (_committingCloud || !_usingCloud || _disposed) return;
    _committingCloud = true;
    _usingCloud = false;
    try {
      final cloud = _cloud;
      if (cloud == null) return;
      state = state.copyWith(amplitude: 0.18);
      final transcript = await cloud.stopAndTranscribe();
      if (_disposed) return;
      if (transcript.trim().isNotEmpty) {
        await submitSpokenUtterance(transcript.trim());
      } else if (state.phase == OvaVoicePhase.listening &&
          !state.isMicMuted &&
          !state.isPaused &&
          !_heldByOtherApp) {
        await _cloudListenPass();
      }
    } catch (e) {
      if (!_disposed &&
          state.phase == OvaVoicePhase.listening &&
          !state.isMicMuted &&
          !state.isPaused &&
          !_heldByOtherApp) {
        await _cloudListenPass();
      }
    } finally {
      _committingCloud = false;
    }
  }

  Future<void> _listenPass() async {
    if (!_speechReady ||
        _disposed ||
        state.isMicMuted ||
        state.isPaused ||
        _heldByOtherApp) {
      return;
    }
    if (!(_lease?.isActive ?? false)) return;
    _usingCloud = false;
    try {
      final started = await _speech.listen(
        owner: this,
        options: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: stt.ListenMode.dictation,
        ),
        onStatus: (status) {
          if (_disposed || _usingCloud || _liveSession != null) return;
          if ((status == 'done' || status == 'notListening') &&
              state.phase == OvaVoicePhase.listening &&
              !state.isMicMuted &&
              !state.isPaused) {
            Future.delayed(const Duration(milliseconds: 350), () {
              if (!_disposed &&
                  !_usingCloud &&
                  _liveSession == null &&
                  state.phase == OvaVoicePhase.listening &&
                  !state.isMicMuted &&
                  !state.isPaused &&
                  !_speech.isListeningFor(this)) {
                _listenPass();
              }
            });
          }
        },
        onError: (err) {
          if (_disposed || _usingCloud || _liveSession != null) return;
          if (_endOfPassErrors.contains(err.errorMsg)) return;
          if (_permissionErrors.contains(err.errorMsg)) {
            state = state.copyWith(
              isMicMuted: true,
              errorMessage: 'Please allow microphone access to speak with Ova.',
            );
            unawaited(_releaseLease());
            return;
          }
          unawaited(_cloudListenPass());
        },
        onSoundLevel: (level) {
          if (_disposed || state.phase != OvaVoicePhase.listening) return;
          final normalized = ((level + 2.0) / 12.0).clamp(0.04, 1.0);
          state = state.copyWith(amplitude: normalized);
        },
        onResult: (result) {
          if (_disposed || _usingCloud || _liveSession != null) return;
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            state = state.copyWith(userTranscript: words);
            _armSilence();
          }
          if (result.finalResult && words.isNotEmpty) {
            submitSpokenUtterance(words);
          }
        },
      );
      if (!started && !_disposed && state.phase == OvaVoicePhase.listening) {
        await _cloudListenPass();
      }
    } catch (_) {
      if (!_disposed && state.phase == OvaVoicePhase.listening) {
        await _cloudListenPass();
      }
    }
  }

  /// Sends a spoken or tapped utterance into the active Vertex Live session
  /// (or processes it via the shared LLM & tool loop when Vertex Live is in fallback mode).
  Future<void> submitSpokenUtterance(String rawUtterance) async {
    final text = rawUtterance.trim();
    if (text.isEmpty || _disposed) return;

    _silenceTimer?.cancel();
    _pendingQuestion = null;

    // If connected to Vertex Live, send directly into the live session!
    if (_liveSession != null) {
      state = state.copyWith(
        phase: OvaVoicePhase.thinking,
        userTranscript: text,
        friendlyActivity: 'Looking into that for you…',
        amplitude: 0.28,
        clearError: true,
      );
      _partialUserTranscript = text;
      try {
        await _liveSession!.sendTextRealtime(text);
        return;
      } catch (e) {
        debugPrint('[OvaVoiceSession] sendTextRealtime fallback: $e');
      }
    }

    // Fallback path when Vertex Live WebSocket is not open:
    _usingCloud = false;
    await _speech.stop(this);
    await _cloud?.cancel();

    state = state.copyWith(
      phase: OvaVoicePhase.thinking,
      userTranscript: text,
      friendlyActivity: 'Looking into that for you…',
      amplitude: 0.25,
      clearError: true,
    );

    final tasks = ref.read(ovaTaskCenterProvider.notifier);
    final taskId = tasks.start(
      text.length > 64 ? '${text.substring(0, 64)}…' : text,
      source: isOverlaySurface ? 'ova' : 'ai_lab',
    );
    final stepIdx = tasks.addStep(
      taskId,
      'Looking into your request',
      Icons.auto_awesome_rounded,
    );
    _currentTaskId = taskId;

    String spokenReply = '';
    String? routeToOpen;
    OvaToolResult? turnToolResult;
    bool ok = true;
    bool degraded = false;

    try {
      final registry = ref.read(ovaToolRegistryProvider);

      if (_asksForProgress(text)) {
        spokenReply = ref.read(ovaTaskCenterProvider).progressReport(exceptId: taskId);
      }

      final local = spokenReply.isEmpty ? OvaLocalIntents.parse(text) : null;
      if (local != null) {
        final spec = registry.spec(local.tool);
        if (spec != null) {
          if (spec.risk == OvaRisk.confirm) {
            spokenReply =
                'Please tap confirm on the screen so I can ${registry.describe(local.tool, local.args).title.toLowerCase()} for you.';
          } else {
            final friendly = friendlyOvaStepLabel(local.tool, local.args);
            state = state.copyWith(friendlyActivity: '$friendly…');
            final res = await registry.run(
              local.tool,
              local.args,
              _permissionContext,
              _invocation,
            );
            turnToolResult = res;
            spokenReply = res.summary;
            routeToOpen = res.navigateTo;
            ok = res.ok;
          }
        }
      }

      final lower = text.toLowerCase();
      if (spokenReply.isEmpty &&
          (lower.contains('repair') ||
              lower.contains('diagnos') ||
              lower.contains('health check') ||
              lower.contains('system health'))) {
        final repairEngine = ref.read(oneOvaSelfRepairEngineProvider);
        final uid = Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser?.uid : null;
        if (uid != null) {
          await repairEngine.repairUserProfile(uid);
        }
        await repairEngine.repairInterfaceAndCache();
        final health = await repairEngine.runSystemHealthScan();
        final updater = ref.read(oneOvaAutoUpdaterProvider);
        final upd = await updater.checkForUpdates();
        spokenReply =
            'Everything looks good! Your app health is ${health.overallScore}% and you are ${upd.hasUpdate ? "ready for a new update" : "right up to date"}.';
      }

      if (spokenReply.isEmpty) {
        await Future.wait([
          OvaMemoryTools.instance.warm(),
          OvaAccountContext.instance.warm(),
          OvaNotificationMemoryService.instance.warm(),
        ]);
        final tempHistory = [
          ..._voiceHistory,
          {'role': 'user', 'content': text},
        ];

        final llm = ref.read(ovaLlmClientProvider);
        final voiceSystemPrompt = _buildVertexLiveSystemInstruction();

        String? lastToolSummary;
        for (var round = 0; round < 4; round++) {
          if (_disposed) return;
          final textBuf = StringBuffer();
          final calls = <OvaToolCall>[];
          bool roundDegraded = false;

          await for (final ev in llm.stream(
            system: voiceSystemPrompt,
            history: tempHistory,
            tools: registry.specs,
          )) {
            if (_disposed) return;
            switch (ev) {
              case OvaTextDelta():
                textBuf.write(ev.text);
              case OvaToolCallsEvent():
                calls.addAll(ev.calls);
              case OvaLlmDegraded():
                roundDegraded = true;
              case OvaLlmError():
                break;
            }
          }

          if (roundDegraded) degraded = true;
          final replyChunk = textBuf.toString().trim();

          tempHistory.add({
            'role': 'assistant',
            'content': replyChunk,
            if (calls.isNotEmpty)
              'tool_calls': calls
                  .map((c) => {
                        'id': c.id,
                        'type': 'function',
                        'function': {
                          'name': c.name,
                          'arguments': jsonEncode(c.args),
                        },
                      })
                  .toList(),
          });

          if (calls.isEmpty) {
            if (replyChunk.isNotEmpty) {
              spokenReply = _toSpokenProse(replyChunk);
            } else if (lastToolSummary != null && lastToolSummary.isNotEmpty) {
              spokenReply = _toSpokenProse(lastToolSummary);
            }
            break;
          }

          for (final c in calls) {
            final spec = registry.spec(c.name);
            String toolOut;
            if (spec == null) {
              toolOut = 'That action is not available on this device.';
            } else if (spec.risk == OvaRisk.confirm) {
              toolOut =
                  'Requires user confirmation: ${registry.describe(c.name, c.args).title}.';
              lastToolSummary =
                  'Please tap confirm on the screen so I can ${registry.describe(c.name, c.args).title.toLowerCase()} for you.';
            } else {
              final friendly = friendlyOvaStepLabel(c.name, c.args);
              state = state.copyWith(friendlyActivity: '$friendly…');
              final toolStep = tasks.addStep(taskId, friendly, Icons.auto_awesome_rounded);
              final res = await registry.run(
                c.name,
                c.args,
                _permissionContext,
                _invocation,
              );
              turnToolResult = res;
              tasks.updateStep(
                taskId,
                toolStep,
                res.ok ? OvaStepStatus.done : OvaStepStatus.failed,
              );
              routeToOpen ??= res.navigateTo;
              if (!res.ok) ok = false;
              toolOut = res.summary;
              lastToolSummary = res.summary;
            }
            tempHistory.add({
              'role': 'tool',
              'tool_call_id': c.id,
              'name': c.name,
              'content': toolOut,
            });
          }

          if (routeToOpen != null && lastToolSummary != null) {
            spokenReply = _toSpokenProse(lastToolSummary);
            break;
          }
        }
      }
    } catch (e) {
      ok = false;
      degraded = true;
      debugPrint('[OvaVoiceSession] utterance processing error: $e');
      spokenReply = 'I had a brief connection hiccup—could you say that one more time for me?';
    }

    tasks.updateStep(taskId, stepIdx, ok ? OvaStepStatus.done : OvaStepStatus.failed);
    tasks.finish(
      taskId,
      ok: ok,
      summary: spokenReply.length > 140
          ? '${spokenReply.substring(0, 140)}…'
          : spokenReply,
    );

    await _persistUnifiedTurn(
      userText: text,
      assistantText: spokenReply,
      toolResult: turnToolResult,
      persistToFirestore: !degraded,
    );

    if (_disposed) return;

    final trimmed = spokenReply.trim();
    _pendingQuestion = trimmed.endsWith('?') ? trimmed : null;
    state = state.copyWith(
      phase: state.audioEnabled ? OvaVoicePhase.speaking : OvaVoicePhase.listening,
      assistantReply: spokenReply,
      amplitude: state.audioEnabled ? 0.65 : 0.0,
      pendingRoute: routeToOpen,
      clearActivity: true,
    );

    if (state.audioEnabled && spokenReply.isNotEmpty) {
      await _speakViaVertexNativeAudio(spokenReply);
    } else if (!state.isMicMuted && !state.isPaused) {
      await _beginFallbackListening();
    }
  }

  Future<void> togglePause() async {
    HapticFeedback.selectionClick();
    if (state.isPaused) {
      await startSession(
        workspace: _workspace,
        invocation: _invocation,
        permissionContext: _permissionContext,
      );
    } else {
      state = state.copyWith(
        phase: OvaVoicePhase.paused,
        amplitude: 0.0,
        clearActivity: true,
      );
      await _enterStandbyOrStop();
    }
  }

  Future<void> toggleMic() async {
    HapticFeedback.lightImpact();
    if (state.phase == OvaVoicePhase.idle || state.isPaused) {
      await startSession(
        workspace: _workspace,
        invocation: _invocation,
        permissionContext: _permissionContext,
      );
      return;
    }
    if (state.phase == OvaVoicePhase.speaking) {
      // Barge-in: stop speaking immediately and listen to the user
      try {
        await OvaVertexAudioEngine.instance.stop();
      } catch (_) {}
      state = state.copyWith(
        phase: OvaVoicePhase.listening,
        isMicMuted: false,
        amplitude: 0.06,
      );
      if (_liveSession == null) {
        await _beginFallbackListening();
      }
      return;
    }

    final nextMuted = !state.isMicMuted;
    state = state.copyWith(
      isMicMuted: nextMuted,
      phase: state.isPaused ? OvaVoicePhase.paused : OvaVoicePhase.listening,
      amplitude: 0.0,
    );
    if (nextMuted) {
      _usingCloud = false;
      await _speech.cancel(this);
      await _cloud?.cancel();
    } else if (!state.isPaused && _liveSession == null) {
      await _beginFallbackListening();
    }
  }

  void toggleCaptions() {
    HapticFeedback.selectionClick();
    state = state.copyWith(captionsEnabled: !state.captionsEnabled);
  }

  Future<void> toggleAudioOutput() async {
    HapticFeedback.selectionClick();
    final nextAudio = !state.audioEnabled;
    state = state.copyWith(audioEnabled: nextAudio);
    if (!nextAudio && state.phase == OvaVoicePhase.speaking) {
      try {
        await OvaVertexAudioEngine.instance.stop();
      } catch (_) {}
      state = state.copyWith(phase: OvaVoicePhase.listening, amplitude: 0.0);
    }
  }

  void toggleVoiceEnhance() {
    HapticFeedback.selectionClick();
    state = state.copyWith(voiceEnhanced: !state.voiceEnhanced);
  }

  Future<void> setSpeechRate(double rate) async {
    final clamped = rate.clamp(0.35, 0.75);
    state = state.copyWith(speechRate: clamped);
  }

  Future<void> retryMicrophone() async {
    if (_disposed) return;
    HapticFeedback.lightImpact();
    _heldByOtherApp = false;
    OneovaAiGateway.resetCooldown();
    await _stopHardware();
    if (_disposed) return;
    await startSession(
      workspace: _workspace,
      invocation: _invocation,
      permissionContext: _permissionContext,
    );
  }

  Future<void> endSession() async {
    HapticFeedback.mediumImpact();
    if (!_disposed) {
      state = state.copyWith(
        phase: OvaVoicePhase.idle,
        amplitude: 0.0,
        isMicMuted: false,
        isVertexLiveConnected: false,
        clearError: true,
        clearActivity: true,
      );
    }
    await _stopHardware();
    if (state.wakeCallEnabled && !_disposed) {
      unawaited(_startWakeWordStandby());
    }
  }

  static final RegExp _progressAsk = RegExp(
    r"\b(progress|status|update me|what('?s| is) (happening|going on|running)|what are you (doing|working on)|how far|is it (done|finished|ready)|still (working|running)|background)\b",
    caseSensitive: false,
  );

  static bool _asksForProgress(String text) =>
      text.length < 120 && _progressAsk.hasMatch(text);

  String _liveContext(String taskId) {
    final now = DateTime.now();
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    return 'Current local time: ${days[now.weekday - 1]} $hh:$mm. '
        'User language: ${locale.toLanguageTag()}.\n'
        '${OvaAccountContext.instance.contextLine()}\n'
        '${OvaMemoryTools.instance.contextLine()}\n'
        '${OvaGeoTools.instance.contextLine()}\n'
        '${OvaNotificationMemoryService.instance.buildOnDemandContext(latestUserQuery: state.userTranscript)}\n'
        'Background tasks:\n${ref.read(ovaTaskCenterProvider).progressContext(exceptId: taskId)}';
  }

  Future<void> _announce(String line) async {
    if (!state.audioEnabled) {
      state = state.copyWith(assistantReply: line);
      return;
    }
    if (_liveSession != null) {
      try {
        await _liveSession!.sendTextRealtime('Say this brief update warmly to the user: $line');
        return;
      } catch (_) {}
    }
    await _speech.stop(this);
    await _cloud?.cancel();
    if (_disposed) return;
    state = state.copyWith(
      phase: OvaVoicePhase.speaking,
      assistantReply: line,
      amplitude: 0.5,
    );
    await _speakViaVertexNativeAudio(line);
  }

  static String _toSpokenProse(String raw) {
    final lines = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('|') && !l.startsWith('#'))
        .map(
          (l) => l
              .replaceFirst(RegExp(r'^[-*•>]\s*'), '')
              .replaceFirst(RegExp(r'^\d+\.\s*'), '')
              .replaceAll(RegExp(r'[*#_`]'), '')
              .replaceAll(RegExp(r'\[(.*?)\]\(.*?\)'), r'$1')
              .trim(),
        )
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return raw.replaceAll(RegExp(r'[*#_`|]'), '').trim();
    }
    final joined = lines.take(4).join(' ');
    return joined.length > 280 ? '${joined.substring(0, 280).trim()}…' : joined;
  }

  Future<void> _stopHardware() async {
    _silenceTimer?.cancel();
    _usingCloud = false;
    _wakeStandbyListening = false;
    await _closeVertexLiveSession();
    await _speech.cancel(this);
    await _cloud?.cancel();
    try {
      await OvaVertexAudioEngine.instance.stop();
    } catch (_) {}
    await _releaseLease();
  }
}
