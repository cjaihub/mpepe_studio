import 'package:oneova/backend/maps/models/map_models.dart';

enum LocationPrecision {
  precise,
  approximate,
  selectedPlace,
}

class LocationContext {
  final GeoLocation location;
  final LocationPrecision precision;
  final String? placeName; // Only used if precision == selectedPlace

  const LocationContext({
    required this.location,
    required this.precision,
    this.placeName,
  });

  String get disclaimerText {
    switch (precision) {
      case LocationPrecision.precise:
        return 'Using precise location';
      case LocationPrecision.approximate:
        return 'Using approximate location';
      case LocationPrecision.selectedPlace:
        return 'Using selected place: \${placeName ?? "Unknown"}';
    }
  }
}

enum LocationAIToolCall {
  searchPlaces,
  getPlace,
  searchEvents,
  computeRoute,
  comparePlaces,
  createItinerary,
  savePlace,
}

class LocationAIResponse {
  final String textResponse;
  final LocationAIToolCall? toolUsed;
  final dynamic toolResult; // E.g. List<PlaceDetails>, RouteDetails, etc.
  final LocationContext contextUsed;

  const LocationAIResponse({
    required this.textResponse,
    this.toolUsed,
    this.toolResult,
    required this.contextUsed,
  });
}
