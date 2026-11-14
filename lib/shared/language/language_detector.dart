import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Finds the language of a piece of text on the phone (ML Kit Language ID,
/// offline, about 100 languages). Nothing leaves the phone to detect it.
class LanguageDetector {
  LanguageDetector._();
  static final LanguageDetector instance = LanguageDetector._();

  static const String _readsKey = 'languages_i_read';

  LanguageIdentifier? _id;
  final Map<String, String?> _cache = {};
  Set<String>? _reads;

  bool get _supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Base code of the phone language, e.g. "sw" for sw-KE.
  static String phoneLanguage() => WidgetsBinding.instance.platformDispatcher.locale.languageCode.toLowerCase();

  /// Languages the user reads without translation: the phone language plus any
  /// they added ("I read these").
  Future<Set<String>> readsLanguages() async {
    if (_reads != null) return _reads!;
    final p = await SharedPreferences.getInstance();
    _reads = {phoneLanguage(), ...?p.getStringList(_readsKey)};
    return _reads!;
  }

  Future<void> addReadLanguage(String code) async {
    final p = await SharedPreferences.getInstance();
    final set = {...await readsLanguages(), code.toLowerCase()};
    _reads = set;
    await p.setStringList(_readsKey, set.where((c) => c != phoneLanguage()).toList());
  }

  /// Base language code ("sw", "fr", "yo") or null when unsure (short text,
  /// emoji, links, mixed).
  Future<String?> detect(String text) async {
    final t = _clean(text);
    if (t.length < 12 || !_supported) return null;
    final key = t.length > 200 ? t.substring(0, 200) : t;
    if (_cache.containsKey(key)) return _cache[key];
    String? out;
    try {
      _id ??= LanguageIdentifier(confidenceThreshold: 0.6);
      final code = await _id!.identifyLanguage(key);
      out = code == 'und' ? null : code.split('-').first.toLowerCase();
    } catch (e) {
      debugPrint('[LanguageDetector] $e');
    }
    if (_cache.length > 500) _cache.remove(_cache.keys.first);
    _cache[key] = out;
    return out;
  }

  /// The message's language when it's one the user doesn't read, else null.
  Future<String?> foreignLanguageOf(String text) async {
    final code = await detect(text);
    if (code == null) return null;
    return (await readsLanguages()).contains(code) ? null : code;
  }

  static String _clean(String s) => s
      .replaceAll(RegExp(r'https?://\S+'), ' ')
      .replaceAll(RegExp(r'[@#]\w+'), ' ')
      .replaceAll(RegExp(r'[^\p{L}\p{M}\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// English name for a language code.
  static String nameOf(String code) => _names[code] ?? code.toUpperCase();

  static const Map<String, String> _names = {
    'af': 'Afrikaans', 'am': 'Amharic', 'ar': 'Arabic', 'bn': 'Bengali', 'de': 'German', 'el': 'Greek',
    'en': 'English', 'es': 'Spanish', 'fa': 'Persian', 'fr': 'French', 'ha': 'Hausa', 'he': 'Hebrew',
    'hi': 'Hindi', 'id': 'Indonesian', 'ig': 'Igbo', 'it': 'Italian', 'ja': 'Japanese', 'ko': 'Korean',
    'mg': 'Malagasy', 'ms': 'Malay', 'nl': 'Dutch', 'ny': 'Chichewa', 'pl': 'Polish', 'pt': 'Portuguese',
    'ru': 'Russian', 'rw': 'Kinyarwanda', 'sn': 'Shona', 'so': 'Somali', 'st': 'Sesotho', 'sv': 'Swedish',
    'sw': 'Swahili', 'ta': 'Tamil', 'th': 'Thai', 'tr': 'Turkish', 'uk': 'Ukrainian', 'ur': 'Urdu',
    'vi': 'Vietnamese', 'xh': 'Xhosa', 'yo': 'Yoruba', 'zh': 'Chinese', 'zu': 'Zulu',
  };

  Future<void> dispose() async {
    await _id?.close();
    _id = null;
  }
}
