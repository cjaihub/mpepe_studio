import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../audio/ova_vertex_audio_engine.dart';

/// Metadata for a supported language.
class LanguageInfo {
  final String code;
  final String name;
  final String nativeName;
  final String flag;
  final bool isRtl;

  const LanguageInfo({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.flag,
    this.isRtl = false,
  });

  String get displayName => '$flag $name ($nativeName)';
  String get shortLabel => '$flag $name';

  Map<String, dynamic> toMap() => {
        'code': code,
        'name': name,
        'nativeName': nativeName,
        'flag': flag,
        'isRtl': isRtl,
      };
}

/// Result of auto-detecting language on a piece of text.
class DetectedLanguage {
  final LanguageInfo language;
  final double confidence;
  final String originalText;

  const DetectedLanguage({
    required this.language,
    required this.confidence,
    required this.originalText,
  });

  String get code => language.code;
  String get name => language.name;
  String get flag => language.flag;
}

/// Oneova Universal Language Detector & Translation Service
///
/// Features:
/// - Fast on-device language detection for 17+ global & African languages
/// - Script analysis (Arabic, Devanagari, CJK, Cyrillic, Ge'ez/Amharic)
/// - Stopword and n-gram scoring for Latin-script languages (Swahili, French, Spanish, Yoruba, Zulu, etc.)
/// - Cloud-backed translation via Firebase Functions `chatAssist` with resilient offline phrase fallback
/// - AI Text Polish & Tone styling (Studio, Concise, Friendly, Professional)
/// - Native Human Voice via Vertex AI ([OvaVertexAudioEngine])
class OneovaLanguageService {
  OneovaLanguageService._();
  static final OneovaLanguageService instance = OneovaLanguageService._();

  bool _isTtsSpeaking = false;

  bool get isTtsSpeaking => _isTtsSpeaking || OvaVertexAudioEngine.instance.isSpeaking.value;

  // ───────────────────────────────────────────────────────────────────────────
  // Supported Languages Catalog
  // ───────────────────────────────────────────────────────────────────────────
  static const List<LanguageInfo> supportedLanguages = [
    LanguageInfo(code: 'en', name: 'English', nativeName: 'English', flag: '🇺🇸'),
    LanguageInfo(code: 'sw', name: 'Swahili', nativeName: 'Kiswahili', flag: '🇰🇪'),
    LanguageInfo(code: 'fr', name: 'French', nativeName: 'Français', flag: '🇫🇷'),
    LanguageInfo(code: 'es', name: 'Spanish', nativeName: 'Español', flag: '🇪🇸'),
    LanguageInfo(code: 'ar', name: 'Arabic', nativeName: 'العربية', flag: '🇸🇦', isRtl: true),
    LanguageInfo(code: 'pt', name: 'Portuguese', nativeName: 'Português', flag: '🇧🇷'),
    LanguageInfo(code: 'yo', name: 'Yoruba', nativeName: 'Èdè Yorùbá', flag: '🇳🇬'),
    LanguageInfo(code: 'ig', name: 'Igbo', nativeName: 'Asụsụ Igbo', flag: '🇳🇬'),
    LanguageInfo(code: 'ha', name: 'Hausa', nativeName: 'Harshen Hausa', flag: '🇳🇬'),
    LanguageInfo(code: 'zu', name: 'Zulu', nativeName: 'isiZulu', flag: '🇿🇦'),
    LanguageInfo(code: 'am', name: 'Amharic', nativeName: 'አማርኛ', flag: '🇪🇹'),
    LanguageInfo(code: 'de', name: 'German', nativeName: 'Deutsch', flag: '🇩🇪'),
    LanguageInfo(code: 'hi', name: 'Hindi', nativeName: 'हिन्दी', flag: '🇮🇳'),
    LanguageInfo(code: 'zh', name: 'Chinese', nativeName: '中文', flag: '🇨🇳'),
    LanguageInfo(code: 'ja', name: 'Japanese', nativeName: '日本語', flag: '🇯🇵'),
    LanguageInfo(code: 'it', name: 'Italian', nativeName: 'Italiano', flag: '🇮🇹'),
    LanguageInfo(code: 'ru', name: 'Russian', nativeName: 'Русский', flag: '🇷🇺'),
  ];

  static LanguageInfo get defaultLanguage => supportedLanguages[0]; // English

