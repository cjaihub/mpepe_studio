import 'package:flutter/material.dart';

/// Single searchable setting item in Oneova platform
class SettingsSearchItem {
  final String id;
  final String title;
  final String subtitle;
  final String category;
  final String route;
  final IconData icon;
  final List<String> keywords;
  final String? settingKey;

  const SettingsSearchItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.route,
    required this.icon,
    required this.keywords,
    this.settingKey,
  });
}

/// Search result pairing an item with its similarity match score
class SettingsSearchResult {
  final SettingsSearchItem item;
  final double score; // 0.0 - 1.0
  final String matchedTerm;

  const SettingsSearchResult({
    required this.item,
    required this.score,
    required this.matchedTerm,
  });
}

/// High-performance similarity and fuzzy search engine for all platform settings
class SettingsSearchEngine {
  static final List<SettingsSearchItem> registry = [
    // 1. Account & Profile
    const SettingsSearchItem(
      id: 'profile_name',
      title: 'Profile Name & Display Handle',
      subtitle: 'Change your public creator name, stage handle, and bio',
      category: 'Profile',
      route: '/settings/profile',
      icon: Icons.person_rounded,
      keywords: ['name', 'handle', 'username', 'bio', 'account', 'identity', 'profile', 'avatar'],
      settingKey: 'displayName',
    ),
    const SettingsSearchItem(
      id: 'profile_avatar',
      title: 'Avatar & Studio Branding',
      subtitle: 'Update your official studio picture and badge verification',
      category: 'Profile',
      route: '/settings/profile',
      icon: Icons.photo_camera_rounded,
      keywords: ['photo', 'picture', 'image', 'logo', 'badge', 'verified', 'brand'],
    ),

    // 2. Chat & Messaging
    const SettingsSearchItem(
      id: 'chat_density',
      title: 'Bubble Text Density & Font Size',
      subtitle: 'Switch between Compact (12px), Classic (13px), and Spacious (14.5px)',
      category: 'Chat & Messaging',
      route: '/settings/chat',
      icon: Icons.format_size_rounded,
      keywords: ['font', 'text', 'size', 'density', 'bubble', 'compact', 'reading', 'letters'],
      settingKey: 'bubbleFontSize',
    ),
    const SettingsSearchItem(
      id: 'chat_swipe_reply',
      title: 'Swipe-to-Reply & Gestures',
      subtitle: 'Swipe horizontally on bubbles to quote and reply with glowing pink aura',
      category: 'Chat & Messaging',
      route: '/settings/chat',
      icon: Icons.swipe_rounded,
      keywords: ['swipe', 'reply', 'quote', 'gestures', 'double tap', 'reaction', 'heart'],
      settingKey: 'smoothAnimations',
    ),
    const SettingsSearchItem(
      id: 'chat_ai_fab',
      title: 'AI Studio Companion FAB',
      subtitle: 'Floating AI copilot button on chat inbox for instant prompts',
      category: 'Chat & Messaging',
      route: '/settings/chat',
      icon: Icons.auto_awesome_rounded,
      keywords: ['ai', 'fab', 'floating', 'companion', 'bot', 'assistant', 'button'],
      settingKey: 'showAiStudioFab',
    ),
    const SettingsSearchItem(
      id: 'chat_compose_fab',
      title: 'Compose Message FAB & Alignment',
      subtitle: 'Align the primary "+" new conversation button left or right',
      category: 'Chat & Messaging',
      route: '/settings/chat',
      icon: Icons.add_comment_rounded,
      keywords: ['compose', 'new chat', 'plus', 'add', 'fab', 'alignment', 'left', 'right'],
      settingKey: 'showComposeFab',
    ),

    // 3. Notifications & Tone
    const SettingsSearchItem(
      id: 'notif_tone',
      title: 'Notification Sound & Chime Tone',
      subtitle: 'Choose between Oneova Celestial, Studio Pop, Soft Bloom, Executive Ping, or Silent',
      category: 'Notifications',
      route: '/settings/notifications',
      icon: Icons.music_note_rounded,
      keywords: ['sound', 'tone', 'chime', 'ringtone', 'audio', 'pop', 'ping', 'celestial', 'alert', 'volume', 'silent'],
      settingKey: 'notificationTone',
    ),
    const SettingsSearchItem(
      id: 'notif_banner',
      title: 'In-App Overlay Cards & Banners',
      subtitle: 'High-contrast floating push alert cards when inside other screens',
      category: 'Notifications',
      route: '/settings/notifications',
      icon: Icons.aspect_ratio_rounded,
      keywords: ['banner', 'overlay', 'popup', 'alert', 'card', 'preview', 'heads up'],
      settingKey: 'inAppBannerEnabled',
    ),
    const SettingsSearchItem(
      id: 'notif_push',
      title: 'System Push Notifications',
      subtitle: 'Receive background notifications even when phone display is off',
      category: 'Notifications',
      route: '/settings/notifications',
      icon: Icons.notifications_active_rounded,
      keywords: ['push', 'system', 'android', 'notification', 'background', 'lockscreen', 'alerts'],
      settingKey: 'uploadAlerts',
    ),
    const SettingsSearchItem(
      id: 'notif_number_badges',
      title: 'Live Header & Nav Number Badges',
      subtitle: 'Show unread message counts in brand pink on bottom navigation',
      category: 'Notifications',
      route: '/settings/notifications',
      icon: Icons.mark_chat_unread_rounded,
      keywords: ['badges', 'unread', 'counter', 'dots', 'pink dot', 'pill', 'numbers'],
      settingKey: 'showNumberBadges',
    ),

    // 4. Privacy, Security & Oneova Shield
    const SettingsSearchItem(
      id: 'sec_shield_e2ee',
      title: 'Oneova Shield E2EE Verification',
      subtitle: 'Verify cryptographic safety numbers and 60-digit fingerprint keys',
      category: 'Privacy & Security',
      route: '/settings/privacy',
      icon: Icons.verified_user_rounded,
      keywords: ['shield', 'e2ee', 'encryption', 'fingerprint', 'safety number', 'keys', 'crypto'],
    ),
    const SettingsSearchItem(
      id: 'sec_2fa',
      title: 'Two-Factor Authentication (2FA)',
      subtitle: 'Arm your creator account with secondary verification code requirement',
      category: 'Privacy & Security',
      route: '/settings/privacy',
      icon: Icons.security_rounded,
      keywords: ['2fa', 'two factor', 'auth', 'passcode', 'verification', 'otp', 'login security'],
      settingKey: 'twoFactorEnabled',
    ),
    const SettingsSearchItem(
      id: 'sec_biometrics',
      title: 'Biometric Lock & Face ID',
      subtitle: 'Require fingerprint or Face ID to unlock studio sessions',
      category: 'Privacy & Security',
      route: '/settings/privacy',
      icon: Icons.fingerprint_rounded,
      keywords: ['biometric', 'fingerprint', 'face id', 'touch id', 'passkey', 'unlock'],
      settingKey: 'requireBiometrics',
    ),
    const SettingsSearchItem(
      id: 'sec_app_pin',
      title: 'Change App Security PIN',
      subtitle: 'Set a private 4-digit code to protect studio workflows',
      category: 'Privacy & Security',
      route: '/settings/privacy',
      icon: Icons.dialpad_rounded,
      keywords: ['pin', 'passcode', 'password', 'code', 'lock', 'secret'],
    ),

    // 5. AI Assistant & Workstation Copilot
    const SettingsSearchItem(
      id: 'ai_model',
      title: 'AI Intelligence Engine & Model',
      subtitle: 'Configure Gemini Pro multimodal reasoning engine and studio agent',
      category: 'AI Assistant',
      route: '/settings/ai',
      icon: Icons.psychology_rounded,
      keywords: ['ai', 'model', 'gemini', 'engine', 'copilot', 'intelligence', 'gpt', 'llm'],
      settingKey: 'defaultModel',
    ),
    const SettingsSearchItem(
      id: 'ai_tone',
      title: 'Assistant Voice & Persona Tone',
      subtitle: 'Calibrate voice demeanor: Professional, Creative Director, or Executive',
      category: 'AI Assistant',
      route: '/settings/ai',
      icon: Icons.record_voice_over_rounded,
      keywords: ['voice', 'tone', 'persona', 'attitude', 'speech', 'sound', 'talking'],
      settingKey: 'assistantTone',
    ),

    // 6. Platform Integrations
    const SettingsSearchItem(
      id: 'social_yt',
      title: 'YouTube Studio Connect',
      subtitle: 'Sync channel uploads, latest comments, and analytics directly to inbox',
      category: 'Integrations',
      route: '/yt/settings',
      icon: Icons.video_library_rounded,
      keywords: ['youtube', 'google', 'channel', 'video', 'comments', 'subscribers', 'studio'],
      settingKey: 'youtubeAutoSync',
    ),
    const SettingsSearchItem(
      id: 'social_omni',
      title: 'Meta, TikTok & WhatsApp Connect',
      subtitle: 'Manage cross-platform inboxes, DMs, and synchronized comments',
      category: 'Integrations',
      route: '/social_hub',
      icon: Icons.hub_rounded,
      keywords: ['meta', 'instagram', 'tiktok', 'whatsapp', 'facebook', 'social', 'inbox', 'sync'],
    ),
    const SettingsSearchItem(
      id: 'app_desktop_link',
      title: 'Workstation Remote Desktop Connect',
      subtitle: 'Auto-connect to your Mac / PC workstation for video & audio rendering',
      category: 'App Settings',
      route: '/settings/app',
      icon: Icons.desktop_windows_rounded,
      keywords: ['desktop', 'workstation', 'pc', 'mac', 'remote', 'control', 'connect', 'link'],
      settingKey: 'desktopAutoConnect',
    ),

    // 7. Appearance & Storage
    const SettingsSearchItem(
      id: 'app_theme_mode',
      title: 'Appearance: Dark / Light Mode',
      subtitle: 'Toggle between Studio Obsidian Black and Clean Corporate Luxury White',
      category: 'Appearance',
      route: '/settings/app',
      icon: Icons.brightness_4_rounded,
      keywords: ['theme', 'dark', 'light', 'mode', 'appearance', 'colors', 'black', 'white', 'display'],
    ),
    const SettingsSearchItem(
      id: 'app_cache_storage',
      title: 'Cache & Local Media Storage',
      subtitle: 'Inspect cached audio stems, video previews, and free up device space',
      category: 'Storage',
      route: '/settings/app',
      icon: Icons.storage_rounded,
      keywords: ['cache', 'storage', 'memory', 'clean', 'delete', 'disk', 'space', 'download'],
    ),
  ];

