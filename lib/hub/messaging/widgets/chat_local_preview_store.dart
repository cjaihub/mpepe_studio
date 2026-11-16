import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Device-local cache of already-decrypted latest snippets for 1:1 E2EE chats.
/// Plaintext is NEVER written back to Firestore; only cached on the user's phone
/// so the Chats inbox list and search remain readable after decrypting.
class ChatLocalPreviewStore {
  ChatLocalPreviewStore._();

  static final ChatLocalPreviewStore instance = ChatLocalPreviewStore._();
  static const _prefsKey = 'oneova_e2ee_chat_previews_v1';

  Map<String, _PreviewEntry>? _cache;
  Future<void>? _loading;

  Future<void> ensureLoaded() {
    if (_cache != null) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final map = <String, _PreviewEntry>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            if (v is Map) {
              map[k.toString()] = _PreviewEntry(
                preview: (v['p'] ?? '').toString(),
                tsMs: (v['t'] as num?)?.toInt() ?? 0,
              );
            }
          });
        }
      }
    } catch (_) {}
    _cache = map;
  }

  String? previewFor(String chatId, int? lastMessageMs) {
    final entry = _cache?[chatId];
    if (entry == null || entry.preview.isEmpty) return null;
    if (lastMessageMs != null && entry.tsMs > 0 && lastMessageMs > entry.tsMs + 3000) {
      return null;
    }
    return entry.preview;
  }

  Future<void> save(String chatId, String preview, int tsMs) async {
    await ensureLoaded();
    final map = _cache!;
    final existing = map[chatId];
    if (existing != null && existing.tsMs > tsMs) return;
    if (existing != null && existing.preview == preview && existing.tsMs == tsMs) return;
    map[chatId] = _PreviewEntry(preview: preview, tsMs: tsMs);
    if (map.length > 200) {
      final sorted = map.entries.toList()..sort((a, b) => a.value.tsMs.compareTo(b.value.tsMs));
      for (final e in sorted.take(map.length - 200)) {
        map.remove(e.key);
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        for (final e in map.entries) e.key: {'p': e.value.preview, 't': e.value.tsMs},
      });
      await prefs.setString(_prefsKey, encoded);
    } catch (_) {}
  }

  Future<void> remove(String chatId) async {
    await ensureLoaded();
    if (_cache?.remove(chatId) == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        for (final e in _cache!.entries) e.key: {'p': e.value.preview, 't': e.value.tsMs},
      });
      await prefs.setString(_prefsKey, encoded);
    } catch (_) {}
  }
}

class _PreviewEntry {
  final String preview;
  final int tsMs;
  const _PreviewEntry({required this.preview, required this.tsMs});
}
