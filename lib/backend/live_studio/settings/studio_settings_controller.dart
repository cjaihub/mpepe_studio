// LIVE STUDIO v2 — stage customization controller (workstream #6).
//
// Wiring: `StudioState` comes through [studioSettingsStateSourceProvider].
// LiveStudioV2Screen overrides it in its ProviderScope
// (studio_v2/shell/studio_scope.dart); tests use a fake stream.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/studio_contracts.dart';
import '../contracts/studio_ports.dart';
import 'settings_rules.dart';

// ─── Ports ───────────────────────────────────────────────────────────────────

/// Authoritative [StudioState] stream for a stream id (the session's merged
/// snapshot + `state.patch` events). Must be overridden; see the file header.
final studioSettingsStateSourceProvider = Provider.family<Stream<StudioState>, String>(
  (ref, streamId) => throw UnimplementedError(
      'studioSettingsStateSourceProvider is not wired: LiveStudioV2Screen overrides it '
      '(studio_v2/shell/studio_scope.dart).'),
);

/// Typed wrapper over `lsSetSettings`.
class StudioSettingsApi {
  StudioSettingsApi(this._port);
  final StudioCallPort _port;

  /// Sends [partial] (wire keys from [StudioSettingsKeys]). `streamId == null`
  /// saves the caller's defaults only. Returns the settings the server applied.
  Future<StudioSettings?> save(String? streamId, Map<String, Object?> partial) async {
    final res = await _port.call(
        StudioCallables.setSettings, {'streamId': streamId, 'partial': partial});
    final s = res['settings'];
    return s is Map ? sanitizeSettings(StudioSettings.fromJson(Map<String, dynamic>.from(s))) : null;
  }
}

final studioSettingsApiProvider =
    Provider<StudioSettingsApi>((ref) => StudioSettingsApi(ref.watch(studioCallPortProvider)));

/// One-time reads of `users/{hostId}/live_studio/settings`.
abstract class HostSettingsStore {
  Future<Map<String, dynamic>?> read(String hostId);
}

class FirestoreHostSettingsStore implements HostSettingsStore {
  FirestoreHostSettingsStore([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  @override
  Future<Map<String, dynamic>?> read(String hostId) async {
    final snap = await _db.doc(StudioPaths.hostSettings(hostId)).get();
    return snap.data();
  }
}

final hostSettingsStoreProvider =
    Provider<HostSettingsStore>((ref) => FirestoreHostSettingsStore());

/// The host's saved settings (one-time get), sanitized, or theme defaults when
/// nothing is saved yet. Pass the result as `settings` to `lsStart`.
final hostDefaultsProvider =
    FutureProvider.autoDispose.family<StudioSettings, String>((ref, hostId) async {
  final raw = await ref.watch(hostSettingsStoreProvider).read(hostId);
  return raw == null ? const StudioSettings() : sanitizeSettings(StudioSettings.fromJson(raw));
});

// ─── Controller ──────────────────────────────────────────────────────────────

@immutable
class StudioSettingsView {
  /// Last server-confirmed settings (from StudioState or a callable result).
  final StudioSettings applied;

  /// What the host sees: [applied] plus unconfirmed local edits.
  final StudioSettings effective;

  /// True once the first StudioState arrived.
  final bool ready;

  /// True while a call is in flight or a slider value is waiting to be sent.
  final bool saving;

  /// The last callable error; the edit it carried has been reverted.
  final Object? error;

  const StudioSettingsView({
    this.applied = const StudioSettings(),
    this.effective = const StudioSettings(),
    this.ready = false,
    this.saving = false,
    this.error,
  });
}

/// Host-side settings editing for one stream: optimistic preview, slider
/// throttling (one call per [throttle]), revert on error. Viewers do not need
/// it; they render `StudioState.settings`.
final studioSettingsControllerProvider = NotifierProvider.autoDispose
    .family<StudioSettingsController, StudioSettingsView, String>(StudioSettingsController.new);

/// The settings the host's own stage should render (preview included).
final studioPreviewSettingsProvider = Provider.autoDispose.family<StudioSettings, String>(
    (ref, streamId) => ref.watch(studioSettingsControllerProvider(streamId)).effective);

class StudioSettingsController extends Notifier<StudioSettingsView> {
  StudioSettingsController(this.streamId);

  final String streamId;

  static const Duration throttle = Duration(milliseconds: 250);

  StudioSettings _applied = const StudioSettings();
  bool _ready = false;
  Object? _error;

  /// Edited values not yet confirmed by the server (wire keys).
  final Map<String, Object?> _overlay = {};

  /// Slider values waiting for the throttle window.
  final Map<String, Object?> _queued = {};
  Timer? _timer;
  int _inFlight = 0;
  Future<void> _chain = Future<void>.value();
  late StudioSettingsApi _api;

  @override
  StudioSettingsView build() {
    final source = ref.watch(studioSettingsStateSourceProvider(streamId));
    _api = ref.watch(studioSettingsApiProvider);
    final sub = source.listen(_onState, onError: (Object _) {});
    ref.onDispose(() {
      sub.cancel();
      _timer?.cancel();
      _timer = null;
      if (_queued.isNotEmpty) {
        // Keep the host's last slider value even if the sheet closed mid-window.
        final pending = Map<String, Object?>.of(_queued);
        _queued.clear();
        unawaited(_api.save(streamId, pending).then((_) {}, onError: (Object _) {}));
      }
    });
    return _view();
  }

  // ── Edits ──

  void setStudio(String studioId) {
    if (studioId.isEmpty) return;
    _edit({StudioSettingsKeys.studioId: studioId});
  }

  void setTheme(StudioTheme theme) {
    final cur = state.effective;
    if (cur.theme == theme) return;
    _edit({
      StudioSettingsKeys.theme: theme.wire,
      StudioSettingsKeys.frameColor: mapFrameColor(cur.frameColor, cur.theme, theme),
    });
  }

  void setFrameWidth(num width) =>
      _editSlider({StudioSettingsKeys.frameWidth: clampFrameWidth(width)});

  void setFrameColor(String hex) {
    final opt = frameColorOption(state.effective.theme, hex);
    if (opt == null) return;
    _edit({StudioSettingsKeys.frameColor: opt});
  }

  void setGuestSize(GuestSize size) => _edit({StudioSettingsKeys.guestSize: size.wire});

  void setShowNames(bool show) => _edit({StudioSettingsKeys.showNames: show});

  void setStudioDim(num dim) => _editSlider({StudioSettingsKeys.studioDim: clampStudioDim(dim)});

  void setSpeakerMode(SpeakerMode mode) => _edit({StudioSettingsKeys.speakerMode: mode.wire});

  /// Sends any throttled slider value now (e.g. on slider release).
  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_queued.isEmpty) return;
    final p = Map<String, Object?>.of(_queued);
    _queued.clear();
    _send(p);
  }