  /// Perform similarity match against the entire settings registry
  static List<SettingsSearchResult> search(String query) {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    final queryWords = cleanQuery.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final results = <SettingsSearchResult>[];

    for (final item in registry) {
      double maxScore = 0.0;
      String bestMatchedTerm = '';

      final titleLower = item.title.toLowerCase();
      final subLower = item.subtitle.toLowerCase();
      final catLower = item.category.toLowerCase();

      // 1. Direct query matching on title
      if (titleLower == cleanQuery) {
        maxScore = 1.0;
        bestMatchedTerm = item.title;
      } else if (titleLower.startsWith(cleanQuery)) {
        maxScore = 0.95;
        bestMatchedTerm = item.title;
      } else if (titleLower.contains(cleanQuery)) {
        maxScore = 0.88;
        bestMatchedTerm = item.title;
      }

      // 2. Keyword exact / prefix similarity
      for (final kw in item.keywords) {
        final kwLower = kw.toLowerCase();
        if (kwLower == cleanQuery) {
          if (0.92 > maxScore) {
            maxScore = 0.92;
            bestMatchedTerm = kw;
          }
        } else if (kwLower.startsWith(cleanQuery)) {
          final score = 0.85;
          if (score > maxScore) {
            maxScore = score;
            bestMatchedTerm = kw;
          }
        } else if (kwLower.contains(cleanQuery)) {
          final score = 0.78;
          if (score > maxScore) {
            maxScore = score;
            bestMatchedTerm = kw;
          }
        } else {
          // Token fuzzy similarity
          final sim = _stringSimilarity(cleanQuery, kwLower);
          if (sim > 0.65 && sim * 0.8 > maxScore) {
            maxScore = sim * 0.8;
            bestMatchedTerm = kw;
          }
        }
      }

      // 3. Category matching
      if (catLower.contains(cleanQuery)) {
        if (0.75 > maxScore) {
          maxScore = 0.75;
          bestMatchedTerm = item.category;
        }
      }

      // 4. Subtitle matching
      if (subLower.contains(cleanQuery)) {
        if (0.65 > maxScore) {
          maxScore = 0.65;
          bestMatchedTerm = cleanQuery;
        }
      }

      // Multi-word conjunction check
      if (queryWords.length > 1) {
        int matchedWords = 0;
        for (final w in queryWords) {
          if (titleLower.contains(w) ||
              subLower.contains(w) ||
              catLower.contains(w) ||
              item.keywords.any((k) => k.contains(w))) {
            matchedWords++;
          }
        }
        if (matchedWords == queryWords.length && maxScore < 0.85) {
          maxScore = 0.85;
          bestMatchedTerm = cleanQuery;
        }
      }

      if (maxScore >= 0.5) {
        results.add(SettingsSearchResult(item: item, score: maxScore, matchedTerm: bestMatchedTerm));
      }
    }

    // Sort by relevance score descending
    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }

  /// Levenshtein distance ratio calculation for fuzzy similarity
  static double _stringSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final d = List.generate(
      s1.length + 1,
      (i) => List.filled(s2.length + 1, 0),
    );

    for (int i = 0; i <= s1.length; i++) {
      d[i][0] = i;
    }
    for (int j = 0; j <= s2.length; j++) {
      d[0][j] = j;
    }

    for (int i = 1; i <= s1.length; i++) {
      for (int j = 1; j <= s2.length; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        d[i][j] = [
          d[i - 1][j] + 1,
          d[i][j - 1] + 1,
          d[i - 1][j - 1] + cost,
        ].reduce((curr, next) => curr < next ? curr : next);
      }
    }

    final maxLen = s1.length > s2.length ? s1.length : s2.length;
    return 1.0 - (d[s1.length][s2.length] / maxLen);
  }
}
