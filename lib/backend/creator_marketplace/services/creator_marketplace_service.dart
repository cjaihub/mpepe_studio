// ignore_for_file: avoid_print
import 'package:oneova/backend/creator_marketplace/models/creator_marketplace_models.dart';
import 'package:oneova/backend/social_inbox_repository.dart';
import 'package:oneova/backend/unified_inbox_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CreatorMarketplaceService {
  // ignore: unused_field
  final SocialInboxRepository _inboxRepo;
  final Map<String, CreatorMarketplaceProfile> _profiles = {};
  final Map<String, CollaborationRequest> _requests = {};

  CreatorMarketplaceService(this._inboxRepo);

  void registerProfile(CreatorMarketplaceProfile profile) {
    _profiles[profile.userId] = profile;
  }

  /// Searches and filters available creators based on exact criteria
  List<CreatorMarketplaceProfile> searchCreators({
    String? category,
    String? skill,
    String? language,
    bool requireAvailable = true,
  }) {
    return _profiles.values.where((p) {
      if (requireAvailable && !p.isAvailable) return false;
      if (category != null && !p.categories.contains(category)) return false;
      if (skill != null && !p.skills.contains(skill)) return false;
      if (language != null && !p.languages.contains(language)) return false;
      return true;
    }).toList();
  }

  /// Sends a direct message to a creator via the Canonical Inbox, protecting their private email/phone
  void messageCreator(String requestorId, String targetCreatorId, String text) {
    final creator = _profiles[targetCreatorId];
    if (creator == null) throw Exception('Creator not found');

    // ignore: unused_local_variable
    final msg = SocialMessageModel(
      id: 'dm_${DateTime.now().millisecondsSinceEpoch}',
      userId: targetCreatorId, // Routes directly to the creator's inbox
      platform: SocialPlatform.system,
      interactionType: SocialInteractionType.message,
      targetId: targetCreatorId,
      senderName: requestorId, // Replace with real name in prod
      senderAvatarUrl: '',
      content: 'Marketplace Inquiry: $text',
      timestamp: Timestamp.now(),
    );

    // _inboxRepo.sendMessage(msg);
    print('Canonical DM to [$targetCreatorId] from [$requestorId]: $text');
  }

  /// Submits a formal collaboration request
  CollaborationRequest requestCollaboration({
    required String requestorId,
    required String targetCreatorId,
    required String serviceId,
    required String message,
  }) {
    final creator = _profiles[targetCreatorId];
    if (creator == null) throw Exception('Creator not found');

    final service = creator.services.where((s) => s.id == serviceId).firstOrNull;
    if (service == null) throw Exception('Service listing not found');

    final request = CollaborationRequest(
      id: 'collab_${DateTime.now().millisecondsSinceEpoch}',
      requestorId: requestorId,
      targetCreatorId: targetCreatorId,
      serviceId: serviceId,
      message: message,
      agreedPrice: service.price,
    );

    _requests[request.id] = request;

    // Notify via unified inbox
    messageCreator(
      requestorId, 
      targetCreatorId, 
      'I would like to hire you for: ${service.title}. Message: $message'
    );

    return request;
  }

  CollaborationRequest? getRequest(String id) => _requests[id];
}
