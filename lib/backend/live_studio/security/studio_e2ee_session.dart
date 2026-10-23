// LIVE STUDIO v2 — media end-to-end encryption key handling (security
// workstream). Used by media/livekit_studio_room.dart.
//
// WHAT THIS PROTECTS: stage audio/video frames are encrypted on the
// publisher's device (LiveKit frame encryption, AES-GCM, shared key) and
// decrypted by viewers, so the SFU (our LiveKit nodes, TURN relays) and the
// network only see ciphertext.
// WHAT IT DOES NOT: the key is issued by our Cloud Functions (lsToken /
// lsMediaKey) to everyone allowed to join, so the backend can read it.
// Comments, reactions and data messages are not encrypted (server-visible for
// moderation). DRM screen-share content is still blocked by the OS.
//
// Rotation: when someone is blocked or leaves the stage the server rotates
// the key and sends `key.update {keyIndex}` on topic `security`. The message
// only carries the index (it travels through the SFU); the key itself is
// fetched over HTTPS with lsMediaKey, added to the key ring at that index,
// and local senders switch to it after [switchDelay] so receivers have time
// to fetch it too (frames carry their key index, so receivers decrypt
// old and new frames during the overlap).

import 'dart:async';

import 'studio_security_models.dart';

class StudioE2eeSession {
  StudioE2eeSession({
    required this.fetchKey,
    required this.installKey,
    required this.useIndex,
    this.switchDelay = const Duration(milliseconds: 1500),
  });

  /// Gets the current key from the server (lsMediaKey); null when E2EE is off.
  final Future<StudioMediaKey?> Function() fetchKey;

  /// Adds [key] to the key ring at its index.
  final Future<void> Function(StudioMediaKey key) installKey;

  /// Makes this client's senders encrypt with ring index [index].
  final Future<void> Function(int index) useIndex;

  final Duration switchDelay;

  int? _current;
  int? _pending;

  /// Ring index local senders use; null before [start].
  int? get currentIndex => _current;
  bool get active => _current != null;

  Future<void> start(StudioMediaKey key) async {
    await installKey(key);
    _current = key.keyIndex;
    await useIndex(key.keyIndex);
  }

  /// Re-applies the current index (new local tracks start at index 0).
  Future<void> reapply() async {
    final c = _current;
    if (c != null) await useIndex(c);
  }

  /// Handles a `key.update`. Returns true when a new key was installed.
  Future<bool> onKeyUpdate(int keyIndex) async {
    if (_current == null || keyIndex == _current || keyIndex == _pending) return false;
    _pending = keyIndex;
    try {
      final key = await fetchKey();
      if (key == null) return false;
      await installKey(key);
      _current = key.keyIndex;
      await Future<void>.delayed(switchDelay);
      if (_current == key.keyIndex) await useIndex(key.keyIndex);
      return true;
    } catch (_) {
      return false;
    } finally {
      if (_pending == keyIndex) _pending = null;
    }
  }
}
