import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Your own settings for one chat, at users/{uid}/chat_prefs/{chatId}.
/// Private to you: highlights, messages deleted for you, and the AI toggle.
class ChatPrefs {
  final bool aiEnabled;
  final bool aiAutoTranslate;
  final Map<String, Timestamp> highlights;
  final Set<String> hidden;

  const ChatPrefs({
    this.aiEnabled = false,
    this.aiAutoTranslate = false,
    this.highlights = const {},
    this.hidden = const {},
  });

  factory ChatPrefs.fromMap(Map<String, dynamic>? d) {
    if (d == null) return const ChatPrefs();
    final h = <String, Timestamp>{};
    (d['highlights'] as Map?)?.forEach((k, v) {
      if (v is Timestamp) h[k.toString()] = v;
    });
    return ChatPrefs(
      aiEnabled: d['aiEnabled'] == true,
      aiAutoTranslate: d['aiAutoTranslate'] == true,
      highlights: h,
      hidden: {...((d['hidden'] as List?) ?? const []).map((e) => e.toString())},
    );
  }
}

typedef ChatPrefsKey = ({String uid, String chatId});

final chatPrefsProvider = StreamProvider.family<ChatPrefs, ChatPrefsKey>((ref, k) {
  if (k.uid.isEmpty) return Stream.value(const ChatPrefs());
  return ref.read(chatAssistServiceProvider)._prefsDoc(k.uid, k.chatId).snapshots().map((s) => ChatPrefs.fromMap(s.data()));
});

/// One line of conversation handed to the AI.
typedef AssistLine = ({bool me, String text});

class ChatSummary {
  final String summary;
  final List<String> points;
  final List<String> todos;
  const ChatSummary(this.summary, this.points, this.todos);
}

class ChatTranslation {
  final String text;
  final String source;

  /// Already in your language, so there is nothing to show.
  final bool same;
  const ChatTranslation(this.text, this.source, this.same);
}

/// Chat AI through the `chatAssist` Cloud Function (Gemini on Vertex AI, no
/// API keys on the phone). Callers only use it for a message the user asked
/// to translate, or in a chat where the user turned AI on.
class ChatAssistService {
  ChatAssistService(this._db, this._functions);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  DocumentReference<Map<String, dynamic>> _prefsDoc(String uid, String chatId) =>
      _db.collection('users').doc(uid).collection('chat_prefs').doc(chatId);

  Future<void> setAi(String uid, String chatId, {bool? enabled, bool? autoTranslate}) =>
      _prefsDoc(uid, chatId).set({
        'aiEnabled': ?enabled,
        // Turning AI off also stops auto-translate.
        'aiAutoTranslate': ?(enabled == false ? false : autoTranslate),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> setHighlight(String uid, String chatId, String messageId, bool on) => _prefsDoc(uid, chatId).set({
        'highlights': {messageId: on ? FieldValue.serverTimestamp() : FieldValue.delete()},
      }, SetOptions(merge: true));

  Future<void> hideForMe(String uid, String chatId, String messageId) => _prefsDoc(uid, chatId).set({
        'hidden': FieldValue.arrayUnion([messageId]),
        'highlights': {messageId: FieldValue.delete()},
      }, SetOptions(merge: true));

  /// The device language, e.g. "fr" or "pt-BR".
  static String deviceLanguage() {
    final l = WidgetsBinding.instance.platformDispatcher.locale;
    final c = l.countryCode;
    return (c == null || c.isEmpty) ? l.languageCode : '${l.languageCode}-$c';
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final res = await _functions
          .httpsCallable('chatAssist', options: HttpsCallableOptions(timeout: const Duration(seconds: 45)))
          .call(body);
      return Map<String, dynamic>.from(res.data as Map);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') throw const ChatAssistException('Oneova AI for chats is not available yet.');
      throw ChatAssistException(e.message ?? 'Oneova AI could not help with that right now.');
    }
  }

  Future<List<ChatTranslation>> translate(List<String> texts, {String? target}) async {
    if (texts.isEmpty) return const [];
    final d = await _call({'op': 'translate', 'texts': texts, 'target': target ?? deviceLanguage()});
    final items = (d['items'] as List?) ?? const [];
    return [
      for (var i = 0; i < texts.length; i++)
        if (i < items.length && items[i] is Map)
          ChatTranslation(
            (items[i]['translated'] ?? texts[i]).toString(),
            (items[i]['source'] ?? '').toString(),
            items[i]['same'] == true,
          )
        else
          ChatTranslation(texts[i], '', true),
    ];
  }

  Future<ChatSummary> summarize(List<AssistLine> lines, {String? target}) async {
    final d = await _call({
      'op': 'summarize',
      'target': target ?? deviceLanguage(),
      'lines': [for (final l in lines) {'me': l.me, 'text': l.text}],
    });
    List<String> strs(Object? v) => ((v as List?) ?? const []).map((e) => e.toString()).toList();
    return ChatSummary((d['summary'] ?? '').toString(), strs(d['points']), strs(d['todos']));
  }

  Future<List<String>> smartReplies(List<AssistLine> lines) async {
    final d = await _call({
      'op': 'replies',
      'lines': [for (final l in lines) {'me': l.me, 'text': l.text}],
    });
    return ((d['replies'] as List?) ?? const []).map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }
}

class ChatAssistException implements Exception {
  final String message;
  const ChatAssistException(this.message);
  @override
  String toString() => message;
}

final chatAssistServiceProvider = Provider<ChatAssistService>(
  (ref) => ChatAssistService(FirebaseFirestore.instance, FirebaseFunctions.instance),
);
