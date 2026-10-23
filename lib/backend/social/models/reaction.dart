import 'package:cloud_firestore/cloud_firestore.dart';

class Reaction {
  final String id;
  final String targetId;
  final String targetType; // 'post', 'comment', 'message'
  final String userId;
  final String emoji;
  final DateTime createdAt;

  Reaction({
    required this.id,
    required this.targetId,
    required this.targetType,
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  factory Reaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Reaction(
      id: doc.id,
      targetId: data['targetId'] ?? '',
      targetType: data['targetType'] ?? '',
      userId: data['userId'] ?? '',
      emoji: data['emoji'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'targetId': targetId,
      'targetType': targetType,
      'userId': userId,
      'emoji': emoji,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
