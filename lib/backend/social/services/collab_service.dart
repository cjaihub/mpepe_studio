import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/social_profile.dart';
import '../models/social_notification.dart';

/// Roles for co-authors and collaborators on Oneova content.
enum CollaboratorRole {
  coAuthor,
  editor,
  featuredCreator,
  soundDesigner,
  director,
}

extension CollaboratorRoleExtension on CollaboratorRole {
  String get displayName {
    switch (this) {
      case CollaboratorRole.coAuthor:
        return 'Co-Author';
      case CollaboratorRole.editor:
        return 'Video Editor';
      case CollaboratorRole.featuredCreator:
        return 'Featured Creator';
      case CollaboratorRole.soundDesigner:
        return 'Sound Designer';
      case CollaboratorRole.director:
        return 'Creative Director';
    }
  }
}

/// Invitation states for creator collaboration.
enum CollabInviteStatus {
  pending,
  accepted,
  declined,
  cancelled,
}

/// Represents a co-author or collaborator attached to a piece of content.
class ContentCollaborator {
  final String id;
  final String contentId;
  final String inviterId;
  final String collaboratorUserId;
  final String collaboratorUsername;
  final String collaboratorDisplayName;
  final String collaboratorAvatarUrl;
  final CollaboratorRole role;
  final CollabInviteStatus status;
  final bool displayOnProfile;
  final double? revenueSplitPercent;
  final String? inviteMessage;
  final DateTime invitedAt;
  final DateTime? respondedAt;

  const ContentCollaborator({
    required this.id,
    required this.contentId,
    required this.inviterId,
    required this.collaboratorUserId,
    required this.collaboratorUsername,
    required this.collaboratorDisplayName,
    required this.collaboratorAvatarUrl,
    required this.role,
    required this.status,
    this.displayOnProfile = true,
    this.revenueSplitPercent,
    this.inviteMessage,
    required this.invitedAt,
    this.respondedAt,
  });

  factory ContentCollaborator.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ContentCollaborator.fromMap(data, doc.id);
  }

  factory ContentCollaborator.fromMap(Map<String, dynamic> data, String id) {
    return ContentCollaborator(
      id: id,
      contentId: data['contentId'] as String? ?? '',
      inviterId: data['inviterId'] as String? ?? '',
      collaboratorUserId: data['collaboratorUserId'] as String? ?? '',
      collaboratorUsername: data['collaboratorUsername'] as String? ?? '',
      collaboratorDisplayName: data['collaboratorDisplayName'] as String? ?? '',
      collaboratorAvatarUrl: data['collaboratorAvatarUrl'] as String? ?? '',
      role: CollaboratorRole.values.firstWhere(
        (e) => e.name == data['role'],
        orElse: () => CollaboratorRole.coAuthor,
      ),
      status: CollabInviteStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => CollabInviteStatus.pending,
      ),
      displayOnProfile: data['displayOnProfile'] as bool? ?? true,
      revenueSplitPercent: (data['revenueSplitPercent'] as num?)?.toDouble(),
      inviteMessage: data['inviteMessage'] as String?,
      invitedAt: (data['invitedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      respondedAt: (data['respondedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'contentId': contentId,
      'inviterId': inviterId,
      'collaboratorUserId': collaboratorUserId,
      'collaboratorUsername': collaboratorUsername,
      'collaboratorDisplayName': collaboratorDisplayName,
      'collaboratorAvatarUrl': collaboratorAvatarUrl,
      'role': role.name,
      'status': status.name,
      'displayOnProfile': displayOnProfile,
      'revenueSplitPercent': revenueSplitPercent,
      'inviteMessage': inviteMessage,
      'invitedAt': Timestamp.fromDate(invitedAt),
      'respondedAt': respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
    };
  }

  ContentCollaborator copyWith({
    String? id,
    String? contentId,
    String? inviterId,
    String? collaboratorUserId,
    String? collaboratorUsername,
    String? collaboratorDisplayName,
    String? collaboratorAvatarUrl,
    CollaboratorRole? role,
    CollabInviteStatus? status,
    bool? displayOnProfile,
    double? revenueSplitPercent,
    String? inviteMessage,
    DateTime? invitedAt,
    DateTime? respondedAt,
  }) {
    return ContentCollaborator(
      id: id ?? this.id,
      contentId: contentId ?? this.contentId,
      inviterId: inviterId ?? this.inviterId,
      collaboratorUserId: collaboratorUserId ?? this.collaboratorUserId,
      collaboratorUsername: collaboratorUsername ?? this.collaboratorUsername,
      collaboratorDisplayName: collaboratorDisplayName ?? this.collaboratorDisplayName,
      collaboratorAvatarUrl: collaboratorAvatarUrl ?? this.collaboratorAvatarUrl,
      role: role ?? this.role,
      status: status ?? this.status,
      displayOnProfile: displayOnProfile ?? this.displayOnProfile,
      revenueSplitPercent: revenueSplitPercent ?? this.revenueSplitPercent,
      inviteMessage: inviteMessage ?? this.inviteMessage,
      invitedAt: invitedAt ?? this.invitedAt,
      respondedAt: respondedAt ?? this.respondedAt,
    );
  }
}

