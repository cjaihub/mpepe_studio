import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/recommendation_models.dart';
import '../../settings_service.dart';

final recommendationPreferencesProvider = StreamProvider<RecommendationPreferences>((ref) {
  return ref.watch(recommendationPreferencesServiceProvider).streamPreferences();
});

final recommendationPreferencesServiceProvider = Provider<RecommendationPreferencesService>((ref) {
  return RecommendationPreferencesService();
});

/// Explicit recommendation preferences: the `recommendations` category of
/// the one settings store, user_settings/{uid}.
class RecommendationPreferencesService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final SettingsService _settings = SettingsService();

  String? get _userId => _auth.currentUser?.uid;

  Stream<RecommendationPreferences> streamPreferences() {
    final uid = _userId;
    if (uid == null) return const Stream.empty();
    return _settings
        .watchCategory(uid, 'recommendations')
        .map((data) => RecommendationPreferences.fromMap(uid, data));
  }

  Future<void> updatePreferences(RecommendationPreferences prefs) async {
    final uid = _userId;
    if (uid == null) return;
    await _settings.updateSettingsCategory(uid, 'recommendations', prefs.toMap());
  }

  Future<void> resetRecommendations() async {
    final uid = _userId;
    if (uid == null) return;
    // Explicit blocks are kept; only the reset time moves.
    await _settings.updateSettingsCategory(uid, 'recommendations', {
      'lastResetTime': FieldValue.serverTimestamp(),
    });
  }

  Future<void> hideTopic(String topic) async {
    final uid = _userId;
    if (uid == null) return;
    await _settings.updateSettingsCategory(uid, 'recommendations', {
      'hiddenTopics': FieldValue.arrayUnion([topic]),
    });
  }

  Future<void> hideCreator(String creatorId) async {
    final uid = _userId;
    if (uid == null) return;
    await _settings.updateSettingsCategory(uid, 'recommendations', {
      'hiddenCreators': FieldValue.arrayUnion([creatorId]),
    });
  }
}
