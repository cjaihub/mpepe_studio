import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/connectors/models/connector_models.dart';
import 'package:oneova/backend/connectors/implementations/tiktok_connector.dart';

void main() {
  late TikTokConnector tk;

  setUp(() {
    tk = TikTokConnector();
  });

  test('Authorizes successfully when video.upload scope present', () async {
    final account = await tk.authorize({
      'open_id': 'tk_123',
      'scopes': ['video.upload', 'user.info.basic'],
    });
    
    expect(account.externalAccountId, 'tk_123');
  });

  test('Throws if video.upload scope is missing', () async {
    expect(
      () => tk.authorize({
        'open_id': 'tk_123',
        'scopes': ['user.info.basic'], // missing video.upload
      }),
      throwsA(isA<Exception>()),
    );
  });

  test('Throws if explicit consent is missing during publish', () async {
    final account = await tk.authorize({
      'open_id': 'tk_123',
      'scopes': ['video.upload'],
    });

    expect(
      () => tk.publish(
        account,
        const ExternalObject(externalId: 'ext', platform: 'TikTok', type: 'video', data: {
          'explicit_consent': false, // No consent
        }),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('Returns PENDING_AUDIT status for successful publish pipeline', () async {
    final account = await tk.authorize({
      'open_id': 'tk_123',
      'scopes': ['video.upload'],
    });

    final job = await tk.publish(
      account,
      ExternalObject(externalId: 'ext', platform: 'TikTok', type: 'video', data: {
        'explicit_consent': true,
        'tiktok_privacy': TikTokPrivacySettings(privacyLevel: 'public'),
      }),
    );
    
    expect(job.status, 'PENDING_AUDIT');
  });
}
