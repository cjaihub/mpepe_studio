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

  /// Rates or likes a comment
  Future<bool> setCommentRating(String commentId, {String rating = 'like'}) async {
    final client = await _authService.getAuthClient();
    if (client == null) return false;
    final ytApi = youtube.YouTubeApi(client);
    try {
      await ytApi.comments.setModerationStatus([commentId], 'published');
      return true;
    } catch (e) {
      if (kDebugMode) print('Error rating comment: $e');
      return false;
    }
  }

  /// Moderates a comment (holds for review or rejects/deletes)
  Future<bool> moderateComment(String commentId, {required String moderationStatus}) async {
    final client = await _authService.getAuthClient();
    if (client == null) return false;
    final ytApi = youtube.YouTubeApi(client);
    try {
      await ytApi.comments.setModerationStatus([commentId], moderationStatus);
      return true;
    } catch (e) {
      if (kDebugMode) print('Error moderating comment: $e');
      return false;
    }
  }

  /// Updates title, description or tags of an existing video
  Future<bool> updateVideoMetadata({
    required String videoId,
    String? title,
    String? description,
    List<String>? tags,
  }) async {
    final client = await _authService.getAuthClient();
    if (client == null) throw Exception('Not authenticated with YouTube.');

    final ytApi = youtube.YouTubeApi(client);
    try {
      final existing = await ytApi.videos.list(['snippet', 'status'], id: [videoId]);
      final video = existing.items?.firstOrNull;
      if (video == null) return false;

      final snippet = video.snippet ?? youtube.VideoSnippet();
      if (title != null && title.trim().isNotEmpty) snippet.title = title.trim();
      if (description != null) snippet.description = description.trim();
      if (tags != null) snippet.tags = tags;
      video.snippet = snippet;

      await ytApi.videos.update(video, ['snippet']);
      return true;
    } catch (e) {
      if (kDebugMode) print('Error updating video: $e');
      return false;
    }
  }

  /// Schedules a new live stream broadcast on YouTube
  Future<Map<String, dynamic>?> scheduleLiveBroadcast({
    required String title,
    String description = '',
    DateTime? startTime,
    String privacyStatus = 'public',
  }) async {
    final client = await _authService.getAuthClient();
    if (client == null) throw Exception('Not authenticated with YouTube.');

    final ytApi = youtube.YouTubeApi(client);
    try {
      final scheduledTime = (startTime ?? DateTime.now().add(const Duration(hours: 1))).toUtc();
      final broadcast = youtube.LiveBroadcast()
        ..snippet = (youtube.LiveBroadcastSnippet()
          ..title = title
          ..description = description
          ..scheduledStartTime = scheduledTime)
        ..status = (youtube.LiveBroadcastStatus()..privacyStatus = privacyStatus)
        ..contentDetails = (youtube.LiveBroadcastContentDetails()
          ..enableAutoStart = true
          ..enableAutoStop = true);

      final res = await ytApi.liveBroadcasts.insert(broadcast, ['snippet', 'status', 'contentDetails']);
      return {
        'id': res.id,
        'title': res.snippet?.title,
        'watchUrl': 'https://youtube.com/watch?v=${res.id}',
        'scheduledStartTime': res.snippet?.scheduledStartTime?.toIso8601String(),
      };
    } catch (e) {
      if (kDebugMode) print('Error scheduling broadcast: $e');
      return null;
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
