import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../backend/settings_service.dart';

final settingsServiceProvider = Provider((ref) => SettingsService());

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, Map<String, dynamic>>(() {
  return SettingsNotifier();
});

/// Lifecycle of the most recent settings write, shown by the live
/// auto-save indicator on every settings screen.
enum SettingsSavePhase { idle, saving, saved, pendingSync, error }

class SettingsSaveStatus {
  final SettingsSavePhase phase;
  final DateTime? at;
  const SettingsSaveStatus(this.phase, [this.at]);
}

class SettingsSaveStatusNotifier extends Notifier<SettingsSaveStatus> {
  @override
  SettingsSaveStatus build() => const SettingsSaveStatus(SettingsSavePhase.idle);

  void set(SettingsSavePhase phase) => state = SettingsSaveStatus(phase, DateTime.now());
}

final settingsSaveStatusProvider =
    NotifierProvider<SettingsSaveStatusNotifier, SettingsSaveStatus>(SettingsSaveStatusNotifier.new);

/// Settings for the signed-in user, kept in sync with `user_settings/{uid}`
/// through a real-time snapshots() listener, so changes made on another
/// device (or by an undo) show up immediately.
class SettingsNotifier extends AsyncNotifier<Map<String, dynamic>> {
  String? _userId;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<Map<String, dynamic>>? _docSub;
  int _writeSeq = 0;

  @override
  Future<Map<String, dynamic>> build() {
    ref.onDispose(() {
      _authSub?.cancel();
      _docSub?.cancel();
      _authSub = null;
      _docSub = null;
    });
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid == _userId) return;
      state = const AsyncValue.loading();
      _watch(user?.uid).then((data) => state = AsyncValue.data(data));
    });
    return _watch(FirebaseAuth.instance.currentUser?.uid);
  }

  /// Subscribes to [uid]'s settings doc. The returned future completes with
  /// the first snapshot; later snapshots are pushed straight into [state].
  Future<Map<String, dynamic>> _watch(String? uid) {
    _userId = uid;
    _docSub?.cancel();
    _docSub = null;
    if (uid == null) return Future.value(<String, dynamic>{});

    final service = ref.read(settingsServiceProvider);
    final first = Completer<Map<String, dynamic>>();
    _docSub = service.watchSettings(uid).listen(
      (data) {
        if (!first.isCompleted) {
          first.complete(data);
        } else {
          state = AsyncValue.data(data);
        }
      },
      onError: (Object e, StackTrace st) {
        if (!first.isCompleted) {
          first.complete(service.defaultSettings);
        } else {
          state = AsyncValue.error(e, st);
        }
      },
    );
    return first.future;
  }

  Future<void> updateCategory(String category, Map<String, dynamic> data) async {
    if (_userId == null) return;

    final currentData = state.value ?? {};
    final updatedData = Map<String, dynamic>.from(currentData);

    if (updatedData[category] is Map) {
      final categoryData = Map<String, dynamic>.from(updatedData[category] as Map);
      data.forEach((key, value) {
        categoryData[key] = value;
      });
      updatedData[category] = categoryData;
    } else {
      updatedData[category] = data;
    }

    // Optimistic update; the snapshot listener confirms (or corrects) it.
    state = AsyncValue.data(updatedData);

    final status = ref.read(settingsSaveStatusProvider.notifier);
    final seq = ++_writeSeq;
    status.set(SettingsSavePhase.saving);

    // Firestore applies the write to the local cache immediately and only
    // completes once the server acks. If that takes a while (offline), tell
    // the user it is safe on the device and will sync.
    final slowTimer = Timer(const Duration(seconds: 3), () {
      if (seq == _writeSeq) status.set(SettingsSavePhase.pendingSync);
    });

    try {
      final service = ref.read(settingsServiceProvider);
      await service.updateSettingsCategory(_userId!, category, data);
      if (seq == _writeSeq) status.set(SettingsSavePhase.saved);
    } catch (_) {
      // A rejected write is rolled back by Firestore and re-delivered to the
      // snapshot listener, which restores the server state.
      if (seq == _writeSeq) status.set(SettingsSavePhase.error);
    } finally {
      slowTimer.cancel();
    }
  }

  Future<void> updateSetting(String category, String key, dynamic value) async {
    await updateCategory(category, {key: value});
  }
}
