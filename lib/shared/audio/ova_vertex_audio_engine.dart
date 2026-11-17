import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../../desktop_agent/desktop_firebase_rest_client.dart';

/// Shared Vertex AI Native Audio Speech Engine (`gemini-live-2.5-flash-preview-native-audio-09-2025`
/// + Vertex `gemini-2.5-flash-preview-tts` via `chatAssist`).
///
/// Replaces all legacy `FlutterTts` robotic OS voices across Ova Assistant,
/// Live Copilot, 3D Stage Live, AI Lab, Chat Assist, and Desktop Agent.
class OvaVertexAudioEngine {
  OvaVertexAudioEngine._();
  static final OvaVertexAudioEngine instance = OvaVertexAudioEngine._();

  static const String vertexLocation = 'us-central1';
  static const String liveAudioModel =
      'gemini-live-2.5-flash-preview-native-audio-09-2025';
  static const List<String> allowedVoices = [
    'Aoede',
    'Puck',
    'Kore',
    'Charon',
    'Fenrir',
    'Zephyr',
  ];

  final ValueNotifier<bool> isSpeaking = ValueNotifier<bool>(false);
  final Map<String, Uint8List> _wavCache = <String, Uint8List>{};

  Player? _mediaPlayer;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;
  Completer<void>? _activeUtterance;
  LiveSession? _oneShotLive;
  bool _pcmInitialized = false;
  int _generation = 0;

  static bool get _supportsStreamingPcm =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  /// Removes markdown symbols, links and technical punctuation so spoken audio
  /// flows like natural human speech.
  static String cleanForSpeech(String raw) {
    final cleaned = raw
        .replaceAllMapped(
          RegExp(r'\[(.*?)\]\(.*?\)'),
          (m) => m.group(1) ?? '',
        )
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'[*#_`>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.length > 1400 ? '${cleaned.substring(0, 1400).trim()}…' : cleaned;
  }

  Future<void> _ensurePcmPlayer() async {
    if (_pcmInitialized || !_supportsStreamingPcm) return;
    try {
      await FlutterPcmSound.setup(sampleRate: 24000, channelCount: 1);
      await FlutterPcmSound.setLogLevel(LogLevel.none);
      _pcmInitialized = true;
    } catch (e) {
      debugPrint('[OvaVertexAudio] PCM setup notice: $e');
    }
  }

  Player _ensureMediaPlayer() {
    if (_mediaPlayer != null) return _mediaPlayer!;
    final p = Player();
    _mediaPlayer = p;
    _completedSub = p.stream.completed.listen((done) {
      if (done && isSpeaking.value) {
        _completeActive();
      }
    });
    _playingSub = p.stream.playing.listen((playing) {
      if (playing && !isSpeaking.value) {
        isSpeaking.value = true;
      }
    });
    return p;
  }

  void _completeActive() {
    isSpeaking.value = false;
    final c = _activeUtterance;
    _activeUtterance = null;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
  }

  /// Speaks [text] using Vertex AI Native Audio (`gemini-live-2.5-flash-preview-native-audio-09-2025`
  /// live stream first, or Vertex `gemini-2.5-flash-preview-tts` / user's own
  /// enrolled voice via `chatAssist` when desktop/offline-WS fallback is needed).
  Future<void> speak(
    String text, {
    String voiceName = 'Aoede',
    String languageCode = 'en',
    String style = 'warm natural conversational human voice',
    bool useOwnVoice = false,
    VoidCallback? onStart,
    VoidCallback? onComplete,
  }) async {
    final clean = cleanForSpeech(text);
    if (clean.isEmpty) {
      onComplete?.call();
      return;
    }

    await stop();
    final gen = ++_generation;
    final safeVoice =
        allowedVoices.contains(voiceName) ? voiceName : 'Aoede';

    final completer = Completer<void>();
    _activeUtterance = completer;
    isSpeaking.value = true;
    onStart?.call();

    final cacheKey = '$safeVoice|$languageCode|$useOwnVoice|$clean';
    final cachedWav = _wavCache[cacheKey];
    if (cachedWav != null) {
      await _playWavBytes(cachedWav, gen);
      onComplete?.call();
      return;
    }

    bool played = false;
    if (!useOwnVoice &&
        _supportsStreamingPcm &&
        Firebase.apps.isNotEmpty &&
        FirebaseAuth.instance.currentUser != null) {
      played = await _speakViaVertexLiveStream(
        clean,
        voiceName: safeVoice,
        languageCode: languageCode,
        style: style,
        gen: gen,
      );
    }

    if (!played && gen == _generation) {
      final wavBytes = await _fetchVertexTtsWav(
        clean,
        voiceName: safeVoice,
        languageCode: languageCode,
        style: style,
        useOwnVoice: useOwnVoice,
      );
      if (wavBytes != null && wavBytes.isNotEmpty && gen == _generation) {
        _rememberWav(cacheKey, wavBytes);
        await _playWavBytes(wavBytes, gen);
        played = true;
      }
    }

    if (gen == _generation && isSpeaking.value) {
      _completeActive();
    }
    onComplete?.call();
  }

