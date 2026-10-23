import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../backend/ai_agents/openrouter_agent_service.dart';
import '../../../backend/publishing/models/publishing_destination.dart';

class VideoOptimizationPackage {
  final String suggestedTitle;
  final String suggestedDescription;
  final List<String> suggestedHashtags;
  final String detectedNiche;
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
    required this.viralScore,
    required this.viralHooks,
    required this.recommendedCoverTimeMs,
    required this.optimizationRationale,
    required this.platformCaptions,
    required this.platformTitles,
    this.isAiGenerated = true,
  });

  factory VideoOptimizationPackage.fallback({
    required String rawCaption,
    String? mediaName,
    int? durationMs,
  }) {
    final cleanTopic = rawCaption.isNotEmpty
        ? rawCaption
        : (mediaName?.replaceAll(RegExp(r'[^a-zA-Z0-9 ]'), ' ').trim() ?? 'Exclusive Video');
    final title = cleanTopic.length > 50 ? '${cleanTopic.substring(0, 47)}...' : cleanTopic;

    return VideoOptimizationPackage(
      suggestedTitle: title.isNotEmpty ? title : 'Next-Level Studio Masterclass 🔥',
      suggestedDescription: rawCaption.isNotEmpty
          ? '$rawCaption\n\nExperience this in master lossless fidelity on Oneova. What are your thoughts on this? Drop a comment below 👇'
          : 'Wait till the end! 🤯 Discover the exact technique behind this result.\n\nSave this reel for later & follow for daily creator drops.',
      suggestedHashtags: const [
        '#oneova',
        '#fyp',
        '#viral',
        '#creatorstudio',
        '#trending',
        '#reels',
        '#masterclass',
      ],
      detectedNiche: 'Creative Production & Visual Arts',
      viralScore: 84,
      viralHooks: [
        'Stop scrolling: The #1 thing creators overlook 🤫',
        'If you make this 1 mistake, you are losing 80% of your audience 🚨',
        'The exact formula behind 10x viral retention 📈',
      ],
      recommendedCoverTimeMs: durationMs != null && durationMs > 2000 ? 1200 : 500,
      optimizationRationale:
          'High curiosity loop with strong visual contrast and open loop engagement.',
      platformCaptions: {
        PlatformDestination.internal:
            'Streaming in master lossless fidelity on Oneova. Co-authors & collaborators tagged below. #oneova #creators',
        PlatformDestination.tiktok:
            'Wait till the end! 🤯 Drop your thoughts below 👇 #fyp #viral #trending',
        PlatformDestination.instagram:
            'Elevate your creative vision ✨ Save this post for reference later! #reels #explore',
        PlatformDestination.youtube:
            'Watch till the end for the key breakdown! Subscribe to Oneova for daily pro creator workflows. #shorts',
        PlatformDestination.whatsappBusiness:
            'Hey! Just published an exclusive new reel on Oneova. Check it out and let me know your thoughts!',
        PlatformDestination.facebook:
            'We’ve all experienced this moment firsthand. Share with someone who needs this perspective today!',
      },
      platformTitles: {
        PlatformDestination.youtube: 'HOW TO ELEVATE YOUR CONTENT CREATION 🔥',
        PlatformDestination.internal: 'Oneova Master Broadcast',
      },
      isAiGenerated: false,
    );
  }
}

final openRouterPostOptimizerProvider = Provider<OpenRouterPostOptimizer>((ref) {
  final agent = ref.watch(openRouterAgentServiceProvider);
  return OpenRouterPostOptimizer(agent);
});

/// Intelligent Multi-Platform AI Agent with built-in skills for:
/// - Oneova Reels (PRIMARY · LOCKED)
/// - TikTok Direct
/// - Instagram Reels
/// - YouTube Shorts
/// - WhatsApp Business API
/// - Facebook Reels
class OpenRouterPostOptimizer {
  final OpenRouterAgentService _agentService;

  OpenRouterPostOptimizer(this._agentService);

