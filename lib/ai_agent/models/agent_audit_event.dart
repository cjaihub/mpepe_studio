import 'package:cloud_firestore/cloud_firestore.dart';

class AgentAuditEvent {
  final String id;
  final String actionType; // e.g., 'send_message', 'read_conversation', 'summarize'
  final DateTime timestamp;
  final String reason;
  final String? conversationId;
  final List<String> toolsUsed;
  final List<String> dataAccessed;
  final String? responseGenerated;

  AgentAuditEvent({
    required this.id,
    required this.actionType,
    required this.timestamp,
    required this.reason,
    this.conversationId,
    this.toolsUsed = const [],
    this.dataAccessed = const [],
    this.responseGenerated,
  });

  factory AgentAuditEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return AgentAuditEvent(
      id: doc.id,
      actionType: data['actionType'] ?? 'unknown',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reason: data['reason'] ?? 'No reason provided',
      conversationId: data['conversationId'],
      toolsUsed: List<String>.from(data['toolsUsed'] ?? []),
      dataAccessed: List<String>.from(data['dataAccessed'] ?? []),
      responseGenerated: data['responseGenerated'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'actionType': actionType,
      'timestamp': Timestamp.fromDate(timestamp),
      'reason': reason,
      'conversationId': conversationId,
      'toolsUsed': toolsUsed,
      'dataAccessed': dataAccessed,
      'responseGenerated': responseGenerated,
    };
  }
}
