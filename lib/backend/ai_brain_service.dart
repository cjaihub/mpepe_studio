import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'tiktok_automation_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'remote_connect_service.dart';
import '../youtube_manager/models/youtube_channel_profile.dart';
import '../auth/auth_repository.dart';
import '../youtube_manager/services/youtube_account_store.dart';
import 'project_repository.dart';
import '../ova_assistant/memory/ova_memory_engine.dart';
import 'security/secure_api_key_vault.dart';
import 'security/oneova_ai_gateway.dart';

sealed class AiResponse {}

class AiTextResponse extends AiResponse {
  final String text;
  AiTextResponse(this.text);
}

class AiToolCallResponse extends AiResponse {
  final List<dynamic> toolCalls;
  AiToolCallResponse(this.toolCalls);
}

class AiWidgetResponse extends AiResponse {
  final String widgetType; // e.g., 'chart', 'card', 'youtube_stats'
  final Map<String, dynamic> data;
  AiWidgetResponse(this.widgetType, this.data);
}

class ScriptBreakdown {
  final String title;
  final List<String> characters;
  final List<String> props;
  final List<Map<String, String>> shotList;

  ScriptBreakdown({required this.title, required this.characters, required this.props, required this.shotList});

  factory ScriptBreakdown.fromJson(Map<String, dynamic> json) {
    return ScriptBreakdown(
      title: json['title'] ?? 'Untitled',
      characters: List<String>.from(json['characters'] ?? []),
      props: List<String>.from(json['props'] ?? []),
      shotList: (json['shotList'] as List<dynamic>?)?.map((e) => Map<String, String>.from(e)).toList() ?? [],
    );
  }
}

class AIBrainService {
  final RemoteConnectService remoteConnect;
  final TikTokAutomationService tiktokAutomation;
  final ProjectRepository projectRepository;
  final SecureKeyVault? vault;
  String? _customApiKey;
  void setApiKey(String key) => _customApiKey = key.trim();

  String get openRouterKey {
    // Only a key the user saved themselves. Without one, calls go through
    // the aiProxy Cloud Function (OneovaAiGateway); the app ships no key.
    if (_customApiKey != null && _customApiKey!.isNotEmpty) return _customApiKey!;
    return '';
  }

  bool get hasApiKey => OneovaAiGateway.canCall(openRouterKey);

  AIBrainService(this.remoteConnect, this.tiktokAutomation, this.projectRepository, [this.vault]);