  /// Performs background analysis of the video metadata, creator's draft caption,
  /// and target destinations, returning an end-to-end optimization package.
  Future<VideoOptimizationPackage> analyzeAndOptimize({
    required String mediaPath,
    required bool isVideo,
    String? currentCaption,
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

    const systemPrompt = '''
You are Oneova's Premier AI Video Director & Cross-Platform Viral Optimization Agent.
You possess deep, specialized algorithmic publishing knowledge for short-form video networks:
1. Oneova Reels (PRIMARY · LOCKED): Master lossless fidelity, LinUCB viral incubator, fast-trend pulse accelerator badge, collaborator co-authoring, genuine community engagement.
2. TikTok Direct: 3-second pattern interrupts, retention loops, curiosity gap hooks, trending sounds synergy, TikTok SEO keywords.
3. Instagram Reels: Aesthetic paragraph spacing, high-save value, clean CTA, targeted 3-5 niche tags.
4. YouTube Shorts: High-CTR uppercase power titles (<60 chars), keyword-dense description, #shorts tag.
5. WhatsApp Business API: Direct conversational VIP broadcast tone, status updates, client conversion.
6. Facebook Reels: Relatable storytelling, emotional triggers, community debate prompt.

Analyze the video specs and creator notes. Output ONLY a valid JSON object matching this schema:
{
  "suggestedTitle": "Catchy high-CTR title",
  "suggestedDescription": "Comprehensive caption with hooks, linebreaks, and CTA",
  "suggestedHashtags": ["#oneova", "#fyp", "#viral", "#tech", "#creator"],
  "detectedNiche": "e.g., Tech / AI, Music Production, Filmmaking, Lifestyle, Comedy",
  "viralScore": 92,
  "viralHooks": [
    "Hook option 1",
    "Hook option 2",
    "Hook option 3"
  ],
  "recommendedCoverTimeMs": 1500,
  "optimizationRationale": "Explanation of viral pacing and hooks used",
  "platformCaptions": {
    "internal": "Caption for Oneova",
    "tiktok": "Punchy TikTok caption",
    "instagram": "Clean aesthetic IG caption",
    "youtube": "Shorts description with keywords",
    "whatsappBusiness": "Conversational WhatsApp message",
    "facebook": "Relatable FB caption"
  },
  "platformTitles": {
    "youtube": "ALL CAPS SHORTS TITLE 🔥",
    "internal": "Oneova Feature Title"
  }
}
''';

    final userPrompt = '''
Video File: "$fileName"
Duration: ${durationSeconds.toStringAsFixed(1)}s
Aspect Ratio: $aspectString
Current Creator Input / Draft Notes: "${currentCaption ?? ''}"
Target Platforms: [${destinations.map((d) => d.name).join(', ')}]

Analyze this video now and return the comprehensive optimization package JSON.
''';

    try {
      final responseText = await _agentService.queryAgent(
        systemPrompt,
        userPrompt,
        timeout: const Duration(seconds: 15),
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

        final title = parsed['suggestedTitle'] as String? ?? 'Oneova Master Reel';
        final description = parsed['suggestedDescription'] as String? ?? (currentCaption ?? '');
        final hashtags = (parsed['suggestedHashtags'] as List<dynamic>?)
                ?.map((e) => e.toString().startsWith('#') ? e.toString() : '#$e')
                .toList() ??
            [];
        final niche = parsed['detectedNiche'] as String? ?? 'Creative Production';
        final score = ((parsed['viralScore'] as num?)?.toInt() ?? 88).clamp(1, 100);
        final hooks = (parsed['viralHooks'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        final coverMs = (parsed['recommendedCoverTimeMs'] as num?)?.toInt() ?? 1200;
        final rationale = parsed['optimizationRationale'] as String? ??
            'Optimized with viral curiosity gaps and cross-platform algorithms.';

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
              : ['#oneova', '#fyp', '#viral', '#trending'],
          detectedNiche: niche,
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
      debugPrint('[OpenRouterPostOptimizer] AI analysis failed, falling back to heuristics: $e');
    }

    return VideoOptimizationPackage.fallback(
      rawCaption: currentCaption ?? '',
      mediaName: fileName,
      durationMs: durationMs,
    );
  }
}
