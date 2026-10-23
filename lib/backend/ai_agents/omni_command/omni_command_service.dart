// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../openrouter_agent_service.dart';
import 'omni_context_resolver.dart';
import 'omni_intent_engine.dart';
import 'omni_risk_engine.dart';
import 'omni_tool_registry.dart';
import 'omni_assistant_service.dart';
import 'personal_memory_engine.dart';
import '../../audit/models/audit_models.dart';
import '../../audit/audit_ledger_service.dart';

// ---------------------------------------------------------------------------
// Omni Command State
// ---------------------------------------------------------------------------

enum OmniRequestStatus {
  idle,
  classifying,    // Parsing intent
  planning,       // Building tool plan
  executing,      // Running tools
  awaitingConfirmation,
  generating,     // AI text generation
  completed,
  failed,
  cancelled,
}

class OmniTurnMessage {
  final String role; // 'user' | 'assistant' | 'tool'
  final String content;
  final DateTime timestamp;
  final List<ToolResult>? toolResults;

  const OmniTurnMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.toolResults,
  });
}

class OmniCommandState {
  final OmniRequestStatus status;
  final List<OmniTurnMessage> history;

  /// The current tool step label shown in the UI (e.g. "Searching inbox...")
  final String? progressLabel;

  /// The pending tool call awaiting user confirmation
  final ToolCall? pendingConfirmation;
  final OmniPlan? pendingPlan;

  /// The last fully completed AI response
  final String? lastResponse;
  final String? errorMessage;

  /// Suggested actions derived from real context
  final List<String> suggestions;

  /// Command History
  final List<ToolCall> recentCommands;

  /// Last undoable action
  final ToolCall? lastUndoableAction;

  const OmniCommandState({
    this.status = OmniRequestStatus.idle,
    this.history = const [],
    this.progressLabel,
    this.pendingConfirmation,
    this.pendingPlan,
    this.lastResponse,
    this.errorMessage,
    this.suggestions = const [],
    this.recentCommands = const [],
    this.lastUndoableAction,
  });

  OmniCommandState copyWith({
    OmniRequestStatus? status,
    List<OmniTurnMessage>? history,
    String? progressLabel,
    ToolCall? pendingConfirmation,
    OmniPlan? pendingPlan,
    String? lastResponse,
    String? errorMessage,
    List<String>? suggestions,
    List<ToolCall>? recentCommands,
    ToolCall? lastUndoableAction,
    bool clearUndoable = false,
  }) {
    return OmniCommandState(
      status: status ?? this.status,
      history: history ?? this.history,
      progressLabel: progressLabel,
      pendingConfirmation: pendingConfirmation ?? this.pendingConfirmation,
      pendingPlan: pendingPlan ?? this.pendingPlan,
      lastResponse: lastResponse ?? this.lastResponse,
      errorMessage: errorMessage ?? this.errorMessage,
      suggestions: suggestions ?? this.suggestions,
      recentCommands: recentCommands ?? this.recentCommands,
      lastUndoableAction: clearUndoable ? null : (lastUndoableAction ?? this.lastUndoableAction),
    );
  }
}

// ---------------------------------------------------------------------------
// Confirmation Request
// ---------------------------------------------------------------------------

class ConfirmationRequest {
  final ToolCall toolCall;
  final OmniToolDefinition definition;
  final RiskAssessment risk;

  /// Human-readable summary of WHAT will happen
  final String whatLabel;

  /// Platform/connector it targets (if any)
  final String? whereLabel;

  /// Target (recipient, conversation name, etc.)
  final String? targetLabel;

  /// Content being sent (if applicable)
  final String? contentPreview;

  const ConfirmationRequest({
    required this.toolCall,
    required this.definition,
    required this.risk,
    required this.whatLabel,
    this.whereLabel,
    this.targetLabel,
    this.contentPreview,
  });
}

