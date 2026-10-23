import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:record/record.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

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

class GeminiLiveService extends Notifier<GeminiLiveState> {
  WebSocketChannel? _channel;
  final _audioRecorder = AudioRecorder();
  bool _playerReady = false;

  StreamSubscription? _wsSubscription;

  StreamSubscription? _recorderSubscription;

  @override
  GeminiLiveState build() {
    _initAudio();
    return GeminiLiveState();
  }

  Future<void> _initAudio() async {
    // Gemini Live returns 24kHz mono 16-bit PCM.
    await FlutterPcmSound.setup(sampleRate: 24000, channelCount: 1);
    _playerReady = true;
  }

  Future<void> connect() async {
    state = state.copyWith(state: LiveVoiceState.reconnecting, currentError: null);
    try {
      // 1. Get ephemeral token from backend
      final callable = FirebaseFunctions.instance.httpsCallable('generateLiveApiToken');
      final result = await callable.call();
      final token = result.data['token'] as String;

      // 2. Connect to WebSocket
      final wsUrl = Uri.parse('wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained?access_token=$token');
      _channel = WebSocketChannel.connect(wsUrl);

      // Send initial setup message
      _channel!.sink.add(jsonEncode({
        "setup": {
          "model": "models/gemini-2.0-flash-exp"
        }
      }));

      _wsSubscription = _channel!.stream.listen(
        _handleWsMessage,
        onError: _handleWsError,
        onDone: _handleWsDone,
      );

      // 3. Start sending audio
      await _startRecording();
      state = state.copyWith(state: LiveVoiceState.listening);
    } catch (e) {
      if (kDebugMode) print('Gemini Live Connect Error: $e');
      state = state.copyWith(state: LiveVoiceState.disconnected, currentError: 'Connection failed: $e');
    }
  }

  Future<void> _startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      final audioStream = await _audioRecorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));
      _recorderSubscription = audioStream.listen((data) {
        if (state.isMuted) return;
        
        // When user speaks, interrupt the AI
        if (state.state == LiveVoiceState.speaking) {
          interrupt();
        }

        final base64Audio = base64Encode(data);
        if (_channel != null) {
          _channel!.sink.add(jsonEncode({
            "realtimeInput": {
              "mediaChunks": [{
                "mimeType": "audio/pcm;rate=16000",
                "data": base64Audio
              }]
            }
          }));
        }
      });
    } else {
      state = state.copyWith(currentError: 'Microphone permission denied.');
    }
  }

  void _handleWsMessage(dynamic message) {
    if (message is String) {
      try {
        final data = jsonDecode(message);
        
        // Handle server responses
        if (data.containsKey('serverContent')) {
          final serverContent = data['serverContent'];
          if (serverContent.containsKey('modelTurn')) {
            final parts = serverContent['modelTurn']['parts'] as List;
            for (var part in parts) {
              if (part.containsKey('text')) {
                _appendTranscript(part['text']);
              }
              if (part.containsKey('inlineData')) {
                // Play audio data
                final base64Audio = part['inlineData']['data'];
                final bytes = base64Decode(base64Audio);
                if (state.state != LiveVoiceState.speaking) {
                  state = state.copyWith(state: LiveVoiceState.speaking);
                }
                if (_playerReady) {
                  FlutterPcmSound.feed(PcmArrayInt16(bytes: bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes)));
                }
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) print('WS JSON Error: $e');
      }
    }
  }

  void _appendTranscript(String text) {
    final updated = List<String>.from(state.transcript)..add('AI: $text');
    state = state.copyWith(transcript: updated);
  }

  void _handleWsError(dynamic error) {
    if (kDebugMode) print('WS Error: $error');
    state = state.copyWith(state: LiveVoiceState.disconnected, currentError: 'WebSocket error occurred');
    _cleanup();
  }

  void _handleWsDone() {
    state = state.copyWith(state: LiveVoiceState.disconnected);
    _cleanup();
  }

  void interrupt() {
    // Clear playback buffer and notify server of interruption
    // Send a clientContent message to clear the generation
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({
        "clientContent": {
          "turnComplete": true
        }
      }));
    }
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
    _cleanup();
    state = state.copyWith(state: LiveVoiceState.disconnected);
  }

  void _cleanup() {
    _wsSubscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _recorderSubscription?.cancel();
    _audioRecorder.stop();
  }
}

final geminiLiveProvider = NotifierProvider<GeminiLiveService, GeminiLiveState>(() {
  return GeminiLiveService();
});
