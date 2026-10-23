import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum FeedbackAction {
  ACCEPTED,
  EDITED,
  REJECTED,
  REGENERATED,
  CHANGED_TONE,
  SHORTENED,
  EXPANDED,
  CHANGED_LANGUAGE,
}

class LearningCandidate {
  final String id;
  final String userId;
  final String inferredPreference;
  final double confidence;
  final int occurrences;
  final bool userConfirmed;
  final DateTime firstObservedAt;
  final DateTime lastObservedAt;

  LearningCandidate({
    required this.id,
    required this.userId,
    required this.inferredPreference,
    required this.confidence,
    required this.occurrences,
    required this.userConfirmed,
    required this.firstObservedAt,
    required this.lastObservedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'inferred_preference': inferredPreference,
      'confidence': confidence,
      'occurrences': occurrences,
      'user_confirmed': userConfirmed,
      'first_observed_at': Timestamp.fromDate(firstObservedAt),
      'last_observed_at': Timestamp.fromDate(lastObservedAt),
    };
  }

  factory LearningCandidate.fromMap(String id, Map<String, dynamic> map) {
    return LearningCandidate(
      id: id,
      userId: map['user_id'] ?? '',
      inferredPreference: map['inferred_preference'] ?? '',
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
      occurrences: map['occurrences'] ?? 1,
      userConfirmed: map['user_confirmed'] ?? false,
      firstObservedAt: (map['first_observed_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastObservedAt: (map['last_observed_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

final feedbackLearningLoopProvider = Provider<FeedbackLearningLoop>((ref) {
  return FeedbackLearningLoop(FirebaseFirestore.instance);
});

class FeedbackLearningLoop {
  final FirebaseFirestore _firestore;
  static const int _promotionThreshold = 3; // Occurrences required before promoting to memory
  static const double _baseConfidenceIncrement = 0.2;

  FeedbackLearningLoop(this._firestore);

  Future<void> recordFeedbackEvent({
    required String userId,
    required FeedbackAction action,
    required String originalDraft,
    required String finalResult,
    required String contextId,
  }) async {
    // 1. Analyze the difference (in a real scenario, this would use a fast LLM call or heuristics)
    String? inferredPreference = _inferPreference(action, originalDraft, finalResult);
    
    if (inferredPreference == null) return;

    // 2. Query existing candidates for this user
    final query = await _firestore
        .collection('users')
        .doc(userId)
        .collection('learning_candidates')
        .where('inferred_preference', isEqualTo: inferredPreference)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      // 3. Update existing candidate
      final doc = query.docs.first;
      final currentOccurrences = doc.data()['occurrences'] ?? 1;
      final currentConfidence = (doc.data()['confidence'] as num?)?.toDouble() ?? 0.0;
      
      final newOccurrences = currentOccurrences + 1;
      final newConfidence = (currentConfidence + _baseConfidenceIncrement).clamp(0.0, 1.0);
      
      await doc.reference.update({
        'occurrences': newOccurrences,
        'confidence': newConfidence,
        'last_observed_at': FieldValue.serverTimestamp(),
      });

      // 4. Promote to durable memory if threshold met
      if (newOccurrences >= _promotionThreshold || newConfidence >= 0.8) {
        await _promoteToMemory(userId, inferredPreference, newConfidence);
      }
    } else {
      // 5. Create new candidate
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('learning_candidates')
          .add({
        'user_id': userId,
        'inferred_preference': inferredPreference,
        'confidence': _baseConfidenceIncrement,
        'occurrences': 1,
        'user_confirmed': false,
        'first_observed_at': FieldValue.serverTimestamp(),
        'last_observed_at': FieldValue.serverTimestamp(),
      });
    }
  }

  String? _inferPreference(FeedbackAction action, String original, String updated) {
    // Basic heuristic simulation. An LLM would extract this.
    switch (action) {
      case FeedbackAction.SHORTENED:
        return 'Prefers concise, shorter responses.';
      case FeedbackAction.EXPANDED:
        return 'Prefers detailed, elaborate responses.';
      case FeedbackAction.CHANGED_TONE:
        return 'Adjusted tone (requires deeper semantic analysis).';
      case FeedbackAction.EDITED:
        if (updated.toLowerCase().contains('bro') || updated.toLowerCase().contains('hey')) {
          return 'Prefers casual, friendly greetings.';
        }
        return 'Custom phrasing preference.';
      default:
        return null;
    }
  }

  Future<void> _promoteToMemory(String userId, String preference, double confidence) async {
    // In reality, this would interface with PersonalMemoryEngine to insert a COMMUNICATION type memory.
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('memories')
        .add({
      'user_id': userId,
      'type': 'COMMUNICATION',
      'content': preference,
      'source': 'FeedbackLearningLoop',
      'confidence': confidence,
      'permission': 'USER_APPROVED_AI_CONTEXT',
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'confirmed_by_user': false, // Still waiting for explicit user confirmation in UI
    });
  }
  
  Future<void> deleteCandidate(String userId, String candidateId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('learning_candidates')
        .doc(candidateId)
        .delete();
  }
}
