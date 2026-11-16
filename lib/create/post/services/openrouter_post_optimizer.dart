import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_compress/video_compress.dart';
import '../../../backend/ai_agents/openrouter_agent_service.dart';
import '../../../backend/publishing/models/publishing_destination.dart';

class CreatorChannelContext {
  final String channelName;
  final String bio;
  final String inferredNiche;
  final List<String> recentTitles;
  final List<String> topHashtags;
  final List<String> connectedChannelLabels;

  const CreatorChannelContext({
    required this.channelName,
    required this.bio,
    required this.inferredNiche,
    required this.recentTitles,
    required this.topHashtags,
    required this.connectedChannelLabels,
  });

  String toPromptSummary() {
    final parts = <String>[
      'Creator / Channel Name: $channelName',
      'Channel Niche & Focus: $inferredNiche',
      if (bio.isNotEmpty) 'Creator Bio: $bio',
      if (connectedChannelLabels.isNotEmpty)
        'Connected Channels: ${connectedChannelLabels.join(', ')}',
      if (recentTitles.isNotEmpty)
        'Recent Channel Videos: ${recentTitles.take(5).join(' | ')}',
      if (topHashtags.isNotEmpty)
        'Signature Channel Tags: ${topHashtags.take(8).join(' ')}',
    ];
    return parts.join('\n');
  }
}

class VideoOptimizationPackage {
  final String suggestedTitle;
  final String suggestedDescription;
  final List<String> suggestedHashtags;
  final String detectedNiche;
  final String channelName;
  final bool analyzedVideoFrame;
  final int viralScore;
  final List<String> viralHooks;
  final int recommendedCoverTimeMs;
  final String optimizationRationale;
  final Map<PlatformDestination, String> platformCaptions;
  final Map<PlatformDestination, String> platformTitles;
  final bool isAiGenerated;

  const VideoOptimizationPackage({
    required this.suggestedTitle,
    required this.suggestedDescription,
    required this.suggestedHashtags,
    required this.detectedNiche,
    this.channelName = '',
    this.analyzedVideoFrame = false,
    required this.viralScore,
    required this.viralHooks,
    required this.recommendedCoverTimeMs,
    required this.optimizationRationale,
    required this.platformCaptions,
    required this.platformTitles,
    this.isAiGenerated = true,
  });

