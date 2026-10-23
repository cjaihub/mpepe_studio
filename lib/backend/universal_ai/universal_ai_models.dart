
enum AIToolCategory {
  messages,
  content,
  video,
  analytics,
  locations,
  events,
  calendar,
  files,
  communities,
  connectedChannels,
}

/// Represents the authorization level required to execute a tool
enum ToolPrivilegeLevel {
  readOnly,
  userAction, // E.g., send message
  adminAction, // E.g., delete video
}

/// A structured tool definition passed to the AI
class AIToolDefinition {
  final String name;
  final String description;
  final AIToolCategory category;
  final ToolPrivilegeLevel privilege;
  final Map<String, dynamic> parameterSchema;

  const AIToolDefinition({
    required this.name,
    required this.description,
    required this.category,
    required this.privilege,
    required this.parameterSchema,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'category': category.name,
    'parameters': parameterSchema,
  };
}

/// The context of the user asking the AI
class AIUserContext {
  final String userId;
  final String? activeCommunityId;
  final List<String> grantedRoles;

  const AIUserContext({
    required this.userId,
    this.activeCommunityId,
    this.grantedRoles = const [],
  });
}

class AIAuditLog {
  final String id;
  final String userId;
  final String toolName;
  final String prompt;
  final bool permitted;
  final DateTime timestamp;
  final String? errorReason;

  const AIAuditLog({
    required this.id,
    required this.userId,
    required this.toolName,
    required this.prompt,
    required this.permitted,
    required this.timestamp,
    this.errorReason,
  });
}
