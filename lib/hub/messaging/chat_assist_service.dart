import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/services/voice_audio_cache.dart';
import 'widgets/chat_background.dart';

export '../../shared/services/voice_audio_cache.dart';

/// Your own settings for one chat, at users/{uid}/chat_prefs/{chatId}.
/// Private to you: highlights, messages deleted for you, and the AI toggle.
class ChatPrefs {
  final bool aiEnabled;
  final bool aiAutoTranslate;
  final bool aiAutoTranslateVoice;
  final Map<String, Timestamp> highlights;
  final Set<String> hidden;
  final Timestamp? clearedBefore;

  /// Background for this chat, or (in the all-chats doc) the default.
  final ChatBackground? background;

  const ChatPrefs({
    this.aiEnabled = false,
    this.aiAutoTranslate = false,
    this.aiAutoTranslateVoice = false,
    this.highlights = const {},
    this.hidden = const {},
    this.clearedBefore,
    this.background,
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
      aiAutoTranslateVoice: d['aiAutoTranslateVoice'] == true,
      highlights: h,
      hidden: {...((d['hidden'] as List?) ?? const []).map((e) => e.toString())},
      clearedBefore: d['clearedBefore'] as Timestamp?,
      background: ChatBackground.fromMap(d['background']),
    );
  }
}

typedef ChatPrefsKey = ({String uid, String chatId});

final chatPrefsProvider = StreamProvider.family<ChatPrefs, ChatPrefsKey>((ref, k) {
  if (k.uid.isEmpty) return Stream.value(const ChatPrefs());
  return ref.read(chatAssistServiceProvider)._prefsDoc(k.uid, k.chatId).snapshots().map((s) => ChatPrefs.fromMap(s.data()));
});

typedef GlobalHighlightEntry = ({String chatId, String messageId, Timestamp highlightedAt});

