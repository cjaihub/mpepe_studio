import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../backend/settings_service.dart';
import '../backend/settings/account_settings_schema.dart';

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
/// device, another screen (or by an undo) show up immediately. This is the
/// only settings store: see [AccountSettingsSchema].
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

  static String _cacheKey(String uid) => 'oneova_settings_cache_$uid';

  Future<Map<String, dynamic>?> _readOfflineCache(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(uid));
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}
    return null;
  }

  void _writeOfflineCache(String uid, Map<String, dynamic> data) {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_cacheKey(uid), jsonEncode(data));
    }).catchError((_) {});
  }

  /// Subscribes to [uid]'s settings doc. The returned future completes with
  /// the first snapshot; later snapshots are pushed straight into [state].
  Future<Map<String, dynamic>> _watch(String? uid) {
    _userId = uid;
    _docSub?.cancel();
    _docSub = null;
    if (uid == null) return Future.value(<String, dynamic>{});

    // Hydrate instantly from offline cache if available to avoid any network wait
    _readOfflineCache(uid).then((cached) {
      if (cached != null && !(_firstCompleter?.isCompleted ?? true)) {
        state = AsyncValue.data(AccountSettingsSchema.resolve(cached));
      }
    });

    final service = ref.read(settingsServiceProvider);
    final first = Completer<Map<String, dynamic>>();
    _firstCompleter = first;
    _docSub = service.watchSettings(uid).listen(
      (data) {
        _writeOfflineCache(uid, data);
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

  Completer<Map<String, dynamic>>? _firstCompleter;

  Future<void> updateCategory(String category, Map<String, dynamic> data) async {
    if (_userId == null) return;

    final updatedData = AccountSettingsSchema.merge(state.value ?? const {}, {category: data});

    // Optimistic update; the snapshot listener confirms (or corrects) it.
    state = AsyncValue.data(updatedData);
    _writeOfflineCache(_userId!, updatedData);

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
