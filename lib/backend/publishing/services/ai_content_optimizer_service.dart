import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/publishing_destination.dart';
import '../../ai_agents/openrouter_agent_service.dart';

/// Represents optimized content tailored for a specific platform.
class PlatformOptimizedVariant {
  final PlatformDestination platform;
  final String title;
  final String caption;
  final List<String> hashtags;
  final String formatNotes;
  final int characterCount;

  const PlatformOptimizedVariant({
    required this.platform,
    this.title = '',
    required this.caption,
    this.hashtags = const [],
    this.formatNotes = '',
    required this.characterCount,
  });

  Map<String, dynamic> toMap() {
    return {
      'platform': platform.name,
      'title': title,
      'caption': caption,
      'hashtags': hashtags,
      'formatNotes': formatNotes,
      'characterCount': characterCount,
    };
  }

  factory PlatformOptimizedVariant.fromMap(
    Map<String, dynamic> map,
    PlatformDestination platform,
  ) {
    return PlatformOptimizedVariant(
      platform: platform,
      title: map['title'] as String? ?? '',
      caption: map['caption'] as String? ?? '',
      hashtags: (map['hashtags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      formatNotes: map['formatNotes'] as String? ?? '',
      characterCount: (map['characterCount'] as num?)?.toInt() ?? (map['caption']?.toString().length ?? 0),
    );
  }
}

/// The complete optimization payload returned by AIContentOptimizerService.
class AIContentOptimizationResult {
  final String originalCaption;
  final String? category;
  final int viralHookScore;
  final List<String> hookSuggestions;
  final List<String> recommendedHashtags;
  final Map<PlatformDestination, PlatformOptimizedVariant> platformOptimizations;
  final String recommendedPostTime;
  final String hookAnalysisRationale;
  final DateTime analyzedAt;
  final bool isAiGenerated;

  const AIContentOptimizationResult({
    required this.originalCaption,
    this.category,
    required this.viralHookScore,
    required this.hookSuggestions,
    required this.recommendedHashtags,
    required this.platformOptimizations,
    required this.recommendedPostTime,
    required this.hookAnalysisRationale,
    required this.analyzedAt,
    this.isAiGenerated = false,
  });

  /// Helper to get caption for a specific platform or fallback to original.
  String getCaptionFor(PlatformDestination platform) {
    return platformOptimizations[platform]?.caption ?? originalCaption;
  }

  /// Helper to get title for a specific platform (e.g. YouTube Shorts).
  String getTitleFor(PlatformDestination platform) {
    return platformOptimizations[platform]?.title ?? '';
  }

  /// Helper to get hashtags for a specific platform.
  List<String> getHashtagsFor(PlatformDestination platform) {
    return platformOptimizations[platform]?.hashtags ?? recommendedHashtags;
  }

  Map<String, dynamic> toMap() {
    return {
      'originalCaption': originalCaption,
      'category': category,
      'viralHookScore': viralHookScore,
      'hookSuggestions': hookSuggestions,
      'recommendedHashtags': recommendedHashtags,
      'platformOptimizations': platformOptimizations.map(
        (key, value) => MapEntry(key.name, value.toMap()),
      ),
      'recommendedPostTime': recommendedPostTime,
      'hookAnalysisRationale': hookAnalysisRationale,
      'analyzedAt': analyzedAt.toIso8601String(),
      'isAiGenerated': isAiGenerated,
    };
  }
}

final aiContentOptimizerServiceProvider = Provider<AIContentOptimizerService>((ref) {
  final agentService = ref.watch(openRouterAgentServiceProvider);
  return AIContentOptimizerService(agentService);
});

/// Live AI Multi-Channel Content Optimizer Engine for Oneova.
/// Interacts with OpenRouter / Gemini AI models, with a deterministic NLP heuristic fallback engine.
class AIContentOptimizerService {
  final OpenRouterAgentService _agentService;

  AIContentOptimizerService([OpenRouterAgentService? agentService])
      : _agentService = agentService ?? OpenRouterAgentService();

  /// Analyzes video title/caption, calculates Viral Hook Score (0-100),
  /// recommends viral hashtags, optimizes posting times, and automatically adapts
  /// captions, tags, and formatting across multiple selected platforms.
  Future<AIContentOptimizationResult> optimizeContent({
    required String caption,
    required List<PlatformDestination> platforms,
    String? category,
  }) async {
    final cleanCaption = caption.trim();
    final effectivePlatforms = platforms.isEmpty
        ? [PlatformDestination.internal, PlatformDestination.tiktok, PlatformDestination.instagram]
        : platforms;

    // 1. Try real OpenRouter / Gemini AI query
    final aiResult = await _tryAiOptimization(
      caption: cleanCaption,
      platforms: effectivePlatforms,
      category: category,
    );

    if (aiResult != null) {
      return aiResult;
    }

    // 2. High-Grade Heuristic NLP Engine Fallback
    return _generateHeuristicOptimization(
      caption: cleanCaption,
      platforms: effectivePlatforms,
      category: category,
    );
  }

  /// Attempts to run analysis through OpenRouter AI agent.
  Future<AIContentOptimizationResult?> _tryAiOptimization({
    required String caption,
    required List<PlatformDestination> platforms,
    String? category,
  }) async {
    const systemPrompt = '''
You are Oneova's elite AI Multi-Channel Content Optimizer & Viral Growth Engine.
You specialize in maximizing audience retention, click-through-rates, and algorithmic velocity across short-form platforms (Oneova, TikTok, Instagram Reels, YouTube Shorts, X/Twitter, Facebook Reels).
You must analyze the input caption and output ONLY a valid, raw JSON object (no markdown quotes, no triple backticks) matching this structure:
{
  "viralHookScore": 88,
  "hookAnalysisRationale": "Strong curiosity loop with emotional urgency.",
  "hookSuggestions": [
    "Catchy Hook 1",
    "Catchy Hook 2",
    "Catchy Hook 3"
  ],
  "recommendedHashtags": ["#fyp", "#viral", "#oneova", "#creator", "#trending", "#studio"],
  "recommendedPostTime": "Today at 6:45 PM (Peak Audience Velocity)",
  "platformCaptions": {
    "internal": {
      "title": "Oneova Master Feature",
      "caption": "Oneova high-velocity caption",
      "hashtags": ["#oneova", "#creatorstudio"],
      "formatNotes": "Uncompressed stream with collaborator tags"
    },
    "tiktok": {
      "title": "",
      "caption": "Punchy TikTok caption with slang & high energy",
      "hashtags": ["#fyp", "#viral", "#trending"],
      "formatNotes": "High pacing, immediate hook"
    },
    "instagram": {
      "title": "",
      "caption": "Aesthetic spaced caption with CTA",
      "hashtags": ["#reels", "#explore", "#creative"],
      "formatNotes": "Clean aesthetic line breaks"
    },
    "youtube": {
      "title": "ALL-CAPS HIGH-CTR TITLE 🔥",
      "caption": "Search-optimized YouTube Shorts description with keywords",
      "hashtags": ["#shorts", "#youtube"],
      "formatNotes": "SEO keyword density"
    },
    "twitter": {
      "title": "",
      "caption": "Under 280 chars punchy debate/question",
      "hashtags": ["#oneova", "#tech"],
      "formatNotes": "Concise conversational debate hook"
    },
    "facebook": {
      "title": "",
      "caption": "Relatable storytelling narrative hook",
      "hashtags": ["#storytelling", "#reels"],
      "formatNotes": "Community discussion prompt"
    }
  }
}
''';

    final platformNames = platforms.map((p) => p.name).join(', ');
    final userPrompt = '''
Caption: "$caption"
Category: "${category ?? 'General Video / Creative Production'}"
Target Platforms: [$platformNames]

Generate the full viral optimization payload with tailored formatting for each target platform. Output pure JSON.
''';

    try {
      final responseText = await _agentService.queryAgent(systemPrompt, userPrompt);
      if (responseText == null || responseText.trim().isEmpty) {
        return null;
      }

      // Clean markdown fences if any returned by LLM
      String cleanedJson = responseText.trim();
      if (cleanedJson.startsWith('```json')) {
        cleanedJson = cleanedJson.substring(7);
      } else if (cleanedJson.startsWith('```')) {
        cleanedJson = cleanedJson.substring(3);
      }
      if (cleanedJson.endsWith('```')) {
        cleanedJson = cleanedJson.substring(0, cleanedJson.length - 3);
      }
      cleanedJson = cleanedJson.trim();

      final parsed = jsonDecode(cleanedJson) as Map<String, dynamic>;
      final rawScore = (parsed['viralHookScore'] as num?)?.toInt() ?? 75;
      final score = rawScore.clamp(0, 100);
      final rationale = parsed['hookAnalysisRationale'] as String? ?? 'AI-optimized for cross-platform audience velocity.';
      final hooks = (parsed['hookSuggestions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .take(3)
              .toList() ??
          [];
      final hashtags = (parsed['recommendedHashtags'] as List<dynamic>?)
              ?.map((e) => e.toString().startsWith('#') ? e.toString() : '#$e')
              .toList() ??
          [];
      final postTime = parsed['recommendedPostTime'] as String? ?? _calculateAudienceVelocityTime();

      final rawPlatforms = parsed['platformCaptions'] as Map<String, dynamic>? ?? {};
      final Map<PlatformDestination, PlatformOptimizedVariant> platformMap = {};

      for (final p in platforms) {
        final key = p.name;
        if (rawPlatforms.containsKey(key) && rawPlatforms[key] is Map<String, dynamic>) {
          platformMap[p] = PlatformOptimizedVariant.fromMap(
            rawPlatforms[key] as Map<String, dynamic>,
            p,
          );
        } else {
          // Fallback variant for this platform
          platformMap[p] = _createPlatformVariant(p, caption, hashtags);
        }
      }

      return AIContentOptimizationResult(
        originalCaption: caption,
        category: category,
        viralHookScore: score,
        hookSuggestions: hooks.length >= 3 ? hooks : _generateDefaultHooks(caption, category),
        recommendedHashtags: hashtags.length >= 6 ? hashtags : _generateTrendingHashtags(category),
        platformOptimizations: platformMap,
        recommendedPostTime: postTime,
        hookAnalysisRationale: rationale,
        analyzedAt: DateTime.now(),
        isAiGenerated: true,
      );
    } catch (_) {
      // Fallback gracefully on parsing error or bad connection
      return null;
    }
  }

  /// High-grade NLP Heuristic Engine for instant zero-dependency optimization.
  AIContentOptimizationResult _generateHeuristicOptimization({
    required String caption,
    required List<PlatformDestination> platforms,
    String? category,
  }) {
    final viralHookScore = _computeViralHookScore(caption);
    final hookSuggestions = _generateDefaultHooks(caption, category);
    final recommendedHashtags = _generateTrendingHashtags(category);
    final recommendedPostTime = _calculateAudienceVelocityTime();

    final Map<PlatformDestination, PlatformOptimizedVariant> platformMap = {};
    for (final platform in platforms) {
      platformMap[platform] = _createPlatformVariant(
        platform,
        caption,
        recommendedHashtags,
      );
    }

    return AIContentOptimizationResult(
      originalCaption: caption,
      category: category,
      viralHookScore: viralHookScore,
      hookSuggestions: hookSuggestions,
      recommendedHashtags: recommendedHashtags,
      platformOptimizations: platformMap,
      recommendedPostTime: recommendedPostTime,
      hookAnalysisRationale: _generateRationale(viralHookScore),
      analyzedAt: DateTime.now(),
      isAiGenerated: false,
    );
  }

  /// Calculates a deterministic Viral Hook Score (0-100) based on linguistic markers.
  int _computeViralHookScore(String text) {
    if (text.isEmpty) return 30;

    int score = 45; // baseline
    final lower = text.toLowerCase();

    // Power words and curiosity triggers
    final powerTriggers = [
      'secret', 'revealed', 'insane', 'never', 'how to', 'why you', 'stop',
      'truth', 'hack', 'mistake', 'transform', 'watch', 'wait for it', '10x',
      'unbelievable', 'mind blown', 'don\'t', 'blueprint', 'masterclass',
      'rule', 'hidden', 'proof', 'viral', 'ultimate'
    ];
    int triggerMatches = 0;
    for (final trigger in powerTriggers) {
      if (lower.contains(trigger)) {
        triggerMatches++;
      }
    }
    score += (triggerMatches * 9);

    // Number presence (odd numbers & statistics boost retention)
    if (RegExp(r'\b\d+\b').hasMatch(text)) {
      score += 10;
    }

    // Question marks (curiosity gap)
    if (text.contains('?')) {
      score += 8;
    }

    // Exclamation / urgency
    if (text.contains('!')) {
      score += 5;
    }

    // Length check: Short, punchy hooks (40 - 140 chars) achieve the highest immediate CTR
    if (text.length >= 30 && text.length <= 160) {
      score += 12;
    } else if (text.length > 300) {
      score -= 8; // Overly verbose hooks lose viewer focus
    }

    return score.clamp(15, 98);
  }

  /// Generates 3 catchy, high-CTR hook variations.
  List<String> _generateDefaultHooks(String caption, String? category) {
    final topic = caption.isNotEmpty
        ? (caption.length > 40 ? '${caption.substring(0, 40).trim()}...' : caption)
        : (category ?? 'content creation');

    return [
      'Stop scrolling: The #1 thing nobody is talking about regarding $topic 🤫',
      'If you make this 1 mistake with $topic, you are wasting your time 🚨',
      'The exact secret we used to 10x our reach with $topic in 24 hours 📈',
    ];
  }

  /// Generates 6-10 trending hashtags including velocity tags (#fyp, #viral, #oneova).
  List<String> _generateTrendingHashtags(String? category) {
    final baseVelocityTags = ['#fyp', '#viral', '#oneova', '#trending', '#creator'];
    final categoryTags = _getCategoryHashtags(category);

    final merged = <String>{...baseVelocityTags, ...categoryTags}.toList();
    if (merged.length < 8) {
      merged.addAll(['#explorepage', '#reelsviral', '#shortsfeed']);
    }
    return merged.take(10).toList();
  }

  List<String> _getCategoryHashtags(String? category) {
    final cat = (category ?? '').toLowerCase();
    if (cat.contains('music') || cat.contains('audio')) {
      return ['#audioproduction', '#sounddesign', '#musicproducer', '#studiosessions'];
    } else if (cat.contains('film') || cat.contains('video') || cat.contains('cinema')) {
      return ['#filmmaking', '#cinematography', '#colorgrading', '#indiefilm'];
    } else if (cat.contains('tech') || cat.contains('ai')) {
      return ['#technews', '#aiart', '#creatoreconomy', '#futuretech'];
    } else if (cat.contains('lifestyle') || cat.contains('vlog')) {
      return ['#lifestylevlog', '#dailyroutine', '#creatorlife', '#aesthetic'];
    }
    return ['#contentcreator', '#cinematic', '#videoproduction', '#creatorspotlight'];
  }

  /// Constructs tailored caption per destination adhering strictly to channel conventions.
  PlatformOptimizedVariant _createPlatformVariant(
    PlatformDestination platform,
    String baseCaption,
    List<String> tags,
  ) {
    final tagSlice = tags.take(5).join(' ');

    switch (platform) {
      case PlatformDestination.tiktok:
        final tiktokCaption = baseCaption.isNotEmpty
            ? '$baseCaption 👀 Wait till the end! Drop your thoughts below 🔥\n$tagSlice #fyp #foryou'
            : 'Wait till the end! 🤯 Drop your thoughts below 👇 #fyp #viral #oneova';
        return PlatformOptimizedVariant(
          platform: platform,
          title: '',
          caption: tiktokCaption,
          hashtags: tags.take(6).toList(),
          formatNotes: 'Punchy, high-energy slang, trend velocity tags.',
          characterCount: tiktokCaption.length,
        );

      case PlatformDestination.instagram:
        final instaCaption = StringBuffer();
        instaCaption.writeln(baseCaption.isNotEmpty ? baseCaption : 'Elevate your creative vision ✨');
        instaCaption.writeln('.');
        instaCaption.writeln('Save this post for later reference! Which detail stood out most to you? Drop a comment below 👇');
        instaCaption.writeln('.');
        instaCaption.write(tags.take(8).join(' '));
        final str = instaCaption.toString();
        return PlatformOptimizedVariant(
          platform: platform,
          title: '',
          caption: str,
          hashtags: tags.take(8).toList(),
          formatNotes: 'Visual aesthetic, readable paragraph spacing, niche tags.',
          characterCount: str.length,
        );

      case PlatformDestination.youtube:
        final cleanTitle = baseCaption.isNotEmpty
            ? '${baseCaption.toUpperCase()} 🔥 (Watch Till End)'
            : 'THE SECRET BEHIND VIRAL CONTENT CREATION 🔥';
        final ytDescription = '''$cleanTitle

In this Short, we break down high-fidelity production and viral pacing strategies.
🔔 Subscribe to Oneova for daily pro creator workflows!

Tags:
${tags.take(6).join(' ')} #shorts #youtubeshorts''';
        return PlatformOptimizedVariant(
          platform: platform,
          title: cleanTitle.length > 70 ? '${cleanTitle.substring(0, 67)}...' : cleanTitle,
          caption: ytDescription,
          hashtags: [...tags.take(5), '#shorts'],
          formatNotes: 'High-CTR uppercase video title + search-optimized description.',
          characterCount: ytDescription.length,
        );

      case PlatformDestination.twitter:
        // Strictly under 280 characters with controversy / debate hook
        String tweetBody = baseCaption.isNotEmpty
            ? 'Hot take: $baseCaption\n\nAgree or disagree? 👇'
            : 'Hot take: 99% of creators overlook this one variable.\n\nAgree or disagree? 👇';
        final tweetTags = ' #oneova #creators';
        if (tweetBody.length + tweetTags.length > 275) {
          tweetBody = '${tweetBody.substring(0, 275 - tweetTags.length - 3)}...';
        }
        final finalTweet = '$tweetBody$tweetTags';
        return PlatformOptimizedVariant(
          platform: platform,
          title: '',
          caption: finalTweet,
          hashtags: ['#oneova', '#creators'],
          formatNotes: 'Concise under 280 characters, strong debate hook.',
          characterCount: finalTweet.length,
        );

      case PlatformDestination.facebook:
        final fbCaption = '''We’ve all experienced this moment firsthand.
$baseCaption

Share this with someone who needs this perspective today! What would you have done differently? Let’s discuss in the comments below.

${tags.take(5).join(' ')}''';
        return PlatformOptimizedVariant(
          platform: platform,
          title: '',
          caption: fbCaption,
          hashtags: tags.take(5).toList(),
          formatNotes: 'Relatable storytelling hook and share prompts.',
          characterCount: fbCaption.length,
        );

      case PlatformDestination.internal:
      default:
        final oneovaCaption = '''$baseCaption ✨

Streaming in master lossless fidelity on Oneova.
Co-authors & collaborators tagged below.

${tags.join(' ')}''';
        return PlatformOptimizedVariant(
          platform: platform,
          title: 'Oneova Master Broadcast',
          caption: oneovaCaption,
          hashtags: tags,
          formatNotes: 'High-velocity community engagement hook & collaborator co-credit.',
          characterCount: oneovaCaption.length,
        );
    }
  }

  /// Calculates dynamic recommended posting time based on audience velocity peaks.
  String _calculateAudienceVelocityTime() {
    final now = DateTime.now();
    final hour = now.hour;

    if (hour < 11) {
      return 'Today at 12:15 PM (Lunch Rush Velocity)';
    } else if (hour < 16) {
      return 'Today at 6:45 PM (Peak Audience Velocity)';
    } else if (hour < 21) {
      return 'Today at 8:30 PM (Prime Evening Velocity)';
    } else {
      return 'Tomorrow at 8:15 AM (Morning Commute Velocity)';
    }
  }

  String _generateRationale(int score) {
    if (score >= 85) {
      return 'Viral Hook Tier: Exceptional curiosity gap and high retention velocity detected.';
    } else if (score >= 65) {
      return 'Strong Engagement Tier: Good curiosity markers with room for increased emotional intensity.';
    } else {
      return 'Moderate Hook Tier: Recommend opening with one of the 3 AI high-CTR hook suggestions.';
    }
  }
}
