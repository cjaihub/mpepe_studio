import 'package:oneova/backend/connectors/core/platform_connector.dart';
import 'package:oneova/backend/connectors/models/connector_models.dart';

/// Base class for Meta properties containing shared token logic
abstract class MetaBaseConnector extends PlatformConnector {
  MetaBaseConnector(super.platformName);

  @override
  Future<void> connect() async {
    // Shared Meta OAuth connect logic
    await Future.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<Credential> refreshCredentials(Credential current) async {
    // Shared Meta long-lived token exchange
    if (DateTime.now().isAfter(current.expiresAt)) {
      await Future.delayed(const Duration(milliseconds: 300));
      return Credential(
        accessToken: '${current.accessToken}_refreshed',
        expiresAt: DateTime.now().add(const Duration(days: 60)), // Meta's 60-day token
        metadata: current.metadata,
      );
    }
    return current;
  }

  @override
  Future<void> handleWebhook(Webhook webhook) async {
    requireCapability(PlatformCapability.webhooks);
    // Generic signature validation using APP_SECRET
  }

  @override
  Future<void> disconnect(ConnectedAccount account) async {
    // Revoke token via Graph API
  }
}

class FacebookConnector extends MetaBaseConnector {
  FacebookConnector() : super('Facebook');

  @override
  Future<ConnectedAccount> authorize(Map<String, dynamic> authPayload) async {
    // Validates Graph API user token & requests Page Access Token if applicable.
    final scopes = List<String>.from(authPayload['granted_scopes'] ?? []);
    
    return ConnectedAccount(
      externalAccountId: authPayload['page_id'] ?? 'fb_page_1',
      platformId: platformName,
      connectorId: 'facebook_core',
      displayName: authPayload['page_name'] ?? 'Facebook Page',
      status: 'VERIFIED',
      capabilities: getCapabilities(),
      scopes: scopes,
      connectedAt: DateTime.now(),
      reauthRequired: false,
      credential: Credential(
        accessToken: authPayload['access_token'] ?? 'fb_token',
        expiresAt: DateTime.now().add(const Duration(days: 60)),
        metadata: {
          'granted_scopes': scopes,
          'is_page': authPayload['is_page'] ?? true,
        },
      ),
    );
  }

  @override
  List<PlatformCapability> getCapabilities() {
    // Facebook Pages support publishing, reading/replying to comments, live, analytics
    // Note: Messaging is explicitly handled via Messenger API (MessengerConnector).
    return [
      PlatformCapability.contentPublish,
      PlatformCapability.contentRead,
      PlatformCapability.commentsRead,
      PlatformCapability.commentsReply,
      PlatformCapability.analytics,
      PlatformCapability.live,
      PlatformCapability.mediaUpload,
      PlatformCapability.webhooks,
    ];
  }

  @override
  Future<PublishJob> publish(ConnectedAccount account, ExternalObject object) async {
    requireCapability(PlatformCapability.contentPublish);
    await Future.delayed(const Duration(milliseconds: 200));
    return PublishJob(jobId: 'fb_pub_1', targetPlatform: platformName, status: 'published');
  }

  @override
  Future<String> getStatus(ConnectedAccount account) async => 'ACTIVE';
}

class InstagramConnector extends MetaBaseConnector {
  InstagramConnector() : super('Instagram');

  @override
  Future<ConnectedAccount> authorize(Map<String, dynamic> authPayload) async {
    // Must map Facebook Page -> IG Professional Account ID
    final igAccountId = authPayload['ig_account_id'];
    if (igAccountId == null) {
      throw Exception('Instagram Professional Account not linked to Facebook Page.');
    }
    
    return ConnectedAccount(
      externalAccountId: igAccountId,
      platformId: platformName,
      connectorId: 'instagram_core',
      displayName: authPayload['username'] ?? 'IG Creator',
      status: 'VERIFIED',
      capabilities: getCapabilities(),
      scopes: const ['instagram_basic', 'instagram_manage_messages'], // mock scopes
      connectedAt: DateTime.now(),
      reauthRequired: false,
      credential: Credential(
        accessToken: authPayload['access_token'] ?? 'ig_token',
        expiresAt: DateTime.now().add(const Duration(days: 60)),
        metadata: {
          'fb_page_id': authPayload['fb_page_id'],
        },
      ),
    );
  }

  @override
  List<PlatformCapability> getCapabilities() {
    // Instagram Graph API capabilities (Professional/Creator accounts)
    return [
      PlatformCapability.contentPublish,
      PlatformCapability.contentRead,
      PlatformCapability.commentsRead,
      PlatformCapability.commentsReply,
      PlatformCapability.messagesRead, // IG Direct
      PlatformCapability.messagesSend, // IG Direct
      PlatformCapability.stories,
      PlatformCapability.analytics,
      PlatformCapability.mediaUpload,
      PlatformCapability.webhooks,
    ];
  }

  @override
  Future<ExternalMessage> sendMessage(ConnectedAccount account, String recipientId, String text) async {
    requireCapability(PlatformCapability.messagesSend);
    await Future.delayed(const Duration(milliseconds: 200));
    return ExternalMessage(messageId: 'ig_msg_1', senderId: account.externalAccountId, text: text, timestamp: DateTime.now());
  }

  @override
  Future<PublishJob> publish(ConnectedAccount account, ExternalObject object) async {
    requireCapability(PlatformCapability.contentPublish);
    await Future.delayed(const Duration(milliseconds: 200));
    return PublishJob(jobId: 'ig_pub_1', targetPlatform: platformName, status: 'published');
  }

  @override
  Future<String> getStatus(ConnectedAccount account) async => 'ACTIVE';
}

class MessengerConnector extends MetaBaseConnector {
  MessengerConnector() : super('Messenger');

  @override
  Future<ConnectedAccount> authorize(Map<String, dynamic> authPayload) async {
    // Requires pages_messaging scope on the Page Access Token
    final scopes = List<String>.from(authPayload['granted_scopes'] ?? []);
    if (!scopes.contains('pages_messaging')) {
      throw Exception('Missing pages_messaging scope for Messenger access.');
    }

    return ConnectedAccount(
      externalAccountId: authPayload['page_id'] ?? 'msg_page_1',
      platformId: platformName,
      connectorId: 'messenger_core',
      displayName: authPayload['page_name'] ?? 'Messenger Bot',
      status: 'VERIFIED',
      capabilities: getCapabilities(),
      scopes: scopes,
      connectedAt: DateTime.now(),
      reauthRequired: false,
      metadata: {
        'avatar_url': authPayload['avatar_url'] ?? '',
      },
      credential: Credential(
        accessToken: authPayload['access_token'] ?? 'msg_token',
        expiresAt: DateTime.now().add(const Duration(days: 60)),
      ),
    );
  }

  @override
  List<PlatformCapability> getCapabilities() {
    // Messenger is strictly for 1-1 messaging, handovers, templates
    // NO feed publishing, NO comments.
    return [
      PlatformCapability.messagesRead,
      PlatformCapability.messagesSend,
      PlatformCapability.webhooks,
      PlatformCapability.mediaUpload, // Sending attachments in messages
    ];
  }

  @override
  Future<ExternalMessage> sendMessage(ConnectedAccount account, String recipientId, String text) async {
    requireCapability(PlatformCapability.messagesSend);
    // Sends via the Send API
    await Future.delayed(const Duration(milliseconds: 150));
    return ExternalMessage(messageId: 'msg_msg_1', senderId: account.externalAccountId, text: text, timestamp: DateTime.now());
  }

  @override
  Future<String> getStatus(ConnectedAccount account) async => 'ACTIVE';
}
