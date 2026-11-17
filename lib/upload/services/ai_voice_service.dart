import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:cloud_functions/cloud_functions.dart';
import '../../shared/audio/cloud_dictation.dart';
import '../../shared/audio/mic_coordinator.dart';
import '../../shared/audio/ova_vertex_audio_engine.dart';
import '../../shared/audio/speech_hub.dart';

class AiVoiceState {
  final bool isListening;
  final bool isProcessing;
  final String lastWords;
  final String aiResponse;
  final double soundLevel;

  AiVoiceState({
    this.isListening = false,
    this.isProcessing = false,
    this.lastWords = '',
    this.aiResponse = '',
    this.soundLevel = 0.0,
  });

  AiVoiceState copyWith({
    bool? isListening,
    bool? isProcessing,
    String? lastWords,
    String? aiResponse,
    double? soundLevel,
  }) {
    return AiVoiceState(
      isListening: isListening ?? this.isListening,
      isProcessing: isProcessing ?? this.isProcessing,
      lastWords: lastWords ?? this.lastWords,
      aiResponse: aiResponse ?? this.aiResponse,
      soundLevel: soundLevel ?? this.soundLevel,
    );
  }
}

final aiVoiceServiceProvider = NotifierProvider<AiVoiceService, AiVoiceState>(() => AiVoiceService());

class AiVoiceService extends Notifier<AiVoiceState> {
  final SpeechHub _speech = SpeechHub.instance;
  MicLease? _micLease;
  CloudDictation? _cloud;
  bool _usingCloud = false;

  @override
  AiVoiceState build() {
    ref.onDispose(() {
      unawaited(_speech.cancel(this));
      unawaited(_cloud?.dispose());
      unawaited(_micLease?.release());
      _micLease = null;
      unawaited(OvaVertexAudioEngine.instance.stop());
    });
    return AiVoiceState();
  }

  Future<void> _releaseMic() async {
    final lease = _micLease;
    _micLease = null;
    await lease?.release();
  }

  Future<void> startListening() async {
    final got = await MicCoordinator.instance.acquire(
      MicUser.assistant,
      onPreempted: () async {
        _usingCloud = false;
        await _speech.cancel(this);
        await _cloud?.cancel();
        _micLease = null;
        if (ref.mounted) {
          state = state.copyWith(isListening: false);
        }
      },
      onInterruption: (i) {
        if (i == MicInterruption.heldByOtherApp && ref.mounted && state.isListening) {
          unawaited(stopListening());
        }
      },
    );
    if (got is MicBusy) {
      state = state.copyWith(isListening: false, aiResponse: got.message);
      return;
    }
    _micLease = got as MicLease;
    _usingCloud = false;
    state = state.copyWith(isListening: true, lastWords: '');

    final available = await _speech.listen(
      owner: this,
      options: stt.SpeechListenOptions(partialResults: true, cancelOnError: true),
      onStatus: (status) {
        if (_usingCloud || !ref.mounted) return;
        if (status == 'done' || status == 'notListening' || status == 'preempted') {
          unawaited(_finishListening());
        }
      },
      onError: (errorNotification) {
        if (_usingCloud || !ref.mounted) return;
        if (errorNotification.errorMsg == 'error_no_match' ||
            errorNotification.errorMsg == 'error_speech_timeout') {
          unawaited(_finishListening());
        } else {
          unawaited(_startCloudFallback());
        }
      },
      onResult: (result) {
        if (_usingCloud || !ref.mounted) return;
        state = state.copyWith(lastWords: result.recognizedWords);
      },
      onSoundLevel: (level) {
        if (_usingCloud || !ref.mounted) return;
        state = state.copyWith(soundLevel: level);
      },
    );

    if (!available && ref.mounted && state.isListening) {
      await _startCloudFallback();
    }
  }

  Future<void> _startCloudFallback() async {
    if (_usingCloud || !ref.mounted || !state.isListening) return;
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
      onSilenceCommit: () => unawaited(_finishListening()),
    );
    if (!ok) {
      _usingCloud = false;
      await _releaseMic();
      if (ref.mounted) {
        state = state.copyWith(isListening: false);
      }
    }
  }

  Future<void> _finishListening() async {
    final wasCloud = _usingCloud;
    _usingCloud = false;
    await _speech.stop(this);
    if (wasCloud) {
      try {
        final text = (await _cloud?.stopAndTranscribe() ?? '').trim();
        if (ref.mounted && text.isNotEmpty) {
          state = state.copyWith(lastWords: text);
        }
      } catch (_) {}
    }
    await _releaseMic();
    if (!ref.mounted) return;
    state = state.copyWith(isListening: false);
    if (state.lastWords.trim().isNotEmpty) {
      await _processCommand(state.lastWords.trim());
    }
  }

  Future<void> stopListening() async {
    if (state.isListening) {
      await _finishListening();
    } else {
      await _speech.stop(this);
      await _cloud?.cancel();
      await _releaseMic();
    }
  }

  Future<void> _processCommand(String text) async {
    state = state.copyWith(isProcessing: true);

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('processAiCommand');
      final result = await callable.call({'transcript': text});
      
      final reply = result.data['result']?['actionable_response'] ?? 'I have completed your request.';
      state = state.copyWith(aiResponse: reply);
      
      await speak(reply);
    } catch (e) {
      state = state.copyWith(aiResponse: "I'm sorry, I couldn't process that.");
      await speak(state.aiResponse);
    } finally {
      state = state.copyWith(isProcessing: false);
    }
  }

  Future<void> speak(String text) async {
    await OvaVertexAudioEngine.instance.speak(text);
  }

  Future<void> stopSpeaking() async {
    await OvaVertexAudioEngine.instance.stop();
  }
}