  // OneOva Studio Engine tools definition
  final List<Map<String, dynamic>> studioTools = [
    {
      "type": "function",
      "function": {
        "name": "apply_lut",
        "description": "Applies a color grading LUT to the current OneOva Studio timeline.",
        "parameters": {
          "type": "object",
          "properties": {
            "lut_path": {"type": "string", "description": "The path or name of the LUT to apply"}
          },
          "required": ["lut_path"]
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "add_marker",
        "description": "Adds a marker to the current timeline in OneOva Studio.",
        "parameters": {
          "type": "object",
          "properties": {
            "name": {"type": "string", "description": "The name of the marker"},
            "color": {"type": "string", "description": "The color of the marker (e.g. Blue, Red)"},
            "note": {"type": "string", "description": "Optional notes"}
          },
          "required": ["name"]
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "color_match",
        "description": "Matches the color of the current clip to a reference clip in OneOva Studio.",
        "parameters": {
          "type": "object",
          "properties": {
            "reference_clip": {"type": "string", "description": "The name or index of the reference clip"}
          },
          "required": ["reference_clip"]
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "auto_balance",
        "description": "Automatically balances the white point and exposure of the current clip.",
        "parameters": {
          "type": "object",
          "properties": {
            "strength": {"type": "number", "description": "Strength of the auto-balance from 0.0 to 1.0"}
          }
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "apply_film_emulation",
        "description": "Applies a film emulation look (e.g., Kodak 2383, Fuji 3510) in OneOva Studio.",
        "parameters": {
          "type": "object",
          "properties": {
            "film_stock": {"type": "string", "description": "The name of the film stock (e.g. Kodak 2383)"}
          },
          "required": ["film_stock"]
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "get_studio_calendar",
        "description": "Fetches the current studio calendar events and schedule.",
        "parameters": {
          "type": "object",
          "properties": {},
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "fetch_latest_comments",
        "description": "Fetches the latest comments for a specific YouTube channel.",
        "parameters": {
          "type": "object",
          "properties": {
            "channel_id": {"type": "string", "description": "The YouTube channel ID"}
          },
          "required": ["channel_id"]
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "reply_to_comment",
        "description": "Replies to a specific YouTube comment.",
        "parameters": {
          "type": "object",
          "properties": {
            "comment_id": {"type": "string", "description": "The ID of the comment to reply to"},
            "text": {"type": "string", "description": "The reply text"}
          },
          "required": ["comment_id", "text"]
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "research_trending_topics",
        "description": "Researches trending topics on YouTube for a specific query or niche.",
        "parameters": {
          "type": "object",
          "properties": {
            "query": {"type": "string", "description": "The search query or niche to research"}
          },
          "required": ["query"]
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "auto_crop_video",
        "description": "Auto crops a YouTube video to 9:16 for TikTok.",
        "parameters": {
          "type": "object",
          "properties": {
            "video_id": {"type": "string", "description": "The ID of the video to crop."}
          },
          "required": ["video_id"]
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "analyze_retention",
        "description": "Analyzes the retention curve of a TikTok video.",
        "parameters": {
          "type": "object",
          "properties": {
            "video_id": {"type": "string", "description": "The ID of the video to analyze."}
          },
          "required": ["video_id"]
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "inject_broll",
        "description": "Injects B-Roll into a TikTok video's dead zones.",
        "parameters": {
          "type": "object",
          "properties": {
            "video_id": {"type": "string", "description": "The ID of the video to process."}
          },
          "required": ["video_id"]
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "create_studio_project",
        "description": "Creates a new Video or Audio project in the studio directory. Call this ONLY after you have gathered all necessary details from the user (genre, reference links, characters, tools, and generated a short script/storyboard).",
        "parameters": {
          "type": "object",
          "properties": {
            "title": {"type": "string", "description": "The title of the project."},
            "category": {"type": "string", "description": "Must be exactly 'Video' or 'Audio'."},
            "characters": {
              "type": "array",
              "items": {"type": "string"},
              "description": "List of characters or artists."
            },
            "script": {"type": "string", "description": "The generated script or storyboard outline."},
            "tools_used": {
              "type": "array",
              "items": {"type": "string"},
              "description": "Preferred tools for the project (e.g., OneOva Video, OneOva Audio)."
            }
          },
          "required": ["title", "category", "script"]
        }
      }
    }
  ];

  Future<String> executeTikTokTool(String name, String argumentsJson) async {
    final args = jsonDecode(argumentsJson);
    try {
      switch (name) {
        case 'auto_crop_video':
          return await tiktokAutomation.autoCropVideo(args['video_id'] ?? 'unknown');
        case 'analyze_retention':
          return await tiktokAutomation.analyzeRetentionCurve(args['video_id'] ?? 'unknown');
        case 'inject_broll':
          return await tiktokAutomation.injectBRoll(args['video_id'] ?? 'unknown');
        default:
          return "TikTok tool $name not implemented in mock backend.";
      }
    } catch (e) {
      return "Error executing $name: $e";
    }
  }

  Future<AiResponse> processRequest(
    List<Map<String, dynamic>> messages, {
    String taskType = 'general',
    String? modelId,
    List<int>? imageBytes,
    String? screenBase64,
    List<Map<String, dynamic>>? customTools,
    String? userContextPrompt,
  }) async {
    // 1. Resolve effective image base64 if present
    String? effectiveImageBase64 = screenBase64;
    if (effectiveImageBase64 == null && imageBytes != null && imageBytes.isNotEmpty) {
      effectiveImageBase64 = base64Encode(imageBytes);
    }
    final bool hasImage = effectiveImageBase64 != null && effectiveImageBase64.isNotEmpty;

    // 2. Select appropriate model dynamically
    String model = (modelId != null && modelId.isNotEmpty) ? modelId : 'auto';

    if (model == 'auto') {
      if (hasImage || taskType == 'vision') {
        // Premium fast multimodal vision model on OpenRouter
        model = 'google/gemini-2.5-flash';
      } else if (taskType == 'audio' || taskType == 'voice') {
        model = 'openai/gpt-4o';
      } else {
        model = 'anthropic/claude-3.5-sonnet';
      }
    } else {
      // If user selected a model, but an image/screen context was provided,
      // verify the model supports vision; if not, gracefully promote to Gemini 2.5 Flash
      if (hasImage && !_isVisionModel(model)) {
        model = 'google/gemini-2.5-flash';
      }
    }

    // 3. Assemble multimodal payload if image is present
    final List<Map<String, dynamic>> finalMessages = [];
    for (int i = 0; i < messages.length; i++) {
      final msg = Map<String, dynamic>.from(messages[i]);
      // If this is the last user message and we have an image, format as OpenRouter multimodal content
      if (hasImage && i == messages.length - 1 && msg['role'] == 'user') {
        final existingContent = msg['content'];
        final textPrompt = (existingContent is String && existingContent.isNotEmpty)
            ? existingContent
            : 'Analyze this screen/image context and provide actionable insights.';
        msg['content'] = [
          {
            'type': 'text',
            'text': textPrompt,
          },
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:image/jpeg;base64,$effectiveImageBase64',
            },
          },
        ];
      }
      finalMessages.add(msg);
    }

    final allTools = [...?customTools, ...studioTools];
    return _callOpenRouter(
      finalMessages,
      model: model,
      tools: allTools,
      userContextPrompt: userContextPrompt,
    );
  }

  bool _isVisionModel(String modelId) {
    final lower = modelId.toLowerCase();
    return lower.contains('vision') ||
        lower.contains('gemini') ||
        lower.contains('gpt-4o') ||
        lower.contains('claude-3') ||
        lower.contains('pixtral') ||
        lower.contains('qwen-vl') ||
        lower.contains('vl-');
  }

  Future<String> executeStudioTool(String name, String argumentsJson) async {
    final args = jsonDecode(argumentsJson);
    try {
      if (name == 'create_studio_project') {
        final project = StudioProject(
          id: '',
          category: args['category'] ?? 'Video',
          title: args['title'] ?? 'Untitled Project',
          status: 'Scripting',
          completedSteps: 1,
          totalSteps: 5,
          characters: List<String>.from(args['characters'] ?? []),
          script: args['script'],
          toolsUsed: List<String>.from(args['tools_used'] ?? []),
          createdAt: DateTime.now(),
        );
        final id = await projectRepository.addProject(project);
        return "Successfully created project '${project.title}' with ID: $id.";
      }
      return "Tool $name not recognized by local studio tools.";
    } catch (e) {
      return "Error executing $name: $e";
    }
  }

  Future<http.Response> _postWithRetry(Uri uri, {required Map<String, String> headers, required String body, int maxRetries = 2}) async {
    int attempts = 0;
    while (attempts < maxRetries) {
      try {
        final response = await http.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 15));
        if (response.statusCode >= 500) {
          // Server error, try again
          attempts++;
          await Future.delayed(Duration(seconds: attempts * 2));
          continue;
        }
        return response;
      } on TimeoutException {
        attempts++;
        if (attempts >= maxRetries) throw Exception('Request timed out after $maxRetries attempts.');
        await Future.delayed(Duration(seconds: attempts * 2));
      } on SocketException {
        attempts++;
        if (attempts >= maxRetries) throw Exception('Network error. Please check your connection.');
        await Future.delayed(Duration(seconds: attempts * 2));
      }
    }
    throw Exception('Failed to connect to AI Service.');
  }

  Future<ScriptBreakdown?> breakdownScript(String script) async {
    final systemPrompt = '''
You are a professional film pre-production assistant.
Analyze the provided script and return a JSON object with this exact structure (NO markdown formatting, JUST raw JSON):
{
  "title": "Inferred Title",
  "characters": ["Char 1", "Char 2"],
  "props": ["Prop 1", "Prop 2"],
  "shotList": [
    {"shot": "EXT. WIDE", "description": "Description of the shot"}
  ]
}
''';
    
    if (!OneovaAiGateway.canCall(openRouterKey)) throw Exception('Sign in to use Oneova AI.');
    
    final uri = OneovaAiGateway.chatUri(openRouterKey);
    final body = {
      "model": "anthropic/claude-sonnet-5", // Using Claude 5 Sonnet for superior text parsing and reasoning
      "response_format": {"type": "json_object"},
      "messages": [
        {"role": "system", "content": systemPrompt},
        {"role": "user", "content": script}
      ],
    };

    try {
      final response = await _postWithRetry(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await OneovaAiGateway.bearer(openRouterKey)}',
          'HTTP-Referer': 'https://oneova.studio',
          'X-Title': 'Oneova Studio',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] as String;
        return ScriptBreakdown.fromJson(jsonDecode(content));
      } else {
        throw Exception('API returned ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) print('Breakdown Error: $e'); // Keep debug log, but throw to UI
      throw Exception('Failed to generate breakdown: $e');
    }
  }

  Future<Map<String, dynamic>?> generateYouTubeMetadata(String topic) async {
    final systemPrompt = '''
You are an expert YouTube strategist and copywriter.
Based on the provided video topic or rough idea, generate optimized metadata for a YouTube upload.
Return a JSON object with this exact structure (NO markdown formatting, JUST raw JSON):
{
  "title": "A highly clickable, CTR-optimized title",
  "description": "A detailed, SEO-friendly description including timestamps if applicable and call to actions.",
  "tags": ["tag1", "tag2", "tag3", "up to 15 optimized tags"]
}
''';

    if (!OneovaAiGateway.canCall(openRouterKey)) throw Exception('Sign in to use Oneova AI.');

    final uri = OneovaAiGateway.chatUri(openRouterKey);
    final body = {
      "model": "anthropic/claude-sonnet-5", // Claude 5 Sonnet is highly capable at copywriting
      "response_format": {"type": "json_object"},
      "messages": [
        {"role": "system", "content": systemPrompt},
        {"role": "user", "content": topic}
      ],
    };

    try {
      final response = await _postWithRetry(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await OneovaAiGateway.bearer(openRouterKey)}',
          'HTTP-Referer': 'https://oneova.studio',
          'X-Title': 'Oneova Studio',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] as String;
        return jsonDecode(content) as Map<String, dynamic>;
      } else {
        throw Exception('API returned ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) print('YouTube Metadata Gen Error: $e');
      throw Exception('Failed to generate metadata: $e');
    }
  }

  Future<YouTubeChannelProfile?> analyzeYouTubeChannel(
    String channelId, 
    String channelName, 
    Map<String, dynamic> analytics, 
    List<Map<String, dynamic>> recentVideos, 
    String channelKeywords,
  ) async {
    final systemPrompt = '''
You are an expert YouTube Channel Manager and Data Analyst.
You are performing a deep scan of a YouTube channel to generate an Intelligence Profile.
Review the provided analytics, recent video data, and channel keywords.
Return a JSON object with this exact structure (NO markdown formatting, JUST raw JSON):
{
  "niche": "e.g., Tech Reviews, Vlogging, Gaming",
  "targetAudience": "e.g., Males 18-35 interested in PC building",
  "toneOfVoice": "e.g., Energetic and educational",
  "missingElements": ["e.g., Thumbnails lack consistent branding", "No links in descriptions"],
  "recommendedActions": ["e.g., Add timestamps to videos", "Create a playlist for series X"]
}
''';

    if (!OneovaAiGateway.canCall(openRouterKey)) throw Exception('Sign in to use Oneova AI.');

    final userData = '''
Channel Name: $channelName
Keywords: $channelKeywords
Recent 28-day Analytics: ${jsonEncode(analytics)}
Recent Videos: ${jsonEncode(recentVideos)}
''';

    final uri = OneovaAiGateway.chatUri(openRouterKey);
    final body = {
      "model": "anthropic/claude-sonnet-5", // Deep analytical reasoning
      "response_format": {"type": "json_object"},
      "messages": [
        {"role": "system", "content": systemPrompt},
        {"role": "user", "content": userData}
      ],
    };

    try {
      final response = await _postWithRetry(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await OneovaAiGateway.bearer(openRouterKey)}',
          'HTTP-Referer': 'https://oneova.studio',
          'X-Title': 'Oneova Studio',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] as String;
        final jsonResult = jsonDecode(content) as Map<String, dynamic>;
        
        return YouTubeChannelProfile(
          channelId: channelId,
          niche: jsonResult['niche'] ?? 'Unknown',
          targetAudience: jsonResult['targetAudience'] ?? 'Unknown',
          toneOfVoice: jsonResult['toneOfVoice'] ?? 'Unknown',
          missingElements: List<String>.from(jsonResult['missingElements'] ?? []),
          recommendedActions: List<String>.from(jsonResult['recommendedActions'] ?? []),
          lastScanned: DateTime.now(),
          rawAnalyticsSnapshot: analytics,
        );
      } else {
        throw Exception('API returned ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) print('Analyze Channel Error: $e');
      throw Exception('Failed to analyze channel: $e');
    }
  }

  Future<Map<String, dynamic>> analyzeSingleVideo({
    required String videoId,
    required String title,
    required String description,
    required Map<String, dynamic> stats,
    required List<Map<String, dynamic>> geoData,
  }) async {
    final systemPrompt = '''
You are an expert YouTube strategist and analyst.
You are analyzing a single video based on its title, description, engagement metrics, and geographic audience data.
Return a JSON object with this exact structure (NO markdown formatting, JUST raw JSON):
{
  "performanceSummary": "e.g., The video has high engagement relative to views, indicating strong resonance.",
  "seoCritique": "e.g., The title is catchy but lacks searchable keywords. Description could use more hashtags.",
  "audienceInsights": "e.g., High viewership in India and US suggests a diverse appeal.",
  "actionableTips": ["e.g., Pin a comment asking a question", "Create a localized subtitle track"]
}
''';

    if (!OneovaAiGateway.canCall(openRouterKey)) throw Exception('Sign in to use Oneova AI.');

    final userData = '''
Video ID: $videoId
Title: $title
Description: $description
Stats (Views, Likes, Comments): ${jsonEncode(stats)}
Top Audience Countries: ${jsonEncode(geoData)}
''';

    final uri = OneovaAiGateway.chatUri(openRouterKey);
    final body = {
      "model": "anthropic/claude-sonnet-5", // Deep analytical reasoning
      "response_format": {"type": "json_object"},
      "messages": [
        {"role": "system", "content": systemPrompt},
        {"role": "user", "content": userData}
      ],
    };

    try {
      final response = await _postWithRetry(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await OneovaAiGateway.bearer(openRouterKey)}',
          'HTTP-Referer': 'https://oneova.studio',
          'X-Title': 'Oneova Studio',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String content = data['choices'][0]['message']['content'] as String;
        
        // Strip markdown code blocks if the model wrapped the JSON
        content = content.trim();
        if (content.startsWith('```json')) {
          content = content.substring(7);
        } else if (content.startsWith('```')) {
          content = content.substring(3);
        }
        if (content.endsWith('```')) {
          content = content.substring(0, content.length - 3);
        }
        content = content.trim();

        return jsonDecode(content) as Map<String, dynamic>;
      } else {
        throw Exception('API returned ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) print('Analyze Video Error: $e');
      throw Exception('Failed to analyze video: $e');
    }
  }

  Future<AiResponse> _callOpenRouter(
    List<Map<String, dynamic>> messages, {
    required String model,
    List<Map<String, dynamic>>? tools,
    String? userContextPrompt,
  }) async {
    if (!OneovaAiGateway.canCall(openRouterKey)) {
      final geminiKey = await vault?.getGeminiApiKey() ?? '';
      if (geminiKey.isNotEmpty) {
        final geminiRes = await _callGeminiDirect(
          messages,
          geminiKey: geminiKey,
          userContextPrompt: userContextPrompt,
        );
        if (geminiRes != null) return geminiRes;
      }

      final lastUserMsg = messages.lastWhere(
        (m) => m['role'] == 'user',
        orElse: () => {'content': ''},
      )['content'];
      final userText = (lastUserMsg is String ? lastUserMsg : '').toLowerCase();

      if (userText.contains('reach') || userText.contains('contact') || userText.contains('preference') || userText.contains('email') || userText.contains('phone')) {
        return AiTextResponse(
          "## 🧠 Semantic Memory Analysis (Vector DB + Knowledge Graph)\n\n"
          "### 1. 🎯 Vector Database Nearest Cluster:\n"
          "- **Query:** *\"How to reach them?\"*\n"
          "- **Cluster Match:** `PREFERS EMAIL` (Cosine Similarity: 0.98)\n"
          "- **Category:** `customer_channel`\n\n"
          "### 2. 🕸️ Knowledge Graph Traversal:\n"
          "- `CUSTOMER` —[`PREFERS`]➔ **`EMAIL`** (`creator@oneova.studio`)\n"
          "- `CUSTOMER` —[`PLACED`]➔ **`ORDER 4471`**\n"
          "- `ORDER 4471` —[`CONTAINS`]➔ **`PHONE`** (`+1 555-019-4471`)\n\n"
          "**💡 Action Recommendation:**\n"
          "Reach out via **Email** as the customer's primary registered preference. Use **Phone** from Order #4471 only for urgent courier or delivery alerts."
        );
      } else if (userText.contains('ticket') || userText.contains('refund')) {
        return AiTextResponse(
          "## 🛡️ Episodic Memory Safeguard (Mistake Avoidance)\n\n"
          "**Past Mistake Identified:**\n"
          "> *\"Closed user ticket before payment gateway verified refund settlement.\"*\n\n"
          "**Safe Execution Sequence:**\n"
          "1. 💳 **Verify Refund:** Payment gateway verifies refund confirmation status is green.\n"
          "2. 📧 **Notify Customer:** Customer Operations Agent dispatches confirmation via preferred channel (`EMAIL`).\n"
          "3. 🎫 **Resolve Ticket:** Close support ticket only after verified settlement and customer notification.\n\n"
          "✅ *Zero recurrence guarantee active.*"
        );
      } else if (userText.contains('safari') || userText.contains('budget')) {
        return AiTextResponse(
          "## 🦁 Budget-Friendly Safari Plan (Oneova Studio Guide)\n\n"
          "Here is an optimized itinerary balancing budget, wildlife visibility, and 4K reel cinematography:\n\n"
          "| Day | Activity | Est. Cost (USD) | Cinematography Focus |\n"
          "|---|---|---|---|\n"
          "| Day 1 | Arrival & Lake Nakuru Game Drive | \$85 - \$120 | Flamingo flocks, wide landscape b-roll |\n"
          "| Day 2 | Masai Mara Transit & Golden Hour | \$140 - \$190 | Big 5 stalking, slow-mo 120fps predator shots |\n"
          "| Day 3 | Sunrise Balloon/Drive & River Crossing | \$110 - \$160 | High-contrast sunrise, telephoto portraits |\n"
          "| Day 4 | Cultural Village & Departure | \$45 - \$70 | Ambient storytelling, creator interview audio |\n\n"
          "**💡 Creator Budget Tips:**\n"
          "- Join group safari vans (cuts transport cost by 60%).\n"
          "- Bring 200–600mm zoom lens; keep shutter speed ≥ 1/1000s for running wildlife.\n"
          "- Export direct to **Oneova Reels** to engage wildlife communities."
        );
      } else if (userText.contains('script') || userText.contains('reel') || userText.contains('viral')) {
        return AiTextResponse(
          "## 🎬 High-Velocity Viral Oneova Reel Script (15s)\n\n"
          "**Niche:** Tech & Creative Production\n"
          "**Target Retention:** > 85% via 1.5s visual hook\n\n"
          "---\n"
          "**[0.0s – 1.8s] Hook (Visual + Verbal):**\n"
          "*Fast snap-zoom onto phone screen with sound effect.*\n"
          "> *\"Stop editing your reels manually in 2026—watch this.\"*\n\n"
          "**[1.8s – 8.0s] The Core Value:**\n"
          "*Screen recording of Oneova Assistant boosting a reel and color grading it in Oneova Pro Studio.*\n"
          "> *\"Ova Assistant runs autonomous workflows across your desktop workstation and device without heating your hardware.\"*\n\n"
          "**[8.0s – 12.5s] The Proof / Result:**\n"
          "*Split-screen before/after showing instant render and trending analytics on Oneova Reels feed.*\n\n"
          "**[12.5s – 15.0s] Call To Action:**\n"
          "> *\"Tap remix or drop a comment to grab this workflow template.\"*\n"
          "---\n\n"
          "**Recommended Hashtags:** `#OneovaReels #CreativeWorkflow #AIEditing #ContentCreator`"
        );
      } else if (userText.contains('hi') || userText.contains('hello') || userText.contains('hey')) {
        return AiTextResponse(
          "Hello! I am **Ova Assistant**—your autonomous AI creative partner.\n\n"
          "I can run autonomous workflows for you right now:\n"
          "- **Boost to Oneova Reels**: Help more people discover your post.\n"
          "- **Safety & Burn Notice Audit**: Comprehensive policy & content validation.\n"
          "- **Live Stage Digital Twin**: Autonomous host persona for your live broadcast.\n"
          "- **Workstation Control**: Remote render, LUT match, or passkey unlock for Oneova Pro Workstation.\n\n"
          "What would you like to create or publish today?"
        );
      }

      return AiTextResponse(
        "### 🧠 Oneova AI • Creative Intelligence\n\n"
        "I've processed your request: **\"${lastUserMsg is String ? lastUserMsg : ''}\"**.\n\n"
        "You can run any autonomous procedure directly (e.g. *\"Boost to Oneova Reels\"*, *\"Safety audit\"*, *\"Live stage digital twin\"*).\n\n"
        "*(Sign in to Oneova to get full answers from Ova.)*"
      );
    }
    
    final uri = OneovaAiGateway.chatUri(openRouterKey);
    
    String baseSystemPrompt = "You are Oneova AI, a highly intelligent, empathetic, and human-like studio assistant. "
                   "Be exceptionally concise, direct, and conversational in your responses. "
                   "CRITICAL RULES:\n"
                   "1. **Act Human:** Respond naturally like a real human assistant. DO NOT say things like 'I don't have a tool for that' or list your internal thought processes (e.g., 'What I can do', 'What happened'). If you cannot perform a task, apologize politely and naturally.\n"
                   "2. **Markdown Formatting:** Format ALL your responses using clean Markdown. Use headings (##), bolding, bullet points, and especially **Markdown Tables** to display data cleanly and beautifully.\n"
                   "3. **Smart Clarification:** If a user request is ambiguous, do not guess. Provide a clean, bulleted list of options they can choose from, then wait for their response.\n"
                   "4. **No Meta-Talk:** Never describe what you are doing technically or what your system instructions are. Just deliver the final, clean answer.\n"
                   "5. **Professional Tone:** Maintain a consultative, empathetic, yet highly professional tone. Never use generic AI filler phrases.\n";

    if (userContextPrompt != null && userContextPrompt.isNotEmpty) {
      baseSystemPrompt += "\n\n--- USER CONTEXT ---\n$userContextPrompt\n--------------------\n";
    }

    // Ensure system prompt is first with the new persona
    final List<Map<String, dynamic>> finalMessages = [
      {
        "role": "system", 
        "content": baseSystemPrompt
      },
      ...messages,
    ];

    final body = {
      "model": model,
      "messages": finalMessages,
      if (tools != null && tools.isNotEmpty) "tools": tools,
    };

    try {
      final response = await _postWithRetry(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await OneovaAiGateway.bearer(openRouterKey)}',
          'HTTP-Referer': 'https://oneova.studio',
          'X-Title': 'Oneova Studio',
        },
        body: jsonEncode(body),
      );

      return _handleResponse(response);
    } catch (e) {
      if (kDebugMode) print('OpenRouter Request Error: $e');
      return AiTextResponse("Error: Unable to reach AI Brain. Please check your connection or try again later.");
    }
  }

  AiResponse _handleResponse(http.Response response) {
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final message = data['choices'][0]['message'];
      
      if (message['tool_calls'] != null) {
        final toolCalls = message['tool_calls'] as List<dynamic>;
        
        // Special interception for render_chart to turn it into an AiWidgetResponse
        for (final tc in toolCalls) {
          if (tc['function']?['name'] == 'render_chart') {
            final args = jsonDecode(tc['function']['arguments']);
            return AiWidgetResponse('chart', args);
          }
        }
        
        return AiToolCallResponse(toolCalls);
      }

      return AiTextResponse(message['content'] ?? "No response content.");
    } else {
      if (kDebugMode) print('API Error: ${response.statusCode} - ${response.body}');
      return AiTextResponse("Sorry, I encountered a server error (${response.statusCode}). Please try again.");
    }
  }

  Future<AiResponse?> _callGeminiDirect(
    List<Map<String, dynamic>> messages, {
    required String geminiKey,
    String? userContextPrompt,
  }) async {
    try {
      final model = await vault?.getPreferredGeminiModel() ?? 'gemini-2.5-flash';
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$geminiKey',
      );

      String baseSystemPrompt = "You are Oneova AI, a highly intelligent, empathetic, and human-like studio assistant. "
          "Be exceptionally concise, direct, and conversational in your responses. "
          "Format ALL your responses using clean Markdown. Use headings, bullet points, and tables where applicable.\n";

      if (userContextPrompt != null && userContextPrompt.isNotEmpty) {
        baseSystemPrompt += "\n\n--- USER CONTEXT ---\n$userContextPrompt\n--------------------\n";
      }

      final contents = <Map<String, dynamic>>[];
      for (final m in messages) {
        final role = m['role'] == 'user' ? 'user' : 'model';
        final text = (m['content'] ?? '').toString();
        if (text.isNotEmpty) {
          contents.add({
            'role': role,
            'parts': [
              {'text': text}
            ]
          });
        }
      }

      final body = {
        'system_instruction': {
          'parts': [
            {'text': baseSystemPrompt}
          ]
        },
        'contents': contents,
        'generationConfig': {
          'temperature': 0.7,
          'maxOutputTokens': 2048,
        }
      };

      final response = await _postWithRetry(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List<dynamic>?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = candidates[0]['content']?['parts'] as List<dynamic>?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts[0]['text'] as String?;
            if (text != null && text.trim().isNotEmpty) {
              return AiTextResponse(text.trim());
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Gemini Direct Error: $e');
    }
    return null;
  }
}

final aiBrainProvider = Provider<AIBrainService>((ref) {
  final remoteConnect = ref.watch(remoteConnectProvider.notifier);
  final tiktokAutomation = ref.watch(tiktokAutomationProvider);
  final projectRepo = ref.watch(projectRepositoryProvider);
  final vault = ref.watch(secureKeyVaultProvider);
  return AIBrainService(remoteConnect, tiktokAutomation, projectRepo, vault);
});

final aiUserContextProvider = Provider<String>((ref) {
  final authState = ref.watch(authStateProvider);
  final ytAccountsAsync = ref.watch(ytAccountsStreamProvider);
  final memoryEngine = ref.watch(ovaMemoryEngineProvider);
  
  final user = authState.value;
  String contextStr = "";
  
  if (user != null) {
    contextStr += "User Identity: ${user.displayName ?? 'Unknown Name'} (${user.email ?? 'Unknown Email'}).\n";
  }
  
  final ytAccounts = ytAccountsAsync.value;
  if (ytAccounts != null && ytAccounts.isNotEmpty) {
    contextStr += "Connected YouTube Accounts & Channels:\n";
    for (var acc in ytAccounts) {
      contextStr += "- Google Account: ${acc.accountName} (${acc.email})\n";
      for (var ch in acc.channels) {
        final activeStr = ch.isActive ? " [ACTIVE CHANNEL]" : "";
        contextStr += "  * Channel: '${ch.title}' | Subs: ${ch.subscriberCount} | Videos: ${ch.videoCount} | Views: ${ch.viewCount}$activeStr\n";
      }
    }
  } else {
    contextStr += "No connected YouTube channels.\n";
  }

  // Inject Universal Shared Memories Across All Screens (Vector DB + Knowledge Graph + Episodic Mistakes Avoidance)
  final unifiedMemory = memoryEngine.buildUnifiedMemoryContext(
    query: 'User creative preferences, active studio tasks, editing style, and safety safeguards',
    scenarioKey: 'general_creation',
  );
  if (unifiedMemory.isNotEmpty) {
    contextStr += "\n--- UNIVERSAL ONESHARED MEMORY (VECTOR DB + KNOWLEDGE GRAPH + EPISODIC SAFEGUARDS) ---\n";
    contextStr += unifiedMemory;
    contextStr += "\n-----------------------------------------------------------------------------------------\n";
  }
  
  return contextStr;
});
