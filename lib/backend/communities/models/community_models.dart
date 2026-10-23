enum CommunityType {
  creator,
  city,
  school,
  interest,
  professional,
  sports,
  gaming,
  travel,
  learning,
}

enum CommunityPrivacy {
  public,
  private,
  inviteOnly,
}

enum CommunityRole {
  owner,
  admin,
  moderator,
  member,
  guest,
}

class CommunityMember {
  final String userId;
  final CommunityRole role;
  final DateTime joinedAt;

  const CommunityMember({
    required this.userId,
    required this.role,
    required this.joinedAt,
  });
}

class Community {
  final String id;
  // This explicitly links to the Canonical Group/Relationship system underlying the app
  final String canonicalGroupId; 
  
  final String name;
  final String description;
  final CommunityType type;
  final CommunityPrivacy privacy;
  
  final List<String> rules;
  final List<CommunityMember> members;

  const Community({
    required this.id,
    required this.canonicalGroupId,
    required this.name,
    required this.description,
    required this.type,
    required this.privacy,
    this.rules = const [],
    this.members = const [],
  });

  bool isModeratorOrAbove(String userId) {
    final member = members.where((m) => m.userId == userId).firstOrNull;
    if (member == null) return false;
    return member.role == CommunityRole.owner || 
           member.role == CommunityRole.admin || 
           member.role == CommunityRole.moderator;
  }
}

// Stubs for modular community features
class CommunityPoll {
  final String id;
  final String question;
  final List<String> options;
  final Map<String, int> votes; // userId -> optionIndex

  CommunityPoll(this.id, this.question, this.options) : votes = {};
}

class CommunityEvent {
  final String id;
  final String title;
  final DateTime startTime;

  CommunityEvent(this.id, this.title, this.startTime);
}
