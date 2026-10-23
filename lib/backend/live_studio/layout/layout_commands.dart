import '../contracts/studio_contracts.dart';
import '../contracts/studio_ports.dart';

/// Typed client for `lsSetLayout` (server: functions/src/liveStudio/layout.ts).
///
/// Host/coHost only. Viewer taps never call this — a viewer tap opens a local
/// pop-out (ARCHITECTURE Q3).
class LayoutCommands {
  LayoutCommands(this._port, this.streamId);
  final StudioCallPort _port;
  final String streamId;

  Future<Map<String, dynamic>> _call(String op, [Map<String, dynamic> args = const {}]) =>
      _port.call(StudioCallables.setLayout, {'streamId': streamId, 'op': op, ...args});

  /// Swap wall[index] with the center.
  Future<Map<String, dynamic>> swap(int index) => _call(LayoutOps.swap, {'index': index});

  /// Pin [uid] to the center (moves them there if needed).
  Future<Map<String, dynamic>> pin(String uid) => _call(LayoutOps.pin, {'uid': uid});
  Future<Map<String, dynamic>> unpin() => _call(LayoutOps.unpin);

  /// Writes settings.speakerMode (hostPinned also brings the host back).
  Future<Map<String, dynamic>> setMode(SpeakerMode mode) =>
      _call(LayoutOps.setMode, {'mode': mode.wire});

  /// Swap overflow member [uid] with the wall occupant at [index].
  Future<Map<String, dynamic>> rotateIn(String uid, int index) =>
      _call(LayoutOps.rotateIn, {'uid': uid, 'index': index});

  /// Leader only (auto mode).
  Future<Map<String, dynamic>> autoPromote(String uid) => _call(LayoutOps.autoPromote, {'uid': uid});
}