// ---------------------------------------------------------------------------
// Omni Command Service (Central Orchestrator)
// ---------------------------------------------------------------------------
// Pipeline:
//   User input
//   → Context resolution
//   → Intent classification
//   → Capability/mode gating
//   → Planner (registered tools only)
//   → Risk assessment
//   → Confirmation (if required)
//   → Tool execution
//   → Result sanitization
//   → AI text generation
//   → Audit
//   → UI state update
// ---------------------------------------------------------------------------

class OmniCommandService extends Notifier<OmniCommandState> {
  late OmniIntentEngine _intentEngine;
  late OmniRiskEngine _riskEngine;
  late AuditLedgerService _auditService;

  /// Active request ID. Any response with a different ID is stale and discarded.
  String? _activeRequestId;
  int _requestCounter = 0;

  @override
  OmniCommandState build() {
    _intentEngine = OmniIntentEngine();
    _riskEngine = OmniRiskEngine();
    _auditService = ref.read(auditLedgerServiceProvider);
    return const OmniCommandState();
  }

  // ---------------------------------------------------------------------------
  // Main entry: process a user prompt
  // ---------------------------------------------------------------------------

  Future<void> process(String rawInput, OmniContext context) async {
    if (rawInput.trim().isEmpty) return;

    // Gate: AI is off
    if (context.aiMode == AiOperatingMode.off) {
      _emitFailed('AI is currently disabled. Enable it in Settings to continue.');
      return;
    }

    _requestCounter++;
    final requestId = 'req_${DateTime.now().microsecondsSinceEpoch}_$_requestCounter';
    _activeRequestId = requestId;

    // Append user turn to history
    final userMsg = OmniTurnMessage(
      role: 'user',
      content: rawInput,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(
      status: OmniRequestStatus.classifying,
      history: [...state.history, userMsg],
      progressLabel: 'Understanding your request...',
      errorMessage: null,
    );

    try {
      // 1. Classify intent
      final intent = _intentEngine.classify(rawInput, context);
      if (_isStale(requestId)) return;

      if (intent.category == IntentCategory.unknown) {
        // Fallback to conversational AI response
        await _generateConversationalResponse(rawInput, context, requestId);
        return;
      }

      // 2. Capability gate
      if (!_hasRequiredCapabilities(intent, context)) {
        _emitFailed(
          _capabilityBlockedMessage(intent, context.aiMode),
        );
        _auditService.logStarted(
          actorId: context.userId,
          sessionId: context.sessionId,
          correlationId: requestId,
          surface: context.surface ?? 'unknown',
          toolId: 'unknown',
          operationType: OperationType.read,
          action: intent.category.name,
          targetType: 'unknown',
          targetId: 'unknown',
          authorizationState: AuthorizationState.denied,
          confirmationState: ConfirmationState.notRequired,
        ).then((_) => _auditService.logFailed(
          correlationId: requestId,
          targetId: 'unknown',
          toolId: 'unknown',
          failureCode: 'BLOCKED_CAPABILITY',
        ));
        return;
      }

      // 3. Build plan
      final registry = ref.read(omniToolRegistryProvider);
      final planner = OmniPlanner(registry.registeredIds);

      state = state.copyWith(
        status: OmniRequestStatus.planning,
        progressLabel: 'Planning...',
      );

      final plan = planner.buildPlan(intent, context);
      if (_isStale(requestId)) return;

      if (plan == null || plan.steps.isEmpty) {
        await _generateConversationalResponse(rawInput, context, requestId);
        return;
      }

      // 4. Execute plan step by step
      state = state.copyWith(
        status: OmniRequestStatus.executing,
        pendingPlan: plan,
      );

      final allResults = <ToolResult>[];

      for (final step in plan.steps) {
        if (_isStale(requestId)) return;

        // Risk assessment
        final risk = _riskEngine.classify(step.toolId, context);
        if (!_riskEngine.isModeAuthorized(context.aiMode, risk)) {
          _emitFailed('This action requires a higher AI permission mode.');
          return;
        }

        // Confirmation gate for HIGH/CRITICAL
        if (risk.requiresConfirmation && context.aiMode != AiOperatingMode.auto) {
          final toolDef = registry.getDefinition(step.toolId);
          if (toolDef != null) {
            final confirmReq = ConfirmationRequest(
              toolCall: step,
              definition: toolDef,
              risk: risk,
              whatLabel: toolDef.name,
              whereLabel: step.parameters['platformId'] as String?,
              targetLabel: step.parameters['conversationId'] as String?,
              contentPreview: step.parameters['content'] as String?,
            );
            state = state.copyWith(
              status: OmniRequestStatus.awaitingConfirmation,
              pendingConfirmation: step,
              progressLabel: null,
            );
            _auditService.logStarted(
              actorId: context.userId,
              sessionId: context.sessionId,
              correlationId: requestId,
              surface: context.surface ?? 'unknown',
              toolId: step.toolId,
              operationType: _getOpType(risk.level),
              action: intent.category.name,
              targetType: 'unknown',
              targetId: 'unknown',
              authorizationState: AuthorizationState.authorized,
              confirmationState: ConfirmationState.pending,
            );
            // Emit the confirmation request as assistant message
            _appendAssistantMessage(
              _buildConfirmationMessage(confirmReq),
              toolResults: null,
            );
            return; // Stop here — user must confirm
          }
        }

        final isRead = intent.isReadOperation;
        if (!isRead) {
          await _auditService.logStarted(
            actorId: context.userId,
            sessionId: context.sessionId,
            correlationId: requestId,
            surface: context.surface ?? 'unknown',
            toolId: step.toolId,
            operationType: _getOpType(risk.level),
            action: intent.category.name,
            targetType: 'unknown',
            targetId: 'unknown',
            authorizationState: AuthorizationState.authorized,
            confirmationState: risk.requiresConfirmation ? ConfirmationState.confirmed : ConfirmationState.notRequired,
          );
        }

        // Execute tool
        state = state.copyWith(progressLabel: step.progressLabel);
        final result = await registry.execute(step.toolId, step.parameters, context);
        if (_isStale(requestId)) return;

        allResults.add(result);

        if (!isRead) {
          if (result.success) {
            await _auditService.logCompleted(
              correlationId: requestId,
              targetId: 'unknown',
              toolId: step.toolId,
              undoAvailable: result.data['undoAvailable'] == true,
              metadata: result.data,
            );
          } else {
            await _auditService.logFailed(
              correlationId: requestId,
              targetId: 'unknown',
              toolId: step.toolId,
              failureCode: result.errorMessage ?? 'UNKNOWN_ERROR',
              metadata: result.data,
            );
          }
        }

        if (!result.success) {
          _emitFailed(result.errorMessage ?? result.statusMessage);
          _appendAssistantMessage(result.errorMessage ?? result.statusMessage, toolResults: allResults);
          return;
        }

        // Track history and undoable actions
        final updatedRecent = [step, ...state.recentCommands].take(10).toList();
        ToolCall? undoable = state.lastUndoableAction;
        
        // Let's assume medium risk actions that mutate locally can be undone 
        // if they have an inverse, for now we track them if risk is medium.
        if (risk.level == RiskLevel.medium && result.success) {
          undoable = step;
        }

        state = state.copyWith(
          recentCommands: updatedRecent,
          lastUndoableAction: undoable,
        );
      }

      if (_isStale(requestId)) return;

      // 5. Generate AI narrative from tool results
      await _generateNarrativeResponse(rawInput, intent, allResults, context, requestId);
    } catch (e) {
      if (_isStale(requestId)) return;
      print('OmniCommandService error: $e');
      _emitFailed('An unexpected error occurred. Please try again.');
    }
  }

  // ---------------------------------------------------------------------------
  // Confirmation flow
  // ---------------------------------------------------------------------------

  Future<void> confirmPendingAction(OmniContext context) async {
    final pending = state.pendingConfirmation;
    if (pending == null) return;

    final requestId = 'req_confirm_${DateTime.now().millisecondsSinceEpoch}';
    _activeRequestId = requestId;

    state = state.copyWith(
      status: OmniRequestStatus.executing,
      progressLabel: pending.progressLabel,
      pendingConfirmation: null,
    );

    final risk = _riskEngine.classify(pending.toolId, context);
    await _auditService.logStarted(
      actorId: context.userId,
      sessionId: context.sessionId,
      correlationId: requestId,
      surface: context.surface ?? 'unknown',
      toolId: pending.toolId,
      operationType: _getOpType(risk.level),
      action: 'confirmed_action',
      targetType: 'unknown',
      targetId: 'unknown',
      authorizationState: AuthorizationState.authorized,
      confirmationState: ConfirmationState.confirmed,
    );

    final registry = ref.read(omniToolRegistryProvider);
    final result = await registry.execute(pending.toolId, pending.parameters, context);

    if (result.success) {
      await _auditService.logCompleted(
        correlationId: requestId,
        targetId: 'unknown',
        toolId: pending.toolId,
        undoAvailable: result.data['undoAvailable'] == true,
        metadata: result.data,
      );
    } else {
      await _auditService.logFailed(
        correlationId: requestId,
        targetId: 'unknown',
        toolId: pending.toolId,
        failureCode: result.errorMessage ?? 'UNKNOWN_ERROR',
        metadata: result.data,
      );
    }

    _appendAssistantMessage(
      result.success ? result.statusMessage : (result.errorMessage ?? result.statusMessage),
      toolResults: [result],
    );
    state = state.copyWith(
      status: result.success ? OmniRequestStatus.completed : OmniRequestStatus.failed,
      progressLabel: null,
      lastResponse: result.statusMessage,
      errorMessage: result.success ? null : result.errorMessage,
    );
  }

  void cancelPendingAction() {
    state = state.copyWith(
      status: OmniRequestStatus.idle,
      pendingConfirmation: null,
      progressLabel: null,
    );
    _appendAssistantMessage('Action cancelled.', toolResults: null);
  }

  // ---------------------------------------------------------------------------
  // Cancellation
  // ---------------------------------------------------------------------------

  void cancel() {
    _activeRequestId = null; // Invalidate active request
    state = state.copyWith(
      status: OmniRequestStatus.idle,
      progressLabel: null,
    );
  }

  // ---------------------------------------------------------------------------
  // Memory
  // ---------------------------------------------------------------------------

  Future<void> clearHistory() async {
    state = const OmniCommandState();
  }

  // ---------------------------------------------------------------------------
  // Undo Support
  // ---------------------------------------------------------------------------

  Future<void> undoLastAction(OmniContext context) async {
    final lastAction = state.lastUndoableAction;
    if (lastAction == null) {
      _emitFailed("Nothing to undo.");
      return;
    }

    final requestId = 'req_undo_${DateTime.now().millisecondsSinceEpoch}';
    _activeRequestId = requestId;

    state = state.copyWith(
      status: OmniRequestStatus.executing,
      progressLabel: 'Undoing ${lastAction.progressLabel}...',
      clearUndoable: true,
    );

    // In a real implementation, we'd look up the inverse tool for lastAction.toolId.
    // For now, we simulate an undo tool call.
    final registry = ref.read(omniToolRegistryProvider);
    // Assuming tools might support an undo variation or parameter. 
    // Example: "modify_project" with "undo: true"
    final undoParams = Map<String, dynamic>.from(lastAction.parameters)..['undo'] = true;
    
    final result = await registry.execute(lastAction.toolId, undoParams, context);

    await _auditService.logStarted(
      actorId: context.userId,
      sessionId: context.sessionId,
      correlationId: requestId,
      surface: context.surface ?? 'unknown',
      toolId: lastAction.toolId,
      operationType: OperationType.write,
      action: 'undo',
      targetType: 'unknown',
      targetId: 'unknown',
      authorizationState: AuthorizationState.authorized,
      confirmationState: ConfirmationState.notRequired,
    );

    if (result.success) {
      await _auditService.logCompleted(
        correlationId: requestId,
        targetId: 'unknown',
        toolId: lastAction.toolId,
        undoAvailable: false,
      );
    } else {
      await _auditService.logFailed(
        correlationId: requestId,
        targetId: 'unknown',
        toolId: lastAction.toolId,
        failureCode: 'UNDO_FAILED',
      );
    }

    _appendAssistantMessage(
      result.success ? 'Action undone.' : 'Failed to undo.',
      toolResults: [result],
    );

    state = state.copyWith(
      status: result.success ? OmniRequestStatus.completed : OmniRequestStatus.failed,
      progressLabel: null,
      lastResponse: result.success ? 'Action undone.' : 'Failed to undo.',
    );
  }

  // ---------------------------------------------------------------------------
  // Suggestions
  // ---------------------------------------------------------------------------

  void updateSuggestions(List<String> suggestions) {
    state = state.copyWith(suggestions: suggestions);
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  bool _isStale(String requestId) => _activeRequestId != requestId;

  void _emitFailed(String message) {
    state = state.copyWith(
      status: OmniRequestStatus.failed,
      progressLabel: null,
      errorMessage: message,
    );
  }

  void _appendAssistantMessage(String content, {required List<ToolResult>? toolResults}) {
    final msg = OmniTurnMessage(
      role: 'assistant',
      content: content,
      timestamp: DateTime.now(),
      toolResults: toolResults,
    );
    state = state.copyWith(history: [...state.history, msg]);
  }

  bool _hasRequiredCapabilities(OmniIntent intent, OmniContext context) {
    if (intent.isReadOperation) return true;
    if (intent.requiresDraftMode) {
      return context.aiMode != AiOperatingMode.off &&
          context.aiMode != AiOperatingMode.assist;
    }
    if (intent.requiresApprovalMode) {
      return context.aiMode == AiOperatingMode.approval ||
          context.aiMode == AiOperatingMode.auto;
    }
    return true;
  }

  String _capabilityBlockedMessage(OmniIntent intent, AiOperatingMode mode) {
    if (intent.requiresDraftMode) {
      return 'To draft replies, set AI mode to Draft or higher in Settings.';
    }
    if (intent.requiresApprovalMode) {
      return 'This action requires AI Approval mode. Enable it in Settings.';
    }
    return 'This action is not available in your current AI mode.';
  }

  String _buildConfirmationMessage(ConfirmationRequest req) {
    final sb = StringBuffer();
    sb.writeln('**${req.whatLabel}**');
    if (req.whereLabel != null) sb.writeln('Platform: ${req.whereLabel}');
    if (req.targetLabel != null) sb.writeln('Target: ${req.targetLabel}');
    if (req.contentPreview != null) sb.writeln('Content: "${req.contentPreview}"');
    sb.writeln('Risk: **${req.risk.level.name.toUpperCase()}**');
    sb.writeln('\nConfirm to proceed, or Cancel to abort.');
    return sb.toString();
  }

  Future<void> _generateConversationalResponse(
    String rawInput,
    OmniContext context,
    String requestId,
  ) async {
    state = state.copyWith(
      status: OmniRequestStatus.generating,
      progressLabel: 'Thinking...',
    );

    // Build system prompt from existing OmniAssistantService
    final assistantService = ref.read(omniAssistantServiceProvider.notifier);
    final styleInstructions = assistantService.generateSystemPromptAdditions();

    // Load relevant memories (approved only)
    final memories = context.memoryEnabled
        ? await ref
            .read(personalMemoryEngineProvider)
            .retrieveRelevantMemories(context.userId, rawInput)
        : <SemanticMemory>[];

    final memoryContext = memories.isEmpty
        ? ''
        : '\n=== APPROVED MEMORY ===\n${memories
                .where((m) => m.confirmedByUser)
                .map((m) => '- ${m.content}')
                .join('\n')}';

    // Build minimal context description (no raw data)
    final contextDescription = '''
Current context: ${context.displayContext}
${context.conversationId != null ? 'In conversation: yes (ID withheld for privacy)' : ''}
${context.platformId != null ? 'Platform: ${context.platformId}' : ''}
AI Mode: ${context.aiMode.name}
    '''.trim();

    final systemPrompt = '''
You are the ONEROVA personal AI assistant. You help users manage their inbox, conversations, and social media platforms.
$styleInstructions

$contextDescription
$memoryContext

IMPORTANT RULES:
- You NEVER have direct database access.
- You NEVER send messages without explicit user confirmation.
- You NEVER expose API keys, tokens, or credentials.
- If you cannot fulfill a request, explain clearly what is needed.
- Report truthful execution states: Queued, Sending, Sent, Failed — never invent success.
    ''';

    final agentService = ref.read(openRouterAgentServiceProvider);
    final response = await agentService.queryAgent(systemPrompt, rawInput);

    if (_isStale(requestId)) return;

    final reply = response ??
        "I'm here to help! I can search your inbox, summarize conversations, draft replies, and more. What would you like to do?";

    _appendAssistantMessage(reply, toolResults: null);
    state = state.copyWith(
      status: OmniRequestStatus.completed,
      progressLabel: null,
      lastResponse: reply,
    );
  }

  Future<void> _generateNarrativeResponse(
    String rawInput,
    OmniIntent intent,
    List<ToolResult> results,
    OmniContext context,
    String requestId,
  ) async {
    state = state.copyWith(
      status: OmniRequestStatus.generating,
      progressLabel: 'Generating response...',
    );

    // Build sanitized tool result summary for the model
    final toolSummary = results
        .map((r) => '${r.toolId}: ${r.statusMessage}\nData: ${jsonEncode(r.data)}')
        .join('\n\n');

    final systemPrompt = '''
You are the ONEROVA personal AI assistant.
You have just executed the following tools on behalf of the user. Report results clearly, truthfully, and naturally.

Tool Results:
$toolSummary

RULES:
- Do NOT invent data not present in the tool results.
- If status is "queued", say "queued for delivery" — NOT "sent".
- If a tool failed, explain the failure clearly.
- Be concise. Avoid bullet-point-heavy responses.
- Never expose internal IDs, tokens, or system internals.
    ''';

    final agentService = ref.read(openRouterAgentServiceProvider);
    final response = await agentService.queryAgent(systemPrompt, rawInput);

    if (_isStale(requestId)) return;

    // Fallback narrative if model unavailable
    final narrative = response ?? _buildFallbackNarrative(results);

    _appendAssistantMessage(narrative, toolResults: results);
    state = state.copyWith(
      status: OmniRequestStatus.completed,
      progressLabel: null,
      lastResponse: narrative,
    );
  }

  String _buildFallbackNarrative(List<ToolResult> results) {
    if (results.isEmpty) return "I wasn't able to retrieve any results.";
    return results.map((r) => r.statusMessage).join(' ');
  }
}

// ---------------------------------------------------------------------------
// Audit Service
// ---------------------------------------------------------------------------

// Removed OmniCommandAuditService

// ---------------------------------------------------------------------------
// Riverpod Providers
// ---------------------------------------------------------------------------

final omniCommandServiceProvider =
    NotifierProvider<OmniCommandService, OmniCommandState>(
  OmniCommandService.new,
);

OperationType _getOpType(RiskLevel level) {
  if (level == RiskLevel.critical) return OperationType.destructive;
  if (level == RiskLevel.high) return OperationType.externalAction;
  if (level == RiskLevel.medium) return OperationType.write;
  return OperationType.read;
}

// ---------------------------------------------------------------------------
// AI Memory Settings
// ---------------------------------------------------------------------------

class AiSettings {
  final bool aiEnabled;
  final bool memoryEnabled;
  final bool conversationLearningEnabled;
  final bool styleLearningEnabled;
  final bool externalActionsEnabled;
  final AiOperatingMode mode;

