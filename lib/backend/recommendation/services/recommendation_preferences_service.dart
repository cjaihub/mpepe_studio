import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/recommendation_models.dart';

final recommendationPreferencesProvider = StreamProvider<RecommendationPreferences>((ref) {
  return ref.watch(recommendationPreferencesServiceProvider).streamPreferences();
});

final recommendationPreferencesServiceProvider = Provider<RecommendationPreferencesService>((ref) {
  return RecommendationPreferencesService();
});

class RecommendationPreferencesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;

  Stream<RecommendationPreferences> streamPreferences() {
    final uid = _userId;
    if (uid == null) return const Stream.empty();

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('recommendations')
        .snapshots()
        .map((doc) => RecommendationPreferences.fromFirestore(doc));
  }

  Future<void> updatePreferences(RecommendationPreferences prefs) async {
    final uid = _userId;
    if (uid == null) return;

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('recommendations')
        .set(prefs.toMap(), SetOptions(merge: true));
  }

  Future<void> resetRecommendations() async {
    final uid = _userId;
    if (uid == null) return;

    // We keep explicit blocks, but wipe the behavioral ML profile
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('recommendations')
        .update({
      'lastResetTime': FieldValue.serverTimestamp(),
    });
    
    // In a real system, we would also trigger a backend deletion of cached embeddings.
  }

  Future<void> hideTopic(String topic) async {
    final uid = _userId;
    if (uid == null) return;

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('recommendations')
        .set({
      'hiddenTopics': FieldValue.arrayUnion([topic])
    }, SetOptions(merge: true));
  }

  Future<void> hideCreator(String creatorId) async {
    final uid = _userId;
    if (uid == null) return;

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('recommendations')
        .set({
      'hiddenCreators': FieldValue.arrayUnion([creatorId])
    }, SetOptions(merge: true));
  }
}
