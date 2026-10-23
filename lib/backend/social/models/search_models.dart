enum SearchResultType {
  user,
  product,
  video,
  sound,
  hashtag,
  comment,
  message,
  channel,
  playlist,
  series,
  liveStream,
  post,
}

enum AutocompleteResultType {
  username,
  hashtag,
  sound,
  topic,
}

enum TrendingItemType {
  video,
  creator,
  hashtag,
  sound,
  topic,
}

class AutocompleteResult {
  final String text;
  final AutocompleteResultType type;
  final String? subtitle;
  final String? imageUrl;

  const AutocompleteResult({
    required this.text,
    required this.type,
    this.subtitle,
    this.imageUrl,
  });
}

class TrendingItem {
  final String id;
  final TrendingItemType type;
  final String title;
  final String subtitle;
  final int interactionCount;
  final String? imageUrl;

  const TrendingItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.interactionCount,
    this.imageUrl,
  });
}

class SearchResult {
  final String id;
  final SearchResultType type;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final double relevanceScore; // used for ranking
  final bool isSafe; // safety check
  final bool isPrivate; // privacy check

  const SearchResult({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    this.relevanceScore = 0.0,
    this.isSafe = true,
    this.isPrivate = false,
  });
}
