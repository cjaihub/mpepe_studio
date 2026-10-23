// ignore_for_file: constant_identifier_names
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'unified_inbox_provider.dart'; // for SocialPlatform

final socialInboxRepositoryProvider = Provider<SocialInboxRepository>((ref) {
  return SocialInboxRepository(FirebaseFirestore.instance);
});

final socialMessagesProvider = StreamProvider.family<List<SocialMessageModel>, String>((ref, userId) {
  final repository = ref.watch(socialInboxRepositoryProvider);
  return repository.getSocialMessages(userId);
});

final connectedChannelsCountProvider = StreamProvider.family<int, String>((ref, userId) {
  final repository = ref.watch(socialInboxRepositoryProvider);
  return repository.getConnectedChannelsCount(userId);
});

class SocialInboxRepository {
  final FirebaseFirestore _firestore;
  SocialInboxRepository(this._firestore);

  Stream<List<SocialMessageModel>> getSocialMessages(String userId) {
    return _firestore
        .collection('social_messages')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(50) // Limit to latest 50 to prevent huge reads
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => SocialMessageModel.fromFirestore(doc)).toList());
  }

  Stream<int> getConnectedChannelsCount(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('connected_channels')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Future<void> markAsRead(String messageId) async {
    await _firestore.collection('social_messages').doc(messageId).update({'isRead': true});
  }
}

enum SocialInteractionType { message, comment, mention, reply, like, reaction, share, post, video_comment }

class SocialMessageModel {
  final String id;
  final String userId;
  final SocialPlatform platform;
  final SocialInteractionType interactionType;
  final String? targetId; // The ID of the post, video, or comment this interaction relates to
  final String? parentCommentId; // If this is a reply to a comment
  final String senderName;
  final String senderAvatarUrl;
  final String content;
  final Timestamp timestamp;
  final bool isRead;
  final bool handledByAI;
  final bool isHarsh;
  final bool isMutedByAI;
  final int likeCount;
  final int replyCount;
  final int shareCount;

  SocialMessageModel({
    required this.id,
    required this.userId,
    required this.platform,
    this.interactionType = SocialInteractionType.message,
    this.targetId,
    this.parentCommentId,
    required this.senderName,
    required this.senderAvatarUrl,
    required this.content,
    required this.timestamp,
    this.isRead = false,
    this.handledByAI = false,
    this.isHarsh = false,
    this.isMutedByAI = false,
    this.likeCount = 0,
    this.replyCount = 0,
    this.shareCount = 0,
  });

  factory SocialMessageModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Parse platform safely
    SocialPlatform parsedPlatform = SocialPlatform.system;
    final String pStr = data['platform'] ?? '';
    for (var p in SocialPlatform.values) {
      if (p.name.toLowerCase() == pStr.toLowerCase()) {
        parsedPlatform = p;
        break;
      }
    }

    SocialInteractionType parsedType = SocialInteractionType.message;
    final String tStr = data['interactionType'] ?? '';
    for (var t in SocialInteractionType.values) {
      if (t.name.toLowerCase() == tStr.toLowerCase()) {
        parsedType = t;
        break;
      }
    }

    return SocialMessageModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      platform: parsedPlatform,
      interactionType: parsedType,
      targetId: data['targetId'] as String?,
      parentCommentId: data['parentCommentId'] as String?,
      senderName: data['senderName'] ?? 'Unknown',
      senderAvatarUrl: data['senderAvatarUrl'] ?? '',
      content: data['content'] ?? '',
      timestamp: data['timestamp'] as Timestamp? ?? Timestamp.now(),
      isRead: data['isRead'] ?? false,
      handledByAI: data['handledByAI'] ?? false,
      isHarsh: data['isHarsh'] ?? false,
      isMutedByAI: data['isMutedByAI'] ?? false,
      likeCount: data['likeCount'] ?? 0,
      replyCount: data['replyCount'] ?? 0,
      shareCount: data['shareCount'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'platform': platform.name,
      'interactionType': interactionType.name,
      if (targetId != null) 'targetId': targetId,
      if (parentCommentId != null) 'parentCommentId': parentCommentId,
      'senderName': senderName,
      'senderAvatarUrl': senderAvatarUrl,
      'content': content,
      'timestamp': timestamp,
      'isRead': isRead,
      'handledByAI': handledByAI,
      'isHarsh': isHarsh,
      'isMutedByAI': isMutedByAI,
      'likeCount': likeCount,
      'replyCount': replyCount,
      'shareCount': shareCount,
    };
  }
}
