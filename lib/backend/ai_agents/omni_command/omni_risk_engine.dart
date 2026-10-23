import 'omni_intent_engine.dart';
import 'omni_context_resolver.dart';

// ---------------------------------------------------------------------------
// Risk Engine
// ---------------------------------------------------------------------------
// Every tool execution is classified by risk level BEFORE it runs.
// High/Critical actions require confirmation. LOW/MEDIUM may proceed silently.
// This classification is enforced server-side. The client enforces it too
// to provide a good UX (confirmation dialogs), but the server is authoritative.
// ---------------------------------------------------------------------------

enum RiskLevel {
  /// Read-only, no external side effects.
  low,

  /// Mutates local state (e.g., mark read, set priority).
  medium,

  /// External side effect (e.g., send message, assign conversation).
  high,

  /// Irreversible or destructive action (e.g., delete data, disconnect account).
  critical,
}

/// Documents the risk classification for an action.
class RiskAssessment {
  final RiskLevel level;
  final String rationale;
  final bool requiresConfirmation;
  final bool requiresApprovalMode;

  const RiskAssessment({
    required this.level,
    required this.rationale,
    required this.requiresConfirmation,
    required this.requiresApprovalMode,
  });
}

class OmniRiskEngine {
  /// Classifies the risk of executing [toolId] in [context].
  RiskAssessment classify(String toolId, OmniContext context) {
    switch (toolId) {
      // --------------- LOW RISK (read-only) ---------------
      case 'search_inbox':
      case 'search_messages':
      case 'get_conversation':
      case 'get_notifications':
      case 'get_connector_health':
      case 'list_connected_accounts':
      case 'get_connector_capabilities':
      case 'search_media':
      case 'read_project':
        return const RiskAssessment(
          level: RiskLevel.low,
          rationale: 'Read-only operation. No external side effects.',
          requiresConfirmation: false,
          requiresApprovalMode: false,
        );

      // --------------- LOW/MEDIUM (summarize, draft, translate) ---------------
      case 'summarize_conversation':
      case 'draft_reply':
      case 'translate_message':
        return const RiskAssessment(
          level: RiskLevel.low,
          rationale: 'Generates a draft or summary. No external message is sent.',
          requiresConfirmation: false,
          requiresApprovalMode: false,
        );

      // --------------- MEDIUM (local mutations) ---------------
      case 'mark_message_read':
      case 'set_priority':
        return const RiskAssessment(
          level: RiskLevel.medium,
          rationale: 'Mutates local conversation state. Reversible.',
          requiresConfirmation: false,
          requiresApprovalMode: true,
        );

      case 'assign_conversation':
        return const RiskAssessment(
          level: RiskLevel.medium,
          rationale: 'Assigns a conversation to a team member. Can be re-assigned.',
          requiresConfirmation: true,
          requiresApprovalMode: true,
        );

      // --------------- HIGH (external side effects) ---------------
      case 'send_message':
        return const RiskAssessment(
          level: RiskLevel.high,
          rationale:
              'Sends a real message to an external recipient via a connected platform. '
              'Cannot be recalled in most cases.',
          requiresConfirmation: true,
          requiresApprovalMode: true,
        );

      case 'refresh_connector':
        return const RiskAssessment(
          level: RiskLevel.high,
          rationale: 'Initiates a re-authorization flow for a connected platform account.',
          requiresConfirmation: true,
          requiresApprovalMode: true,
        );

      case 'upload_media':
        return const RiskAssessment(
          level: RiskLevel.high,
          rationale: 'Uploads a media file to a connected platform.',
          requiresConfirmation: true,
          requiresApprovalMode: true,
        );
        
      case 'export_project':
        return const RiskAssessment(
          level: RiskLevel.high,
          rationale: 'Initiates export or render process.',
          requiresConfirmation: true,
          requiresApprovalMode: true,
        );

      case 'create_message_draft':
        return const RiskAssessment(
          level: RiskLevel.medium,
          rationale: 'Creates a saved draft. Not sent externally.',
          requiresConfirmation: false,
          requiresApprovalMode: true,
        );

      case 'modify_project':
        return const RiskAssessment(
          level: RiskLevel.medium,
          rationale: 'Modifies local project sequence. Undo available.',
          requiresConfirmation: true,
          requiresApprovalMode: true,
        );

      case 'apply_effect':
        return const RiskAssessment(
          level: RiskLevel.medium,
          rationale: 'Applies visual effect to current project. Reversible.',
          requiresConfirmation: false,
          requiresApprovalMode: true,
        );

      // --------------- CRITICAL (irreversible/destructive) ---------------
      case 'delete_message':
      case 'disconnect_account':
      case 'delete_memory':
      case 'reset_memory':
      case 'delete_project':
        return const RiskAssessment(
          level: RiskLevel.critical,
          rationale: 'Irreversible destructive action. Requires explicit user confirmation.',
          requiresConfirmation: true,
          requiresApprovalMode: true,
        );

      default:
        // Unknown tools are treated as critical to fail safe.
        return const RiskAssessment(
          level: RiskLevel.critical,
          rationale: 'Unknown tool ID. Blocked as a safety measure.',
          requiresConfirmation: true,
          requiresApprovalMode: true,
        );
    }
  }

