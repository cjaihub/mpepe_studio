import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single draft record with content, metadata, and timestamp.
class DraftRecord {
  final String text;
  final Map<String, dynamic> metadata;
  final DateTime updatedAt;

  const DraftRecord({
    required this.text,
    this.metadata = const {},
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'metadata': metadata,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory DraftRecord.fromJson(Map<String, dynamic> json) {
    return DraftRecord(
      text: json['text'] as String? ?? '',
      metadata: json['metadata'] is Map ? Map<String, dynamic>.from(json['metadata']) : const {},
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Global, high-performance draft store that autosaves in-flight user input across:
/// - Chat composer per conversation
/// - Comment sheets per post / reel
/// - Bio & profile editor
/// - Post creator captions & tags
/// - Ova AI prompt input
/// - Live studio wizard setup
///
/// Provides 0ms synchronous reads from memory, debounced async persistence to
/// local storage, and reactive change notification for badges and indicators.
class DraftStore {
  DraftStore._();
  static final DraftStore instance = DraftStore._();

  static const String _prefix = 'oneova_draft_';
  final Map<String, DraftRecord> _memoryCache = {};
  final Map<String, Timer> _debounceTimers = {};
  final ValueNotifier<int> _revisionNotifier = ValueNotifier<int>(0);
  SharedPreferences? _prefs;
  bool _isInitialized = false;

  ValueListenable<int> get revisions => _revisionNotifier;

  /// Common namespaced key builders
  static String chatKey(String chatId) => 'chat_$chatId';
  static String commentKey(String contentId) => 'comment_$contentId';
  static String get postCaptionKey => 'post_caption';
  static String get profileBioKey => 'profile_bio';
  static String get profileDisplayNameKey => 'profile_display_name';
  static String get ovaPromptKey => 'ova_prompt';
  static String get liveWizardKey => 'live_wizard';

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      final keys = _prefs?.getKeys() ?? {};
      for (final rawKey in keys) {
        if (rawKey.startsWith(_prefix)) {
          final key = rawKey.substring(_prefix.length);
          final rawJson = _prefs?.getString(rawKey);
          if (rawJson != null && rawJson.isNotEmpty) {
            try {
              final map = jsonDecode(rawJson) as Map<String, dynamic>;
              _memoryCache[key] = DraftRecord.fromJson(map);
            } catch (_) {}
          }
        }
      }
      _isInitialized = true;
      _revisionNotifier.value++;
    } catch (e) {
      debugPrint('[DraftStore] Initialization error: $e');
    }
  }

  /// Retrieves the draft text synchronously in 0ms.
  String? getDraft(String key) {
    return _memoryCache[key]?.text;
  }

  /// Retrieves full draft record including metadata.
  DraftRecord? getRecord(String key) {
    return _memoryCache[key];
  }

  /// Checks if a non-empty draft exists for the given key.
  bool hasDraft(String key) {
    final text = _memoryCache[key]?.text;
    return text != null && text.trim().isNotEmpty;
  }

  /// Saves a draft with debounced local persistence (400ms).
  /// Synchronous memory state updates immediately so no input is ever lost.
  void setDraft(
    String key,
    String text, {
    Map<String, dynamic>? metadata,
    Duration debounce = const Duration(milliseconds: 400),
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty && (metadata == null || metadata.isEmpty)) {
      clearDraft(key);
      return;
    }

    final record = DraftRecord(
      text: text,
      metadata: metadata ?? const {},
      updatedAt: DateTime.now(),
    );
    _memoryCache[key] = record;
    _revisionNotifier.value++;

    _debounceTimers[key]?.cancel();
    _debounceTimers[key] = Timer(debounce, () async {
      await _persist(key, record);
    });
  }

  /// Clears a draft from memory and persistent disk.
  Future<void> clearDraft(String key) async {
    _debounceTimers[key]?.cancel();
    _debounceTimers.remove(key);

    if (_memoryCache.remove(key) != null) {
      _revisionNotifier.value++;
    }

    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$key');
    } catch (e) {
      debugPrint('[DraftStore] Error clearing draft for $key: $e');
    }
  }

  /// Flushes any pending debounce timers immediately.
  Future<void> flush() async {
    for (final entry in _debounceTimers.entries) {
      entry.value.cancel();
      final record = _memoryCache[entry.key];
      if (record != null) {
        await _persist(entry.key, record);
      }
    }
    _debounceTimers.clear();
  }

  Future<void> _persist(String key, DraftRecord record) async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$key', jsonEncode(record.toJson()));
    } catch (e) {
      debugPrint('[DraftStore] Failed to persist draft for $key: $e');
    }
  }
}

final draftStoreProvider = Provider<DraftStore>((ref) {
  return DraftStore.instance;
});

final draftNotifierProvider = StreamProvider.family<String?, String>((ref, key) async* {
  final store = ref.watch(draftStoreProvider);
  yield store.getDraft(key);

  final controller = StreamController<String?>();
  void listener() {
    controller.add(store.getDraft(key));
  }

  store.revisions.addListener(listener);
  ref.onDispose(() {
    store.revisions.removeListener(listener);
    controller.close();
  });

  yield* controller.stream;
});
