import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/maps/models/map_models.dart';
import 'package:oneova/backend/maps/services/google_maps_service.dart';

void main() {
  late GoogleMapsService mapsService;

  setUp(() {
    mapsService = GoogleMapsService();
  });

  // Note: Due to missing API keys in CI/mock environment, these tests primarily ensure 
  // the service doesn't crash on initialization or empty environment variables, 
  // and degrades gracefully (returns empty lists or nulls) rather than throwing format exceptions.

  test('textSearch degrades gracefully when API key is missing', () async {
    final results = await mapsService.textSearch('Coffee shop');
    expect(results, isEmpty);
  });

  test('nearbySearch degrades gracefully when API key is missing', () async {
    final results = await mapsService.nearbySearch(
      location: const GeoLocation(latitude: 37.7749, longitude: -122.4194),
      radiusMeters: 500,
    );
    expect(results, isEmpty);
  });

  test('getPlaceDetails degrades gracefully when API key is missing', () async {
    final result = await mapsService.getPlaceDetails('ChIJN1t_tDeuEmsRUsoyG83frY4');
    expect(result, isNull);
  });

  test('computeRoute degrades gracefully when API key is missing', () async {
    final result = await mapsService.computeRoute(
      const GeoLocation(latitude: 37.7749, longitude: -122.4194),
      const GeoLocation(latitude: 37.7849, longitude: -122.4094),
    );
    expect(result, isNull);
  });
}
