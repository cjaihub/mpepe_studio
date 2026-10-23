import 'package:cloud_firestore/cloud_firestore.dart';
import 'attachment_model.dart';

enum MessageStatus { sending, sent, delivered, read, error }

class InboxMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final List<Attachment> attachments; // Objects containing metadata and URL
  final MessageStatus status;
  final Map<String, int> reactions; // e.g. {'👍': 2, '❤️': 1}
  final String? replyToId;
  final String? forwardedFromId;
  final bool isEdited;
  final bool isDeleted;
  final bool isPinned;
  final bool isBookmarked;
  final DateTime timestamp;

  // New Canonical Fields
  final String? externalMessageId;
  final String? externalThreadId;
  final String? platformId;
  final String? connectorId;
  final String? externalAccountId;
  final String? deliveryState;
  final Map<String, dynamic> metadata;
  final String? syncState;
  final String? source;
  final String? priority;
  
  // Phase 7: Real Platform Operations
  final String? clientCommandId;
  final int? attempt;

  InboxMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.attachments = const [],
    this.status = MessageStatus.sent,
    this.reactions = const {},
    this.replyToId,
    this.forwardedFromId,
    this.isEdited = false,
    this.isDeleted = false,
    this.isPinned = false,
    this.isBookmarked = false,
    required this.timestamp,
    this.externalMessageId,
    this.externalThreadId,
    this.platformId,
    this.connectorId,
    this.externalAccountId,
    this.deliveryState,
    this.metadata = const {},
    this.syncState,
    this.source,
    this.priority,
    this.clientCommandId,
    this.attempt,
  });

  factory InboxMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    MessageStatus parsedStatus = MessageStatus.sent;
    final String sStr = data['status'] ?? '';
    for (var s in MessageStatus.values) {
      if (s.name.toLowerCase() == sStr.toLowerCase()) {
        parsedStatus = s;
        break;
      }
    }

    if (doc.metadata.hasPendingWrites) {
      parsedStatus = MessageStatus.sending;
    }

    // Safely parse attachments
    final rawAttachments = data['attachments'] as List<dynamic>? ?? [];
    final List<Attachment> parsedAttachments = rawAttachments.map((a) {
      if (a is Map<String, dynamic>) {
        return Attachment.fromJson(a);
      } else if (a is String) {
        // Legacy fallback
        return Attachment(
          id: a,
          fileName: 'legacy_attachment',
          fileSize: 0,
          mimeType: 'application/octet-stream',
          type: AttachmentType.unknown,
          storagePath: a,
          downloadUrl: a,
          status: AttachmentStatus.ready,
        );
      }
      return null;
    }).whereType<Attachment>().toList();

    return InboxMessage(
      id: doc.id,
      conversationId: data['conversationId'] ?? '',
      senderId: data['senderId'] ?? '',
      content: data['content'] ?? '',
      attachments: parsedAttachments,
      status: parsedStatus,
      reactions: Map<String, int>.from(data['reactions'] ?? {}),
      replyToId: data['replyToId'],
      forwardedFromId: data['forwardedFromId'],
      isEdited: data['isEdited'] ?? false,
      isDeleted: data['isDeleted'] ?? false,
      isPinned: data['isPinned'] ?? false,
      isBookmarked: data['isBookmarked'] ?? false,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      externalMessageId: data['externalMessageId'],
      externalThreadId: data['externalThreadId'],
      platformId: data['platformId'],
      connectorId: data['connectorId'],
      externalAccountId: data['externalAccountId'],
      deliveryState: data['deliveryState'],
      metadata: Map<String, dynamic>.from(data['metadata'] ?? {}),
      syncState: data['syncState'],
      source: data['source'],
      priority: data['priority'],
      clientCommandId: data['clientCommandId'],
      attempt: data['attempt'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'conversationId': conversationId,
      'senderId': senderId,
      'content': content,
      'attachments': attachments.map((a) => a.toJson()).toList(),
      'status': status.name,
      'reactions': reactions,
      'replyToId': replyToId,
      'forwardedFromId': forwardedFromId,
      'isEdited': isEdited,
      'isDeleted': isDeleted,
      'isPinned': isPinned,
      'isBookmarked': isBookmarked,
      'timestamp': Timestamp.fromDate(timestamp),
      if (externalMessageId != null) 'externalMessageId': externalMessageId,
      if (externalThreadId != null) 'externalThreadId': externalThreadId,
      if (platformId != null) 'platformId': platformId,
      if (connectorId != null) 'connectorId': connectorId,
      if (externalAccountId != null) 'externalAccountId': externalAccountId,
      if (deliveryState != null) 'deliveryState': deliveryState,
      'metadata': metadata,
      if (syncState != null) 'syncState': syncState,
      if (source != null) 'source': source,
      if (priority != null) 'priority': priority,
      if (clientCommandId != null) 'clientCommandId': clientCommandId,
      if (attempt != null) 'attempt': attempt,
    };
  }

  InboxMessage copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? content,
    List<Attachment>? attachments,
    MessageStatus? status,
    Map<String, int>? reactions,
    String? replyToId,
    String? forwardedFromId,
    bool? isEdited,
    bool? isDeleted,
    bool? isPinned,
    bool? isBookmarked,
    DateTime? timestamp,
    String? externalMessageId,
    String? externalThreadId,
    String? platformId,
    String? connectorId,
    String? externalAccountId,
    String? deliveryState,
    Map<String, dynamic>? metadata,
    String? syncState,
    String? source,
    String? priority,
    String? clientCommandId,
    int? attempt,
  }) {
    return InboxMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      attachments: attachments ?? this.attachments,
      status: status ?? this.status,
      reactions: reactions ?? this.reactions,
      replyToId: replyToId ?? this.replyToId,
      forwardedFromId: forwardedFromId ?? this.forwardedFromId,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      isPinned: isPinned ?? this.isPinned,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      timestamp: timestamp ?? this.timestamp,
      externalMessageId: externalMessageId ?? this.externalMessageId,
      externalThreadId: externalThreadId ?? this.externalThreadId,
      platformId: platformId ?? this.platformId,
      connectorId: connectorId ?? this.connectorId,
      externalAccountId: externalAccountId ?? this.externalAccountId,
      deliveryState: deliveryState ?? this.deliveryState,
      metadata: metadata ?? this.metadata,
      syncState: syncState ?? this.syncState,
      source: source ?? this.source,
      priority: priority ?? this.priority,
      clientCommandId: clientCommandId ?? this.clientCommandId,
      attempt: attempt ?? this.attempt,
    );
  }
}
