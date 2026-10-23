
enum PermissionResource {
  messages,
  contacts,
  files,
  calls,
  analytics,
  automation,
  ai,
  billing,
  settings,
  privacy,
  teamManagement,
  channelManagement
}

enum PermissionAction { read, write, delete, execute, assign }

class RolePermission {
  final PermissionResource resource;
  final PermissionAction action;

  const RolePermission(this.resource, this.action);

  String toScopeString() => '\${resource.name}:\${action.name}';
}

/// Represents a configurable role within a workspace
class WorkspaceRole {
  final String id;
  final String name;
  final String description;
  final List<String> grantedScopes; // List of 'resource:action'
  final bool isSystemRole;

  const WorkspaceRole({
    required this.id,
    required this.name,
    required this.description,
    required this.grantedScopes,
    this.isSystemRole = false,
  });

  bool hasPermission(PermissionResource resource, PermissionAction action) {
    final scope = '\${resource.name}:\${action.name}';
    // Admin override or explicit scope check
    return grantedScopes.contains('*') || grantedScopes.contains(scope);
  }

  factory WorkspaceRole.fromJson(Map<String, dynamic> json) {
    return WorkspaceRole(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      grantedScopes: List<String>.from(json['grantedScopes'] ?? []),
      isSystemRole: json['isSystemRole'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'grantedScopes': grantedScopes,
    'isSystemRole': isSystemRole,
  };
}

/// A member belonging to a workspace
class WorkspaceMember {
  final String uid;
  final String workspaceId;
  final String roleId;
  final String? teamId; // Optional specific team assignment
  final bool isOnline; // Agent presence
  final bool isAvailable; // Taking routing?

  const WorkspaceMember({
    required this.uid,
    required this.workspaceId,
    required this.roleId,
    this.teamId,
    this.isOnline = false,
    this.isAvailable = true,
  });

  factory WorkspaceMember.fromJson(Map<String, dynamic> json) {
    return WorkspaceMember(
      uid: json['uid'] as String,
      workspaceId: json['workspaceId'] as String,
      roleId: json['roleId'] as String,
      teamId: json['teamId'] as String?,
      isOnline: json['isOnline'] as bool? ?? false,
      isAvailable: json['isAvailable'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'workspaceId': workspaceId,
    'roleId': roleId,
    'teamId': teamId,
    'isOnline': isOnline,
    'isAvailable': isAvailable,
  };
}

class InternalNote {
  final String id;
  final String authorId;
  final String text;
  final List<String> mentionedUids;
  final DateTime createdAt;

  const InternalNote({
    required this.id,
    required this.authorId,
    required this.text,
    this.mentionedUids = const [],
    required this.createdAt,
  });

  factory InternalNote.fromJson(Map<String, dynamic> json) {
    return InternalNote(
      id: json['id'] as String,
      authorId: json['authorId'] as String,
      text: json['text'] as String,
      mentionedUids: List<String>.from(json['mentionedUids'] ?? []),
      createdAt: json['createdAt'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'authorId': authorId,
    'text': text,
    'mentionedUids': mentionedUids,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };
}
