import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'settings/account_settings_schema.dart';

/// Reads and writes the one per-account settings store, `user_settings/{uid}`.
/// See [AccountSettingsSchema] for the layout, the legacy documents it
/// replaces and the server mirrors it keeps in step.
class SettingsService {
  SettingsService({FirebaseFirestore? firestore}) : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;
  FirebaseFirestore get _firestore => _firestoreOverride ?? FirebaseFirestore.instance;

  /// Accounts whose legacy settings were folded in by this process.
  static final Map<String, Future<void>> _migrations = {};

  @visibleForTesting
  static void resetMigrationCache() => _migrations.clear();

  DocumentReference<Map<String, dynamic>> _doc(String userId) =>
      _firestore.collection(AccountSettingsSchema.collection).doc(userId);

  DocumentReference<Map<String, dynamic>> _userDoc(String userId, String relativePath) =>
      _firestore.doc('users/$userId/$relativePath');

  Future<Map<String, dynamic>> getSettings(String userId) async {
    try {
      await ensureMigrated(userId);
      final doc = await _doc(userId).get();
      return AccountSettingsSchema.resolve(doc.data());
    } catch (e) {
      debugPrint('Error getting settings: $e');
      return defaultSettings;
    }
  }

  /// Real-time stream of `user_settings/{userId}` merged over the defaults.
  /// The first time an account is seen, its legacy settings documents are
  /// folded in (and the doc is created when missing).
  Stream<Map<String, dynamic>> watchSettings(String userId) {
    return _doc(userId).snapshots().map((doc) {
      final data = doc.data();
      if (!doc.exists || data == null || (data[AccountSettingsSchema.schemaKey] as num? ?? 0) < AccountSettingsSchema.version) {
        unawaited(ensureMigrated(userId).catchError((Object e) {
          debugPrint('Error migrating settings: $e');
        }));
      }
      return AccountSettingsSchema.resolve(data);
    });
  }

  /// One section of the settings, e.g. `notifications`, kept live.
  Stream<Map<String, dynamic>> watchCategory(String userId, String category) =>
      watchSettings(userId).map((s) => AccountSettingsSchema.category(s, category));

  Map<String, dynamic> get defaultSettings => AccountSettingsSchema.defaults();

  /// Folds the legacy settings documents into `user_settings/{userId}` once.
  Future<void> ensureMigrated(String userId) {
    return _migrations.putIfAbsent(userId, () async {
      try {
        await _migrate(userId);
      } catch (e) {
        _migrations.remove(userId);
        rethrow;
      }
    });
  }

  Future<void> _migrate(String userId) async {
    final ref = _doc(userId);
    final snap = await ref.get();
    final stored = snap.data() ?? <String, dynamic>{};
    if ((stored[AccountSettingsSchema.schemaKey] as num? ?? 0) >= AccountSettingsSchema.version) return;

    final legacy = <String, Map<String, dynamic>>{};
    for (final entry in AccountSettingsSchema.legacyDocs.entries) {
      try {
        final doc = await _userDoc(userId, entry.value).get();
        final data = doc.data();
        if (data != null && data.isNotEmpty) legacy[entry.key] = data;
      } catch (e) {
        debugPrint('Skipping legacy settings ${entry.value}: $e');
      }
    }

    final patch = AccountSettingsSchema.foldLegacy(stored, legacy);
    if (!snap.exists) {
      // New account: materialize the defaults with any legacy values on top.
      final clean = Map<String, dynamic>.from(patch)
        ..removeWhere((k, v) => v is Map && v.values.any((x) => x is FieldValue));
      await ref.set(AccountSettingsSchema.merge(AccountSettingsSchema.defaults(), clean));
    } else {
      await ref.set(patch, SetOptions(merge: true));
    }
  }

  Future<void> updateSettings(String userId, Map<String, dynamic> newSettings) async {
    try {
      final batch = _firestore.batch();
      batch.set(_doc(userId), newSettings, SetOptions(merge: true));
      newSettings.forEach((category, value) {
        final mirror = AccountSettingsSchema.serverMirrors[category];
        if (mirror != null && value is Map) {
          batch.set(_userDoc(userId, mirror), Map<String, dynamic>.from(value), SetOptions(merge: true));
        }
      });
      await batch.commit();
    } catch (e) {
      debugPrint('Error updating settings: $e');
      rethrow;
    }
  }

  /// Merges [categoryData] into one category. Nested maps merge too, so
  /// `{'categoryOverrides': {'mention': false}}` only touches that entry.
  Future<void> updateSettingsCategory(String userId, String category, Map<String, dynamic> categoryData) {
    return updateSettings(userId, {category: categoryData});
  }
}
