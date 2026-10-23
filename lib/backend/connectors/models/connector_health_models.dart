enum PlatformState {
  connected,
  disconnected,
  expired,
  permissionRequired, // Requires user to re-authorize specific scopes
  rateLimited,
  syncing,
  degraded,
  error,
}

enum PlatformCapability {
  readInbox,
  publishContent,
  readAnalytics,
  manageComments,
  realtimeWebhooks,
}

class TokenExpiryState {
  final bool isExpired;
  final DateTime? expiresAt;
  final bool isRefreshable;

  const TokenExpiryState({
    required this.isExpired,
    this.expiresAt,
    required this.isRefreshable,
  });
}

class ConnectorHealth {
  final String platformId; // e.g. 'youtube', 'x', 'tiktok'
  final PlatformState state;
  
  final DateTime? lastSuccessfulSync;
  final DateTime? lastWebhookReceived;
  final DateTime? lastPublish;
  final DateTime? lastApiError;
  final String? lastApiErrorMessage;
  
  final TokenExpiryState tokenState;
  final List<PlatformCapability> capabilities;

  const ConnectorHealth({
    required this.platformId,
    required this.state,
    this.lastSuccessfulSync,
    this.lastWebhookReceived,
    this.lastPublish,
    this.lastApiError,
    this.lastApiErrorMessage,
    required this.tokenState,
    required this.capabilities,
  });
}
