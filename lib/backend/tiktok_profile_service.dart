import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TikTokVideoModel {
  final String id;
  final String title;
  final String thumbnailUrl;
  final int views;
  final int likes;
  final int comments;

  TikTokVideoModel({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    required this.views,
    required this.likes,
    required this.comments,
  });

  TikTokVideoModel copyWith({
    int? views,
    int? likes,
    int? comments,
  }) {
    return TikTokVideoModel(
      id: id,
      title: title,
      thumbnailUrl: thumbnailUrl,
      views: views ?? this.views,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
    );
  }
}

class TikTokProfileState {
  final int followers;
  final int totalLikes;
  final List<TikTokVideoModel> videos;

  TikTokProfileState({
    required this.followers,
    required this.totalLikes,
    required this.videos,
  });
}

final tiktokProfileProvider = StreamProvider.autoDispose<TikTokProfileState>((ref) {
  final random = Random();
  
  // Initial mock state
  var currentState = TikTokProfileState(
    followers: 12500,
    totalLikes: 452000,
    videos: [
      TikTokVideoModel(
        id: 'v1',
        title: 'Behind the scenes at Oneova Studio 🎬',
        thumbnailUrl: 'https://images.unsplash.com/photo-1611162617213-7d7a39e9b1d7?auto=format&fit=crop&w=400&q=80',
        views: 15400,
        likes: 2100,
        comments: 342,
      ),
      TikTokVideoModel(
        id: 'v2',
        title: 'Testing the new AI voice cloning 🤖🎙️',
        thumbnailUrl: 'https://images.unsplash.com/photo-1516280440502-861614917f6a?auto=format&fit=crop&w=400&q=80',
        views: 8900,
        likes: 1250,
        comments: 89,
      ),
      TikTokVideoModel(
        id: 'v3',
        title: 'How to automate your shorts workflow #tutorial',
        thumbnailUrl: 'https://images.unsplash.com/photo-1533750516457-a7f992034fec?auto=format&fit=crop&w=400&q=80',
        views: 45000,
        likes: 8500,
        comments: 1205,
      ),
    ],
  );

  // Stream controller to emit state updates
  final controller = StreamController<TikTokProfileState>();
  controller.add(currentState);

  // Simulate real-time updates every 3 seconds
  final timer = Timer.periodic(const Duration(seconds: 3), (_) {
    // Simulate 0-5 new followers
    final newFollowers = currentState.followers + random.nextInt(6);
    
    // Simulate 0-20 new likes
    final newTotalLikes = currentState.totalLikes + random.nextInt(21);

    // Update random video stats
    final updatedVideos = currentState.videos.map((video) {
      if (random.nextDouble() > 0.5) {
        return video.copyWith(
          views: video.views + random.nextInt(50),
          likes: video.likes + random.nextInt(10),
          comments: video.comments + random.nextInt(2),
        );
      }
      return video;
    }).toList();

    currentState = TikTokProfileState(
      followers: newFollowers,
      totalLikes: newTotalLikes,
      videos: updatedVideos,
    );

    if (!controller.isClosed) {
      controller.add(currentState);
    }
  });

  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });

  return controller.stream;
});
