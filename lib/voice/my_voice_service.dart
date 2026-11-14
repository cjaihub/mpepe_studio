import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';

/// "My voice" (functions/src/voice/voice.ts): the person's own voice for
/// translated voice notes and calls, built on Oneova's own GPU server. The
/// server only ever speaks in the signed-in person's own voice.
class MyVoiceStatus {
  final bool available; // the voice server is switched on
  final String status; // none | recording | building | ready | needs_retake
  final double seconds;
  final List<String> prompts;
  final List<({String clip, List<String> problems})> retake;
  const MyVoiceStatus({required this.available, required this.status, required this.seconds, required this.prompts, required this.retake});
  bool get ready => status == 'ready';
}

/// Languages the voice server speaks directly in your voice (others are
/// converted from another voice). Same list as services/voice/voice/logic.py.
const kCloneLanguages = {
  'ar', 'da', 'de', 'el', 'en', 'es', 'fi', 'fr', 'he', 'hi', 'it', 'ja', 'ko', 'ms', 'nl', 'no', 'pl', 'pt', 'ru', 'sv', 'sw', 'tr', 'zh',
};

bool speaksDirectly(String lang) => kCloneLanguages.contains(lang.split(RegExp('[-_]')).first.toLowerCase());

class MyVoiceService {
  MyVoiceService._();
  static final MyVoiceService instance = MyVoiceService._();
  final FirebaseFunctions _fn = FirebaseFunctions.instance;

  Future<Map<String, dynamic>> _call(String name, [Map<String, Object?> data = const {}]) async {
    final r = await _fn.httpsCallable(name, options: HttpsCallableOptions(timeout: const Duration(minutes: 5))).call<Object?>(data);
    return Map<String, dynamic>.from((r.data as Map?) ?? const {});
  }

  static List<({String clip, List<String> problems})> _retake(Object? v) => [
        for (final r in (v as List? ?? const []))
          if (r is Map) (clip: '${r['clip']}', problems: [for (final p in (r['problems'] as List? ?? const [])) '$p']),
      ];

  Future<MyVoiceStatus> status() async {
    final r = await _call('voiceStatus');
    final p = r['profile'] as Map?;
    return MyVoiceStatus(
      available: r['available'] == true,
      status: (p?['status'] as String?) ?? 'none',
      seconds: ((p?['seconds'] as num?) ?? 0).toDouble(),
      prompts: [for (final s in (r['prompts'] as List? ?? const [])) '$s'],
      retake: _retake(p?['retake']),
    );
  }

  /// Records consent on the server; returns where the clips go.
  Future<({String path, String consentPath})> start() async {
    final r = await _call('voiceEnrollStart', {'consent': true});
    return (path: r['path'] as String, consentPath: r['consentPath'] as String);
  }

  Future<({bool ready, double seconds, List<({String clip, List<String> problems})> retake})> finish() async {
    final r = await _call('voiceEnrollFinish');
    return (ready: r['ready'] == true, seconds: ((r['seconds'] as num?) ?? 0).toDouble(), retake: _retake(r['retake']));
  }

  Future<void> disable() => _call('voiceDisable');

  /// 24 kHz mono PCM16 of [text] in my own voice.
  Future<Uint8List> speakOwn(String text, String language) async {
    final r = await _call('voiceSpeakOwn', {'text': text, 'language': language});
    return base64Decode(r['audioBase64'] as String);
  }

  /// Converts speech (e.g. a preset voice in Yoruba) into my own voice.
  Future<Uint8List> convertOwn(Uint8List pcm16, int sampleRate) async {
    final r = await _call('voiceConvertOwn', {'audioBase64': base64Encode(pcm16), 'sampleRate': sampleRate});
    return base64Decode(r['audioBase64'] as String);
  }

  Future<({String url, String token})> streamToken(String callId) async {
    final r = await _call('voiceStreamToken', {'callId': callId});
    return (url: r['url'] as String, token: r['token'] as String);
  }

  /// Plain words for the server's problem codes.
  static String problemText(String code) => switch (code) {
        'too_quiet' => 'Speak a little louder',
        'too_loud' => 'Hold the phone a bit further away',
        'noisy' => 'Find a quieter place',
        'too_short' => 'Read the whole sentence',
        _ => 'Try once more',
      };
}