  factory VideoOptimizationPackage.fallback({
    String? rawTitle,
    required String rawCaption,
    String? mediaName,
    int? durationMs,
    CreatorChannelContext? channelCtx,
    bool analyzedVideoFrame = false,
  }) {
    final seed = (rawTitle != null && rawTitle.trim().isNotEmpty)
        ? rawTitle.trim()
        : (rawCaption.trim().isNotEmpty
            ? rawCaption.trim()
            : (mediaName?.replaceAll(RegExp(r'[^a-zA-Z0-9 ]'), ' ').trim() ??
                'Exclusive Studio Drop'));
    final niche = channelCtx?.inferredNiche.isNotEmpty == true
        ? channelCtx!.inferredNiche
        : 'Creative Production & Digital Culture';
    final channelLabel = channelCtx?.channelName.isNotEmpty == true
        ? channelCtx!.channelName
        : 'Oneova Creator';

    final cleanTitle = seed.length > 56 ? '${seed.substring(0, 53)}...' : seed;
    final finalTitle = cleanTitle.isNotEmpty
        ? cleanTitle
        : '$channelLabel · $niche Spotlight 🔥';

    final baseTags = <String>{
      '#oneova',
      ...(channelCtx?.topHashtags ?? const <String>[]),
      '#fyp',
      '#viral',
      '#reels',
      '#shorts',
      '#trending',
    }.take(8).toList();

    final finalDesc = rawCaption.trim().isNotEmpty
        ? '${rawCaption.trim()}\n\nOptimized for $channelLabel ($niche). Drop your thoughts below 👇\n${baseTags.join(' ')}'
        : '$finalTitle — full breakdown for our $niche community.\n\nWatch till the end & follow $channelLabel for more! 👇\n${baseTags.join(' ')}';

    return VideoOptimizationPackage(
      suggestedTitle: finalTitle,
      suggestedDescription: finalDesc,
      suggestedHashtags: baseTags,
      detectedNiche: niche,
      channelName: channelLabel,
      analyzedVideoFrame: analyzedVideoFrame,
      viralScore: 88,
      viralHooks: [
        'Stop scrolling: Why this changes everything in $niche 🔥',
        'Watch till the end for the full $finalTitle breakdown 👇',
        'The #1 technique top creators in $niche use every day 📈',
      ],
      recommendedCoverTimeMs:
          durationMs != null && durationMs > 2000 ? 1200 : 500,
      optimizationRationale:
          'Tailored to $channelLabel ($niche) with high-retention hooks and cross-platform keywords.',
      platformCaptions: {
        PlatformDestination.internal: finalDesc,
        PlatformDestination.tiktok:
            '$finalTitle 🤯 Wait till the end! Drop your thoughts 👇 ${baseTags.take(5).join(' ')}',
        PlatformDestination.instagram:
            '$finalTitle ✨\n.\nSave this post for reference & share with someone in $niche!\n.\n${baseTags.take(5).join(' ')}',
        PlatformDestination.youtube:
            '$finalTitle\n\nSubscribe to $channelLabel for more $niche videos & Shorts! #Shorts ${baseTags.take(4).join(' ')}',
        PlatformDestination.whatsappBusiness:
            'New video is live: "$finalTitle" — check it out and reply with your thoughts!',
        PlatformDestination.facebook:
            '$finalTitle — what would you do in this situation? Let us know in the comments!',
      },
      platformTitles: {
        PlatformDestination.youtube: '$finalTitle #Shorts',
        PlatformDestination.tiktok: finalTitle,
        PlatformDestination.instagram: finalTitle,
        PlatformDestination.facebook: finalTitle,
        PlatformDestination.internal: finalTitle,
      },
      isAiGenerated: false,
    );
  }
}

final openRouterPostOptimizerProvider = Provider<OpenRouterPostOptimizer>((ref) {
  final agent = ref.watch(openRouterAgentServiceProvider);
  return OpenRouterPostOptimizer(agent);
});

/// Intelligent Multi-Platform AI Agent that:
/// 1. Extracts a real visual frame from the video clip (or image) for Gemini Vision.
/// 2. Automatically learns the creator's channel profile, niche, and past content from Firestore.
/// 3. Synthesizes optimized titles, descriptions, hashtags, and platform-specific captions
///    in the background so posting to Oneova and any connected channel is effortless.
class OpenRouterPostOptimizer {
  final OpenRouterAgentService _agentService;

  static CreatorChannelContext? _cachedChannelCtx;
  static DateTime? _cachedChannelAt;
  static String? _cachedChannelUid;

  OpenRouterPostOptimizer(this._agentService);

  /// Standalone helper so background upload workers (`UploadService`) can run
  /// full AI video + channel optimization without a Riverpod `WidgetRef`.
  static Future<VideoOptimizationPackage> optimizeInBackground({
    required String mediaPath,
    required bool isVideo,
    String? currentTitle,
    String? currentCaption,
    String? selectedChannelLabel,
    int? durationMs,
    double? aspectRatio,
    List<PlatformDestination> destinations = const [PlatformDestination.internal],
  }) {
    final optimizer = OpenRouterPostOptimizer(OpenRouterAgentService());
    return optimizer.analyzeAndOptimize(
      mediaPath: mediaPath,
      isVideo: isVideo,
      currentTitle: currentTitle,
      currentCaption: currentCaption,
      selectedChannelLabel: selectedChannelLabel,
      durationMs: durationMs,
      aspectRatio: aspectRatio,
      destinations: destinations,
    );
  }