  static LanguageInfo findLanguage(String code) {
    final clean = code.trim().toLowerCase().split(RegExp('[-_]')).first;
    return supportedLanguages.firstWhere(
      (l) => l.code.toLowerCase() == clean,
      orElse: () => defaultLanguage,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Stopword Dictionaries for Fast On-Device Language Detection
  // ───────────────────────────────────────────────────────────────────────────
  static const Set<String> _swahiliWords = {
    'habari', 'jambo', 'asante', 'karibu', 'sana', 'kwa', 'katika', 'yako', 'yangu',
    'wewe', 'mimi', 'yeye', 'wao', 'sisi', 'ndio', 'hapana', 'tafadhali', 'nzuri',
    'mambo', 'vipi', 'hujambo', 'sijambo', 'kazi', 'rafiki', 'nini', 'gani', 'wapi',
    'lini', 'ngapi', 'hapa', 'pale', 'kubwa', 'ndogo', 'sasa', 'baadaye',
    'leo', 'kesho', 'jana', 'kitu', 'watu', 'mtu', 'kitabu', 'mji', 'nchi', 'chakula',
  };

  static const Set<String> _frenchWords = {
    'bonjour', 'merci', 'avec', 'pour', 'dans', 'sur', 'vous', 'nous', 'ils', 'elles',
    'être', 'faire', 'bien', 'oui', 'non', 'tout', 'plus', 'pas', 'mon', 'ma', 'mes',
    'ton', 'ta', 'tes', 'notre', 'votre', 'leur', 'salut', 'très', 'aussi', 'mais',
    'comme', 'cette', 'c\'est', 'suis', 'sont', 'beaucoup', 'bonne', 'temps', 'monde',
  };

  static const Set<String> _spanishWords = {
    'hola', 'gracias', 'amigo', 'amiga', 'por', 'para', 'con', 'bueno', 'buenos',
    'días', 'tardes', 'noches', 'como', 'estás', 'está', 'muy', 'bien', 'todos',
    'todas', 'hacer', 'estar', 'pero', 'porque', 'qué', 'dónde', 'cuándo',
    'tiempo', 'vida', 'mundo', 'casa', 'favor', 'por favor', 'hasta', 'luego',
  };

  static const Set<String> _portugueseWords = {
    'olá', 'obrigado', 'obrigada', 'você', 'bom', 'boa', 'tarde', 'noite', 'tudo',
    'bem', 'muito', 'mais', 'como', 'vai', 'para', 'com', 'fazer', 'não', 'sim',
    'estou', 'está', 'isso', 'aqui', 'agora', 'tempo', 'amigo', 'onde', 'quando',
  };

  static const Set<String> _yorubaWords = {
    'bawo', 'ẹkú', 'ekun', 'ṣé', 'ọ̀rẹ́', 'ore', 'adúpẹ́', 'adupe', 'bẹ́ẹ̀ni', 'beeni',
    'rárá', 'rara', 'kò', 'ko', 'ní', 'ni', 'sí', 'si', 'ti', 'pé', 'pe', 'ọmọ',
    'omo', 'ilé', 'ile', 'owo', 'ojo', 'wa', 'mi', 're', 'dara', 'pupo',
  };

  static const Set<String> _zuluWords = {
    'sawubona', 'ngiyabonga', 'yebo', 'cha', 'kahle', 'umngane', 'abantu', 'isikhathi',
    'hamba', 'sala', 'unjani', 'ngikhona', 'kakhulu', 'namhlanje', 'kusasa', 'izolo',
  };

  static const Set<String> _hausaWords = {
    'sannu', 'na gode', 'lafiya', 'eh', 'a\'a', 'da', 'don', 'cikin', 'mutum',
    'gida', 'kudi', 'yaya', 'ina', 'yau', 'gobe', 'jiya', 'aboki', 'sosai',
  };

  static const Set<String> _igboWords = {
    'kedu', 'daalu', 'nnọọ', 'nnoo', 'biko', 'ee', 'mba', 'nke', 'na', 'maka',
    'onye', 'nwanne', 'chineke', 'mma', 'ofuma', 'taa', 'echi',
  };

  static const Set<String> _germanWords = {
    'hallo', 'danke', 'bitte', 'guten', 'tag', 'morgen', 'abend', 'sehr', 'gut',
    'nicht', 'mit', 'und', 'oder', 'aber', 'wir', 'sie', 'ich', 'du', 'ist',
    'sind', 'alles', 'klar', 'wieder', 'zeit', 'schön', 'wie', 'geht',
  };

  // ───────────────────────────────────────────────────────────────────────────
  // Real-Time Language Detection
  // ───────────────────────────────────────────────────────────────────────────
  DetectedLanguage detectLanguage(String text) {
    final clean = text.trim();
    if (clean.isEmpty) {
      return DetectedLanguage(language: defaultLanguage, confidence: 0.0, originalText: clean);
    }

    // 1. Script checks
    // Arabic script
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(clean)) {
      return DetectedLanguage(language: findLanguage('ar'), confidence: 0.95, originalText: clean);
    }
    // Devanagari (Hindi)
    if (RegExp(r'[\u0900-\u097F]').hasMatch(clean)) {
      return DetectedLanguage(language: findLanguage('hi'), confidence: 0.95, originalText: clean);
    }
    // CJK (Chinese)
    if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(clean)) {
      return DetectedLanguage(language: findLanguage('zh'), confidence: 0.95, originalText: clean);
    }
    // Japanese Hiragana/Katakana
    if (RegExp(r'[\u3040-\u309F\u30A0-\u30FF]').hasMatch(clean)) {
      return DetectedLanguage(language: findLanguage('ja'), confidence: 0.95, originalText: clean);
    }
    // Amharic (Ethiopic)
    if (RegExp(r'[\u1200-\u137F]').hasMatch(clean)) {
      return DetectedLanguage(language: findLanguage('am'), confidence: 0.95, originalText: clean);
    }
    // Cyrillic (Russian)
    if (RegExp(r'[\u0400-\u04FF]').hasMatch(clean)) {
      return DetectedLanguage(language: findLanguage('ru'), confidence: 0.95, originalText: clean);
    }

    // 2. Tokenize lowercase words for Latin script detection
    final words = clean
        .toLowerCase()
        .replaceAll(RegExp(r"[^\w\s']"), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (words.isEmpty) {
      return DetectedLanguage(language: defaultLanguage, confidence: 0.5, originalText: clean);
    }

    int scoreSwahili = 0;
    int scoreFrench = 0;
    int scoreSpanish = 0;
    int scorePortuguese = 0;
    int scoreYoruba = 0;
    int scoreZulu = 0;
    int scoreHausa = 0;
    int scoreIgbo = 0;
    int scoreGerman = 0;

    for (final w in words) {
      if (_swahiliWords.contains(w)) scoreSwahili += 2;
      if (_frenchWords.contains(w)) scoreFrench += 2;
      if (_spanishWords.contains(w)) scoreSpanish += 2;
      if (_portugueseWords.contains(w)) scorePortuguese += 2;
      if (_yorubaWords.contains(w)) scoreYoruba += 3;
      if (_zuluWords.contains(w)) scoreZulu += 3;
      if (_hausaWords.contains(w)) scoreHausa += 3;
      if (_igboWords.contains(w)) scoreIgbo += 3;
      if (_germanWords.contains(w)) scoreGerman += 2;
    }

    final scores = <String, int>{
      'sw': scoreSwahili,
      'fr': scoreFrench,
      'es': scoreSpanish,
      'pt': scorePortuguese,
      'yo': scoreYoruba,
      'zu': scoreZulu,
      'ha': scoreHausa,
      'ig': scoreIgbo,
      'de': scoreGerman,
    };

    String bestCode = 'en';
    int maxScore = 0;

    scores.forEach((code, score) {
      if (score > maxScore) {
        maxScore = score;
        bestCode = code;
      }
    });

    if (maxScore >= 2) {
      final confidence = (maxScore / (words.length * 2)).clamp(0.65, 0.98);
      return DetectedLanguage(
        language: findLanguage(bestCode),
        confidence: confidence,
        originalText: clean,
      );
    }

    // Default to English with base confidence
    return DetectedLanguage(
      language: findLanguage('en'),
      confidence: 0.70,
      originalText: clean,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Cloud & Resilient Text Translation
  // ───────────────────────────────────────────────────────────────────────────
  Future<String> translateText(
    String text, {
    required String targetLanguageCode,
    String? sourceLanguageCode,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return clean;

    final target = targetLanguageCode.trim().toLowerCase();
    final source = sourceLanguageCode ?? detectLanguage(clean).code;

    if (target == source) {
      return clean; // Already in target language
    }

    // Try cloud assist via Firebase Functions
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'chatAssist',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
      );

      final res = await callable.call<Map<dynamic, dynamic>>({
        'op': 'translate',
        'texts': [clean],
        'target': target,
      });

      final items = res.data['items'] as List?;
      if (items != null && items.isNotEmpty && items.first is Map) {
        final translated = (items.first['translated'] ?? '').toString().trim();
        if (translated.isNotEmpty) {
          return translated;
        }
      }
    } catch (e) {
      debugPrint('[OneovaLanguageService] Cloud translation fallback: $e');
    }

    // High quality offline fallback translation dictionary for common conversational phrases
    return _applyOfflineFallbackTranslation(clean, source: source, target: target);
  }

  String _applyOfflineFallbackTranslation(String text, {required String source, required String target}) {
    final lower = text.trim().toLowerCase();

    // Swahili <-> English
    if (source == 'sw' && target == 'en') {
      if (lower.contains('habari ya asubuhi')) return 'Good morning';
      if (lower.contains('habari za jioni')) return 'Good evening';
      if (lower.contains('habari')) return 'Hello / How are you?';
      if (lower.contains('asante sana')) return 'Thank you very much';
      if (lower.contains('asante')) return 'Thank you';
      if (lower.contains('karibu')) return 'Welcome';
      if (lower.contains('mambo')) return 'What\'s up?';
      if (lower.contains('kwaheri')) return 'Goodbye';
    } else if (source == 'en' && target == 'sw') {
      if (lower.contains('good morning')) return 'Habari ya asubuhi';
      if (lower.contains('good evening')) return 'Habari za jioni';
      if (lower.contains('thank you very much')) return 'Asante sana';
      if (lower.contains('thank you') || lower.contains('thanks')) return 'Asante';
      if (lower.contains('hello') || lower.contains('hi')) return 'Habari';
      if (lower.contains('welcome')) return 'Karibu';
      if (lower.contains('goodbye')) return 'Kwaheri';
    }

    // French <-> English
    if (source == 'fr' && target == 'en') {
      if (lower.contains('bonjour')) return 'Hello / Good morning';
      if (lower.contains('bonsoir')) return 'Good evening';
      if (lower.contains('merci beaucoup')) return 'Thank you very much';
      if (lower.contains('merci')) return 'Thank you';
      if (lower.contains('s\'il vous plaît') || lower.contains('svp')) return 'Please';
      if (lower.contains('au revoir')) return 'Goodbye';
    } else if (source == 'en' && target == 'fr') {
      if (lower.contains('hello') || lower.contains('hi')) return 'Bonjour';
      if (lower.contains('thank you very much')) return 'Merci beaucoup';
      if (lower.contains('thank you') || lower.contains('thanks')) return 'Merci';
      if (lower.contains('please')) return 'S\'il vous plaît';
      if (lower.contains('goodbye')) return 'Au revoir';
    }

    // Spanish <-> English
    if (source == 'es' && target == 'en') {
      if (lower.contains('buenos días')) return 'Good morning';
      if (lower.contains('buenas noches')) return 'Good night';
      if (lower.contains('muchas gracias')) return 'Thank you very much';
      if (lower.contains('gracias')) return 'Thank you';
      if (lower.contains('hola')) return 'Hello';
      if (lower.contains('por favor')) return 'Please';
      if (lower.contains('adiós') || lower.contains('adios')) return 'Goodbye';
    } else if (source == 'en' && target == 'es') {
      if (lower.contains('hello') || lower.contains('hi')) return 'Hola';
      if (lower.contains('good morning')) return 'Buenos días';
      if (lower.contains('thank you very much')) return 'Muchas gracias';
      if (lower.contains('thank you') || lower.contains('thanks')) return 'Gracias';
      if (lower.contains('please')) return 'Por favor';
      if (lower.contains('goodbye')) return 'Adiós';
    }

    // If no direct phrase match, return original text safely
    return text;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // AI Polish & Tone Tidy
  // ───────────────────────────────────────────────────────────────────────────
  Future<String> polishText(String text, {String tone = 'studio'}) async {
    final clean = text.trim();
    if (clean.isEmpty) return clean;

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('voiceTidy');
      final res = await callable.call<Map<dynamic, dynamic>>({
        'text': clean,
        'style': tone,
      });
      final tidied = res.data['text']?.toString().trim();
      if (tidied != null && tidied.isNotEmpty) {
        return tidied;
      }
    } catch (_) {
      // Local grammar & punctuation polishing
    }

    return _applyLocalPolish(clean, tone: tone);
  }

  String _applyLocalPolish(String text, {required String tone}) {
    var out = text.trim();
    if (out.isEmpty) return out;

    // Capitalize first letter
    out = out[0].toUpperCase() + (out.length > 1 ? out.substring(1) : '');

    // Ensure trailing punctuation
    if (!out.endsWith('.') && !out.endsWith('!') && !out.endsWith('?') && !out.endsWith('…')) {
      out = '$out.';
    }

    // Fix multiple spaces
    out = out.replaceAll(RegExp(r'\s+'), ' ');

    // Tone specific subtle styling
    if (tone == 'friendly') {
      if (out.endsWith('.')) out = '${out.substring(0, out.length - 1)}! 😊';
    } else if (tone == 'concise') {
      out = out.replaceAll(RegExp(r'\b(um|uh|like|you know)\b\s*', caseSensitive: false), '');
    }

    return out.trim();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Native Vertex AI Human Voice Playback
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> speak(String text, {String? languageCode}) async {
    final clean = text.trim();
    if (clean.isEmpty) return;

    final lang = languageCode ?? detectLanguage(clean).code;
    _isTtsSpeaking = true;
    try {
      await OvaVertexAudioEngine.instance.speak(
        clean,
        languageCode: lang,
        onComplete: () => _isTtsSpeaking = false,
      );
    } catch (e) {
      debugPrint('[OneovaLanguageService] Vertex voice notice: $e');
      _isTtsSpeaking = false;
    }
  }

  Future<void> stopSpeaking() async {
    _isTtsSpeaking = false;
    await OvaVertexAudioEngine.instance.stop();
  }
}
