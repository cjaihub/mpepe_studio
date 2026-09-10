import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cloud_functions/cloud_functions.dart';

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
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  @override
  AiVoiceState build() {
    _initTts();
    return AiVoiceState();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> startListening() async {
    bool available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          state = state.copyWith(isListening: false);
          if (state.lastWords.isNotEmpty) {
            _processCommand(state.lastWords);
          }
        }
      },
      onError: (errorNotification) {
        state = state.copyWith(isListening: false);
      },
    );

    if (available) {
      state = state.copyWith(isListening: true, lastWords: '');
      _speech.listen(
        onResult: (result) {
          state = state.copyWith(lastWords: result.recognizedWords);
        },
        onSoundLevelChange: (level) {
          state = state.copyWith(soundLevel: level);
        }
      );
    }
  }

  Future<void> stopListening() async {
    await _speech.stop();
    state = state.copyWith(isListening: false);
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
    await _tts.speak(text);
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
  }
}
