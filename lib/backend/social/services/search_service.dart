import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/search_models.dart';

final searchServiceProvider = Provider<SearchService>((ref) {
  return SearchService();
});

class SearchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<AutocompleteResult>> getAutocomplete(String query) async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (query.isEmpty) return [];

    return [
      AutocompleteResult(text: '${query}tutorials', type: AutocompleteResultType.topic),
      AutocompleteResult(text: '#${query}vibes', type: AutocompleteResultType.hashtag),
      AutocompleteResult(text: '@${query}creator', type: AutocompleteResultType.username),
    ];
  }

  Future<List<TrendingItem>> getTrending() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return [
      TrendingItem(
        id: 'trend_1',
        type: TrendingItemType.hashtag,
        title: '#ONEROVA2026',
        subtitle: 'Trending worldwide',
        interactionCount: 1500000,
      ),
      TrendingItem(
        id: 'trend_2',
        type: TrendingItemType.sound,
        title: 'Epic Cinematic Theme',
        subtitle: 'Trending in Filmmaking',
        interactionCount: 450000,
        imageUrl: 'https://picsum.photos/100?random=1',
      ),
      TrendingItem(
        id: 'trend_3',
        type: TrendingItemType.creator,
        title: '@filmmaker_pro',
        subtitle: 'Trending Creator',
        interactionCount: 89000,
        imageUrl: 'https://i.pravatar.cc/100',
      ),
    ];
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
      print('Search error: $e');
    }

    results.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
    return results;
  }
}
