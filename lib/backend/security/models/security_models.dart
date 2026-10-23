enum SecurityEventType {
  loginSuccess,
  loginFailed,
  passwordChanged,
  passkeyAdded,
  tokenIssued,
  sessionRevoked,
}

class DeviceSession {
  final String id;
  final String deviceName;
  final String osVersion;
  final String ipAddress;
  final DateTime lastActive;
  bool isRevoked;

  DeviceSession({
    required this.id,
    required this.deviceName,
    required this.osVersion,
    required this.ipAddress,
    required this.lastActive,
    this.isRevoked = false,
  });
}

class ConnectedAccount {
  final String providerId; // e.g. 'google', 'apple'
  final String identifier; // e.g. masked email 'j***@gmail.com'
  final DateTime linkedAt;

  const ConnectedAccount({
    required this.providerId,
    required this.identifier,
    required this.linkedAt,
  });
}

class ApiToken {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime? lastUsed;
  
  // CRITICAL CONSTRAINT: Never display secrets.
  // The actual secret is generated once and returned, never stored here in plaintext.
  // Only store the trailing 4 characters for identification.
  final String trailingChars; 

  const ApiToken({
    required this.id,
    required this.name,
    required this.createdAt,
    this.lastUsed,
    required this.trailingChars,
  });
}

class SecurityEvent {
  final String id;
  final SecurityEventType eventType;
  final DateTime timestamp;
  final String ipAddress;
  final String location; // Approximate City/Country

  const SecurityEvent({
    required this.id,
    required this.eventType,
    required this.timestamp,
    required this.ipAddress,
    required this.location,
  });
}

class SecurityCenterSnapshot {
  final String userId;
  final List<DeviceSession> activeSessions;
  final List<ConnectedAccount> connectedAccounts;
  final List<ApiToken> apiTokens;
  final List<SecurityEvent> recentEvents;

  const SecurityCenterSnapshot({
    required this.userId,
    required this.activeSessions,
    required this.connectedAccounts,
    required this.apiTokens,
    required this.recentEvents,
  });
}
