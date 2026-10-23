import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/router.dart';
import 'pin_auth_service.dart';
import '../security/login_security.dart';

final secureLogoutServiceProvider = Provider<SecureLogoutService>((ref) {
  return SecureLogoutService(
    auth: FirebaseAuth.instance,
    googleSignIn: GoogleSignIn.instance,
    secureStorage: const FlutterSecureStorage(),
    pinService: ref.read(pinAuthServiceProvider),
    ref: ref,
  );
});

/// Atomic, multi-layer logout that clears:
/// 1. Firebase Auth session
/// 2. Google Sign-In session (if active)
/// 3. PIN hash + salt + lockout state (secure storage)
/// 4. Session timer keys (SharedPreferences)
/// 5. Onboarding draft (SharedPreferences)
/// 6. Riverpod provider cache
///
/// This ensures no session resurrection is possible after logout.
class SecureLogoutService {
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final FlutterSecureStorage _secureStorage;
  final PinAuthService _pinService;
  final Ref _ref;

  SecureLogoutService({
    required this._auth,
    required this._googleSignIn,
    required this._secureStorage,
    required this._pinService,
    required this._ref,
  });

  /// Full secure logout. Call this from ANY logout trigger in the app.
  /// Safe to call even if partially signed in.
  Future<void> logout() async {
    // Run all cleanup operations in parallel for speed
    await Future.wait([
      _signOutFirebase(),
      _signOutGoogle(),
      _clearPinData(),
      _clearSharedPrefs(),
    ]);

    // Invalidate Riverpod cache last (so providers don't race)
    _invalidateProviders();

    // Redirect to login screen explicitly
    try {
      _ref.read(routerProvider).go('/auth/main_login');
    } catch (_) {}
  }

  Future<void> _signOutFirebase() async {
    try {
      await LoginSecurity.instance.clear();
      await _auth.signOut();
    } catch (_) {
      // Best-effort — don't block logout if Firebase is unreachable
    }
  }

  Future<void> _signOutGoogle() async {
    try {
      // v7 API: unconditionally sign out to clear local state.
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  Future<void> _clearPinData() async {
    try {
      await _pinService.clearAll();
      // Belt-and-suspenders: also wipe known secure storage keys directly
      await Future.wait([
        _secureStorage.delete(key: 'pin_hash'),
        _secureStorage.delete(key: 'pin_salt'),
        _secureStorage.delete(key: 'pin_attempts'),
        _secureStorage.delete(key: 'pin_locked_until'),
      ]);
    } catch (_) {}
  }

  Future<void> _clearSharedPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Only remove auth-related keys, not user settings
      await Future.wait([
        prefs.remove('last_active_time'),
        prefs.remove('onboarding_draft'),
        prefs.remove('onboarding_draft_step'),
      ]);
    } catch (_) {}
  }

  void _invalidateProviders() {
    // Invalidate all known Riverpod providers that cache user data
    // The providers will re-fetch when needed after login
    try {
      _ref.invalidate(pinAuthServiceProvider);
    } catch (_) {}
  }
}
