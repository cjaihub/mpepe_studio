import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message_model.dart';
import '../models/conversation_model.dart';
import '../models/connector_health_model.dart';

final controlPlaneServiceProvider = Provider<ControlPlaneService>((ref) {
  return ControlPlaneService(
    FirebaseFunctions.instance,
    FirebaseFirestore.instance,
  );
});

class ControlPlaneService {
  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  ControlPlaneService(this._functions, this._firestore);

  /// Phase 7: Real Message Send Control Plane
  /// Sends a message via the backend command infrastructure.
  Future<void> sendMessage(Conversation conversation, InboxMessage draftMessage) async {
    // Local validation
    if (draftMessage.content.isEmpty && draftMessage.attachments.isEmpty) {
      throw Exception("Cannot send an empty message.");
    }
    
    if (draftMessage.clientCommandId == null) {
      throw Exception("clientCommandId is strictly required for idempotency.");
    }

    try {
      final callable = _functions.httpsCallable('inboxSendMessage');
      await callable.call({
        'conversationId': conversation.id,
        'platformId': conversation.connectorId,
        'clientCommandId': draftMessage.clientCommandId,
        'attempt': draftMessage.attempt ?? 1,
        'content': draftMessage.content,
        'attachments': draftMessage.attachments.map((a) => a.toJson()).toList(),
      });
      // The backend will perform authorization, provider resolution,
      // idempotency checks, send it to the provider API, and persist
      // the canonical record with deliveryState = 'sent' or 'failed'.
      // The realtime stream in ConversationStateProvider will pick up the result.
    } on FirebaseFunctionsException catch (e) {
      throw Exception("Backend failed to process message: ${e.message}");
    } catch (e) {
      throw Exception("Failed to dispatch send command: $e");
    }
  }

  /// Phase 7: Media / Attachment Pipeline
  /// Retrieves a secure upload URL from the backend before sending media to storage.
  Future<String> requestSecureUploadUrl(String fileName, String mimeType, int fileSize) async {
    // Example: request signed URL or token from backend
    final callable = _functions.httpsCallable('requestSecureAttachmentUpload');
    final response = await callable.call({
      'fileName': fileName,
      'mimeType': mimeType,
      'fileSize': fileSize,
    });
    return response.data['uploadUrl'] as String;
  }

  /// Phase 7: Connector Health System
  /// Listen to realtime connector health status.
  Stream<ConnectorHealth?> watchConnectorHealth(String connectorId) {
    return _firestore
        .collection('connectors')
        .doc(connectorId)
        .snapshots()
        .map((doc) => doc.exists ? ConnectorHealth.fromFirestore(doc) : null);
  }

  /// Phase 7: Platform Action Resolution
  /// Resolves which actions are available given current capability and health.
  List<String> resolveAvailableActions(
    Conversation conversation,
    ConnectorHealth? health,
    bool hasPermission,
  ) {
    if (!hasPermission) return [];

    final actions = <String>[];
    
    // Account-level capability + health takes precedence
    if (health != null && health.status != ConnectorStatus.connected) {
      // If degraded/disconnected, maybe only local actions like 'Archive', 'Delete' are allowed.
      return ['archive', 'delete'];
    }

    final caps = conversation.capabilities ?? [];
    
    // Default actions always supported if connected
    actions.add('send_text');
    actions.add('archive');
    actions.add('delete');

    if (caps.contains('attachments') || conversation.connectorId == null) {
      actions.add('send_media');
      actions.add('send_file');
    }

    if (caps.contains('voice') || conversation.connectorId == null) {
      actions.add('send_voice');
    }
    
    if (caps.contains('reply') || conversation.connectorId == null) {
      actions.add('reply');
    }
    
    if (caps.contains('react') || conversation.connectorId == null) {
      actions.add('react');
    }

    return actions;
  }
}
