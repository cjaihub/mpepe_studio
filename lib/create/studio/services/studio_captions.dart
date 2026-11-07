import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:oneova_media_engine/oneova_media_engine.dart';

import '../models/studio_project.dart';
import 'studio_renderer.dart';
import 'studio_text_templates.dart';

/// A language offered for captions and translation.
class StudioLanguage {
  final String code;
  final String name;
  final String region;

  /// Fewer speech/text resources: results may need checking.
  final bool limited;
  const StudioLanguage(this.code, this.name, this.region, {this.limited = false});

  /// A language the user typed that isn't in the list.
  factory StudioLanguage.custom(String name) => StudioLanguage(name.trim(), name.trim(), 'Other', limited: true);
}

/// How well the model handles a language, as it rated itself.
enum StudioLanguageSupport {
  good,
  limited,
  unsupported;

  static StudioLanguageSupport parse(Object? v) =>
      values.firstWhere((e) => e.name == v, orElse: () => StudioLanguageSupport.limited);
}

/// Auto-caption result.
class StudioCaptionResult {
  final List<StudioText> captions;
  final String language;
  final String languageName;
  final StudioLanguageSupport support;

  /// Captions the model was unsure about.
  final int lowConfidence;
  const StudioCaptionResult(this.captions, this.language, this.languageName, this.support, this.lowConfidence);
}

/// Thrown with a message that can be shown to the user as is.
class StudioAiException implements Exception {
  final String message;
  const StudioAiException(this.message);
  @override
  String toString() => message;
}

/// Auto captions (speech to text with word timing) and translation through
/// the `studioCaptions` / `studioTranslate` functions (Gemini on Vertex AI,
/// OpenRouter fallback for translation). The app never holds an AI key.
class StudioCaptionService {
  StudioCaptionService._();

  /// Speech is sent in pieces of this length so long videos work too.
  static const _chunkMs = 4 * 60 * 1000;

