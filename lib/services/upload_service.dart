import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import '../backend/connections/google_services.dart';
import '../backend/social/services/global_hashtag_service.dart';
import '../backend/social/services/collab_service.dart';
import '../backend/media/high_fidelity_media_engine.dart';
import '../backend/security/account_security_protocol.dart';
import '../backend/publishing/models/publishing_destination.dart';
import '../backend/notifications/services/follower_alert_service.dart';
import '../create/post/services/openrouter_post_optimizer.dart';
import '../youtube_manager/services/youtube_upload_service.dart';

class UploadService {
  /// Uploads the media, runs background AI channel/video optimization if enabled,
  /// creates the `content` document, and auto-posts to the selected connected channel.
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
    String uploadQualityTier = '4k_master',
    bool autoOptimizeInBackground = true,
    Map<String, dynamic>? selectedConnectedChannel,
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
    final selectedChannelPlatform =
        (selectedConnectedChannel?['platform'] ?? '').toString().toLowerCase();
    final selectedChannelTitle =
        (selectedConnectedChannel?['title'] ?? selectedConnectedChannel?['accountName'] ?? '')
            .toString();
    if (selectedChannelPlatform == 'youtube') {
      allDestinations.add(PlatformDestination.youtube);
    } else if (selectedChannelPlatform == 'tiktok') {
      allDestinations.add(PlatformDestination.tiktok);
    } else if (selectedChannelPlatform == 'instagram') {
      allDestinations.add(PlatformDestination.instagram);
    } else if (selectedChannelPlatform == 'facebook') {
      allDestinations.add(PlatformDestination.facebook);
    }

