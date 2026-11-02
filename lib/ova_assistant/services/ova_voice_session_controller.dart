import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../backend/ai_brain_service.dart';
import '../../backend/repair/oneova_auto_updater.dart';
import '../../backend/repair/oneova_self_repair_engine.dart';
import '../../backend/security/oneova_ai_gateway.dart';
import '../core/ova_tool_result.dart';
import '../widgets/ova_fluid_voice_orb.dart';
import 'ova_chat_controller.dart';
import 'ova_local_intents.dart';
import 'ova_shared_history_service.dart';
import 'ova_task_center.dart';
import 'ova_tool_registry.dart';

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
    this.speechRate = 0.50,
    this.errorMessage,
    this.pendingRoute,
  });

  bool get isActive => phase != OvaVoicePhase.idle;
  bool get isPaused => phase == OvaVoicePhase.paused;

  OvaOrbMode get orbMode => switch (phase) {
        OvaVoicePhase.idle => OvaOrbMode.idle,
        OvaVoicePhase.listening => isMicMuted ? OvaOrbMode.idle : OvaOrbMode.listening,
        OvaVoicePhase.thinking => OvaOrbMode.thinking,
        OvaVoicePhase.speaking => OvaOrbMode.speaking,
        OvaVoicePhase.paused => OvaOrbMode.paused,
      };

  String get statusLabel => switch (phase) {
        OvaVoicePhase.idle => 'Tap mic to start',
        OvaVoicePhase.listening => isMicMuted ? 'Mic muted' : 'Listening...',
        OvaVoicePhase.thinking => 'Thinking...',
        OvaVoicePhase.speaking => 'Speaking...',
        OvaVoicePhase.paused => 'Paused',
      };

  OvaVoiceSessionState copyWith({
    OvaVoicePhase? phase,
    String? userTranscript,
    String? assistantReply,
    double? amplitude,
    bool? isMicMuted,
    bool? captionsEnabled,
    bool? audioEnabled,
    bool? voiceEnhanced,
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
      speechRate: speechRate ?? this.speechRate,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pendingRoute: clearRoute ? null : (pendingRoute ?? this.pendingRoute),
    );
  }
}

/// Separate session providers for Ova Main Interface vs Ova Overlay Assistant,
/// while syncing all completed voice turns & tasks to [ovaSharedHistoryProvider]
/// and [ovaTaskCenterProvider].
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

abstract class OvaVoiceSessionBaseNotifier extends Notifier<OvaVoiceSessionState> {
  bool get isOverlaySurface;

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _speechReady = false;
  bool _ttsReady = false;
  bool _disposed = false;
  String? _activeThreadId;
  OvaWorkspaceId _workspace = OvaWorkspaceId.personal;
  OvaInvocationContext _invocation = const OvaInvocationContext();
  BuildContext? _permissionContext;

  @override
  OvaVoiceSessionState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
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