  Future<bool> _speakViaVertexLiveStream(
    String text, {
    required String voiceName,
    required String languageCode,
    required String style,
    required int gen,
  }) async {
    LiveSession? session;
    try {
      await _ensurePcmPlayer();
      if (!_pcmInitialized || gen != _generation) return false;

      final liveModel =
          FirebaseAI.agentPlatform(location: vertexLocation).liveGenerativeModel(
        model: liveAudioModel,
        systemInstruction: Content.system(
          'You are a natural human voice speaker for Oneova in language "$languageCode". '
          'Speak ONLY the exact text the user sends you, verbatim, with $style and natural human cadence. '
          'Never add commentary, greetings, or explanations.',
        ),
        liveGenerationConfig: LiveGenerationConfig(
          speechConfig: SpeechConfig(voiceName: voiceName),
          responseModalities: [ResponseModalities.audio],
        ),
      );

      session = await liveModel.connect().timeout(const Duration(seconds: 7));
      if (gen != _generation) {
        unawaited(session.close().catchError((_) {}));
        return false;
      }
      _oneShotLive = session;

      await session.sendTextRealtime(text);
      bool receivedAudio = false;
      await for (final resp in session.receive()) {
        if (gen != _generation) break;
        final msg = resp.message;
        if (msg is LiveServerContent) {
          final parts = msg.modelTurn?.parts ?? const <Part>[];
          for (final p in parts) {
            if (p is InlineDataPart && p.mimeType.startsWith('audio/pcm')) {
              receivedAudio = true;
              FlutterPcmSound.feed(
                PcmArrayInt16(
                  bytes: p.bytes.buffer.asByteData(
                    p.bytes.offsetInBytes,
                    p.bytes.lengthInBytes,
                  ),
                ),
              );
            }
          }
          if (msg.turnComplete == true) {
            // Allow final PCM buffer (~280ms) to drain smoothly before closing.
            await Future<void>.delayed(const Duration(milliseconds: 280));
            break;
          }
        }
      }
      return receivedAudio;
    } catch (e) {
      debugPrint('[OvaVertexAudio] Live stream fallback notice: $e');
      return false;
    } finally {
      if (identical(_oneShotLive, session)) {
        _oneShotLive = null;
      }
      unawaited(session?.close().catchError((_) {}));
    }
  }

  Future<Uint8List?> _fetchVertexTtsWav(
    String text, {
    required String voiceName,
    required String languageCode,
    required String style,
    required bool useOwnVoice,
  }) async {
    final payload = <String, dynamic>{
      'op': 'speakText',
      'text': text,
      'target': languageCode,
      'voiceName': voiceName,
      'style': style,
      'useOwnVoice': useOwnVoice,
    };

    try {
      Map<String, dynamic>? map;
      final isDesktop =
          !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
      if (isDesktop &&
          (Firebase.apps.isEmpty || FirebaseAuth.instance.currentUser == null)) {
        map = await DesktopFirebaseRestClient.instance.callCallable(
          'chatAssist',
          payload,
          timeout: const Duration(seconds: 25),
        );
      } else if (Firebase.apps.isNotEmpty) {
        final callable = FirebaseFunctions.instanceFor(region: vertexLocation)
            .httpsCallable(
          'chatAssist',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
        );
        final res = await callable.call<dynamic>(payload);
        if (res.data is Map) {
          map = Map<String, dynamic>.from(res.data as Map);
        }
      }
      final b64 = map?['audioBase64']?.toString() ?? '';
      if (b64.isEmpty) return null;
      return Uint8List.fromList(base64Decode(b64));
    } catch (e) {
      debugPrint('[OvaVertexAudio] Vertex TTS fetch notice: $e');
      return null;
    }
  }

  Future<void> _playWavBytes(Uint8List wavBytes, int gen) async {
    if (gen != _generation) return;
    try {
      final dir = await getTemporaryDirectory();
      final f = File(
        '${dir.path}${Platform.pathSeparator}ova_vertex_${gen}_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      await f.writeAsBytes(wavBytes, flush: true);
      if (gen != _generation) {
        unawaited(f.delete().catchError((_) => f));
        return;
      }
      final p = _ensureMediaPlayer();
      await p.open(Media(f.path), play: true);
      await _activeUtterance?.future.timeout(
        const Duration(seconds: 35),
        onTimeout: () {},
      );
      unawaited(f.delete().catchError((_) => f));
    } catch (e) {
      debugPrint('[OvaVertexAudio] Media playback notice: $e');
    }
  }

  void _rememberWav(String key, Uint8List bytes) {
    if (_wavCache.length >= 24) {
      _wavCache.remove(_wavCache.keys.first);
    }
    _wavCache[key] = bytes;
  }

  /// Wraps raw 24 kHz mono PCM16 bytes in a standard RIFF WAV container.
  static Uint8List pcm16MonoToWav(Uint8List pcm, {int sampleRate = 24000}) {
    final byteRate = sampleRate * 2;
    final out = Uint8List(44 + pcm.length);
    final bd = ByteData.sublistView(out);
    out.setAll(0, ascii.encode('RIFF'));
    bd.setUint32(4, 36 + pcm.length, Endian.little);
    out.setAll(8, ascii.encode('WAVE'));
    out.setAll(12, ascii.encode('fmt '));
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);
    bd.setUint16(22, 1, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, byteRate, Endian.little);
    bd.setUint16(32, 2, Endian.little);
    bd.setUint16(34, 16, Endian.little);
    out.setAll(36, ascii.encode('data'));
    bd.setUint32(40, pcm.length, Endian.little);
    out.setRange(44, out.length, pcm);
    return out;
  }

  Future<void> stop() async {
    _generation++;
    final session = _oneShotLive;
    _oneShotLive = null;
    if (session != null) {
      unawaited(session.close().catchError((_) {}));
    }
    try {
      await _mediaPlayer?.stop();
    } catch (_) {}
    _completeActive();
  }

  Future<void> dispose() async {
    await stop();
    await _completedSub?.cancel();
    await _playingSub?.cancel();
    await _mediaPlayer?.dispose();
    _mediaPlayer = null;
  }
}
