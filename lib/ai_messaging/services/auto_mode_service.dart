import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../models/auto_mode_settings.dart';
import '../../auth/auth_repository.dart';

class AutoModeService extends AsyncNotifier<AutoModeSettings> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  String? get _userId => ref.read(authRepositoryProvider).currentUser?.uid;

  @override
  Future<AutoModeSettings> build() async {
    return _fetchSettings();
  }

  Future<AutoModeSettings> _fetchSettings() async {
    final uid = _userId;
    if (uid == null) return AutoModeSettings();

    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('communicationProfile')
          .doc('autoMode')
          .get();
          
      if (doc.exists && doc.data() != null) {
        return AutoModeSettings.fromMap(doc.data()!);
      }
    } catch (e) {
      debugPrint('Error loading auto mode settings: $e');
    }
    return AutoModeSettings(); // Defaults
  }

  Future<void> updateSettings(AutoModeSettings settings) async {
    final uid = _userId;
    if (uid == null) throw Exception('Not authenticated');

    try {
      // Optimistic update
      state = AsyncValue.data(settings);
      
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('communicationProfile')
          .doc('autoMode')
          .set(settings.toMap(), SetOptions(merge: true));
          
    } catch (e) {
      debugPrint('Error updating auto mode settings: $e');
      // Revert on error
      state = const AsyncValue.loading();
      state = await AsyncValue.guard(() => _fetchSettings());
      throw Exception('Failed to update settings');
    }
  }
}

final autoModeProvider = AsyncNotifierProvider<AutoModeService, AutoModeSettings>(() {
  return AutoModeService();
});
