import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../models/conversation_model.dart';
import '../models/message_model.dart';

/// Handles normalization of external payloads to canonical models.
class NormalizationService {
  
  /// Generates a globally unique identifier for external messages.
  /// Format: `<platform>_<externalAccountId>_<externalMessageId>`
  static String generateExternalIdentity({
    required String platform,
    required String externalAccountId,
    required String externalMessageId,
  }) {
    final raw = '${platform}_${externalAccountId}_$externalMessageId';
    // Using a hash prevents overly long IDs or invalid characters in Firestore keys
    final bytes = utf8.encode(raw);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Normalizes an incoming Webhook or external payload into a Canonical Conversation.
  static Conversation normalizeConversation({
    required String internalId,
    required String platform,
    required String externalAccountId,
    required String externalConversationId,
    required Map<String, dynamic> rawPayload,
    required List<String> currentParticipants,
    String? title,
  }) {
    return Conversation(
      id: internalId,
      channel: _parsePlatform(platform),
      participants: currentParticipants,
      unreadCount: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      connectorId: platform,
      externalAccountId: externalAccountId,
      externalConversationId: externalConversationId,
      priority: 'normal',
      needsReply: true,
      status: 'active',
      syncState: 'synced',
      metadata: rawPayload,
      source: 'webhook',
    );
  }

  /// Normalizes an incoming Webhook or external payload into a Canonical Message.
  static InboxMessage normalizeMessage({
    required String internalMessageId,
    required String conversationId,
    required String platform,
    required String externalAccountId,
    required String externalMessageId,
    required String senderId,
    required String text,
    required Map<String, dynamic> rawPayload,
    DateTime? timestamp,
  }) {
    return InboxMessage(
      id: internalMessageId,
      conversationId: conversationId,
      senderId: senderId,
      content: text,
      timestamp: timestamp ?? DateTime.now(),
      externalMessageId: externalMessageId,
      platformId: platform,
      connectorId: platform,
      externalAccountId: externalAccountId,
      deliveryState: 'delivered',
      metadata: rawPayload,
      syncState: 'synced',
      source: 'webhook',
    );
  }
  
  static dynamic _parsePlatform(String platformStr) {
    // We would parse this to SocialPlatform. Since this file cannot import it properly 
    // due to circular dependency on unified_inbox_provider in current codebase structure,
    // we use a dynamic hack for now or refactor SocialPlatform out.
    // In actual implementation, we would extract SocialPlatform to a shared enums file.
    return null; 
  }
}
