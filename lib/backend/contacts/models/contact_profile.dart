
enum ContactRelationship {
  none,
  following,
  follower,
  mutual,
  blocked,
}

enum ContactPermissionLevel {
  public,     // Sees display name, username, profile image
  connected,  // Sees shared channels/conversations, recent files, last interaction
  trusted,    // Sees phone, email, notes, tags
  admin,      // Full access
}

class ContactProfile {
  final String id;
  final String profileImage;
  final String displayName;
  final String username;
  
  // Permission gated fields
  final String? phone;
  final String? email;
  final ContactRelationship relationshipStatus;
  
  // Lists
  final List<String> sharedConversations;
  final List<String> sharedChannels;
  final List<String> notes;
  final List<String> tags;
  final List<String> recentFiles;
  final List<String> mediaUris;
  
  final DateTime? lastInteraction;

  const ContactProfile({
    required this.id,
    required this.profileImage,
    required this.displayName,
    required this.username,
    this.phone,
    this.email,
    this.relationshipStatus = ContactRelationship.none,
    this.sharedConversations = const [],
    this.sharedChannels = const [],
    this.notes = const [],
    this.tags = const [],
    this.recentFiles = const [],
    this.mediaUris = const [],
    this.lastInteraction,
  });
  
  /// Applies a permission filter. Only fields authorized by [level] will be populated.
  /// Fields lacking permission are stripped (set to null or empty lists).
  ContactProfile filterByPermission(ContactPermissionLevel level) {
    if (level == ContactPermissionLevel.admin) return this;
    
    final isTrusted = level.index >= ContactPermissionLevel.trusted.index;
    final isConnected = level.index >= ContactPermissionLevel.connected.index;

    return ContactProfile(
      id: id,
      profileImage: profileImage,
      displayName: displayName,
      username: username,
      // Phone/email only if trusted
      phone: isTrusted ? phone : null,
      email: isTrusted ? email : null,
      relationshipStatus: relationshipStatus,
      // Connections data if connected or trusted
      sharedConversations: isConnected ? sharedConversations : const [],
      sharedChannels: isConnected ? sharedChannels : const [],
      recentFiles: isConnected ? recentFiles : const [],
      mediaUris: isConnected ? mediaUris : const [],
      lastInteraction: isConnected ? lastInteraction : null,
      // Notes/tags only if trusted
      notes: isTrusted ? notes : const [],
      tags: isTrusted ? tags : const [],
    );
  }
}
