import 'package:cloud_firestore/cloud_firestore.dart';

/// The one per-account settings store: `user_settings/{uid}`.
///
/// Every settings screen and service reads and writes this document through
/// [SettingsService] (lib/backend/settings_service.dart), one map per
/// category. Older builds kept the same settings in several other documents;
/// [AccountSettingsSchema.foldLegacy] carries those values forward once per
/// account (see [legacyDocs]).
class AccountSettingsSchema {
  AccountSettingsSchema._();

  static const String collection = 'user_settings';

  /// Bumped when a migration step is added. Stored at [schemaKey].
  static const int version = 2;
  static const String schemaKey = '_schema';

  /// Legacy documents folded into the canonical store, by id, as paths
  /// relative to `users/{uid}`.
  static const Map<String, String> legacyDocs = {
    'prefs': 'settings/prefs',
    'notifications': 'settings/notifications',
    'ai_preferences': 'settings/ai_preferences',
    'digital_wellbeing': 'settings/digital_wellbeing',
    'recommendations': 'settings/recommendations',
    'ai_personalization': 'settings/ai_personalization',
    'agent_config': 'ai_settings/agent_config',
  };

  /// Categories that deployed Cloud Functions still read from their old
  /// documents (notifications.ts, securityMail.ts, aiGateway.ts). Writes to
  /// these categories are copied there in the same batch. The functions in
  /// functions/src now read `user_settings` first; once they are deployed
  /// these mirrors can be dropped.
  static const Map<String, String> serverMirrors = {
    'notifications': 'settings/notifications',
    'aiAgent': 'ai_settings/agent_config',
  };

  /// Keys renamed inside the canonical doc: category -> {old: new}.
  static const Map<String, Map<String, String>> renamedKeys = {
    'notifications': {
      'inAppBannerEnabled': 'inAppEnabled',
      'showNumberBadges': 'showBadges',
      'notificationTone': 'ringtone',
    },
  };

  /// Platform ids a user may pick as Post / Go Live destinations.
  static const String publishing = 'publishing';
  static const String crossPostPlatforms = 'crossPostPlatforms';
  static const String liveSimulcastPlatforms = 'liveSimulcastPlatforms';

