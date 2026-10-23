import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/publishing/models/publishing_destination.dart';
import 'package:oneova/backend/publishing/services/ai_content_optimizer_service.dart';
import 'package:oneova/backend/ai_agents/openrouter_agent_service.dart';
import 'package:oneova/backend/media/high_fidelity_media_engine.dart';
import 'package:oneova/backend/social/services/collab_service.dart';

void main() {
  group('AIContentOptimizerService Tests', () {
    late AIContentOptimizerService optimizer;

    setUp(() {
      optimizer = AIContentOptimizerService(OpenRouterAgentService());
    });

    test('Optimizes content across destinations and calculates viral hook score', () async {
      const caption = 'How to edit 10x faster using secret shortcuts in Oneova!';
      final platforms = [
        PlatformDestination.tiktok,
        PlatformDestination.instagram,
        PlatformDestination.youtube,
        PlatformDestination.twitter,
        PlatformDestination.facebook,
        PlatformDestination.internal,
      ];

      final result = await optimizer.optimizeContent(
        caption: caption,
        platforms: platforms,
        category: 'Filmmaking & Video Production',
      );

      // Viral Hook Score validation (0-100)
      expect(result.viralHookScore, greaterThanOrEqualTo(0));
      expect(result.viralHookScore, lessThanOrEqualTo(100));

      // Hook Suggestions (exactly 3 catchy hooks)
      expect(result.hookSuggestions.length, 3);
      for (final hook in result.hookSuggestions) {
        expect(hook.isNotEmpty, true);
      }

      // Recommended Hashtags (6-10 trending tags with velocity tags)
      expect(result.recommendedHashtags.length, greaterThanOrEqualTo(6));
      expect(result.recommendedHashtags.length, lessThanOrEqualTo(10));
      expect(result.recommendedHashtags.contains('#fyp'), true);
      expect(result.recommendedHashtags.contains('#viral'), true);
      expect(result.recommendedHashtags.contains('#oneova'), true);

      // Recommended posting time
      expect(result.recommendedPostTime.isNotEmpty, true);
      expect(result.recommendedPostTime.contains('Velocity'), true);

      // Platform Tailoring
      // TikTok: Punchy, slang, trend tags
      final tiktok = result.platformOptimizations[PlatformDestination.tiktok]!;
      expect(tiktok.caption.contains('#fyp'), true);

      // Instagram: Visual aesthetic, spaced dots
      final insta = result.platformOptimizations[PlatformDestination.instagram]!;
      expect(insta.caption.contains('.'), true);
      expect(insta.caption.contains('Save this post'), true);

      // YouTube Shorts: High-CTR uppercase title + search-optimized description
      final yt = result.platformOptimizations[PlatformDestination.youtube]!;
      expect(yt.title.isNotEmpty, true);
      expect(yt.caption.contains('#shorts'), true);

      // Twitter / X: Under 280 characters with controversy/debate hook
      final twitter = result.platformOptimizations[PlatformDestination.twitter]!;
      expect(twitter.caption.length, lessThanOrEqualTo(280));
      expect(twitter.caption.contains('Hot take:'), true);

      // Facebook Reels: Relatable storytelling narrative hook
      final fb = result.platformOptimizations[PlatformDestination.facebook]!;
      expect(fb.caption.contains('experienced this moment'), true);

      // Oneova native: High-velocity community engagement hook & collaborator tags
      final oneova = result.platformOptimizations[PlatformDestination.internal]!;
      expect(oneova.caption.contains('lossless fidelity'), true);
    });
  });

  group('HighFidelityMediaEngine Tests', () {
    late HighFidelityMediaEngine engine;
    late Directory tempDir;
    late File testVideoFile;

    setUp(() async {
      engine = HighFidelityMediaEngine();
      tempDir = await Directory.systemTemp.createTemp('oneova_test_');
      testVideoFile = File('${tempDir.path}/sample_render.mp4');
      // Create a 2MB dummy payload
      await testVideoFile.writeAsBytes(List<int>.filled(1024 * 1024 * 2, 42));
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Generates HighFidelityMediaSpec adhering to lossless streaming guidelines', () async {
      final spec = await engine.inspectAndGenerateSpec(
        file: testVideoFile,
        ownerId: 'creator_99',
        forcedWidth: 1080,
        forcedHeight: 1920,
      );

      // Raw master preservation
      expect(spec.isRawMasterPreserved, true);
      expect(spec.rawMasterStoragePath.startsWith('masters/creator_99/'), true);

      // Delivery parameters: 1080p 60fps, CRF 18 visually lossless, fast-start moov atom, AAC 320kbps
      expect(spec.targetFps, 60);
      expect(spec.crf, 18);
      expect(spec.hasFastStartMoovAtom, true);
      expect(spec.audioBitrateKbps, 320);
      expect(spec.audioSampleRate, 48000);
      expect(spec.pixelFormat, 'yuv420p');
      expect(spec.colorSpace, 'bt709');

      // Cross-platform protection profiles
      expect(spec.platformProfiles.containsKey(PlatformDestination.tiktok), true);
      expect(spec.platformProfiles.containsKey(PlatformDestination.instagram), true);
      expect(spec.platformProfiles.containsKey(PlatformDestination.youtube), true);
      expect(spec.platformProfiles.containsKey(PlatformDestination.twitter), true);
      expect(spec.platformProfiles.containsKey(PlatformDestination.facebook), true);
      expect(spec.platformProfiles.containsKey(PlatformDestination.internal), true);

      // Clamped bitrate for TikTok & YouTube
      expect(spec.platformProfiles[PlatformDestination.tiktok]!.maxBitrateKbps, 12000);
      expect(spec.platformProfiles[PlatformDestination.youtube]!.crf, 16);

      // FFmpeg CLI argument generation
      final ffmpegArgs = engine.getFfmpegArguments(
        inputPath: testVideoFile.path,
        outputPath: '${tempDir.path}/out.mp4',
        spec: spec,
      );

      expect(ffmpegArgs.contains('-movflags'), true);
      expect(ffmpegArgs.contains('+faststart'), true);
      expect(ffmpegArgs.contains('libx264'), true);
      expect(ffmpegArgs.contains('320k'), true);
      expect(ffmpegArgs.contains('48000'), true);
    });
  });

  group('CollabService Models & Logic Tests', () {
    test('ContentCollaborator serialization and role formatting', () {
      final now = DateTime.now();
      final collab = ContentCollaborator(
        id: 'collab_user_1',
        contentId: 'post_123',
        inviterId: 'creator_owner',
        collaboratorUserId: 'collab_user_1',
        collaboratorUsername: 'sarah_creator',
        collaboratorDisplayName: 'Sarah Studio',
        collaboratorAvatarUrl: 'https://cdn.oneova.com/sarah.jpg',
        role: CollaboratorRole.coAuthor,
        status: CollabInviteStatus.pending,
        revenueSplitPercent: 50.0,
        invitedAt: now,
      );

      expect(collab.role.displayName, 'Co-Author');
      expect(collab.status, CollabInviteStatus.pending);

      final map = collab.toMap();
      expect(map['contentId'], 'post_123');
      expect(map['revenueSplitPercent'], 50.0);
      expect(map['role'], 'coAuthor');

      final copied = collab.copyWith(status: CollabInviteStatus.accepted);
      expect(copied.status, CollabInviteStatus.accepted);
      expect(copied.contentId, 'post_123');
    });
  });
}
