import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
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
  final stt.SpeechToText _stt = stt.SpeechToText();

  @override
  VoiceAssistantState build() {
    _initTTS();
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

  Future<void> startListening({bool continuous = false}) async {
    bool available = await _stt.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (state.state == VoiceState.listening) {
            _processVoiceInput();
          }
        }
      },
      onError: (val) {
        debugPrint('STT Error: $val');
        state = state.copyWith(state: VoiceState.idle, isContinuous: false);
      },
    );

    if (available) {
      state = state.copyWith(state: VoiceState.listening, currentText: '', soundLevel: 0.0, isContinuous: continuous);
      _tts.stop(); // Stop any ongoing speech
      _stt.listen(
        onResult: (val) {
          state = state.copyWith(currentText: val.recognizedWords);
        },
        onSoundLevelChange: (level) {
          state = state.copyWith(soundLevel: level);
        }
      );
    }
  }

  Future<void> stopListening({bool force = false}) async {
    if (force) {
      state = state.copyWith(isContinuous: false);
    }
    await _stt.stop();
    // processVoiceInput is called from status handler 'done'
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
