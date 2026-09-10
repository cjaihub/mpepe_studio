import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/youtube/v3.dart' as youtube;
import 'package:googleapis/youtubeanalytics/v2.dart' as analytics;
import 'youtube_auth_service.dart';
import 'package:http/http.dart' as http;
import 'youtube_account_store.dart';

/// Client to interact with the YouTube Data API v3 and Analytics API
class YouTubeApiClient {
  final Future<http.Client?> Function() _getAuthClient;

  YouTubeApiClient(this._getAuthClient);

  /// Fetches the channels associated with the authenticated user
  Future<List<YouTubeChannel>> fetchMyChannels() async {
    final client = await _getAuthClient();
    if (client == null) throw Exception('Not authenticated');

    final youtubeApi = youtube.YouTubeApi(client);
    
    try {
      final response = await youtubeApi.channels.list(
        ['snippet', 'statistics'],
        mine: true,
      ).timeout(const Duration(seconds: 15));

      final channels = response.items ?? [];
      
      return channels.map((channel) {
        return YouTubeChannel(
          id: channel.id ?? '',
          title: channel.snippet?.title ?? 'Unknown Channel',
          thumbnailUrl: channel.snippet?.thumbnails?.default_?.url ?? '',
          subscriberCount: int.tryParse(channel.statistics?.subscriberCount ?? '0') ?? 0,
        );
      }).toList();
    } on TimeoutException {
      throw Exception('Request timed out while fetching channels. Please try again.');
    } catch (e) {
      if (kDebugMode) print('Error fetching channels: $e');
      throw Exception('Failed to fetch channels. Check your internet connection.');
    }
  }

  /// Fetches real-time basic statistics for a channel
  Future<Map<String, dynamic>> fetchChannelAnalytics(String channelId) async {
    final client = await _getAuthClient();
    if (client == null) throw Exception('Not authenticated');

    final youtubeApi = youtube.YouTubeApi(client);
    
    try {
      final response = await youtubeApi.channels.list(
        ['statistics'],
        id: [channelId],
      ).timeout(const Duration(seconds: 15));

      final items = response.items ?? [];
      if (items.isNotEmpty) {
        final stats = items.first.statistics;
        return {
          'views': int.tryParse(stats?.viewCount ?? '0') ?? 0,
          'videoCount': int.tryParse(stats?.videoCount ?? '0') ?? 0,
          'subscribers': int.tryParse(stats?.subscriberCount ?? '0') ?? 0,
        };
      }
      return _emptyAnalytics();
    } on TimeoutException {
      throw Exception('Request timed out while fetching analytics.');
    } catch (e) {
      if (kDebugMode) print('Error fetching analytics: $e');
      throw Exception('Failed to load channel live stats.');
    }
  }

  /// Fetches recent videos from a channel to help the AI understand content style
  Future<List<Map<String, dynamic>>> fetchRecentVideos(String channelId, {int maxResults = 10}) async {
    final client = await _getAuthClient();
    if (client == null) throw Exception('Not authenticated');

    final youtubeApi = youtube.YouTubeApi(client);
    
    try {
      final response = await youtubeApi.search.list(
        ['snippet'],
        channelId: channelId,
        order: 'date',
        type: ['video'],
        maxResults: maxResults,
      ).timeout(const Duration(seconds: 15));

      final items = response.items ?? [];
      return items.map((item) {
        return {
          'title': item.snippet?.title ?? '',
          'description': item.snippet?.description ?? '',
          'publishedAt': item.snippet?.publishedAt?.toIso8601String() ?? '',
          'videoId': item.id?.videoId ?? '',
          'thumbnailUrl': item.snippet?.thumbnails?.medium?.url ?? item.snippet?.thumbnails?.default_?.url ?? '',
        };
      }).toList();
    } on TimeoutException {
      throw Exception('Request timed out while fetching recent videos.');
    } catch (e) {
      if (kDebugMode) print('Error fetching recent videos: $e');
      throw Exception('Failed to fetch recent videos.');
    }
  }

