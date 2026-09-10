import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/youtube/v3.dart' as youtube;
import '../../youtube_manager/services/youtube_auth_service.dart';

class YouTubeAgentService {
  final YouTubeAuthService _authService;

  YouTubeAgentService(this._authService);

  Future<List<Map<String, dynamic>>> fetchLatestComments(String channelId, {int limit = 10}) async {
    final client = await _authService.getAuthClient();
    if (client == null) throw Exception('Not authenticated with YouTube.');

    final youtubeApi = youtube.YouTubeApi(client);

    try {
      final response = await youtubeApi.commentThreads.list(
        ['snippet'],
        allThreadsRelatedToChannelId: channelId,
        maxResults: limit,
        order: 'time',
      ).timeout(const Duration(seconds: 15));

      final threads = response.items ?? [];
      return threads.map((thread) {
        final comment = thread.snippet?.topLevelComment?.snippet;
        return {
          'id': thread.snippet?.topLevelComment?.id,
          'author': comment?.authorDisplayName,
          'text': comment?.textDisplay,
          'publishedAt': comment?.publishedAt?.toIso8601String(),
          'likeCount': comment?.likeCount,
        };
      }).toList();
    } on TimeoutException {
      return [{'error': 'Request timed out while fetching comments.'}];
    } catch (e) {
      if (kDebugMode) print('Error fetching comments: $e');
      return [{'error': 'Failed to fetch comments. $e'}];
    }
  }

  Future<bool> replyToComment(String commentId, String text) async {
    final client = await _authService.getAuthClient();
    if (client == null) throw Exception('Not authenticated with YouTube.');

    final youtubeApi = youtube.YouTubeApi(client);

    try {
      final reply = youtube.Comment(
        snippet: youtube.CommentSnippet(
          parentId: commentId,
          textOriginal: text,
        ),
      );
      
      await youtubeApi.comments.insert(reply, ['snippet']).timeout(const Duration(seconds: 15));
      return true;
    } on TimeoutException {
      return false;
    } catch (e) {
      if (kDebugMode) print('Error replying to comment: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> researchTrendingTopics(String query, {int limit = 5}) async {
    final client = await _authService.getAuthClient();
    if (client == null) throw Exception('Not authenticated with YouTube.');

    final youtubeApi = youtube.YouTubeApi(client);

    try {
      final response = await youtubeApi.search.list(
        ['snippet'],
        q: query,
        maxResults: limit,
        order: 'viewCount', // Sort by views to find trending/popular
        type: ['video'],
      ).timeout(const Duration(seconds: 15));

      final videos = response.items ?? [];
      return videos.map((video) {
        return {
          'title': video.snippet?.title,
          'channel': video.snippet?.channelTitle,
          'description': video.snippet?.description,
          'publishedAt': video.snippet?.publishedAt?.toIso8601String(),
        };
      }).toList();
    } on TimeoutException {
      return [{'error': 'Request timed out while researching topics.'}];
    } catch (e) {
      if (kDebugMode) print('Error researching topics: $e');
      return [{'error': 'Failed to research topics. $e'}];
    }
  }
}

final youtubeAgentProvider = Provider<YouTubeAgentService>((ref) {
  final authService = ref.watch(youtubeAuthProvider.notifier);
  return YouTubeAgentService(authService);
});
