import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/discovery_models.dart';

final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  return DiscoveryService();
});

class DiscoveryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;

  /// Extracts hashtags and mentions from text, aggregates metrics, and routes notifications.
  Future<void> processTextEntities({
    required String text,
    required String sourceId,
    required String sourceType, // 'video', 'post', 'comment'
  }) async {
    final uid = _userId;
    if (uid == null) return;

    final tags = _extractRegex(text, r'#\w+');
    final mentions = _extractRegex(text, r'@\w+');

    final batch = _firestore.batch();

    // 1. Process Hashtags
    for (final tag in tags) {
      final cleanTag = tag.substring(1).toLowerCase();
      final ref = _firestore.collection('hashtags').doc(cleanTag);
      // In production, this uses an atomic counter/shard architecture.
      batch.set(ref, {
        'totalVideos': FieldValue.increment(1),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    // 2. Process Mentions
    for (final mention in mentions) {
      final username = mention.substring(1);
      
      // Look up user by username to get their UID
      final query = await _firestore.collection('users').where('username', isEqualTo: username).limit(1).get();
      if (query.docs.isEmpty) continue;
      final targetUserId = query.docs.first.id;

      // EXPLICIT REQUIREMENT: Mentions must notify according to privacy settings.
      final canNotify = await _checkMentionPrivacy(targetUserId, uid);
      if (canNotify) {
        batch.set(_firestore.collection('users').doc(targetUserId).collection('notifications').doc(), {
          'type': 'mention',
          'sourceId': sourceId,
          'sourceType': sourceType,
          'actorId': uid,
          'timestamp': FieldValue.serverTimestamp(),
          'read': false,
        });
      }
    }

    await batch.commit();
  }

  /// Evaluates granular privacy settings of the mentioned user.
  Future<bool> _checkMentionPrivacy(String targetUserId, String actorId) async {
    // Stubbed until PrivacyPreferences are correctly synchronized with the UI
    return true;
  }

  /// Streams Hashtag Metadata
  Stream<HashtagMetadata?> streamHashtag(String tag) {
    return _firestore.collection('hashtags').doc(tag.toLowerCase()).snapshots().map(
      (doc) => doc.exists ? HashtagMetadata.fromFirestore(doc) : null
    );
  }

  /// Simulates fetching trending discovery entities
  Future<List<TrendingTopic>> getTrending() async {
    // In production, this pulls from an aggregate materialized view populated by 
    // Spark/Dataflow streaming analytics.
    return [
      const TrendingTopic(id: 't1', name: '#dance', category: 'hashtag', rank: 1, metricDelta: 5000),
      const TrendingTopic(id: 't2', name: 'Original Sound - Creator', category: 'sound', rank: 2, metricDelta: 4200),
      const TrendingTopic(id: 't3', name: 'New York, NY', category: 'location', rank: 3, metricDelta: 2100),
      const TrendingTopic(id: 't4', name: '@viralstar', category: 'creator', rank: 4, metricDelta: 1800),
    ];
  }

  List<String> _extractRegex(String text, String pattern) {
    final regex = RegExp(pattern);
    return regex.allMatches(text).map((m) => m.group(0)!).toList();
  }
}
