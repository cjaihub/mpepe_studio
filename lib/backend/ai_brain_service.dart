import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'tiktok_automation_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'remote_connect_service.dart';
import '../youtube_manager/models/youtube_channel_profile.dart';
import '../auth/auth_repository.dart';
import '../youtube_manager/services/youtube_account_store.dart';
import 'project_repository.dart';

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
  String get openRouterKey => dotenv.env['OPENROUTER_API_KEY'] ?? '';

  AIBrainService(this.remoteConnect, this.tiktokAutomation, this.projectRepository);

  // DaVinci and Premiere specific tools definition
  final List<Map<String, dynamic>> studioTools = [
    {
      "type": "function",
      "function": {
        "name": "apply_lut",
        "description": "Applies a color grading LUT to the current DaVinci Resolve timeline.",
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
        "description": "Adds a marker to the current timeline in DaVinci Resolve or Premiere Pro.",
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
        "description": "Matches the color of the current clip to a reference clip in DaVinci Resolve.",
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
        "description": "Applies a film emulation look (e.g., Kodak 2383, Fuji 3510) in DaVinci Resolve.",
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
              "description": "Preferred tools for the project (e.g., Premiere, Logic Pro)."
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
    List<Map<String, dynamic>>? customTools,
    String? userContextPrompt,
  }) async {
    // Default to the most capable reasoning model for general tasks
    String model = 'anthropic/claude-sonnet-5';
    if (taskType == 'audio' || taskType == 'voice') {
      // Use GPT-4o for audio/voice related tasks (best multimodal capabilities)
      model = 'openai/gpt-4o';
    }
    
    final allTools = [...?customTools, ...studioTools];
    return _callOpenRouter(messages, model: model, tools: allTools, userContextPrompt: userContextPrompt);
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
    
    if (openRouterKey.isEmpty) throw Exception('OPENROUTER_API_KEY is missing.');
    
    final uri = Uri.parse('https://openrouter.ai/api/v1/chat/completions');
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
          'Authorization': 'Bearer $openRouterKey',
          'HTTP-Referer': 'https://mpepe.studio',
          'X-Title': 'MPEPE Studio',
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

    if (openRouterKey.isEmpty) throw Exception('OPENROUTER_API_KEY is missing.');

    final uri = Uri.parse('https://openrouter.ai/api/v1/chat/completions');
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
          'Authorization': 'Bearer $openRouterKey',
          'HTTP-Referer': 'https://mpepe.studio',
          'X-Title': 'MPEPE Studio',
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

    if (openRouterKey.isEmpty) throw Exception('OPENROUTER_API_KEY is missing.');

    final userData = '''
Channel Name: $channelName
Keywords: $channelKeywords
Recent 28-day Analytics: ${jsonEncode(analytics)}
Recent Videos: ${jsonEncode(recentVideos)}
''';

    final uri = Uri.parse('https://openrouter.ai/api/v1/chat/completions');
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
          'Authorization': 'Bearer $openRouterKey',
          'HTTP-Referer': 'https://mpepe.studio',
          'X-Title': 'MPEPE Studio',
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

    if (openRouterKey.isEmpty) throw Exception('OPENROUTER_API_KEY is missing.');

    final userData = '''
Video ID: $videoId
Title: $title
Description: $description
Stats (Views, Likes, Comments): ${jsonEncode(stats)}
Top Audience Countries: ${jsonEncode(geoData)}
''';

    final uri = Uri.parse('https://openrouter.ai/api/v1/chat/completions');
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
          'Authorization': 'Bearer $openRouterKey',
          'HTTP-Referer': 'https://mpepe.studio',
          'X-Title': 'MPEPE Studio',
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
    if (openRouterKey.isEmpty) return AiTextResponse("Error: OPENROUTER_API_KEY is missing.");
    
    final uri = Uri.parse('https://openrouter.ai/api/v1/chat/completions');
    
    String baseSystemPrompt = "You are Mpepe AI, a highly intelligent, empathetic, and human-like studio assistant. "
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
          'Authorization': 'Bearer $openRouterKey',
          'HTTP-Referer': 'https://mpepe.studio',
          'X-Title': 'MPEPE Studio',
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
}

final aiBrainProvider = Provider<AIBrainService>((ref) {
  final remoteConnect = ref.watch(remoteConnectProvider.notifier);
  final tiktokAutomation = ref.watch(tiktokAutomationProvider);
  final projectRepo = ref.watch(projectRepositoryProvider);
  return AIBrainService(remoteConnect, tiktokAutomation, projectRepo);
});

final aiUserContextProvider = Provider<String>((ref) {
  final authState = ref.watch(authStateProvider);
  final ytAccountsAsync = ref.watch(ytAccountsStreamProvider);
  
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
  
  return contextStr;
});
