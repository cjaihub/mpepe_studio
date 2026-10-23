// ignore_for_file: constant_identifier_names
import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  new_follower,
  follow_accepted,
  post_like,
  comment_like,
  new_comment,
  mention,
  share,
  collab_invite,
  collab_accepted,
}

class SocialNotification {
  final String id;
  final String userId; // The user receiving the notification
  final String actorId; // The user who performed the action
  final NotificationType type;
  final String? targetId; // ID of the post, comment, or relationship
  final bool isRead;
  final DateTime createdAt;

  SocialNotification({
    required this.id,
    required this.userId,
    required this.actorId,
    required this.type,
    this.targetId,
    this.isRead = false,
    required this.createdAt,
  });

  factory SocialNotification.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SocialNotification(
      id: doc.id,
      userId: data['userId'] ?? '',
      actorId: data['actorId'] ?? '',
      type: NotificationType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => NotificationType.new_follower,
      ),
      targetId: data['targetId'],
      isRead: data['isRead'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'actorId': actorId,
      'type': type.name,
      'targetId': targetId,
      'isRead': isRead,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