  /// Worldwide languages, local and regional ones included. Auto-detect
  /// handles any language the model hears; users can also type one in.
  static const languages = <StudioLanguage>[
    StudioLanguage('sw', 'Swahili', 'Africa'),
    StudioLanguage('am', 'Amharic', 'Africa'),
    StudioLanguage('yo', 'Yoruba', 'Africa'),
    StudioLanguage('ha', 'Hausa', 'Africa'),
    StudioLanguage('ig', 'Igbo', 'Africa'),
    StudioLanguage('zu', 'Zulu', 'Africa'),
    StudioLanguage('xh', 'Xhosa', 'Africa'),
    StudioLanguage('af', 'Afrikaans', 'Africa'),
    StudioLanguage('so', 'Somali', 'Africa'),
    StudioLanguage('rw', 'Kinyarwanda', 'Africa'),
    StudioLanguage('ar', 'Arabic', 'Africa'),
    StudioLanguage('fr', 'French', 'Africa'),
    StudioLanguage('pt', 'Portuguese', 'Africa'),
    StudioLanguage('en', 'English', 'Africa'),
    StudioLanguage('pcm', 'Nigerian Pidgin', 'Africa', limited: true),
    StudioLanguage('ki', 'Kikuyu', 'Africa', limited: true),
    StudioLanguage('luo', 'Luo (Dholuo)', 'Africa', limited: true),
    StudioLanguage('lg', 'Luganda', 'Africa', limited: true),
    StudioLanguage('kam', 'Kamba', 'Africa', limited: true),
    StudioLanguage('mer', 'Meru', 'Africa', limited: true),
    StudioLanguage('guz', 'Kisii (Ekegusii)', 'Africa', limited: true),
    StudioLanguage('luy', 'Luhya', 'Africa', limited: true),
    StudioLanguage('kln', 'Kalenjin', 'Africa', limited: true),
    StudioLanguage('mas', 'Maasai', 'Africa', limited: true),
    StudioLanguage('nyn', 'Runyankole', 'Africa', limited: true),
    StudioLanguage('rn', 'Kirundi', 'Africa', limited: true),
    StudioLanguage('ln', 'Lingala', 'Africa', limited: true),
    StudioLanguage('kg', 'Kikongo', 'Africa', limited: true),
    StudioLanguage('lua', 'Tshiluba', 'Africa', limited: true),
    StudioLanguage('wo', 'Wolof', 'Africa', limited: true),
    StudioLanguage('ff', 'Fula (Fulfulde)', 'Africa', limited: true),
    StudioLanguage('bm', 'Bambara', 'Africa', limited: true),
    StudioLanguage('ak', 'Twi (Akan)', 'Africa', limited: true),
    StudioLanguage('ee', 'Ewe', 'Africa', limited: true),
    StudioLanguage('gaa', 'Ga', 'Africa', limited: true),
    StudioLanguage('fon', 'Fon', 'Africa', limited: true),
    StudioLanguage('om', 'Oromo', 'Africa', limited: true),
    StudioLanguage('ti', 'Tigrinya', 'Africa', limited: true),
    StudioLanguage('mg', 'Malagasy', 'Africa', limited: true),
    StudioLanguage('ny', 'Chichewa', 'Africa', limited: true),
    StudioLanguage('sn', 'Shona', 'Africa', limited: true),
    StudioLanguage('nd', 'Ndebele', 'Africa', limited: true),
    StudioLanguage('st', 'Sesotho', 'Africa', limited: true),
    StudioLanguage('tn', 'Setswana', 'Africa', limited: true),
    StudioLanguage('ts', 'Xitsonga', 'Africa', limited: true),
    StudioLanguage('ve', 'Tshivenda', 'Africa', limited: true),
    StudioLanguage('ss', 'Swati', 'Africa', limited: true),
    StudioLanguage('bem', 'Bemba', 'Africa', limited: true),
    StudioLanguage('kr', 'Kanuri', 'Africa', limited: true),
    StudioLanguage('efi', 'Efik', 'Africa', limited: true),
    StudioLanguage('tiv', 'Tiv', 'Africa', limited: true),
    StudioLanguage('ber', 'Tamazight (Berber)', 'Africa', limited: true),
    StudioLanguage('zh', 'Chinese (Mandarin)', 'Asia'),
    StudioLanguage('yue', 'Cantonese', 'Asia'),
    StudioLanguage('hi', 'Hindi', 'Asia'),
    StudioLanguage('bn', 'Bengali', 'Asia'),
    StudioLanguage('ur', 'Urdu', 'Asia'),
    StudioLanguage('pa', 'Punjabi', 'Asia'),
    StudioLanguage('ta', 'Tamil', 'Asia'),
    StudioLanguage('te', 'Telugu', 'Asia'),
    StudioLanguage('mr', 'Marathi', 'Asia'),
    StudioLanguage('gu', 'Gujarati', 'Asia'),
    StudioLanguage('kn', 'Kannada', 'Asia'),
    StudioLanguage('ml', 'Malayalam', 'Asia'),
    StudioLanguage('ja', 'Japanese', 'Asia'),
    StudioLanguage('ko', 'Korean', 'Asia'),
    StudioLanguage('id', 'Indonesian', 'Asia'),
    StudioLanguage('ms', 'Malay', 'Asia'),
    StudioLanguage('vi', 'Vietnamese', 'Asia'),
    StudioLanguage('th', 'Thai', 'Asia'),
    StudioLanguage('tl', 'Filipino (Tagalog)', 'Asia'),
    StudioLanguage('fa', 'Persian', 'Asia'),
    StudioLanguage('tr', 'Turkish', 'Asia'),
    StudioLanguage('he', 'Hebrew', 'Asia'),
    StudioLanguage('ne', 'Nepali', 'Asia', limited: true),
    StudioLanguage('si', 'Sinhala', 'Asia', limited: true),
    StudioLanguage('my', 'Burmese', 'Asia', limited: true),
    StudioLanguage('km', 'Khmer', 'Asia', limited: true),
    StudioLanguage('lo', 'Lao', 'Asia', limited: true),
    StudioLanguage('jv', 'Javanese', 'Asia', limited: true),
    StudioLanguage('su', 'Sundanese', 'Asia', limited: true),
    StudioLanguage('ceb', 'Cebuano', 'Asia', limited: true),
    StudioLanguage('ilo', 'Ilocano', 'Asia', limited: true),
    StudioLanguage('ps', 'Pashto', 'Asia', limited: true),
    StudioLanguage('ku', 'Kurdish', 'Asia', limited: true),
    StudioLanguage('kk', 'Kazakh', 'Asia', limited: true),
    StudioLanguage('uz', 'Uzbek', 'Asia', limited: true),
    StudioLanguage('ky', 'Kyrgyz', 'Asia', limited: true),
    StudioLanguage('tg', 'Tajik', 'Asia', limited: true),
    StudioLanguage('mn', 'Mongolian', 'Asia', limited: true),
    StudioLanguage('ka', 'Georgian', 'Asia', limited: true),
    StudioLanguage('hy', 'Armenian', 'Asia', limited: true),
    StudioLanguage('az', 'Azerbaijani', 'Asia', limited: true),
    StudioLanguage('or', 'Odia', 'Asia', limited: true),
    StudioLanguage('as', 'Assamese', 'Asia', limited: true),
    StudioLanguage('bho', 'Bhojpuri', 'Asia', limited: true),
    StudioLanguage('sd', 'Sindhi', 'Asia', limited: true),
    StudioLanguage('es', 'Spanish', 'Europe'),
    StudioLanguage('de', 'German', 'Europe'),
    StudioLanguage('it', 'Italian', 'Europe'),
    StudioLanguage('nl', 'Dutch', 'Europe'),
    StudioLanguage('ru', 'Russian', 'Europe'),
    StudioLanguage('uk', 'Ukrainian', 'Europe'),
    StudioLanguage('pl', 'Polish', 'Europe'),
    StudioLanguage('ro', 'Romanian', 'Europe'),
    StudioLanguage('el', 'Greek', 'Europe'),
    StudioLanguage('sv', 'Swedish', 'Europe'),
    StudioLanguage('no', 'Norwegian', 'Europe'),
    StudioLanguage('da', 'Danish', 'Europe'),
    StudioLanguage('fi', 'Finnish', 'Europe'),
    StudioLanguage('cs', 'Czech', 'Europe'),
    StudioLanguage('hu', 'Hungarian', 'Europe'),
    StudioLanguage('bg', 'Bulgarian', 'Europe'),
    StudioLanguage('sr', 'Serbian', 'Europe'),
    StudioLanguage('hr', 'Croatian', 'Europe'),
    StudioLanguage('ca', 'Catalan', 'Europe', limited: true),
    StudioLanguage('eu', 'Basque', 'Europe', limited: true),
    StudioLanguage('gl', 'Galician', 'Europe', limited: true),
    StudioLanguage('cy', 'Welsh', 'Europe', limited: true),
    StudioLanguage('ga', 'Irish', 'Europe', limited: true),
    StudioLanguage('gd', 'Scottish Gaelic', 'Europe', limited: true),
    StudioLanguage('is', 'Icelandic', 'Europe', limited: true),
    StudioLanguage('lt', 'Lithuanian', 'Europe', limited: true),
    StudioLanguage('lv', 'Latvian', 'Europe', limited: true),
    StudioLanguage('et', 'Estonian', 'Europe', limited: true),
    StudioLanguage('sk', 'Slovak', 'Europe', limited: true),
    StudioLanguage('sl', 'Slovenian', 'Europe', limited: true),
    StudioLanguage('mk', 'Macedonian', 'Europe', limited: true),
    StudioLanguage('sq', 'Albanian', 'Europe', limited: true),
    StudioLanguage('be', 'Belarusian', 'Europe', limited: true),
    StudioLanguage('mt', 'Maltese', 'Europe', limited: true),
    StudioLanguage('lb', 'Luxembourgish', 'Europe', limited: true),
    StudioLanguage('bs', 'Bosnian', 'Europe', limited: true),
    StudioLanguage('pt-BR', 'Portuguese (Brazil)', 'Americas & Pacific'),
    StudioLanguage('es-419', 'Spanish (Latin America)', 'Americas & Pacific'),
    StudioLanguage('fr-CA', 'French (Canada)', 'Americas & Pacific'),
    StudioLanguage('ht', 'Haitian Creole', 'Americas & Pacific', limited: true),
    StudioLanguage('qu', 'Quechua', 'Americas & Pacific', limited: true),
    StudioLanguage('gn', 'Guarani', 'Americas & Pacific', limited: true),
    StudioLanguage('ay', 'Aymara', 'Americas & Pacific', limited: true),
    StudioLanguage('nah', 'Nahuatl', 'Americas & Pacific', limited: true),
    StudioLanguage('yua', 'Yucatec Maya', 'Americas & Pacific', limited: true),
    StudioLanguage('jam', 'Jamaican Patois', 'Americas & Pacific', limited: true),
    StudioLanguage('mi', 'Maori', 'Americas & Pacific', limited: true),
    StudioLanguage('sm', 'Samoan', 'Americas & Pacific', limited: true),
    StudioLanguage('to', 'Tongan', 'Americas & Pacific', limited: true),
    StudioLanguage('fj', 'Fijian', 'Americas & Pacific', limited: true),
    StudioLanguage('haw', 'Hawaiian', 'Americas & Pacific', limited: true),
    StudioLanguage('tpi', 'Tok Pisin', 'Americas & Pacific', limited: true),
  ];

