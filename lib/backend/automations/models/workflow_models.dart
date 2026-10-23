
enum WorkflowTriggerType {
  newMessage,
  keyword,
  reaction,
  newFollower,
  newContact,
  formSubmission,
  scheduledTime,
  webhook,
  channelEvent,
  aiClassification,
}

enum WorkflowActionType {
  sendMessage,
  createDraft,
  assignConversation,
  addLabel,
  createTask,
  scheduleMessage,
  notifyTeam,
  callAi,
  escalate,
  updateContact,
  createCalendarEvent,
}

class WorkflowRetryPolicy {
  final int maxRetries;
  final Duration initialBackoff;
  final double backoffMultiplier;

  const WorkflowRetryPolicy({
    this.maxRetries = 3,
    this.initialBackoff = const Duration(seconds: 2),
    this.backoffMultiplier = 2.0,
  });
}

class WorkflowRateLimit {
  final int maxExecutions;
  final Duration window;

  const WorkflowRateLimit({
    this.maxExecutions = 10,
    this.window = const Duration(minutes: 1),
  });
}

class WorkflowAction {
  final String id;
  final WorkflowActionType type;
  final Map<String, dynamic> payload;
  final Duration? delayBeforeExecution;

  const WorkflowAction({
    required this.id,
    required this.type,
    this.payload = const {},
    this.delayBeforeExecution,
  });
}

class WorkflowCondition {
  final String field;
  final String operator; // e.g. "==", "contains", ">"
  final dynamic value;

  const WorkflowCondition({
    required this.field,
    required this.operator,
    required this.value,
  });
}

class WorkflowDefinition {
  final String id;
  final String name;
  final bool isEnabled;
  final int version;
  final String ownerId;
  final List<String> permissions;
  
  final WorkflowTriggerType triggerType;
  final Map<String, dynamic> triggerConfig;
  final List<WorkflowCondition> conditions;
  final List<WorkflowAction> actions;
  
  final WorkflowRetryPolicy retryPolicy;
  final WorkflowRateLimit rateLimit;
  
  // To prevent infinite loops (e.g. automated reply triggering another automated reply)
  final bool preventSelfTrigger;
  final int maxExecutionDepth;

  const WorkflowDefinition({
    required this.id,
    required this.name,
    this.isEnabled = false,
    this.version = 1,
    required this.ownerId,
    this.permissions = const [],
    required this.triggerType,
    this.triggerConfig = const {},
    this.conditions = const [],
    this.actions = const [],
    this.retryPolicy = const WorkflowRetryPolicy(),
    this.rateLimit = const WorkflowRateLimit(),
    this.preventSelfTrigger = true,
    this.maxExecutionDepth = 3,
  });
}

enum ExecutionStatus {
  pending,
  running,
  completed,
  failed,
  rateLimited,
  loopDetected,
}

class WorkflowExecutionLog {
  final String executionId;
  final String workflowId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final ExecutionStatus status;
  final String? errorMessage;
  final Map<String, dynamic> triggerPayload;

  const WorkflowExecutionLog({
    required this.executionId,
    required this.workflowId,
    required this.startedAt,
    this.completedAt,
    required this.status,
    this.errorMessage,
    required this.triggerPayload,
  });
}
