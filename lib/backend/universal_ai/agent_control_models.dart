import 'package:oneova/backend/universal_ai/universal_ai_models.dart'; // Reusing AIToolCategory

enum AgentMode {
  suggestions,
  draft,
  scheduled,
  auto,
}

class AgentLimits {
  final int maxDailyActions;
  final int maxDailyMessages;
  final double maxCostUsd;
  final int allowedHourStart; // 0-23
  final int allowedHourEnd;   // 0-23
  final List<String> blockedContacts;

  const AgentLimits({
    this.maxDailyActions = 50,
    this.maxDailyMessages = 20,
    this.maxCostUsd = 1.0,
    this.allowedHourStart = 0, // midnight
    this.allowedHourEnd = 24,  // midnight next day
    this.blockedContacts = const [],
  });
}

class ControlledAgentProfile {
  final String id;
  final String ownerUserId;
  final AgentMode mode;
  final List<AIToolCategory> allowedPermissions;
  final AgentLimits limits;

  const ControlledAgentProfile({
    required this.id,
    required this.ownerUserId,
    required this.mode,
    required this.allowedPermissions,
    required this.limits,
  });
}

class AutonomousActionAudit {
  final String id;
  final String agentId;
  final DateTime timestamp;
  final String toolName;
  final Map<String, dynamic> toolInvocationParams;
  final dynamic result;
  final bool authorized;
  final String authorizationReason;

  const AutonomousActionAudit({
    required this.id,
    required this.agentId,
    required this.timestamp,
    required this.toolName,
    required this.toolInvocationParams,
    this.result,
    required this.authorized,
    required this.authorizationReason,
  });
}
