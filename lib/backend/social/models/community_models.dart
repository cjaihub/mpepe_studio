enum CommunityType {
  friends,
  followers,
  closeFriends,
  subscribers,
  group,
  channel,
  customCommunity,
}

enum CommunityRole {
  owner,
  admin,
  moderator,
  member,
  guest,
}

class CommunityRule {
  final String id;
  final String title;
  final String description;

  const CommunityRule({
    required this.id,
    required this.title,
    required this.description,
  });
}

class CommunityEvent {
  final String id;
  final String title;
  final String description;
  final DateTime startTime;
  final DateTime endTime;
  final String? locationUrl;

  const CommunityEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
    this.locationUrl,
  });
}

class CommunityAccessConfig {
  final bool canViewPosts;
  final bool canPostVideos;
  final bool canChat;
  final bool canCreateEvents;
  final bool canCreatePolls;

  const CommunityAccessConfig({
    this.canViewPosts = true,
    this.canPostVideos = false,
    this.canChat = true,
    this.canCreateEvents = false,
    this.canCreatePolls = false,
  });
}

class CommunityModel {
  final String id;
  final String name;
  final String description;
  final String? coverImageUrl;
  final String? iconUrl;
  final CommunityType type;
  
  final List<CommunityRule> rules;
  final List<String> badgeIds;
  
  // Access control mapping role -> config
  final Map<CommunityRole, CommunityAccessConfig> accessControl;

  final int memberCount;
  final bool isPrivate;
  final String ownerId;

  const CommunityModel({
    required this.id,
    required this.name,
    required this.description,
    this.coverImageUrl,
    this.iconUrl,
    required this.type,
    this.rules = const [],
    this.badgeIds = const [],
    this.accessControl = const {},
    this.memberCount = 0,
    this.isPrivate = false,
    required this.ownerId,
  });
}
