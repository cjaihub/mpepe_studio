import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ova_assistant/services/ova_device_hub.dart';
import 'speech_hub.dart';

/// Every Oneova feature that records from the microphone.
enum MicUser {
  voiceTyping,
  voiceNote,
  assistant,
  aiLive,
  call;

  /// A call is never interrupted by another feature. Everything else is
  /// equal: whatever the user started most recently gets the mic.
  int get priority => this == MicUser.call ? 2 : 1;

  String get label => switch (this) {
        MicUser.voiceTyping => 'voice typing',
        MicUser.voiceNote => 'a voice note',
        MicUser.assistant => 'Ova',
        MicUser.aiLive => 'AI voice',
        MicUser.call => 'your call',
      };
}

/// What happened to the mic while a lease was held.
enum MicInterruption {
  /// Another app (a phone call, a recorder) took the mic for now.
  heldByOtherApp,

  /// The other app let go; recording can continue.
  released,
}

/// Ownership of the microphone for one feature. Call [release] when done.
class MicLease {
  MicLease._(this.user, this._id, this._coordinator);

  final MicUser user;
  final int _id;
  final MicCoordinator _coordinator;

  /// False once released, or after another feature took over.
  bool get isActive => _coordinator._current?.lease._id == _id;

  Future<void> release() => _coordinator._release(_id);
}

/// Thrown-free result when the mic can't be handed over.
class MicBusy {
  const MicBusy(this.heldBy);
  final MicUser heldBy;
  String get message => 'The microphone is in use by ${heldBy.label}. End it first.';
}

class _Owner {
  _Owner(this.lease, this.onPreempted, this.onInterruption, this.tookFocus);
  final MicLease lease;
  final Future<void> Function() onPreempted;
  final void Function(MicInterruption)? onInterruption;
  final bool tookFocus;
}

/// One owner of the microphone at a time across the whole app.
///
/// Starting a feature hands the mic over cleanly: the previous owner is told
/// to stop first, so two recorders never fight over the device. On Android
/// the owner also takes exclusive audio focus, which pauses other apps'
/// music and videos while Oneova listens, and is told when another app
/// takes the mic (a phone call) and when it is free again.
class MicCoordinator {
  MicCoordinator._();
  static final MicCoordinator instance = MicCoordinator._();

  final OvaDeviceHub _hub = OvaDeviceHub();
  StreamSubscription<String>? _focusSub;
  _Owner? _current;
  int _nextId = 0;
  Future<void> _queue = Future<void>.value();

  /// Who holds the mic right now (null when free). Reels go silent while set.
  final ValueNotifier<MicUser?> owner = ValueNotifier<MicUser?>(null);

  MicUser? get currentUser => _current?.lease.user;

  /// Takes the mic for [user]. Returns a [MicLease], or a [MicBusy] when a
  /// higher-priority feature (a call) holds it.
  ///
  /// [onPreempted] must stop recording; it runs when another feature takes
  /// over or the OS gives the mic to another app for good.
  /// [takeFocus] is false for calls: WebRTC manages its own audio mode.
  Future<Object> acquire(
    MicUser user, {
    required Future<void> Function() onPreempted,
    void Function(MicInterruption)? onInterruption,
    bool takeFocus = true,
  }) {
    final done = Completer<Object>();
    _queue = _queue.then((_) async {
      try {
        done.complete(await _acquire(user, onPreempted, onInterruption, takeFocus));
      } catch (e) {
        done.completeError(e);
      }
    });
    return done.future;
  }

  Future<Object> _acquire(
    MicUser user,
    Future<void> Function() onPreempted,
    void Function(MicInterruption)? onInterruption,
    bool takeFocus,
  ) async {
    final prev = _current;
    if (prev != null) {
      if (prev.lease.user.priority > user.priority) return MicBusy(prev.lease.user);
      _current = null;
      debugPrint('[MicCoordinator] ${user.name} takes the mic from ${prev.lease.user.name}');
      try {
        await prev.onPreempted().timeout(const Duration(milliseconds: 1200));
      } catch (e) {
        debugPrint('[MicCoordinator] ${prev.lease.user.name} stop failed: $e');
      }
      if (prev.tookFocus && !takeFocus) await _hub.releaseAudioFocus();
    }

    final lease = MicLease._(user, ++_nextId, this);
    var focused = false;
    if (takeFocus && OvaDeviceHub.supported) {
      final r = await _hub.acquireAudioFocus();
      focused = r == 'granted' || r == 'delayed';
      _focusSub ??= _hub.audioFocusEvents.listen(_onFocusEvent, onError: (_) {});
    }
    _current = _Owner(lease, onPreempted, onInterruption, focused);
    owner.value = user;
    return lease;
  }

  void _onFocusEvent(String event) {
    final cur = _current;
    if (cur == null || !cur.tookFocus) return;
    switch (event) {
      case 'loss_transient':
        // Android's external SpeechRecognizer service requests transient audio
        // focus on our behalf right when SpeechHub.listen() starts. Do not
        // self-interrupt Oneova's own dictation/assistant session.
        final usingPlatformSpeech = SpeechHub.instance.isActive &&
            (cur.lease.user == MicUser.assistant ||
                cur.lease.user == MicUser.voiceTyping);
        if (usingPlatformSpeech) {
          debugPrint('[MicCoordinator] Ignoring transient focus handoff to platform SpeechRecognizer');
          return;
        }
        cur.onInterruption?.call(MicInterruption.heldByOtherApp);
      case 'silenced':
        cur.onInterruption?.call(MicInterruption.heldByOtherApp);
      case 'gain':
      case 'unsilenced':
        cur.onInterruption?.call(MicInterruption.released);
      case 'loss':
        // Another app took audio for good (e.g. it started a call).
        if (cur.onInterruption != null) {
          cur.onInterruption!(MicInterruption.heldByOtherApp);
        } else {
          unawaited(_preemptCurrent());
        }
    }
  }

  Future<void> _preemptCurrent() async {
    final cur = _current;
    if (cur == null) return;
    try {
      await cur.onPreempted();
    } catch (_) {}
    await _release(cur.lease._id);
  }

  /// Not queued: a preempted owner may release from inside its stop callback
  /// while [_acquire] is waiting for it. Platform calls stay in call order.
  Future<void> _release(int id) async {
    final cur = _current;
    if (cur == null || cur.lease._id != id) return;
    _current = null;
    owner.value = null;
    if (cur.tookFocus) await _hub.releaseAudioFocus();
  }
}
