import 'dart:async';
import 'dart:typed_data' show BytesBuilder;

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../../feed/services/reel_translation_service.dart' show reelTranslateToProvider;
import '../../../shared/language/language_detector.dart';
import '../providers/active_call_controller.dart';
import '../providers/call_media_service.dart';
import '../providers/webrtc_connection_manager.dart';
import '../../../voice/my_voice_service.dart' show speaksDirectly;
import 'interpreter_protocol.dart';
import 'own_voice_stream.dart';

/// One caption line on the call screen.
class InterpCaption {
  final String from; // uid, or '' for me
  final String original;
  final String translated;
  final DateTime at;
  const InterpCaption(this.from, this.original, this.translated, this.at);
  bool get mine => from.isEmpty;
}

/// Voices the interpreter can speak with (Vertex Live preset voices).
const Map<String, String> kInterpreterVoices = {
  'Aoede': 'Warm',
  'Charon': 'Deep',
  'Puck': 'Bright',
  'Kore': 'Calm',
};

class CallInterpreterState {
  /// My voice is being interpreted for the others.
  final bool active;
  final bool starting;
  final String voice;
  final String myLang;
  final String? error;
  final List<InterpCaption> captions;

  /// Each person's language, from their "hello".
  final Map<String, String> peerLangs;

  /// People whose voice reaches me translated (their original is muted).
  final Set<String> hearingFrom;

  /// I switched translation off for this call (it starts by itself otherwise).
  final bool turnedOff;

  const CallInterpreterState({
    this.active = false,
    this.starting = false,
    this.voice = 'Aoede',
    this.myLang = 'en',
    this.error,
    this.captions = const [],
    this.peerLangs = const {},
    this.hearingFrom = const {},
    this.turnedOff = false,
  });

  CallInterpreterState copyWith({
    bool? active,
    bool? starting,
    String? voice,
    String? myLang,
    String? error,
    bool clearError = false,
    List<InterpCaption>? captions,
    Map<String, String>? peerLangs,
    Set<String>? hearingFrom,
    bool? turnedOff,
  }) =>
      CallInterpreterState(
        active: active ?? this.active,
        starting: starting ?? this.starting,
        voice: voice ?? this.voice,
        myLang: myLang ?? this.myLang,
        error: clearError ? null : (error ?? this.error),
        captions: captions ?? this.captions,
        peerLangs: peerLangs ?? this.peerLangs,
        hearingFrom: hearingFrom ?? this.hearingFrom,
        turnedOff: turnedOff ?? this.turnedOff,
      );
}

final callInterpreterProvider = NotifierProvider<CallInterpreter, CallInterpreterState>(CallInterpreter.new);

/// Interpreter mode (docs/architecture/translated_calls.md, G3).
///
/// Speaker: takes the mic from the call, streams it to Vertex Live (one session
/// per listener language, at most two), and sends the translated voice plus
/// captions to each listener over the call's encrypted data channel. People
/// who share the speaker's language get the original voice the same way.
/// Listener: mutes the speaker's original audio and plays the translation.
/// No key in the app: Vertex is reached through Firebase AI Logic.
class CallInterpreter extends Notifier<CallInterpreterState> {
  static const String _location = 'us-central1';
  static const List<String> _models = [
    'gemini-live-2.5-flash-preview-native-audio-09-2025',
    'gemini-2.0-flash-exp',
    'gemini-2.0-flash',
  ];
  static const int _maxSessions = 2;
  static const int _maxBuffered = 256 * 1024;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _mic;
  StreamSubscription<CallDataMessage>? _inSub;
  StreamSubscription<String>? _openSub;
  final Map<String, LiveSession> _sessions = {}; // target language → session
  final Map<String, StringBuffer> _heard = {}; // original words per session
  final Map<String, StringBuffer> _said = {}; // translated words per session
  bool _playerReady = false;

  // My voice: translated words come back in my own voice from Oneova's voice
  // server (own_voice_stream.dart). Null → Vertex's preset voice (the fallback).
  OwnVoiceStream? _own;
  final Set<String> _textModeLangs = {}; // Live answers in text; my voice speaks it
  final Map<String, StringBuffer> _phrase = {};
  final Map<String, BytesBuilder> _toConvert = {};

  WebRTCConnectionManager get _mesh => ref.read(webrtcConnectionManagerProvider.notifier);

