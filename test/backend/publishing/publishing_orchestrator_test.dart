import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/publishing/models/publishing_job_models.dart';
import 'package:oneova/backend/publishing/services/publishing_orchestrator.dart';
import 'package:oneova/backend/connectors/models/connector_models.dart';
import 'package:oneova/backend/connectors/core/platform_connector.dart';

// Fake Connectors
class FakeSuccessConnector extends PlatformConnector {
  FakeSuccessConnector(super.name);
  @override Future<void> connect() async {}
  @override Future<ConnectedAccount> authorize(Map<String, dynamic> a) async => throw UnimplementedError();
  @override Future<Credential> refreshCredentials(Credential c) async => throw UnimplementedError();
  @override List<PlatformCapability> getCapabilities() => [PlatformCapability.contentPublish];
  @override Future<String> getStatus(ConnectedAccount a) async => 'OK';
  @override Future<void> handleWebhook(Webhook w) async {}
  @override Future<void> disconnect(ConnectedAccount a) async {}

  @override
  Future<PublishJob> publish(ConnectedAccount account, ExternalObject object) async {
    requireCapability(PlatformCapability.contentPublish);
    return PublishJob(jobId: '123', targetPlatform: platformName, status: 'published');
  }
}

class FakeFailureConnector extends FakeSuccessConnector {
  FakeFailureConnector(super.name);

  @override
  Future<PublishJob> publish(ConnectedAccount account, ExternalObject object) async {
    throw Exception('Simulated API Outage');
  }
}

void main() {
  late PublishingOrchestrator orchestrator;

  setUp(() {
    orchestrator = PublishingOrchestrator(connectors: {
      'Instagram': FakeSuccessConnector('Instagram'),
      'Facebook': FakeSuccessConnector('Facebook'),
      'TikTok': FakeFailureConnector('TikTok'),
      'YouTube': FakeSuccessConnector('YouTube'),
    });
  });

  test('Yields PARTIAL status if TikTok fails but others succeed', () async {
    final targets = [
      _mockAccount('Instagram', 'ig_1'),
      _mockAccount('Facebook', 'fb_1'),
      _mockAccount('TikTok', 'tk_1'),
      _mockAccount('YouTube', 'yt_1'),
    ];

    final job = await orchestrator.orchestratePublish('content_1', targets, {});

    // Ensure it does NOT report PUBLISHED if any failed.
    expect(job.masterStatus, OrchestrationStatus.partial);

    expect(job.destinations.firstWhere((d) => d.platform == 'Instagram').status, DestinationStatus.published);
    expect(job.destinations.firstWhere((d) => d.platform == 'TikTok').status, DestinationStatus.failed);
  });

  test('Retry individual failed destination correctly updates master status', () async {
    final targets = [
      _mockAccount('YouTube', 'yt_1'),
      _mockAccount('TikTok', 'tk_1'), // Will fail
    ];

    final job = await orchestrator.orchestratePublish('content_1', targets, {});
    expect(job.masterStatus, OrchestrationStatus.partial);

    final failedTkJob = job.destinations.firstWhere((d) => d.platform == 'TikTok');

    // Hot-swap TikTok to the successful connector to simulate the API recovering
    orchestrator.connectors['TikTok'] = FakeSuccessConnector('TikTok');

    await orchestrator.retryDestination(job, failedTkJob.id, targets[1], {});

    // After retry succeeds, the master status should upgrade to published.
    expect(failedTkJob.status, DestinationStatus.published);
    expect(job.masterStatus, OrchestrationStatus.published);
  });
}
ConnectedAccount _mockAccount(String platform, String id) {
  return ConnectedAccount(
    externalAccountId: id,
    platformId: platform,
    connectorId: '${platform.toLowerCase()}_core',
    displayName: 'test',
    status: 'VERIFIED',
    capabilities: [],
    scopes: [],
    connectedAt: DateTime.now(),
    reauthRequired: false,
    credential: Credential(accessToken: 'token', expiresAt: DateTime.now().add(const Duration(days: 1))),
  );
}
