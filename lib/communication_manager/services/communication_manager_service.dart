import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../models/communication_preference.dart';
import '../../auth/auth_repository.dart';

class CommunicationManagerService extends AsyncNotifier<List<CommunicationPreference>> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  String get userId {
    return ref.read(authStateProvider).value?.uid ?? 'unknown';
  }

  @override
  Future<List<CommunicationPreference>> build() async {
    return _fetchPreferences();
  }

  Future<List<CommunicationPreference>> _fetchPreferences() async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('communicationProfile')
          .doc('preferences')
          .collection('items')
          .orderBy('updatedAt', descending: true)
          .get();
      return snapshot.docs.map((doc) => CommunicationPreference.fromMap(doc.data(), doc.id)).toList();
    } catch (e) {
      debugPrint('Error loading communication preferences: $e');
      return [];
    }
  }

  Future<PersonalizationSettings> getSettings() async {
    try {
      final doc = await _firestore.collection('users').doc(userId).collection('communicationProfile').doc('settings').get();
      if (doc.exists && doc.data() != null) {
        return PersonalizationSettings.fromMap(doc.data()!);
      }
    } catch (e) {
      debugPrint('Error fetching personalization settings: $e');
    }
    return PersonalizationSettings(); // Defaults
  }

  Future<void> updateSettings(PersonalizationSettings settings) async {
    try {
      await _firestore.collection('users').doc(userId).collection('communicationProfile').doc('settings').set(settings.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating personalization settings: $e');
      throw Exception('Failed to update settings');
    }
  }

  Future<void> updatePreference(CommunicationPreference pref) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('communicationProfile')
          .doc('preferences')
          .collection('items')
          .doc(pref.id)
          .set(pref.toMap(), SetOptions(merge: true));
      
      ref.invalidateSelf();
    } catch (e) {
      debugPrint('Error updating communication preference: $e');
      throw Exception('Failed to update preference');
    }
  }

  Future<void> deletePreference(String id) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('communicationProfile')
          .doc('preferences')
          .collection('items')
          .doc(id)
          .delete();
          
      ref.invalidateSelf();
    } catch (e) {
      debugPrint('Error deleting communication preference: $e');
      throw Exception('Failed to delete preference');
    }
  }

  Future<void> resetProfile() async {
    try {
      // Create a batch
      final batch = _firestore.batch();
      
      // Delete all preferences
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('communicationProfile')
          .doc('preferences')
          .collection('items')
          .get();
          
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      
      // Reset settings
      final settingsRef = _firestore.collection('users').doc(userId).collection('communicationProfile').doc('settings');
      batch.set(settingsRef, PersonalizationSettings(lastReset: DateTime.now()).toMap());
      
      await batch.commit();
      
      ref.invalidateSelf();
    } catch (e) {
      debugPrint('Error resetting communication profile: $e');
      throw Exception('Failed to reset profile');
    }
  }
}

// In a real app this would depend on an auth provider for the current userId
final communicationManagerProvider = AsyncNotifierProvider<CommunicationManagerService, List<CommunicationPreference>>(CommunicationManagerService.new);
