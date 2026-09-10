import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> getSettings(String userId) async {
    try {
      final doc = await _firestore.collection('user_settings').doc(userId).get();
      if (doc.exists && doc.data() != null) {
        // Merge with defaults to ensure missing keys are populated
        final data = doc.data()!;
        final defaults = _defaultSettings();
        return _mergeSettings(defaults, data);
      } else {
        await _firestore.collection('user_settings').doc(userId).set(_defaultSettings());
        return _defaultSettings();
      }
    } catch (e) {
      print('Error getting settings: $e');
      return _defaultSettings();
    }
  }

  Future<void> updateSettings(String userId, Map<String, dynamic> newSettings) async {
    try {
      await _firestore.collection('user_settings').doc(userId).set(newSettings, SetOptions(merge: true));
    } catch (e) {
      print('Error updating settings: $e');
      rethrow;
    }
  }

  Future<void> updateSettingsCategory(String userId, String category, Map<String, dynamic> categoryData) async {
    try {
      await _firestore.collection('user_settings').doc(userId).set({
        category: categoryData
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error updating settings category: $e');
      rethrow;
    }
  }

  Map<String, dynamic> _mergeSettings(Map<String, dynamic> defaults, Map<String, dynamic> current) {
    Map<String, dynamic> result = Map.from(defaults);
    current.forEach((key, value) {
      if (value is Map<String, dynamic> && result.containsKey(key) && result[key] is Map<String, dynamic>) {
        result[key] = _mergeSettings(result[key] as Map<String, dynamic>, value);
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  Map<String, dynamic> _defaultSettings() {
    return {
      'profile': {
        'displayName': '',
        'bio': '',
        'creatorTags': [],
      },
      'app': {
        'callsEnabled': true,
        'messagingEnabled': true,
        'saveHistory': true,
        'desktopAutoConnect': false,
      },
      'notifications': {
        'uploadAlerts': true,
        'commentsMentions': true,
        'milestoneAlerts': false,
        'teamMessages': true,
        'aiCompletions': true,
      },
      'ai': {
        'defaultModel': 'gemini-1.5-pro',
        'assistantTone': 'Professional',
        'autoAggressiveness': 0.5,
      },
      'social': {
        'youtubeAutoSync': false,
        'metaAutoReply': false,
        'tiktokAutoPost': false,
        'instagramStorySync': false,
      },
      'privacy': {
        'shareAnalytics': false,
        'requireBiometrics': false,
        'twoFactorEnabled': false,
        'publicProfile': true,
      },
    };
  }
}