  @override
  CallInterpreterState build() {
    final mesh = ref.read(webrtcConnectionManagerProvider.notifier);
    _inSub = mesh.dataMessages.listen(_onMessage);
    _openSub = mesh.dataChannelOpened.listen(_onOpened);
    ref.listen<ActiveCallState>(activeCallControllerProvider, (prev, next) {
      if (next.phase == CallPhase.ended || next.phase == CallPhase.idle) unawaited(_reset());
    });
    ref.onDispose(() {
      _inSub?.cancel();
      _openSub?.cancel();
      unawaited(_stopSpeaking(restoreMic: false));
      unawaited(_recorder.dispose());
    });
    // My language: Settings → Language (the same choice reels use), else the phone's.
    final lang = _base(ref.read(reelTranslateToProvider));
    ref.listen<String>(reelTranslateToProvider, (_, next) {
      final l = _base(next);
      if (l == state.myLang) return;
      state = state.copyWith(myLang: l);
      for (final uid in _mesh.dataReadyPeers) {
        _mesh.sendData(uid, text: InterpProtocol.hello(l));
      }
      if (state.active) unawaited(_reconcile());
    });
    // Say hello to anyone already connected.
    for (final uid in mesh.dataReadyPeers) {
      mesh.sendData(uid, text: InterpProtocol.hello(lang));
    }
    return CallInterpreterState(myLang: lang);
  }

  static String _base(String code) => code.split(RegExp('[-_]')).first.toLowerCase();

  /// Live translation starts by itself as soon as someone in the call speaks
  /// another language, unless I turned it off for this call.
  void _autoStart() {
    if (state.active || state.starting || state.turnedOff) return;
    final differs = _mesh.dataReadyPeers.any((uid) {
      final l = state.peerLangs[uid];
      return l != null && l != state.myLang;
    });
    if (differs) unawaited(start());
  }

  void setVoice(String v) {
    if (kInterpreterVoices.containsKey(v)) state = state.copyWith(voice: v);
  }

  // ── Listener side ────────────────────────────────────────────────────────

  void _onOpened(String uid) {
    _mesh.sendData(uid, text: InterpProtocol.hello(state.myLang));
    if (state.active) _mesh.sendData(uid, text: InterpProtocol.interp(true));
  }

  void _onMessage(CallDataMessage m) {
    final bytes = m.bytes;
    if (bytes != null) {
      if (!state.hearingFrom.contains(m.from)) return;
      final pcm = InterpProtocol.audioOf(bytes);
      if (pcm != null) unawaited(_play(pcm));
      return;
    }
    final msg = InterpProtocol.decodeText(m.text);
    if (msg == null) return;
    switch (msg['t']) {
      case 'hello':
        final lang = msg['lang'];
        if (lang is String && RegExp(r'^[a-z]{2,3}$').hasMatch(lang)) {
          // First hello from them: answer with mine, in case mine was sent
          // before their side was listening.
          if (!state.peerLangs.containsKey(m.from)) _mesh.sendData(m.from, text: InterpProtocol.hello(state.myLang));
          state = state.copyWith(peerLangs: {...state.peerLangs, m.from: lang});
          if (state.active) {
            unawaited(_reconcile());
          } else {
            _autoStart();
          }
        }
      case 'interp':
        final on = msg['on'] == true;
        final hearing = {...state.hearingFrom};
        on ? hearing.add(m.from) : hearing.remove(m.from);
        state = state.copyWith(hearingFrom: hearing);
        unawaited(_mesh.setRemoteAudioEnabled(m.from, !on));
        if (on) unawaited(_ensurePlayer());
      case 'cap':
        final o = msg['o'], tr = msg['tr'];
        if (o is String && tr is String && (o.isNotEmpty || tr.isNotEmpty)) _addCaption(InterpCaption(m.from, o, tr, DateTime.now()));
    }
  }

  Future<void> _ensurePlayer() async {
    if (_playerReady) return;
    try {
      await FlutterPcmSound.setup(sampleRate: InterpProtocol.playRate, channelCount: 1);
      _playerReady = true;
    } catch (e) {
      debugPrint('[Interpreter] player: $e');
    }
  }

  Future<void> _play(Uint8List pcm) async {
    await _ensurePlayer();
    if (!_playerReady) return;
    FlutterPcmSound.feed(PcmArrayInt16(bytes: ByteData.sublistView(pcm)));
  }

  void _addCaption(InterpCaption c) {
    final list = [...state.captions, c];
    state = state.copyWith(captions: list.length > 6 ? list.sublist(list.length - 6) : list);
  }

  // ── Speaker side ─────────────────────────────────────────────────────────