  // ── Internals ──

  void _onState(StudioState s) {
    _applied = sanitizeSettings(s.settings);
    _ready = true;
    state = _view();
  }

  StudioSettingsView _view() => StudioSettingsView(
        applied: _applied,
        effective: applySettingsPatch(_applied, _overlay),
        ready: _ready,
        saving: _inFlight > 0 || _queued.isNotEmpty,
        error: _error,
      );

  bool _isNoop(Map<String, Object?> patch) {
    final cur = state.effective.toJson();
    return patch.entries.every((e) => cur[e.key] == e.value);
  }

  void _edit(Map<String, Object?> patch) {
    if (_isNoop(patch)) return;
    _overlay.addAll(patch);
    // Piggy-back any throttled slider value on this call.
    _timer?.cancel();
    _timer = null;
    final send = {..._queued, ...patch};
    _queued.clear();
    _error = null;
    state = _view();
    _send(send);
  }

  void _editSlider(Map<String, Object?> patch) {
    if (_isNoop(patch)) return;
    _overlay.addAll(patch);
    _queued.addAll(patch);
    _error = null;
    _timer ??= Timer(throttle, flush);
    state = _view();
  }

  void _send(Map<String, Object?> patch) {
    _inFlight++;
    state = _view();
    _chain = _chain.then((_) async {
      try {
        final confirmed = await _api.save(streamId, patch);
        if (!ref.mounted) return;
        _settle(patch);
        if (confirmed != null) _applied = confirmed;
        _error = null;
      } catch (e) {
        if (!ref.mounted) return;
        _settle(patch); // drop the optimistic values → back to the applied settings
        _error = e;
      } finally {
        _inFlight--;
        if (ref.mounted) state = _view();
      }
    });
  }

  /// Removes overlay entries this call carried, unless the host edited the
  /// same field again since (that newer value is queued or in flight).
  void _settle(Map<String, Object?> sent) {
    for (final e in sent.entries) {
      if (_overlay.containsKey(e.key) && _overlay[e.key] == e.value) _overlay.remove(e.key);
    }
  }
}
