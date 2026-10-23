class GeoLocation {
  final double latitude;
  final double longitude;

  const GeoLocation({required this.latitude, required this.longitude});

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
  };
}

enum MapPinType {
  place,
  event,
  creator,
  community,
  publicContent,
  savedLocation,
}

class MapPin {
  final String id;
  final MapPinType type;
  final GeoLocation location;
  final String title;
  final String? subtitle;
  final String? imageUrl;

  const MapPin({
    required this.id,
    required this.type,
    required this.location,
    required this.title,
    this.subtitle,
    this.imageUrl,
  });
}

class PlaceDetails {
  final String id;
  final String name;
  final String formattedAddress;
  final GeoLocation location;
  final List<String> types;
  final String? primaryType;
  final bool? isOpenNow;
  final String? websiteUri;
  final String? googleMapsUri;

  const PlaceDetails({
    required this.id,
    required this.name,
    required this.formattedAddress,
    required this.location,
    required this.types,
    this.primaryType,
    this.isOpenNow,
    this.websiteUri,
    this.googleMapsUri,
  });
}

class RouteDetails {
  final int distanceMeters;
  final int durationSeconds;
  final String encodedPolyline;

  const RouteDetails({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.encodedPolyline,
  });
}
