// ignore_for_file: avoid_print
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/search_result.dart';

import '../social/services/global_hashtag_service.dart';

final searchServiceProvider = Provider<SearchService>((ref) {
  return SearchService();
});

class SearchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<List<SearchResult>> exactSearch({
    required String query,
    SearchEntityType? type,
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    final rawQ = query.trim();
    if (rawQ.isEmpty) return [];

    final q = rawQ.toLowerCase();
    final cleanTag = GlobalHashtagService.normalizeTag(rawQ);
    final isTagQuery = rawQ.startsWith('#');
    final endQ = '$q\uf8ff';

    final List<SearchResult> results = [];
    final Set<String> seenIds = {};

    try {
      // 1. Hashtags
      if (type == null || type == SearchEntityType.hashtag) {
        final hashtagService = GlobalHashtagService(firestore: _firestore);
        final tagQuery = isTagQuery ? cleanTag : q;
        final matchedTags = await hashtagService.searchHashtags(tagQuery, limit: limit);
        for (final h in matchedTags) {
          final id = 'tag_${h.tag}';
          if (seenIds.add(id)) {
            results.add(SearchResult(
              id: h.tag,
              type: SearchEntityType.hashtag,
              title: '#${h.tag}',
              subtitle: '${h.postCount} posts',
              content: '${h.velocityPerHour.toStringAsFixed(1)}/h velocity',
              metadata: h.toMap(),
              createdAt: h.lastUsedAt,
            ));
          }
        }
      }

      // 2. Creators
      if ((type == null || type == SearchEntityType.person) && !isTagQuery) {
        // Query users by username prefix
        try {
          final userSnap = await _firestore
              .collection('users')
              .where('username', isGreaterThanOrEqualTo: q)
              .where('username', isLessThan: endQ)
              .limit(limit)
              .get();

          for (final doc in userSnap.docs) {
            final data = doc.data();
            if (seenIds.add('usr_${doc.id}')) {
              final displayName = (data['displayName'] as String?)?.isNotEmpty == true
                  ? data['displayName']
                  : (data['fullName'] as String?)?.isNotEmpty == true
                      ? data['fullName']
                      : (data['username'] as String?) ?? 'Creator';
              final username = (data['username'] as String?) ?? '';
              final followerCount = (data['followerCount'] as num?)?.toInt() ??
                  (data['followers'] as num?)?.toInt() ?? 0;
              final avatar = (data['profilePhotoUrl'] as String?) ?? (data['avatarUrl'] as String?) ?? '';

              results.add(SearchResult(
                id: doc.id,
                type: SearchEntityType.person,
                title: displayName,
                subtitle: username.isNotEmpty ? '@$username' : null,
                content: (data['bio'] as String?) ?? '',
                metadata: {
                  ...data,
                  'id': doc.id,
                  'displayName': displayName,
                  'username': username,
                  'followerCount': followerCount,
                  'avatarUrl': avatar,
                  'isVerified': data['isVerified'] ?? false,
                },
                createdAt: data['createdAt'] is Timestamp
                    ? (data['createdAt'] as Timestamp).toDate()
                    : DateTime.now(),
              ));
            }
          }
        } catch (_) {}

        // Query users by displayName if limit not reached
        if (results.where((r) => r.type == SearchEntityType.person).length < limit) {
          try {
            final cleanName = rawQ.replaceAll('@', '');
            final endName = '$cleanName\uf8ff';
            final nameSnap = await _firestore
                .collection('users')
                .where('displayName', isGreaterThanOrEqualTo: cleanName)
                .where('displayName', isLessThan: endName)
                .limit(limit)
                .get();

            for (final doc in nameSnap.docs) {
              if (seenIds.add('usr_${doc.id}')) {
                final data = doc.data();
                final displayName = (data['displayName'] as String?)?.isNotEmpty == true
                    ? data['displayName']
                    : (data['fullName'] as String?)?.isNotEmpty == true
                        ? data['fullName']
                        : (data['username'] as String?) ?? 'Creator';
                final username = (data['username'] as String?) ?? '';
                final followerCount = (data['followerCount'] as num?)?.toInt() ??
                    (data['followers'] as num?)?.toInt() ?? 0;
                final avatar = (data['profilePhotoUrl'] as String?) ?? (data['avatarUrl'] as String?) ?? '';

                results.add(SearchResult(
                  id: doc.id,
                  type: SearchEntityType.person,
                  title: displayName,
                  subtitle: username.isNotEmpty ? '@$username' : null,
                  content: (data['bio'] as String?) ?? '',
                  metadata: {
                    ...data,
                    'id': doc.id,
                    'displayName': displayName,
                    'username': username,
                    'followerCount': followerCount,
                    'avatarUrl': avatar,
                    'isVerified': data['isVerified'] ?? false,
                  },
                  createdAt: data['createdAt'] is Timestamp
                      ? (data['createdAt'] as Timestamp).toDate()
                      : DateTime.now(),
                ));
              }
            }
          } catch (_) {}
        }
      }

      // 3. Videos
      if (type == null || type == SearchEntityType.video || type == SearchEntityType.post) {
        // Query content by hashtag if tag query
        if (isTagQuery || cleanTag.isNotEmpty) {
          try {
            final tagSnap = await _firestore
                .collection('content')
                .where('hashtags', arrayContains: cleanTag)
                .limit(limit)
                .get();

            for (final doc in tagSnap.docs) {
              if (seenIds.add('vid_${doc.id}')) {
                final data = doc.data();
                final mediaMeta = data['mediaMetadata'] as Map<String, dynamic>?;
                final thumb = (mediaMeta?['thumbnailUrl'] as String?) ??
                    (mediaMeta?['posterFrameUrl'] as String?) ??
                    (data['thumbnailUrl'] as String?) ??
                    (data['mediaUrl'] as String?);
                final viewCount = (data['viewCount'] as num?)?.toInt() ?? 0;
                final authorHandle = (data['authorHandle'] as String?) ??
                    (data['authorName'] as String?) ??
                    (data['authorId'] as String?) ?? '';

                results.add(SearchResult(
                  id: doc.id,
                  type: SearchEntityType.video,
                  title: (data['description'] as String?)?.isNotEmpty == true
                      ? data['description']
                      : 'Video by @$authorHandle',
                  subtitle: '@$authorHandle',
                  content: (data['description'] as String?) ?? '',
                  metadata: {
                    ...data,
                    'id': doc.id,
                    'thumbnailUrl': thumb,
                    'viewCount': viewCount,
                    'authorHandle': authorHandle,
                  },
                  createdAt: data['createdAt'] is Timestamp
                      ? (data['createdAt'] as Timestamp).toDate()
                      : DateTime.now(),
                ));
              }
            }
          } catch (_) {}
        }

        // Search content collection general
        try {
          final contentSnap = await _firestore
              .collection('content')
              .limit(limit * 2)
              .get();

          for (final doc in contentSnap.docs) {
            if (seenIds.contains('vid_${doc.id}')) continue;
            final data = doc.data();
            final desc = (data['description'] as String? ?? '').toLowerCase();
            final tags = List<String>.from(data['hashtags'] ?? []).map((t) => t.toLowerCase());
            final author = (data['authorHandle'] as String? ?? data['authorId'] as String? ?? '').toLowerCase();

            if (desc.contains(q) || tags.any((t) => t.contains(cleanTag)) || author.contains(q)) {
              seenIds.add('vid_${doc.id}');
              final mediaMeta = data['mediaMetadata'] as Map<String, dynamic>?;
              final thumb = (mediaMeta?['thumbnailUrl'] as String?) ??
                  (mediaMeta?['posterFrameUrl'] as String?) ??
                  (data['thumbnailUrl'] as String?) ??
                  (data['mediaUrl'] as String?);
              final viewCount = (data['viewCount'] as num?)?.toInt() ?? 0;
              final authorHandle = (data['authorHandle'] as String?) ??
                  (data['authorName'] as String?) ??
                  (data['authorId'] as String?) ?? '';

              results.add(SearchResult(
                id: doc.id,
                type: SearchEntityType.video,
                title: (data['description'] as String?)?.isNotEmpty == true
                    ? data['description']
                    : 'Video by @$authorHandle',
                subtitle: '@$authorHandle',
                content: (data['description'] as String?) ?? '',
                metadata: {
                  ...data,
                  'id': doc.id,
                  'thumbnailUrl': thumb,
                  'viewCount': viewCount,
                  'authorHandle': authorHandle,
                },
                createdAt: data['createdAt'] is Timestamp
                    ? (data['createdAt'] as Timestamp).toDate()
                    : DateTime.now(),
              ));
            }
          }
        } catch (_) {}
      }

      // Sort by creation date
      results.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (results.length > limit) {
        return results.sublist(0, limit);
      }
      return results;
    } catch (e) {
      return [];
    }
  }

  /// Semantic Search using the backend Cloud Function
  Future<List<SearchResult>> semanticSearch({
    required String query,
    SearchEntityType? type,
    int limit = 20,
  }) async {
    try {
      final callable = _functions.httpsCallable('globalSemanticSearch');
      final response = await callable.call({
        'query': query,
        'limit': limit,
        if (type != null && type != SearchEntityType.unknown) 'type': type.name,
      });

      final data = response.data as Map<String, dynamic>;
      final resultsList = data['results'] as List<dynamic>;

      return resultsList.map((item) {
        return SearchResult.fromMap(
          Map<String, dynamic>.from(item),
          item['id'] ?? '',
        );
      }).toList();
    } catch (e) {
      print('Semantic search error: \$e');
      return [];
    }
  }
}
