import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/wellbeing_models.dart';
import '../../settings_service.dart';

final wellbeingServiceProvider = Provider<DigitalWellbeingService>((ref) {
  return DigitalWellbeingService();
});

final wellbeingPreferencesProvider = StreamProvider<DigitalWellbeingPreferences>((ref) {
  return ref.watch(wellbeingServiceProvider).streamPreferences();
});

/// Wellbeing preferences: the `wellbeing` category of the one settings
/// store, user_settings/{uid}.
class DigitalWellbeingService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final SettingsService _settings = SettingsService();

  String? get _userId => _auth.currentUser?.uid;

  Stream<DigitalWellbeingPreferences> streamPreferences() {
    final uid = _userId;
    if (uid == null) return const Stream.empty();
    return _settings
        .watchCategory(uid, 'wellbeing')
        .map((data) => DigitalWellbeingPreferences.fromMap(uid, data));
  }

  Future<void> updatePreferences(DigitalWellbeingPreferences prefs) async {
    final uid = _userId;
    if (uid == null) return;
    await _settings.updateSettingsCategory(uid, 'wellbeing', prefs.toMap());
  }

  Future<void> updateFeedMode(FeedLayoutMode mode) async {
    final uid = _userId;
    if (uid == null) return;
    await _settings.updateSettingsCategory(uid, 'wellbeing', {'feedMode': mode.name});
  }
}
