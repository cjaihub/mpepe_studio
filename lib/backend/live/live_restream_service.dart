import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../youtube_manager/services/youtube_api_client.dart';
import '../connections/linked_accounts.dart';
import '../live_studio/contracts/studio_ports.dart';
import '../live_studio/fun/studio_fun.dart';

/// Records, on `live_streams/{id}`, which linked platforms a Oneova live
/// should also go live on. Only platforms with a live API qualify
/// ([LinkedPlatform.live]: YouTube Live, Facebook Live Video).
///
/// For YouTube, it interacts directly with the YouTube Data & Live Streaming
/// APIs to create the live broadcast, bind the RTMP ingestion stream, and
/// register the RTMP destination with `lsDestinations` for real-time LiveKit egress.
class LiveRestreamService {
  LiveRestreamService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;

  /// The update for [targets]; accounts that can't go live are skipped.
  static Map<String, dynamic> requestFields(Iterable<LinkedAccount> targets, {DateTime? now}) {
    final usable = targets.where((a) => a.isUsable && a.platform.live).toList();
    final at = Timestamp.fromDate(now ?? DateTime.now());
    return {
      'isMultiPlatform': usable.isNotEmpty,
      'linkedPlatforms': [for (final a in usable) a.platform.id],
      'restreamTargets': {
        for (final a in usable)
          a.platform.id: {
            'accountId': a.accountId,
            'accountName': a.accountName,
            'status': 'requested',
            'requestedAt': at,
          },
      },
    };
  }

  Future<void> request(String streamId, Iterable<LinkedAccount> targets) async {
    final fields = requestFields(targets);
    if (fields['isMultiPlatform'] != true) return;
    await _firestore.collection('live_streams').doc(streamId).set(fields, SetOptions(merge: true));
  }

  /// Automatically provisions a YouTube Live Broadcast & Stream via YouTube API,
  /// binds RTMP ingestion, and saves the destination into Live Studio (`lsDestinations`).
  Future<YouTubeLiveBroadcastDetails?> autoProvisionYouTubeLive({
    required String streamId,
    required String title,
    String description = '',
    required YouTubeApiClient ytClient,
  }) async {
    try {
      final details = await ytClient.setupFullLiveStream(
        title: title,
        description: description,
      );

      // Register the RTMP endpoint in Live Studio's egress destinations
      await StudioBroadcastApi(FirebaseStudioCallPort()).saveDestination(
        platform: 'youtube',
        label: 'YouTube Live: ${details.title}',
        url: details.rtmpIngestUrl,
        key: details.streamKey,
        enabled: true,
      );

      // Save the YouTube broadcast details into Firestore live_streams
      await _firestore.collection('live_streams').doc(streamId).set({
        'youtubeBroadcast': {
          'broadcastId': details.broadcastId,
          'streamId': details.streamId,
          'watchUrl': 'https://youtube.com/watch?v=${details.broadcastId}',
          'status': 'ready',
          'provisionedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      return details;
    } catch (e) {
      if (kDebugMode) print('[LiveRestreamService] Auto-provision YouTube Live failed: $e');
      return null;
    }
  }

  /// Transitions the YouTube broadcast live or complete
  Future<void> transitionYouTubeBroadcast({
    required String broadcastId,
    required String status,
    required YouTubeApiClient ytClient,
  }) async {
    await ytClient.transitionBroadcast(broadcastId: broadcastId, status: status);
  }
}

final liveRestreamServiceProvider = Provider<LiveRestreamService>((ref) => LiveRestreamService());
