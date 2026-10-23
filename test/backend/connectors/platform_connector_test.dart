import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/connectors/models/connector_models.dart';
import 'package:oneova/backend/connectors/core/platform_connector.dart';

class StubMockYouTubeConnector extends PlatformConnector {
  StubMockYouTubeConnector() : super('YouTube');

  @override
  Future<void> connect() async {}

  @override
  Future<ConnectedAccount> authorize(Map<String, dynamic> authPayload) async {
    return ConnectedAccount(
      externalAccountId: 'yt_1',
      platformId: 'YouTube',
      connectorId: 'stub',
      displayName: 'My Channel',
      status: 'VERIFIED',
      capabilities: getCapabilities(),
      scopes: [],
      connectedAt: DateTime.now(),
      reauthRequired: false,
      credential: Credential(accessToken: 'token', expiresAt: DateTime.now()),
    );
  }

  @override
  Future<Credential> refreshCredentials(Credential current) async {
    return current;
  }

  @override
  List<PlatformCapability> getCapabilities() {
    // YouTube supports publishing and comments read, but NOT messages send.
    return [
      PlatformCapability.contentPublish,
      PlatformCapability.commentsRead,
      PlatformCapability.analytics,
    ];
  }

  @override
  Future<PublishJob> publish(ConnectedAccount account, ExternalObject object) async {
    super.requireCapability(PlatformCapability.contentPublish);
    return PublishJob(jobId: 'pub_1', targetPlatform: platformName, status: 'completed');
  }

  @override
  Future<ExternalMessage> sendMessage(ConnectedAccount account, String recipientId, String text) async {
    // This calls requireCapability under the hood in the base class, or we can call it explicitly here.
    super.requireCapability(PlatformCapability.messagesSend);
    return ExternalMessage(messageId: '1', senderId: 'me', text: text, timestamp: DateTime.now());
  }

  @override
  Future<String> getStatus(ConnectedAccount account) async {
    return 'ok';
  }

  @override
  Future<void> disconnect(ConnectedAccount account) async {}
}

void main() {
  test('Connector enforces capabilities strictly', () async {
    final yt = StubMockYouTubeConnector();
    final account = await yt.authorize({});

    // Should succeed because contentPublish is supported
    final job = await yt.publish(
      account,
      const ExternalObject(externalId: 'v1', platform: 'YouTube', type: 'video', data: {}),
    );
    expect(job.status, 'completed');

    // Should fail because messagesSend is NOT supported by YouTube
    expect(
      () => yt.sendMessage(account, 'user_b', 'hello'),
      throwsA(isA<UnsupportedCapabilityException>()),
    );
  });
}
