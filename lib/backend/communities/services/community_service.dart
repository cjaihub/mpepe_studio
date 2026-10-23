// ignore_for_file: avoid_print
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:oneova/backend/communities/models/community_models.dart';
import 'package:oneova/backend/social_inbox_repository.dart';
import 'package:oneova/backend/unified_inbox_provider.dart';

class CommunityService {
  // ignore: unused_field
  final SocialInboxRepository _inboxRepo;
  final Map<String, Community> _communities = {}; // Memory stub for testing
  final Map<String, List<CommunityPoll>> _polls = {};
  final Map<String, List<CommunityEvent>> _events = {};
  
  CommunityService(this._inboxRepo);

  Community createCommunity({
    required String creatorUserId,
    required String canonicalGroupId,
    required String name,
    required String description,
    required CommunityType type,
    required CommunityPrivacy privacy,
    List<String> rules = const [],
  }) {
    final comm = Community(
      id: 'comm_${DateTime.now().millisecondsSinceEpoch}',
      canonicalGroupId: canonicalGroupId,
      name: name,
      description: description,
      type: type,
      privacy: privacy,
      rules: rules,
      members: [
        CommunityMember(
          userId: creatorUserId,
          role: CommunityRole.owner, // Creator is owner
          joinedAt: DateTime.now(),
        )
      ],
    );

    _communities[comm.id] = comm;
    return comm;
  }

  /// Broadcasts an announcement leveraging the existing Canonical Messaging system
  void postAnnouncement(String communityId, String moderatorUserId, String content) {
    final comm = _communities[communityId];
    if (comm == null) throw Exception('Community not found');
    
    if (!comm.isModeratorOrAbove(moderatorUserId)) {
      throw Exception('Unauthorized: Only moderators or admins can post announcements.');
    }

    // Instead of building a duplicate chat system, we map directly to SocialInbox
    final announcement = SocialMessageModel(
      id: 'annc_${DateTime.now().millisecondsSinceEpoch}',
      userId: comm.canonicalGroupId, // The canonical group inbox receives this
      platform: SocialPlatform.system,
      interactionType: SocialInteractionType.post, // Represents a top-level announcement/feed post
      senderName: moderatorUserId, // Real app uses user profile service
      senderAvatarUrl: '',
      content: 'ANNOUNCEMENT: $content',
      timestamp: Timestamp.now(),
    );

    // Simulate sending to repository
    print('Inbox Broadcast (Canonical Group ${comm.canonicalGroupId}): ${announcement.content}');
  }

  /// Sends a normal community chat message
  void sendChatMessage(String communityId, String senderId, String message) {
    final comm = _communities[communityId];
    if (comm == null) throw Exception('Community not found');

    if (comm.members.where((m) => m.userId == senderId).isEmpty) {
      throw Exception('Unauthorized: Not a member of this community.');
    }

    // Leverages Canonical Messaging System
    print('Inbox Broadcast (Canonical Group ${comm.canonicalGroupId}): [$senderId] $message');
  }

  /// Poll implementation
  CommunityPoll createPoll(String communityId, String creatorId, String question, List<String> options) {
    final comm = _communities[communityId];
    if (comm == null) throw Exception('Community not found');

    final poll = CommunityPoll('poll_${DateTime.now().millisecondsSinceEpoch}', question, options);
    _polls.putIfAbsent(communityId, () => []).add(poll);
    
    // Announce poll to chat
    sendChatMessage(communityId, creatorId, 'New Poll: $question');
    return poll;
  }

  /// Event implementation
  CommunityEvent createEvent(String communityId, String creatorId, String title, DateTime time) {
    final comm = _communities[communityId];
    if (comm == null) throw Exception('Community not found');
    
    if (!comm.isModeratorOrAbove(creatorId)) {
      throw Exception('Unauthorized: Only moderators can create official events.');
    }

    final event = CommunityEvent('evt_${DateTime.now().millisecondsSinceEpoch}', title, time);
    _events.putIfAbsent(communityId, () => []).add(event);

    sendChatMessage(communityId, creatorId, 'New Event Scheduled: $title');
    return event;
  }

  Community? getCommunity(String id) => _communities[id];
}