  static Map<String, dynamic> defaults() {
    return {
      'profile': {
        'displayName': '',
        'bio': '',
        'creatorTags': <dynamic>[],
        'pronouns': '',
        'category': '',
        'accountType': 'personal',
        'links': <dynamic>[],
        'pinnedPostIds': <dynamic>[],
        'location': '',
        'isPrivate': false,
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
        'pushEnabled': true,
        'emailEnabled': true,
        'inAppEnabled': true,
        'soundEnabled': true,
        'ringtone': 'celestial',
        'vibrateEnabled': true,
        'ringForLive': true,
        'showBadges': true,
        'desktopEnabled': true,
        'mobileEnabled': true,
        'previewMessageContent': true,
        'dndEnabled': false,
        'quietHoursStart': 22,
        'quietHoursEnd': 8,
        'categoryOverrides': <String, dynamic>{},
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
      'aiAgent': <String, dynamic>{},
      'aiPersonalization': {
        'learningEnabled': false,
      },
      publishing: {
        crossPostPlatforms: <String>[],
        liveSimulcastPlatforms: <String>[],
      },
      'security': {
        'requirePasskey': false,
        'loginAlerts': true,
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
        // themeMode ('light' | 'dark' | 'system') has no default on purpose:
        // until the account picks one, the device's cached choice applies.
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
      'wellbeing': <String, dynamic>{},
      'recommendations': <String, dynamic>{},
    };
  }

  /// Deep-merges [current] over [base]; nested maps merge, anything else in
  /// [current] replaces the base value. Neither input is modified.
  static Map<String, dynamic> merge(Map<String, dynamic> base, Map<String, dynamic> current) {
    final result = <String, dynamic>{};
    base.forEach((k, v) => result[k] = v is Map ? Map<String, dynamic>.from(v) : v);
    current.forEach((key, value) {
      final existing = result[key];
      if (value is Map && existing is Map) {
        result[key] = merge(Map<String, dynamic>.from(existing), Map<String, dynamic>.from(value));
      } else if (value is Map) {
        result[key] = Map<String, dynamic>.from(value);
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  /// The stored doc merged over [defaults], with renamed keys read forward,
  /// so readers always see the current key names.
  static Map<String, dynamic> resolve(Map<String, dynamic>? stored) {
    final data = Map<String, dynamic>.from(stored ?? const {});
    renamedKeys.forEach((category, renames) {
      final section = data[category];
      if (section is! Map) return;
      final copy = Map<String, dynamic>.from(section);
      renames.forEach((oldKey, newKey) {
        if (copy.containsKey(oldKey) && !copy.containsKey(newKey)) copy[newKey] = copy[oldKey];
        copy.remove(oldKey);
      });
      data[category] = copy;
    });
    data.remove(schemaKey);
    return merge(defaults(), data);
  }

  /// Returns the patch that carries [legacy] documents (keyed like
  /// [legacyDocs]) into the canonical doc [stored]. A legacy value only fills
  /// a field the canonical doc does not have yet, except for the server-read
  /// notification doc, whose values were the ones actually enforced and so
  /// win over the renamed canonical keys. The patch also deletes renamed keys
  /// and stamps [schemaKey].
  static Map<String, dynamic> foldLegacy(
    Map<String, dynamic> stored,
    Map<String, Map<String, dynamic>> legacy,
  ) {
    final patch = <String, Map<String, dynamic>>{};

    bool has(String category, String key) {
      final section = stored[category];
      return section is Map && section.containsKey(key);
    }

    void fill(String category, String key, dynamic value, {bool force = false}) {
      if (value == null) return;
      if (!force && has(category, key)) return;
      final section = patch.putIfAbsent(category, () => <String, dynamic>{});
      if (!force && section.containsKey(key)) return;
      section[key] = value;
    }

    // Renamed canonical keys: the legacy notification doc wins, then the old
    // canonical key.
    final notifDoc = legacy['notifications'] ?? const <String, dynamic>{};
    renamedKeys.forEach((category, renames) {
      final section = stored[category];
      renames.forEach((oldKey, newKey) {
        final fromServer = category == 'notifications' ? notifDoc[newKey] : null;
        if (fromServer != null) {
          fill(category, newKey, fromServer, force: true);
        } else if (section is Map && section.containsKey(oldKey) && !has(category, newKey)) {
          fill(category, newKey, section[oldKey]);
        }
        if (section is Map && section.containsKey(oldKey)) {
          patch.putIfAbsent(category, () => <String, dynamic>{})[oldKey] = FieldValue.delete();
        }
      });
    });

    // users/{uid}/settings/notifications — everything it holds.
    notifDoc.forEach((k, v) => fill('notifications', k, v, force: true));

    // users/{uid}/settings/prefs — the old AppSettings store.
    final prefs = legacy['prefs'] ?? const <String, dynamic>{};
    for (final k in const ['requirePasskey', 'loginAlerts']) {
      fill('security', k, prefs[k]);
    }
    for (final k in const [
      'profileVisibility',
      'messagePermissions',
      'onlineVisibility',
      'readReceipts',
      'typingStatus',
      'dataRetentionForever',
    ]) {
      fill('privacy', k, prefs[k]);
    }
    fill('storage', 'allowMediaAutoDownload', prefs['allowMediaAutoDownload']);
    for (final k in const ['aiEnabled', 'aiSuggestions', 'autoMode', 'backgroundAgentEnabled', 'aiPersonalization']) {
      fill('ai', k, prefs[k]);
    }
    final voice = prefs['voiceSelection'];
    if (voice is String && voice.isNotEmpty && voice != 'default') fill('ai', 'selectedVoice', voice);
    fill('appearance', 'language', prefs['language']);

    // users/{uid}/settings/ai_preferences — voice assistant choices.
    final aiPrefs = legacy['ai_preferences'] ?? const <String, dynamic>{};
    fill('ai', 'selectedVoice', aiPrefs['selectedVoice'], force: aiPrefs['selectedVoice'] != null);
    fill('ai', 'selectedModel', aiPrefs['selectedModel']);

    void fillAll(String legacyId, String category) {
      final doc = legacy[legacyId];
      if (doc == null) return;
      doc.forEach((k, v) => fill(category, k, v));
    }

    fillAll('digital_wellbeing', 'wellbeing');
    fillAll('recommendations', 'recommendations');
    fillAll('ai_personalization', 'aiPersonalization');
    fillAll('agent_config', 'aiAgent');

    return {
      ...patch,
      schemaKey: version,
    };
  }

  /// Read a category map from resolved settings.
  static Map<String, dynamic> category(Map<String, dynamic> settings, String name) {
    final section = settings[name];
    return section is Map ? Map<String, dynamic>.from(section) : <String, dynamic>{};
  }

  /// Read a string list (e.g. publishing.crossPostPlatforms).
  static List<String> stringList(Map<String, dynamic> section, String key) {
    final v = section[key];
    return v is List ? v.whereType<String>().toList() : <String>[];
  }
}
