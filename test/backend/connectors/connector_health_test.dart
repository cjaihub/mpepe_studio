import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/connectors/models/connector_health_models.dart';
import 'package:oneova/backend/connectors/services/connector_health_service.dart';

// Mock Network Pinger
class MockNetworkPinger implements NetworkPingerStub {
  int mockStatusCode = 200;

  @override
  Future<int> pingProvider(String platformId) async {
    return mockStatusCode;
  }
}

void main() {
  late ConnectorHealthService service;
  late MockNetworkPinger pinger;

  setUp(() {
    pinger = MockNetworkPinger();
    service = ConnectorHealthService(pinger);
  });

  test('Valid token + 200 ping returns Connected', () async {
    final health = await service.checkHealth(
      'youtube',
      const TokenExpiryState(isExpired: false, isRefreshable: true),
      [PlatformCapability.publishContent, PlatformCapability.readAnalytics],
    );

    expect(health.state, PlatformState.connected);
    expect(health.lastApiErrorMessage, null);
  });

  test('Expired token short-circuits network ping and returns Expired', () async {
    // Even if pinger returns 200, the token state should block it
    pinger.mockStatusCode = 200;

    final health = await service.checkHealth(
      'x',
      const TokenExpiryState(isExpired: true, isRefreshable: true),
      [],
    );

    expect(health.state, PlatformState.expired);
  });

  test('429 network response maps to Rate Limited', () async {
    pinger.mockStatusCode = 429;

    final health = await service.checkHealth(
      'tiktok',
      const TokenExpiryState(isExpired: false, isRefreshable: true),
      [],
    );

    expect(health.state, PlatformState.rateLimited);
    expect(health.lastApiErrorMessage, 'HTTP 429 on health ping');
  });

  test('401/403 network response maps to Permission Required', () async {
    pinger.mockStatusCode = 403;

    final health = await service.checkHealth(
      'instagram',
      const TokenExpiryState(isExpired: false, isRefreshable: true),
      [],
    );

    expect(health.state, PlatformState.permissionRequired);
  });

  test('500+ network responses map to Degraded', () async {
    pinger.mockStatusCode = 502;

    final health = await service.checkHealth(
      'linkedin',
      const TokenExpiryState(isExpired: false, isRefreshable: true),
      [],
    );

    expect(health.state, PlatformState.degraded);
  });
}
