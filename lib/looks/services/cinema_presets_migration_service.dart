import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../create/services/cinema_preset_service.dart';
import '../adapters/legacy_look_adapters.dart';

/// Migration service folding legacy Cinema Presets into unified Oneova Looks.
/// Executes once per user, non-destructively copying presets into `users/{uid}/looks`.
class CinemaPresetsMigrationService {
  final FirebaseFirestore _firestore;
  final CinemaPresetService _cinemaPresetService;

  CinemaPresetsMigrationService({
    FirebaseFirestore? firestore,
    CinemaPresetService? cinemaPresetService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _cinemaPresetService = cinemaPresetService ?? CinemaPresetService();

  /// Runs migration if not previously completed.
  Future<int> migrateUserCinemaPresets(String uid) async {
    if (uid.isEmpty) return 0;

    try {
      final userSettingsDoc = _firestore.collection('users').doc(uid).collection('settings').doc('migrations');
      final snapshot = await userSettingsDoc.get();

      if (snapshot.exists && (snapshot.data()?['cinemaPresetsMigrated'] == true)) {
        debugPrint('[CinemaPresetsMigration] Already migrated for user $uid.');
        return 0;
      }

      // Fetch user cinema presets from CinemaPresetService
      final userPresets = await _cinemaPresetService.getUserCustomPresets();
      if (userPresets.isEmpty) {
        await userSettingsDoc.set({'cinemaPresetsMigrated': true}, SetOptions(merge: true));
        return 0;
      }

      int count = 0;
      final batch = _firestore.batch();
      final looksCollection = _firestore.collection('users').doc(uid).collection('looks');

      for (final cp in userPresets) {
        final look = LegacyLookAdapters.fromCinemaPreset(cp).copyWith(
          ownerUid: uid,
          source: 'user',
        );
        batch.set(looksCollection.doc(look.id), look.toMap(), SetOptions(merge: true));
        count++;
      }

      batch.set(userSettingsDoc, {'cinemaPresetsMigrated': true, 'cinemaPresetsMigratedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      await batch.commit();

      debugPrint('[CinemaPresetsMigration] Migrated $count cinema presets to Oneova Looks for user $uid.');
      return count;
    } catch (e, st) {
      debugPrint('[CinemaPresetsMigration] Error migrating cinema presets: $e\n$st');
      return 0;
    }
  }
}
