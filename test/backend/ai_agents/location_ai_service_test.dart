import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:oneova/backend/maps/models/map_models.dart';
import 'package:oneova/backend/maps/services/google_maps_service.dart';
import 'package:oneova/backend/ai_agents/openrouter_agent_service.dart';
import 'package:oneova/backend/ai_agents/location_ai_models.dart';
import 'package:oneova/backend/ai_agents/location_ai_service.dart';

import 'location_ai_service_test.mocks.dart';

@GenerateMocks([OpenRouterAgentService, GoogleMapsService])
void main() {
  late MockOpenRouterAgentService mockAgent;
  late MockGoogleMapsService mockMaps;
  late LocationAIService locationAI;

  setUp(() {
    mockAgent = MockOpenRouterAgentService();
    mockMaps = MockGoogleMapsService();
    locationAI = LocationAIService(mockAgent, mockMaps);
  });

  test('Routes searchPlaces correctly and enforces disclaimer context', () async {
    const mockJson = '''
    {
      "intent": "searchPlaces",
      "parameters": {
        "query": "coffee shops"
      },
      "explanation": "Looking for coffee shops nearby."
    }
    ''';
    when(mockAgent.queryAgent(any, any)).thenAnswer((_) async => mockJson);

    final expectedPlaces = [
      PlaceDetails(id: '1', name: 'Cafe', formattedAddress: '123 St', location: GeoLocation(latitude: 0, longitude: 0), types: ['cafe']),
    ];
    when(mockMaps.textSearch(any)).thenAnswer((_) async => expectedPlaces);

    const context = LocationContext(
      location: GeoLocation(latitude: 40.7128, longitude: -74.0060),
      precision: LocationPrecision.approximate,
    );

    final response = await locationAI.handleUserQuery("Where can I get coffee?", context);

    expect(response.toolUsed, LocationAIToolCall.searchPlaces);
    expect(response.textResponse, "Looking for coffee shops nearby.");
    expect(response.toolResult, expectedPlaces);
    
    // Core privacy requirement: must return the context so UI can display "Using approximate location"
    expect(response.contextUsed.disclaimerText, 'Using approximate location');
    
    // Verify it appended coordinates safely rather than raw DB scans
    verify(mockMaps.textSearch('coffee shops near 40.7128,-74.006')).called(1);
  });

  test('Routes computeRoute correctly', () async {
    const mockJson = '''
    {
      "intent": "computeRoute",
      "parameters": {
        "destinationLat": 40.75,
        "destinationLng": -74.00
      },
      "explanation": "Calculating route to Times Square."
    }
    ''';
    when(mockAgent.queryAgent(any, any)).thenAnswer((_) async => mockJson);

    final expectedRoute = RouteDetails(distanceMeters: 5000, durationSeconds: 600, encodedPolyline: 'abc');
    when(mockMaps.computeRoute(any, any)).thenAnswer((_) async => expectedRoute);

    const context = LocationContext(
      location: GeoLocation(latitude: 40.7128, longitude: -74.0060),
      precision: LocationPrecision.precise,
    );

    final response = await locationAI.handleUserQuery("How do I get to Times Square?", context);

    expect(response.toolUsed, LocationAIToolCall.computeRoute);
    expect(response.toolResult, expectedRoute);
    expect(response.contextUsed.disclaimerText, 'Using precise location'); // Enforces precision text
  });

  test('Degrades gracefully on malformed JSON', () async {
    when(mockAgent.queryAgent(any, any)).thenAnswer((_) async => "I am an AI, I can't do that.");

    const context = LocationContext(
      location: GeoLocation(latitude: 0, longitude: 0),
      precision: LocationPrecision.precise,
    );

    final response = await locationAI.handleUserQuery("Hi", context);

    expect(response.toolUsed, isNull);
    expect(response.textResponse.contains('understand'), true);
  });
}