  /// Starts translating my voice for everyone in the call.
  Future<void> start() async {
    if (state.active || state.starting) return;
    state = state.copyWith(turnedOff: false);
    final ready = _mesh.dataReadyPeers;
    if (ready.isEmpty) {
      state = state.copyWith(error: 'The other person needs the latest Oneova for translated calls.');
      return;
    }
    state = state.copyWith(starting: true, clearError: true);
    try {
      // The call stops sending my original voice; the interpreter takes the mic.
      await _mesh.replaceAudioTrack(null);
      await ref.read(callMediaServiceProvider.notifier).releaseMicForInterpreter();
      final callId = ref.read(activeCallControllerProvider).call?.id;
      if (callId != null) {
        _own = await OwnVoiceStream.open(
          callId: callId,
          onAudio: (lang, pcm) => unawaited(_sendTo(lang, InterpProtocol.frameAudio(pcm))),
          onBroken: () => unawaited(_ownVoiceLost()),
        );
      }
      await _reconcile();
      if (!await _startMic()) throw StateError('mic');
      for (final uid in _mesh.dataReadyPeers) {
        _mesh.sendData(uid, text: InterpProtocol.interp(true));
      }
      state = state.copyWith(active: true, starting: false);
    } catch (e) {
      debugPrint('[Interpreter] start: $e');
      await _stopSpeaking(restoreMic: true);
      state = state.copyWith(starting: false, error: 'Couldn’t start translation. Your normal voice is back on.');
    }
  }

  /// Back to my normal voice for the rest of this call.
  Future<void> stop() async {
    state = state.copyWith(turnedOff: true);
    if (!state.active && !state.starting) return;
    await _stopSpeaking(restoreMic: true);
    state = state.copyWith(active: false, starting: false);
  }

  /// Opens a Live session for each language a listener needs (other than mine).
  Future<void> _reconcile() async {
    final needed = <String>{};
    for (final uid in _mesh.dataReadyPeers) {
      final l = state.peerLangs[uid];
      if (l != null && l != state.myLang) needed.add(l);
    }
    for (final lang in _sessions.keys.where((l) => !needed.contains(l)).toList()) {
      unawaited(_sessions.remove(lang)?.close().catchError((_) {}));
    }
    for (final lang in needed.take(_maxSessions)) {
      if (_sessions.containsKey(lang)) continue;
      final s = await _open(lang);
      if (s != null) {
        _sessions[lang] = s;
        _heard[lang] = StringBuffer();
        _said[lang] = StringBuffer();
        unawaited(_receive(lang, s));
      }
    }
    if (needed.isNotEmpty && _sessions.isEmpty) throw StateError('no live session');
  }

  String _model() {
    try {
      final m = FirebaseRemoteConfig.instance.getString('interpreter_model').trim();
      if (m.isNotEmpty) return m;
    } catch (_) {}
    return _models.first;
  }

  Future<LiveSession?> _open(String lang) async {
    for (final model in {_model(), ..._models}) {
      try {
        final live = FirebaseAI.agentPlatform(location: _location).liveGenerativeModel(
          model: model,
          systemInstruction: Content.system(InterpProtocol.interpreterPrompt(LanguageDetector.nameOf(lang))),
          liveGenerationConfig: LiveGenerationConfig(
            speechConfig: SpeechConfig(voiceName: state.voice),
            // With My voice on, Live gives the translated text and my own voice speaks it.
            responseModalities: [_own != null && speaksDirectly(lang) ? ResponseModalities.text : ResponseModalities.audio],
            inputAudioTranscription: AudioTranscriptionConfig(),
            outputAudioTranscription: AudioTranscriptionConfig(),
          ),
        );
        final session = await live.connect();
        if (_own != null && speaksDirectly(lang)) {
          _textModeLangs.add(lang);
        } else {
          _textModeLangs.remove(lang);
        }
        return session;
      } catch (e) {
        debugPrint('[Interpreter] $model → $lang failed: $e');
      }
    }
    return null;
  }

  Future<void> _receive(String lang, LiveSession s) async {
    try {
      await for (final r in s.receive()) {
        final msg = r.message;
        if (msg is! LiveServerContent) continue;
        for (final part in msg.modelTurn?.parts ?? const <Part>[]) {
          if (part is TextPart && _textModeLangs.contains(lang)) {
            // Say each finished sentence in my own voice as soon as it's ready.
            _said[lang]?.write(part.text);
            final buf = _phrase.putIfAbsent(lang, StringBuffer.new)..write(part.text);
            final t = buf.toString();
            final cut = t.lastIndexOf(RegExp(r'[.!?。！？؟]\s'));
            if (cut > 0) {
              _own?.say(t.substring(0, cut + 1).trim(), lang);
              buf
                ..clear()
                ..write(t.substring(cut + 1));
            }
          } else if (part is InlineDataPart && part.mimeType.startsWith('audio')) {
            if (_own != null) {
              // Another language: convert the whole turn into my voice.
              _toConvert.putIfAbsent(lang, BytesBuilder.new).add(part.bytes);
            } else {
              await _sendTo(lang, InterpProtocol.frameAudio(part.bytes));
            }
          }
        }
        if (msg.turnComplete == true) {
          final rest = _phrase.remove(lang)?.toString().trim() ?? '';
          if (rest.isNotEmpty) _own?.say(rest, lang);
          final audio = _toConvert.remove(lang)?.takeBytes();
          if (audio != null && audio.isNotEmpty) _own?.convert(audio, lang);
        }
        final heard = msg.inputTranscription?.text;
        if (heard != null && heard.isNotEmpty) _heard[lang]?.write(heard);
        final said = msg.outputTranscription?.text;
        if (said != null && said.isNotEmpty) _said[lang]?.write(said);
        if (msg.turnComplete == true) _flushCaption(lang);
      }
    } catch (e) {
      debugPrint('[Interpreter] receive $lang: $e');
    }
    if (identical(_sessions[lang], s)) _sessions.remove(lang);
  }

