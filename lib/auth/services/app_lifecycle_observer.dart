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

  // Tracks when the app was last backgrounded
  DateTime? _pausedAt;

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
        // Record when we went to background
        _pausedAt = DateTime.now();
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
    // Only apply to authenticated users
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    DateTime? lastActive = _pausedAt;

    // Fall back to SharedPreferences if in-memory value is gone (e.g. process restart)
    if (lastActive == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final ms = prefs.getInt('last_active_time');
        if (ms != null) {
          lastActive = DateTime.fromMillisecondsSinceEpoch(ms);
        }
      } catch (_) {}
    }

    if (lastActive == null) return;

    final elapsed = DateTime.now().difference(lastActive);
    if (elapsed.inMinutes >= kSessionTimeoutMinutes) {
      // Session expired — navigate to lock screen
      // We use the router's global context via the navigator key
      _navigateToLock();
    }
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
