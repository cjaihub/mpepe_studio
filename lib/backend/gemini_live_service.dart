// ignore_for_file: avoid_print
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Current documentation maps for Gemini Live states
enum GeminiLiveState {
  disconnected,
  reconnecting,
  listening,
  thinking,
  speaking,
  interrupted,
}

class GeminiLiveConfig {
  final String voiceSelection; 
  final String language;
  final double playbackSpeed;
  final String? audioDeviceId;

  const GeminiLiveConfig({
    this.voiceSelection = 'Aoede', // Default Gemini Live voice
    this.language = 'en-US',
    this.playbackSpeed = 1.0,
    this.audioDeviceId,
  });

  GeminiLiveConfig copyWith({
    String? voiceSelection,
    String? language,
    double? playbackSpeed,
    String? audioDeviceId,
  }) {
    return GeminiLiveConfig(
      voiceSelection: voiceSelection ?? this.voiceSelection,
      language: language ?? this.language,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      audioDeviceId: audioDeviceId ?? this.audioDeviceId,
    );
  }
}

class GeminiLiveSessionState {
  final GeminiLiveState state;
  final GeminiLiveConfig config;
  final List<String> transcript;
  final bool isMuted;
  
  GeminiLiveSessionState({
    this.state = GeminiLiveState.disconnected,
    this.config = const GeminiLiveConfig(),
    this.transcript = const [],
    this.isMuted = false,
  });
  
  GeminiLiveSessionState copyWith({
    GeminiLiveState? state,
    GeminiLiveConfig? config,
    List<String>? transcript,
    bool? isMuted,
  }) {
    return GeminiLiveSessionState(
      state: state ?? this.state,
      config: config ?? this.config,
      transcript: transcript ?? this.transcript,
      isMuted: isMuted ?? this.isMuted,
    );
  }
}

class GeminiLiveService extends Notifier<GeminiLiveSessionState> {
  // Underlying connection placeholders
  // StreamSubscription? _micSubscription;
  // StreamSubscription? _webSocketSubscription;
  
  @override
  GeminiLiveSessionState build() {
    return GeminiLiveSessionState();
  }

  /// Initiates the Live Voice session using an ephemeral token.
  Future<void> startVoiceMode() async {
    state = state.copyWith(state: GeminiLiveState.reconnecting);
    
    try {
      // 1. Fetch ephemeral auth token from the project's secure gateway.
      // This strictly avoids placing permanent API credentials in the client.
      final ephemeralToken = await _fetchEphemeralToken();

      // 2. Initialize WebSocket to Gemini Live endpoint
      _connectToGeminiLive(ephemeralToken);

      // 3. Initialize audio stream (using small audio chunks)
      _startAudioCapture();

      state = state.copyWith(state: GeminiLiveState.listening);
    } catch (e) {
      state = state.copyWith(state: GeminiLiveState.disconnected);
      print('Failed to start Gemini Live: \$e');
    }
  }

  Future<void> stop() async {
    // Clean up streams and WS
    state = state.copyWith(state: GeminiLiveState.disconnected);
  }

  void mute() {
    state = state.copyWith(isMuted: true);
    // Logic to pause audio capture stream
  }

  void resume() {
    if (state.state == GeminiLiveState.interrupted) {
      state = state.copyWith(state: GeminiLiveState.listening);
    }
    state = state.copyWith(isMuted: false);
    // Logic to resume audio capture stream
  }

  /// Handles natural interruption. When the user speaks over the model,
  /// the incoming audio buffer is immediately cleared.
  void interruptAi() {
    if (state.state == GeminiLiveState.speaking) {
      state = state.copyWith(state: GeminiLiveState.interrupted);
      // Logic to flush playback buffer immediately and signal client-side interruption
      _sendInterruptSignal();
    }
  }

  void updateConfig(GeminiLiveConfig newConfig) {
    state = state.copyWith(config: newConfig);
    // If connected, send config update frame to Gemini API
  }

  Future<String> _fetchEphemeralToken() async {
    // Implementation for hitting the backend gateway to get a short-lived token
    await Future.delayed(const Duration(milliseconds: 500));
    return 'ephemeral_token_xyz';
  }

  void _connectToGeminiLive(String token) {
    // Setup WSS connection
    // On message received, handle:
    // - Transcript segments (add to state.transcript)
    // - Audio output chunks (feed to playback engine)
    // - Turn complete signals (switch back to listening)
  }

  void _startAudioCapture() {
    // Implementation using sound_stream or similar.
    // Send small chunks (~20-100ms) over the WebSocket to minimize latency.
    // Listen for local VAD (Voice Activity Detection) to trigger automatic `interruptAi()` if the model is speaking.
  }

  void _sendInterruptSignal() {
    // Send a client control frame to cancel the current generation
  }
}

final geminiLiveProvider = NotifierProvider<GeminiLiveService, GeminiLiveSessionState>(() {
  return GeminiLiveService();
});
