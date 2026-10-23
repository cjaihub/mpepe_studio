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

  /// Real-time stream of `user_settings/{userId}` merged over the defaults.
  /// Seeds the doc with defaults the first time it is missing.
  Stream<Map<String, dynamic>> watchSettings(String userId) {
    final ref = _firestore.collection('user_settings').doc(userId);
    return ref.snapshots().map((doc) {
      final data = doc.data();
      if (!doc.exists || data == null) {
        ref.set(_defaultSettings(), SetOptions(merge: true)).catchError((Object e) {
          print('Error seeding settings: $e');
        });
        return _defaultSettings();
      }
      return _mergeSettings(_defaultSettings(), data);
    });
  }

  Map<String, dynamic> get defaultSettings => _defaultSettings();

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
        'notificationTone': 'celestial',
        'inAppBannerEnabled': true,
        'showNumberBadges': true,
      },
      'chat': {
        'showAiStudioFab': true,
        'showComposeFab': true,
        'fabAlignment': 'right',
        'holdDurationMs': 350,
        'voiceRecordMode': 'hold',
        'quickCreatorsLimit': 5,
        'showCreatorProBanner': true,
        'enterIsSend': false,
        'chatSoundEffects': true,
        'hapticIntensity': 'medium',
        'smoothAnimations': true,
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
      'appearance': {
        'textSize': 'default',
        'boldText': false,
      },
      'accessibility': {
        'highContrast': false,
        'reduceMotion': false,
        'largeText': false,
        'screenReaderFocus': false,
      },
      'playback': {
        'reelsTheme': 'followApp',
        'autoScroll': false,
        'loopVideos': true,
        'likeHaptics': true,
      },
      'calls': {
        'allowVideo': false,
        'allowMic': true,
        'noiseCancellation': true,
      },
      'storage': {
        'autoDownloadWifi': true,
        'autoDownloadCellular': false,
        'saveToGallery': false,
      },
    };
  }
}
