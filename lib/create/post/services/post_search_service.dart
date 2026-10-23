import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../backend/social/models/social_profile.dart';
import '../../../backend/social/services/global_hashtag_service.dart';

final postSearchServiceProvider = Provider<PostSearchService>((ref) {
  final hashtagService = ref.watch(globalHashtagServiceProvider);
  return PostSearchService(hashtagService: hashtagService);
});

/// Unified search service for:
/// - Inline `@` creator mentions
/// - Collaborator invites
/// - Inline `#` hashtag autocompletions & trending tags
class PostSearchService {
  final FirebaseFirestore _firestore;
  final GlobalHashtagService _hashtagService;

  PostSearchService({
    FirebaseFirestore? firestore,
    GlobalHashtagService? hashtagService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _hashtagService = hashtagService ?? GlobalHashtagService();

  /// Searches creators in Firestore by username or displayName prefix.
  Future<List<SocialProfile>> searchUsers(String query, {int limit = 10}) async {
    final clean = query.trim().replaceAll('@', '').toLowerCase();
    if (clean.isEmpty) return [];

    final endQuery = '$clean\uf8ff';
    final Map<String, SocialProfile> results = {};

    try {
      final snap = await _firestore
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: clean)
          .where('username', isLessThan: endQuery)
          .limit(limit)
          .get();

      for (final doc in snap.docs) {
        results[doc.id] = SocialProfile.fromFirestore(doc);
      }

      if (results.length < limit) {
        final remaining = limit - results.length;
        final nameSnap = await _firestore
            .collection('users')
            .where('displayName', isGreaterThanOrEqualTo: query.trim())
            .where('displayName', isLessThan: '${query.trim()}\uf8ff')
            .limit(remaining)
            .get();

        for (final doc in nameSnap.docs) {
          results[doc.id] = SocialProfile.fromFirestore(doc);
        }
      }
    } catch (_) {}

    return results.values.toList();
  }

  /// Searches hashtags in Firestore `hashtags` collection.
  Future<List<GlobalHashtagModel>> searchHashtags(String query, {int limit = 10}) async {
    return _hashtagService.searchHashtags(query, limit: limit);
  }

  /// Fetches real-time trending hashtags from Firestore.
  Stream<List<GlobalHashtagModel>> watchTrendingHashtags({int limit = 15}) {
    return _hashtagService.watchTrendingHashtags(limit: limit);
  }

  /// Fetches user profiles for a list of user IDs (for displaying selected collabs & tags).
  Future<List<SocialProfile>> fetchProfilesByIds(List<String> userIds) async {
    if (userIds.isEmpty) return [];

    final profiles = <SocialProfile>[];
    for (final id in userIds) {
      try {
        final doc = await _firestore.collection('users').doc(id).get();
        if (doc.exists) {
          profiles.add(SocialProfile.fromFirestore(doc));
        }
      } catch (_) {}
    }
    return profiles;
  }
}
