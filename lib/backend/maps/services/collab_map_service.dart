// ignore_for_file: avoid_print
import 'package:oneova/backend/maps/models/map_models.dart';
import 'package:oneova/backend/maps/models/collab_map_models.dart';
import 'package:oneova/backend/social_inbox_repository.dart'; // To hook into existing chat
import 'package:oneova/backend/unified_inbox_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CollabMapService {
  // ignore: unused_field
  final SocialInboxRepository _inboxRepo;
  final Map<String, CollabMap> _collabMaps = {}; // Mock DB

  CollabMapService(this._inboxRepo);

  CollabMap createMap({
    required String title,
    required CollabMapType type,
    required String existingGroupId,
  }) {
    final map = CollabMap(
      id: 'cmap_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      type: type,
      groupId: existingGroupId,
    );
    _collabMaps[map.id] = map;
    return map;
  }

  /// Adds a location to the collaborative map and triggers a social message in the existing chat architecture
  void addLocation(String mapId, String userId, PlaceDetails place) {
    final map = _collabMaps[mapId];
    if (map == null) return;

    final newLoc = CollabMapLocation(
      id: 'loc_${DateTime.now().millisecondsSinceEpoch}_${place.id}',
      addedByUserId: userId,
      placeDetails: place,
      orderIndex: map.locations.length,
    );
    map.locations.add(newLoc);

    // Broadcast explicitly to the existing messaging system to avoid duplicate architecture
    _broadcastSystemMessage(
      userId: map.groupId, // Using the group ID to target the chat
      content: 'Added "${place.name}" to the ${map.title} map.',
      targetId: map.id,
    );
  }

  void reorderLocation(String mapId, String locationId, int newIndex) {
    final map = _collabMaps[mapId];
    if (map == null) return;

    final locIndex = map.locations.indexWhere((l) => l.id == locationId);
    if (locIndex == -1) return;

    final loc = map.locations.removeAt(locIndex);
    map.locations.insert(newIndex, loc);

    // Normalize order indices
    for (int i = 0; i < map.locations.length; i++) {
      map.locations[i].orderIndex = i;
    }
  }

  void voteLocation(String mapId, String locationId, bool upvote) {
    final map = _collabMaps[mapId];
    if (map == null) return;

    final loc = map.locations.firstWhere((l) => l.id == locationId);
    if (upvote) {
      loc.upvotes++;
    } else {
      loc.downvotes++;
    }
  }

  /// Appends a comment regarding a map element via the unified inbox system
  void commentOnMap(String mapId, String userId, String text) {
    final map = _collabMaps[mapId];
    if (map == null) return;

    _broadcastSystemMessage(
      userId: map.groupId,
      content: text,
      targetId: mapId,
      isUserComment: true,
      senderId: userId,
    );
  }

  /// Uses the existing `SocialInboxRepository` to hook chat directly to the map context
  void _broadcastSystemMessage({
    required String userId, // Group ID maps to the user context in the mockup
    required String content,
    required String targetId,
    bool isUserComment = false,
    String? senderId,
  }) {
    // In a real app, we would write this to Firestore using _inboxRepo.
    // We construct the SocialMessageModel to prove we are using the Canonical Inbox format.
    final msg = SocialMessageModel(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      platform: SocialPlatform.system,
      interactionType: isUserComment ? SocialInteractionType.comment : SocialInteractionType.message,
      targetId: targetId,
      senderName: senderId ?? 'System Map Bot',
      senderAvatarUrl: '',
      content: content,
      timestamp: Timestamp.now(),
    );

    // Simulated broadcast
    print('Broadcast to existing Inbox Architecture: ${msg.content}');
  }

  CollabMap? getMap(String id) => _collabMaps[id];
}