final allChatHighlightsProvider = StreamProvider.family<List<GlobalHighlightEntry>, String>((ref, uid) {
  if (uid.isEmpty) return Stream.value(const []);
  return ref.read(chatAssistServiceProvider).watchAllHighlights(uid);
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

  /// chat_prefs doc holding settings for all chats (the default background).
  static const allChatsDoc = '_all_chats';

  /// Null clears it, so the chat falls back to the all-chats background.
  Future<void> setBackground(String uid, String docId, ChatBackground? b) => _prefsDoc(uid, docId).set({
        'background': b == null ? FieldValue.delete() : b.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  DocumentReference<Map<String, dynamic>> _prefsDoc(String uid, String chatId) =>
      _db.collection('users').doc(uid).collection('chat_prefs').doc(chatId);

  Future<void> setAi(
    String uid,
    String chatId, {
    bool? enabled,
    bool? autoTranslate,
    bool? autoTranslateVoice,
  }) =>
      _prefsDoc(uid, chatId).set({
        'aiEnabled': ?enabled,
        // Turning AI off also stops auto-translate.
        'aiAutoTranslate': ?(enabled == false ? false : autoTranslate),
        'aiAutoTranslateVoice': ?(enabled == false ? false : autoTranslateVoice),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> setHighlight(String uid, String chatId, String messageId, bool on) => _prefsDoc(uid, chatId).set({
        'highlights': {messageId: on ? FieldValue.serverTimestamp() : FieldValue.delete()},
      }, SetOptions(merge: true));

  Future<void> hideForMe(String uid, String chatId, String messageId) => _prefsDoc(uid, chatId).set({
        'hidden': FieldValue.arrayUnion([messageId]),
        'highlights': {messageId: FieldValue.delete()},
      }, SetOptions(merge: true));

  Future<void> hideManyForMe(String uid, String chatId, List<String> messageIds) {
    if (messageIds.isEmpty) return Future.value();
    return _prefsDoc(uid, chatId).set({
      'hidden': FieldValue.arrayUnion(messageIds),
      'highlights': {for (final id in messageIds) id: FieldValue.delete()},
    }, SetOptions(merge: true));
  }

  Future<void> clearChatForMe(String uid, String chatId) => _prefsDoc(uid, chatId).set({
        'clearedBefore': FieldValue.serverTimestamp(),
        'highlights': FieldValue.delete(),
        'hidden': FieldValue.delete(),
      }, SetOptions(merge: true));

  Stream<List<GlobalHighlightEntry>> watchAllHighlights(String uid) {
    return _db.collection('users').doc(uid).collection('chat_prefs').snapshots().map((snap) {
      final list = <GlobalHighlightEntry>[];
      for (final doc in snap.docs) {
        if (doc.id == allChatsDoc) continue;
        final prefs = ChatPrefs.fromMap(doc.data());
        for (final entry in prefs.highlights.entries) {
          if (prefs.hidden.contains(entry.key)) continue;
          list.add((chatId: doc.id, messageId: entry.key, highlightedAt: entry.value));
        }
      }
      list.sort((a, b) => b.highlightedAt.compareTo(a.highlightedAt));
      return list;
    });
  }

  /// The device language, e.g. "fr" or "pt-BR".
  static String deviceLanguage() {
    final l = WidgetsBinding.instance.platformDispatcher.locale;
    final c = l.countryCode;
    return (c == null || c.isEmpty) ? l.languageCode : '${l.languageCode}-$c';
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final res = await _functions
          .httpsCallable('chatAssist', options: HttpsCallableOptions(timeout: const Duration(seconds: 55)))
          .call(body);
      return Map<String, dynamic>.from(res.data as Map);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') throw const ChatAssistException('Oneova AI for chats is not available yet.');
      throw ChatAssistException(e.message ?? 'Oneova AI could not help with that right now.');
    }
  }

  /// Translates a voice note into [target] (defaults to device language) and
  /// synthesizes voice-matched audio preserving the speaker's vocal profile.
  Future<VoiceTranslationResult> translateVoiceNote({
    required String cacheKey,
    required String audioPathOrUrl,
    String? senderUid,
    String? target,
  }) {
    final targetLang = target ?? deviceLanguage();
    final fullKey = '$cacheKey::$targetLang';
    return VoiceAudioDiskCache.runDeduplicatedTranslation(fullKey, () async {
      final bytes = await VoiceAudioDiskCache.readAudioBytes(audioPathOrUrl);
      if (bytes.isEmpty) {
        throw const ChatAssistException('Voice note audio is empty.');
      }
      if (bytes.length > 4400000) {
        throw const ChatAssistException('Voice note is too long to translate at once.');
      }
      final d = await _call({
        'op': 'translateVoice',
        'audioBase64': base64Encode(bytes),
        'mimeType': VoiceAudioDiskCache.inferMimeType(audioPathOrUrl),
        'target': targetLang,
        if (senderUid != null && senderUid.isNotEmpty) 'senderUid': senderUid,
      });

      final audioB64 = (d['audioBase64'] ?? '').toString();
      final audioMime = (d['audioMimeType'] ?? 'audio/wav').toString();
      String? synthPath;
      if (audioB64.isNotEmpty) {
        synthPath = await VoiceAudioDiskCache.saveSynthesizedAudio(
          cacheKey: fullKey,
          base64Audio: audioB64,
          mimeType: audioMime,
        );
      }

      return VoiceTranslationResult(
        transcript: (d['transcript'] ?? '').toString(),
        translated: (d['translated'] ?? '').toString(),
        source: (d['source'] ?? '').toString(),
        target: targetLang,
        same: d['same'] == true,
        localAudioPath: synthPath,
        voiceName: (d['voiceName'] ?? 'Aoede').toString(),
        pitch: (d['pitch'] is num) ? (d['pitch'] as num).toDouble().clamp(0.85, 1.18) : 1.0,
        rate: (d['rate'] is num) ? (d['rate'] as num).toDouble().clamp(0.85, 1.15) : 1.0,
      );
    });
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
