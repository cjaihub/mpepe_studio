import 'package:oneova/backend/search/models/search_models.dart';
import 'package:oneova/backend/search/services/search_permission_filter.dart';

class GlobalSearchService {
  final SearchPermissionFilter _permissionFilter;

  GlobalSearchService(this._permissionFilter);

  /// Executes a global search query across all internal and external entity types.
  Future<SearchResponse> search(SearchQuery query) async {
    // 1. Fetch raw unconstrained results from underlying databases/indices (Stubbed)
    List<SearchResultItem> rawResults = await _fetchFromIndices(query);

    // 2. Enforce Privacy constraints BEFORE sorting or formatting
    List<SearchResultItem> filteredResults = _permissionFilter.applyPreResponseFilter(
      rawResults: rawResults,
      requestorId: query.requestorId,
    );

    // 3. Apply post-filtering type limits
    if (query.typeFilters != null && query.typeFilters!.isNotEmpty) {
      filteredResults = filteredResults.where((r) => query.typeFilters!.contains(r.type)).toList();
    }

    // 4. Sort by relevance
    filteredResults.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));

    // 5. Build response
    return SearchResponse(
      query: query.query,
      results: filteredResults,
      totalHits: filteredResults.length,
      isTruncated: rawResults.length != filteredResults.length, // Truncated due to privacy filters
    );
  }

  /// Stub for underlying distributed index queries (Algolia/ElasticSearch/Firestore)
  Future<List<SearchResultItem>> _fetchFromIndices(SearchQuery query) async {
    // Simulated multi-index query based on matching methods
    final keyword = query.query.toLowerCase();
    
    // Example dataset representing the requested types
    final allEntities = [
      SearchResultItem(id: 'usr_1', type: SearchEntityType.person, title: 'John Doe', relevanceScore: 0.9),
      SearchResultItem(id: 'vid_public', type: SearchEntityType.video, title: 'Epic $keyword montage', relevanceScore: 0.8),
      SearchResultItem(id: 'vid_private_${query.requestorId}', type: SearchEntityType.video, title: 'My hidden $keyword video', relevanceScore: 0.95), // Allowed for owner
      SearchResultItem(id: 'vid_private_other', type: SearchEntityType.video, title: 'Hidden $keyword video', relevanceScore: 0.95), // Blocked for owner
      SearchResultItem(id: 'post_1', type: SearchEntityType.post, title: 'Thoughts on $keyword', relevanceScore: 0.7),
      SearchResultItem(id: 'snd_1', type: SearchEntityType.sound, title: '$keyword remix', relevanceScore: 0.6),
      SearchResultItem(id: 'tag_1', type: SearchEntityType.hashtag, title: '#$keyword', relevanceScore: 1.0),
      SearchResultItem(id: 'msg_private_other', type: SearchEntityType.message, title: 'Private conversation about $keyword', relevanceScore: 0.8), // Blocked
      SearchResultItem(id: 'msg_private_${query.requestorId}', type: SearchEntityType.message, title: 'My conversation about $keyword', relevanceScore: 0.8), // Allowed
      SearchResultItem(id: 'cmt_1', type: SearchEntityType.comment, title: 'Great $keyword!', relevanceScore: 0.5),
      SearchResultItem(id: 'file_1', type: SearchEntityType.file, title: '${keyword}_project.zip', relevanceScore: 0.6),
      SearchResultItem(id: 'plc_1', type: SearchEntityType.place, title: '$keyword Studio', relevanceScore: 0.7),
      SearchResultItem(id: 'evt_1', type: SearchEntityType.event, title: '$keyword Meetup', relevanceScore: 0.85),
      SearchResultItem(id: 'com_1', type: SearchEntityType.community, title: '$keyword Fans', relevanceScore: 0.75),
      SearchResultItem(id: 'chn_1', type: SearchEntityType.channel, title: '$keyword Official', relevanceScore: 0.9),
      SearchResultItem(id: 'ext_yt_${query.requestorId}', type: SearchEntityType.externalMetadata, title: 'YouTube Draft: $keyword', isExternal: true, relevanceScore: 0.9), // Allowed
      SearchResultItem(id: 'ext_yt_other', type: SearchEntityType.externalMetadata, title: 'YouTube Draft: $keyword', isExternal: true, relevanceScore: 0.9), // Blocked
    ];

    if (query.method == SearchMethod.exact) {
      return allEntities.where((e) => e.title.toLowerCase() == keyword).toList();
    } else if (query.method == SearchMethod.semantic) {
      // Stub for vector search: returns highly relevant items even if no exact keyword match
      return allEntities.where((e) => e.relevanceScore > 0.8).toList();
    } else {
      // Fuzzy (default)
      return allEntities.where((e) => e.title.toLowerCase().contains(keyword)).toList();
    }
  }
}