    debugPrint(
      '[UploadService] Starting background upload for: $mediaPath '
      '(isVideo: $isVideo, quality: $uploadQualityTier, autoAI: $autoOptimizeInBackground, '
      'connectedChannel: $selectedChannelPlatform:$selectedChannelTitle)',
    );

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
        final existing =
            await FirebaseFirestore.instance.collection('content').doc(contentId).get();
        if (existing.exists) {
          onProgress?.call(1);
          return contentId;
        }
      }

      // Launch background AI video-clip + channel-niche optimization in parallel with media upload!
      Future<VideoOptimizationPackage?>? bgOptimizationFuture;
      if (autoOptimizeInBackground) {
        bgOptimizationFuture = OpenRouterPostOptimizer.optimizeInBackground(
          mediaPath: mediaPath,
          isVideo: isVideo,
          currentTitle: title,
          currentCaption: caption,
          selectedChannelLabel: selectedChannelTitle.isNotEmpty
              ? '$selectedChannelPlatform ($selectedChannelTitle)'
              : null,
          durationMs: durationMs,
          aspectRatio: aspectRatio,
          destinations: allDestinations.toList(),
        ).then<VideoOptimizationPackage?>((v) => v).catchError((Object e) {
          debugPrint('[UploadService] Background AI optimization non-fatal error: $e');
          return null;
        });
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
          'qualityTier': uploadQualityTier,
          'crf': mediaSpec.crf.toString(),
          'targetFps': mediaSpec.targetFps.toString(),
        },
      );

      final uploadTask = storageRef.putFile(file, metadata);
      final progressSub = onProgress == null
          ? null
          : uploadTask.snapshotEvents.listen((s) {
              if (s.totalBytes > 0) {
                onProgress(0.92 * s.bytesTransferred / s.totalBytes);
              }
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
            final coverSnap = await coverRef.putFile(
              coverFile,
              SettableMetadata(contentType: 'image/jpeg'),
            );
            resolvedCoverUrl = await coverSnap.ref.getDownloadURL();
            storagePaths.add(coverStoragePath);
          }
        } catch (e) {
          debugPrint('[UploadService] Custom cover upload error: $e');
        }
      }

      // 2c. Await background AI optimization (with short cap so upload never stalls)
      VideoOptimizationPackage? aiOpt;
      if (bgOptimizationFuture != null) {
        try {
          aiOpt = await bgOptimizationFuture.timeout(
            const Duration(seconds: 8),
            onTimeout: () => null,
          );
        } catch (_) {}
      }

      var effectiveTitle = (title ?? '').trim();
      var effectiveCaption = caption.trim();
      var effectiveCoverTimeMs = coverTimeMs ?? 0;

      if (aiOpt != null) {
        if (effectiveTitle.isEmpty && aiOpt.suggestedTitle.trim().isNotEmpty) {
          effectiveTitle = aiOpt.suggestedTitle.trim();
        }
        if (effectiveCaption.isEmpty) {
          effectiveCaption = aiOpt.suggestedDescription.trim();
        } else if (!effectiveCaption.contains('#') && aiOpt.suggestedHashtags.isNotEmpty) {
          effectiveCaption = '$effectiveCaption\n\n${aiOpt.suggestedHashtags.join(' ')}';
        }
        if (effectiveCoverTimeMs == 0 &&
            customCoverPath == null &&
            aiOpt.recommendedCoverTimeMs > 0) {
          effectiveCoverTimeMs = aiOpt.recommendedCoverTimeMs;
        }
      }

      // 3. Extract hashtags (#tag) and record with GlobalHashtagService
      final hashtagRegex = RegExp(r'#(\w+)');
      final hashtags = hashtagRegex
          .allMatches(effectiveCaption)
          .map((m) => m.group(1)!.toLowerCase())
          .toSet()
          .toList();
      if (hashtags.isEmpty && aiOpt != null) {
        for (final t in aiOpt.suggestedHashtags) {
          final clean = t.replaceAll('#', '').trim().toLowerCase();
          if (clean.isNotEmpty && !hashtags.contains(clean)) {
            hashtags.add(clean);
          }
        }
      }

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
        'title': effectiveTitle,
        'description': effectiveCaption,
        'type': isVideo ? 'short_video' : 'photo',
        'mediaUrl': mediaUrl,
        'coverUrl': resolvedCoverUrl ?? '',
        // Owner-deletable files backing this post (ContentDeletionService).
        'storagePaths': storagePaths,
        'coverTimeMs': effectiveCoverTimeMs,
        'mediaMetadata': {
          if (resolvedCoverUrl != null && resolvedCoverUrl.isNotEmpty)
            'thumbnailUrl': resolvedCoverUrl,
          'aspectRatio': aspectRatio ?? 9 / 16,
          'durationMs': isVideo ? (durationMs ?? 0) : 0,
          'effects': [],
          'filters': [],
          'hasCaptions': false,
          'highFidelityMaster': highQualityUploads,
          'uploadQualityTier': uploadQualityTier,
          'targetBitrateKbps': mediaSpec.inspection.estimatedBitrateKbps,
          'fps': mediaSpec.targetFps,
        },
        if (aiOpt != null)
          'aiOptimization': {
            'detectedNiche': aiOpt.detectedNiche,
            'channelName': aiOpt.channelName,
            'viralScore': aiOpt.viralScore,
            'analyzedVideoFrame': aiOpt.analyzedVideoFrame,
            'platformTitles': {
              for (final e in aiOpt.platformTitles.entries) e.key.name: e.value,
            },
            'platformCaptions': {
              for (final e in aiOpt.platformCaptions.entries) e.key.name: e.value,
            },
          },
        'selectedConnectedChannel': ?selectedConnectedChannel,
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

      // 5b. Auto-Publish to Selected Connected Channel in the Background!
      if (isVideo &&
          (selectedConnectedChannel != null || allDestinations.length > 1)) {
        unawaited(_autoPublishToConnectedChannel(
          contentId: contentDoc.id,
          videoFile: file,
          effectiveTitle: effectiveTitle,
          effectiveCaption: effectiveCaption,
          hashtags: hashtags,
          privacy: privacy,
          durationMs: durationMs,
          aspectRatio: aspectRatio,
          aiOpt: aiOpt,
          selectedConnectedChannel: selectedConnectedChannel,
          allDestinations: allDestinations,
        ));
      }

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
          final authorDoc =
              await FirebaseFirestore.instance.collection('users').doc(authorId).get();
          final authorData = authorDoc.data() ?? {};
          final authorName = authorData['displayName'] as String? ??
              authorData['username'] as String? ??
              'A creator';
          final authorAvatar = authorData['avatarUrl'] as String? ??
              authorData['profilePhotoUrl'] as String? ??
              '';

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
            final socialNotifRef =
                FirebaseFirestore.instance.collection('social_notifications').doc();
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
          caption: effectiveCaption,
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

  /// Automatically publishes the video with AI-tailored metadata to the user's
  /// selected connected channel (YouTube, TikTok, Instagram, Facebook) in the background.
  static Future<void> _autoPublishToConnectedChannel({
    required String contentId,
    required File videoFile,
    required String effectiveTitle,
    required String effectiveCaption,
    required List<String> hashtags,
    required String privacy,
    required int? durationMs,
    required double? aspectRatio,
    required VideoOptimizationPackage? aiOpt,
    required Map<String, dynamic>? selectedConnectedChannel,
    required Set<PlatformDestination> allDestinations,
  }) async {
    final contentRef = FirebaseFirestore.instance.collection('content').doc(contentId);
    final selectedPlatform =
        (selectedConnectedChannel?['platform'] ?? '').toString().toLowerCase();

    // 1. YouTube Channel Auto-Upload
    if (selectedPlatform == 'youtube' ||
        allDestinations.contains(PlatformDestination.youtube)) {
      try {
        final googleId = selectedConnectedChannel?['googleId']?.toString();
        final channelTitle = selectedConnectedChannel?['title']?.toString() ?? 'YouTube';
        final client = await GoogleServices.clientFor(
          GoogleService.youtube,
          sub: (googleId != null && googleId.isNotEmpty) ? googleId : null,
        );
        if (client != null && await videoFile.exists()) {
          final ytTitle = aiOpt?.platformTitles[PlatformDestination.youtube] ??
              (effectiveTitle.isNotEmpty ? effectiveTitle : 'Oneova Studio Reel #Shorts');
          final ytDesc = aiOpt?.platformCaptions[PlatformDestination.youtube] ??
              effectiveCaption;
          final isShort = (durationMs ?? 0) <= 60000 && (aspectRatio ?? 0.5625) <= 1.0;
          final ytPrivacy = privacy == 'private'
              ? 'private'
              : (privacy == 'followers' ? 'unlisted' : 'public');

          final ytService = YouTubeUploadService(client);
          final result = await ytService.uploadVideo(
            videoFile: videoFile,
            title: ytTitle,
            description: ytDesc,
            tags: hashtags.isEmpty ? const ['Oneova', 'Shorts'] : hashtags,
            privacyStatus: ytPrivacy,
            isShort: isShort,
          );
          client.close();

          await contentRef.set({
            'youtube': {
              'status': 'published',
              'videoId': result.videoId,
              'watchUrl': result.watchUrl,
              'shortsUrl': result.shortsUrl,
              'channelTitle': channelTitle,
              'publishedAt': FieldValue.serverTimestamp(),
            },
          }, SetOptions(merge: true));
          debugPrint('[UploadService] Auto-published to YouTube ($channelTitle): ${result.shortsUrl}');
        }
      } catch (e) {
        debugPrint('[UploadService] YouTube auto-publish non-fatal error: $e');
        await contentRef.set({
          'youtube': {
            'status': 'failed',
            'error': e.toString(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        }, SetOptions(merge: true));
      }
    }

    // 2. TikTok Auto-Publish (via tiktokPublish Cloud Function)
    if (selectedPlatform == 'tiktok' ||
        allDestinations.contains(PlatformDestination.tiktok)) {
      try {
        final tiktokCaption = aiOpt?.platformCaptions[PlatformDestination.tiktok] ??
            (effectiveCaption.isNotEmpty ? effectiveCaption : effectiveTitle);
        final tiktokPrivacy = privacy == 'private'
            ? 'SELF_ONLY'
            : (privacy == 'followers' ? 'MUTUAL_FOLLOW_FRIENDS' : 'PUBLIC_TO_EVERYONE');
        try {
          await FirebaseFunctions.instance.httpsCallable('tiktokPublish').call({
            'contentId': contentId,
            'mode': 'direct',
            'title': tiktokCaption,
            'privacyLevel': tiktokPrivacy,
          });
        } catch (_) {
          // Fallback to TikTok inbox draft mode if direct post isn't enabled on the account
          await FirebaseFunctions.instance.httpsCallable('tiktokPublish').call({
            'contentId': contentId,
            'mode': 'draft',
            'title': tiktokCaption,
          });
        }
        debugPrint('[UploadService] Auto-published to TikTok for contentId=$contentId');
      } catch (e) {
        debugPrint('[UploadService] TikTok auto-publish non-fatal error: $e');
      }
    }

    // 3. Instagram / Facebook Syndication Payload Record
    if (selectedPlatform == 'instagram' ||
        selectedPlatform == 'facebook' ||
        allDestinations.contains(PlatformDestination.instagram) ||
        allDestinations.contains(PlatformDestination.facebook)) {
      try {
        final igCaption =
            aiOpt?.platformCaptions[PlatformDestination.instagram] ?? effectiveCaption;
        final fbCaption =
            aiOpt?.platformCaptions[PlatformDestination.facebook] ?? effectiveCaption;
        await contentRef.set({
          'socialSyndication': {
            if (selectedPlatform == 'instagram' ||
                allDestinations.contains(PlatformDestination.instagram))
              'instagram': {
                'caption': igCaption,
                'accountName': selectedConnectedChannel?['title'] ?? '',
                'status': 'queued_syndication',
                'updatedAt': FieldValue.serverTimestamp(),
              },
            if (selectedPlatform == 'facebook' ||
                allDestinations.contains(PlatformDestination.facebook))
              'facebook': {
                'caption': fbCaption,
                'accountName': selectedConnectedChannel?['title'] ?? '',
                'status': 'queued_syndication',
                'updatedAt': FieldValue.serverTimestamp(),
              },
          },
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[UploadService] Meta syndication record non-fatal error: $e');
      }
    }
  }
}
