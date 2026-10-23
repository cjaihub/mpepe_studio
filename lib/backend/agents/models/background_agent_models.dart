
enum BackgroundAgentMode {
  offline,
  suggestions,
  drafts,
  scheduled,
  auto,
}

enum AgentStatus {
  idle,
  running,
  paused,
  emergencyStop,
}

enum EscalationPolicy {
  alwaysEscalate,
  escalateOnConfidenceLow,
  escalateOnSensitiveAction,
  noEscalation,
}

class BackgroundAgentConfig {
  final BackgroundAgentMode mode;
  final AgentStatus status;
  final List<String> allowedActions;
  final List<String> blockedActions;
  final List<String> allowedChannels;
  final List<String> allowedConversations;
  final EscalationPolicy escalationPolicy;
  final int dailyActionLimit;
  final int currentDailyActions;
  final double dailyBudgetLimit; 
  final double currentDailyBudgetUsed;
  final Map<String, String> schedule; // e.g. {"start": "09:00", "end": "17:00"}
  final bool isGlobalEmergencyStopActive;

  const BackgroundAgentConfig({
    this.mode = BackgroundAgentMode.offline,
    this.status = AgentStatus.idle,
    this.allowedActions = const [],
    this.blockedActions = const [],
    this.allowedChannels = const [],
    this.allowedConversations = const [],
    this.escalationPolicy = EscalationPolicy.alwaysEscalate,
    this.dailyActionLimit = 20,
    this.currentDailyActions = 0,
    this.dailyBudgetLimit = 5.0, // e.g., $5.00 daily spend limit
    this.currentDailyBudgetUsed = 0.0,
    this.schedule = const {},
    this.isGlobalEmergencyStopActive = false,
  });

  BackgroundAgentConfig copyWith({
    BackgroundAgentMode? mode,
    AgentStatus? status,
    List<String>? allowedActions,
    List<String>? blockedActions,
    List<String>? allowedChannels,
    List<String>? allowedConversations,
    EscalationPolicy? escalationPolicy,
    int? dailyActionLimit,
    int? currentDailyActions,
    double? dailyBudgetLimit,
    double? currentDailyBudgetUsed,
    Map<String, String>? schedule,
    bool? isGlobalEmergencyStopActive,
  }) {
    return BackgroundAgentConfig(
      mode: mode ?? this.mode,
      status: status ?? this.status,
      allowedActions: allowedActions ?? this.allowedActions,
      blockedActions: blockedActions ?? this.blockedActions,
      allowedChannels: allowedChannels ?? this.allowedChannels,
      allowedConversations: allowedConversations ?? this.allowedConversations,
      escalationPolicy: escalationPolicy ?? this.escalationPolicy,
      dailyActionLimit: dailyActionLimit ?? this.dailyActionLimit,
      currentDailyActions: currentDailyActions ?? this.currentDailyActions,
      dailyBudgetLimit: dailyBudgetLimit ?? this.dailyBudgetLimit,
      currentDailyBudgetUsed: currentDailyBudgetUsed ?? this.currentDailyBudgetUsed,
      schedule: schedule ?? this.schedule,
      isGlobalEmergencyStopActive: isGlobalEmergencyStopActive ?? this.isGlobalEmergencyStopActive,
    );
  }
}

class AiAuditEvent {
  final String id;
  final DateTime timestamp;
  final String actionTaken; // what the agent did
  final String reasoning; // why
  final String conversationId; // which conversation
  final String toolUsed; // which tool
  final Map<String, dynamic> dataAccessed; // which data
  final String generatedResponse; // what response was generated

  const AiAuditEvent({
    required this.id,
    required this.timestamp,
    required this.actionTaken,
    required this.reasoning,
    required this.conversationId,
    required this.toolUsed,
    required this.dataAccessed,
    required this.generatedResponse,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'actionTaken': actionTaken,
      'reasoning': reasoning,
      'conversationId': conversationId,
      'toolUsed': toolUsed,
      'dataAccessed': dataAccessed,
      'generatedResponse': generatedResponse,
    };
  }
}
