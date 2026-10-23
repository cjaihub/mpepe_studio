import 'package:cloud_firestore/cloud_firestore.dart';

enum SearchEntityType {
  message,
  person,
  channel,
  file,
  post,
  video,
  hashtag,
  notification,
  aiHistory,
  unknown
}

class SearchResult {
  final String id;
  final SearchEntityType type;
  final String title;
  final String? subtitle;
  final String content;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const SearchResult({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    required this.content,
    required this.metadata,
    required this.createdAt,
  });

  factory SearchResult.fromMap(Map<String, dynamic> map, String docId) {
    SearchEntityType parsedType;
    try {
      final typeStr = map['type'] as String? ?? '';
      parsedType = SearchEntityType.values.firstWhere(
        (e) => e.name.toLowerCase() == typeStr.replaceAll('_', '').toLowerCase(),
        orElse: () => SearchEntityType.unknown,
      );
    } catch (_) {
      parsedType = SearchEntityType.unknown;
    }

    DateTime parsedDate;
    if (map['createdAt'] is Timestamp) {
      parsedDate = (map['createdAt'] as Timestamp).toDate();
    } else if (map['createdAt'] is int) {
      // Sometimes semantic search from cloud functions returns raw milliseconds
      parsedDate = DateTime.fromMillisecondsSinceEpoch(map['createdAt']);
    } else {
      parsedDate = DateTime.now();
    }

    return SearchResult(
      id: map['id'] ?? docId,
      type: parsedType,
      title: map['title'] ?? '',
      subtitle: map['subtitle'],
      content: map['content'] ?? '',
      metadata: map['metadata'] as Map<String, dynamic>? ?? {},
      createdAt: parsedDate,
    );
  }
}
