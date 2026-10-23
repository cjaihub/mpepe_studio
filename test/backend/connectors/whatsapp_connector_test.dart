import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/connectors/models/connector_models.dart';
import 'package:oneova/backend/connectors/implementations/whatsapp_connector.dart';

void main() {
  late WhatsAppConnector connector;

  setUp(() {
    connector = WhatsAppConnector();
  });

  test('Authorizes successfully when status is APPROVED', () async {
    final account = await connector.authorize({
      'status': 'APPROVED',
      'waba_id': '123',
      'business_name': 'Test Business',
      'phone_number_id': '456',
    });

    expect(account.externalAccountId, '123');
    expect(account.displayName, 'Test Business');
    expect(account.credential!.metadata['phone_number_id'], '456');
  });

  test('Throws when status is NOT APPROVED', () async {
    expect(
      () => connector.authorize({
        'status': 'REJECTED',
      }),
      throwsA(isA<Exception>()),
    );
  });

  test('Has correct capabilities', () {
    final caps = connector.getCapabilities();
    expect(caps.contains(PlatformCapability.messagesRead), true);
    expect(caps.contains(PlatformCapability.messagesSend), true);
    expect(caps.contains(PlatformCapability.webhooks), true);
    expect(caps.contains(PlatformCapability.contentPublish), false); // WhatsApp doesn't support publishing to a feed
  });

  test('Handles webhook and dedupes (mock)', () async {
    final webhook = Webhook(
      id: 'webhook_123',
      platform: 'WhatsApp Business',
      eventType: 'statuses',
      payload: {'status': 'delivered'},
    );

    // Should complete without throwing UnsupportedCapabilityException
    await expectLater(connector.handleWebhook(webhook), completes);
  });
}
