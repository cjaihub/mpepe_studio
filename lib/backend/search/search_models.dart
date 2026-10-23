
enum SearchEntityType {
  message,
  person,
  conversation,
  file,
  channel,
  post,
  notification,
  aiHistory,
}

class SearchFilter {
  final DateTime? startDate;
  final DateTime? endDate;
  final List<String> channelIds;
  final List<String> senderIds;
  final bool? hasAttachment;
  final bool exactMatch;
  final bool enableSemanticSearch;

  const SearchFilter({
    this.startDate,
    this.endDate,
    this.channelIds = const [],
    this.senderIds = const [],
    this.hasAttachment,
    this.exactMatch = false,
    this.enableSemanticSearch = false,
  });
}

class SearchQuery {
  final String query;
  final List<SearchEntityType> targetEntities;
  final SearchFilter filter;
  final int limit;
  final String? pageToken; // For pagination

  const SearchQuery({
    required this.query,
    this.targetEntities = const [
      SearchEntityType.message,
      SearchEntityType.person,
      SearchEntityType.conversation,
      SearchEntityType.file,
      SearchEntityType.channel,
      SearchEntityType.post,
      SearchEntityType.notification,
      SearchEntityType.aiHistory,
    ],
    this.filter = const SearchFilter(),
    this.limit = 20,
    this.pageToken,
  });
}

class SearchResultItem {
  final String id;
  final SearchEntityType type;
  final String title;
  final String snippet;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;
  
  // The ACL (Access Control List) embedded during indexing.
  final List<String> allowedViewers;

  const SearchResultItem({
    required this.id,
    required this.type,
    required this.title,
    required this.snippet,
    required this.timestamp,
    this.metadata = const {},
    required this.allowedViewers,
  });
}

class PaginatedSearchResults {
  final List<SearchResultItem> results;
  final String? nextPageToken;
  final int totalEstimatedHits;

  const PaginatedSearchResults({
    required this.results,
    this.nextPageToken,
    required this.totalEstimatedHits,
  });
}