  static StudioLanguage? find(String? code) {
    if (code == null || code.isEmpty) return null;
    final c = code.toLowerCase();
    return languages.where((l) => l.code.toLowerCase() == c).firstOrNull ??
        languages.where((l) => l.code == c.split('-').first).firstOrNull ??
        languages.where((l) => l.name.toLowerCase() == c).firstOrNull;
  }

  static String languageName(String? code) {
    if (code == null || code.isEmpty || code == 'und') return 'Unknown';
    return find(code)?.name ?? code;
  }

  /// Message for a language the model can't handle well, or null.
  static String? supportNotice(String name, StudioLanguageSupport support, {required bool captions}) => switch (support) {
        StudioLanguageSupport.good => null,
        StudioLanguageSupport.limited => captions
            ? "$name isn't fully supported yet. Some words may be wrong, so check the captions before posting."
            : "$name isn't fully supported yet. Check the translation before posting.",
        StudioLanguageSupport.unsupported => captions
            ? "$name can't be captioned reliably yet, so no captions were added. You can type them with Enter captions."
            : "$name can't be translated reliably yet, so the text was left unchanged.",
      };

  static FirebaseFunctions get _fns => FirebaseFunctions.instanceFor(region: 'us-central1');

  static String _friendly(FirebaseFunctionsException e, String fallback) {
    if (e.code == 'not-found') return '$fallback is not switched on for this app yet.';
    if (e.code == 'unauthenticated') return 'Sign in to use $fallback.';
    return e.message ?? fallback;
  }

