import '../../backend/webrtc_desktop_service.dart';
import 'computer_action_log.dart';

/// Called for every user-meaningful action so it can be logged.
typedef ActionRecorder = void Function(
  ActionSource source,
  String action,
  Map<String, dynamic> params, {
  bool secret,
});

/// Thin sender for the phone controller.
///
/// Pointer and scroll deltas go over the unordered `pointer_fast` lane
/// (falls back to the reliable channel), while clicks, button state, keys and
/// media commands always use the reliable `mouse_control` channel so they
/// are never dropped or reordered.
class ControllerLink {
  ControllerLink({
    required this.sendFast,
    required this.sendReliable,
    this.recorder,
  });

  factory ControllerLink.forService(
    WebRTCDesktopService service,
    String deviceToken, {
    ActionRecorder? recorder,
  }) =>
      ControllerLink(
        sendFast: (p) => service.sendFastPacket(deviceToken, p),
        sendReliable: (p) => service.sendControlPacket(deviceToken, p),
        recorder: recorder,
      );

  final bool Function(Map<String, dynamic> packet) sendFast;
  final bool Function(Map<String, dynamic> packet) sendReliable;
  final ActionRecorder? recorder;

  /// Source stamped on logged actions (trackpad, touch, voice, ai...).
  ActionSource source = ActionSource.trackpad;

  static double _r(double v) => (v * 100).roundToDouble() / 100;
  static double _n(double v) => (v.clamp(0.0, 1.0) * 10000).roundToDouble() / 10000;

  void _log(String action, [Map<String, dynamic> params = const {}, bool secret = false]) =>
      recorder?.call(source, action, params, secret: secret);

  // ─── Relative pointer (trackpad) ──────────────────────────────────────────

  void move(double dx, double dy) {
    if (dx == 0 && dy == 0) return;
    sendFast({'a': 'mv', 'dx': _r(dx), 'dy': _r(dy)});
    _log('move', {'dx': dx, 'dy': dy});
  }

  /// Pixel scroll. Positive [dy] drags the page down (natural scrolling).
  void scroll(double dx, double dy) {
    if (dx.abs() < 0.01 && dy.abs() < 0.01) return;
    sendFast({'a': 'sc', 'dx': _r(dx), 'dy': _r(dy)});
    _log('scroll', {'dx': dx, 'dy': dy});
  }

  bool click() {
    _log('click');
    return _reliable({'action': 'mouse_left_click'});
  }

  bool rightClick() {
    _log('right_click');
    return _reliable({'action': 'mouse_right_click'});
  }

  bool doubleClick() {
    _log('double_click');
    return _reliable({'action': 'mouse_double_click'});
  }

  bool leftDown() {
    _log('drag', {'phase': 'down'});
    return _reliable({'action': 'mouse_left_down'});
  }

  bool leftUp() => _reliable({'action': 'mouse_left_up'});

  // ─── Absolute pointer (live screen, AI): x/y normalised 0..1 ──────────────

  void moveTo(double x, double y, {bool log = false}) {
    sendFast({'a': 'mt', 'nx': _n(x), 'ny': _n(y)});
    if (log) _log('move', {'x': x, 'y': y});
  }

  bool clickAt(double x, double y) {
    _log('click', {'x': x, 'y': y});
    return _reliable({'action': 'mouse_click_normalized', 'nx': _n(x), 'ny': _n(y)});
  }

  bool doubleClickAt(double x, double y) {
    _log('double_click', {'x': x, 'y': y});
    return _reliable({'action': 'mouse_double_click_normalized', 'nx': _n(x), 'ny': _n(y)});
  }

  bool rightClickAt(double x, double y) {
    _log('right_click', {'x': x, 'y': y});
    return _reliable({'action': 'mouse_right_click_normalized', 'nx': _n(x), 'ny': _n(y)});
  }

  /// Press at a point (drag start). Pair with [moveTo] and [leftUp].
  bool pressAt(double x, double y) {
    _log('drag', {'x': x, 'y': y, 'phase': 'down'});
    _reliable({'action': 'mouse_move_normalized', 'nx': _n(x), 'ny': _n(y)});
    return _reliable({'action': 'mouse_left_down'});
  }

  // ─── Keyboard ─────────────────────────────────────────────────────────────

  bool typeText(String text, {bool pressEnter = false, bool secret = false}) {
    _log('type_text', {'text': text, 'enter': pressEnter}, secret);
    return _reliable({'action': 'type_text', 'text': text, 'pressEnter': pressEnter});
  }

  bool keyCombo(String combo) {
    _log('key_combo', {'combo': combo});
    return _reliable({'action': 'key_combination', 'combo': combo});
  }

  bool pressKey(String key) {
    _log('press_key', {'key': key});
    return _reliable({'action': 'key_tap', 'key': key});
  }

  // ─── Media & volume ───────────────────────────────────────────────────────

  /// `play`, `next`, `prev`, `mute`, `vol_up`, `vol_down`.
  bool media(String key) {
    _log('media_key', {'key': key});
    return _reliable({'action': 'media_key', 'key': key});
  }

  bool setVolume(int level, {bool log = true}) {
    if (log) _log('volume_set', {'level': level});
    return _reliable({'action': 'volume_set', 'level': level});
  }

  bool setMuted(bool muted) {
    _log('media_key', {'key': muted ? 'mute' : 'unmute'});
    return _reliable({'action': 'volume_mute', 'muted': muted});
  }

  bool requestVolume() => _reliable({'action': 'volume_get'});

  // ─── Power ────────────────────────────────────────────────────────────────

  bool wake() {
    _log('wake');
    return _reliable({'action': 'wake_display'});
  }

  /// Wakes the screen and types the login password at the lock screen.
  /// The password travels only inside the encrypted data channel and is
  /// never logged.
  bool unlock(String password) {
    _log('unlock');
    return _reliable({'action': 'unlock_secure', 'password': password});
  }

  bool requestStatus() => _reliable({'action': 'status_get'});

  bool ping() =>
      _reliable({'action': 'ping', 't': DateTime.now().millisecondsSinceEpoch});

  bool _reliable(Map<String, dynamic> packet) => sendReliable(packet);
}
