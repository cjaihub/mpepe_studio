import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:image/image.dart' as img;
import 'package:record/record.dart';

import '../../shared/audio/mic_coordinator.dart';
import 'computer_action_log.dart';
import 'controller_link.dart';

enum OvaLivePhase { off, connecting, listening, thinking, speaking, acting, error }

@immutable
class OvaLiveLine {
  const OvaLiveLine(this.fromUser, this.text);
  final bool fromUser;
  final String text;
}

@immutable
class OvaComputerLiveState {
  const OvaComputerLiveState({
    this.phase = OvaLivePhase.off,
    this.lines = const [],
    this.lastAction,
    this.error,
    this.muted = false,
    this.seeing = false,
  });

  final OvaLivePhase phase;
  final List<OvaLiveLine> lines;
  final String? lastAction;
  final String? error;
  final bool muted;

  /// Screen frames are flowing to the model.
  final bool seeing;

  bool get active => phase != OvaLivePhase.off && phase != OvaLivePhase.error;

  OvaComputerLiveState copyWith({
    OvaLivePhase? phase,
    List<OvaLiveLine>? lines,
    String? lastAction,
    String? error,
    bool clearError = false,
    bool? muted,
    bool? seeing,
  }) =>
      OvaComputerLiveState(
        phase: phase ?? this.phase,
        lines: lines ?? this.lines,
        lastAction: lastAction ?? this.lastAction,
        error: clearError ? null : (error ?? this.error),
        muted: muted ?? this.muted,
        seeing: seeing ?? this.seeing,
      );
}

/// Ova Live for the computer: a Gemini Live (Vertex AI) voice session that
/// watches the computer's screen (≈1 frame/s, downscaled JPEG from the live
/// WebRTC stream) and operates mouse and keyboard through tool calls, while
/// talking with the user in real time. Every action is logged for the
/// activity sidebar and the training dataset. It never handles passwords.
class OvaComputerLive extends Notifier<OvaComputerLiveState> {
  static const String location = 'us-central1';
  static const List<String> fallbackModels = [
    'gemini-live-2.5-flash-preview-native-audio-09-2025',
    'gemini-2.0-flash-exp',
    'gemini-2.0-flash',
  ];
  static const Duration _frameEvery = Duration(milliseconds: 1100);
  static const int _frameWidth = 1024;

  LiveSession? _session;
  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _mic;
  MicLease? _lease;
  Timer? _frameTimer;
  bool _frameBusy = false;
  bool _playerReady = false;

  ControllerLink? _link;
  MediaStreamTrack? Function()? _videoTrack;
  ComputerActionLog? _log;
  String _partialUser = '';
  String _partialAi = '';

  @override
  OvaComputerLiveState build() {
    ref.onDispose(() => unawaited(_cleanup()));
    return const OvaComputerLiveState();
  }

  String _model() {
    try {
      final m = FirebaseRemoteConfig.instance.getString('computer_live_model').trim();
      if (m.isNotEmpty) return m;
    } catch (_) {}
    return fallbackModels.first;
  }

  static final _tools = Tool.functionDeclarations([
    FunctionDeclaration(
      'click',
      'Click on the computer screen at a point. Coordinates are on a 0-1000 grid of the screenshot (x left→right, y top→bottom).',
      parameters: {
        'x': Schema.integer(description: '0-1000 horizontal position'),
        'y': Schema.integer(description: '0-1000 vertical position'),
        'button': Schema.enumString(
          enumValues: ['left', 'right', 'double'],
          description: 'left (default), right, or double click',
        ),
      },
      optionalParameters: ['button'],
    ),
    FunctionDeclaration(
      'move_pointer',
      'Move the mouse pointer to a point (0-1000 grid) without clicking, e.g. to hover.',
      parameters: {'x': Schema.integer(), 'y': Schema.integer()},
    ),
    FunctionDeclaration(
      'drag',
      'Press at one point and drag to another (0-1000 grid), e.g. to move a window or select.',
      parameters: {
        'from_x': Schema.integer(),
        'from_y': Schema.integer(),
        'to_x': Schema.integer(),
        'to_y': Schema.integer(),
      },
    ),
    FunctionDeclaration(
      'scroll',
      'Scroll the content under the pointer.',
      parameters: {
        'direction': Schema.enumString(enumValues: ['up', 'down', 'left', 'right']),
        'amount': Schema.integer(description: '1 (a little) to 10 (a lot)'),
      },
      optionalParameters: ['amount'],
    ),
    FunctionDeclaration(
      'type_text',
      'Type text into the focused field on the computer.',
      parameters: {
        'text': Schema.string(),
        'press_enter': Schema.boolean(description: 'Press Return afterwards'),
      },
      optionalParameters: ['press_enter'],
    ),
    FunctionDeclaration(
      'key_combo',
      'Press a keyboard shortcut, e.g. "cmd+c", "cmd+tab", "cmd+shift+4", "cmd+w".',
      parameters: {'combo': Schema.string()},
    ),
    FunctionDeclaration(
      'press_key',
      'Press a single key.',
      parameters: {
        'key': Schema.enumString(enumValues: [
          'enter', 'tab', 'esc', 'backspace', 'delete', 'space', 'up', 'down', 'left', 'right',
        ]),
      },
    ),
    FunctionDeclaration(
      'open_app',
      'Open an application or file by name using Spotlight.',
      parameters: {'name': Schema.string()},
    ),
    FunctionDeclaration(
      'media',
      'Control media playback on the computer.',
      parameters: {
        'key': Schema.enumString(enumValues: ['play', 'next', 'prev', 'mute', 'vol_up', 'vol_down']),
      },
    ),
    FunctionDeclaration(
      'set_volume',
      'Set the computer output volume.',
      parameters: {'level': Schema.integer(description: '0-100')},
    ),
    FunctionDeclaration(
      'wake_screen',
      'Wake the computer display if it is dark or asleep.',
      parameters: {},
    ),
  ]);

