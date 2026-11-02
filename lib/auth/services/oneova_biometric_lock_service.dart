import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'oneova_biometrics_service.dart';

final oneovaBiometricLockServiceProvider = Provider<OneovaBiometricLockService>((ref) {
  final bioService = ref.watch(oneovaBiometricsServiceProvider);
  return OneovaBiometricLockService(bioService);
});

/// Manages optional Biometric App Lock for Oneova.
///
/// CRITICAL SPEC:
/// By default, Oneova opens directly to the Reel/Feed screen (`/hub/home`)
/// with ZERO biometric barrier, allowing instant entertainment and discovery.
/// Users may optionally toggle "Fingerprint / Face ID App Lock" in Settings.
class OneovaBiometricLockService extends ChangeNotifier {
  static const String prefKey = 'oneova_biometric_app_lock_enabled';
  final OneovaBiometricsService _bioService;

  bool _isLockEnabled = false;
  bool _isCurrentlyUnlocked = true;

  OneovaBiometricLockService(this._bioService) {
    _loadPreference();
  }

  bool get isLockEnabled => _isLockEnabled;
  bool get isCurrentlyUnlocked => _isCurrentlyUnlocked;

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isLockEnabled = prefs.getBool(prefKey) ?? false; // Default: false (open directly to feed)
      notifyListeners();
    } catch (_) {}
  }

  /// Updates whether the user wants the app locked behind fingerprint on resume
  Future<void> setLockEnabled(bool enabled) async {
    _isLockEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefKey, enabled);
    } catch (_) {}
    notifyListeners();
  }

  /// Marks session as locked when going to background (only if user enabled lock)
  void onAppBackgrounded() {
    if (_isLockEnabled) {
      _isCurrentlyUnlocked = false;
      notifyListeners();
    }
  }

  /// Requests hardware biometric verification to unlock the app
  Future<bool> authenticateToUnlock({String reason = 'Scan fingerprint to unlock Oneova'}) async {
    if (!_isLockEnabled) {
      _isCurrentlyUnlocked = true;
      return true;
    }

    try {
      final result = await _bioService.authenticateWithDetails(
        reason: reason,
        biometricOnly: true,
      );

      if (result.isSuccess) {
        _isCurrentlyUnlocked = true;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BiometricLockService] Auth error: $e');
      return false;
    }
  }
}

