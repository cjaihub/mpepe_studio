import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'team_models.dart';

final teamServiceProvider = Provider((ref) => TeamService());

final liveWorkspaceMembersProvider = StreamProvider<List<WorkspaceMember>>((ref) {
  final service = ref.watch(teamServiceProvider);
  return service.streamLiveMembers();
});

class TeamService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<String?> getCurrentWorkspaceId() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    final userDoc = await _firestore.collection('users').doc(uid).get();
    return userDoc.data()?['activeWorkspaceId'] as String?;
  }

  Future<WorkspaceMember?> getCurrentMemberProfile() async {
    final uid = _auth.currentUser?.uid;
    final workspaceId = await getCurrentWorkspaceId();
    if (uid == null || workspaceId == null) return null;

    final doc = await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('members')
        .doc(uid)
        .get();

    if (!doc.exists || doc.data() == null) return null;
    return WorkspaceMember.fromJson(doc.data()!);
  }

  Future<WorkspaceRole?> getRole(String workspaceId, String roleId) async {
    final doc = await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('roles')
        .doc(roleId)
        .get();
    
    if (!doc.exists || doc.data() == null) return null;
    return WorkspaceRole.fromJson(doc.data()!);
  }

  Future<bool> checkPermission(PermissionResource resource, PermissionAction action) async {
    final member = await getCurrentMemberProfile();
    if (member == null) return false;

    final role = await getRole(member.workspaceId, member.roleId);
    if (role == null) return false;

    return role.hasPermission(resource, action);
  }

  /// Reassigns a conversation to a specific agent (UID). 
  /// The backend security rules MUST verify `assignedBy` has `messages:assign` scope.
  Future<void> assignConversation(String conversationId, String? targetUid) async {
    final hasPerm = await checkPermission(PermissionResource.messages, PermissionAction.assign);
    if (!hasPerm) {
      debugPrint("TeamService: Denied - Missing messages:assign permission.");
      return;
    }

    await _firestore.collection('conversations').doc(conversationId).update({
      'assignedTo': targetUid,
      'assignmentUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Submits an internal note to a conversation. 
  /// Internal notes use a subcollection `internal_notes` to guarantee 
  /// they never leak to external channel participants.
  Future<void> addInternalNote(String conversationId, String text, List<String> mentions) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final hasPerm = await checkPermission(PermissionResource.messages, PermissionAction.write);
    if (!hasPerm) return;

    final note = InternalNote(
      id: _firestore.collection('conversations').doc().id, // Generate random ID
      authorId: uid,
      text: text,
      mentionedUids: mentions,
      createdAt: DateTime.now(),
    );

    await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('internal_notes')
        .doc(note.id)
        .set(note.toJson());
  }

  /// Updates agent availability/presence globally.
  Future<void> updatePresence(bool isOnline, bool isAvailable) async {
    final uid = _auth.currentUser?.uid;
    final workspaceId = await getCurrentWorkspaceId();
    if (uid == null || workspaceId == null) return;

    await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('members')
        .doc(uid)
        .update({
      'isOnline': isOnline,
      'isAvailable': isAvailable,
    });
  }

  /// Creates a private team chat (In-App) between team members.
  Future<String?> createPrivateTeamChat(List<String> memberUids) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    final participants = <String>{uid, ...memberUids}.toList();
    
    final docRef = _firestore.collection('conversations').doc();
    await docRef.set({
      'channel': 'system', // In-App / Internal
      'participants': participants,
      'unreadCount': 0,
      'isArchived': false,
      'labels': ['team_chat'],
      'privacyMode': 'private',
      'encryptionMode': 'standard',
      'aiAccessMode': 'denied', // Typically internal chats don't have autonomous AI
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    return docRef.id;
  }

  /// Streams members of the current workspace who are online.
  Stream<List<WorkspaceMember>> streamLiveMembers() async* {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      yield [];
      return;
    }
    
    final userDoc = await _firestore.collection('users').doc(uid).get();
    final workspaceId = userDoc.data()?['activeWorkspaceId'] as String?;
    
    if (workspaceId == null) {
      yield [];
      return;
    }

    yield* _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('members')
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((d) => WorkspaceMember.fromJson(d.data())).toList());
  }
}
