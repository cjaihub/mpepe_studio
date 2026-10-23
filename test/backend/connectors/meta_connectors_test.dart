import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/connectors/models/connector_models.dart';
import 'package:oneova/backend/connectors/core/platform_connector.dart';
import 'package:oneova/backend/connectors/implementations/meta_connectors.dart';

void main() {
  group('FacebookConnector', () {
    late FacebookConnector fb;

    setUp(() {
      fb = FacebookConnector();
    });

    test('Authorizes successfully', () async {
      final account = await fb.authorize({
        'page_id': 'fb_1',
        'access_token': 'token123',
        'granted_scopes': ['pages_manage_posts'],
      });
      expect(account.externalAccountId, 'fb_1');
      expect(account.credential!.accessToken, 'token123');
    });

    test('Refuses to send messages', () async {
      final account = await fb.authorize({'page_id': 'fb_1'});
      expect(
        () => fb.sendMessage(account, 'user_a', 'hello'),
        throwsA(isA<UnsupportedCapabilityException>()),
      );
    });

    test('Allows publishing', () async {
      final account = await fb.authorize({'page_id': 'fb_1'});
      final job = await fb.publish(
        account,
        const ExternalObject(externalId: 'ext_1', platform: 'Facebook', type: 'post', data: {}),
      );
      expect(job.status, 'published');
    });
  });

  group('InstagramConnector', () {
    late InstagramConnector ig;

    setUp(() {
      ig = InstagramConnector();
    });

    test('Throws if IG Professional Account ID is missing', () async {
      expect(
        () => ig.authorize({
          'access_token': 'token123',
          // Missing ig_account_id
        }),
        throwsA(isA<Exception>()),
      );
    });

    test('Allows messaging via IG Direct', () async {
      final account = await ig.authorize({
        'ig_account_id': 'ig_1',
        'access_token': 'token123',
      });
      
      final msg = await ig.sendMessage(account, 'user_a', 'hello IG');
      expect(msg.messageId, 'ig_msg_1');
    });
  });

  group('MessengerConnector', () {
    late MessengerConnector msg;

    setUp(() {
      msg = MessengerConnector();
    });

    test('Throws if pages_messaging scope is missing', () async {
      expect(
        () => msg.authorize({
          'page_id': 'fb_1',
          'granted_scopes': ['pages_read_engagement'], // Missing pages_messaging
        }),
        throwsA(isA<Exception>()),
      );
    });

    test('Refuses to publish content to feed', () async {
      final account = await msg.authorize({
        'page_id': 'fb_1',
        'granted_scopes': ['pages_messaging'],
      });
      
      expect(
        () => msg.publish(account, const ExternalObject(externalId: 'ext', platform: 'Messenger', type: 'post', data: {})),
        throwsA(isA<UnsupportedCapabilityException>()),
      );
    });
  });
}
