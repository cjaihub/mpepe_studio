import 'package:oneova/backend/maps/models/map_models.dart';

enum CollabMapType {
  trip,
  event,
  date,
  creatorShoot,
  roadTrip,
  businessVisit,
  communityEvent,
}

class CollabMapLocation {
  final String id;
  final String addedByUserId;
  final PlaceDetails placeDetails; // Reusing PlaceDetails from the map API
  int orderIndex;
  int upvotes;
  int downvotes;

  CollabMapLocation({
    required this.id,
    required this.addedByUserId,
    required this.placeDetails,
    required this.orderIndex,
    this.upvotes = 0,
    this.downvotes = 0,
  });
}

class CollabMap {
  final String id;
  final String title;
  final CollabMapType type;
  final String groupId; // Reuses existing group architecture ID
  
  // Locations added to the map
  final List<CollabMapLocation> locations;

  CollabMap({
    required this.id,
    required this.title,
    required this.type,
    required this.groupId,
    List<CollabMapLocation>? locations,
  }) : locations = locations ?? [];

  /// Sorts the itinerary based on the current order indices
  void sortLocations() {
    locations.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }
}
