import 'package:cloud_firestore/cloud_firestore.dart';

enum AppEventType {
  userFollowed('user.followed'),
  userUnfollowed('user.unfollowed'),
  contentCreated('content.created'),
  contentUpdated('content.updated'),
  contentDeleted('content.deleted'),
  contentLiked('content.liked'),
  contentReacted('content.reacted'),
  contentReposted('content.reposted'),
  commentCreated('comment.created'),
  storyCreated('story.created'),
  storyExpired('story.expired'),
  messageCreated('message.created'),
  messageRead('message.read'),
  notificationCreated('notification.created'),
  userPresenceChanged('user.presence_changed'),
  liveStarted('live.started'),
  liveEnded('live.ended'),
  callStarted('call.started'),
  callEnded('call.ended'),
  aiStarted('ai.started'),
  aiCompleted('ai.completed'),
  subscriptionCreated('subscription.created'),
  subscriptionCancelled('subscription.cancelled');

  final String eventName;
  const AppEventType(this.eventName);
}

class CanonicalEvent {
  final String eventId; // Must be unique for idempotency & deduplication
  final AppEventType type;
  final String actorId; // The user triggering the event (Authentication bound)
  final String targetId; // What the event happened to
  final Map<String, dynamic> payload; // Context
  final int sequenceNumber; // For ordering where necessary
  final DateTime timestamp;
  
  // Pipeline Tracking
  final bool isProcessed;
  final int retryCount;

  const CanonicalEvent({
    required this.eventId,
    required this.type,
    required this.actorId,
    required this.targetId,
    required this.payload,
    this.sequenceNumber = 0,
    required this.timestamp,
    this.isProcessed = false,
    this.retryCount = 0,
  });

  factory CanonicalEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CanonicalEvent(
      eventId: doc.id,
      type: AppEventType.values.firstWhere(
        (e) => e.eventName == data['type'],
        orElse: () => AppEventType.contentCreated,
      ),
      actorId: data['actorId'] ?? '',
      targetId: data['targetId'] ?? '',
      payload: data['payload'] ?? {},
      sequenceNumber: data['sequenceNumber'] ?? 0,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isProcessed: data['isProcessed'] ?? false,
      retryCount: data['retryCount'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.eventName,
      'actorId': actorId,
      'targetId': targetId,
      'payload': payload,
      'sequenceNumber': sequenceNumber,
      'timestamp': timestamp,
      'isProcessed': isProcessed,
      'retryCount': retryCount,
    };
  }
}
