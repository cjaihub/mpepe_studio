import 'omni_context_resolver.dart';

// ---------------------------------------------------------------------------
// Intent Engine
// ---------------------------------------------------------------------------
// Translates a raw user prompt into a structured OmniIntent.
// The model NEVER directly executes a query or action — it only declares intent.
// The intent is validated against the current context before planning begins.
// ---------------------------------------------------------------------------

enum IntentCategory {
  /// Read/search operations
  searchInbox,
  searchMessages,
  getConversation,
  getNotifications,
  getConnectorStatus,

  /// Summarize / analyze
  summarizeConversation,
  summarizeMessages,

  /// Drafting
  draftReply,
  translateMessage,

  /// Mutations (require higher mode + confirmation for HIGH/CRITICAL)
  markRead,
  setPriority,
  assignConversation,
  sendMessage,

  /// Connector management
  refreshConnector,
  listConnectedAccounts,

  /// Media
  searchMedia,

  /// Project/Media
  readProject,
  modifyProject,
  applyEffect,
  exportProject,
  deleteProject,
  
  /// Color Domain
  setColorExposure,
  setColorContrast,
  setColorHighlights,
  applyColorLut,
  applyColorPreset,
  createSecondaryGrade,

  /// Out of scope
  unknown,
}

/// A structured, validated intent derived from the user's natural language input.
class OmniIntent {
  final IntentCategory category;
  final Map<String, dynamic> parameters;
  final double confidence; // 0.0–1.0
  final String rawInput;

  const OmniIntent({
    required this.category,
    required this.parameters,
    required this.confidence,
    required this.rawInput,
  });

  bool get isReadOperation => const {
        IntentCategory.searchInbox,
        IntentCategory.searchMessages,
        IntentCategory.getConversation,
        IntentCategory.getNotifications,
        IntentCategory.getConnectorStatus,
        IntentCategory.summarizeConversation,
        IntentCategory.summarizeMessages,
        IntentCategory.listConnectedAccounts,
        IntentCategory.searchMedia,
        IntentCategory.readProject,
      }.contains(category);

  bool get requiresDraftMode => const {
        IntentCategory.draftReply,
        IntentCategory.translateMessage,
      }.contains(category);

  bool get requiresApprovalMode => const {
        IntentCategory.sendMessage,
        IntentCategory.assignConversation,
        IntentCategory.refreshConnector,
        IntentCategory.modifyProject,
        IntentCategory.applyEffect,
        IntentCategory.exportProject,
        IntentCategory.deleteProject,
        IntentCategory.setColorExposure,
        IntentCategory.setColorContrast,
        IntentCategory.setColorHighlights,
        IntentCategory.applyColorLut,
        IntentCategory.applyColorPreset,
        IntentCategory.createSecondaryGrade,
      }.contains(category);

  Map<String, dynamic> toJson() => {
        'category': category.name,
        'parameters': parameters,
        'confidence': confidence,
        'rawInput': rawInput,
      };
}

