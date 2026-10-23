enum SearchEntityType {
  person,
  video,
  post,
  sound,
  hashtag,
  message,
  comment,
  file,
  place,
  event,
  community,
  channel,
  externalMetadata,
}

enum SearchMethod {
  exact,
  fuzzy,
  semantic,
}

class SearchQuery {
  final String query;
  final List<SearchEntityType>? typeFilters;
  final SearchMethod method;
  final String requestorId; // Crucial for permission filtering

  const SearchQuery({
    required this.query,
    this.typeFilters,
    this.method = SearchMethod.fuzzy,
    required this.requestorId,
  });
}

class SearchResultItem {
  final String id;
  final SearchEntityType type;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final double relevanceScore; // 0.0 to 1.0

  /// Indicates if this result is from an external connected platform (e.g. YouTube)
  final bool isExternal; 

  const SearchResultItem({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    this.imageUrl,
    required this.relevanceScore,
    this.isExternal = false,
  });
}

class SearchResponse {
  final String query;
  final List<SearchResultItem> results;
  final int totalHits;
  final bool isTruncated; // If results were capped due to privacy or performance

  const SearchResponse({
    required this.query,
    required this.results,
    required this.totalHits,
    this.isTruncated = false,
  });
}
