import 'package:cloud_firestore/cloud_firestore.dart';

enum RelationshipStatus { none, pending, accepted, blocked }

class Relationship {
  final String id;
  final String followerId;
  final String followingId;
  final RelationshipStatus status;
  final bool isCloseFriend;
  final bool isFavorite;
  final bool isMuted;
  final bool isRestricted;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Relationship({
    required this.id,
    required this.followerId,
    required this.followingId,
    this.status = RelationshipStatus.none,
    this.isCloseFriend = false,
    this.isFavorite = false,
    this.isMuted = false,
    this.isRestricted = false,
    required this.createdAt,
    this.updatedAt,
  });

  factory Relationship.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Relationship(
      id: doc.id,
      followerId: data['followerId'] ?? '',
      followingId: data['followingId'] ?? '',
      status: RelationshipStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => RelationshipStatus.none,
      ),
      isCloseFriend: data['isCloseFriend'] ?? false,
      isFavorite: data['isFavorite'] ?? false,
      isMuted: data['isMuted'] ?? false,
      isRestricted: data['isRestricted'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'followerId': followerId,
      'followingId': followingId,
      'status': status.name,
      'isCloseFriend': isCloseFriend,
      'isFavorite': isFavorite,
      'isMuted': isMuted,
      'isRestricted': isRestricted,
      'createdAt': createdAt,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  bool get isBlocked => status == RelationshipStatus.blocked;
}