final collabServiceProvider = Provider<CollabService>((ref) {
  return CollabService();
});

/// Creator collaboration backend for Oneova in Firestore.
/// - Searches creators by username or display name.
/// - Stores collaboration invitations in `content/{contentId}/collaborators`.
/// - Sends real-time notifications to tagged collaborators.
class CollabService {
  final FirebaseFirestore? _customFirestore;

  CollabService({FirebaseFirestore? firestore})
      : _customFirestore = firestore;

  FirebaseFirestore get _firestore => _customFirestore ?? FirebaseFirestore.instance;

  /// Searches creators in the Firestore `users` collection by username or display name prefix.
  Future<List<SocialProfile>> searchCreators(String query, {int limit = 20}) async {
    final cleanQuery = query.trim().replaceAll('@', '');
    if (cleanQuery.isEmpty) return [];

    final q = cleanQuery.toLowerCase();
    final endQ = '$q\uf8ff';

    final Map<String, SocialProfile> resultsMap = {};

    try {
      // Query 1: Search by lowercase username prefix
      final usernameSnap = await _firestore
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: q)
          .where('username', isLessThan: endQ)
          .limit(limit)
          .get();

      for (final doc in usernameSnap.docs) {
        resultsMap[doc.id] = SocialProfile.fromFirestore(doc);
      }

      // Query 2: Search by displayName prefix if limit not reached
      if (resultsMap.length < limit) {
        final remaining = limit - resultsMap.length;
        final nameSnap = await _firestore
            .collection('users')
            .where('displayName', isGreaterThanOrEqualTo: cleanQuery)
            .where('displayName', isLessThan: '$cleanQuery\uf8ff')
            .limit(remaining)
            .get();

        for (final doc in nameSnap.docs) {
          if (!resultsMap.containsKey(doc.id)) {
            resultsMap[doc.id] = SocialProfile.fromFirestore(doc);
          }
        }
      }
    } catch (_) {
      // Return partial or empty results on search timeout
    }

