import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final onboardingPersistenceProvider = Provider<OnboardingPersistenceService>((ref) {
  return OnboardingPersistenceService();
});

class OnboardingPersistenceService {
  static const String _draftKey = 'mpepe_onboarding_draft';

  Future<void> saveDraft(int stepIndex, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final draftData = {
      'stepIndex': stepIndex,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_draftKey, jsonEncode(draftData));
  }

  Future<Map<String, dynamic>?> loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draftString = prefs.getString(_draftKey);
    if (draftString == null) return null;

    try {
      final decoded = jsonDecode(draftString) as Map<String, dynamic>;
      
      // Optional: Check if draft is too old (e.g., > 30 days) and discard it
      if (decoded.containsKey('timestamp')) {
        final timestamp = DateTime.parse(decoded['timestamp'] as String);
        if (DateTime.now().difference(timestamp).inDays > 30) {
          await clearDraft();
          return null;
        }
      }
      
      return decoded;
    } catch (e) {
      // In case of parsing error, clear the corrupted draft
      await clearDraft();
      return null;
    }
  }

  Future<void> clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }
}
