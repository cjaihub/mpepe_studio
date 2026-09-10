import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LocationService {
  /// Fetches the user's country code based on their IP address.
  /// Uses a free IP-based location API.
  static Future<String?> getCountryCode() async {
    try {
      final response = await http.get(Uri.parse('http://ip-api.com/json')).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && data['countryCode'] != null) {
          return data['countryCode']; // e.g., 'US', 'GB', 'KE'
        }
      }
    } catch (e) {
      // Fail silently and fallback to default country in UI
      debugPrint('Location auto-detect failed: $e');
    }
    return null;
  }
}
