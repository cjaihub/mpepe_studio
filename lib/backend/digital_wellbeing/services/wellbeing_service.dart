import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/wellbeing_models.dart';

final wellbeingServiceProvider = Provider<DigitalWellbeingService>((ref) {
  return DigitalWellbeingService();
});

final wellbeingPreferencesProvider = StreamProvider<DigitalWellbeingPreferences>((ref) {
  return ref.watch(wellbeingServiceProvider).streamPreferences();
});

class DigitalWellbeingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;

  Stream<DigitalWellbeingPreferences> streamPreferences() {
    final uid = _userId;
    if (uid == null) return const Stream.empty();

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('digital_wellbeing')
        .snapshots()
        .map((doc) => DigitalWellbeingPreferences.fromFirestore(doc));
  }

  Future<void> updatePreferences(DigitalWellbeingPreferences prefs) async {
    final uid = _userId;
    if (uid == null) return;

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('digital_wellbeing')
        .set(prefs.toMap(), SetOptions(merge: true));
  }

  Future<void> updateFeedMode(FeedLayoutMode mode) async {
    final uid = _userId;
    if (uid == null) return;

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('digital_wellbeing')
        .set({'feedMode': mode.name}, SetOptions(merge: true));
  }
}
