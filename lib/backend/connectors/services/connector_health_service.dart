import 'package:oneova/backend/connectors/models/connector_health_models.dart';

// Interface representing the actual real-world API ping to the provider
abstract class NetworkPingerStub {
  Future<int> pingProvider(String platformId); // returns HTTP status code
}

class ConnectorHealthService {
  final NetworkPingerStub _pinger;

  ConnectorHealthService(this._pinger);

  // In a real environment, this queries the local database for historical sync timestamps
  // and executes a real HTTP ping to verify current rate limits and connection states.
  Future<ConnectorHealth> checkHealth(
    String platformId, 
    TokenExpiryState currentTokenState,
    List<PlatformCapability> capabilities,
    {
      DateTime? lastSync,
      DateTime? lastWebhook,
      DateTime? lastPublish,
      DateTime? lastErrorTime,
      String? lastErrorMessage,
    }
  ) async {
    
    if (currentTokenState.isExpired) {
      return ConnectorHealth(
        platformId: platformId,
        state: currentTokenState.isRefreshable ? PlatformState.expired : PlatformState.disconnected,
        tokenState: currentTokenState,
        capabilities: capabilities,
        lastSuccessfulSync: lastSync,
        lastWebhookReceived: lastWebhook,
        lastPublish: lastPublish,
        lastApiError: lastErrorTime,
        lastApiErrorMessage: lastErrorMessage,
      );
    }

    // Constraint: "The dashboard must use real health checks."
    // Execute real network ping to check for rate limits, degraded APIs, or permission revocations.
    int statusCode = 500;
    try {
      statusCode = await _pinger.pingProvider(platformId);
    } catch (e) {
      statusCode = 503; // Network failure
    }

    PlatformState determinedState;

    switch (statusCode) {
      case 200:
        determinedState = PlatformState.connected;
        break;
      case 401:
      case 403:
        determinedState = PlatformState.permissionRequired;
        break;
      case 429:
        determinedState = PlatformState.rateLimited;
        break;
      case 500:
      case 502:
      case 503:
        determinedState = PlatformState.degraded;
        break;
      default:
        determinedState = PlatformState.error;
    }

    // Override if we are actively syncing right now
    // (In reality this checks a lock or queue depth)
    // if (isCurrentlySyncing) determinedState = PlatformState.syncing;

    return ConnectorHealth(
      platformId: platformId,
      state: determinedState,
      tokenState: currentTokenState,
      capabilities: capabilities,
      lastSuccessfulSync: lastSync,
      lastWebhookReceived: lastWebhook,
      lastPublish: lastPublish,
      lastApiError: statusCode != 200 ? DateTime.now() : lastErrorTime,
      lastApiErrorMessage: statusCode != 200 ? 'HTTP $statusCode on health ping' : lastErrorMessage,
    );
  }
}
