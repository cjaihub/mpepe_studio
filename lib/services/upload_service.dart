import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import '../backend/social/services/global_hashtag_service.dart';
import '../backend/social/services/collab_service.dart';
import '../backend/media/high_fidelity_media_engine.dart';
import '../backend/security/account_security_protocol.dart';
import '../backend/publishing/models/publishing_destination.dart';
import '../backend/notifications/services/follower_alert_service.dart';

class UploadService {
  /// Uploads the media and creates the `content` document.
  /// Returns the new content id; throws if the upload or publish fails.
  static Future<String> uploadPostInBackground({
    BuildContext? context,
    required String mediaPath,
    required bool isVideo,
    String? title,
    required String caption,
    required String privacy,
    required bool allowComments,
    required bool allowDuet,
    bool allowStitch = true,
    bool allowRemix = true,
    bool allowDownload = true,
    // {contentId, authorId, authorName} of the post this remixes.
    Map<String, dynamic>? remixOf,
    required bool highQualityUploads,
    String? location,
    String? link,
    double? latitude,
    double? longitude,
    String? geoRadiusTier,
    String? coverUrl,
    int? coverTimeMs,
    String? customCoverPath,
    String? ageRestriction,
    bool isAiGenerated = false,
    bool isBrandedContent = false,
    List<PlatformDestination> destinations = const [PlatformDestination.internal],
    List<String> collaborators = const [],
    List<String> taggedUserIds = const [],
    bool isFastTrendBoosted = true,
    int? durationMs,
    double? aspectRatio,
    void Function(double progress)? onProgress,
    // Fixed id from PendingPostQueue: a retry reuses the same doc and
    // Storage path, so a post is never published twice.
    String? contentId,
  }) async {
    final Set<PlatformDestination> allDestinations = {
      PlatformDestination.internal, // Oneova native public reels engine is always guaranteed
      ...destinations,
    };
    debugPrint('[UploadService] Starting background upload for: $mediaPath (isVideo: $isVideo, platforms: ${allDestinations.length}, fastTrend: $isFastTrendBoosted)');

    try {
      final file = File(mediaPath);
      if (!await file.exists()) {
        throw StateError('The recorded file is no longer on this device.');
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw StateError('Sign in to publish.');
      }
      final authorId = currentUser.uid;
      if (contentId != null) {
        final existing = await FirebaseFirestore.instance.collection('content').doc(contentId).get();
        if (existing.exists) {
          onProgress?.call(1);
          return contentId;
        }
      }

      // 1. High-Fidelity Master Spec Generation
      final mediaEngine = HighFidelityMediaEngine();
      final mediaSpec = await mediaEngine.inspectAndGenerateSpec(
        file: file,
        ownerId: authorId,
      );

      // 2. Upload to Firebase Storage
      final timestamp = contentId ?? DateTime.now().millisecondsSinceEpoch.toString();
      final extension = isVideo ? 'mp4' : 'jpg';
      final storagePath = 'content/$authorId/${timestamp}_post.$extension';
      final storageRef = FirebaseStorage.instance.ref(storagePath);

      final metadata = SettableMetadata(
        contentType: isVideo ? 'video/mp4' : 'image/jpeg',
        customMetadata: {
          'authorId': authorId,
          'title': title ?? '',
          'caption': caption,
          'fidelity': highQualityUploads ? 'master_raw_lossless' : 'standard',
          'crf': mediaSpec.crf.toString(),
          'targetFps': mediaSpec.targetFps.toString(),
        },
      );

      final uploadTask = storageRef.putFile(file, metadata);
      final progressSub = onProgress == null
          ? null
          : uploadTask.snapshotEvents.listen((s) {
              if (s.totalBytes > 0) onProgress(0.95 * s.bytesTransferred / s.totalBytes);
            }, onError: (_) {});
      final TaskSnapshot snapshot;
      try {
        snapshot = await uploadTask;
      } finally {
        await progressSub?.cancel();
      }
      final mediaUrl = await snapshot.ref.getDownloadURL();

      debugPrint('[UploadService] Media uploaded successfully. URL: $mediaUrl');

      // 2b. Upload Custom Cover Image if provided
      String? resolvedCoverUrl = coverUrl;
      final storagePaths = <String>[storagePath];
      if (customCoverPath != null && customCoverPath.isNotEmpty) {
        try {
          final coverFile = File(customCoverPath);
          if (await coverFile.exists()) {
            final coverStoragePath = 'content/$authorId/${timestamp}_cover.jpg';
            final coverRef = FirebaseStorage.instance.ref(coverStoragePath);
            final coverSnap = await coverRef.putFile(coverFile, SettableMetadata(contentType: 'image/jpeg'));
            resolvedCoverUrl = await coverSnap.ref.getDownloadURL();
            storagePaths.add(coverStoragePath);
          }
        } catch (e) {
          debugPrint('[UploadService] Custom cover upload error: $e');
        }
      }

      // 3. Extract hashtags (#tag) and record with GlobalHashtagService
      final hashtagRegex = RegExp(r'#(\w+)');
      final hashtags = hashtagRegex
          .allMatches(caption)
          .map((m) => m.group(1)!.toLowerCase())
          .toSet()
          .toList();

      if (hashtags.isNotEmpty) {
        try {
          await GlobalHashtagService().recordHashtagsUsed(hashtags);
        } catch (e) {
          debugPrint('[UploadService] Hashtag recording non-fatal error: $e');
        }
      }

      // 4. Generate Security Token for request signing
      final securityProtocol = AccountSecurityProtocol();
      Map<String, String> secHeaders = {};
      try {
        secHeaders = await securityProtocol.generateSecurityHeaders(
          action: 'publish_post',
          payloadHash: storagePath,
        );
      } catch (e) {
        debugPrint('[UploadService] Security header generation: $e');
      }

      // 5. Save Content to Firestore
      final contentDoc = FirebaseFirestore.instance.collection('content').doc(contentId);
      final allTagged = {...collaborators, ...taggedUserIds}.toList();

      await contentDoc.set({
        'id': contentDoc.id,
        'authorId': authorId,
        'title': title ?? '',
        'description': caption,
        'type': isVideo ? 'short_video' : 'photo',
        'mediaUrl': mediaUrl,
        'coverUrl': resolvedCoverUrl ?? '',
        // Owner-deletable files backing this post (ContentDeletionService).
        'storagePaths': storagePaths,
        'coverTimeMs': coverTimeMs ?? 0,
        'mediaMetadata': {
          if (resolvedCoverUrl != null && resolvedCoverUrl.isNotEmpty) 'thumbnailUrl': resolvedCoverUrl,
          'aspectRatio': aspectRatio ?? 9 / 16,
          'durationMs': isVideo ? (durationMs ?? 0) : 0,
          'effects': [],
          'filters': [],
          'hasCaptions': false,
          'highFidelityMaster': highQualityUploads,
          'targetBitrateKbps': mediaSpec.inspection.estimatedBitrateKbps,
          'fps': mediaSpec.targetFps,
        },
        'hashtags': hashtags,
        'mentions': allTagged,
        'coAuthorIds': collaborators,
        'taggedUserIds': taggedUserIds,
        'ageRestriction': ageRestriction ?? 'all',
        'isAiGenerated': isAiGenerated,
        'isBrandedContent': isBrandedContent,
        'location': location,
        'latitude': latitude,
        'longitude': longitude,
        'geoRadiusTier': geoRadiusTier ?? 'global',
        'link': link,
        'visibility': privacy,
        'viewCount': 0,
        'commentCount': 0,
        'likeCount': 0,
        'reactionCount': 0,
        'shareCount': 0,
        'saveCount': 0,
        'repostCount': 0,
        'downloadsPermitted': allowDownload,
        'permissions': {
          'allowComments': allowComments,
          'allowDuet': allowDuet,
          'allowStitch': allowStitch,
          'allowRemix': allowRemix,
          'allowDownload': allowDownload,
        },
        // Checked by the remixOnCreate function, which records the earnings
        // split (remix_links) or rejects a remix the creator did not allow.
        if (remixOf != null && remixOf['contentId'] is String) ...{
          'remixOf': {
            'contentId': remixOf['contentId'],
            'authorId': remixOf['authorId'],
            'authorName': remixOf['authorName'] ?? '',
            'status': 'pending',
          },
          'attribution': {
            'originalContentId': remixOf['contentId'],
            'originalAuthorId': remixOf['authorId'],
            'derivativeType': 'remix',
          },
        },
        'crossPublishChannels': allDestinations.map((d) => d.name).toList(),
        'isFastTrendBoosted': isFastTrendBoosted,
        'securityAudit': {
          'verifiedDeviceId': secHeaders['x-oneova-device-id'],
          'signedAt': secHeaders['x-oneova-timestamp'],
        },
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 6. Record Collaborator Invites & Real Notifications
      if (collaborators.isNotEmpty) {
        final collabService = CollabService();
        for (final collabUserId in collaborators) {
          try {
            await collabService.inviteCollaborator(
              contentId: contentDoc.id,
              inviterId: authorId,
              collaboratorUserId: collabUserId,
              role: CollaboratorRole.coAuthor,
            );
          } catch (e) {
            debugPrint('[UploadService] Collab invite non-fatal error: $e');
          }
        }
      }

      // 6b. Dispatch Real Notifications for Tagged Users
      if (taggedUserIds.isNotEmpty) {
        try {
          final authorDoc = await FirebaseFirestore.instance.collection('users').doc(authorId).get();
          final authorData = authorDoc.data() ?? {};
          final authorName = authorData['displayName'] as String? ?? authorData['username'] as String? ?? 'A creator';
          final authorAvatar = authorData['avatarUrl'] as String? ?? authorData['profilePhotoUrl'] as String? ?? '';

          for (final taggedId in taggedUserIds) {
            if (taggedId == authorId) continue;
            // Unified notifications center
            final notifRef = FirebaseFirestore.instance.collection('notifications').doc();
            await notifRef.set({
              'id': notifRef.id,
              'userId': taggedId,
              'actorId': authorId,
              'category': 'mention',
              'priority': 'normal',
              'title': 'Tagged in a Reel 🎬',
              'body': '$authorName tagged you in a new Oneova Reel.',
              'groupId': 'post_${contentDoc.id}',
              'deepLink': '/hub/home',
              'payload': {
                'contentId': contentDoc.id,
                'actorName': authorName,
                'avatarUrl': authorAvatar,
                'thumbnailUrl': mediaUrl,
              },
              'isRead': false,
              'createdAt': FieldValue.serverTimestamp(),
            });

            // Social Activity Notifications
            final socialNotifRef = FirebaseFirestore.instance.collection('social_notifications').doc();
            await socialNotifRef.set({
              'userId': taggedId,
              'actorId': authorId,
              'type': 'mention',
              'targetId': contentDoc.id,
              'isRead': false,
              'title': 'Tagged in a Reel 🎬',
              'body': '$authorName tagged you in a new Oneova Reel.',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        } catch (e) {
          debugPrint('[UploadService] Tagged user notification dispatch error: $e');
        }
      }

      // 7. Let followers know (skipped for private posts)
      if (privacy != 'private') {
        unawaited(FollowerAlertService().notifyFollowersNewPost(
          authorId: authorId,
          contentId: contentDoc.id,
          caption: caption,
          isVideo: isVideo,
          mediaUrl: mediaUrl,
        ));
      }

      debugPrint('[UploadService] Content document created with id: ${contentDoc.id}');
      onProgress?.call(1);
      return contentDoc.id;
    } catch (e, st) {
      debugPrint('[UploadService] Error uploading post in background: $e\n$st');
      rethrow;
    }
  }
}
