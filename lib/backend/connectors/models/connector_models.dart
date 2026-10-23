enum PlatformCapability {
  messagesRead,
  messagesSend,
  commentsRead,
  commentsReply,
  contentPublish,
  contentRead,
  stories,
  analytics,
  profileRead,
  profileWrite,
  webhooks,
  live,
  mediaUpload,
}

class Credential {
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
  final Map<String, dynamic> metadata;

  const Credential({
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
    this.metadata = const {},
  });
}

class ConnectedAccount {
  final String externalAccountId;
  final String platformId;
  final String connectorId;
  final String displayName;
  final String? username;
  final String? accountType;
  final String status;
  final List<PlatformCapability> capabilities;
  final List<String> scopes;
  final DateTime connectedAt;
  final DateTime? lastValidatedAt;
  final DateTime? lastSyncAt;
  final bool reauthRequired;
  final Map<String, dynamic> metadata;
  
  // NOTE: Credentials must never be stored in plain text inside this model in production/Firestore.
  // They should be stored in Secret Manager or encrypted.
  final Credential? credential;

  const ConnectedAccount({
    required this.externalAccountId,
    required this.platformId,
    required this.connectorId,
    required this.displayName,
    this.username,
    this.accountType,
    required this.status,
    required this.capabilities,
    required this.scopes,
    required this.connectedAt,
    this.lastValidatedAt,
    this.lastSyncAt,
    required this.reauthRequired,
    this.metadata = const {},
    this.credential,
  });

  Map<String, dynamic> toJson() {
    return {
      'externalAccountId': externalAccountId,
      'platformId': platformId,
      'connectorId': connectorId,
      'displayName': displayName,
      'username': username,
      'accountType': accountType,
      'status': status,
      'capabilities': capabilities.map((c) => c.toString().split('.').last).toList(),
      'scopes': scopes,
      'connectedAt': connectedAt.toIso8601String(),
      'lastValidatedAt': lastValidatedAt?.toIso8601String(),
      'lastSyncAt': lastSyncAt?.toIso8601String(),
      'reauthRequired': reauthRequired,
      'metadata': metadata,
      // Credential explicitly omitted to prevent secret leakage
    };
  }

  factory ConnectedAccount.fromJson(Map<String, dynamic> json) {
    return ConnectedAccount(
      externalAccountId: json['externalAccountId'],
      platformId: json['platformId'],
      connectorId: json['connectorId'],
      displayName: json['displayName'],
      username: json['username'],
      accountType: json['accountType'],
      status: json['status'],
      capabilities: (json['capabilities'] as List).map((c) => PlatformCapability.values.firstWhere((e) => e.toString().split('.').last == c)).toList(),
      scopes: List<String>.from(json['scopes'] ?? []),
      connectedAt: DateTime.parse(json['connectedAt']),
      lastValidatedAt: json['lastValidatedAt'] != null ? DateTime.parse(json['lastValidatedAt']) : null,
      lastSyncAt: json['lastSyncAt'] != null ? DateTime.parse(json['lastSyncAt']) : null,
      reauthRequired: json['reauthRequired'] ?? false,
      metadata: json['metadata'] ?? {},
      credential: null,
    );
  }
}

class Webhook {
  final String id;
  final String platform;
  final String eventType;
  final Map<String, dynamic> payload;

  const Webhook({
    required this.id,
    required this.platform,
    required this.eventType,
    required this.payload,
  });
}

class SyncJob {
  final String jobId;
  final String accountId;
  final DateTime startedAt;
  final String status;

  const SyncJob({
    required this.jobId,
    required this.accountId,
    required this.startedAt,
    required this.status,
  });
}

class PublishJob {
  final String jobId;
  final String targetPlatform;
  final String status;

  const PublishJob({
    required this.jobId,
    required this.targetPlatform,
    required this.status,
  });
}

class ExternalObject {
  final String externalId;
  final String platform;
  final String type; // e.g. video, photo, story
  final Map<String, dynamic> data;

  const ExternalObject({
    required this.externalId,
    required this.platform,
    required this.type,
    required this.data,
  });
}

class ExternalMessage {
  final String messageId;
  final String senderId;
  final String text;
  final DateTime timestamp;

  const ExternalMessage({
    required this.messageId,
    required this.senderId,
    required this.text,
    required this.timestamp,
  });
}

class ExternalComment {
  final String commentId;
  final String authorName;
  final String text;
  final String parentObjectId;

  const ExternalComment({
    required this.commentId,
    required this.authorName,
    required this.text,
    required this.parentObjectId,
  });
}
