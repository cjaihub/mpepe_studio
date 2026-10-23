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
  });

  factory NotificationPreferences.fromFirestore(DocumentSnapshot doc) {
    if (!doc.exists) return NotificationPreferences();
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final tone = data['ringtone'] as String?;
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
