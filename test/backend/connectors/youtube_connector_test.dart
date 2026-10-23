import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/connectors/models/connector_models.dart';
import 'package:oneova/backend/connectors/implementations/youtube_connector.dart';
import 'package:oneova/backend/connectors/core/platform_connector.dart';

void main() {
  late YouTubeConnector yt;

  setUp(() {
    yt = YouTubeConnector();
  });

  test('Authorizes successfully when minimum scopes present', () async {
    final account = await yt.authorize({
      'channel_id': 'UC123',
      'scopes': ['https://www.googleapis.com/auth/youtube.readonly'],
    });
    
    expect(account.externalAccountId, 'UC123');
  });
  
  test('Throws if minimum read scope is missing', () async {
    expect(
      () => yt.authorize({
        'channel_id': 'UC123',
        'scopes': ['https://www.googleapis.com/auth/youtube.upload'], // missing readonly
      }),
      throwsA(isA<Exception>()),
    );
  });

  test('Requires refresh_token to refresh short-lived token', () async {
    final account = await yt.authorize({
      'channel_id': 'UC123',
      'scopes': ['https://www.googleapis.com/auth/youtube.readonly'],
      // Notice refresh_token is missing
    });

    // Manually expire token
    final expiredCredential = Credential(
      accessToken: 'old_token',
      expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
      metadata: account.credential!.metadata,
    );

    expect(
      () => yt.refreshCredentials(expiredCredential),
      throwsA(isA<Exception>()),
    );
  });

  test('Publishes correctly with correct scopes', () async {
    final account = await yt.authorize({
      'channel_id': 'UC123',
      'scopes': [
        'https://www.googleapis.com/auth/youtube.readonly',
        'https://www.googleapis.com/auth/youtube.upload'
      ],
    });

    final job = await yt.publish(
      account,
      const ExternalObject(externalId: 'ext', platform: 'YouTube', type: 'video', data: {}),
    );
    expect(job.status, 'published');
  });

  test('Publication fails without upload scope', () async {
    final account = await yt.authorize({
      'channel_id': 'UC123',
      'scopes': ['https://www.googleapis.com/auth/youtube.readonly'], // No upload scope
    });

    expect(
      () => yt.publish(
        account,
        const ExternalObject(externalId: 'ext', platform: 'YouTube', type: 'video', data: {}),
      ),
      throwsA(isA<Exception>()),
    );
  });
  
  test('Throws UnsupportedCapabilityException for messaging', () async {
    final account = await yt.authorize({
      'channel_id': 'UC123',
      'scopes': ['https://www.googleapis.com/auth/youtube.readonly'],
    });

    expect(
      () => yt.sendMessage(account, 'user_b', 'hello'),
      throwsA(isA<UnsupportedCapabilityException>()),
    );
  });
}
