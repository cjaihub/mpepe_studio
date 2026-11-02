import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:googleapis/youtube/v3.dart' as youtube;
import 'package:http/http.dart' as http;

class YouTubeUploadResult {
  final String videoId;
  final String title;
  final String watchUrl;
  final String shortsUrl;
  final bool isShort;
  final DateTime publishedAt;

  const YouTubeUploadResult({
    required this.videoId,
    required this.title,
    required this.watchUrl,
    required this.shortsUrl,
    required this.isShort,
    required this.publishedAt,
  });
}

class YouTubeUploadService {
  final http.Client authenticatedClient;

  YouTubeUploadService(this.authenticatedClient);

  Future<YouTubeUploadResult> uploadVideo({
    required File videoFile,
    required String title,
    required String description,
    required List<String> tags,
    String privacyStatus = 'public',
    String categoryId = '22', // People & Blogs default
    bool isShort = false,
  }) async {
    final ytApi = youtube.YouTubeApi(authenticatedClient);

    // Format tags & description for YouTube Shorts if applicable
    final effectiveTags = [
      ...tags,
      if (isShort && !tags.any((t) => t.toLowerCase().contains('shorts'))) 'Shorts',
    ];

    var effectiveTitle = title;
    var effectiveDescription = description;
    if (isShort) {
      if (!effectiveTitle.toLowerCase().contains('#shorts')) {
        effectiveTitle = '$effectiveTitle #Shorts';
      }
      if (!effectiveDescription.toLowerCase().contains('#shorts')) {
        effectiveDescription = '$effectiveDescription\n\n#Shorts #YouTubeShorts';
      }
    }

    final video = youtube.Video()
      ..snippet = (youtube.VideoSnippet()
        ..title = effectiveTitle
        ..description = effectiveDescription
        ..tags = effectiveTags
        ..categoryId = categoryId)
      ..status = (youtube.VideoStatus()
        ..privacyStatus = privacyStatus
        ..selfDeclaredMadeForKids = false);

    final fileStream = videoFile.openRead();
    final media = youtube.Media(fileStream, videoFile.lengthSync());

    try {
      final response = await ytApi.videos.insert(
        video,
        ['snippet', 'status'],
        uploadMedia: media,
      );

      final videoId = response.id ?? '';
      return YouTubeUploadResult(
        videoId: videoId,
        title: response.snippet?.title ?? title,
        watchUrl: 'https://youtube.com/watch?v=$videoId',
        shortsUrl: 'https://youtube.com/shorts/$videoId',
        isShort: isShort,
        publishedAt: response.snippet?.publishedAt ?? DateTime.now(),
      );
    } catch (e) {
      debugPrint('Error uploading video to YouTube: $e');
      rethrow;
    }
  }

  /// Uploads specifically formatted as a YouTube Short
  Future<YouTubeUploadResult> uploadShort({
    required File videoFile,
    required String title,
    String description = '',
    List<String> tags = const [],
    String privacyStatus = 'public',
  }) {
    return uploadVideo(
      videoFile: videoFile,
      title: title,
      description: description,
      tags: tags,
      privacyStatus: privacyStatus,
      isShort: true,
    );
  }
}

