import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/monetization_models.dart';

final monetizationServiceProvider = Provider<MonetizationService>((ref) {
  return MonetizationService();
});

final creatorMonetizationProvider = StreamProvider<CreatorMonetizationProfile>((ref) {
  return ref.watch(monetizationServiceProvider).streamProfile();
});

class MonetizationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;

  Stream<CreatorMonetizationProfile> streamProfile() {
    final uid = _userId;
    if (uid == null) return const Stream.empty();

    return _firestore
        .collection('creators')
        .doc(uid)
        .collection('studio')
        .doc('monetization')
        .snapshots()
        .map((doc) => CreatorMonetizationProfile.fromFirestore(doc));
  }

  Future<void> enableFeature(MonetizationFeatureType type) async {
    final uid = _userId;
    if (uid == null) return;
    
    // In production, this would trigger a Cloud Function to verify identity (Oneova KYC), etc.
    // For now we assume eligibility is pre-checked.
    
    final update = {
      'features.${type.name}.type': type.name,
      'features.${type.name}.status': MonetizationStatus.active.name,
      'features.${type.name}.config': {},
    };

    await _firestore
        .collection('creators')
        .doc(uid)
        .collection('studio')
        .doc('monetization')
        .set(update, SetOptions(merge: true));
  }
  
  Future<void> updateFeatureConfig(MonetizationFeatureType type, Map<String, dynamic> config) async {
    final uid = _userId;
    if (uid == null) return;
    
    final update = {
      'features.${type.name}.config': config,
    };

    await _firestore
        .collection('creators')
        .doc(uid)
        .collection('studio')
        .doc('monetization')
        .set(update, SetOptions(merge: true));
  }

  Future<void> disableFeature(MonetizationFeatureType type) async {
    final uid = _userId;
    if (uid == null) return;
    
    final update = {
      'features.${type.name}.status': MonetizationStatus.eligible.name,
    };

    await _firestore
        .collection('creators')
        .doc(uid)
        .collection('studio')
        .doc('monetization')
        .set(update, SetOptions(merge: true));
  }
}