  /// Fetches channel branding/keywords to help the AI understand the niche
  Future<String> fetchChannelKeywords(String channelId) async {
    final client = await _getAuthClient();
    if (client == null) throw Exception('Not authenticated');

    final youtubeApi = youtube.YouTubeApi(client);
    
    try {
      final response = await youtubeApi.channels.list(
        ['brandingSettings'],
        id: [channelId],
      ).timeout(const Duration(seconds: 15));

      final items = response.items ?? [];
      if (items.isNotEmpty) {
        return items.first.brandingSettings?.channel?.keywords ?? '';
      }
      return '';
    } on TimeoutException {
      throw Exception('Request timed out while fetching channel keywords.');
    } catch (e) {
      if (kDebugMode) print('Error fetching channel keywords: $e');
      throw Exception('Failed to fetch channel keywords.');
    }
  }
  
  Map<String, dynamic> _emptyAnalytics() {
    return {
      'views': 0,
      'videoCount': 0,
      'subscribers': 0,
    };
  }

  /// Fetches specific video statistics (views, likes, comments)
  Future<Map<String, dynamic>> fetchVideoDetails(String videoId) async {
    final client = await _getAuthClient();
    if (client == null) throw Exception('Not authenticated');

    final youtubeApi = youtube.YouTubeApi(client);
    
    try {
      final response = await youtubeApi.videos.list(
        ['statistics'],
        id: [videoId],
      ).timeout(const Duration(seconds: 15));

      final items = response.items ?? [];
      if (items.isNotEmpty) {
        final stats = items.first.statistics;
        return {
          'views': int.tryParse(stats?.viewCount ?? '0') ?? 0,
          'likes': int.tryParse(stats?.likeCount ?? '0') ?? 0,
          'comments': int.tryParse(stats?.commentCount ?? '0') ?? 0,
        };
      }
      return {'views': 0, 'likes': 0, 'comments': 0};
    } on TimeoutException {
      throw Exception('Request timed out while fetching video details.');
    } catch (e) {
      if (kDebugMode) print('Error fetching video details: $e');
      throw Exception('Failed to fetch video statistics.');
    }
  }

  /// Fetches the top countries where this video was watched
  Future<List<Map<String, dynamic>>> fetchVideoGeography(String videoId) async {
    final client = await _getAuthClient();
    if (client == null) throw Exception('Not authenticated');

    final analyticsApi = analytics.YouTubeAnalyticsApi(client);
    
    try {
      // Use a wide date range to get all-time data
      final startDate = '2005-01-01';
      final endDate = DateTime.now().toIso8601String().split('T').first;
      
      final response = await analyticsApi.reports.query(
        ids: 'channel==MINE',
        startDate: startDate,
        endDate: endDate,
        metrics: 'views',
        dimensions: 'country',
        filters: 'video==$videoId',
        sort: '-views',
        maxResults: 5,
      ).timeout(const Duration(seconds: 15));

      final rows = response.rows ?? [];
      return rows.map((row) {
        return {
          'country': row[0].toString(),
          'views': int.tryParse(row[1].toString()) ?? 0,
        };
      }).toList();
    } on TimeoutException {
      throw Exception('Request timed out while fetching video geography.');
    } catch (e) {
      if (kDebugMode) print('Error fetching video geography: $e');
      // Return empty list instead of throwing to prevent breaking the UI if analytics scope is limited
      return [];
    }
  }
}

final youtubeApiClientProvider = Provider((ref) {
  final store = ref.watch(ytAccountStoreProvider.notifier);
  return YouTubeApiClient(() => store.getActiveAuthClient());
});

final myChannelsProvider = FutureProvider<List<YouTubeChannel>>((ref) async {
  final client = ref.watch(youtubeApiClientProvider);
  return await client.fetchMyChannels();
});

final channelAnalyticsProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, channelId) async {
  final client = ref.watch(youtubeApiClientProvider);
  return await client.fetchChannelAnalytics(channelId);
});

final recentVideosProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, channelId) async {
  final client = ref.watch(youtubeApiClientProvider);
  return await client.fetchRecentVideos(channelId);
});

final videoDetailsProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, videoId) async {
  final client = ref.watch(youtubeApiClientProvider);
  return await client.fetchVideoDetails(videoId);
});

final videoGeographyProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, videoId) async {
  final client = ref.watch(youtubeApiClientProvider);
  return await client.fetchVideoGeography(videoId);
});

