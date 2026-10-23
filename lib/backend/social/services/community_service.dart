import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/community_models.dart';

final communityServiceProvider = Provider<CommunityService>((ref) {
  return CommunityService();
});

class CommunityService {
  Future<CommunityModel> getCommunity(String id) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return CommunityModel(
      id: id,
      name: 'Filmmakers Elite',
      description: 'Exclusive community for premium subscribers.',
      type: CommunityType.subscribers,
      ownerId: 'me',
      memberCount: 1420,
      isPrivate: true,
      rules: const [
        CommunityRule(id: 'r1', title: 'Be Respectful', description: 'No hate speech or bullying.'),
        CommunityRule(id: 'r2', title: 'Stay on Topic', description: 'Only filmmaking related content.'),
      ],
      accessControl: const {
        CommunityRole.owner: CommunityAccessConfig(canViewPosts: true, canPostVideos: true, canChat: true, canCreateEvents: true, canCreatePolls: true),
        CommunityRole.moderator: CommunityAccessConfig(canViewPosts: true, canPostVideos: true, canChat: true, canCreateEvents: true, canCreatePolls: true),
        CommunityRole.member: CommunityAccessConfig(canViewPosts: true, canPostVideos: false, canChat: true, canCreateEvents: false, canCreatePolls: false),
      },
    );
  }

  Future<List<CommunityEvent>> getUpcomingEvents(String communityId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return [
      CommunityEvent(
        id: 'e1',
        title: 'Weekly Q&A',
        description: 'Live Q&A with the creator.',
        startTime: DateTime.now().add(const Duration(days: 1)),
        endTime: DateTime.now().add(const Duration(days: 1, hours: 1)),
      ),
    ];
  }

  Future<void> updateAccessConfig(String communityId, CommunityRole role, CommunityAccessConfig config) async {
    // Updates backend
    await Future.delayed(const Duration(milliseconds: 200));
  }

  Future<void> postAnnouncement(String communityId, String text) async {
    // Posts a system/admin message to the community chat/feed
    await Future.delayed(const Duration(milliseconds: 200));
  }
}
