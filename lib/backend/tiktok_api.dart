import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tiktok_oauth_service.dart';

/// One of the creator's TikTok videos (video.list).
class TikTokVideo {
  final String id;
  final String title;
  final String? coverUrl;
  final String? shareUrl;
  final int durationSec;
  final DateTime? createdAt;
  final int views;
  final int likes;
  final int comments;
  final int shares;

  const TikTokVideo({
    required this.id,
    required this.title,
    this.coverUrl,
    this.shareUrl,
    this.durationSec = 0,
    this.createdAt,
    this.views = 0,
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
  });

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  factory TikTokVideo.fromJson(Map<String, dynamic> j) {
    final created = _int(j['create_time']);
    final title = (j['title'] ?? j['video_description'] ?? '').toString();
    return TikTokVideo(
      id: j['id']?.toString() ?? '',
      title: title,
      coverUrl: j['cover_image_url'] as String?,
      shareUrl: j['share_url'] as String?,
      durationSec: _int(j['duration']),
      createdAt: created > 0 ? DateTime.fromMillisecondsSinceEpoch(created * 1000) : null,
      views: _int(j['view_count']),
      likes: _int(j['like_count']),
      comments: _int(j['comment_count']),
      shares: _int(j['share_count']),
    );
  }
}

class TikTokVideoPage {
  final List<TikTokVideo> videos;
  final int? cursor;
  final bool hasMore;
  const TikTokVideoPage(this.videos, this.cursor, this.hasMore);
}

/// What TikTok allows this creator to post right now. TikTok requires the
/// post sheet to show these and never to pre-pick a privacy level.
class TikTokCreatorInfo {
  final String? nickname;
  final String? username;
  final String? avatarUrl;
  final List<String> privacyLevelOptions;
  final bool commentDisabled;
  final bool duetDisabled;
  final bool stitchDisabled;
  final int? maxVideoPostDurationSec;

  const TikTokCreatorInfo({
    this.nickname,
    this.username,
    this.avatarUrl,
    this.privacyLevelOptions = const [],
    this.commentDisabled = false,
    this.duetDisabled = false,
    this.stitchDisabled = false,
    this.maxVideoPostDurationSec,
  });

  factory TikTokCreatorInfo.fromJson(Map<String, dynamic> j) => TikTokCreatorInfo(
        nickname: j['nickname'] as String?,
        username: j['username'] as String?,
        avatarUrl: j['avatarUrl'] as String?,
        privacyLevelOptions: [for (final o in (j['privacyLevelOptions'] as List? ?? const [])) o.toString()],
        commentDisabled: j['commentDisabled'] == true,
        duetDisabled: j['duetDisabled'] == true,
        stitchDisabled: j['stitchDisabled'] == true,
        maxVideoPostDurationSec: (j['maxVideoPostDurationSec'] as num?)?.toInt(),
      );

  static String label(String privacy) => switch (privacy) {
        'PUBLIC_TO_EVERYONE' => 'Everyone',
        'MUTUAL_FOLLOW_FRIENDS' => 'Friends',
        'FOLLOWER_OF_CREATOR' => 'Followers',
        'SELF_ONLY' => 'Only me',
        _ => privacy,
      };
}

/// Choices from the direct-post sheet.
class TikTokDirectPost {
  final String title;
  final String privacyLevel;
  final bool allowComments;
  final bool allowDuet;
  final bool allowStitch;
  final bool brandContent;
  final bool brandOrganic;

  const TikTokDirectPost({
    required this.title,
    required this.privacyLevel,
    this.allowComments = true,
    this.allowDuet = true,
    this.allowStitch = true,
    this.brandContent = false,
    this.brandOrganic = false,
  });
}

/// TikTok features, through Cloud Functions (the tokens stay on the server).
class TikTokApi {
  TikTokApi([FirebaseFunctions? functions]) : _fn = functions ?? FirebaseFunctions.instance;
  final FirebaseFunctions _fn;

  Future<Map<String, dynamic>> _call(String name, [Map<String, dynamic>? data]) async {
    final r = await _fn.httpsCallable(name, options: HttpsCallableOptions(timeout: const Duration(minutes: 5)))
        .call<Map<String, dynamic>>(data);
    return Map<String, dynamic>.from(r.data);
  }

  Future<TikTokAccount> profile() async =>
      TikTokAccount.fromJson(Map<String, dynamic>.from((await _call('tiktokProfile'))['account'] as Map));

  Future<TikTokVideoPage> videos({int? cursor}) async {
    final d = await _call('tiktokVideos', {'cursor': ?cursor});
    return TikTokVideoPage(
      [for (final v in (d['videos'] as List? ?? const [])) TikTokVideo.fromJson(Map<String, dynamic>.from(v as Map))],
      (d['cursor'] as num?)?.toInt(),
      d['hasMore'] == true,
    );
  }

  Future<TikTokCreatorInfo> creatorInfo() async => TikTokCreatorInfo.fromJson(await _call('tiktokCreatorInfo'));

  /// Sends an Oneova video to the creator's TikTok drafts (video.upload).
  Future<String> sendToDrafts(String contentId) async =>
      (await _call('tiktokPublish', {'contentId': contentId, 'mode': 'draft'}))['publishId'].toString();

  /// Posts an Oneova video straight to TikTok (video.publish).
  Future<String> postDirect(String contentId, TikTokDirectPost p) async => (await _call('tiktokPublish', {
        'contentId': contentId,
        'mode': 'direct',
        'title': p.title,
        'privacyLevel': p.privacyLevel,
        'disableComment': !p.allowComments,
        'disableDuet': !p.allowDuet,
        'disableStitch': !p.allowStitch,
        'brandContent': p.brandContent,
        'brandOrganic': p.brandOrganic,
      }))['publishId']
          .toString();
}

final tiktokApiProvider = Provider<TikTokApi>((ref) => TikTokApi());