  /// Audio for the people who speak [lang]. Drops audio rather than build up delay.
  Future<void> _sendTo(String lang, List<Uint8List> frames) async {
    for (final uid in _mesh.dataReadyPeers) {
      if (state.peerLangs[uid] != lang) continue;
      if (await _mesh.bufferedAmount(uid) > _maxBuffered) continue;
      for (final f in frames) {
        _mesh.sendData(uid, bytes: f);
      }
    }
  }

  void _flushCaption(String lang) {
    final o = _heard[lang]?.toString().trim() ?? '';
    final tr = _said[lang]?.toString().trim() ?? '';
    _heard[lang]?.clear();
    _said[lang]?.clear();
    if (o.isEmpty && tr.isEmpty) return;
    for (final uid in _mesh.dataReadyPeers) {
      if (state.peerLangs[uid] == lang) _mesh.sendData(uid, text: InterpProtocol.caption(o, tr, lang));
    }
    _addCaption(InterpCaption('', o, tr, DateTime.now()));
  }

  Future<bool> _startMic() async {
    if (!await _recorder.hasPermission()) return false;
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      // The translation of the other side plays out loud: cancel its echo.
      echoCancel: true,
      noiseSuppress: true,
      autoGain: true,
      androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceCommunication),
    ));
    _mic = stream.listen(_onMic);
    return true;
  }

  void _onMic(Uint8List pcm) {
    if (ref.read(callMediaServiceProvider).isAudioMuted) return;
    for (final s in _sessions.values) {
      unawaited(s.sendAudioRealtime(InlineDataPart('audio/pcm', pcm)).catchError((_) {}));
    }
    // People who share my language hear my own voice through the same channel.
    final same = [for (final uid in _mesh.dataReadyPeers) if (state.peerLangs[uid] == state.myLang) uid];
    if (same.isEmpty) return;
    final frames = InterpProtocol.frameAudio(InterpProtocol.resample16kTo24k(pcm));
    for (final uid in same) {
      for (final f in frames) {
        _mesh.sendData(uid, bytes: f);
      }
    }
  }

  /// The voice server went away mid-call: back to the preset voice at once.
  Future<void> _ownVoiceLost() async {
    _own = null;
    _phrase.clear();
    _toConvert.clear();
    if (!state.active) return;
    for (final s in _sessions.values) {
      unawaited(s.close().catchError((_) {}));
    }
    _sessions.clear();
    _textModeLangs.clear();
    try {
      await _reconcile();
    } catch (e) {
      debugPrint('[Interpreter] fallback: $e');
    }
  }

  Future<void> _stopSpeaking({required bool restoreMic}) async {
    await _mic?.cancel();
    _mic = null;
    final own = _own;
    _own = null;
    _textModeLangs.clear();
    _phrase.clear();
    _toConvert.clear();
    unawaited(own?.close());
    try {
      await _recorder.stop();
    } catch (_) {}
    for (final s in _sessions.values) {
      unawaited(s.close().catchError((_) {}));
    }
    _sessions.clear();
    _heard.clear();
    _said.clear();
    try {
      for (final uid in _mesh.dataReadyPeers) {
        _mesh.sendData(uid, text: InterpProtocol.interp(false));
      }
      if (restoreMic) {
        final track = await ref.read(callMediaServiceProvider.notifier).restoreMicAfterInterpreter();
        await _mesh.replaceAudioTrack(track);
      }
    } catch (e) {
      debugPrint('[Interpreter] stop: $e');
    }
  }

  Future<void> _reset() async {
    if (state.active || state.starting) await _stopSpeaking(restoreMic: false);
    for (final uid in state.hearingFrom) {
      unawaited(_mesh.setRemoteAudioEnabled(uid, true));
    }
    state = CallInterpreterState(voice: state.voice, myLang: state.myLang);
  }
}
