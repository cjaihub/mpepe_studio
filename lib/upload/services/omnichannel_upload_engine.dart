import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_compress/video_compress.dart';
import '../../backend/connections/linked_accounts.dart';
import '../../youtube_manager/services/youtube_account_store.dart';
import '../../youtube_manager/services/youtube_upload_service.dart';
import '../models/connected_destination.dart';
import '../models/omnichannel_upload_task.dart';
import 'dart:async';
import '../../backend/notifications/services/follower_alert_service.dart';

class OmnichannelUploadEngine extends Notifier<List<OmnichannelUploadTask>> {
  final Map<String, StreamSubscription> _subscriptions = {};

  @override
  List<OmnichannelUploadTask> build() {
    ref.onDispose(() {
      for (final sub in _subscriptions.values) {
        sub.cancel();
      }
      _subscriptions.clear();
    });
    return [];
  }

  /// Fetches all linked accounts across all platforms for the current user
  Future<List<ConnectedDestination>> fetchAllDestinations() async {
    final destinations = <ConnectedDestination>[];

    // 1. Fetch YouTube Channels
    final ytStore = await ref.read(ytAccountStoreProvider.future);
    for (final account in ytStore.accounts) {
      for (final channel in account.channels) {
        destinations.add(ConnectedDestination.youtube(
          channelId: channel.id,
          channelTitle: channel.title,
          googleId: account.googleId,
          thumbnailUrl: channel.thumbnailUrl,
        ));
      }
    }

    // 2. Meta / TikTok: the accounts linked through their OAuth flows, by
    //    their real page / open ids.
    final accounts = await ref.read(linkedAccountsProvider.future);
    for (final a in accounts.where((a) => a.isUsable)) {
      switch (a.platform) {
        case LinkedPlatform.facebook:
        case LinkedPlatform.instagram:
          destinations.add(ConnectedDestination.meta(
            pageId: a.accountId,
            pageName: a.accountName,
            metaUserId: a.accountId,
            platform: a.platform == LinkedPlatform.facebook ? PlatformType.facebook : PlatformType.instagram,
          ));
        case LinkedPlatform.tiktok:
          destinations.add(ConnectedDestination.tiktok(
            tiktokUserId: a.accountId,
            username: a.accountName,
          ));
        default:
          break;
      }
    }

    return destinations;
  }

  void addTasks(List<File> files, List<ConnectedDestination> selectedDestinations) {
    final newTasks = files.map((file) => OmnichannelUploadTask(
      id: '${DateTime.now().millisecondsSinceEpoch}_${file.path.hashCode}',
      file: file,
      selectedDestinations: selectedDestinations,
    )).toList();

    state = [...state, ...newTasks];
  }

  void updateTaskMetadata(String id, {String? title, String? description, List<String>? tags, YouTubeSpecificMetadata? ytMetadata}) {
    state = state.map((t) {
      if (t.id == id) {
        return t.copyWith(
          title: title ?? t.title,
          description: description ?? t.description,
          tags: tags ?? t.tags,
          ytMetadata: ytMetadata ?? t.ytMetadata,
        );
      }
      return t;
    }).toList();
  }
  
  void removeTask(String taskId) {
    state = state.where((task) => task.id != taskId).toList();
  }

  /// Live Firebase Storage upload handles, keyed by task id (for pause/cancel).
  final Map<String, UploadTask> _storageUploads = {};
  bool _isPaused = false;
  bool get isPaused => _isPaused;

  static const _videoExtensions = {'mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm', '3gp'};

  Future<void> startUploads() async {
    final pendingTasks = state.where((t) => t.status == UploadStatus.pending || t.status == UploadStatus.failed).toList();
    await Future.wait(pendingTasks.map(_uploadTask));
  }

