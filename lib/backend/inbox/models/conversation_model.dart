import 'package:cloud_firestore/cloud_firestore.dart';
import '../../unified_inbox_provider.dart' show SocialPlatform;
import '../../security/models/privacy_enums.dart';

class Conversation {
  final String id;
  final SocialPlatform channel;
  final List<String> participants;
  final int unreadCount;
  final String? latestMessage;
  final String? typingState; // e.g., 'user_id' or null
  final Map<String, String> presence; // e.g., {'user_id': 'online'}
  final bool isPinned;
  final bool isMuted;
  final bool isArchived;
  final List<String> labels;
  final String? assignment; // UID of assigned team member
  final String? assignedTeamId; // ID of the assigned team
  final PrivacyMode privacyMode;
  final EncryptionMode encryptionMode;
  final AiAccessMode aiAccessMode;
  final RetentionPolicy retentionPolicy;
  final MediaPolicy mediaPolicy;
  final DateTime updatedAt;
  final DateTime createdAt;

  // New Canonical Fields
  final String? connectorId;
  final String? externalAccountId;
  final String? externalConversationId;
  final String? priority;
  final bool needsReply;
  final String? status;
  final String? syncState;
  final List<String> capabilities;
  final Map<String, dynamic> metadata;
  final String? source;

  Conversation({
    required this.id,
    required this.channel,
    required this.participants,
    required this.unreadCount,
    this.latestMessage,
    this.typingState,
    this.presence = const {},
    this.isPinned = false,
    this.isMuted = false,
    this.isArchived = false,
    this.labels = const [],
    this.assignment,
    this.assignedTeamId,
    this.privacyMode = PrivacyMode.private,
    this.encryptionMode = EncryptionMode.standard,
    this.aiAccessMode = AiAccessMode.allowed,
    this.retentionPolicy = RetentionPolicy.forever,
    this.mediaPolicy = MediaPolicy.standard,
    required this.updatedAt,
    required this.createdAt,
    this.connectorId,
    this.externalAccountId,
    this.externalConversationId,
    this.priority,
    this.needsReply = false,
    this.status,
    this.syncState,
    this.capabilities = const [],
    this.metadata = const {},
    this.source,
  });

  factory Conversation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    SocialPlatform parsedPlatform = SocialPlatform.system;
    final String pStr = data['channel'] ?? '';
    for (var p in SocialPlatform.values) {
      if (p.name.toLowerCase() == pStr.toLowerCase()) {
        parsedPlatform = p;
        break;
      }
    }

    return Conversation(
      id: doc.id,
      channel: parsedPlatform,
      participants: List<String>.from(data['participants'] ?? []),
      unreadCount: data['unreadCount'] ?? 0,
      latestMessage: data['latestMessage'],
      typingState: data['typingState'],
      presence: Map<String, String>.from(data['presence'] ?? {}),
      isPinned: data['isPinned'] ?? false,
      isMuted: data['isMuted'] ?? false,
      isArchived: data['isArchived'] ?? false,
      labels: List<String>.from(data['labels'] ?? []),
      assignment: data['assignment'],
      assignedTeamId: data['assignedTeamId'],
      privacyMode: PrivacyMode.values.firstWhere((e) => e.name == data['privacyMode'], orElse: () => PrivacyMode.private),
      encryptionMode: EncryptionMode.values.firstWhere((e) => e.name == data['encryptionMode'], orElse: () => EncryptionMode.standard),
      aiAccessMode: AiAccessMode.values.firstWhere((e) => e.name == data['aiAccessMode'], orElse: () => AiAccessMode.allowed),
      retentionPolicy: RetentionPolicy.values.firstWhere((e) => e.name == data['retentionPolicy'], orElse: () => RetentionPolicy.forever),
      mediaPolicy: MediaPolicy.values.firstWhere((e) => e.name == data['mediaPolicy'], orElse: () => MediaPolicy.standard),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      connectorId: data['connectorId'],
      externalAccountId: data['externalAccountId'],
      externalConversationId: data['externalConversationId'],
      priority: data['priority'],
      needsReply: data['needsReply'] ?? false,
      status: data['status'],
      syncState: data['syncState'],
      capabilities: List<String>.from(data['capabilities'] ?? []),
      metadata: Map<String, dynamic>.from(data['metadata'] ?? {}),
      source: data['source'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'channel': channel.name,
      'participants': participants,
      'unreadCount': unreadCount,
      'latestMessage': latestMessage,
      'typingState': typingState,
      'presence': presence,
      'isPinned': isPinned,
      'isMuted': isMuted,
      'isArchived': isArchived,
      'labels': labels,
      'assignment': assignment,
      'assignedTeamId': assignedTeamId,
      'privacyMode': privacyMode.name,
      'encryptionMode': encryptionMode.name,
      'aiAccessMode': aiAccessMode.name,
      'retentionPolicy': retentionPolicy.name,
      'mediaPolicy': mediaPolicy.name,
      'updatedAt': Timestamp.fromDate(updatedAt),
      'createdAt': Timestamp.fromDate(createdAt),
      if (connectorId != null) 'connectorId': connectorId,
      if (externalAccountId != null) 'externalAccountId': externalAccountId,
      if (externalConversationId != null) 'externalConversationId': externalConversationId,
      if (priority != null) 'priority': priority,
      'needsReply': needsReply,
      if (status != null) 'status': status,
      if (syncState != null) 'syncState': syncState,
      'capabilities': capabilities,
      'metadata': metadata,
      if (source != null) 'source': source,
    };
  }
}
