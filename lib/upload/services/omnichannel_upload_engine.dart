import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../backend/social_connection_service.dart';
import '../../youtube_manager/services/youtube_account_store.dart';
import '../../youtube_manager/services/youtube_auth_service.dart';
import '../models/connected_destination.dart';
import '../models/omnichannel_upload_task.dart';
import 'dart:async';
import '../../youtube_manager/services/bulk_upload_engine.dart'; // Old bulk uploader

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

    // 2. Fetch Meta/TikTok destinations from unified social connection state
    final socialConnectionsAsync = ref.read(socialConnectionProvider);
    final socialConnections = socialConnectionsAsync.value ?? [];
    
    final fbConnection = socialConnections.where((c) => c.platform.toLowerCase() == 'facebook').firstOrNull;
    if (fbConnection != null) {
      destinations.add(ConnectedDestination.meta(
        pageId: fbConnection.accountName, // Fake ID for mock
        pageName: fbConnection.accountName,
        metaUserId: fbConnection.accountName,
        platform: PlatformType.facebook,
      ));
    }

    final igConnection = socialConnections.where((c) => c.platform.toLowerCase() == 'instagram').firstOrNull;
    if (igConnection != null) {
      destinations.add(ConnectedDestination.meta(
        pageId: igConnection.accountName,
        pageName: igConnection.accountName,
        metaUserId: igConnection.accountName,
        platform: PlatformType.instagram,
      ));
    }

    // 3. Fetch TikTok Accounts
    final ttConnection = socialConnections.where((c) => c.platform.toLowerCase() == 'tiktok').firstOrNull;
    if (ttConnection != null) {
      destinations.add(ConnectedDestination.tiktok(
        tiktokUserId: ttConnection.accountName,
        username: ttConnection.accountName,
      ));
    }

    return destinations;
  }

  void addTasks(List<File> files, List<ConnectedDestination> selectedDestinations) {
    final newTasks = files.map((file) => OmnichannelUploadTask(
      id: DateTime.now().millisecondsSinceEpoch.toString() + '_' + file.path.hashCode.toString(),
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

  Future<void> startUploads() async {
    final pendingTasks = state.where((t) => t.status == UploadStatus.pending || t.status == UploadStatus.failed).toList();

    for (final task in pendingTasks) {
      _updateTaskStatus(task.id, UploadStatus.uploading, 0.05);

      // Simulate a network upload process for the UI mockup
      int ticks = 0;
      Timer.periodic(const Duration(milliseconds: 300), (timer) {
        ticks++;
        double newProgress = 0.05 + (ticks * 0.05);
        if (newProgress >= 1.0) {
          timer.cancel();
          _updateTaskStatus(task.id, UploadStatus.completed, 1.0);
        } else {
          _updateTaskStatus(task.id, UploadStatus.uploading, newProgress);
        }
      });
    }
  }

  void _updateTaskStatus(String id, UploadStatus status, double progress) {
    state = state.map((t) {
      if (t.id == id) {
        return t.copyWith(status: status, progress: progress);
      }
      return t;
    }).toList();
  }
}

final omnichannelUploadEngineProvider = NotifierProvider<OmnichannelUploadEngine, List<OmnichannelUploadTask>>(() {
  return OmnichannelUploadEngine();
});