  static const _system = '''
You are Ova, Oneova's live computer co-pilot. You see the user's computer
screen as a stream of screenshots and hear the user. You can operate the
computer with the provided tools (mouse, keyboard, media, volume).

Rules:
- Speak briefly and naturally, like a helpful person sitting next to them.
- Before acting, say in a few words what you'll do; then call the tool.
- Coordinates are on a 0-1000 grid of the latest screenshot.
- After an action, look at the next screenshot to confirm it worked; adjust
  if it didn't. Do one step at a time.
- Never type passwords, payment details or other secrets. If a login or
  lock screen needs a password, ask the user to tap Unlock on their phone.
- Ask before anything destructive (deleting, sending, buying, closing
  unsaved work).
''';

  /// Starts the live session. [videoTrack] supplies the computer's screen
  /// track (null while it isn't streaming).
  Future<void> start({
    required ControllerLink link,
    required MediaStreamTrack? Function() videoTrack,
  }) async {
    if (state.active) return;
    _link = link;
    _videoTrack = videoTrack;
    _log = ref.read(computerActionLogProvider.notifier);
    state = state.copyWith(phase: OvaLivePhase.connecting, clearError: true);

    if (!_playerReady) {
      try {
        await FlutterPcmSound.setup(sampleRate: 24000, channelCount: 1);
        _playerReady = true;
      } catch (_) {}
    }

    final candidates = {_model(), ...fallbackModels}.toList();
    Object? lastErr;
    for (final candidate in candidates) {
      try {
        final model = FirebaseAI.agentPlatform(location: location).liveGenerativeModel(
          model: candidate,
          systemInstruction: Content.system(_system),
          tools: [_tools],
          liveGenerationConfig: LiveGenerationConfig(
            speechConfig: SpeechConfig(voiceName: 'Aoede'),
            responseModalities: [ResponseModalities.audio],
            inputAudioTranscription: AudioTranscriptionConfig(),
            outputAudioTranscription: AudioTranscriptionConfig(),
            contextWindowCompression: ContextWindowCompressionConfig(
              slidingWindow: SlidingWindow(),
            ),
          ),
        );
        _session = await model.connect();
        unawaited(_receive(_session!));
        final got = await MicCoordinator.instance.acquire(
          MicUser.aiLive,
          onPreempted: () async {
            _lease = null;
            await stop();
          },
        );
        if (got is MicBusy) {
          await _cleanup();
          state = state.copyWith(phase: OvaLivePhase.error, error: got.message);
          return;
        }
        _lease = got as MicLease;
        await _startMic();
        _frameTimer = Timer.periodic(_frameEvery, (_) => unawaited(_sendFrame()));
        unawaited(_sendFrame());
        state = state.copyWith(phase: OvaLivePhase.listening);
        _log?.record(ActionSource.ai, 'connect', params: {'mode': 'ova_live', 'model': candidate});
        return;
      } catch (e) {
        lastErr = e;
        if (kDebugMode) debugPrint('[OvaComputerLive] $candidate failed: $e');
        await _cleanup(keepState: true);
      }
    }
    if (kDebugMode) debugPrint('[OvaComputerLive] connect error: $lastErr');
    state = state.copyWith(
      phase: OvaLivePhase.error,
      error: 'Ova Live could not start. Check your connection and try again.',
    );
  }