  /// Uploads the file to Storage, then publishes a `content` document so the
  /// post appears in the Oneova feed. External platforms are recorded in
  /// `crossPublishChannels` for the server-side publishers.
  Future<void> _uploadTask(OmnichannelUploadTask task) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _updateTaskStatus(task.id, UploadStatus.failed, 0, errorMessage: 'Sign in to upload');
      return;
    }
    _updateTaskStatus(task.id, UploadStatus.uploading, 0.01);

    try {
      final ext = task.file.path.split('.').last.toLowerCase();
      final isVideo = _videoExtensions.contains(ext);

      File fileToUpload = task.file;
      String? thumbnailUrl;
      int? videoWidth;
      int? videoHeight;
      int? durationMs;

      // Enhanced MP4 optimization & thumbnail generation for zero-lag streaming
      if (isVideo) {
        try {
          final thumb = await VideoCompress.getFileThumbnail(
            task.file.path,
            quality: 75,
            position: -1,
          );
          if (await thumb.exists()) {
            final thumbPath = 'content/$uid/thumbnails/${DateTime.now().millisecondsSinceEpoch}_${task.id}.jpg';
            final thumbUpload = await FirebaseStorage.instance.ref(thumbPath).putFile(
                  thumb,
                  SettableMetadata(contentType: 'image/jpeg'),
                );
            thumbnailUrl = await thumbUpload.ref.getDownloadURL();
          }

          final compressed = await VideoCompress.compressVideo(
            task.file.path,
            quality: VideoQuality.MediumQuality,
            deleteOrigin: false,
            includeAudio: true,
          );
          if (compressed != null && compressed.file != null && await compressed.file!.exists()) {
            fileToUpload = compressed.file!;
            videoWidth = compressed.width;
            videoHeight = compressed.height;
            durationMs = compressed.duration?.toInt();
          }
        } catch (e) {
          debugPrint('[UploadEngine] video compression fallback to original: $e');
        }
      }

      final uploadExt = fileToUpload.path.split('.').last.toLowerCase();
      final storagePath = 'content/$uid/${DateTime.now().millisecondsSinceEpoch}_${task.id}.$uploadExt';
      final upload = FirebaseStorage.instance.ref(storagePath).putFile(
            fileToUpload,
            SettableMetadata(contentType: isVideo ? 'video/$uploadExt' : 'image/$uploadExt'),
          );
      _storageUploads[task.id] = upload;

      _subscriptions[task.id] = upload.snapshotEvents.listen((snap) {
        if (snap.totalBytes > 0 && snap.state == TaskState.running) {
          // Reserve the last 5% for the Firestore publish step.
          _updateTaskStatus(task.id, UploadStatus.uploading, 0.95 * snap.bytesTransferred / snap.totalBytes);
        }
      }, onError: (_) {});

      final snapshot = await upload;
      final mediaUrl = await snapshot.ref.getDownloadURL();

      final caption = [task.title, task.description].where((s) => s.trim().isNotEmpty).join('\n');
      final hashtags = {
        ...task.tags.map((t) => t.replaceAll('#', '').toLowerCase()).where((t) => t.isNotEmpty),
        ...RegExp(r'#(\w+)').allMatches(caption).map((m) => m.group(1)!.toLowerCase()),
      }.toList();

      // Dispatch to external platforms: YouTube
      String? youtubeVideoId;
      String? youtubeWatchUrl;
      final hasYouTube = task.selectedDestinations.any((d) => d.platform == PlatformType.youtube);
      if (hasYouTube && isVideo) {
        try {
          final authClient = await ref.read(ytAccountStoreProvider.notifier).getActiveAuthClient();
          if (authClient != null) {
            final ytUploader = YouTubeUploadService(authClient);
            final ytResult = await ytUploader.uploadVideo(
              videoFile: task.file,
              title: task.title.trim().isEmpty ? 'New Video' : task.title.trim(),
              description: caption,
              tags: hashtags,
              isShort: task.title.toLowerCase().contains('short') || caption.toLowerCase().contains('#short'),
            );
            youtubeVideoId = ytResult.videoId;
            youtubeWatchUrl = ytResult.watchUrl;
          }
        } catch (e) {
          // Keep Oneova upload even if external platform API quota or network fails
        }
      }

      final doc = FirebaseFirestore.instance.collection('content').doc();
      await doc.set({
        'id': doc.id,
        'authorId': uid,
        'description': caption,
        'type': isVideo ? 'short_video' : 'photo',
        'mediaUrl': mediaUrl,
        'mediaMetadata': {
          'thumbnailUrl': ?thumbnailUrl,
          'width': ?videoWidth,
          'height': ?videoHeight,
          'durationMs': ?durationMs,
          'aspectRatio': (videoWidth != null && videoHeight != null && videoHeight > 0)
              ? videoWidth / videoHeight
              : 9 / 16,
        },
        'hashtags': hashtags,
        'visibility': 'public',
        'viewCount': 0,
        'commentCount': 0,
        'likeCount': 0,
        'reactionCount': 0,
        'shareCount': 0,
        'saveCount': 0,
        'repostCount': 0,
        'permissions': {'allowComments': true, 'allowDuet': true, 'allowStitch': true, 'allowDownload': true},
        'crossPublishChannels': ['internal', ...task.selectedDestinations.map((d) => d.platform.name)],
        'crossPublishTargets': task.selectedDestinations.map((d) => {'platform': d.platform.name, 'id': d.id, 'name': d.name}).toList(),
        'youtubeVideoId': ?youtubeVideoId,
        'youtubeWatchUrl': ?youtubeWatchUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });

      unawaited(FollowerAlertService().notifyFollowersNewPost(
        authorId: uid,
        contentId: doc.id,
        caption: caption,
        isVideo: isVideo,
        mediaUrl: mediaUrl,
      ));

      _updateTaskStatus(task.id, UploadStatus.completed, 1.0);
    } on FirebaseException catch (e) {
      if (e.code == 'canceled') {
        removeTask(task.id);
      } else {
        _updateTaskStatus(task.id, UploadStatus.failed, 0, errorMessage: e.message ?? e.code);
      }
    } catch (e) {
      _updateTaskStatus(task.id, UploadStatus.failed, 0, errorMessage: e.toString());
    } finally {
      _storageUploads.remove(task.id);
      await _subscriptions.remove(task.id)?.cancel();
    }
  }

  Future<void> togglePauseAll() async {
    _isPaused = !_isPaused;
    for (final upload in _storageUploads.values) {
      _isPaused ? await upload.pause() : await upload.resume();
    }
    state = [...state];
  }

  Future<void> cancelActiveUploads() async {
    for (final upload in _storageUploads.values.toList()) {
      await upload.cancel();
    }
    state = state.where((t) => t.status != UploadStatus.pending && t.status != UploadStatus.uploading).toList();
    _isPaused = false;
  }

  void _updateTaskStatus(String id, UploadStatus status, double progress, {String? errorMessage}) {
    state = state.map((t) {
      if (t.id == id) {
        return t.copyWith(status: status, progress: progress, errorMessage: errorMessage);
      }
      return t;
    }).toList();
  }
}

final omnichannelUploadEngineProvider = NotifierProvider<OmnichannelUploadEngine, List<OmnichannelUploadTask>>(() {
  return OmnichannelUploadEngine();
});
