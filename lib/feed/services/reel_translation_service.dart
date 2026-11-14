import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import '../../shared/language/language_detector.dart';
import '../../shared/language/world_languages.dart';
import '../models/video_transcript_model.dart';

/// A reel's caption (and caption track) in the viewer's language, as cached by
/// the `reelTranslate` function (functions/src/reelTranslate.ts). Each reel is
/// translated once per language on the server and shared by every viewer.
class ReelTranslation {
  final String target;
  final String? source;
  final String caption;
  final List<CaptionSegment> segments;
  final String support;

  const ReelTranslation({
    required this.target,
    required this.source,
    required this.caption,
    required this.segments,
    required this.support,
  });

  /// "Swahili", or null when the source is unknown.
  String? get sourceName => source == null ? null : (WorldLanguages.nameOf(source) ?? LanguageDetector.nameOf(source!));
}

/// Base code: "pt" for "pt-BR".
String _base(String code) => code.split(RegExp('[-_]')).first.toLowerCase();

/// Caption text without hashtags, the part that gets translated.
String reelCaptionBody(String caption) => caption
    .replaceAll(RegExp(r'(^|\s)#[\wÀ-￿]+'), ' ')
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .trim();

/// Language reels are translated into: Settings → Language, else the phone language.
final reelTranslateToProvider = Provider<String>((ref) {
  final lang = ref.watch(settingsProvider).value?['language'];
  final picked = lang is Map ? lang['translateTo'] : null;
  return picked is String && picked.isNotEmpty ? picked : LanguageDetector.phoneLanguage();
});

/// Settings → Language → "Translate reels automatically" (on by default).
final reelAutoTranslateProvider = Provider<bool>((ref) {
  final lang = ref.watch(settingsProvider).value?['language'];
  return !(lang is Map && lang['autoTranslateReels'] == false);
});

class ReelTranslationService {
  ReelTranslationService(this._functions);
  final FirebaseFunctions _functions;

  /// Per app run; the server cache is the real one.
  final Map<String, Future<ReelTranslation?>> _memo = {};

  Future<ReelTranslation?> translate(String postId, String target) {
    final key = '$postId|$target';
    final hit = _memo[key];
    if (hit != null) return hit;
    if (_memo.length > 300) _memo.remove(_memo.keys.first);
    final f = _fetch(postId, target);
    _memo[key] = f;
    // A failed call may be tried again on the next view.
    f.then((v) {
      if (v == null) _memo.remove(key);
    });
    return f;
  }

  Future<ReelTranslation?> _fetch(String postId, String target) async {
    try {
      final res = await _functions
          .httpsCallable('reelTranslate', options: HttpsCallableOptions(timeout: const Duration(seconds: 45)))
          .call({'postId': postId, 'target': target});
      final d = Map<String, dynamic>.from(res.data as Map);
      if (d['same'] == true || d['support'] == 'unsupported') return null;
      final caption = (d['caption'] as String? ?? '').trim();
      final segments = (d['segments'] as List? ?? const [])
          .map((e) => CaptionSegment.fromMap(Map<String, dynamic>.from(e as Map)))
          .where((s) => s.text.isNotEmpty)
          .toList();
      if (caption.isEmpty && segments.isEmpty) return null;
      return ReelTranslation(
        target: target,
        source: d['source'] as String?,
        caption: caption,
        segments: segments,
        support: d['support'] as String? ?? 'limited',
      );
    } catch (e) {
      debugPrint('[ReelTranslation] $postId: $e');
      return null;
    }
  }
}

final reelTranslationServiceProvider = Provider((ref) => ReelTranslationService(FirebaseFunctions.instance));

/// Translation to show for a reel, or null when it's already in a language the
/// viewer reads (detected on the phone first, so most reels never call the server).
final reelTranslationProvider =
    FutureProvider.autoDispose.family<ReelTranslation?, ({String id, String caption})>((ref, reel) async {
  if (!ref.watch(reelAutoTranslateProvider)) return null;
  final target = ref.watch(reelTranslateToProvider);
  final body = reelCaptionBody(reel.caption);
  if (body.isEmpty) return null;
  final detected = await LanguageDetector.instance.detect(body);
  if (detected == null || detected == _base(target)) return null;
  // Languages the viewer said they read (and the phone language) stay as they are,
  // unless they picked a different translation language on purpose.
  final reads = await LanguageDetector.instance.readsLanguages();
  if (reads.contains(detected) && _base(target) == LanguageDetector.phoneLanguage()) return null;
  return ref.read(reelTranslationServiceProvider).translate(reel.id, target);
});

/// "See original" per reel for this app run.
class ReelShowOriginalNotifier extends Notifier<bool> {
  ReelShowOriginalNotifier(this.reelId);
  final String reelId;

  @override
  bool build() => false;

  void toggle() => state = !state;
}

final reelShowOriginalProvider =
    NotifierProvider.family<ReelShowOriginalNotifier, bool, String>(ReelShowOriginalNotifier.new);
