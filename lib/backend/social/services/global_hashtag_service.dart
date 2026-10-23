import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final globalHashtagServiceProvider = Provider<GlobalHashtagService>((ref) {
  return GlobalHashtagService();
});

/// Data model representing a global trending hashtag tracked in Firestore.
class GlobalHashtagModel {
  final String tag;
  final int postCount;
  final double velocityPerHour;
  final String category;
  final DateTime lastUsedAt;
  final double trendingScore;

  const GlobalHashtagModel({
    required this.tag,
    required this.postCount,
    required this.velocityPerHour,
    required this.category,
    required this.lastUsedAt,
    required this.trendingScore,
  });

  factory GlobalHashtagModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return GlobalHashtagModel(
      tag: (data['tag'] as String?) ?? doc.id,
      postCount: (data['postCount'] as num?)?.toInt() ?? 0,
      velocityPerHour: (data['velocityPerHour'] as num?)?.toDouble() ?? 0.0,
      category: (data['category'] as String?) ?? 'general',
      lastUsedAt: (data['lastUsedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      trendingScore: (data['trendingScore'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tag': tag,
      'postCount': postCount,
      'velocityPerHour': velocityPerHour,
      'category': category,
      'lastUsedAt': Timestamp.fromDate(lastUsedAt),
      'trendingScore': trendingScore,
    };
  }
}

/// Global Hashtag Velocity & Trending Engine for Oneova.
///
/// Tracks real-time hashtag usage across the platform, computes hourly velocity
/// with time-decay dynamics, and powers real-time discovery feeds.
class GlobalHashtagService {
  final FirebaseFirestore _firestore;

  GlobalHashtagService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String _collectionName = 'hashtags';

  /// Normalizes a hashtag string: strips '#' symbols, trims whitespace, and converts to lowercase.
  static String normalizeTag(String rawTag) {
    return rawTag.trim().toLowerCase().replaceAll(RegExp(r'^#+'), '');
  }

  /// Categorizes a hashtag heuristically based on keywords if no category is provided.
  static String categorizeTag(String tag) {
    final t = tag.toLowerCase();
    if (t.contains('music') || t.contains('song') || t.contains('audio') || t.contains('beat')) {
      return 'music';
    }
    if (t.contains('dance') || t.contains('choreography')) {
      return 'dance';
    }
    if (t.contains('tech') || t.contains('ai') || t.contains('code') || t.contains('app')) {
      return 'technology';
    }
    if (t.contains('art') || t.contains('design') || t.contains('photo') || t.contains('film')) {
      return 'creative';
    }
    if (t.contains('comedy') || t.contains('funny') || t.contains('humor') || t.contains('meme')) {
      return 'comedy';
    }
    if (t.contains('fashion') || t.contains('style') || t.contains('fit') || t.contains('beauty')) {
      return 'lifestyle';
    }
    return 'general';
  }

  /// Records usage of one or more hashtags atomically.
  ///
  /// Increments postCount, updates lastUsedAt, and calculates updated velocityPerHour
  /// using an exponential time-decay moving average.
  Future<void> recordHashtagsUsed(List<String> tags, {String? category}) async {
    if (tags.isEmpty) return;

    final Set<String> uniqueTags = tags
        .map(normalizeTag)
        .where((t) => t.isNotEmpty && RegExp(r'^[a-z0-9_]+$').hasMatch(t))
        .toSet();

    for (final cleanTag in uniqueTags) {
      final docRef = _firestore.collection(_collectionName).doc(cleanTag);

      await _firestore.runTransaction((tx) async {
        final snapshot = await tx.get(docRef);
        final now = DateTime.now();

        if (!snapshot.exists) {
          final assignedCategory = category ?? categorizeTag(cleanTag);
          tx.set(docRef, {
            'tag': cleanTag,
            'postCount': 1,
            'velocityPerHour': 1.0,
            'category': assignedCategory,
            'lastUsedAt': FieldValue.serverTimestamp(),
            'trendingScore': 1.0,
          });
        } else {
          final data = snapshot.data() ?? {};
          final prevCount = (data['postCount'] as num?)?.toInt() ?? 0;
          final prevVelocity = (data['velocityPerHour'] as num?)?.toDouble() ?? 0.0;
          final prevTime = (data['lastUsedAt'] as Timestamp?)?.toDate() ?? now;

          // Elapsed time in hours (minimum 60 seconds to avoid division by near-zero)
          final elapsedHours = math.max(1.0 / 60.0, now.difference(prevTime).inSeconds / 3600.0);

          // 6-hour half-life exponential decay factor
          final decay = math.exp(-0.1155 * elapsedHours);
          final incrementalRate = 1.0 / elapsedHours;
          final newVelocity = (prevVelocity * decay) + incrementalRate;

          final newCount = prevCount + 1;
          // Trending score combines real-time velocity with logarithmic post volume
          final trendingScore = (newVelocity * 0.70) + (math.log(newCount + 1) * 3.0);

          tx.update(docRef, {
            'postCount': FieldValue.increment(1),
            'velocityPerHour': double.parse(newVelocity.toStringAsFixed(3)),
            'lastUsedAt': FieldValue.serverTimestamp(),
            'trendingScore': double.parse(trendingScore.toStringAsFixed(3)),
            'category': ?category,
          });
        }
      });
    }
  }

  /// Returns a real-time stream of trending hashtags ordered by trendingScore descending.
  Stream<List<GlobalHashtagModel>> watchTrendingHashtags({int limit = 20}) {
    return _firestore
        .collection(_collectionName)
        .orderBy('trendingScore', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => GlobalHashtagModel.fromFirestore(doc)).toList());
  }

  /// Searches hashtags by prefix query, returning matches with their live post counts.
  Future<List<GlobalHashtagModel>> searchHashtags(String query, {int limit = 20}) async {
    final clean = normalizeTag(query);
    if (clean.isEmpty) return [];

    final endClean = '$clean\uf8ff';

    final snapshot = await _firestore
        .collection(_collectionName)
        .where('tag', isGreaterThanOrEqualTo: clean)
        .where('tag', isLessThan: endClean)
        .limit(limit * 2)
        .get();

    final results = snapshot.docs
        .map((doc) => GlobalHashtagModel.fromFirestore(doc))
        .toList();

    // Sort by postCount descending to present the most popular tags first
    results.sort((a, b) => b.postCount.compareTo(a.postCount));

    return results.take(limit).toList();
  }

  /// Fetches a specific hashtag document by its name.
  Future<GlobalHashtagModel?> getHashtag(String tag) async {
    final clean = normalizeTag(tag);
    if (clean.isEmpty) return null;

    final doc = await _firestore.collection(_collectionName).doc(clean).get();
    if (!doc.exists) return null;
    return GlobalHashtagModel.fromFirestore(doc);
  }
}
