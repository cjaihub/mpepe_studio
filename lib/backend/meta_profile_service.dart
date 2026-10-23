import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class MetaPostModel {
  final String id;
  final String message;
  final String? pictureUrl;
  final int likes;
  final int comments;

  MetaPostModel({
    required this.id,
    required this.message,
    this.pictureUrl,
    required this.likes,
    required this.comments,
  });

  factory MetaPostModel.fromJson(Map<String, dynamic> json) {
    int totalLikes = 0;
    if (json['likes'] != null && json['likes']['summary'] != null) {
      totalLikes = json['likes']['summary']['total_count'] ?? 0;
    }

    int totalComments = 0;
    if (json['comments'] != null && json['comments']['summary'] != null) {
      totalComments = json['comments']['summary']['total_count'] ?? 0;
    }

    return MetaPostModel(
      id: json['id'] ?? '',
      message: json['message'] ?? '',
      pictureUrl: json['full_picture'],
      likes: totalLikes,
      comments: totalComments,
    );
  }
}

class MetaProfileState {
  final int followers;
  final int totalLikes;
  final List<MetaPostModel> posts;

  MetaProfileState({
    required this.followers,
    required this.totalLikes,
    required this.posts,
  });
}

class MetaProfileService extends AsyncNotifier<MetaProfileState> {
  final _secureStorage = const FlutterSecureStorage();
  
  static const String _graphApiBase = 'https://graph.facebook.com/v22.0';

  @override
  Future<MetaProfileState> build() async {
    return _fetchLiveData();
  }

  Future<MetaProfileState> _fetchLiveData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw Exception('User not authenticated');
    }

    // 1. Get connection info from Firestore
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('social_connections')
        .doc('facebook')
        .get();

    if (!doc.exists) {
      throw Exception('Facebook account not linked');
    }

    final data = doc.data()!;
    final tokenKey = data['tokenKey'] as String?;
    final pageId = data['pageId'] as String?;

    if (tokenKey == null || pageId == null) {
      throw Exception('Invalid Facebook connection data');
    }

    // 2. Retrieve the access token securely
    final accessToken = await _secureStorage.read(key: tokenKey);
    if (accessToken == null) {
      throw Exception('Access token not found in secure storage');
    }

    // 3. Fetch Data in Parallel
    final results = await Future.wait([
      _fetchPageStats(pageId, accessToken),
      _fetchRecentPosts(pageId, accessToken),
    ]);

    final stats = results[0] as Map<String, int>;
    final posts = results[1] as List<MetaPostModel>;

    // 4. Calculate total likes
    int calculatedTotalLikes = posts.fold(0, (acc, item) => acc + item.likes);

    return MetaProfileState(
      followers: stats['fan_count'] ?? 0,
      totalLikes: calculatedTotalLikes,
      posts: posts,
    );
  }

  Future<Map<String, int>> _fetchPageStats(String pageId, String token) async {
    try {
      final response = await http.get(
        Uri.parse('$_graphApiBase/$pageId').replace(queryParameters: {
          'fields': 'fan_count,followers_count',
          'access_token': token,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'fan_count': data['fan_count'] ?? data['followers_count'] ?? 0,
        };
      } else {
        debugPrint('Failed to fetch Facebook page stats: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching Facebook page stats: $e');
    }
    return {'fan_count': 0};
  }

  Future<List<MetaPostModel>> _fetchRecentPosts(String pageId, String token) async {
    try {
      final response = await http.get(
        Uri.parse('$_graphApiBase/$pageId/feed').replace(queryParameters: {
          'fields': 'id,message,full_picture,likes.summary(true),comments.summary(true)',
          'limit': '10',
          'access_token': token,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final postsJson = data['data'] as List<dynamic>?;
        if (postsJson != null) {
          return postsJson
              .map((p) => MetaPostModel.fromJson(p as Map<String, dynamic>))
              .toList();
        }
      } else {
        debugPrint('Failed to fetch Facebook feed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Error fetching Facebook feed: $e');
    }
    return [];
  }

  Future<void> refreshData() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchLiveData());
  }
}

final metaProfileProvider = AsyncNotifierProvider<MetaProfileService, MetaProfileState>(
  MetaProfileService.new,
);
