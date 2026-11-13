import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../shared/audio/cloud_dictation.dart';
import '../shared/audio/mic_coordinator.dart';
import '../shared/audio/speech_hub.dart';
import 'ai_brain_service.dart';

enum VoiceState { idle, listening, processing, speaking }

class VoiceAssistantState {
  final VoiceState state;
  final String currentText;
  final String currentVoice;
  final double soundLevel;
  final bool isContinuous;
  
  VoiceAssistantState({
    this.state = VoiceState.idle,
    this.currentText = '',
    this.currentVoice = '',
    this.soundLevel = 0.0,
    this.isContinuous = false,
  });

  VoiceAssistantState copyWith({
    VoiceState? state,
    String? currentText,
    String? currentVoice,
    double? soundLevel,
    bool? isContinuous,
  }) {
    return VoiceAssistantState(
      state: state ?? this.state,
      currentText: currentText ?? this.currentText,
      currentVoice: currentVoice ?? this.currentVoice,
      soundLevel: soundLevel ?? this.soundLevel,
      isContinuous: isContinuous ?? this.isContinuous,
    );
  }
}

class VoiceAssistantService extends Notifier<VoiceAssistantState> {
  final FlutterTts _tts = FlutterTts();
  final SpeechHub _speech = SpeechHub.instance;
  MicLease? _micLease;
  CloudDictation? _cloud;
  bool _usingCloud = false;

  @override
  VoiceAssistantState build() {
    _initTTS();
    ref.onDispose(() {
      unawaited(_speech.cancel(this));
      unawaited(_cloud?.dispose());
      unawaited(_micLease?.release());
      _micLease = null;
      unawaited(_tts.stop());
    });
    return VoiceAssistantState();
  }

