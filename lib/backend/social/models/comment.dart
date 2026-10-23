import 'package:cloud_firestore/cloud_firestore.dart';
import 'mention.dart';

enum CommentType { text, emoji, gif, image, video, voice }

class Comment {
  final String id;
  final String postId;
  final String authorId;
  final String content;
  final CommentType type;
  final List<Mention> mentions;
  final List<String> mentionedUserIds;
  final String? replyToId;
  final int reactionCount;
  final DateTime createdAt;
  
  final bool isPinned;
  final bool hasCreatorReply;
  final bool isModerated;
  final String? videoReplyPostId;
  final List<String> likerIds;

  /// Length of a voice comment ([type] == [CommentType.voice]); [content] is its audio URL.
  final int? voiceDurationMs;

  Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.content,
    this.type = CommentType.text,
    this.mentions = const [],
    this.mentionedUserIds = const [],
    this.replyToId,
    this.reactionCount = 0,
    required this.createdAt,
    this.isPinned = false,
    this.hasCreatorReply = false,
    this.isModerated = false,
    this.videoReplyPostId,
    this.likerIds = const [],
    this.voiceDurationMs,
  });

  factory Comment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Comment(
      id: doc.id,
      postId: data['postId'] ?? '',
      authorId: data['authorId'] ?? '',
      content: data['content'] ?? '',
      type: CommentType.values.firstWhere(
        (e) => e.name == data['type'], 
        orElse: () => CommentType.text
      ),
      mentions: (data['mentions'] as List<dynamic>?)
              ?.map((e) => Mention.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      mentionedUserIds: List<String>.from(data['mentionedUserIds'] ?? []),
      replyToId: data['replyToId'],
      reactionCount: data['reactionCount'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isPinned: data['isPinned'] ?? false,
      hasCreatorReply: data['hasCreatorReply'] ?? false,
      isModerated: data['isModerated'] ?? false,
      videoReplyPostId: data['videoReplyPostId'],
      likerIds: List<String>.from(data['likerIds'] ?? []),
      voiceDurationMs: (data['voiceDurationMs'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'postId': postId,
      'authorId': authorId,
      'content': content,
      'type': type.name,
      'mentions': mentions.map((m) => m.toMap()).toList(),
      'mentionedUserIds': mentionedUserIds,
      'replyToId': replyToId,
      'reactionCount': reactionCount,
      'createdAt': FieldValue.serverTimestamp(),
      'isPinned': isPinned,
      'hasCreatorReply': hasCreatorReply,
      'isModerated': isModerated,
      if (videoReplyPostId != null) 'videoReplyPostId': videoReplyPostId,
      'likerIds': likerIds,
      if (voiceDurationMs != null) 'voiceDurationMs': voiceDurationMs,
    };
  }
}
