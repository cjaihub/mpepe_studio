import 'package:cloud_firestore/cloud_firestore.dart';

/// Ring styles a user can choose for in-app alerts. `celestial` etc. map onto
/// [OneOvaSoundService] tones; `mute` is haptics only.
const List<String> kNotificationTones = [
  'celestial',
  'studio_pop',
  'soft_bloom',
  'executive',
  'voice_cue',
  'mute',
];

class NotificationPreferences {
  final bool pushEnabled;
  final bool emailEnabled;
  final bool inAppEnabled;

  // Audio & Haptics
  final bool soundEnabled;
  final String ringtone;
  final bool vibrateEnabled;

  /// Go-live alerts from people you follow ring twice with a stronger haptic.
  final bool ringForLive;

  /// Unread counters on the bell / nav.
  final bool showBadges;

  // Platform Overrides
  final bool desktopEnabled;
  final bool mobileEnabled;

  // Privacy
  final bool previewMessageContent;

  // Quiet Hours (DND)
  final bool dndEnabled;
  final int quietHoursStart; // 0-23
  final int quietHoursEnd; // 0-23

  // Per-category overrides, keyed by AppNotificationCategory.name
  final Map<String, bool> categoryOverrides;

  /// Block other apps' notifications from popping up inside Oneova (and auto-dismiss them).
  final bool blockExternalAppNotifications;

  /// Specific external app package names blocked by the user (e.g. 'com.whatsapp').
  final List<String> blockedExternalPackages;

  /// Whether to show floating drop-down pop-up cards on top of the screen.
  /// Defaults to `false` so alerts ring & save quietly without interrupting the screen.
  final bool showScreenPopups;

  /// Information sources the user does not want alerts or AI learning from
  /// (e.g. 'external_apps', 'ai_suggestions', 'promotions', 'social_likes', 'comments', 'live_streams', 'system').
  final List<String> mutedSources;

  /// Specific sender names, keywords, or topics the user never wants information from.
  final List<String> mutedKeywords;

  NotificationPreferences({
    this.pushEnabled = true,
    this.emailEnabled = true,
    this.inAppEnabled = true,
    this.soundEnabled = true,
    this.ringtone = 'celestial',
    this.vibrateEnabled = true,
    this.ringForLive = true,
    this.showBadges = true,
    this.desktopEnabled = true,
    this.mobileEnabled = true,
    this.previewMessageContent = true,
    this.dndEnabled = false,
    this.quietHoursStart = 22,
    this.quietHoursEnd = 8,
    this.categoryOverrides = const {},
    this.blockExternalAppNotifications = false,
    this.blockedExternalPackages = const [],
    this.showScreenPopups = false,
    this.mutedSources = const [],
    this.mutedKeywords = const [],
  });

  factory NotificationPreferences.fromFirestore(DocumentSnapshot doc) {
    if (!doc.exists) return NotificationPreferences();
    return NotificationPreferences.fromMap(doc.data() as Map<String, dynamic>? ?? {});
  }

  /// From the `notifications` category of `user_settings/{uid}`.
  factory NotificationPreferences.fromMap(Map<String, dynamic> data) {
    final tone = data['ringtone'] as String?;
    final rawBlocked = data['blockedExternalPackages'];
    final blockedList = rawBlocked is Iterable
        ? rawBlocked.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : const <String>[];
    final rawMutedSources = data['mutedSources'];
    final mutedSourcesList = rawMutedSources is Iterable
        ? rawMutedSources.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : const <String>[];
    final rawMutedKeywords = data['mutedKeywords'];
    final mutedKeywordsList = rawMutedKeywords is Iterable
        ? rawMutedKeywords.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : const <String>[];
    return NotificationPreferences(
      pushEnabled: data['pushEnabled'] ?? true,
      emailEnabled: data['emailEnabled'] ?? true,
      inAppEnabled: data['inAppEnabled'] ?? true,
      soundEnabled: data['soundEnabled'] ?? true,
      ringtone: (tone == null || tone == 'default') ? 'celestial' : tone,
      vibrateEnabled: data['vibrateEnabled'] ?? true,
      ringForLive: data['ringForLive'] ?? true,
      showBadges: data['showBadges'] ?? true,
      desktopEnabled: data['desktopEnabled'] ?? true,
      mobileEnabled: data['mobileEnabled'] ?? true,
      previewMessageContent: data['previewMessageContent'] ?? true,
      dndEnabled: data['dndEnabled'] ?? false,
      quietHoursStart: data['quietHoursStart'] ?? 22,
      quietHoursEnd: data['quietHoursEnd'] ?? 8,
      categoryOverrides: Map<String, bool>.from(data['categoryOverrides'] ?? {}),
      blockExternalAppNotifications: data['blockExternalAppNotifications'] == true,
      blockedExternalPackages: blockedList,
      showScreenPopups: data['showScreenPopups'] == true,
      mutedSources: mutedSourcesList,
      mutedKeywords: mutedKeywordsList,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'pushEnabled': pushEnabled,
      'emailEnabled': emailEnabled,
      'inAppEnabled': inAppEnabled,
      'soundEnabled': soundEnabled,
      'ringtone': ringtone,
      'vibrateEnabled': vibrateEnabled,
      'ringForLive': ringForLive,
      'showBadges': showBadges,
      'desktopEnabled': desktopEnabled,
      'mobileEnabled': mobileEnabled,
      'previewMessageContent': previewMessageContent,
      'dndEnabled': dndEnabled,
      'quietHoursStart': quietHoursStart,
      'quietHoursEnd': quietHoursEnd,
      'categoryOverrides': categoryOverrides,
      'blockExternalAppNotifications': blockExternalAppNotifications,
      'blockedExternalPackages': blockedExternalPackages,
      'showScreenPopups': showScreenPopups,
      'mutedSources': mutedSources,
      'mutedKeywords': mutedKeywords,
    };
  }

