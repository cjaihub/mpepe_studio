// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:oneova/backend/maps/models/map_models.dart';

class GoogleMapsService {
  // Provided securely via environment configuration
  final String _apiKey = const String.fromEnvironment('GOOGLE_MAPS_API_KEY', defaultValue: '');
  
  // Base URLs for the New Places API and Routes API
  final String _placesBaseUrl = 'https://places.googleapis.com/v1/places';
  final String _routesBaseUrl = 'https://routes.googleapis.com/directions/v2:computeRoutes';

  /// Text Search using the New Places API
  Future<List<PlaceDetails>> textSearch(String query) async {
    if (_apiKey.isEmpty) return [];

    try {
      final response = await http.post(
        Uri.parse('$_placesBaseUrl:searchText'),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,places.location,places.types,places.primaryType,places.regularOpeningHours.isOpenNow,places.websiteUri,places.googleMapsUri',
        },
        body: jsonEncode({
          'textQuery': query,
        }),
      );

      if (response.statusCode == 200) {
        return _parsePlacesResponse(jsonDecode(response.body));
      } else {
        print('Google Maps Text Search API Error: \${response.statusCode} - \${response.body}');
      }
    } catch (e) {
      print('Google Maps Text Search Error: $e');
    }
    return [];
  }

  /// Nearby Search using the New Places API
  Future<List<PlaceDetails>> nearbySearch({
    required GeoLocation location, 
    required double radiusMeters,
    List<String>? includedTypes,
  }) async {
    if (_apiKey.isEmpty) return [];

    final Map<String, dynamic> body = {
      'locationRestriction': {
        'circle': {
          'center': {
            'latitude': location.latitude,
            'longitude': location.longitude,
          },
          'radius': radiusMeters,
        }
      }
    };
    if (includedTypes != null && includedTypes.isNotEmpty) {
      body['includedTypes'] = includedTypes;
    }

    try {
      final response = await http.post(
        Uri.parse('$_placesBaseUrl:searchNearby'),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,places.location,places.types,places.primaryType,places.regularOpeningHours.isOpenNow,places.websiteUri,places.googleMapsUri',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        return _parsePlacesResponse(jsonDecode(response.body));
      } else {
        print('Google Maps Nearby Search API Error: \${response.statusCode} - \${response.body}');
      }
    } catch (e) {
      print('Google Maps Nearby Search Error: $e');
    }
    return [];
  }

  /// Fetch full Place Details using the New Places API
  Future<PlaceDetails?> getPlaceDetails(String placeId) async {
    if (_apiKey.isEmpty) return null;

    try {
      final response = await http.get(
        Uri.parse('$_placesBaseUrl/$placeId'),
        headers: {
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask': 'id,displayName,formattedAddress,location,types,primaryType,regularOpeningHours.isOpenNow,websiteUri,googleMapsUri',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return _parsePlaceItem(data);
      } else {
        print('Google Maps Place Details API Error: \${response.statusCode} - \${response.body}');
      }
    } catch (e) {
      print('Google Maps Place Details Error: $e');
    }
    return null;
  }

  /// Calculate routes using the Google Maps Routes API v2
  Future<RouteDetails?> computeRoute(GeoLocation origin, GeoLocation destination) async {
    if (_apiKey.isEmpty) return null;

    try {
      final response = await http.post(
        Uri.parse(_routesBaseUrl),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask': 'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline',
        },
        body: jsonEncode({
          'origin': {
            'location': {
              'latLng': {
                'latitude': origin.latitude,
                'longitude': origin.longitude,
              }
            }
          },
          'destination': {
            'location': {
              'latLng': {
                'latitude': destination.latitude,
                'longitude': destination.longitude,
              }
            }
          },
          'travelMode': 'DRIVE', // Default for now
          'routingPreference': 'TRAFFIC_AWARE',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final routes = data['routes'] as List<dynamic>?;
        if (routes != null && routes.isNotEmpty) {
          final primaryRoute = routes.first;
          final durationStr = primaryRoute['duration'] as String? ?? '0s';
          // Parse "123s" to int
          final durationSeconds = int.tryParse(durationStr.replaceAll('s', '')) ?? 0;
          
          return RouteDetails(
            distanceMeters: primaryRoute['distanceMeters'] as int? ?? 0,
            durationSeconds: durationSeconds,
            encodedPolyline: primaryRoute['polyline']?['encodedPolyline'] as String? ?? '',
          );
        }
      } else {
        print('Google Maps Routes API Error: \${response.statusCode} - \${response.body}');
      }
    } catch (e) {
      print('Google Maps Compute Route Error: $e');
    }
    return null;
  }

  List<PlaceDetails> _parsePlacesResponse(Map<String, dynamic> data) {
    final placesList = data['places'] as List<dynamic>?;
    if (placesList == null) return [];
    
    return placesList.map((e) => _parsePlaceItem(e as Map<String, dynamic>)).toList();
  }

  PlaceDetails _parsePlaceItem(Map<String, dynamic> data) {
    final loc = data['location'] as Map<String, dynamic>?;
    
    return PlaceDetails(
      id: data['id'] ?? '',
      name: data['displayName']?['text'] ?? 'Unknown Location',
      formattedAddress: data['formattedAddress'] ?? '',
      location: GeoLocation(
        latitude: (loc?['latitude'] as num?)?.toDouble() ?? 0.0, 
        longitude: (loc?['longitude'] as num?)?.toDouble() ?? 0.0,
      ),
      types: List<String>.from(data['types'] ?? []),
      primaryType: data['primaryType'],
      isOpenNow: data['regularOpeningHours']?['isOpenNow'] as bool?,
      websiteUri: data['websiteUri'],
      googleMapsUri: data['googleMapsUri'],
    );
  }
}
