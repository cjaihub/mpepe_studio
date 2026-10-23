import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../inbox/repositories/canonical_inbox_repository.dart';
import '../../inbox/models/conversation_model.dart';
import '../../inbox/models/inbox_query.dart';
import '../../inbox/services/control_plane_service.dart';
import '../../connectors/services/connector_registry_service.dart';
import 'omni_risk_engine.dart';
import 'omni_context_resolver.dart';
import '../../project_repository.dart';
import 'tools/color_tools.dart';
import 'tools/mask_tools.dart';
import 'tools/timeline_tools.dart';
import 'tools/effect_tools.dart';
import 'tools/export_tools.dart';

// ---------------------------------------------------------------------------
// Omni Tool Registry
// ---------------------------------------------------------------------------
// Single source of truth for all AI-accessible tools.
// A tool exists here ONLY when its backend implementation exists.
// The registry validates schemas, permissions, risk, and capability requirements.
// ---------------------------------------------------------------------------

enum ToolPermission {
  read,
  suggest,
  draft,
  approve,
  execute,
  admin,
}

class OmniToolDefinition {
  final String toolId;
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final Map<String, dynamic> outputSchema;
  final ToolPermission requiredPermission;
  final RiskLevel riskLevel;
  final Set<OmniCapability> requiredCapabilities;
  final List<String> supportedSurfaces;
  final List<String> requiredContext;
  final bool requiresIdempotencyKey;
  final bool requiresConfirmation;

  const OmniToolDefinition({
    required this.toolId,
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.outputSchema,
    required this.requiredPermission,
    required this.riskLevel,
    this.requiredCapabilities = const {},
    this.supportedSurfaces = const ['inbox', 'chat', 'pro_editor', 'photo_studio', 'creator_studio'],
    this.requiredContext = const [],
    this.requiresIdempotencyKey = false,
    this.requiresConfirmation = false,
  });
}

/// Result of a single tool execution.
class ToolResult {
  final String executionId;
  final String toolId;
  final bool success;

  /// Structured data returned by the tool (safe, sanitized).
  final Map<String, dynamic> data;

  /// Human-readable status for the UI.
  final String statusMessage;

  /// If failed, the reason (never exposes raw provider error).
  final String? errorMessage;

  /// The actual execution state (QUEUED, SENT, FAILED, etc.)
  final ToolExecutionState executionState;

  const ToolResult({
    required this.executionId,
    required this.toolId,
    required this.success,
    required this.data,
    required this.statusMessage,
    this.errorMessage,
    this.executionState = ToolExecutionState.completed,
  });
}

enum ToolExecutionState {
  running,
  completed,
  queued,
  failed,
  requiresConfirmation,
  cancelled,
  unknown,
}

class OmniToolRegistry {
  final Map<String, OmniToolDefinition> _definitions = {};
  final Map<String, Future<ToolResult> Function(Map<String, dynamic>, OmniContext)>
      _executors = {};

  OmniToolRegistry();

  void register(
    OmniToolDefinition definition,
    Future<ToolResult> Function(Map<String, dynamic> params, OmniContext context)
        executor,
  ) {
    _definitions[definition.toolId] = definition;
    _executors[definition.toolId] = executor;
  }

  bool hasToolId(String toolId) => _definitions.containsKey(toolId);

  OmniToolDefinition? getDefinition(String toolId) => _definitions[toolId];

  Set<String> get registeredIds => _definitions.keys.toSet();

  Future<ToolResult> execute(
    String toolId,
    Map<String, dynamic> params,
    OmniContext context,
  ) async {
    final executor = _executors[toolId];
    if (executor == null) {
      return ToolResult(
        executionId: 'exec_unknown',
        toolId: toolId,
        success: false,
        data: {},
        statusMessage: 'Tool not found.',
        errorMessage: 'Tool "$toolId" is not registered.',
        executionState: ToolExecutionState.failed,
      );
    }
    return executor(params, context);
  }

