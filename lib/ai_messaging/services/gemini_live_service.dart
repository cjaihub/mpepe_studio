import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

enum LiveVoiceState {
  disconnected,
  reconnecting,
  listening,
  thinking,
  speaking,
  interrupted,
}

class GeminiLiveState {
  final LiveVoiceState state;
  final List<String> transcript;
  final String? currentError;
  final bool isMuted;

  GeminiLiveState({
    this.state = LiveVoiceState.disconnected,
    this.transcript = const [],
    this.currentError,
    this.isMuted = false,
  });

  GeminiLiveState copyWith({
    LiveVoiceState? state,
    List<String>? transcript,
    String? currentError,
    bool? isMuted,
  }) {
    return GeminiLiveState(
      state: state ?? this.state,
      transcript: transcript ?? this.transcript,
      currentError: currentError ?? this.currentError,
      isMuted: isMuted ?? this.isMuted,
    );
  }
}

/// Voice mode on the Gemini Live model through Vertex AI (Firebase AI Logic,
/// `FirebaseAI.agentPlatform()`): no API key in the app or the backend.
/// Requests are authorized by Firebase (App Check + Auth) against the
/// project's Vertex AI quota, and show up in Firebase AI monitoring.
class GeminiLiveService extends Notifier<GeminiLiveState> {
  /// Vertex Live model; override with Remote Config `live_voice_model`.
  static const String defaultModel = 'gemini-live-2.5-flash-preview-native-audio-09-2025';

  /// Live models are served regionally on Vertex AI.
  static const String location = 'us-central1';

  LiveSession? _session;
  final _audioRecorder = AudioRecorder();
  bool _playerReady = false;
  StreamSubscription<Uint8List>? _recorderSubscription;
  bool _receiving = false;

  @override
  GeminiLiveState build() {
    _initAudio();
    ref.onDispose(_cleanup);
    return GeminiLiveState();
  }

  Future<void> _initAudio() async {
    // Gemini Live returns 24kHz mono 16-bit PCM.
    await FlutterPcmSound.setup(sampleRate: 24000, channelCount: 1);
    _playerReady = true;
  }

  String _model() {
    try {
      final m = FirebaseRemoteConfig.instance.getString('live_voice_model').trim();
      return m.isEmpty ? defaultModel : m;
    } catch (_) {
      return defaultModel;
    }
  }

  Future<void> connect() async {
    state = state.copyWith(state: LiveVoiceState.reconnecting, currentError: null);
    try {
      final model = FirebaseAI.agentPlatform(location: location).liveGenerativeModel(
        model: _model(),
        liveGenerationConfig: LiveGenerationConfig(
          speechConfig: SpeechConfig(voiceName: 'Aoede'),
          responseModalities: [ResponseModalities.audio],
          outputAudioTranscription: AudioTranscriptionConfig(),
        ),
      );
      _session = await model.connect();
      unawaited(_receive());
      await _startRecording();
      state = state.copyWith(state: LiveVoiceState.listening);
    } catch (e) {
      if (kDebugMode) debugPrint('Gemini Live connect error: $e');
      await _cleanup();
      state = state.copyWith(state: LiveVoiceState.disconnected, currentError: 'Could not start voice mode. Try again.');
    }
  }

  Future<void> _startRecording() async {
    if (!await _audioRecorder.hasPermission()) {
      state = state.copyWith(currentError: 'Microphone permission denied.');
      return;
    }
    final audioStream = await _audioRecorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    ));
    _recorderSubscription = audioStream.listen((data) {
      final session = _session;
      if (state.isMuted || session == null) return;
      unawaited(session.sendAudioRealtime(InlineDataPart('audio/pcm', data)).catchError((_) {}));
    });
  }

  Future<void> _receive() async {
    final session = _session;
    if (session == null || _receiving) return;
    _receiving = true;
    String? error;
    try {
      // One stream for the whole session; it ends when the socket closes.
      await for (final response in session.receive()) {
        _handle(response.message);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Gemini Live receive error: $e');
      error = 'Voice mode disconnected.';
    } finally {
      _receiving = false;
    }
    if (identical(session, _session)) {
      await _cleanup();
      state = state.copyWith(state: LiveVoiceState.disconnected, currentError: error);
    }
  }

  void _handle(LiveServerMessage message) {
    if (message is! LiveServerContent) return;
    if (message.interrupted == true) {
      state = state.copyWith(state: LiveVoiceState.interrupted);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (state.state == LiveVoiceState.interrupted) {
          state = state.copyWith(state: LiveVoiceState.listening);
        }
      });
    }
    for (final part in message.modelTurn?.parts ?? const <Part>[]) {
      if (part is InlineDataPart && part.mimeType.startsWith('audio')) {
        if (state.state != LiveVoiceState.speaking) {
          state = state.copyWith(state: LiveVoiceState.speaking);
        }
        if (_playerReady) {
          final b = part.bytes;
          FlutterPcmSound.feed(PcmArrayInt16(bytes: b.buffer.asByteData(b.offsetInBytes, b.lengthInBytes)));
        }
      } else if (part is TextPart && part.text.trim().isNotEmpty) {
        _appendTranscript(part.text);
      }
    }
    final said = message.outputTranscription;
    if (said?.text != null && said!.text!.trim().isNotEmpty) _appendTranscript(said.text!);
    if (message.turnComplete == true && state.state == LiveVoiceState.speaking) {
      state = state.copyWith(state: LiveVoiceState.listening);
    }
  }

  void _appendTranscript(String text) {
    final updated = List<String>.from(state.transcript)..add('AI: $text');
    state = state.copyWith(transcript: updated);
  }

  /// The user started talking over the model: Live's voice activity
  /// detection interrupts the answer server-side; we just show it.
  void interrupt() {
    state = state.copyWith(state: LiveVoiceState.interrupted);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (state.state == LiveVoiceState.interrupted) {
        state = state.copyWith(state: LiveVoiceState.listening);
      }
    });
  }

  void toggleMute() {
    state = state.copyWith(isMuted: !state.isMuted);
  }

  void disconnect() {
    unawaited(_cleanup());
    state = state.copyWith(state: LiveVoiceState.disconnected);
  }

  Future<void> _cleanup() async {
    final session = _session;
    _session = null;
    await _recorderSubscription?.cancel();
    _recorderSubscription = null;
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    try {
      await session?.close();
    } catch (_) {}
  }
}

final geminiLiveProvider = NotifierProvider<GeminiLiveService, GeminiLiveState>(() {
  return GeminiLiveService();
});
