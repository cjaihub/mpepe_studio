import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

/// How long before the app auto-locks after being backgrounded (in minutes).
const int kSessionTimeoutMinutes = 5;

final appLifecycleObserverProvider = Provider<AppLifecycleObserver>((ref) {
  return AppLifecycleObserver(ref);
});

/// Watches the app lifecycle. On [AppLifecycleState.resumed], checks if
/// the session has been idle for longer than [kSessionTimeoutMinutes].
/// If so, routes the user back to the lock screen.
///
/// Inject via [WidgetsBinding.instance.addObserver] in main.dart.
class AppLifecycleObserver with WidgetsBindingObserver {
  final Ref _ref;

  AppLifecycleObserver(this._ref);

  /// Call this once during app startup to register the observer
  void register() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Call this on app disposal (usually never for long-lived apps)
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _saveLastActiveTime();
        break;

      case AppLifecycleState.resumed:
        _checkSessionTimeout();
        break;

      default:
        break;
    }
  }

  Future<void> _saveLastActiveTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'last_active_time',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  Future<void> _checkSessionTimeout() async {
    // By default, Oneova keeps sessions permanently unlocked to allow seamless viewing.
    // Biometric prompt only applies if the user explicitly opted-in to App Lock in Settings.
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final bioLockEnabled = prefs.getBool('oneova_biometric_app_lock_enabled') ?? false;
      if (!bioLockEnabled) return;

      final lastActiveMs = prefs.getInt('last_active_time');
      if (lastActiveMs == null) return;
      final elapsed = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastActiveMs));
      if (elapsed.inMinutes >= 15) {
        _navigateToLock();
      }
    } catch (_) {}
  }

  void _navigateToLock() {
    // Use GoRouter's global navigation via the rootNavigatorKey
    final context = _ref.read(_navigatorKeyProvider)?.currentContext;
    if (context != null && context.mounted) {
      context.go('/auth/locked');
    }
  }
}

/// Holds a reference to the root navigator key so the observer can navigate
/// without a BuildContext.
final _navigatorKeyProvider = Provider<GlobalKey<NavigatorState>?>((ref) => null);

/// The actual navigator key — set this in main.dart and override the provider
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Provider that exposes the rootNavigatorKey for the observer
final navigatorKeyProvider = Provider<GlobalKey<NavigatorState>>((ref) {
  return rootNavigatorKey;
});
