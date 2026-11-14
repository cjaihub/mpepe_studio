import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../shared/audio/cloud_dictation.dart';
import '../../shared/audio/mic_coordinator.dart';
import '../../shared/audio/speech_hub.dart';

import '../../backend/ai_brain_service.dart';
import '../../backend/repair/oneova_auto_updater.dart';
import '../../backend/repair/oneova_self_repair_engine.dart';
import '../../backend/security/oneova_ai_gateway.dart';
import '../core/ova_tool_result.dart';
import '../widgets/ova_fluid_voice_orb.dart';
import 'ova_chat_controller.dart';
import 'ova_llm_client.dart';
import 'ova_local_intents.dart';
import 'ova_account_context.dart';
import 'ova_geo_tools.dart';
import 'ova_memory_tools.dart';
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

  final SpeechHub _speech = SpeechHub.instance;
  final FlutterTts _tts = FlutterTts();
  CloudDictation? _cloud;
  MicLease? _lease;
  bool _heldByOtherApp = false;
  bool _usingCloud = false;
  bool _committingCloud = false;
  AppLifecycleListener? _lifecycle;
  final List<Map<String, dynamic>> _voiceHistory = [];

  bool _speechReady = false;
  bool _ttsReady = false;
  bool _disposed = false;
  String? _activeThreadId;
  /// A question Ova asked that the user hasn't answered yet. Kept while Ova
  /// sleeps, asked again when the user comes back.
  String? _pendingQuestion;
  /// No speech for a while: Ova stops listening and waits to be called.
  Timer? _silenceTimer;
  /// The task for the turn being answered (so it isn't reported as background work).
  String? _currentTaskId;
  OvaWorkspaceId _workspace = OvaWorkspaceId.personal;
  OvaInvocationContext _invocation = const OvaInvocationContext();
  BuildContext? _permissionContext;

  @override
  OvaVoiceSessionState build() {
    _disposed = false;
    // The in-app assistant stops listening when Oneova leaves the screen; the
    // overlay assistant is meant to keep working over other apps.
    if (!isOverlaySurface) {
      _lifecycle = AppLifecycleListener(onPause: () {
        if (!_disposed && state.isActive && !state.isPaused) {
          state = state.copyWith(phase: OvaVoicePhase.paused, amplitude: 0.0);
          unawaited(_stopHardware());
        }
      });
    }
    // Background work finishing while we talk: say so, in one short line.
    ref.listen<OvaTaskState>(ovaTaskCenterProvider, (prev, next) {
      final f = next.justFinished;
      if (f == null || prev?.justFinished?.id == f.id || f.id == _currentTaskId) return;
      if (_disposed || !state.isActive || state.isPaused || state.phase != OvaVoicePhase.listening) return;
      unawaited(_announce('${f.status == OvaTaskStatus.done ? 'Done' : 'Could not finish'}: ${f.title}.'));
    });
    ref.onDispose(() {
      _disposed = true;
      _lifecycle?.dispose();
      unawaited(_cloud?.dispose());
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
    // Carry on where we left off, with no time limit: in memory, or from the
    // conversation saved to the account (after an app restart).
    if (_voiceHistory.isEmpty) _restoreLastVoiceThread();
    final resuming = _voiceHistory.isNotEmpty;
    unawaited(OvaAccountContext.instance.warm());
    _activeThreadId ??= ref
        .read(ovaSharedHistoryProvider.notifier)
        .newThreadId(isOverlaySurface ? 'overlay_voice' : 'main_voice');

    HapticFeedback.lightImpact();

    final lastAsk = resuming
        ? _voiceHistory.lastWhere((m) => m['role'] == 'user', orElse: () => const {'content': ''})['content'] as String? ?? ''
        : '';
    state = state.copyWith(
      phase: OvaVoicePhase.listening,
      isMicMuted: false,
      clearError: true,
      assistantReply: _pendingQuestion != null
          ? 'Welcome back. Before you left I asked: $_pendingQuestion'
          : resuming
          ? (lastAsk.isNotEmpty ? 'Welcome back. We were on “${lastAsk.length > 60 ? '${lastAsk.substring(0, 60)}…' : lastAsk}”. Carry on.' : 'Welcome back. Carry on.')
          : state.assistantReply.isEmpty
              ? 'Hi, I\'m listening. Ask anything or give me a task.'
              : state.assistantReply,
    );

    await _ensureTts();
    if (_disposed || state.isPaused || state.phase == OvaVoicePhase.idle) return;

    // Ova asked something before the user left: ask it again, then listen.
    if (_pendingQuestion != null) {
      await _announce('Welcome back. Before you left I asked: $_pendingQuestion');
      return;
    }
    await _beginListeningInternal();
  }

  /// Loads the latest voice conversation saved to the account.
  void _restoreLastVoiceThread() {
    try {
      final turns = ref.read(ovaSharedHistoryProvider).turns; // newest first
      final latest = turns.where((t) => t.source == OvaOriginSource.voice).firstOrNull;
      if (latest == null) return;
      final thread = [for (final t in turns) if (t.threadId == latest.threadId) t].take(8).toList().reversed;
      for (final t in thread) {
        if (t.query.isNotEmpty) _voiceHistory.add({'role': 'user', 'content': t.query});
        if (t.response.isNotEmpty) _voiceHistory.add({'role': 'assistant', 'content': t.response});
      }
      _activeThreadId = latest.threadId;
      final last = latest.response.trim();
      if (last.endsWith('?')) _pendingQuestion = last;
    } catch (e) {
      debugPrint('[OvaVoiceSession] restore: $e');
    }
  }

  /// Restarts the quiet timer: a pending question waits 45 s, otherwise 90 s,
  /// then Ova stops listening (mic off) and waits to be called.
  void _armSilence() {
    _silenceTimer?.cancel();
    if (_disposed) return;
    _silenceTimer = Timer(Duration(seconds: _pendingQuestion != null ? 45 : 90), () {
      if (_disposed || state.phase != OvaVoicePhase.listening || state.isPaused) return;
      state = state.copyWith(
        phase: OvaVoicePhase.paused,
        amplitude: 0.0,
        assistantReply: _pendingQuestion != null
            ? 'I’ll wait for your answer. Tap the mic or call me when you’re back.'
            : 'I’m resting. Tap the mic or call me when you need me.',
      );
      unawaited(_stopHardware());
    });
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

  /// Takes the mic for Ova. Voice typing, AI voice or a voice note started
  /// later take it back; a call keeps it.
  Future<bool> _ensureMicLease() async {
    if (_lease?.isActive ?? false) return true;
    final got = await MicCoordinator.instance.acquire(
      MicUser.assistant,
      onPreempted: () async {
        _lease = null;
        _usingCloud = false;
        await _speech.cancel(this);
        await _cloud?.cancel();
        try {
          await _tts.stop();
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
          unawaited(_speech.cancel(this));
          unawaited(_cloud?.cancel());
          state = state.copyWith(
            amplitude: 0.0,
            errorMessage: 'Another app is using the microphone. I\'ll continue when it\'s free.',
          );
        } else if (_heldByOtherApp) {
          _heldByOtherApp = false;
          state = state.copyWith(clearError: true);
          if (state.phase == OvaVoicePhase.listening && !state.isMicMuted) {
            unawaited(_speechReady ? _listenPass() : _cloudListenPass());
          }
        }
      },
    );
    if (got is MicBusy) {
      if (!_disposed) {
        state = state.copyWith(phase: OvaVoicePhase.listening, isMicMuted: true, errorMessage: got.message);
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
  static const _permissionErrors = {'error_permission', 'error_insufficient_permissions'};

  /// Direct hardware microphone capture + Gemini transcription with VAD when
  /// the phone's external SpeechRecognizer app is missing, disabled, or busy.
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
          errorMessage: 'Voice input isn\'t available right now. Type your request instead.',
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
      debugPrint('[OvaVoiceSession] cloud dictation error: $e');
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
    if (!_speechReady || _disposed || state.isMicMuted || state.isPaused || _heldByOtherApp) return;
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
          if (_disposed || _usingCloud) return;
          if ((status == 'done' || status == 'notListening') &&
              state.phase == OvaVoicePhase.listening &&
              !state.isMicMuted &&
              !state.isPaused) {
            // Keep the conversation open: listen again after a short pause.
            Future.delayed(const Duration(milliseconds: 350), () {
              if (!_disposed &&
                  !_usingCloud &&
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
          if (_disposed || _usingCloud) return;
          debugPrint('[OvaVoiceSession] STT error: ${err.errorMsg}');
          if (_endOfPassErrors.contains(err.errorMsg)) return;
          if (_permissionErrors.contains(err.errorMsg)) {
            state = state.copyWith(
              isMicMuted: true,
              errorMessage: 'Microphone permission is needed to speak with Ova.',
            );
            unawaited(_releaseLease());
            return;
          }
          // External recognizer busy/disabled/offline/language-pack missing:
          // switch immediately to Oneova's direct microphone recorder.
          unawaited(_cloudListenPass());
        },
        onSoundLevel: (level) {
          if (_disposed || state.phase != OvaVoicePhase.listening) return;
          final normalized = ((level + 2.0) / 12.0).clamp(0.04, 1.0);
          state = state.copyWith(amplitude: normalized);
        },
        onResult: (result) {
          if (_disposed || _usingCloud) return;
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
    } catch (e) {
      debugPrint('[OvaVoiceSession] listenPass error: $e');
      if (!_disposed && state.phase == OvaVoicePhase.listening) {
        await _cloudListenPass();
      }
    }
  }

  /// Processes a committed spoken utterance through Ova Agent tools + AI brain + TTS.
  Future<void> submitSpokenUtterance(String rawUtterance) async {
    final text = rawUtterance.trim();
    if (text.isEmpty || _disposed) return;

    _usingCloud = false;
    _silenceTimer?.cancel();
    _pendingQuestion = null;
    await _speech.stop(this);
    await _cloud?.cancel();

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
    _currentTaskId = taskId;

    String spokenReply = '';
    String? routeToOpen;
    bool ok = true;
    bool degraded = false;

    try {
      final registry = ref.read(ovaToolRegistryProvider);

      // 0. "What's happening?": answer from the task centre at once, no AI round trip.
      if (_asksForProgress(text)) {
        spokenReply = ref.read(ovaTaskCenterProvider).progressReport(exceptId: taskId);
      }

      // 1. Fast local & device tool intents (flashlight, timer, go live, search, etc.)
      final local = spokenReply.isEmpty ? OvaLocalIntents.parse(text) : null;
      if (local != null) {
        final spec = registry.spec(local.tool);
        if (spec != null) {
          if (spec.risk == OvaRisk.confirm) {
            spokenReply =
                'For safety, please confirm ${registry.describe(local.tool, local.args).title.toLowerCase()} in the Ova chat panel.';
          } else {
            final res = await registry.run(local.tool, local.args, _permissionContext, _invocation);
            spokenReply = res.summary;
            routeToOpen = res.navigateTo;
            ok = res.ok;
          }
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

      // 3. Full Ova Agent reasoning + tool execution loop via OvaLlmClient
      if (spokenReply.isEmpty) {
        await Future.wait([OvaMemoryTools.instance.warm(), OvaAccountContext.instance.warm()]);
        _voiceHistory.add({'role': 'user', 'content': text});
        if (_voiceHistory.length > 16) {
          _voiceHistory.removeRange(0, _voiceHistory.length - 16);
        }

        final llm = ref.read(ovaLlmClientProvider);
        final voiceSystemPrompt =
            'You are Ova, the real-time voice agent inside Oneova (${_workspace.label} workspace). '
            'Use tools whenever the user asks to take an action, check info, navigate, manage notes/reminders, or control device settings. '
            'Reply in 1 to 3 concise, natural spoken sentences with no markdown symbols, tables, or bullet lists. '
            'Reply in the language the user speaks.\n${_liveContext(taskId)}';

        String? lastToolSummary;
        for (var round = 0; round < 4; round++) {
          if (_disposed) return;
          final textBuf = StringBuffer();
          final calls = <OvaToolCall>[];
          bool roundDegraded = false;

          await for (final ev in llm.stream(
            system: voiceSystemPrompt,
            history: _voiceHistory,
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

          _voiceHistory.add({
            'role': 'assistant',
            'content': replyChunk,
            if (calls.isNotEmpty)
              'tool_calls': calls
                  .map((c) => {
                        'id': c.id,
                        'type': 'function',
                        'function': {'name': c.name, 'arguments': jsonEncode(c.args)},
                      })
                  .toList(),
          });

          if (calls.isEmpty) {
            if (replyChunk.isNotEmpty) {
              spokenReply = _toSpokenProse(replyChunk, isDegraded: degraded);
            } else if (lastToolSummary != null && lastToolSummary.isNotEmpty) {
              spokenReply = _toSpokenProse(lastToolSummary, isDegraded: false);
            }
            break;
          }

          for (final c in calls) {
            final spec = registry.spec(c.name);
            String toolOut;
            if (spec == null) {
              toolOut = 'Tool ${c.name} is not available on this device.';
            } else if (spec.risk == OvaRisk.confirm) {
              toolOut =
                  'Action requires explicit user confirmation in the Ova chat panel: ${registry.describe(c.name, c.args).title}.';
              lastToolSummary =
                  'Please confirm ${registry.describe(c.name, c.args).title.toLowerCase()} in the Ova chat panel.';
            } else {
              final stepLabel = 'Agent · ${c.name.replaceAll('_', ' ')}';
              final toolStep = tasks.addStep(taskId, stepLabel, Icons.bolt_rounded);
              final res = await registry.run(c.name, c.args, _permissionContext, _invocation);
              tasks.updateStep(taskId, toolStep, res.ok ? OvaStepStatus.done : OvaStepStatus.failed);
              routeToOpen ??= res.navigateTo;
              if (!res.ok) ok = false;
              toolOut = res.summary;
              lastToolSummary = res.summary;
            }
            _voiceHistory.add({
              'role': 'tool',
              'tool_call_id': c.id,
              'name': c.name,
              'content': toolOut,
            });
          }

          if (routeToOpen != null && lastToolSummary != null) {
            spokenReply = _toSpokenProse(lastToolSummary, isDegraded: false);
            break;
          }
        }
      }

      // 4. Direct AI Brain fallback if stream returned empty
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
      } else if (_voiceHistory.isEmpty || _voiceHistory.last['role'] != 'assistant') {
        _voiceHistory.add({'role': 'assistant', 'content': spokenReply});
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

    final trimmed = spokenReply.trim();
    _pendingQuestion = trimmed.endsWith('?') ? trimmed : null;
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
      if (_pendingQuestion != null) {
        await _announce('Welcome back. Before you left I asked: $_pendingQuestion');
      } else if (!state.isMicMuted) {
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
      _usingCloud = false;
      await _speech.cancel(this);
      await _cloud?.cancel();
      await _releaseLease();
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

  /// Manually refreshes & re-acquires the microphone if interrupted or stalled.
  Future<void> retryMicrophone() async {
    if (_disposed) return;
    HapticFeedback.lightImpact();
    _heldByOtherApp = false;
    OneovaAiGateway.resetCooldown();
    await _stopHardware();
    if (_disposed) return;
    state = state.copyWith(
      phase: OvaVoicePhase.listening,
      isMicMuted: false,
      clearError: true,
      amplitude: 0.0,
    );
    await _beginListeningInternal();
  }

  /// Ends the voice session and releases mic + TTS. The conversation is kept
  /// (and saved to the account), so reopening carries on where it stopped.
  Future<void> endSession() async {
    HapticFeedback.mediumImpact();
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

  static final RegExp _progressAsk = RegExp(
    r"\b(progress|status|update me|what('?s| is) (happening|going on|running)|what are you (doing|working on)|how far|is it (done|finished|ready)|still (working|running)|background)\b",
    caseSensitive: false,
  );

  static bool _asksForProgress(String text) => text.length < 120 && _progressAsk.hasMatch(text);

  /// Local time, language and background work, added to every voice turn.
  String _liveContext(String taskId) {
    final now = DateTime.now();
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    return 'Now: ${days[now.weekday - 1]} $hh:$mm local time (UTC${now.timeZoneOffset.isNegative ? '-' : '+'}${now.timeZoneOffset.inHours.abs()}). '
        'Phone language: ${locale.toLanguageTag()}.\n'
        '${OvaAccountContext.instance.contextLine()}\n'
        '${OvaMemoryTools.instance.contextLine()}\n'
        '${OvaGeoTools.instance.contextLine()}\n'
        'Background work (answer progress questions from this):\n${ref.read(ovaTaskCenterProvider).progressContext(exceptId: taskId)}';
  }

  /// Speaks a short update between turns, then goes back to listening.
  Future<void> _announce(String line) async {
    if (!state.audioEnabled) {
      state = state.copyWith(assistantReply: line);
      return;
    }
    await _speech.stop(this);
    await _cloud?.cancel();
    if (_disposed) return;
    state = state.copyWith(phase: OvaVoicePhase.speaking, assistantReply: line, amplitude: 0.5);
    await _ensureTts();
    try {
      await _tts.speak(line);
    } catch (_) {
      if (!_disposed) await _beginListeningInternal();
    }
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
    _silenceTimer?.cancel();
    _usingCloud = false;
    await _speech.cancel(this);
    await _cloud?.cancel();
    try {
      await _tts.stop();
    } catch (_) {}
    await _releaseLease();
  }
}