  /// Clips covering output time [a, b) of [p], trimmed to that range.
  static List<StudioClip> _clipsInRange(StudioProject p, int a, int b) {
    final out = <StudioClip>[];
    var start = 0;
    for (final c in p.clips) {
      final end = start + c.outDurationMs;
      final s = math.max(a, start), e = math.min(b, end);
      if (e > s) {
        if (c.isImage) {
          out.add(c.copyWith(imageDurationMs: e - s));
        } else {
          out.add(c.copyWith(startMs: c.sourceMsAt(s - start), endMs: c.sourceMsAt(e - start)));
        }
      }
      start = end;
    }
    return out;
  }

  /// Transcribes the project's original sound into word-timed captions
  /// styled with [templateId] (a Captions template). [language] is a code
  /// or 'auto'. Returns the captions and the detected language.
  static Future<StudioCaptionResult> autoCaptions(
    StudioProject project, {
    String language = 'auto',
    String templateId = 'ca_karaoke',
    void Function(double progress, String stage)? onProgress,
  }) async {
    if (!project.clips.any((c) => !c.isImage && c.hasAudio)) {
      throw const StudioAiException('None of the clips have sound to caption.');
    }
    final total = project.durationMs;
    final chunks = <(int, int)>[];
    for (var a = 0; a < total; a += _chunkMs) {
      chunks.add((a, math.min(total, a + _chunkMs)));
    }
    final tpl = StudioTextTemplates.byId(templateId) ?? StudioTextTemplates.inCategory('Captions').first;
    final captions = <StudioText>[];
    var detected = language;
    var detectedName = '';
    var support = StudioLanguageSupport.good;
    var lowConfidence = 0;
    for (var i = 0; i < chunks.length; i++) {
      final (a, b) = chunks[i];
      final part = project.copyWith(clips: _clipsInRange(project, a, b));
      if (!part.clips.any((c) => !c.isImage && c.hasAudio)) continue;
      onProgress?.call(i / chunks.length, 'Preparing audio');
      String path;
      try {
        path = await StudioRenderer.exportSpeechAudio(part);
      } on MediaEngineException catch (e) {
        throw StudioAiException('Could not read the sound: ${e.message}');
      }
      final bytes = await File(path).readAsBytes();
      try {
        await File(path).delete();
      } catch (_) {}
      onProgress?.call((i + 0.4) / chunks.length, 'Listening');
      Map<String, dynamic> res;
      try {
        final call = _fns.httpsCallable('studioCaptions', options: HttpsCallableOptions(timeout: const Duration(minutes: 5)));
        final r = await call.call<Map<String, dynamic>>({
          'audio': base64Encode(bytes),
          'mimeType': 'audio/mp4',
          'language': language,
          'offsetMs': a,
          'durationMs': b - a,
        });
        res = Map<String, dynamic>.from(r.data);
      } on FirebaseFunctionsException catch (e) {
        throw StudioAiException(_friendly(e, 'Auto captions'));
      }
      if (detected == 'auto') detected = res['language'] as String? ?? 'auto';
      if (detectedName.isEmpty) detectedName = res['languageName'] as String? ?? '';
      final partSupport = StudioLanguageSupport.parse(res['support']);
      if (partSupport.index > support.index) support = partSupport;
      for (final s in (res['segments'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(s as Map);
        final text = (m['text'] as String? ?? '').trim();
        if (text.isEmpty) continue;
        final words = [
          for (final w in (m['words'] as List? ?? const []))
            StudioWord.fromJson(Map<String, dynamic>.from(w as Map)),
        ];
        final startMs = (m['startMs'] as num?)?.toInt() ?? 0;
        final endMs = math.min(total, (m['endMs'] as num?)?.toInt() ?? startMs + 1500);
        if (endMs <= startMs) continue;
        if (((m['confidence'] as num?)?.toDouble() ?? 1) < 0.5) lowConfidence++;
        final base = StudioText.create(text: text, startMs: startMs, endMs: endMs, isCaption: true, words: words, lang: res['language'] as String?);
        captions.add(tpl.applyTo(base));
      }
      onProgress?.call((i + 1) / chunks.length, 'Listening');
    }
    debugPrint('[StudioCaptions] ${captions.length} captions, language $detected ($support)');
    // A language listed as limited never reports "good" to the user.
    if (support == StudioLanguageSupport.good && find(detected)?.limited == true) support = StudioLanguageSupport.limited;
    final name = find(detected)?.name ?? (detectedName.isNotEmpty ? detectedName : languageName(detected));
    return StudioCaptionResult(captions, detected, name, support, lowConfidence);
  }

  /// Translates [texts] into [target]; same order and length as [texts].
  /// [target] is a code or a typed language name. Returns the translations
  /// and how well the model handles that language.
  static Future<(List<String>, StudioLanguageSupport)> translate(List<String> texts, String target, {String? source}) async {
    if (texts.isEmpty) return (const <String>[], StudioLanguageSupport.good);
    final out = <String>[];
    var support = StudioLanguageSupport.good;
    // Batches keep each request well under the server limits.
    for (var i = 0; i < texts.length; i += 150) {
      final batch = texts.sublist(i, math.min(texts.length, i + 150));
      try {
        final call = _fns.httpsCallable('studioTranslate', options: HttpsCallableOptions(timeout: const Duration(minutes: 2)));
        final r = await call.call<Map<String, dynamic>>({'texts': batch, 'target': target, 'source': ?source});
        final data = Map<String, dynamic>.from(r.data);
        final part = StudioLanguageSupport.parse(data['support']);
        if (part.index > support.index) support = part;
        final list = (data['translations'] as List? ?? const []).map((e) => '$e').toList();
        if (list.length != batch.length) throw const StudioAiException('The translation came back incomplete. Try again.');
        out.addAll(list);
      } on FirebaseFunctionsException catch (e) {
        throw StudioAiException(_friendly(e, 'Translation'));
      }
    }
    return (out, support);
  }
}