  Future<void> _initTTS() async {
    await _tts.setSharedInstance(true);
    await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers
        ]);
    
    _tts.setStartHandler(() {
      state = state.copyWith(state: VoiceState.speaking);
    });

    _tts.setCompletionHandler(() {
      state = state.copyWith(state: VoiceState.idle, currentText: '');
      if (state.isContinuous) {
        startListening(continuous: true);
      }
    });

    _tts.setErrorHandler((msg) {
      debugPrint("TTS Error: $msg");
      state = state.copyWith(state: VoiceState.idle, isContinuous: false);
    });
  }

  Future<List<Map<String, String>>> getAvailableVoices() async {
    try {
      final voices = await _tts.getVoices;
      List<Map<String, String>> voiceList = [];
      for (var v in voices) {
        voiceList.add({
          "name": v["name"].toString(),
          "locale": v["locale"].toString(),
        });
      }
      return voiceList;
    } catch (e) {
      debugPrint("Error getting voices: $e");
      return [];
    }
  }

  Future<void> setVoice(Map<String, String> voice) async {
    await _tts.setVoice({"name": voice["name"]!, "locale": voice["locale"]!});
    state = state.copyWith(currentVoice: voice["name"]);
  }

  Future<void> _releaseMic() async {
    final lease = _micLease;
    _micLease = null;
    await lease?.release();
  }

  Future<void> startListening({bool continuous = false}) async {
    final got = await MicCoordinator.instance.acquire(
      MicUser.assistant,
      onPreempted: () async {
        _usingCloud = false;
        await _speech.cancel(this);
        await _cloud?.cancel();
        _micLease = null;
        if (ref.mounted) {
          state = state.copyWith(state: VoiceState.idle, isContinuous: false);
        }
      },
      onInterruption: (i) {
        if (i == MicInterruption.heldByOtherApp && ref.mounted && state.state == VoiceState.listening) {
          unawaited(stopListening(force: true));
        }
      },
    );
    if (got is MicBusy) {
      state = state.copyWith(state: VoiceState.idle, isContinuous: false);
      return;
    }
    _micLease = got as MicLease;
    _usingCloud = false;

    state = state.copyWith(state: VoiceState.listening, currentText: '', soundLevel: 0.0, isContinuous: continuous);
    await _tts.stop(); // Stop any ongoing speech

    final started = await _speech.listen(
      owner: this,
      options: stt.SpeechListenOptions(partialResults: true, cancelOnError: true),
      onStatus: (status) {
        if (_usingCloud || !ref.mounted) return;
        if (status == 'done' || status == 'notListening' || status == 'preempted') {
          if (state.state == VoiceState.listening) {
            unawaited(_finishListeningAndProcess());
          }
        }
      },
      onError: (val) {
        debugPrint('STT Error: $val');
        if (_usingCloud || !ref.mounted) return;
        if (val.errorMsg == 'error_no_match' || val.errorMsg == 'error_speech_timeout') {
          unawaited(_finishListeningAndProcess());
        } else {
          unawaited(_startCloudFallback());
        }
      },
      onResult: (val) {
        if (_usingCloud || !ref.mounted) return;
        state = state.copyWith(currentText: val.recognizedWords);
      },
      onSoundLevel: (level) {
        if (_usingCloud || !ref.mounted) return;
        state = state.copyWith(soundLevel: level);
      },
    );
    if (!started && ref.mounted && state.state == VoiceState.listening) {
      await _startCloudFallback();
    }
  }

  Future<void> _startCloudFallback() async {
    if (_usingCloud || !ref.mounted || state.state != VoiceState.listening) return;
    await _speech.cancel(this);
    _usingCloud = true;
    _cloud ??= CloudDictation();
    final ok = await _cloud!.start(
      autoStopOnSilence: true,
      onLevel: (level) {
        if (ref.mounted && _usingCloud) {
          state = state.copyWith(soundLevel: level * 10.0);
        }
      },
      onSilenceCommit: () => unawaited(_finishListeningAndProcess()),
    );
    if (!ok) {
      _usingCloud = false;
      await _releaseMic();
      if (ref.mounted) {
        state = state.copyWith(state: VoiceState.idle, isContinuous: false);
      }
    }
  }

  Future<void> _finishListeningAndProcess() async {
    final wasCloud = _usingCloud;
    _usingCloud = false;
    await _speech.stop(this);
    if (wasCloud) {
      try {
        final text = (await _cloud?.stopAndTranscribe() ?? '').trim();
        if (ref.mounted && text.isNotEmpty) {
          state = state.copyWith(currentText: text);
        }
      } catch (_) {}
    }
    await _releaseMic();
    if (ref.mounted) {
      await _processVoiceInput();
    }
  }

  Future<void> stopListening({bool force = false}) async {
    if (force) {
      state = state.copyWith(isContinuous: false);
    }
    if (state.state == VoiceState.listening) {
      await _finishListeningAndProcess();
    } else {
      await _speech.stop(this);
      await _cloud?.cancel();
      await _releaseMic();
    }
  }

  Future<void> _processVoiceInput() async {
    if (state.currentText.trim().isEmpty) {
      state = state.copyWith(state: VoiceState.idle, isContinuous: false);
      return;
    }
    
    final recognizedText = state.currentText;
    state = state.copyWith(state: VoiceState.processing);

    final messages = [
      {"role": "user", "content": recognizedText}
    ];

    final aiBrain = ref.read(aiBrainProvider);
    final userContext = ref.read(aiUserContextProvider);

    final response = await aiBrain.processRequest(
      messages,
      userContextPrompt: userContext,
    );

    if (response is AiTextResponse) {
      final spoken = response.isDegraded
          ? response.text
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty && !l.startsWith('#') && !l.startsWith('|'))
              .take(2)
              .join(' ')
          : response.text;
      await speak(spoken.isEmpty ? 'Local Ova is ready.' : spoken);
    } else {
      state = state.copyWith(state: VoiceState.idle);
    }
  }

  Future<void> speak(String text) async {
    state = state.copyWith(state: VoiceState.speaking, currentText: text);
    // basic sanitization to avoid reading markdown symbols awkwardly
    final cleanText = text.replaceAll(RegExp(r'[*#_`]'), '');
    await _tts.speak(cleanText);
  }

  Future<void> stopSpeaking({bool force = false}) async {
    if (force) {
      state = state.copyWith(isContinuous: false);
    }
    await _tts.stop();
    state = state.copyWith(state: VoiceState.idle);
  }
}

final voiceAssistantProvider = NotifierProvider<VoiceAssistantService, VoiceAssistantState>(() {
  return VoiceAssistantService();
});
