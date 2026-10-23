import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'search_models.dart';

final globalSearchServiceProvider = Provider((ref) => GlobalSearchService());

class GlobalSearchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Keeps search indexing synchronized with real data lifecycle events.
  /// Call this when a message, post, or channel is created/updated.
  Future<void> indexRecord(SearchResultItem item) async {
    // In production, this might push to Algolia/Elasticsearch or a dedicated 
    // Firestore `_search_index` collection. We use Firestore here.
    await _firestore.collection('_search_index').doc(item.id).set({
      'type': item.type.name,
      'title': item.title,
      'snippet': item.snippet,
      'timestamp': item.timestamp.millisecondsSinceEpoch,
      'metadata': item.metadata,
      'allowedViewers': item.allowedViewers,
    }, SetOptions(merge: true));
  }

  /// Removes a record from the search index (e.g. when a message is deleted).
  Future<void> removeRecord(String id) async {
    await _firestore.collection('_search_index').doc(id).delete();
  }

  /// Executes a global search spanning the requested entities.
  Future<PaginatedSearchResults> executeSearch(SearchQuery query) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception("User must be authenticated to perform searches.");
    }
    
    final uid = user.uid;

    // 1. Build the base query against the index.
    // SECURITY ENFORCEMENT: 
    // "Never return a private record simply because the search engine indexed it."
    // By enforcing `arrayContains: uid` at the query level, it is mathematically 
    // impossible to retrieve a record the user does not have permission to view,
    // regardless of what text matched.
    Query ref = _firestore
        .collection('_search_index')
        .where('allowedViewers', arrayContains: uid);

    // Apply entity type filters
    if (query.targetEntities.isNotEmpty) {
      final typeNames = query.targetEntities.map((e) => e.name).toList();
      // Note: Firestore limits 'whereIn' to 10 items.
      ref = ref.where('type', whereIn: typeNames);
    }

    // Apply date range filters
    if (query.filter.startDate != null) {
      ref = ref.where('timestamp', isGreaterThanOrEqualTo: query.filter.startDate!.millisecondsSinceEpoch);
    }
    if (query.filter.endDate != null) {
      ref = ref.where('timestamp', isLessThanOrEqualTo: query.filter.endDate!.millisecondsSinceEpoch);
    }

    // Sort by relevance / time
    ref = ref.orderBy('timestamp', descending: true);

    // Pagination limit
    ref = ref.limit(query.limit);

    // Apply pagination cursor if present
    if (query.pageToken != null && query.pageToken!.isNotEmpty) {
      // In a real implementation, the token would deserialize to a DocumentSnapshot or offset.
      // We simulate cursor pagination here.
      // ref = ref.startAfterDocument(decodedCursor);
    }

    // 2. Execute Query
    final snapshot = await ref.get();

    // 3. Post-query filtering for exact matches, semantic search limits, sender/channel IDs
    // Since Firestore doesn't support full-text search directly without extensions,
    // we do application-level filtering on the results returned. (In prod, this is done via Algolia/Elastic).
    List<SearchResultItem> processedResults = snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return SearchResultItem(
        id: doc.id,
        type: SearchEntityType.values.firstWhere((e) => e.name == data['type']),
        title: data['title'] ?? '',
        snippet: data['snippet'] ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(data['timestamp']),
        metadata: data['metadata'] ?? {},
        allowedViewers: List<String>.from(data['allowedViewers'] ?? []),
      );
    }).toList();

    // Text filtering
    if (query.query.isNotEmpty) {
      final searchTerm = query.filter.exactMatch ? query.query : query.query.toLowerCase();
      
      processedResults = processedResults.where((item) {
        final textTarget = query.filter.exactMatch 
          ? item.snippet 
          : item.snippet.toLowerCase();
          
        if (query.filter.enableSemanticSearch) {
          // If semantic search is explicitly enabled, we would route to a vector DB 
          // or use embeddings. For now, it passes.
          return true;
        } else {
          return textTarget.contains(searchTerm) || 
                 (query.filter.exactMatch ? item.title : item.title.toLowerCase()).contains(searchTerm);
        }
      }).toList();
    }

    // Channel / Sender filtering
    if (query.filter.channelIds.isNotEmpty) {
      processedResults = processedResults.where((item) => query.filter.channelIds.contains(item.metadata['channelId'])).toList();
    }
    if (query.filter.senderIds.isNotEmpty) {
      processedResults = processedResults.where((item) => query.filter.senderIds.contains(item.metadata['senderId'])).toList();
    }
    
    // Attachment filtering
    if (query.filter.hasAttachment != null) {
      processedResults = processedResults.where((item) {
        final hasMedia = (item.metadata['mediaCount'] ?? 0) > 0;
        return hasMedia == query.filter.hasAttachment;
      }).toList();
    }

    // Pagination token generation
    String? nextToken;
    if (snapshot.docs.length == query.limit) {
      nextToken = snapshot.docs.last.id;
    }

    return PaginatedSearchResults(
      results: processedResults,
      nextPageToken: nextToken,
      totalEstimatedHits: processedResults.length, // Simulated hit count
    );
  }
}
