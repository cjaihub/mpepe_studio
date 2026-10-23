import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../observability/telemetry_service.dart';

enum AppFeature {
  reelsV2('reels_v2'),
  creatorStudio('creator_studio'),
  aiVideo('ai_video'),
  aiCopilot('ai_copilot'),
  recommendationsV2('recommendations_v2'),
  liveV2('live_v2'),
  liveStudioV2('live_studio_v2'),
  subscriptions('subscriptions'),
  series('series'),
  communities('communities'),
  advancedSearch('advanced_search'),
  newProfile('new_profile'),
  newNotifications('new_notifications'),
  enterprise('enterprise'),
  omnichannel('omnichannel'),
  businessProfiles('business_profiles');

  final String key;
  const AppFeature(this.key);
}

enum RolloutEnvironment {
  internal,
  staging,
  production,
}

/// Represents the rollout rules for a specific feature.
/// Synced from Firebase Remote Config; falls back to safe defaults.
class FeatureConfig {
  final bool enabledGlobally;
  final RolloutEnvironment minimumEnvironment;
  final List<String> allowedUserIds;
  final bool requireCreator;
  final int percentageRollout; // 0–100

  FeatureConfig({
    this.enabledGlobally = false,
    this.minimumEnvironment = RolloutEnvironment.production,
    this.allowedUserIds = const [],
    this.requireCreator = false,
    this.percentageRollout = 0,
  });

  factory FeatureConfig.fromJson(Map<String, dynamic> json) {
    return FeatureConfig(
      enabledGlobally: json['enabledGlobally'] as bool? ?? false,
      minimumEnvironment: RolloutEnvironment.values.firstWhere(
        (e) => e.name == json['minimumEnvironment'],
        orElse: () => RolloutEnvironment.production,
      ),
      allowedUserIds: (json['allowedUserIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      requireCreator: json['requireCreator'] as bool? ?? false,
      percentageRollout: json['percentageRollout'] as int? ?? 0,
    );
  }
}

final featureFlagServiceProvider = Provider<FeatureFlagService>((ref) {
  return FeatureFlagService(ref.read(telemetryServiceProvider));
});

/// Evaluates feature flags based on the user's context.
///
/// Configuration is sourced exclusively from Firebase Remote Config.
/// Falls back to production-safe defaults (disabled) when offline or
/// when a feature key is not yet seeded in Remote Config.
class FeatureFlagService {
  final TelemetryService _telemetry;

  /// Live configs loaded from Remote Config. Safe-defaults to disabled.
  final Map<AppFeature, FeatureConfig> _configs = {};

  bool _initialized = false;

  FeatureFlagService(this._telemetry);

  // ─────────────────────────────────────────────────────────────────────
  // Remote Config sync
  // ─────────────────────────────────────────────────────────────────────

  /// Must be called once at app startup (e.g., in main() or a boot provider).
  /// Fetches the latest flag config from Firebase Remote Config with a 1-hour
  /// minimum fetch interval in production (0 in debug for rapid iteration).
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final rc = FirebaseRemoteConfig.instance;

      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: kDebugMode
            ? Duration.zero
            : const Duration(hours: 1),
      ));

      // Seed production-safe defaults (all disabled) so the app never
      // crashes if Remote Config is unreachable on first launch.
      final defaults = {
        for (final f in AppFeature.values)
          'flag_${f.key}': jsonEncode({'enabledGlobally': false}),
      };
      await rc.setDefaults(defaults);

      // Fetch & activate. On failure, cached / default values are used.
      await rc.fetchAndActivate();

      // Parse each feature flag from Remote Config
      for (final feature in AppFeature.values) {
        final raw = rc.getString('flag_${feature.key}');
        if (raw.isNotEmpty) {
          try {
            final json = jsonDecode(raw) as Map<String, dynamic>;
            _configs[feature] = FeatureConfig.fromJson(json);
          } catch (e) {
            debugPrint('[FeatureFlagService] Failed to parse ${feature.key}: $e');
          }
        }
      }

      _initialized = true;
      debugPrint('[FeatureFlagService] Initialized with ${_configs.length} configs from Remote Config.');
    } catch (e) {
      // Remote Config fetch failed — all flags remain at safe defaults (disabled).
      debugPrint('[FeatureFlagService] Remote Config sync failed, using safe defaults: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Flag evaluation
  // ─────────────────────────────────────────────────────────────────────

  /// Returns true if [feature] is enabled for the currently signed-in user.
  ///
  /// Evaluation order:
  ///   1. Global kill-switch (enabledGlobally = true → always on)
  ///   2. Environment gate (internal overrides all)
  ///   3. Exact UID allow-list
  ///   4. Creator requirement
  ///   5. Percentage rollout (deterministic by UID)
  bool isEnabled(
    AppFeature feature, {
    RolloutEnvironment currentEnvironment = RolloutEnvironment.production,
    bool isUserCreator = false,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    final config = _configs[feature] ?? FeatureConfig(); // safe default = disabled

    // 1. Global on
    if (config.enabledGlobally) return true;

    // 2. Internal environment bypass
    if (currentEnvironment == RolloutEnvironment.internal) return true;

    // All targeting rules require an authenticated user
    if (uid == null) return false;

    // 3. Exact allow-list
    if (config.allowedUserIds.contains(uid)) return true;

    // 4. Creator gate
    if (config.requireCreator && !isUserCreator) return false;

    // 5. Percentage rollout (deterministic — same user always gets same result)
    if (config.percentageRollout > 0) {
      final hash = uid.hashCode.abs() % 100;
      if (hash < config.percentageRollout) return true;
    }

    return false;
  }

  // ─────────────────────────────────────────────────────────────────────
  // Admin override (audited)
  // ─────────────────────────────────────────────────────────────────────

  /// Applies an admin-driven override to a flag config locally.
  /// This does NOT persist — use the Firebase Console to persist changes.
  /// Every call is written to the immutable telemetry/audit trail.
  void updateFlagConfig(AppFeature feature, FeatureConfig newConfig, String adminUid) {
    _configs[feature] = newConfig;

    _telemetry.logEvent('feature_flag_changed', {
      'feature': feature.key,
      'admin_uid': adminUid,
      'enabled_globally': newConfig.enabledGlobally,
      'percentage': newConfig.percentageRollout,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}

