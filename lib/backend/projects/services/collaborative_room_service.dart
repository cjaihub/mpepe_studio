// ignore_for_file: avoid_print
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:oneova/backend/project_repository.dart';
import 'package:oneova/backend/social_inbox_repository.dart';
import 'package:oneova/backend/unified_inbox_provider.dart';

class CollaborativeRoomService {
  // ignore: unused_field
  final ProjectRepository _projectRepo;
  // ignore: unused_field
  final SocialInboxRepository _inboxRepo;

  CollaborativeRoomService(this._projectRepo, this._inboxRepo);

  Future<void> addCollaborator(String projectId, String requestorId, String newMemberId, String role) async {
    // Note: In real app, we'd fetch current project to check if requestor is owner
    // This is a simplified stub showing the architectural intent.
    // _firestore.runTransaction...
  }

  Future<void> assignTask(String projectId, String requestorId, String assigneeId, String taskDescription) async {
    // Validate role, append to tasks list
  }

  Future<void> shareAsset(String projectId, String uploaderId, String assetUrl) async {
    // Append to assets
  }

  Future<void> executeAiAction(String projectId, String requestorId, String actionData) async {
    // Record AI brainstorm event
  }

  /// Sends a chat message to the room using the unified Canonical Group architecture
  Future<void> sendRoomMessage(StudioProject project, String senderId, String message) async {
    if (project.canonicalGroupId == null) {
      throw Exception('Project is not linked to a canonical communication group.');
    }

    if (project.memberIds?.contains(senderId) != true && project.ownerId != senderId) {
      throw Exception('Unauthorized: Sender is not a member of this project.');
    }

    // ignore: unused_local_variable
    final msg = SocialMessageModel(
      id: 'proj_msg_${DateTime.now().millisecondsSinceEpoch}',
      userId: project.canonicalGroupId!, // Target the project's canonical group chat
      platform: SocialPlatform.system,
      interactionType: SocialInteractionType.message,
      targetId: project.id,
      senderName: senderId,
      senderAvatarUrl: '',
      content: message,
      timestamp: Timestamp.now(),
    );

    // _inboxRepo.sendMessage(msg);
    print('Room Chat (Group ${project.canonicalGroupId}): [$senderId] $message');
  }

}