    return resultsMap.values.toList();
  }

  /// Sends a collaborator invitation to a creator for a specific content piece.
  /// Stores the invitation at `content/{contentId}/collaborators/{collaboratorUserId}`
  /// and sends an invitation notification to the tagged creator.
  Future<ContentCollaborator> inviteCollaborator({
    required String contentId,
    required String inviterId,
    required String collaboratorUserId,
    CollaboratorRole role = CollaboratorRole.coAuthor,
    bool displayOnProfile = true,
    double? revenueSplitPercent,
    String? inviteMessage,
  }) async {
    if (inviterId == collaboratorUserId) {
      throw ArgumentError('Creators cannot invite themselves as collaborators.');
    }

    // 1. Fetch collaborator user details from Firestore
    final collaboratorDoc = await _firestore.collection('users').doc(collaboratorUserId).get();
    final collaboratorData = collaboratorDoc.data() ?? {};
    final collaboratorUsername = collaboratorData['username'] as String? ?? 'creator';
    final collaboratorDisplayName = collaboratorData['displayName'] as String? ?? collaboratorUsername;
    final collaboratorAvatarUrl = collaboratorData['avatarUrl'] as String? ?? collaboratorData['profilePhotoUrl'] as String? ?? '';

    // Fetch inviter user details for notification
    final inviterDoc = await _firestore.collection('users').doc(inviterId).get();
    final inviterData = inviterDoc.data() ?? {};
    final inviterName = inviterData['displayName'] as String? ?? inviterData['username'] as String? ?? 'A creator';

    final now = DateTime.now();

    final collaborator = ContentCollaborator(
      id: collaboratorUserId,
      contentId: contentId,
      inviterId: inviterId,
      collaboratorUserId: collaboratorUserId,
      collaboratorUsername: collaboratorUsername,
      collaboratorDisplayName: collaboratorDisplayName,
      collaboratorAvatarUrl: collaboratorAvatarUrl,
      role: role,
      status: CollabInviteStatus.pending,
      displayOnProfile: displayOnProfile,
      revenueSplitPercent: revenueSplitPercent,
      inviteMessage: inviteMessage,
      invitedAt: now,
    );

    final batch = _firestore.batch();

    // 2. Store collaborator document in content/{contentId}/collaborators/{collaboratorUserId}
    final collabRef = _firestore
        .collection('content')
        .doc(contentId)
        .collection('collaborators')
        .doc(collaboratorUserId);
    batch.set(collabRef, collaborator.toMap(), SetOptions(merge: true));

    // 3. Store invite reference under collaborator's inbox/activity for quick lookup
    final userInviteRef = _firestore
        .collection('users')
        .doc(collaboratorUserId)
        .collection('collab_invites')
        .doc(contentId);
    batch.set(userInviteRef, {
      'contentId': contentId,
      'inviterId': inviterId,
      'inviterName': inviterName,
      'role': role.name,
      'status': CollabInviteStatus.pending.name,
      'invitedAt': Timestamp.fromDate(now),
    }, SetOptions(merge: true));

    // 4. Send notification to tagged user in social_notifications
    final notifRef = _firestore.collection('social_notifications').doc();
    batch.set(notifRef, {
      'userId': collaboratorUserId,
      'actorId': inviterId,
      'type': NotificationType.collab_invite.name,
      'targetId': contentId,
      'isRead': false,
      'title': 'Co-Author Collaboration Invitation',
      'body': '$inviterName invited you to co-author a video as ${role.displayName} on Oneova.',
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    return collaborator;
  }

  /// Responds to a collaborator invitation (accept or decline).
  Future<void> respondToInvite({
    required String contentId,
    required String collaboratorUserId,
    required bool accept,
  }) async {
    final newStatus = accept ? CollabInviteStatus.accepted : CollabInviteStatus.declined;
    final now = DateTime.now();

    final collabRef = _firestore
        .collection('content')
        .doc(contentId)
        .collection('collaborators')
        .doc(collaboratorUserId);

    final collabDoc = await collabRef.get();
    if (!collabDoc.exists) {
      throw StateError('Collaboration invitation does not exist.');
    }

    final data = collabDoc.data() ?? {};
    final inviterId = data['inviterId'] as String? ?? '';

    final batch = _firestore.batch();

    // 1. Update status in content/{contentId}/collaborators
    batch.update(collabRef, {
      'status': newStatus.name,
      'respondedAt': Timestamp.fromDate(now),
    });

    // 2. Update user's invite entry
    final userInviteRef = _firestore
        .collection('users')
        .doc(collaboratorUserId)
        .collection('collab_invites')
        .doc(contentId);
    batch.update(userInviteRef, {
      'status': newStatus.name,
      'respondedAt': Timestamp.fromDate(now),
    });

    // 3. If accepted, add to coAuthorIds array in content document
    final contentRef = _firestore.collection('content').doc(contentId);
    if (accept) {
      batch.update(contentRef, {
        'coAuthorIds': FieldValue.arrayUnion([collaboratorUserId]),
      });
    }

    // 4. Send response notification to inviter
    if (inviterId.isNotEmpty) {
      final notifRef = _firestore.collection('social_notifications').doc();
      final collabUserDoc = await _firestore.collection('users').doc(collaboratorUserId).get();
      final collabUserData = collabUserDoc.data() ?? {};
      final collabName = collabUserData['displayName'] as String? ?? collabUserData['username'] as String? ?? 'A creator';

      batch.set(notifRef, {
        'userId': inviterId,
        'actorId': collaboratorUserId,
        'type': accept ? NotificationType.collab_accepted.name : NotificationType.mention.name,
        'targetId': contentId,
        'isRead': false,
        'title': accept ? 'Collaboration Accepted 🎉' : 'Collaboration Declined',
        'body': accept
            ? '$collabName accepted your invitation to co-author on Oneova!'
            : '$collabName was unable to accept your co-author invitation.',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  /// Removes or revokes a collaborator from a piece of content.
  Future<void> removeCollaborator({
    required String contentId,
    required String collaboratorUserId,
  }) async {
    final batch = _firestore.batch();

    final collabRef = _firestore
        .collection('content')
        .doc(contentId)
        .collection('collaborators')
        .doc(collaboratorUserId);
    batch.delete(collabRef);

    final contentRef = _firestore.collection('content').doc(contentId);
    batch.update(contentRef, {
      'coAuthorIds': FieldValue.arrayRemove([collaboratorUserId]),
    });

    final userInviteRef = _firestore
        .collection('users')
        .doc(collaboratorUserId)
        .collection('collab_invites')
        .doc(contentId);
    batch.delete(userInviteRef);

    await batch.commit();
  }

  /// Streams active collaborators for a given content item.
  Stream<List<ContentCollaborator>> streamContentCollaborators(String contentId) {
    return _firestore
        .collection('content')
        .doc(contentId)
        .collection('collaborators')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(ContentCollaborator.fromFirestore).toList());
  }

  /// Fetches collaborators for a given content item once.
  Future<List<ContentCollaborator>> getContentCollaborators(String contentId) async {
    final snapshot = await _firestore
        .collection('content')
        .doc(contentId)
        .collection('collaborators')
        .get();
    return snapshot.docs.map(ContentCollaborator.fromFirestore).toList();
  }

  /// Streams pending collaboration invitations for a user.
  Stream<List<ContentCollaborator>> streamPendingInvitesForUser(String userId) {
    return _firestore
        .collectionGroup('collaborators')
        .where('collaboratorUserId', isEqualTo: userId)
        .where('status', isEqualTo: CollabInviteStatus.pending.name)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(ContentCollaborator.fromFirestore).toList());
  }
}