  /// Inspects the signed-in creator's Firestore profile, recent posts, and linked
  /// channels to automatically understand their channel identity and niche.
  Future<CreatorChannelContext> loadCreatorChannelContext() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return const CreatorChannelContext(
        channelName: 'Oneova Creator',
        bio: '',
        inferredNiche: 'Creative Studio & Entertainment',
        recentTitles: [],
        topHashtags: ['#oneova', '#reels', '#viral'],
        connectedChannelLabels: [],
      );
    }

    if (_cachedChannelCtx != null &&
        _cachedChannelUid == uid &&
        _cachedChannelAt != null &&
        DateTime.now().difference(_cachedChannelAt!) < const Duration(minutes: 5)) {
      return _cachedChannelCtx!;
    }

    try {
      final db = FirebaseFirestore.instance;
      final results = await Future.wait([
        db.collection('users').doc(uid).get(),
        db
            .collection('content')
            .where('authorId', isEqualTo: uid)
            .limit(8)
            .get(),
        db.collection('users').doc(uid).collection('youtube_accounts').get(),
        db.collection('users').doc(uid).collection('social_connections').get(),
      ]);

      final userDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final contentSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;
      final ytSnap = results[2] as QuerySnapshot<Map<String, dynamic>>;
      final socialSnap = results[3] as QuerySnapshot<Map<String, dynamic>>;

      final userData = userDoc.data() ?? const <String, dynamic>{};
      var channelName = (userData['displayName'] ??
              userData['username'] ??
              userData['name'] ??
              'Oneova Creator')
          .toString()
          .trim();
      final bio = (userData['bio'] ?? userData['about'] ?? '').toString().trim();
      final profileCategory =
          (userData['category'] ?? userData['niche'] ?? userData['profession'] ?? '')
              .toString()
              .trim();

      final connectedLabels = <String>[];
      for (final d in ytSnap.docs) {
        final data = d.data();
        final channels = (data['channels'] as List? ?? const []).whereType<Map>();
        for (final ch in channels) {
          final title = (ch['title'] ?? '').toString().trim();
          if (title.isNotEmpty) {
            connectedLabels.add('YouTube: $title');
            if (ch['isActive'] == true && channelName == 'Oneova Creator') {
              channelName = title;
            }
          }
        }
      }
      for (final d in socialSnap.docs) {
        final data = d.data();
        final plat = (data['platform'] ?? d.id).toString();
        final accName = (data['accountName'] ?? data['username'] ?? '').toString().trim();
        if (accName.isNotEmpty) {
          connectedLabels.add('$plat: $accName');
        }
      }

      final recentTitles = <String>[];
      final tagCounts = <String, int>{};
      for (final doc in contentSnap.docs) {
        final d = doc.data();
        final t = (d['title'] ?? '').toString().trim();
        final desc = (d['description'] ?? '').toString().trim();
        if (t.isNotEmpty) {
          recentTitles.add(t);
        } else if (desc.isNotEmpty) {
          recentTitles.add(desc.length > 60 ? '${desc.substring(0, 60)}...' : desc);
        }
        final tags = (d['hashtags'] as List? ?? const []);
        for (final rawTag in tags) {
          final clean = rawTag.toString().trim().toLowerCase().replaceAll('#', '');
          if (clean.isNotEmpty) {
            tagCounts['#$clean'] = (tagCounts['#$clean'] ?? 0) + 1;
          }
        }
      }

      final sortedTags = tagCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topHashtags = sortedTags.take(8).map((e) => e.key).toList();

      String inferredNiche = profileCategory;
      if (inferredNiche.isEmpty) {
        final corpus = '$bio ${recentTitles.join(' ')} ${topHashtags.join(' ')}'.toLowerCase();
        if (corpus.contains('music') || corpus.contains('beat') || corpus.contains('song') || corpus.contains('studio')) {
          inferredNiche = 'Music Production & Audio Studio';
        } else if (corpus.contains('tech') || corpus.contains('ai') || corpus.contains('code') || corpus.contains('app')) {
          inferredNiche = 'Tech, AI & Digital Innovation';
        } else if (corpus.contains('business') || corpus.contains('shop') || corpus.contains('finance') || corpus.contains('entrepreneur')) {
          inferredNiche = 'Business, Commerce & Entrepreneurship';
        } else if (corpus.contains('comedy') || corpus.contains('funny') || corpus.contains('skit') || corpus.contains('prank')) {
          inferredNiche = 'Comedy & Entertainment';
        } else if (corpus.contains('fashion') || corpus.contains('beauty') || corpus.contains('style') || corpus.contains('glow')) {
          inferredNiche = 'Fashion, Beauty & Lifestyle';
        } else if (corpus.contains('fitness') || corpus.contains('gym') || corpus.contains('sport') || corpus.contains('football')) {
          inferredNiche = 'Sports, Fitness & Athletics';
        } else if (corpus.contains('food') || corpus.contains('cook') || corpus.contains('recipe')) {
          inferredNiche = 'Food & Culinary Arts';
        } else if (corpus.contains('travel') || corpus.contains('vlog') || corpus.contains('explore')) {
          inferredNiche = 'Travel, Vlogs & Lifestyle';
        } else {
          inferredNiche = 'Creative Content & Digital Culture';
        }
      }

      final ctx = CreatorChannelContext(
        channelName: channelName,
        bio: bio,
        inferredNiche: inferredNiche,
        recentTitles: recentTitles,
        topHashtags: topHashtags.isEmpty ? const ['#oneova', '#fyp', '#viral'] : topHashtags,
        connectedChannelLabels: connectedLabels,
      );
      _cachedChannelCtx = ctx;
      _cachedChannelUid = uid;
      _cachedChannelAt = DateTime.now();
      return ctx;
    } catch (e) {
      debugPrint('[OpenRouterPostOptimizer] Channel context load error: $e');
      return const CreatorChannelContext(
        channelName: 'Oneova Creator',
        bio: '',
        inferredNiche: 'Creative Studio & Entertainment',
        recentTitles: [],
        topHashtags: ['#oneova', '#reels', '#viral'],
        connectedChannelLabels: [],
      );
    }
  }

  /// Extracts a real visual frame from the video clip (or photo) as base64 JPEG
  /// so Gemini Vision can see the actual video clip content.
  Future<String?> _extractVisualFrameBase64(String mediaPath, bool isVideo, int? durationMs) async {
    try {
      final f = File(mediaPath);
      if (!await f.exists()) return null;

      if (!isVideo) {
        final bytes = await f.readAsBytes();
        if (bytes.lengthInBytes > 0 && bytes.lengthInBytes < 2 * 1024 * 1024) {
          return base64Encode(bytes);
        }
        return null;
      }

      final samplePosMs = (durationMs != null && durationMs > 2500) ? 1200 : 500;
      final thumbFile = await VideoCompress.getFileThumbnail(
        mediaPath,
        quality: 68,
        position: samplePosMs,
      ).timeout(const Duration(seconds: 6));

      if (await thumbFile.exists()) {
        final bytes = await thumbFile.readAsBytes();
        if (bytes.isNotEmpty && bytes.lengthInBytes < 2 * 1024 * 1024) {
          return base64Encode(bytes);
        }
      }
    } catch (e) {
      debugPrint('[OpenRouterPostOptimizer] Video frame extraction non-fatal: $e');
    }
    return null;
  }

  /// Performs background analysis of:
  /// 1. Real visual frame from the video clip (`_extractVisualFrameBase64`)
  /// 2. Creator's channel & niche profile (`loadCreatorChannelContext`)
  /// 3. User's video title / topic description (`currentTitle`) & draft caption (`currentCaption`)
  /// 4. Selected connected channel (`selectedChannelLabel`) & target destinations
  Future<VideoOptimizationPackage> analyzeAndOptimize({
    required String mediaPath,
    required bool isVideo,
    String? currentTitle,
    String? currentCaption,
    String? selectedChannelLabel,
    int? durationMs,
    double? aspectRatio,
    List<PlatformDestination> destinations = const [PlatformDestination.internal],
  }) async {
    final fileName = File(mediaPath).uri.pathSegments.isNotEmpty
        ? File(mediaPath).uri.pathSegments.last
        : 'video.mp4';
    final durationSeconds = (durationMs ?? 0) / 1000.0;
    final aspectString = aspectRatio != null
        ? (aspectRatio < 0.8 ? '9:16 Vertical Reel' : '16:9 Landscape')
        : '9:16 Vertical';

    // Run channel niche discovery and real video clip frame extraction in parallel!
    final parallelResults = await Future.wait([
      loadCreatorChannelContext(),
      _extractVisualFrameBase64(mediaPath, isVideo, durationMs),
    ]);
    final channelCtx = parallelResults[0] as CreatorChannelContext;
    final frameBase64 = parallelResults[1] as String?;
    final hasVisualFrame = frameBase64 != null && frameBase64.isNotEmpty;

    const systemPrompt = '''
You are Oneova's Premier AI Video Director, Channel Analyst & Cross-Platform Viral Optimization Agent.
You analyze:
1. The REAL visual frame from the creator's video clip (if attached).
2. The creator's Channel Profile, Niche, Bio, and Past Content style.
3. The creator's Video Title / Topic description (if provided).
4. The target connected channel / platform so the post is automatically tailored and ready to publish on both Oneova and the connected channel.

Output ONLY a valid JSON object matching this exact schema:
{
  "suggestedTitle": "Catchy high-CTR title (<60 chars) matching the video clip, user's title topic, and channel niche",
  "suggestedDescription": "Engaging caption with a strong 1st-line hook, value breakdown, CTA, and relevant hashtags",
  "suggestedHashtags": ["#oneova", "#nichetag1", "#nichetag2", "#viral", "#fyp", "#shorts"],
  "detectedNiche": "Specific niche of this video & channel (e.g. Tech & AI, Music Studio, Comedy, Fashion, Business)",
  "viralScore": 94,
  "viralHooks": [
    "Hook option 1",
    "Hook option 2",
    "Hook option 3"
  ],
  "recommendedCoverTimeMs": 1400,
  "optimizationRationale": "1-sentence explanation of how this matches the video clip and channel niche",
  "platformCaptions": {
    "internal": "Caption for Oneova Reels",
    "tiktok": "Punchy TikTok caption with curiosity hook and tags",
    "instagram": "Clean aesthetic Instagram Reels caption",
    "youtube": "Keyword-rich YouTube Shorts description with #Shorts",
    "whatsappBusiness": "Direct conversational broadcast message",
    "facebook": "Relatable storytelling Facebook Reels caption"
  },
  "platformTitles": {
    "youtube": "HIGH-CTR YOUTUBE SHORTS TITLE 🔥 #Shorts",
    "tiktok": "Punchy TikTok Headline",
    "instagram": "Instagram Reel Title",
    "facebook": "Facebook Reel Title",
    "internal": "Oneova Feature Title"
  }
}
''';

    final userPrompt = '''
=== CREATOR CHANNEL & NICHE INTELLIGENCE ===
${channelCtx.toPromptSummary()}
${selectedChannelLabel != null && selectedChannelLabel.isNotEmpty ? 'Selected Connected Channel for Auto-Post: $selectedChannelLabel' : ''}

=== VIDEO CLIP & CREATOR INPUT ===
Media Type: ${isVideo ? 'Video Clip' : 'Photo'} ("$fileName")
Duration: ${durationSeconds.toStringAsFixed(1)}s ($aspectString)
Visual Frame Attached: ${hasVisualFrame ? 'YES — inspect the attached video frame carefully to see what is happening in the clip!' : 'No'}
Creator's Video Title / Topic Description: "${currentTitle ?? ''}"
Creator's Draft Caption / Notes: "${currentCaption ?? ''}"
Target Platforms: [${destinations.map((d) => d.name).join(', ')}]

Generate the complete JSON optimization package now. If the creator provided a Video Title or topic, build directly upon it and enrich it for their niche and the visual frame. If they left the title/caption blank, invent a compelling, accurate title and caption from the visual frame and their channel niche.
''';

    try {
      final responseText = await _agentService.queryAgent(
        systemPrompt,
        userPrompt,
        model: 'google/gemini-2.5-flash',
        imageBase64: frameBase64,
        timeout: const Duration(seconds: 18),
      );

      if (responseText != null && responseText.trim().isNotEmpty) {
        String cleaned = responseText.trim();
        if (cleaned.startsWith('```json')) {
          cleaned = cleaned.substring(7);
        } else if (cleaned.startsWith('```')) {
          cleaned = cleaned.substring(3);
        }
        if (cleaned.endsWith('```')) {
          cleaned = cleaned.substring(0, cleaned.length - 3);
        }
        cleaned = cleaned.trim();

        final parsed = jsonDecode(cleaned) as Map<String, dynamic>;

        final title = parsed['suggestedTitle'] as String? ??
            (currentTitle?.isNotEmpty == true ? currentTitle! : 'Oneova Studio Reel');
        final description = parsed['suggestedDescription'] as String? ?? (currentCaption ?? '');
        final hashtags = (parsed['suggestedHashtags'] as List<dynamic>?)
                ?.map((e) => e.toString().startsWith('#') ? e.toString() : '#$e')
                .toList() ??
            [];
        final niche = parsed['detectedNiche'] as String? ?? channelCtx.inferredNiche;
        final score = ((parsed['viralScore'] as num?)?.toInt() ?? 90).clamp(1, 100);
        final hooks = (parsed['viralHooks'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        final coverMs = (parsed['recommendedCoverTimeMs'] as num?)?.toInt() ?? 1200;
        final rationale = parsed['optimizationRationale'] as String? ??
            'Tailored from your video clip frame and ${channelCtx.channelName} niche.';

        final rawCaptions = parsed['platformCaptions'] as Map<String, dynamic>? ?? {};
        final Map<PlatformDestination, String> platformCaptions = {};
        for (final dest in PlatformDestination.values) {
          final val = rawCaptions[dest.name];
          if (val != null) {
            platformCaptions[dest] = val.toString();
          }
        }

        final rawTitles = parsed['platformTitles'] as Map<String, dynamic>? ?? {};
        final Map<PlatformDestination, String> platformTitles = {};
        for (final dest in PlatformDestination.values) {
          final val = rawTitles[dest.name];
          if (val != null) {
            platformTitles[dest] = val.toString();
          }
        }

        return VideoOptimizationPackage(
          suggestedTitle: title,
          suggestedDescription: description,
          suggestedHashtags: hashtags.isNotEmpty
              ? hashtags
              : ['#oneova', ...channelCtx.topHashtags.take(4), '#fyp', '#viral'],
          detectedNiche: niche,
          channelName: channelCtx.channelName,
          analyzedVideoFrame: hasVisualFrame,
          viralScore: score,
          viralHooks: hooks.isNotEmpty
              ? hooks
              : ['Wait till you see this! 🔥', 'The secret nobody told you 🤫'],
          recommendedCoverTimeMs: coverMs,
          optimizationRationale: rationale,
          platformCaptions: platformCaptions,
          platformTitles: platformTitles,
          isAiGenerated: true,
        );
      }
    } catch (e) {
      debugPrint('[OpenRouterPostOptimizer] AI analysis failed, using channel-aware fallback: $e');
    }

    return VideoOptimizationPackage.fallback(
      rawTitle: currentTitle,
      rawCaption: currentCaption ?? '',
      mediaName: fileName,
      durationMs: durationMs,
      channelCtx: channelCtx,
      analyzedVideoFrame: hasVisualFrame,
    );
  }
}