  Future<void> stop() async {
    await _cleanup();
    state = state.copyWith(phase: OvaLivePhase.off, seeing: false);
  }

  void toggleMute() => state = state.copyWith(muted: !state.muted);

  /// Sends a typed instruction instead of speaking.
  Future<void> say(String text) async {
    final t = text.trim();
    if (t.isEmpty || _session == null) return;
    _addLine(true, t);
    _log?.record(ActionSource.voice, 'user_said', params: {'text': t});
    try {
      await _session!.sendTextRealtime(t);
    } catch (_) {}
  }

  Future<void> _startMic() async {
    if (!await _recorder.hasPermission()) {
      state = state.copyWith(error: 'Microphone permission is needed for Ova Live.');
      return;
    }
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      noiseSuppress: true,
      echoCancel: true,
      autoGain: true,
      androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceCommunication),
    ));
    _mic = stream.listen((data) {
      final s = _session;
      if (s == null || state.muted) return;
      unawaited(s.sendAudioRealtime(InlineDataPart('audio/pcm', data)).catchError((_) {}));
    });
  }

  /// Grabs the current screen frame, downsizes it off the UI thread and
  /// streams it to the model. Skips if the previous frame is still encoding,
  /// so a slow phone never queues frames up.
  Future<void> _sendFrame() async {
    final s = _session;
    final track = _videoTrack?.call();
    if (s == null || track == null || _frameBusy) {
      if (track == null && state.seeing) state = state.copyWith(seeing: false);
      return;
    }
    _frameBusy = true;
    try {
      final raw = await track.captureFrame();
      final jpeg = await compute(_downscaleJpeg, (raw.asUint8List(), _frameWidth));
      if (jpeg != null && _session != null) {
        await s.sendVideoRealtime(InlineDataPart('image/jpeg', jpeg));
        if (!state.seeing) state = state.copyWith(seeing: true);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[OvaComputerLive] frame notice: $e');
    } finally {
      _frameBusy = false;
    }
  }

  Future<void> _receive(LiveSession session) async {
    String? error;
    try {
      await for (final response in session.receive()) {
        await _handle(response.message);
      }
    } catch (e) {
      error = 'Ova Live disconnected.';
      if (kDebugMode) debugPrint('[OvaComputerLive] receive: $e');
    }
    if (identical(session, _session)) {
      await _cleanup();
      state = state.copyWith(
        phase: error == null ? OvaLivePhase.off : OvaLivePhase.error,
        error: error,
        seeing: false,
      );
    }
  }

  Future<void> _handle(LiveServerMessage message) async {
    if (message is LiveServerToolCall) {
      final calls = message.functionCalls ?? const <FunctionCall>[];
      final responses = <FunctionResponse>[];
      state = state.copyWith(phase: OvaLivePhase.acting);
      for (final call in calls) {
        final result = await _run(call.name, call.args);
        responses.add(FunctionResponse(call.name, result, id: call.id));
      }
      try {
        await _session?.sendToolResponse(responses);
      } catch (_) {}
      // Let the model see the result quickly.
      Future<void>.delayed(const Duration(milliseconds: 450), () => unawaited(_sendFrame()));
      state = state.copyWith(phase: OvaLivePhase.thinking);
      return;
    }
    if (message is! LiveServerContent) return;

    final heard = message.inputTranscription?.text;
    if (heard != null && heard.trim().isNotEmpty) {
      _partialUser += heard;
      if (state.phase == OvaLivePhase.listening) {
        state = state.copyWith(phase: OvaLivePhase.thinking);
      }
    }
    for (final part in message.modelTurn?.parts ?? const <Part>[]) {
      if (part is InlineDataPart && part.mimeType.startsWith('audio')) {
        _flushUser();
        if (state.phase != OvaLivePhase.speaking) {
          state = state.copyWith(phase: OvaLivePhase.speaking);
        }
        if (_playerReady) {
          final b = part.bytes;
          FlutterPcmSound.feed(
            PcmArrayInt16(bytes: b.buffer.asByteData(b.offsetInBytes, b.lengthInBytes)),
          );
        }
      }
    }
    final said = message.outputTranscription?.text;
    if (said != null && said.trim().isNotEmpty) {
      _flushUser();
      _partialAi += said;
    }
    if (message.turnComplete == true || message.interrupted == true) {
      _flushUser();
      final ai = _partialAi.trim();
      _partialAi = '';
      if (ai.isNotEmpty) {
        _addLine(false, ai);
        _log?.record(ActionSource.ai, 'ai_said', params: {'text': ai});
      }
      state = state.copyWith(phase: OvaLivePhase.listening);
    }
  }

  void _flushUser() {
    final u = _partialUser.trim();
    _partialUser = '';
    if (u.isEmpty) return;
    _addLine(true, u);
    _log?.record(ActionSource.voice, 'user_said', params: {'text': u});
  }

  void _addLine(bool user, String text) {
    final next = [...state.lines, OvaLiveLine(user, text)];
    state = state.copyWith(lines: next.length > 40 ? next.sublist(next.length - 40) : next);
  }

  /// Runs one tool call on the computer. Grid coords (0-1000) → 0..1.
  Future<Map<String, Object?>> _run(String name, Map<String, Object?> args) async {
    final link = _link;
    if (link == null) return {'error': 'computer not connected'};
    link.source = ActionSource.ai;
    double g(String k) => (((args[k] as num?)?.toDouble() ?? 500) / 1000).clamp(0.0, 1.0);
    bool ok = true;
    String label = name;
    switch (name) {
      case 'click':
        final button = (args['button'] as String?) ?? 'left';
        final x = g('x'), y = g('y');
        ok = switch (button) {
          'right' => link.rightClickAt(x, y),
          'double' => link.doubleClickAt(x, y),
          _ => link.clickAt(x, y),
        };
        label = '${button == 'left' ? 'Click' : button == 'right' ? 'Right-click' : 'Double-click'} '
            '(${args['x']}, ${args['y']})';
      case 'move_pointer':
        link.moveTo(g('x'), g('y'), log: true);
        label = 'Pointer (${args['x']}, ${args['y']})';
      case 'drag':
        link.pressAt(g('from_x'), g('from_y'));
        await Future<void>.delayed(const Duration(milliseconds: 60));
        const steps = 12;
        for (var i = 1; i <= steps; i++) {
          final t = i / steps;
          link.moveTo(
            g('from_x') + (g('to_x') - g('from_x')) * t,
            g('from_y') + (g('to_y') - g('from_y')) * t,
          );
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
        ok = link.leftUp();
        label = 'Drag';
      case 'scroll':
        final dir = (args['direction'] as String?) ?? 'down';
        final amount = ((args['amount'] as num?)?.toInt() ?? 3).clamp(1, 10);
        final px = amount * 120.0;
        // Scroll "down" means reveal content below: content moves up (−dy).
        final dx = dir == 'left' ? px : dir == 'right' ? -px : 0.0;
        final dy = dir == 'up' ? px : dir == 'down' ? -px : 0.0;
        for (var i = 0; i < 6; i++) {
          link.scroll(dx / 6, dy / 6);
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
        label = 'Scroll $dir';
      case 'type_text':
        final text = (args['text'] as String?) ?? '';
        ok = link.typeText(text, pressEnter: args['press_enter'] == true);
        label = 'Typed text';
      case 'key_combo':
        ok = link.keyCombo((args['combo'] as String?) ?? '');
        label = 'Keys ${args['combo']}';
      case 'press_key':
        ok = link.pressKey((args['key'] as String?) ?? 'enter');
        label = 'Key ${args['key']}';
      case 'open_app':
        final app = (args['name'] as String?) ?? '';
        link.keyCombo('cmd+space');
        await Future<void>.delayed(const Duration(milliseconds: 450));
        ok = link.typeText(app, pressEnter: true);
        label = 'Open $app';
      case 'media':
        ok = link.media((args['key'] as String?) ?? 'play');
        label = 'Media ${args['key']}';
      case 'set_volume':
        ok = link.setVolume(((args['level'] as num?)?.toInt() ?? 50).clamp(0, 100));
        label = 'Volume ${args['level']}';
      case 'wake_screen':
        ok = link.wake();
        label = 'Wake screen';
      default:
        return {'error': 'unknown tool $name'};
    }
    state = state.copyWith(lastAction: label);
    return ok ? {'result': 'done'} : {'error': 'computer link is not open'};
  }

  Future<void> _cleanup({bool keepState = false}) async {
    _frameTimer?.cancel();
    _frameTimer = null;
    final session = _session;
    _session = null;
    final lease = _lease;
    _lease = null;
    await _mic?.cancel();
    _mic = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    unawaited(lease?.release());
    try {
      await session?.close();
    } catch (_) {}
    _partialUser = '';
    _partialAi = '';
  }
}

/// Decode → resize to [width] → JPEG q70, in a background isolate.
Uint8List? _downscaleJpeg((Uint8List, int) input) {
  final (bytes, width) = input;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = decoded.width > width ? img.copyResize(decoded, width: width) : decoded;
  return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
}

final ovaComputerLiveProvider =
    NotifierProvider<OvaComputerLive, OvaComputerLiveState>(OvaComputerLive.new);
