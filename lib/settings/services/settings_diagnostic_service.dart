import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../shared/services/oneova_sound_service.dart';

/// Severity level for settings and platform account diagnostics
enum DiagnosticSeverity {
  info,
  warning,
  error,
}

/// Model representing a detected account or settings issue
class DiagnosticIssue {
  final String id;
  final String category;
  final String title;
  final String description;
  final DiagnosticSeverity severity;
  final String settingKey;
  final String route;
  final bool canAutoFix;
  final String fixLabel;

  const DiagnosticIssue({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.severity,
    required this.settingKey,
    required this.route,
    this.canAutoFix = true,
    this.fixLabel = 'AI Auto-Fix',
  });
}

/// Overall report on user account and settings integrity
class AccountHealthReport {
  final int healthScore; // 0 - 100
  final bool isMonitoringActive;
  final List<DiagnosticIssue> issues;
  final DateTime lastChecked;

  const AccountHealthReport({
    required this.healthScore,
    required this.isMonitoringActive,
    required this.issues,
    required this.lastChecked,
  });

  bool get hasIssues => issues.isNotEmpty;
  bool get hasErrors => issues.any((i) => i.severity == DiagnosticSeverity.error);
  bool get hasWarnings => issues.any((i) => i.severity == DiagnosticSeverity.warning);
}

/// Provider that monitors user settings in real-time and computes account diagnostics
final accountHealthProvider = Provider<AccountHealthReport>((ref) {
  final settingsAsync = ref.watch(settingsProvider);
  final settings = settingsAsync.value ?? {};

  final notifSettings = settings['notifications'] as Map<String, dynamic>? ?? {};
  final privacySettings = settings['privacy'] as Map<String, dynamic>? ?? {};
  final chatSettings = settings['chat'] as Map<String, dynamic>? ?? {};
  final appSettings = settings['app'] as Map<String, dynamic>? ?? {};

  final issues = <DiagnosticIssue>[];

  // 1. Notification alerts check
  final bool inAppBanner = notifSettings['inAppBannerEnabled'] ?? true;
  final bool uploadAlerts = notifSettings['uploadAlerts'] ?? true;
  if (!inAppBanner || !uploadAlerts) {
    issues.add(
      const DiagnosticIssue(
        id: 'notif_muted',
        category: 'notifications',
        title: 'Critical Alerts Subdued',
        description: 'In-app notification banners or upload alerts are disabled. You may miss live drops.',
        severity: DiagnosticSeverity.warning,
        settingKey: 'inAppBannerEnabled',
        route: '/settings/notifications',
        canAutoFix: true,
        fixLabel: 'Enable Alerts',
      ),
    );
  }

  // 2. Security & 2FA check
  final bool twoFactor = privacySettings['twoFactorEnabled'] ?? false;
  final bool requireBiometrics = privacySettings['requireBiometrics'] ?? false;
  if (!twoFactor && !requireBiometrics) {
    issues.add(
      const DiagnosticIssue(
        id: 'security_posture',
        category: 'privacy',
        title: 'Two-Factor / Biometrics Inactive',
        description: 'Creator account is operating with basic auth. Protect your studio assets.',
        severity: DiagnosticSeverity.warning,
        settingKey: 'twoFactorEnabled',
        route: '/settings/privacy',
        canAutoFix: true,
        fixLabel: 'Arm Security',
      ),
    );
  }

  // 3. Chat experience density check
  final bool smoothAnim = chatSettings['smoothAnimations'] ?? true;
  if (!smoothAnim) {
    issues.add(
      const DiagnosticIssue(
        id: 'chat_smoothness',
        category: 'chat',
        title: 'Motion & Animations Disabled',
        description: 'Dynamic UI transitions in chats are off, causing abrupt visual jumps.',
        severity: DiagnosticSeverity.info,
        settingKey: 'smoothAnimations',
        route: '/settings/chat',
        canAutoFix: true,
        fixLabel: 'Restore Smoothness',
      ),
    );
  }

  // 4. Communication history check
  final bool saveHistory = appSettings['saveHistory'] ?? true;
  if (!saveHistory) {
    issues.add(
      const DiagnosticIssue(
        id: 'chat_history_off',
        category: 'app',
        title: 'Chat History Ephemeral',
        description: 'Session history is set to auto-wipe. Conversations will not persist on device.',
        severity: DiagnosticSeverity.warning,
        settingKey: 'saveHistory',
        route: '/settings/app',
        canAutoFix: true,
        fixLabel: 'Persist History',
      ),
    );
  }

  // Compute overall score
  int score = 100;
  for (final issue in issues) {
    if (issue.severity == DiagnosticSeverity.error) {
      score -= 20;
    } else if (issue.severity == DiagnosticSeverity.warning) {
      score -= 10;
    } else {
      score -= 4;
    }
  }
  score = score.clamp(0, 100);

  return AccountHealthReport(
    healthScore: score,
    isMonitoringActive: true,
    issues: issues,
    lastChecked: DateTime.now(),
  );
});

/// Service providing autonomous fixes for detected diagnostics
class SettingsDiagnosticService {
  /// Fix a single issue automatically in the background
  static Future<void> autoFixIssue(WidgetRef ref, String issueId) async {
    HapticFeedback.mediumImpact();

    switch (issueId) {
      case 'notif_muted':
        await ref.read(settingsProvider.notifier).updateCategory('notifications', {
          'inAppBannerEnabled': true,
          'uploadAlerts': true,
          'commentsMentions': true,
        });
        OneOvaSoundService().playNotificationChime('studio_pop');
        break;

      case 'security_posture':
        await ref.read(settingsProvider.notifier).updateCategory('privacy', {
          'twoFactorEnabled': true,
          'requireBiometrics': true,
        });
        OneOvaSoundService().playNotificationChime('executive');
        break;

      case 'chat_smoothness':
        await ref.read(settingsProvider.notifier).updateSetting('chat', 'smoothAnimations', true);
        OneOvaSoundService().playNotificationChime('soft_bloom');
        break;

      case 'chat_history_off':
        await ref.read(settingsProvider.notifier).updateSetting('app', 'saveHistory', true);
        OneOvaSoundService().playNotificationChime('studio_pop');
        break;
    }
  }

  /// Fix all fixable issues simultaneously with one tap
  static Future<void> autoFixAll(WidgetRef ref) async {
    HapticFeedback.heavyImpact();

    final health = ref.read(accountHealthProvider);
    for (final issue in health.issues) {
      if (issue.canAutoFix) {
        await autoFixIssue(ref, issue.id);
      }
    }

    OneOvaSoundService().playNotificationChime('celestial');
  }
}
