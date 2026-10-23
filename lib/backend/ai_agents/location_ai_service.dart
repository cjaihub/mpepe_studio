// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:oneova/backend/maps/models/map_models.dart';
import 'package:oneova/backend/maps/services/google_maps_service.dart';
import 'package:oneova/backend/ai_agents/openrouter_agent_service.dart';
import 'package:oneova/backend/ai_agents/location_ai_models.dart';

class LocationAIService {
  final OpenRouterAgentService _agentService;
  final GoogleMapsService _mapsService;

  LocationAIService(this._agentService, this._mapsService);

  final String _systemPrompt = '''
You are the elite Location AI for ONEROVA. You assist users in finding places, computing routes, and planning trips.
You must NEVER invent locations or routes. You do not have direct access to raw location tables; you must use the provided tools.
Analyze the user's request and output a strict JSON object dictating which tool to call and its parameters.
Available tools: searchPlaces, getPlace, searchEvents, computeRoute, comparePlaces, createItinerary, savePlace.

Schema:
{
  "intent": "searchPlaces|getPlace|computeRoute|searchEvents|...",
  "parameters": {
    "query": "string (for searchPlaces)",
    "placeId": "string (for getPlace)",
    "destinationLat": double (for computeRoute),
    "destinationLng": double (for computeRoute)
  },
  "explanation": "Short friendly text explaining what you are looking up."
}
''';

  /// Evaluates a user location query, routes to the correct Google Maps API wrapper tool, and returns the response.
  Future<LocationAIResponse> handleUserQuery(String query, LocationContext context) async {
    // 1. Enforce location context transparency. 
    // The UI must display `context.disclaimerText` when this runs.
    
    // 2. Query LLM to determine the tool intent based on user prompt and explicit location context
    final promptPayload = {
      'userQuery': query,
      'currentLocationLat': context.location.latitude,
      'currentLocationLng': context.location.longitude,
      'precision': context.precision.name,
    };
    
    final llmResult = await _agentService.queryAgent(_systemPrompt, jsonEncode(promptPayload));
    if (llmResult == null || llmResult.isEmpty) {
      return LocationAIResponse(
        textResponse: "I'm having trouble connecting to my location engine right now.",
        contextUsed: context,
      );
    }

    try {
      final String cleanJson = _extractJson(llmResult);
      final Map<String, dynamic> data = jsonDecode(cleanJson);
      
      final String intent = data['intent'] ?? '';
      final Map<String, dynamic> params = data['parameters'] ?? {};
      final String explanation = data['explanation'] ?? 'Looking that up for you...';

      // 3. Execute the determined tool securely via the Maps Service
      dynamic toolResult;
      LocationAIToolCall? toolUsed;

      if (intent == 'searchPlaces') {
        toolUsed = LocationAIToolCall.searchPlaces;
        // Search text around user OR search generic query
        final String searchQ = params['query'] ?? 'places';
        toolResult = await _mapsService.textSearch('$searchQ near ${context.location.latitude},${context.location.longitude}');
      } 
      else if (intent == 'computeRoute') {
        toolUsed = LocationAIToolCall.computeRoute;
        final destLat = (params['destinationLat'] as num?)?.toDouble() ?? context.location.latitude;
        final destLng = (params['destinationLng'] as num?)?.toDouble() ?? context.location.longitude;
        toolResult = await _mapsService.computeRoute(
          context.location, 
          GeoLocation(latitude: destLat, longitude: destLng)
        );
      }
      else if (intent == 'getPlace') {
        toolUsed = LocationAIToolCall.getPlace;
        final pid = params['placeId'] ?? '';
        if (pid.isNotEmpty) {
          toolResult = await _mapsService.getPlaceDetails(pid);
        }
      }
      // Stubs for other requested intents that would wire to respective internal APIs
      else if (intent == 'searchEvents') {
        toolUsed = LocationAIToolCall.searchEvents;
        toolResult = []; // Stubbed Event payload
      } else if (intent == 'comparePlaces') {
        toolUsed = LocationAIToolCall.comparePlaces;
        toolResult = [];
      } else if (intent == 'createItinerary') {
        toolUsed = LocationAIToolCall.createItinerary;
        toolResult = "Itinerary drafted.";
      } else if (intent == 'savePlace') {
        toolUsed = LocationAIToolCall.savePlace;
        toolResult = true; // Success stub
      }

      // 4. Return the cohesive result enforcing the disclaimer context
      return LocationAIResponse(
        textResponse: explanation,
        toolUsed: toolUsed,
        toolResult: toolResult,
        contextUsed: context, // Strictly echoing back the context to guarantee UI displays it
      );

    } catch (e) {
      print('LocationAIService Parse Error: $e');
      return LocationAIResponse(
        textResponse: "I couldn't understand the location requirements for that request.",
        contextUsed: context,
      );
    }
  }

  String _extractJson(String response) {
    final start = response.indexOf('{');
    final end = response.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return response.substring(start, end + 1);
    }
    return response;
  }
}