  /// Returns whether the current [aiMode] satisfies the risk level of this action.
  bool isModeAuthorized(AiOperatingMode mode, RiskAssessment risk) {
    if (mode == AiOperatingMode.off) return false;
    if (mode == AiOperatingMode.assist) {
      return !risk.requiresApprovalMode && risk.level == RiskLevel.low;
    }
    if (mode == AiOperatingMode.draft) {
      if (risk.requiresApprovalMode) return false;
      return risk.level == RiskLevel.low || risk.level == RiskLevel.medium;
    }
    if (mode == AiOperatingMode.approval || mode == AiOperatingMode.auto) {
      return true; // Confirmation engine will gate HIGH/CRITICAL separately
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// Planner
// ---------------------------------------------------------------------------
// For multi-step operations, the Planner produces an ordered list of ToolCall
// objects. The Planner ONLY creates plans using tools that exist in the
// registered ToolRegistry. It never invents tool IDs.
// ---------------------------------------------------------------------------

class ToolCall {
  final String toolId;
  final Map<String, dynamic> parameters;

  /// Unique execution ID for idempotency tracking
  final String executionId;

  /// Human-readable status label shown in the UI during execution
  final String progressLabel;

  const ToolCall({
    required this.toolId,
    required this.parameters,
    required this.executionId,
    required this.progressLabel,
  });

  Map<String, dynamic> toJson() => {
        'toolId': toolId,
        'parameters': parameters,
        'executionId': executionId,
      };
}

class OmniPlan {
  final String planId;
  final String sessionId;
  final OmniIntent intent;
  final List<ToolCall> steps;
  final DateTime createdAt;

  const OmniPlan({
    required this.planId,
    required this.sessionId,
    required this.intent,
    required this.steps,
    required this.createdAt,
  });
}

class OmniPlanner {
  final Set<String> _registeredToolIds;

  OmniPlanner(this._registeredToolIds);

  /// Build a plan for the given [intent] and [context].
  /// Returns null if the intent cannot be mapped to any registered tool.
  OmniPlan? buildPlan(OmniIntent intent, OmniContext context) {
    final planId = 'plan_${DateTime.now().millisecondsSinceEpoch}';
    final steps = _buildSteps(intent, context);

    // Validate: every planned tool must exist in the registry
    for (final step in steps) {
      if (!_registeredToolIds.contains(step.toolId)) {
        // If a tool is not registered, abort the entire plan
        return null;
      }
    }

    if (steps.isEmpty) return null;

    return OmniPlan(
      planId: planId,
      sessionId: context.sessionId,
      intent: intent,
      steps: steps,
      createdAt: DateTime.now(),
    );
  }

  List<ToolCall> _buildSteps(OmniIntent intent, OmniContext context) {
    final ts = DateTime.now().millisecondsSinceEpoch;

    switch (intent.category) {
      case IntentCategory.searchInbox:
        return [
          ToolCall(
            toolId: 'search_inbox',
            parameters: intent.parameters,
            executionId: 'exec_${ts}_search_inbox',
            progressLabel: 'Searching your inbox...',
          ),
        ];

      case IntentCategory.searchMessages:
        return [
          ToolCall(
            toolId: 'search_messages',
            parameters: intent.parameters,
            executionId: 'exec_${ts}_search_messages',
            progressLabel: 'Searching messages...',
          ),
        ];

      case IntentCategory.summarizeConversation:
        return [
          ToolCall(
            toolId: 'get_conversation',
            parameters: {
              'conversationId': intent.parameters['conversationId'] ?? context.conversationId,
            },
            executionId: 'exec_${ts}_get_conv',
            progressLabel: 'Loading conversation...',
          ),
          ToolCall(
            toolId: 'summarize_conversation',
            parameters: {
              'conversationId': intent.parameters['conversationId'] ?? context.conversationId,
            },
            executionId: 'exec_${ts}_summarize',
            progressLabel: 'Summarizing conversation...',
          ),
        ];

      case IntentCategory.draftReply:
        return [
          ToolCall(
            toolId: 'draft_reply',
            parameters: {
              'conversationId': intent.parameters['conversationId'] ?? context.conversationId,
              'tone': intent.parameters['tone'] ?? 'professional',
            },
            executionId: 'exec_${ts}_draft',
            progressLabel: 'Drafting a reply...',
          ),
        ];

      case IntentCategory.translateMessage:
        return [
          ToolCall(
            toolId: 'translate_message',
            parameters: {
              'conversationId': intent.parameters['conversationId'] ?? context.conversationId,
              'messageId': intent.parameters['messageId'] ?? context.messageId,
              'targetLanguage': intent.parameters['targetLanguage'] ?? 'en',
            },
            executionId: 'exec_${ts}_translate',
            progressLabel: 'Translating message...',
          ),
        ];

      case IntentCategory.sendMessage:
        return [
          ToolCall(
            toolId: 'send_message',
            parameters: {
              'conversationId': intent.parameters['conversationId'] ?? context.conversationId,
            },
            executionId: 'exec_${ts}_send',
            progressLabel: 'Preparing to send...',
          ),
        ];

      case IntentCategory.markRead:
        return [
          ToolCall(
            toolId: 'mark_message_read',
            parameters: {
              'conversationId': intent.parameters['conversationId'] ?? context.conversationId,
            },
            executionId: 'exec_${ts}_mark_read',
            progressLabel: 'Marking as read...',
          ),
        ];

      case IntentCategory.setPriority:
        return [
          ToolCall(
            toolId: 'set_priority',
            parameters: intent.parameters,
            executionId: 'exec_${ts}_priority',
            progressLabel: 'Updating priority...',
          ),
        ];

      case IntentCategory.getNotifications:
        return [
          ToolCall(
            toolId: 'get_notifications',
            parameters: intent.parameters,
            executionId: 'exec_${ts}_notifs',
            progressLabel: 'Loading notifications...',
          ),
        ];

      case IntentCategory.getConnectorStatus:
        return [
          ToolCall(
            toolId: 'get_connector_health',
            parameters: intent.parameters,
            executionId: 'exec_${ts}_health',
            progressLabel: 'Checking platform status...',
          ),
        ];

      case IntentCategory.listConnectedAccounts:
        return [
          ToolCall(
            toolId: 'list_connected_accounts',
            parameters: {},
            executionId: 'exec_${ts}_accounts',
            progressLabel: 'Loading connected accounts...',
          ),
        ];

      case IntentCategory.searchMedia:
        return [
          ToolCall(
            toolId: 'search_media',
            parameters: {
              'conversationId': intent.parameters['conversationId'] ?? context.conversationId,
            },
            executionId: 'exec_${ts}_media',
            progressLabel: 'Searching media...',
          ),
        ];

      case IntentCategory.assignConversation:
        return [
          ToolCall(
            toolId: 'assign_conversation',
            parameters: intent.parameters,
            executionId: 'exec_${ts}_assign',
            progressLabel: 'Assigning conversation...',
          ),
        ];

      case IntentCategory.refreshConnector:
        return [
          ToolCall(
            toolId: 'refresh_connector',
            parameters: intent.parameters,
            executionId: 'exec_${ts}_reconnect',
            progressLabel: 'Initiating reconnection...',
          ),
        ];

      case IntentCategory.getConversation:
        return [
          ToolCall(
            toolId: 'get_conversation',
            parameters: {
              'conversationId': intent.parameters['conversationId'] ?? context.conversationId,
            },
            executionId: 'exec_${ts}_get_conv',
            progressLabel: 'Loading conversation...',
          ),
        ];

      case IntentCategory.summarizeMessages:
        return [
          ToolCall(
            toolId: 'summarize_conversation',
            parameters: intent.parameters,
            executionId: 'exec_${ts}_summarize_msgs',
            progressLabel: 'Summarizing messages...',
          ),
        ];

      case IntentCategory.readProject:
        return [
          ToolCall(
            toolId: 'read_project',
            parameters: intent.parameters,
            executionId: 'exec_${ts}_read_proj',
            progressLabel: 'Loading project...',
          ),
        ];

      case IntentCategory.modifyProject:
        return [
          ToolCall(
            toolId: 'modify_project',
            parameters: intent.parameters,
            executionId: 'exec_${ts}_mod_proj',
            progressLabel: 'Modifying project...',
          ),
        ];

      case IntentCategory.applyEffect:
        return [
          ToolCall(
            toolId: 'apply_effect',
            parameters: intent.parameters,
            executionId: 'exec_${ts}_effect',
            progressLabel: 'Applying effect...',
          ),
        ];

      case IntentCategory.exportProject:
        return [
          ToolCall(
            toolId: 'export_project',
            parameters: intent.parameters,
            executionId: 'exec_${ts}_export',
            progressLabel: 'Exporting project...',
          ),
        ];

      case IntentCategory.deleteProject:
        return [
          ToolCall(
            toolId: 'delete_project',
            parameters: intent.parameters,
            executionId: 'exec_${ts}_del_proj',
            progressLabel: 'Deleting project...',
          ),
        ];

      case IntentCategory.setColorExposure:
        return [
          ToolCall(
            toolId: 'color.set_exposure',
            parameters: intent.parameters,
            executionId: 'exec_${ts}_col_exp',
            progressLabel: 'Setting exposure...',
          ),
        ];

      case IntentCategory.setColorContrast:
        return [
          ToolCall(
            toolId: 'color.set_contrast',
            parameters: intent.parameters,
            executionId: 'exec_${ts}_col_cont',
            progressLabel: 'Setting contrast...',
          ),
        ];

      case IntentCategory.setColorHighlights:
        return [
          ToolCall(
            toolId: 'color.set_highlights',
            parameters: intent.parameters,
            executionId: 'exec_${ts}_col_high',
            progressLabel: 'Setting highlights...',
          ),
        ];

      case IntentCategory.applyColorLut:
        return [
          ToolCall(
            toolId: 'color.apply_lut',
            parameters: intent.parameters,
            executionId: 'exec_${ts}_col_lut',
            progressLabel: 'Applying LUT...',
          ),
        ];

      case IntentCategory.applyColorPreset:
        return [
          ToolCall(
            toolId: 'color.apply_preset',
            parameters: intent.parameters,
            executionId: 'exec_${ts}_col_preset',
            progressLabel: 'Applying preset...',
          ),
        ];

      case IntentCategory.createSecondaryGrade:
        return [
          ToolCall(
            toolId: 'color.create_secondary_grade',
            parameters: intent.parameters,
            executionId: 'exec_${ts}_col_sec',
            progressLabel: 'Creating secondary grade...',
          ),
        ];

      case IntentCategory.unknown:
        return [];
    }
  }
}
