import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/search_models.dart';

final searchServiceProvider = Provider<SearchService>((ref) {
  return SearchService();
});

class SearchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Prefix suggestions from real accounts and hashtags.
  Future<List<AutocompleteResult>> getAutocomplete(String query) async {
    final q = query.trim().toLowerCase().replaceFirst(RegExp(r'^[@#]'), '');
    if (q.isEmpty) return [];
    final end = '$q\uf8ff';
    final out = <AutocompleteResult>[];
    try {
      final users = await _firestore
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: q)
          .where('username', isLessThan: end)
          .limit(5)
          .get();
      for (final d in users.docs) {
        final u = d.data()['username'] as String?;
        if (u == null || u.isEmpty) continue;
        out.add(AutocompleteResult(
          text: '@$u',
          type: AutocompleteResultType.username,
          subtitle: d.data()['displayName'] as String?,
          imageUrl: d.data()['profilePhotoUrl'] as String?,
        ));
      }
      final tags = await _firestore
          .collection('hashtags')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: q)
          .where(FieldPath.documentId, isLessThan: end)
          .limit(5)
          .get();
      for (final d in tags.docs) {
        out.add(AutocompleteResult(text: '#${d.id}', type: AutocompleteResultType.hashtag));
      }
    } catch (e) {
      debugPrint('Autocomplete error: $e');
    }
    return out;
  }

  /// Most viewed hashtags right now; empty until real activity exists.
  Future<List<TrendingItem>> getTrending() async {
    try {
      final snap = await _firestore
          .collection('hashtags')
          .orderBy('totalViews', descending: true)
          .limit(10)
          .get();
      return [
        for (final d in snap.docs)
          TrendingItem(
            id: d.id,
            type: TrendingItemType.hashtag,
            title: '#${d.id}',
            subtitle: '${(d.data()['totalVideos'] as num?)?.toInt() ?? 0} videos',
            interactionCount: (d.data()['totalViews'] as num?)?.toInt() ?? 0,
          ),
      ];
    } catch (e) {
      debugPrint('Trending error: $e');
      return [];
    }
  }

  Future<List<SearchResult>> search(String query, {List<SearchResultType>? filters}) async {
    if (query.isEmpty) return [];

    final q = query.toLowerCase();
    final endQ = '$q\\uf8ff';

    List<SearchResult> results = [];

    try {
      // 1. Query Users
      if (filters == null || filters.contains(SearchResultType.user)) {
        final usersSnap = await _firestore.collection('users')
            .where('username', isGreaterThanOrEqualTo: q)
            .where('username', isLessThan: endQ)
            .limit(10)
            .get();
        for (var doc in usersSnap.docs) {
          final data = doc.data();
          results.add(SearchResult(
            id: doc.id,
            type: SearchResultType.user,
            title: '@${data['username'] ?? 'unknown'}',
            subtitle: data['fullName'] ?? 'User',
            imageUrl: data['profilePhotoUrl'],
            relevanceScore: 10.0,
          ));
        }
      }

      // 2. Query Products (Biz)
      if (filters == null || filters.contains(SearchResultType.product)) {
        final productsSnap = await _firestore.collection('products')
            .where('name_lowercase', isGreaterThanOrEqualTo: q)
            .where('name_lowercase', isLessThan: endQ)
            .limit(10)
            .get();
        for (var doc in productsSnap.docs) {
          final data = doc.data();
          results.add(SearchResult(
            id: doc.id,
            type: SearchResultType.product,
            title: data['name'] ?? 'Product',
            subtitle: data['description'] ?? 'Business Product',
            imageUrl: data['imageUrl'],
            relevanceScore: 9.0,
          ));
        }
      }

      // 3. Query Public Content (Posts/Videos)
      if (filters == null || filters.contains(SearchResultType.video) || filters.contains(SearchResultType.post)) {
        final contentSnap = await _firestore.collection('content')
            .where('keywords', arrayContains: q)
            .limit(15)
            .get();
        for (var doc in contentSnap.docs) {
          final data = doc.data();
          final typeStr = data['type'] as String? ?? 'post';
          final type = typeStr == 'video' || typeStr == 'short_video' ? SearchResultType.video : SearchResultType.post;
          
          if (filters != null && !filters.contains(type)) continue;

          results.add(SearchResult(
            id: doc.id,
            type: type,
            title: data['description']?.toString() ?? 'Content',
            subtitle: 'By ${data['authorId'] ?? 'Unknown'}',
            imageUrl: (data['mediaMetadata'] as Map<String, dynamic>?)?['thumbnailUrl'],
            relevanceScore: 8.0,
          ));
        }
      }
    } catch (e) {
      debugPrint('Search error: $e');
    }

    results.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
    return results;
  }
}