  Future<void> _ensureTts() async {
    if (_ttsReady) return;
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
      await _tts.setSpeechRate(state.speechRate);
      await _tts.setPitch(1.0);

      _tts.setCompletionHandler(() {
        if (_disposed) return;
        if (state.phase == OvaVoicePhase.speaking) {
          if (!state.isMicMuted && !state.isPaused) {
            _beginListeningInternal();
          } else {
            state = state.copyWith(phase: OvaVoicePhase.listening, amplitude: 0.0);
          }
        }
      });

      _tts.setErrorHandler((_) {
        if (_disposed) return;
        if (state.phase == OvaVoicePhase.speaking) {
          state = state.copyWith(phase: OvaVoicePhase.listening, amplitude: 0.0);
        }
      });
      _ttsReady = true;
    } catch (e) {
      debugPrint('[OvaVoiceSession] TTS setup skipped: $e');
    }
  }

  /// Starts or resumes a live voice session.
  Future<void> startSession({
    OvaWorkspaceId workspace = OvaWorkspaceId.personal,
    OvaInvocationContext invocation = const OvaInvocationContext(),
    BuildContext? permissionContext,
  }) async {
    _workspace = workspace;
    _invocation = invocation;
    _permissionContext = permissionContext;
    OneovaAiGateway.resetCooldown();
    _activeThreadId ??= ref
        .read(ovaSharedHistoryProvider.notifier)
        .newThreadId(isOverlaySurface ? 'overlay_voice' : 'main_voice');

    HapticFeedback.lightImpact();

    state = state.copyWith(
      phase: OvaVoicePhase.listening,
      isMicMuted: false,
      clearError: true,
      assistantReply: state.assistantReply.isEmpty
          ? 'Hi, I\'m listening. Ask anything or give me a task.'
          : state.assistantReply,
    );

    await _ensureTts();
    if (_disposed || state.isPaused || state.phase == OvaVoicePhase.idle) return;

    await _beginListeningInternal();
  }

  Future<void> _beginListeningInternal() async {
    if (_disposed || state.isPaused || state.isMicMuted) return;

    try {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        if (_disposed) return;
        state = state.copyWith(
          phase: OvaVoicePhase.listening,
          isMicMuted: true,
          errorMessage: micStatus.isPermanentlyDenied
              ? 'Microphone access is off. Enable it in Settings to speak.'
              : 'Microphone permission needed for live voice.',
        );
        return;
      }
    } catch (_) {
      // In desktop/test environments where Permission plugin is unmocked, proceed gracefully.
    }

    if (!_speechReady) {
      try {
        _speechReady = await _speech.initialize(
          onStatus: (status) {
            if (_disposed) return;
            if ((status == 'done' || status == 'notListening') &&
                state.phase == OvaVoicePhase.listening &&
                !state.isMicMuted &&
                !state.isPaused) {
              // Keep continuous session alive gently if no thinking turn took over.
              Future.delayed(const Duration(milliseconds: 350), () {
                if (!_disposed &&
                    state.phase == OvaVoicePhase.listening &&
                    !state.isMicMuted &&
                    !state.isPaused &&
                    !_speech.isListening) {
                  _listenPass();
                }
              });
            }
          },
          onError: (err) {
            debugPrint('[OvaVoiceSession] STT error: $err');
          },
        );
      } catch (e) {
        _speechReady = false;
        debugPrint('[OvaVoiceSession] STT init unavailable: $e');
      }
    }

    if (_disposed || state.isPaused || state.phase == OvaVoicePhase.idle) return;
    state = state.copyWith(phase: OvaVoicePhase.listening, clearError: true);
    if (_speechReady) {
      await _listenPass();
    }
  }

  Future<void> _listenPass() async {
    if (!_speechReady || _disposed || state.isMicMuted || state.isPaused) return;
    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: stt.ListenMode.dictation,
        ),
        onSoundLevelChange: (level) {
          if (_disposed || state.phase != OvaVoicePhase.listening) return;
          final normalized = ((level + 2.0) / 12.0).clamp(0.04, 1.0);
          state = state.copyWith(amplitude: normalized);
        },
        onResult: (result) {
          if (_disposed) return;
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            state = state.copyWith(userTranscript: words);
          }
          if (result.finalResult && words.isNotEmpty) {
            submitSpokenUtterance(words);
          }
        },
      );
    } catch (e) {
      debugPrint('[OvaVoiceSession] listenPass error: $e');
    }
  }

  /// Processes a committed spoken utterance through Ova tools + AI brain + TTS.
  Future<void> submitSpokenUtterance(String rawUtterance) async {
    final text = rawUtterance.trim();
    if (text.isEmpty || _disposed) return;

    try {
      await _speech.stop();
    } catch (_) {}

    state = state.copyWith(
      phase: OvaVoicePhase.thinking,
      userTranscript: text,
      amplitude: 0.25,
      clearError: true,
    );

    final tasks = ref.read(ovaTaskCenterProvider.notifier);
    final taskId = tasks.start(
      text.length > 64 ? '${text.substring(0, 64)}…' : text,
      source: isOverlaySurface ? 'ova' : 'ai_lab',
    );
    final stepIdx = tasks.addStep(taskId, 'Voice · Processing request', Icons.graphic_eq_rounded);

    String spokenReply = '';
    String? routeToOpen;
    bool ok = true;
    bool degraded = false;

    try {
      // 1. Fast local & device tool intents (flashlight, timer, go live, search, etc.)
      final local = OvaLocalIntents.parse(text);
      if (local != null) {
        final registry = ref.read(ovaToolRegistryProvider);
        final spec = registry.spec(local.tool);
        if (spec != null && spec.risk != OvaRisk.confirm) {
          final res = await registry.run(local.tool, local.args, _permissionContext, _invocation);
          spokenReply = res.summary;
          routeToOpen = res.navigateTo;
          ok = res.ok;
        }
      }

      // 2. Self-repair & health check voice trigger
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
            'System check complete. Your Oneova health score is ${health.overallScore}% and build v${OneOvaAutoUpdater.currentVersion} is ${upd.hasUpdate ? "ready for an update" : "up to date"}.';
      }

      // 3. Conversational reasoning via AI Brain
      if (spokenReply.isEmpty) {
        final aiBrain = ref.read(aiBrainProvider);
        final res = await aiBrain.processRequest(
          [
            {'role': 'user', 'content': text},
          ],
          taskType: 'audio',
          userContextPrompt:
              'You are Ova in a live private voice session inside Oneova (${_workspace.label} workspace). '
              'Reply naturally in 1 to 3 concise spoken sentences without markdown formatting or bullet symbols.',
        );
        if (res is AiTextResponse && res.text.trim().isNotEmpty) {
          degraded = res.isDegraded;
          spokenReply = _toSpokenProse(res.text, isDegraded: res.isDegraded);
        } else if (res is AiToolCallResponse) {
          spokenReply = 'Done. I ran that studio tool for you.';
        }
      }

      if (spokenReply.isEmpty) {
        spokenReply = 'Got it. I\'ve noted that in your ${_workspace.shortLabel.toLowerCase()} workspace.';
      }
    } catch (e) {
      ok = false;
      degraded = true;
      debugPrint('[OvaVoiceSession] utterance processing error: $e');
      spokenReply = 'I ran into a temporary connection hiccup. Please try saying that again.';
    }

    tasks.updateStep(taskId, stepIdx, ok ? OvaStepStatus.done : OvaStepStatus.failed);
    tasks.finish(
      taskId,
      ok: ok,
      summary: spokenReply.length > 140 ? '${spokenReply.substring(0, 140)}…' : spokenReply,
    );

    // Sync to shared History & Activities across Main and Overlay interfaces
    _activeThreadId = await ref.read(ovaSharedHistoryProvider.notifier).recordTurn(
          query: text,
          response: spokenReply,
          source: OvaOriginSource.voice,
          workspace: _workspace,
          threadId: _activeThreadId,
          persistToFirestore: !degraded,
        );

    if (_disposed) return;

    state = state.copyWith(
      phase: state.audioEnabled ? OvaVoicePhase.speaking : OvaVoicePhase.listening,
      assistantReply: spokenReply,
      amplitude: state.audioEnabled ? 0.65 : 0.0,
      pendingRoute: routeToOpen,
    );

    if (state.audioEnabled) {
      await _ensureTts();
      try {
        await _tts.speak(spokenReply);
      } catch (_) {
        if (!_disposed) {
          state = state.copyWith(phase: OvaVoicePhase.listening, amplitude: 0.0);
        }
      }
    } else if (!state.isMicMuted && !state.isPaused) {
      await _beginListeningInternal();
    }
  }

  /// Toggles Pause / Resume on the live voice session.
  Future<void> togglePause() async {
    HapticFeedback.selectionClick();
    if (state.isPaused) {
      state = state.copyWith(phase: OvaVoicePhase.listening, amplitude: 0.0);
      if (!state.isMicMuted) {
        await _beginListeningInternal();
      }
    } else {
      state = state.copyWith(phase: OvaVoicePhase.paused, amplitude: 0.0);
      await _stopHardware();
    }
  }

  /// Toggles Microphone mute/unmute (or starts session if idle).
  Future<void> toggleMic() async {
    HapticFeedback.lightImpact();
    if (state.phase == OvaVoicePhase.idle) {
      await startSession(workspace: _workspace, invocation: _invocation);
      return;
    }
    if (state.phase == OvaVoicePhase.speaking) {
      // Barge-in: interrupt TTS and listen immediately.
      try {
        await _tts.stop();
      } catch (_) {}
      state = state.copyWith(phase: OvaVoicePhase.listening, isMicMuted: false, amplitude: 0.0);
      await _beginListeningInternal();
      return;
    }

    final nextMuted = !state.isMicMuted;
    state = state.copyWith(
      isMicMuted: nextMuted,
      phase: state.isPaused ? OvaVoicePhase.paused : OvaVoicePhase.listening,
      amplitude: 0.0,
    );
    if (nextMuted) {
      try {
        await _speech.stop();
      } catch (_) {}
    } else if (!state.isPaused) {
      await _beginListeningInternal();
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
        await _tts.stop();
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
    try {
      await _tts.setSpeechRate(clamped);
    } catch (_) {}
  }

  /// Ends the voice session and releases mic + TTS cleanly.
  Future<void> endSession() async {
    HapticFeedback.mediumImpact();
    _activeThreadId = null;
    if (!_disposed) {
      state = state.copyWith(
        phase: OvaVoicePhase.idle,
        amplitude: 0.0,
        isMicMuted: false,
        clearError: true,
      );
    }
    await _stopHardware();
  }

  static String _toSpokenProse(String raw, {required bool isDegraded}) {
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
      return isDegraded
          ? 'I\'m currently in Local Ova mode. Voice commands like open camera, go live, or set a timer work right away.'
          : raw.replaceAll(RegExp(r'[*#_`|]'), '').trim();
    }

    final joined = lines.take(isDegraded ? 2 : 4).join(' ');
    return joined.length > 260 ? '${joined.substring(0, 260).trim()}…' : joined;
  }

  Future<void> _stopHardware() async {
    try {
      await _speech.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