/// Classifies user input into a structured OmniIntent.
///
/// The engine uses a two-stage approach:
///   1. Local keyword/pattern classification (zero latency, no API call).
///   2. If confidence < threshold → delegates to model layer for disambiguation.
///
/// The model NEVER returns raw actions — only a declared intent + parameters.
class OmniIntentEngine {
  /// Classify user input against the current context.
  /// Returns the best-matching intent, or [IntentCategory.unknown] if unclear.
  OmniIntent classify(String rawInput, OmniContext context) {
    final lower = rawInput.toLowerCase().trim();

    // --- Specific queries ---
    if (_matches(lower, ['notification', 'alerts', 'show notification',
        'unread notification', 'my notifications'])) {
      return OmniIntent(
        category: IntentCategory.getNotifications,
        parameters: {'unreadOnly': lower.contains('unread')},
        confidence: 0.87,
        rawInput: rawInput,
      );
    }

    if (_matches(lower, ['disconnected', 'connection issue', 'connector', 'health',
        'platform status', 'account status', 'reauthorize', 'reconnect'])) {
      return OmniIntent(
        category: IntentCategory.getConnectorStatus,
        parameters: {
          if (context.connectorId != null) 'connectorId': context.connectorId,
        },
        confidence: 0.85,
        rawInput: rawInput,
      );
    }

    // --- Search / Read intents ---
    if (_matches(lower, ['unread', 'need replies', 'needs reply', 'show conversations',
        'all conversations', 'list conversations', 'inbox'])) {
      return OmniIntent(
        category: IntentCategory.searchInbox,
        parameters: _extractInboxParams(lower),
        confidence: 0.90,
        rawInput: rawInput,
      );
    }

    if (_matches(lower, ['find message', 'search message', 'message from', 'messages about',
        'look for message', 'find email', 'search email'])) {
      return OmniIntent(
        category: IntentCategory.searchMessages,
        parameters: _extractSearchParams(lower),
        confidence: 0.88,
        rawInput: rawInput,
      );
    }

    if (_matches(lower, ['summarize', 'summary of', 'what did', 'catch me up', 'tldr'])) {
      return OmniIntent(
        category: IntentCategory.summarizeConversation,
        parameters: {
          if (context.conversationId != null) 'conversationId': context.conversationId,
        },
        confidence: context.conversationId != null ? 0.92 : 0.75,
        rawInput: rawInput,
      );
    }

    if (_matches(lower, ['draft', 'write a reply', 'compose', 'suggest a response',
        'help me reply', 'write back'])) {
      return OmniIntent(
        category: IntentCategory.draftReply,
        parameters: {
          if (context.conversationId != null) 'conversationId': context.conversationId,
          'tone': _extractTone(lower),
        },
        confidence: 0.87,
        rawInput: rawInput,
      );
    }

    if (_matches(lower, ['translate', 'in kinyarwanda', 'in swahili', 'in french',
        'in english', 'in spanish', 'into'])) {
      return OmniIntent(
        category: IntentCategory.translateMessage,
        parameters: {
          'targetLanguage': _extractLanguage(lower),
          if (context.messageId != null) 'messageId': context.messageId,
          if (context.conversationId != null) 'conversationId': context.conversationId,
        },
        confidence: 0.85,
        rawInput: rawInput,
      );
    }

    if (_matches(lower, ['send it', 'send the reply', 'send this', 'send that',
        'go ahead and send', 'post it', 'dispatch'])) {
      return OmniIntent(
        category: IntentCategory.sendMessage,
        parameters: {
          if (context.conversationId != null) 'conversationId': context.conversationId,
        },
        confidence: 0.82,
        rawInput: rawInput,
      );
    }

    if (_matches(lower, ['mark read', 'mark as read', 'mark all read'])) {
      return OmniIntent(
        category: IntentCategory.markRead,
        parameters: {
          if (context.conversationId != null) 'conversationId': context.conversationId,
        },
        confidence: 0.88,
        rawInput: rawInput,
      );
    }

    if (_matches(lower, ['which accounts', 'connected accounts', 'my accounts',
        'which platforms', 'connected platforms'])) {
      return OmniIntent(
        category: IntentCategory.listConnectedAccounts,
        parameters: {},
        confidence: 0.90,
        rawInput: rawInput,
      );
    }



    if (_matches(lower, ['photo', 'image', 'video', 'media', 'file', 'attachment',
        'shared in this', 'find the photo'])) {
      return OmniIntent(
        category: IntentCategory.searchMedia,
        parameters: {
          if (context.conversationId != null) 'conversationId': context.conversationId,
        },
        confidence: 0.80,
        rawInput: rawInput,
      );
    }

    if (_matches(lower, ['priority', 'mark high', 'mark urgent', 'set priority'])) {
      return OmniIntent(
        category: IntentCategory.setPriority,
        parameters: {
          if (context.conversationId != null) 'conversationId': context.conversationId,
          'priority': _extractPriority(lower),
        },
        confidence: 0.82,
        rawInput: rawInput,
      );
    }

    // --- Project/Media intents ---
    if (_matches(lower, ['open project', 'read project', 'get project', 'show project'])) {
      return OmniIntent(
        category: IntentCategory.readProject,
        parameters: {
          if (context.projectId != null) 'projectId': context.projectId,
        },
        confidence: 0.90,
        rawInput: rawInput,
      );
    }

    // --- Color Domain intents ---
    if (_matches(lower, ['exposure', 'brighter', 'darker'])) {
      return OmniIntent(
        category: IntentCategory.setColorExposure,
        parameters: {
          if (context.projectId != null) 'projectId': context.projectId,
          if (context.sequenceId != null) 'sequenceId': context.sequenceId,
          if (context.clipId != null) 'clipId': context.clipId,
          'value': _extractNumber(lower) ?? 0.5,
        },
        confidence: 0.90,
        rawInput: rawInput,
      );
    }

    if (_matches(lower, ['contrast'])) {
      return OmniIntent(
        category: IntentCategory.setColorContrast,
        parameters: {
          if (context.projectId != null) 'projectId': context.projectId,
          if (context.sequenceId != null) 'sequenceId': context.sequenceId,
          if (context.clipId != null) 'clipId': context.clipId,
          'value': _extractNumber(lower) ?? 1.2,
        },
        confidence: 0.90,
        rawInput: rawInput,
      );
    }

    if (_matches(lower, ['highlights'])) {
      return OmniIntent(
        category: IntentCategory.setColorHighlights,
        parameters: {
          if (context.projectId != null) 'projectId': context.projectId,
          if (context.sequenceId != null) 'sequenceId': context.sequenceId,
          if (context.clipId != null) 'clipId': context.clipId,
          'value': _extractNumber(lower) ?? -0.2,
        },
        confidence: 0.90,
        rawInput: rawInput,
      );
    }

    if (_matches(lower, ['lut', 'apply lut'])) {
      return OmniIntent(
        category: IntentCategory.applyColorLut,
        parameters: {
          if (context.projectId != null) 'projectId': context.projectId,
          if (context.sequenceId != null) 'sequenceId': context.sequenceId,
          if (context.clipId != null) 'clipId': context.clipId,
          'lutId': _extractStringArg(lower, ['lut', 'apply']) ?? 'cinematic_lut',
          'intensity': _extractNumber(lower) ?? 1.0,
        },
        confidence: 0.90,
        rawInput: rawInput,
      );
    }

    if (_matches(lower, ['preset', 'apply preset', 'style'])) {
      return OmniIntent(
        category: IntentCategory.applyColorPreset,
        parameters: {
          if (context.projectId != null) 'projectId': context.projectId,
          if (context.sequenceId != null) 'sequenceId': context.sequenceId,
          if (context.clipId != null) 'clipId': context.clipId,
          'presetId': _extractStringArg(lower, ['preset', 'apply', 'style']) ?? 'moody_dark',
        },
        confidence: 0.90,
        rawInput: rawInput,
      );
    }

    if (_matches(lower, ['secondary grade', 'grade only', 'mask', 'face', 'sky', 'subject'])) {
      return OmniIntent(
        category: IntentCategory.createSecondaryGrade,
        parameters: {
          if (context.projectId != null) 'projectId': context.projectId,
          if (context.sequenceId != null) 'sequenceId': context.sequenceId,
          if (context.clipId != null) 'clipId': context.clipId,
          'targetMaskId': _extractSemanticTarget(lower),
          'name': 'Grade for ${_extractSemanticTarget(lower)}',
        },
        confidence: 0.85,
        rawInput: rawInput,
      );
    }

    if (_matches(lower, ['apply', 'add effect', 'change color', 'warm', 'cinematic', 'make it look', 'grade'])) {
      return OmniIntent(
        category: IntentCategory.applyEffect,
        parameters: {
          if (context.projectId != null) 'projectId': context.projectId,
          'effectType': _extractEffect(lower),
        },
        confidence: 0.85,
        rawInput: rawInput,
      );
    }

    if (_matches(lower, ['split', 'trim', 'move clip', 'create project', 'add transition'])) {
      return OmniIntent(
        category: IntentCategory.modifyProject,
        parameters: {
          if (context.projectId != null) 'projectId': context.projectId,
          'action': _extractProjectAction(lower),
        },
        confidence: 0.85,
        rawInput: rawInput,
      );
    }

    if (_matches(lower, ['export', 'render', 'save video', 'publish'])) {
      return OmniIntent(
        category: IntentCategory.exportProject,
        parameters: {
          if (context.projectId != null) 'projectId': context.projectId,
        },
        confidence: 0.92,
        rawInput: rawInput,
      );
    }

    // Low confidence — unknown
    return OmniIntent(
      category: IntentCategory.unknown,
      parameters: {},
      confidence: 0.0,
      rawInput: rawInput,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  bool _matches(String input, List<String> keywords) =>
      keywords.any((k) => input.contains(k));

  Map<String, dynamic> _extractInboxParams(String input) {
    final params = <String, dynamic>{};
    if (input.contains('unread')) params['unread'] = true;
    if (input.contains('need repl')) params['needsReply'] = true;
    if (input.contains('whatsapp')) params['platform'] = 'whatsapp';
    if (input.contains('instagram')) params['platform'] = 'instagram';
    if (input.contains('youtube')) params['platform'] = 'youtube';
    if (input.contains('facebook') || input.contains('fb')) params['platform'] = 'facebook';
    if (input.contains('tiktok')) params['platform'] = 'tiktok';
    return params;
  }

  Map<String, dynamic> _extractSearchParams(String input) {
    final params = <String, dynamic>{};
    // Extract "from <name>"
    final fromMatch = RegExp(r'from ([a-zA-Z]+)').firstMatch(input);
    if (fromMatch != null) params['senderName'] = fromMatch.group(1);
    // Extract "about <topic>"
    final aboutMatch = RegExp(r'about (.+?)(?:\s+last|\s+this|$)').firstMatch(input);
    if (aboutMatch != null) params['query'] = aboutMatch.group(1);
    // Extract time keywords
    if (input.contains('last week')) params['timeRange'] = 'last_week';
    if (input.contains('today')) params['timeRange'] = 'today';
    if (input.contains('yesterday')) params['timeRange'] = 'yesterday';
    return params;
  }

  String _extractTone(String input) {
    if (input.contains('polite') || input.contains('formal')) return 'formal';
    if (input.contains('friendly') || input.contains('casual')) return 'friendly';
    if (input.contains('short') || input.contains('brief')) return 'concise';
    return 'professional';
  }

  String _extractLanguage(String input) {
    if (input.contains('kinyarwanda')) return 'rw';
    if (input.contains('swahili')) return 'sw';
    if (input.contains('french')) return 'fr';
    if (input.contains('spanish')) return 'es';
    if (input.contains('english')) return 'en';
    if (input.contains('arabic')) return 'ar';
    return 'en';
  }

  String _extractPriority(String input) {
    if (input.contains('urgent') || input.contains('critical')) return 'urgent';
    if (input.contains('high')) return 'high';
    if (input.contains('low')) return 'low';
    return 'normal';
  }

  String _extractEffect(String input) {
    if (input.contains('cinematic')) return 'cinematic';
    if (input.contains('warm')) return 'warm';
    if (input.contains('reduce highlights') || input.contains('highlight')) return 'reduce_highlights';
    if (input.contains('lut')) return 'lut';
    if (input.contains('preset')) return 'preset';
    return 'unknown_effect';
  }

  String _extractProjectAction(String input) {
    if (input.contains('split')) return 'split_clip';
    if (input.contains('trim')) return 'trim_clip';
    if (input.contains('create')) return 'create_project';
    if (input.contains('transition')) return 'add_transition';
    return 'unknown_action';
  }

  double? _extractNumber(String input) {
    final match = RegExp(r'[-+]?\d*\.?\d+').firstMatch(input);
    if (match != null) {
      return double.tryParse(match.group(0)!);
    }
    return null;
  }

  String? _extractStringArg(String input, List<String> ignoreWords) {
    final parts = input.split(' ');
    for (final part in parts) {
      if (!ignoreWords.contains(part) && part.length > 2) {
        return part;
      }
    }
    return null;
  }

  String _extractSemanticTarget(String input) {
    if (input.contains('face') || input.contains('person')) return 'semantic_face';
    if (input.contains('sky')) return 'semantic_sky';
    if (input.contains('background')) return 'semantic_background';
    return 'semantic_subject';
  }
}
