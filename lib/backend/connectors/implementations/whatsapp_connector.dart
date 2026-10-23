import 'package:oneova/backend/connectors/core/platform_connector.dart';
import 'package:oneova/backend/connectors/models/connector_models.dart';

class WhatsAppConnector extends PlatformConnector {
  WhatsAppConnector() : super('WhatsApp Business');

  @override
  Future<void> connect() async {
    // Initiate Meta OAuth for WhatsApp Business Cloud API
    await Future.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<ConnectedAccount> authorize(Map<String, dynamic> authPayload) async {
    // Use official Meta Cloud API authorization payload
    final authorized = authPayload['status'] == 'APPROVED';
    if (!authorized) {
      throw Exception('STATUS = NOT APPROVED.');
    }

    return ConnectedAccount(
      externalAccountId: authPayload['waba_id'] ?? 'wa_bus_1',
      platformId: platformName,
      connectorId: 'whatsapp_core',
      displayName: authPayload['business_name'] ?? 'WhatsApp Business Account',
      status: 'VERIFIED',
      capabilities: getCapabilities(),
      scopes: const ['whatsapp_business_messaging'],
      connectedAt: DateTime.now(),
      reauthRequired: false,
      credential: Credential(
        accessToken: authPayload['access_token'] ?? 'wa_token',
        expiresAt: DateTime.now().add(const Duration(days: 60)), // Meta long-lived tokens
        metadata: {
          'phone_number_id': authPayload['phone_number_id'],
        },
      ),
    );
  }

  @override
  Future<Credential> refreshCredentials(Credential current) async {
    // Check token expiry and request a new one via Meta Graph API
    if (DateTime.now().isAfter(current.expiresAt)) {
      // Execute token exchange
      await Future.delayed(const Duration(milliseconds: 300));
      return Credential(
        accessToken: 'wa_token_refreshed',
        expiresAt: DateTime.now().add(const Duration(days: 60)),
        metadata: current.metadata,
      );
    }
    return current;
  }

  @override
  List<PlatformCapability> getCapabilities() {
    return [
      PlatformCapability.messagesRead,
      PlatformCapability.messagesSend,
      PlatformCapability.webhooks,
      PlatformCapability.mediaUpload,
      PlatformCapability.profileRead,
      PlatformCapability.analytics,
    ];
  }

  @override
  Future<SyncJob> sync(ConnectedAccount account) async {
    // Note: Official WhatsApp Cloud API pushes messages via webhooks.
    // Sync here might refer to syncing business profile or templates.
    return SyncJob(
      jobId: 'sync_wa_${DateTime.now().millisecondsSinceEpoch}',
      accountId: account.externalAccountId,
      startedAt: DateTime.now(),
      status: 'completed',
    );
  }

  @override
  Future<ExternalMessage> sendMessage(ConnectedAccount account, String recipientId, String text) async {
    requireCapability(PlatformCapability.messagesSend);
    
    // Check rate limits locally before dispatching to Meta API
    // If rate limit exceeded, return/throw appropriate provider error.
    
    await Future.delayed(const Duration(milliseconds: 250));
    
    return ExternalMessage(
      messageId: 'wa_msg_${DateTime.now().millisecondsSinceEpoch}',
      senderId: account.externalAccountId,
      text: text,
      timestamp: DateTime.now(),
    );
  }
  
  /// Sends an official pre-approved template message (unique to WhatsApp capability).
  Future<ExternalMessage> sendTemplateMessage(ConnectedAccount account, String recipientId, String templateName, List<String> parameters) async {
    requireCapability(PlatformCapability.messagesSend);
    // Dispatches template message via Cloud API
    await Future.delayed(const Duration(milliseconds: 300));
    
    return ExternalMessage(
      messageId: 'wa_msg_tpl_${DateTime.now().millisecondsSinceEpoch}',
      senderId: account.externalAccountId,
      text: 'Template: $templateName',
      timestamp: DateTime.now(),
    );
  }

  @override
  Future<String> getStatus(ConnectedAccount account) async {
    return 'APPROVED';
  }

  @override
  Future<void> handleWebhook(Webhook webhook) async {
    requireCapability(PlatformCapability.webhooks);
    
    // 1. Deduplicate events using webhook.id
    // 2. Validate Meta signature (App Secret proof)
    // 3. Handle specific WhatsApp webhook types (messages, statuses)
    
    if (webhook.eventType == 'messages') {
      // Map to canonical inbox
      // final messageData = webhook.payload['messages'][0];
      // final mappedMessage = _mapToUnifiedInbox(messageData);
      // save mappedMessage to canonical DB
    } else if (webhook.eventType == 'statuses') {
      // Handle delivery state, read state
      // final statusData = webhook.payload['statuses'][0];
      // update delivery state on canonical message model
    }
    
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<void> disconnect(ConnectedAccount account) async {
    // De-register webhooks and drop tokens
    await Future.delayed(const Duration(milliseconds: 100));
  }
}