  const AiSettings({
    this.aiEnabled = true,
    this.memoryEnabled = true,
    this.conversationLearningEnabled = false,
    this.styleLearningEnabled = true,
    this.externalActionsEnabled = false,
    this.mode = AiOperatingMode.assist,
  });

  AiSettings copyWith({
    bool? aiEnabled,
    bool? memoryEnabled,
    bool? conversationLearningEnabled,
    bool? styleLearningEnabled,
    bool? externalActionsEnabled,
    AiOperatingMode? mode,
  }) {
    return AiSettings(
      aiEnabled: aiEnabled ?? this.aiEnabled,
      memoryEnabled: memoryEnabled ?? this.memoryEnabled,
      conversationLearningEnabled:
          conversationLearningEnabled ?? this.conversationLearningEnabled,
      styleLearningEnabled: styleLearningEnabled ?? this.styleLearningEnabled,
      externalActionsEnabled: externalActionsEnabled ?? this.externalActionsEnabled,
      mode: mode ?? this.mode,
    );
  }
}

class AiSettingsNotifier extends Notifier<AiSettings> {
  static const _prefKey = 'omni_ai_settings';

  @override
  AiSettings build() {
    _loadSettings();
    return const AiSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_prefKey);
    if (data != null) {
      try {
        final map = jsonDecode(data) as Map<String, dynamic>;
        state = AiSettings(
          aiEnabled: map['aiEnabled'] ?? true,
          memoryEnabled: map['memoryEnabled'] ?? true,
          conversationLearningEnabled: map['conversationLearningEnabled'] ?? false,
          styleLearningEnabled: map['styleLearningEnabled'] ?? true,
          externalActionsEnabled: map['externalActionsEnabled'] ?? false,
          mode: AiOperatingMode.values.firstWhere(
            (e) => e.name == map['mode'],
            orElse: () => AiOperatingMode.assist,
          ),
        );
      } catch (e) {
        // default
      }
    }
  }

