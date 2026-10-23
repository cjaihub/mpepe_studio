import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../models/contact_profile.dart';
import '../../backend/user_service.dart';

final contactServiceProvider = AsyncNotifierProvider<ContactService, List<ContactProfile>>(() {
  return ContactService();
});

class ContactService extends AsyncNotifier<List<ContactProfile>> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Future<List<ContactProfile>> build() async {
    return _fetchContacts();
  }

  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  Future<List<ContactProfile>> _fetchContacts() async {
    final uid = _currentUserId;
    if (uid == null) return [];

    try {
      // 1. Fetch relational data for all saved contacts
      final contactsSnapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('user_contacts')
          .get();

      final List<ContactProfile> profiles = [];

      for (var doc in contactsSnapshot.docs) {
        final relationalData = ContactRelationalData.fromMap(doc.data(), doc.id);
        
        // 2. Fetch the target user's AppUser profile
        final userDoc = await _firestore.collection('users').doc(doc.id).get();
        if (userDoc.exists && userDoc.data() != null) {
          final appUser = AppUser.fromMap(userDoc.data()!, userDoc.id);
          profiles.add(ContactProfile(user: appUser, relationalData: relationalData));
        }
      }

      return profiles;
    } catch (e) {
      debugPrint('Error fetching contacts: $e');
      return [];
    }
  }

  Future<ContactProfile?> getContact(String targetUserId) async {
    final uid = _currentUserId;
    if (uid == null) return null;

    try {
      final userDoc = await _firestore.collection('users').doc(targetUserId).get();
      if (!userDoc.exists || userDoc.data() == null) return null;
      final appUser = AppUser.fromMap(userDoc.data()!, userDoc.id);

      final relationalDoc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('user_contacts')
          .doc(targetUserId)
          .get();

      final relationalData = ContactRelationalData.fromMap(
        relationalDoc.exists ? relationalDoc.data() : null,
        targetUserId,
      );

      return ContactProfile(user: appUser, relationalData: relationalData);
    } catch (e) {
      debugPrint('Error getting contact: $e');
      return null;
    }
  }

  Future<void> updateNotes(String targetUserId, String notes) async {
    await _updateRelationalData(targetUserId, {'notes': notes});
  }

  Future<void> updateTags(String targetUserId, List<String> tags) async {
    await _updateRelationalData(targetUserId, {'tags': tags});
  }

  Future<void> setMuteStatus(String targetUserId, bool isMuted) async {
    await _updateRelationalData(targetUserId, {'isMuted': isMuted});
  }

  Future<void> setBlockStatus(String targetUserId, bool isBlocked) async {
    await _updateRelationalData(targetUserId, {'isBlocked': isBlocked});
  }

  Future<void> setRelationshipStatus(String targetUserId, RelationshipStatus status) async {
    await _updateRelationalData(targetUserId, {'relationshipStatus': status.name});
  }

  Future<void> _updateRelationalData(String targetUserId, Map<String, dynamic> updates) async {
    final uid = _currentUserId;
    if (uid == null) return;

    try {
      updates['lastInteraction'] = FieldValue.serverTimestamp();
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('user_contacts')
          .doc(targetUserId)
          .set(updates, SetOptions(merge: true));
          
      // Refresh state
      state = const AsyncValue.loading();
      state = await AsyncValue.guard(() => _fetchContacts());
    } catch (e) {
      debugPrint('Error updating contact relational data: $e');
    }
  }
}
