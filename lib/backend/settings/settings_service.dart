import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'settings_models.dart';
import '../settings_service.dart';
import 'account_settings_schema.dart' show AccountSettingsSchema;
import '../../auth/security/login_security.dart';

/// Typed view of the account's security, privacy, AI and appearance
/// settings. It reads and writes the one settings store, `user_settings/{uid}`
/// (lib/backend/settings_service.dart); the old `users/{uid}/settings/prefs`
/// doc is only read once, by the migration in [AccountSettingsSchema].
final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(() {
  return SettingsNotifier();
});

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late final SettingsService _store = SettingsService(firestore: _firestore);

  @override
  Future<AppSettings> build() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Future.value(const AppSettings());

    // Real-time: the first snapshot resolves build(), later ones update state.
    final first = Completer<AppSettings>();
    final sub = _store.watchSettings(uid).listen(
      (data) {
        final settings = AppSettings.fromCanonical(data);
        if (!first.isCompleted) {
          first.complete(settings);
        } else {
          state = AsyncData(settings);
        }
      },
      onError: (Object e, StackTrace st) {
        if (!first.isCompleted) first.complete(const AppSettings());
      },
    );
    ref.onDispose(sub.cancel);
    return first.future;
  }

  Future<void> updateSettings(AppSettings newSettings) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    state = AsyncData(newSettings);
    try {
      await _store.updateSettings(uid, newSettings.toCanonical());
    } catch (e) {
      ref.invalidateSelf();
    }
  }

  // Helper mutations
  Future<void> setAutoMode(AILocalAgentMode mode) async {
    final current = state.value ?? const AppSettings();
    await updateSettings(current.copyWith(autoMode: mode));
  }

  Future<void> setAIEnabled(bool enabled) async {
    final current = state.value ?? const AppSettings();
    await updateSettings(current.copyWith(aiEnabled: enabled));
  }
  
  // Security Actions
  Future<void> revokeAllSessions() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      // Server signs the account out on every device and forgets known phones.
      await FirebaseFunctions.instance.httpsCallable('revokeAllSessions').call();
      await LoginSecurity.instance.clear();
      await _auth.signOut();
    }
  }

  Future<void> exportData() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      // Trigger backend job to compile zip and email user
      await _firestore.collection('data_exports').add({
        'uid': uid,
        'requestedAt': FieldValue.serverTimestamp(),
      });
    }
  }
  
  Future<void> requestAccountDeletion() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      await _firestore.collection('account_deletion_requests').doc(uid).set({
        'requestedAt': FieldValue.serverTimestamp(),
      });
      await _auth.signOut();
    }
  }
}