  Future<void> _saveSettings(AiSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final map = {
      'aiEnabled': settings.aiEnabled,
      'memoryEnabled': settings.memoryEnabled,
      'conversationLearningEnabled': settings.conversationLearningEnabled,
      'styleLearningEnabled': settings.styleLearningEnabled,
      'externalActionsEnabled': settings.externalActionsEnabled,
      'mode': settings.mode.name,
    };
    await prefs.setString(_prefKey, jsonEncode(map));
  }

  void setAiEnabled(bool enabled) {
    state = state.copyWith(
      aiEnabled: enabled,
      mode: enabled ? state.mode : AiOperatingMode.off,
    );
    _saveSettings(state);
  }

  void setMode(AiOperatingMode mode) {
    state = state.copyWith(mode: mode);
    _saveSettings(state);
  }

  void setMemoryEnabled(bool v) {
    state = state.copyWith(memoryEnabled: v);
    _saveSettings(state);
  }

  void setConversationLearning(bool v) {
    state = state.copyWith(conversationLearningEnabled: v);
    _saveSettings(state);
  }

  void setStyleLearning(bool v) {
    state = state.copyWith(styleLearningEnabled: v);
    _saveSettings(state);
  }

  void setExternalActions(bool v) {
    state = state.copyWith(externalActionsEnabled: v);
    _saveSettings(state);
  }

  AiOperatingMode get effectiveMode =>
      state.aiEnabled ? state.mode : AiOperatingMode.off;
}

final aiSettingsProvider =
    NotifierProvider<AiSettingsNotifier, AiSettings>(AiSettingsNotifier.new);