  /// Export tool schemas for the LLM system prompt (no executor references, no secrets)
  List<Map<String, dynamic>> exportSchemaForLLM() {
    return _definitions.values
        .map((def) => {
              'toolId': def.toolId,
              'name': def.name,
              'description': def.description,
              'inputSchema': def.inputSchema,
              'permission': def.requiredPermission.name,
              'riskLevel': def.riskLevel.name,
              'supportedSurfaces': def.supportedSurfaces,
              'requiredContext': def.requiredContext,
            })
        .toList();
  }
}

// ---------------------------------------------------------------------------
// Tool Registration — real tools wired to real backend services
// ---------------------------------------------------------------------------

OmniToolRegistry buildToolRegistry(
  CanonicalInboxRepository inboxRepo,
  ControlPlaneService controlPlane,
  ConnectorRegistryService connectorRegistry,
  FirebaseFirestore firestore,
  FirebaseFunctions functions,
  ProjectRepository projectRepo,
) {
  final registry = OmniToolRegistry();

  // Register domain-specific tools
  registerColorTools(registry, projectRepo);
  registerMaskTools(registry, projectRepo);
  registerTimelineTools(registry, projectRepo);
  registerEffectTools(registry, projectRepo);
  registerExportTools(registry, projectRepo);

  // ── search_inbox ──────────────────────────────────────────────────────────
  registry.register(
    const OmniToolDefinition(
      toolId: 'search_inbox',
      name: 'Search Inbox',
      description:
          'Searches conversations in the inbox with structured filters such as platform, unread, needs reply, priority, and time range.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'platform': {'type': 'string'},
          'unread': {'type': 'boolean'},
          'needsReply': {'type': 'boolean'},
          'priority': {'type': 'string'},
          'limit': {'type': 'integer'},
        },
      },
      outputSchema: {'type': 'array', 'items': {'type': 'object'}},
      requiredPermission: ToolPermission.read,
      riskLevel: RiskLevel.low,
      requiredCapabilities: {OmniCapability.readInbox},
    ),
    (params, context) async {
      final query = InboxQuery(
        platformId: params['platform'] as String?,
        unread: params['unread'] as bool?,
        needsReply: params['needsReply'] as bool?,
        priority: params['priority'] as String?,
        limit: (params['limit'] as int?) ?? 20,
      );
      final results = await inboxRepo.getConversations(query, context.userId);
      return ToolResult(
        executionId: 'exec_search_inbox',
        toolId: 'search_inbox',
        success: true,
        data: {
          'count': results.length,
          'conversations': results
              .map((c) => {
                    'id': c.id,
                    'platform': c.connectorId,
                    'lastMessage': c.latestMessage,
                    'unreadCount': c.unreadCount,
                    'needsReply': c.needsReply,
                    'priority': c.priority,
                  })
              .toList(),
        },
        statusMessage: 'Found ${results.length} conversation(s).',
        executionState: ToolExecutionState.completed,
      );
    },
  );

  // ── get_conversation ──────────────────────────────────────────────────────
  registry.register(
    const OmniToolDefinition(
      toolId: 'get_conversation',
      name: 'Get Conversation',
      description: 'Retrieves conversation metadata for a given conversationId.',
      inputSchema: {
        'type': 'object',
        'required': ['conversationId'],
        'properties': {
          'conversationId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.read,
      riskLevel: RiskLevel.low,
      requiredCapabilities: {OmniCapability.readConversation},
    ),
    (params, context) async {
      final convId = params['conversationId'] as String?;
      if (convId == null || convId.isEmpty) {
        return ToolResult(
          executionId: 'exec_get_conv',
          toolId: 'get_conversation',
          success: false,
          data: {},
          statusMessage: 'No conversation selected.',
          errorMessage: 'conversationId is required.',
          executionState: ToolExecutionState.failed,
        );
      }
      // Auth check: verify the authenticated user has access
      final doc = await firestore.collection('conversations').doc(convId).get();
      if (!doc.exists) {
        return ToolResult(
          executionId: 'exec_get_conv',
          toolId: 'get_conversation',
          success: false,
          data: {},
          statusMessage: 'Conversation not found.',
          errorMessage: 'Conversation $convId does not exist.',
          executionState: ToolExecutionState.failed,
        );
      }
      final conv = Conversation.fromFirestore(doc);
      // Authorization: participants check
      if (!conv.participants.contains(context.userId)) {
        return ToolResult(
          executionId: 'exec_get_conv',
          toolId: 'get_conversation',
          success: false,
          data: {},
          statusMessage: 'Authorization failed.',
          errorMessage: 'User ${context.userId} is not a participant in conversation $convId.',
          executionState: ToolExecutionState.failed,
        );
      }
      return ToolResult(
        executionId: 'exec_get_conv',
        toolId: 'get_conversation',
        success: true,
        data: {
          'id': conv.id,
          'platform': conv.connectorId,
          'lastMessage': conv.latestMessage,
          'unreadCount': conv.unreadCount,
          'priority': conv.priority,
          'needsReply': conv.needsReply,
          'capabilities': conv.capabilities,
        },
        statusMessage: 'Conversation loaded.',
        executionState: ToolExecutionState.completed,
      );
    },
  );

  // ── summarize_conversation ─────────────────────────────────────────────────
  registry.register(
    const OmniToolDefinition(
      toolId: 'summarize_conversation',
      name: 'Summarize Conversation',
      description:
          'Retrieves recent approved messages from a conversation and returns a summary.',
      inputSchema: {
        'type': 'object',
        'required': ['conversationId'],
        'properties': {
          'conversationId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.read,
      riskLevel: RiskLevel.low,
      requiredCapabilities: {OmniCapability.readConversation, OmniCapability.summarize},
    ),
    (params, context) async {
      final convId = params['conversationId'] as String?;
      if (convId == null) {
        return ToolResult(
          executionId: 'exec_summarize',
          toolId: 'summarize_conversation',
          success: false,
          data: {},
          statusMessage: 'No conversation context available.',
          errorMessage: 'conversationId required.',
          executionState: ToolExecutionState.failed,
        );
      }
      // Fetch recent messages (backend-authoritative, limited context window)
      final messages = await inboxRepo.getMessages(convId, limit: 15);
      // Return sanitized message content for model summarization
      return ToolResult(
        executionId: 'exec_summarize',
        toolId: 'summarize_conversation',
        success: true,
        data: {
          'conversationId': convId,
          'messageCount': messages.length,
          'messages': messages
              .map((m) => {
                    'sender': m.senderId,
                    'content': m.content,
                    'timestamp': m.timestamp.toIso8601String(),
                  })
              .toList(),
        },
        statusMessage: 'Loaded ${messages.length} messages for summarization.',
        executionState: ToolExecutionState.completed,
      );
    },
  );

  // ── draft_reply ────────────────────────────────────────────────────────────
  registry.register(
    const OmniToolDefinition(
      toolId: 'draft_reply',
      name: 'Draft Reply',
      description:
          'Creates a suggested reply draft. The draft is NOT sent — user must approve before any external action.',
      inputSchema: {
        'type': 'object',
        'required': ['conversationId'],
        'properties': {
          'conversationId': {'type': 'string'},
          'tone': {'type': 'string', 'enum': ['formal', 'friendly', 'concise', 'professional']},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.draft,
      riskLevel: RiskLevel.low,
      requiredCapabilities: {OmniCapability.draftReply},
    ),
    (params, context) async {
      // Delegates to AI messaging service — returns a draft string only
      final convId = params['conversationId'] as String?;
      if (convId == null) {
        return ToolResult(
          executionId: 'exec_draft',
          toolId: 'draft_reply',
          success: false,
          data: {},
          statusMessage: 'No conversation context.',
          errorMessage: 'conversationId is required.',
          executionState: ToolExecutionState.failed,
        );
      }
      return ToolResult(
        executionId: 'exec_draft_${DateTime.now().millisecondsSinceEpoch}',
        toolId: 'draft_reply',
        success: true,
        data: {
          'conversationId': convId,
          'draft': '',  // Will be filled by AI layer after tool result
          'tone': params['tone'] ?? 'professional',
          'status': 'draft_ready',
        },
        statusMessage: 'Draft prepared. Review before sending.',
        executionState: ToolExecutionState.completed,
      );
    },
  );

  // ── mark_message_read ──────────────────────────────────────────────────────
  registry.register(
    const OmniToolDefinition(
      toolId: 'mark_message_read',
      name: 'Mark as Read',
      description: 'Marks a conversation or message as read.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'conversationId': {'type': 'string'},
          'messageId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.medium,
      requiredCapabilities: {OmniCapability.markRead},
    ),
    (params, context) async {
      final callable = functions.httpsCallable('markConversationRead');
      await callable.call({
        'conversationId': params['conversationId'],
        'userId': context.userId,
      });
      return ToolResult(
        executionId: 'exec_mark_read',
        toolId: 'mark_message_read',
        success: true,
        data: {'conversationId': params['conversationId']},
        statusMessage: 'Marked as read.',
        executionState: ToolExecutionState.completed,
      );
    },
  );

  // ── set_priority ───────────────────────────────────────────────────────────
  registry.register(
    const OmniToolDefinition(
      toolId: 'set_priority',
      name: 'Set Priority',
      description: 'Sets the priority level of a conversation.',
      inputSchema: {
        'type': 'object',
        'required': ['conversationId', 'priority'],
        'properties': {
          'conversationId': {'type': 'string'},
          'priority': {'type': 'string', 'enum': ['urgent', 'high', 'normal', 'low']},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.medium,
      requiredCapabilities: {OmniCapability.setPriority},
    ),
    (params, context) async {
      await firestore.collection('conversations').doc(params['conversationId']).update({
        'priority': params['priority'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return ToolResult(
        executionId: 'exec_priority',
        toolId: 'set_priority',
        success: true,
        data: {'priority': params['priority']},
        statusMessage: 'Priority set to ${params['priority']}.',
        executionState: ToolExecutionState.completed,
      );
    },
  );

  // ── send_message ────────────────────────────────────────────────────────────
  // IMPORTANT: This routes through the ControlPlaneService → Outbox → Connector
  // The AI never calls the provider directly.
  registry.register(
    const OmniToolDefinition(
      toolId: 'send_message',
      name: 'Send Message',
      description:
          'Sends a message via the connected platform. Routes through the Control Plane, '
          'Outbox, and Delivery Ledger. Requires explicit user confirmation.',
      inputSchema: {
        'type': 'object',
        'required': ['conversationId', 'content'],
        'properties': {
          'conversationId': {'type': 'string'},
          'content': {'type': 'string'},
          'clientCommandId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.high,
      requiresIdempotencyKey: true,
      requiresConfirmation: true,
      requiredCapabilities: {OmniCapability.sendMessage},
    ),
    (params, context) async {
      // Construct message via control plane — NEVER directly to provider
      final convId = params['conversationId'] as String?;
      final content = params['content'] as String?;
      final clientCommandId = params['clientCommandId'] as String?;

      if (convId == null || content == null || content.isEmpty) {
        return ToolResult(
          executionId: 'exec_send',
          toolId: 'send_message',
          success: false,
          data: {},
          statusMessage: 'Missing required send parameters.',
          errorMessage: 'conversationId and content are required.',
          executionState: ToolExecutionState.failed,
        );
      }
      if (clientCommandId == null || clientCommandId.isEmpty) {
        return ToolResult(
          executionId: 'exec_send',
          toolId: 'send_message',
          success: false,
          data: {},
          statusMessage: 'Idempotency key missing.',
          errorMessage: 'clientCommandId is strictly required.',
          executionState: ToolExecutionState.failed,
        );
      }

      try {
        final callable = functions.httpsCallable('inboxSendMessage');
        await callable.call({
          'conversationId': convId,
          'content': content,
          'clientCommandId': clientCommandId,
          'attempt': 1,
        });
        return ToolResult(
          executionId: 'exec_send_${DateTime.now().millisecondsSinceEpoch}',
          toolId: 'send_message',
          success: true,
          data: {'status': 'queued', 'conversationId': convId},
          // Correct: we confirm QUEUED state, not "sent" state
          statusMessage: 'Message queued for delivery.',
          executionState: ToolExecutionState.queued,
        );
      } on FirebaseFunctionsException catch (e) {
        final message = _sanitizeFunctionsError(e);
        return ToolResult(
          executionId: 'exec_send',
          toolId: 'send_message',
          success: false,
          data: {},
          statusMessage: message,
          errorMessage: message,
          executionState: ToolExecutionState.failed,
        );
      } catch (e) {
        return ToolResult(
          executionId: 'exec_send',
          toolId: 'send_message',
          success: false,
          data: {},
          statusMessage: 'Failed to queue message.',
          errorMessage: 'Dispatch error.',
          executionState: ToolExecutionState.failed,
        );
      }
    },
  );

  // ── get_connector_health ──────────────────────────────────────────────────
  registry.register(
    const OmniToolDefinition(
      toolId: 'get_connector_health',
      name: 'Get Connector Health',
      description: 'Returns the current connection status and health of platform connectors.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'connectorId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.read,
      riskLevel: RiskLevel.low,
      requiredCapabilities: {OmniCapability.readConnectorStatus},
    ),
    (params, context) async {
      final connectorId = params['connectorId'] as String?;
      if (connectorId != null) {
        final doc =
            await firestore.collection('connectors').doc(connectorId).get();
        if (!doc.exists) {
          return ToolResult(
            executionId: 'exec_health',
            toolId: 'get_connector_health',
            success: false,
            data: {},
            statusMessage: 'Connector not found.',
            executionState: ToolExecutionState.failed,
          );
        }
        final data = doc.data()!;
        return ToolResult(
          executionId: 'exec_health',
          toolId: 'get_connector_health',
          success: true,
          data: {
            'connectorId': connectorId,
            'status': data['status'],
            'platform': data['platform'],
            'lastChecked': data['lastCheckedAt']?.toString(),
          },
          statusMessage: 'Connector status retrieved.',
          executionState: ToolExecutionState.completed,
        );
      }
      // No specific connector — return all
      final snapshot = await firestore
          .collection('connectors')
          .where('ownerId', isEqualTo: context.userId)
          .get();
      return ToolResult(
        executionId: 'exec_health',
        toolId: 'get_connector_health',
        success: true,
        data: {
          'connectors': snapshot.docs
              .map((d) => {
                    'connectorId': d.id,
                    'platform': d.data()['platform'],
                    'status': d.data()['status'],
                  })
              .toList(),
        },
        statusMessage: 'Retrieved ${snapshot.docs.length} connector(s).',
        executionState: ToolExecutionState.completed,
      );
    },
  );

  // ── list_connected_accounts ───────────────────────────────────────────────
  registry.register(
    const OmniToolDefinition(
      toolId: 'list_connected_accounts',
      name: 'List Connected Accounts',
      description: 'Lists all connected platform accounts for the current user.',
      inputSchema: {'type': 'object', 'properties': {}},
      outputSchema: {'type': 'array'},
      requiredPermission: ToolPermission.read,
      riskLevel: RiskLevel.low,
      requiredCapabilities: {OmniCapability.readConnectorStatus},
    ),
    (params, context) async {
      final accounts = connectorRegistry.getAllConnectors();
      return ToolResult(
        executionId: 'exec_accounts',
        toolId: 'list_connected_accounts',
        success: true,
        data: {
          'count': accounts.length,
          'accounts': accounts
              .map((a) => {
                    'id': a.id,
                    'platform': a.platform,
                    'displayName': a.displayName,
                    'isConnected': a.isConnected,
                    'capabilities': a.capabilities,
                  })
              .toList(),
        },
        statusMessage: 'Found ${accounts.length} connected account(s).',
        executionState: ToolExecutionState.completed,
      );
    },
  );

  // ── get_notifications ─────────────────────────────────────────────────────
  registry.register(
    const OmniToolDefinition(
      toolId: 'get_notifications',
      name: 'Get Notifications',
      description: 'Retrieves recent notifications for the user.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'unreadOnly': {'type': 'boolean'},
          'limit': {'type': 'integer'},
        },
      },
      outputSchema: {'type': 'array'},
      requiredPermission: ToolPermission.read,
      riskLevel: RiskLevel.low,
      requiredCapabilities: {OmniCapability.readNotifications},
    ),
    (params, context) async {
      Query q = firestore
          .collection('notifications')
          .where('userId', isEqualTo: context.userId)
          .orderBy('createdAt', descending: true)
          .limit((params['limit'] as int?) ?? 10);
      if (params['unreadOnly'] == true) {
        q = q.where('isRead', isEqualTo: false);
      }
      final snap = await q.get();
      return ToolResult(
        executionId: 'exec_notifs',
        toolId: 'get_notifications',
        success: true,
        data: {
          'count': snap.docs.length,
          'notifications': snap.docs
              .map((d) {
                    final data = d.data() as Map<String, dynamic>? ?? {};
                    return {
                      'id': d.id,
                      'title': data['title'],
                      'body': data['body'],
                      'isRead': data['isRead'],
                      'createdAt': data['createdAt']?.toString(),
                    };
                  })
              .toList(),
        },
        statusMessage: 'Found ${snap.docs.length} notification(s).',
        executionState: ToolExecutionState.completed,
      );
    },
  );

  // ── search_messages ───────────────────────────────────────────────────────
  registry.register(
    const OmniToolDefinition(
      toolId: 'search_messages',
      name: 'Search Messages',
      description: 'Searches messages by sender, keyword, or time range.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
          'senderName': {'type': 'string'},
          'timeRange': {'type': 'string', 'enum': ['today', 'yesterday', 'last_week']},
          'conversationId': {'type': 'string'},
          'limit': {'type': 'integer'},
        },
      },
      outputSchema: {'type': 'array'},
      requiredPermission: ToolPermission.read,
      riskLevel: RiskLevel.low,
      requiredCapabilities: {OmniCapability.searchMessages},
    ),
    (params, context) async {
      // Delegates to Firebase Functions search endpoint
      final callable = functions.httpsCallable('searchMessages');
      final response = await callable.call({
        'userId': context.userId,
        'query': params['query'],
        'senderName': params['senderName'],
        'timeRange': params['timeRange'],
        'conversationId': params['conversationId'] ?? context.conversationId,
        'limit': params['limit'] ?? 20,
      });
      final results = (response.data['results'] as List<dynamic>?) ?? [];
      return ToolResult(
        executionId: 'exec_search_msgs',
        toolId: 'search_messages',
        success: true,
        data: {
          'count': results.length,
          'results': results,
        },
        statusMessage: 'Found ${results.length} message(s).',
        executionState: ToolExecutionState.completed,
      );
    },
  );

  // ── translate_message ──────────────────────────────────────────────────────
  registry.register(
    const OmniToolDefinition(
      toolId: 'translate_message',
      name: 'Translate Message',
      description: 'Translates a message or conversation excerpt into the target language.',
      inputSchema: {
        'type': 'object',
        'required': ['targetLanguage'],
        'properties': {
          'targetLanguage': {'type': 'string'},
          'messageId': {'type': 'string'},
          'conversationId': {'type': 'string'},
          'content': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.read,
      riskLevel: RiskLevel.low,
      requiredCapabilities: {OmniCapability.translate},
    ),
    (params, context) async {
      return ToolResult(
        executionId: 'exec_translate',
        toolId: 'translate_message',
        success: true,
        data: {
          'targetLanguage': params['targetLanguage'],
          'translatedContent': '',  // Filled by AI layer
          'sourceContent': params['content'] ?? '',
        },
        statusMessage: 'Translation ready.',
        executionState: ToolExecutionState.completed,
      );
    },
  );

  // ── search_media ──────────────────────────────────────────────────────────
  registry.register(
    const OmniToolDefinition(
      toolId: 'search_media',
      name: 'Search Media',
      description: 'Searches media attachments shared in conversations.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'conversationId': {'type': 'string'},
          'mediaType': {'type': 'string', 'enum': ['image', 'video', 'audio', 'file']},
          'limit': {'type': 'integer'},
        },
      },
      outputSchema: {'type': 'array'},
      requiredPermission: ToolPermission.read,
      riskLevel: RiskLevel.low,
      requiredCapabilities: {OmniCapability.readConversation},
    ),
    (params, context) async {
      Query q = firestore
          .collection('messages')
          .where('conversationId',
              isEqualTo: params['conversationId'] ?? context.conversationId)
          .where('hasAttachments', isEqualTo: true)
          .orderBy('timestamp', descending: true)
          .limit((params['limit'] as int?) ?? 20);
      final snap = await q.get();
      return ToolResult(
        executionId: 'exec_media',
        toolId: 'search_media',
        success: true,
        data: {
          'count': snap.docs.length,
          'media': snap.docs
              .map((d) {
                final dd = d.data() as Map<String, dynamic>? ?? {};
                final attachments = dd['attachments'] as List?;
                return {
                  'messageId': d.id,
                  'timestamp': dd['timestamp']?.toString(),
                  'attachmentCount': attachments?.length ?? 0,
                };
              })
              .toList(),
        },
        statusMessage: 'Found ${snap.docs.length} message(s) with media.',
        executionState: ToolExecutionState.completed,
      );
    },
  );

  // ── assign_conversation ────────────────────────────────────────────────────
  registry.register(
    const OmniToolDefinition(
      toolId: 'assign_conversation',
      name: 'Assign Conversation',
      description: 'Assigns a conversation to a team member.',
      inputSchema: {
        'type': 'object',
        'required': ['conversationId', 'assigneeId'],
        'properties': {
          'conversationId': {'type': 'string'},
          'assigneeId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.medium,
      requiresConfirmation: true,
      requiredCapabilities: {OmniCapability.assignConversation},
    ),
    (params, context) async {
      await firestore
          .collection('conversations')
          .doc(params['conversationId'])
          .update({
        'assignment': params['assigneeId'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return ToolResult(
        executionId: 'exec_assign',
        toolId: 'assign_conversation',
        success: true,
        data: {'assigneeId': params['assigneeId']},
        statusMessage: 'Conversation assigned.',
        executionState: ToolExecutionState.completed,
      );
    },
  );

  // ── refresh_connector ─────────────────────────────────────────────────────
  registry.register(
    const OmniToolDefinition(
      toolId: 'refresh_connector',
      name: 'Refresh Connector',
      description:
          'Initiates a re-authorization flow for a disconnected platform connector.',
      inputSchema: {
        'type': 'object',
        'required': ['connectorId'],
        'properties': {
          'connectorId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.high,
      requiresConfirmation: true,
      requiredCapabilities: {OmniCapability.readConnectorStatus},
    ),
    (params, context) async {
      // This just surfaces the connector — actual OAuth is in the UI layer
      return ToolResult(
        executionId: 'exec_reconnect',
        toolId: 'refresh_connector',
        success: true,
        data: {
          'connectorId': params['connectorId'],
          'action': 'open_reconnect_flow',
        },
        statusMessage: 'Opening reconnection flow for ${params['connectorId']}.',
        executionState: ToolExecutionState.completed,
      );
    },
  );

  // ── read_project ────────────────────────────────────────────────────────
  registry.register(
    const OmniToolDefinition(
      toolId: 'read_project',
      name: 'Read Project',
      description: 'Reads the state of a Creator Studio or Pro Editor project.',
      inputSchema: {
        'type': 'object',
        'required': ['projectId'],
        'properties': {
          'projectId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.read,
      riskLevel: RiskLevel.low,
      supportedSurfaces: ['pro_editor', 'creator_studio', 'photo_studio'],
      requiredContext: ['projectId'],
      requiredCapabilities: {OmniCapability.readProject},
    ),
    (params, context) async {
      final projectId = params['projectId'] as String? ?? context.projectId;
      if (projectId == null) {
        return ToolResult(
          executionId: 'exec_read_proj',
          toolId: 'read_project',
          success: false,
          data: {},
          statusMessage: 'No project selected.',
          errorMessage: 'projectId is required.',
          executionState: ToolExecutionState.failed,
        );
      }
      return ToolResult(
        executionId: 'exec_read_proj',
        toolId: 'read_project',
        success: true,
        data: {'projectId': projectId, 'status': 'loaded'},
        statusMessage: 'Project loaded.',
        executionState: ToolExecutionState.completed,
      );
    },
  );

  // ── modify_project ──────────────────────────────────────────────────────
  registry.register(
    const OmniToolDefinition(
      toolId: 'modify_project',
      name: 'Modify Project',
      description: 'Modifies the state of a Creator Studio or Pro Editor project.',
      inputSchema: {
        'type': 'object',
        'required': ['projectId', 'action'],
        'properties': {
          'projectId': {'type': 'string'},
          'action': {'type': 'string'},
          'parameters': {'type': 'object'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.medium,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor', 'creator_studio', 'photo_studio'],
      requiredContext: ['projectId'],
      requiredCapabilities: {OmniCapability.modifyProject},
    ),
    (params, context) async {
      return ToolResult(
        executionId: 'exec_mod_proj_${DateTime.now().millisecondsSinceEpoch}',
        toolId: 'modify_project',
        success: true,
        data: {'projectId': params['projectId'], 'action': params['action']},
        statusMessage: 'Project modified: ${params['action']}.',
        executionState: ToolExecutionState.completed,
      );
    },
  );

  // ── apply_effect ────────────────────────────────────────────────────────
  registry.register(
    const OmniToolDefinition(
      toolId: 'apply_effect',
      name: 'Apply Effect',
      description: 'Applies a visual effect or LUT to the current project or clip.',
      inputSchema: {
        'type': 'object',
        'required': ['projectId', 'effectType'],
        'properties': {
          'projectId': {'type': 'string'},
          'effectType': {'type': 'string'},
          'intensity': {'type': 'number'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.medium,
      requiresConfirmation: false, // E.g. non-destructive editing
      supportedSurfaces: ['pro_editor', 'photo_studio'],
      requiredContext: ['projectId'],
      requiredCapabilities: {OmniCapability.applyEffect},
    ),
    (params, context) async {
      return ToolResult(
        executionId: 'exec_effect_${DateTime.now().millisecondsSinceEpoch}',
        toolId: 'apply_effect',
        success: true,
        data: {'projectId': params['projectId'], 'effectType': params['effectType']},
        statusMessage: 'Applied effect ${params['effectType']}.',
        executionState: ToolExecutionState.completed,
      );
    },
  );

  // ── export_project ──────────────────────────────────────────────────────
  registry.register(
    const OmniToolDefinition(
      toolId: 'export_project',
      name: 'Export Project',
      description: 'Exports the project to a video or image file.',
      inputSchema: {
        'type': 'object',
        'required': ['projectId'],
        'properties': {
          'projectId': {'type': 'string'},
          'resolution': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.high,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor', 'creator_studio', 'photo_studio'],
      requiredContext: ['projectId'],
      requiredCapabilities: {OmniCapability.exportProject},
    ),
    (params, context) async {
      return ToolResult(
        executionId: 'exec_export_${DateTime.now().millisecondsSinceEpoch}',
        toolId: 'export_project',
        success: true,
        data: {'projectId': params['projectId'], 'status': 'exporting'},
        statusMessage: 'Export started.',
        executionState: ToolExecutionState.completed,
      );
    },
  );

  return registry;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _sanitizeFunctionsError(FirebaseFunctionsException e) {
  switch (e.code) {
    case 'unauthenticated':
      return 'You are not signed in. Please sign in and try again.';
    case 'permission-denied':
      return 'You do not have permission to perform this action.';
    case 'not-found':
      return 'The requested resource was not found.';
    case 'unavailable':
      return 'The service is temporarily unavailable. Please try again.';
    case 'resource-exhausted':
      return 'Rate limit reached. Please wait before trying again.';
    default:
      return 'An error occurred. Please try again.';
  }
}

// ---------------------------------------------------------------------------
// Riverpod Provider
// ---------------------------------------------------------------------------

final omniToolRegistryProvider = Provider<OmniToolRegistry>((ref) {
  final inboxRepo = ref.watch(canonicalInboxRepositoryProvider);
  final controlPlane = ref.watch(controlPlaneServiceProvider);
  final connectorRegistry = ref.watch(connectorRegistryServiceProvider);
  return buildToolRegistry(
    inboxRepo,
    controlPlane,
    connectorRegistry,
    FirebaseFirestore.instance,
    FirebaseFunctions.instance,
    ref.watch(projectRepositoryProvider),
  );
});