  NotificationPreferences copyWith({
    bool? pushEnabled,
    bool? emailEnabled,
    bool? inAppEnabled,
    bool? soundEnabled,
    String? ringtone,
    bool? vibrateEnabled,
    bool? ringForLive,
    bool? showBadges,
    bool? desktopEnabled,
    bool? mobileEnabled,
    bool? previewMessageContent,
    bool? dndEnabled,
    int? quietHoursStart,
    int? quietHoursEnd,
    Map<String, bool>? categoryOverrides,
    bool? blockExternalAppNotifications,
    List<String>? blockedExternalPackages,
    bool? showScreenPopups,
    List<String>? mutedSources,
    List<String>? mutedKeywords,
  }) {
    return NotificationPreferences(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      emailEnabled: emailEnabled ?? this.emailEnabled,
      inAppEnabled: inAppEnabled ?? this.inAppEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      ringtone: ringtone ?? this.ringtone,
      vibrateEnabled: vibrateEnabled ?? this.vibrateEnabled,
      ringForLive: ringForLive ?? this.ringForLive,
      showBadges: showBadges ?? this.showBadges,
      desktopEnabled: desktopEnabled ?? this.desktopEnabled,
      mobileEnabled: mobileEnabled ?? this.mobileEnabled,
      previewMessageContent: previewMessageContent ?? this.previewMessageContent,
      dndEnabled: dndEnabled ?? this.dndEnabled,
      quietHoursStart: quietHoursStart ?? this.quietHoursStart,
      quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
      categoryOverrides: categoryOverrides ?? this.categoryOverrides,
      blockExternalAppNotifications:
          blockExternalAppNotifications ?? this.blockExternalAppNotifications,
      blockedExternalPackages:
          blockedExternalPackages ?? this.blockedExternalPackages,
      showScreenPopups: showScreenPopups ?? this.showScreenPopups,
      mutedSources: mutedSources ?? this.mutedSources,
      mutedKeywords: mutedKeywords ?? this.mutedKeywords,
    );
  }

  bool isExternalPackageBlocked(String packageName) {
    if (blockExternalAppNotifications || isSourceMuted('external_apps')) return true;
    final clean = packageName.trim().toLowerCase();
    if (clean.isEmpty) return false;
    return blockedExternalPackages.any((p) {
      final b = p.trim().toLowerCase();
      return b == clean || clean.contains(b) || b.contains(clean);
    });
  }

  bool isSourceMuted(String sourceId) {
    final clean = sourceId.trim().toLowerCase();
    return mutedSources.any((s) => s.trim().toLowerCase() == clean);
  }

  bool isTextOrSenderMuted({
    String? title,
    String? body,
    String? sender,
    String? appName,
  }) {
    if (mutedKeywords.isEmpty) return false;
    final haystack = [
      title ?? '',
      body ?? '',
      sender ?? '',
      appName ?? '',
    ].join(' ').toLowerCase();
    if (haystack.trim().isEmpty) return false;
    for (final kw in mutedKeywords) {
      final k = kw.trim().toLowerCase();
      if (k.isNotEmpty && haystack.contains(k)) return true;
    }
    return false;
  }

  bool shouldIgnoreNotification({
    String? category,
    String? packageName,
    String? appName,
    String? sender,
    String? title,
    String? body,
    bool isExternal = false,
  }) {
    if (isExternal) {
      if (isExternalPackageBlocked(packageName ?? '') ||
          isExternalPackageBlocked(appName ?? '')) {
        return true;
      }
    }
    if (category != null && category.isNotEmpty) {
      if (!isCategoryEnabled(category)) return true;
      if ((category == 'aiSuggestion' || category == 'automation') &&
          isSourceMuted('ai_suggestions')) {
        return true;
      }
      if ((category == 'recommendation' || category == 'profileTip') &&
          isSourceMuted('promotions')) {
        return true;
      }
      if ((category == 'like' || category == 'reaction' || category == 'newFollower') &&
          isSourceMuted('social_likes')) {
        return true;
      }
      if ((category == 'comment' || category == 'reply' || category == 'mention') &&
          isSourceMuted('comments')) {
        return true;
      }
      if (category == 'live' && isSourceMuted('live_streams')) {
        return true;
      }
    }
    return isTextOrSenderMuted(
      title: title,
      body: body,
      sender: sender,
      appName: appName,
    );
  }

  /// Whether a category is switched on (everything defaults to on).
  bool isCategoryEnabled(String categoryName) => categoryOverrides[categoryName] != false;

  /// Quiet hours window, handling ranges that wrap past midnight (22 → 8)
  /// as well as same-day ranges (13 → 15).
  bool isInQuietHours([DateTime? at]) {
    if (!dndEnabled || quietHoursStart == quietHoursEnd) return false;
    final hour = (at ?? DateTime.now()).hour;
    if (quietHoursStart < quietHoursEnd) {
      return hour >= quietHoursStart && hour < quietHoursEnd;
    }
    return hour >= quietHoursStart || hour < quietHoursEnd;
  }

  bool isMutedForCategory(String categoryName) {
    if (isInQuietHours()) return true;
    return !isCategoryEnabled(categoryName);
  }
}
