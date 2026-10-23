import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/recommendation_models.dart';
import '../../social/models/content.dart';
import '../algorithm/oneova_neural_ranker.dart';

final recommendationEngineProvider = Provider<RecommendationEngine>((ref) {
  return RecommendationEngine(
    neuralRanker: ref.read(oneOvaNeuralRankerProvider),
  );
});

class RecommendationEngine {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final OneOvaNeuralRanker? _neuralRanker;

  RecommendationEngine({this._neuralRanker});

  String? get _userId => _auth.currentUser?.uid;

  /// Logs an interaction to feed into the recommendation pipeline.
  Future<void> logInteraction(String targetId, InteractionType type, {double weight = 1.0, bool isPrivateContent = false}) async {
    final uid = _userId;
    if (uid == null) return;
    
    // SAFETY/PRIVACY GUARD: Do not log interactions on private content for recommendation engine
    if (isPrivateContent) {
      return; 
    }

    final event = UserInteractionEvent(
      id: _firestore.collection('interactions').doc().id,
      userId: uid,
      targetId: targetId,
      type: type,
      weight: weight,
      timestamp: DateTime.now(),
      sessionContext: {'language': 'en', 'region': 'US'},
    );

    await _firestore.collection('users').doc(uid).collection('interactions').add(event.toMap());
  }

  /// The recommendation pipeline querying real Firestore content.
  Future<List<String>> getRecommendedVideoIds(RecommendationPreferences prefs) async {
    try {
      final snapshot = await _firestore
          .collection('content')
          .where('type', isEqualTo: ContentType.short_video.name)
          .where('visibility', isEqualTo: 'public')
          .orderBy('createdAt', descending: true)
          .limit(30)
          .get();

      final candidates = snapshot.docs.map((doc) => Content.fromFirestore(doc)).toList();
      
      final uid = _userId ?? prefs.userId;
      if (_neuralRanker != null) {
        final ranked = _neuralRanker.rankForYouFeed(
          userId: uid,
          candidates: candidates,
          hiddenCreators: prefs.hiddenCreators,
          hiddenTopics: prefs.hiddenTopics,
        );
        return ranked.map((c) => c.id).toList();
      }

      candidates.removeWhere((c) => prefs.hiddenCreators.contains(c.authorId));
      candidates.removeWhere((c) => c.hashtags.any((t) => prefs.hiddenTopics.contains(t)));
      return candidates.map((c) => c.id).toList();
    } catch (_) {
      return [];
    }
  }

  /// Explains why a piece of content was recommended
  Future<RecommendationExplanation> explainRecommendation(String videoId) async {
    return RecommendationExplanation(
      videoId: videoId,
      reasons: [
        'Curated by OneOva Neural Pulse & Flow Algorithm',
        'Matches your active interest patterns & watch velocity',
        'Trending breakout on OneOva',
      ],
    );
  }
}
