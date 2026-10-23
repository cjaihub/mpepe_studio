import 'package:cloud_firestore/cloud_firestore.dart';
import '../../backend/user_service.dart';
import '../../backend/security/models/privacy_enums.dart';

enum RelationshipStatus {
  none,
  following,
  follower,
  mutual,
}

class ContactRelationalData {
  final String targetUserId;
  final String notes;
  final List<String> tags;
  final RelationshipStatus relationshipStatus;
  final bool isMuted;
  final bool isBlocked;
  final DateTime lastInteraction;

  ContactRelationalData({
    required this.targetUserId,
    this.notes = '',
    this.tags = const [],
    this.relationshipStatus = RelationshipStatus.none,
    this.isMuted = false,
    this.isBlocked = false,
    DateTime? lastInteraction,
  }) : lastInteraction = lastInteraction ?? DateTime.now();

  factory ContactRelationalData.fromMap(Map<String, dynamic>? map, String targetUserId) {
    if (map == null) {
      return ContactRelationalData(targetUserId: targetUserId);
    }
    return ContactRelationalData(
      targetUserId: targetUserId,
      notes: map['notes'] ?? '',
      tags: List<String>.from(map['tags'] ?? []),
      relationshipStatus: RelationshipStatus.values.firstWhere(
        (e) => e.name == map['relationshipStatus'],
        orElse: () => RelationshipStatus.none,
      ),
      isMuted: map['isMuted'] ?? false,
      isBlocked: map['isBlocked'] ?? false,
      lastInteraction: (map['lastInteraction'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'targetUserId': targetUserId,
      'notes': notes,
      'tags': tags,
      'relationshipStatus': relationshipStatus.name,
      'isMuted': isMuted,
      'isBlocked': isBlocked,
      'lastInteraction': Timestamp.fromDate(lastInteraction),
    };
  }
}

class ContactProfile {
  final AppUser user;
  final ContactRelationalData relationalData;

  ContactProfile({
    required this.user,
    required this.relationalData,
  });

  /// Privacy-aware email getter
  String? get email {
    // If we have a mutual relationship or their default mode is public, show it.
    if (user.defaultPrivacyMode == PrivacyMode.public) return user.email;
    if (relationalData.relationshipStatus == RelationshipStatus.mutual) return user.email;
    return null; // Hidden due to permissions
  }

  /// Privacy-aware phone getter (if phone existed on AppUser, we'd do the same)
  String? get phone {
    // AppUser doesn't have phone currently, so return null or a mock for now
    return null;
  }
}
