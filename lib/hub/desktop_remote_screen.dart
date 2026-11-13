import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/services/oneova_biometrics_service.dart';
import '../backend/remote_connect_service.dart';
import '../backend/voice_assistant_service.dart';
import '../backend/webrtc_desktop_service.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/oneova_smart_status_banner.dart';
import '../shared/widgets/voice_wave_visualizer.dart';
import 'messaging/remote_chat_view.dart';
import 'telemetry_dashboard_screen.dart';
import 'live_control/live_keyboard.dart';
import 'live_control/ova_live_copilot.dart';

/// Oneova Online Device Control Panel.
///
/// Renders the paired computer's live screen in real time via a hybrid
/// WebRTC + Cloud Frame Bridge (`registered_computers/{id}/live_stream/current`)
/// so the screen is always live and interactive, even across strict NATs or in
/// the background. Supports direct normalized touch-to-cursor clicks, right-clicks,
/// double-clicks, drags, scroll, live app switching, clipboard sync, Wispr voice
/// typing, biometric wake/unlock, and shared-account Ova AI Agent actions.
class DesktopRemoteScreen extends ConsumerStatefulWidget {
  const DesktopRemoteScreen({super.key});

  @override
  ConsumerState<DesktopRemoteScreen> createState() => _DesktopRemoteScreenState();
}

class _DesktopRemoteScreenState extends ConsumerState<DesktopRemoteScreen>
    with WidgetsBindingObserver {
  final TransformationController _transformationController = TransformationController();
  Offset? _doubleTapPosition;

  // Interactive tool visibility
  bool _isTouchMouseActive = true;
  bool _isTrackpadVisible = false;
  bool _isKeyboardRibbonVisible = false;
  bool _isAppsRibbonVisible = false;
  bool _isAiBarVisible = false;
  bool _isHudCollapsed = false;

  Offset _trackpadPosition = const Offset(16, 108);
  bool _isTrackpadDragLocked = false;

  // Live Cloud Frame Bridge & Telemetry state
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _liveFrameSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _telemetrySub;
  Timer? _viewerHeartbeatTimer;
  Timer? _moveCoalesceTimer;
  double _pendingDx = 0;
  double _pendingDy = 0;

  String? _boundDeviceId;
  Uint8List? _liveFrameBytes;
  int _remoteWidth = 1920;
  int _remoteHeight = 1080;
  double _cursorNx = 0.5;
  double _cursorNy = 0.5;
  List<String> _openApps = const ['Finder', 'Safari', 'Terminal'];
  double? _cpuPercent;
  double? _ramPercent;
  bool _wasOnline = true;

  // Visual tap ripple on rendered screen
  Offset? _tapRipplePos;
  int _tapRippleSeq = 0;

  Timer? _dragHoldTimer;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  final TextEditingController _keyboardInputController = TextEditingController();
  final TextEditingController _aiPromptController = TextEditingController();
  bool _isRendering = false;
  bool _isRefreshingConnection = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[OnlineControl] panel initState');
    WidgetsBinding.instance.addObserver(this);
    SharedPreferences.getInstance().then((p) {
      final right = p.getBool(_railSideKey);
      if (right != null && mounted) setState(() => _railOnRight = right);
    });
    _transformationController.addListener(_onZoomChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bindActiveComputerStreams();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final activeId = ref.read(remoteConnectProvider).activeComputerId;
      if (activeId != null) {
        _publishViewerHeartbeat(activeId);
        ref.read(remoteConnectProvider.notifier).refreshComputers();
        final conn = ref.read(webrtcDesktopProvider).connections[activeId];
        if (conn == null || conn.status != WebRTCStatus.connected) {
          ref.read(webrtcDesktopProvider.notifier).connect(activeId);
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearViewerHeartbeat(_boundDeviceId);
    _viewerHeartbeatTimer?.cancel();
    _liveFrameSub?.cancel();
    _telemetrySub?.cancel();
    _moveCoalesceTimer?.cancel();
    _dragHoldTimer?.cancel();
    _grabTimer?.cancel();
    final held = _boundDeviceId;
    if (held != null) _webrtcService.release(held);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _transformationController.removeListener(_onZoomChanged);
    _transformationController.dispose();
    _keyboardInputController.dispose();
    _aiPromptController.dispose();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _bindActiveComputerStreams() {
    final remoteState = ref.read(remoteConnectProvider);
    final activeId = remoteState.activeComputerId ?? remoteState.activeComputer?.id;
    if (activeId == null || activeId.isEmpty) return;

    if (remoteState.activeComputerId != activeId) {
      ref.read(remoteConnectProvider.notifier).setActiveComputer(activeId);
    }

    if (_boundDeviceId == activeId) return;
    debugPrint('[OnlineControl] panel bound to $activeId');
    final previous = _boundDeviceId;
    _clearViewerHeartbeat(previous);
    if (previous != null) _webrtcService.release(previous);
    _boundDeviceId = activeId;

    // Shared real-time link (already warm when opened from the computer page).
    _webrtcService.hold(activeId);

    // Snapshot frames are only a fallback while live video isn't up.
    void beat() {
      final c = ref.read(webrtcDesktopProvider).connections[activeId];
      if (c?.hasVideoStream == true) {
        _clearViewerHeartbeat(activeId);
      } else {
        _publishViewerHeartbeat(activeId);
      }
    }

    beat();
    _viewerHeartbeatTimer?.cancel();
    _viewerHeartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) => beat());

    _liveFrameSub?.cancel();
    _liveFrameSub = FirebaseFirestore.instance
        .collection('registered_computers')
        .doc(activeId)
        .collection('live_stream')
        .doc('current')
        .snapshots()
        .listen(
      (doc) {
        final data = doc.data();
        if (data == null || !mounted) return;
        final b64 = data['frame_b64'] as String?;
        Uint8List? decoded;
        if (b64 != null && b64.isNotEmpty) {
          try {
            decoded = base64Decode(b64);
          } catch (_) {}
        }
        final w = (data['width'] as num?)?.toInt() ?? _remoteWidth;
        final h = (data['height'] as num?)?.toInt() ?? _remoteHeight;
        final cnx = ((data['cursor_nx'] as num?)?.toDouble() ?? _cursorNx).clamp(0.0, 1.0);
        final cny = ((data['cursor_ny'] as num?)?.toDouble() ?? _cursorNy).clamp(0.0, 1.0);
        final apps = (data['open_apps'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList();

        setState(() {
          if (decoded != null && decoded.isNotEmpty) {
            _liveFrameBytes = decoded;
          }
          if (w > 0) _remoteWidth = w;
          if (h > 0) _remoteHeight = h;
          _cursorNx = cnx;
          _cursorNy = cny;
          if (apps != null && apps.isNotEmpty) {
            _openApps = apps;
          }
        });
      },
      onError: (Object e) {
        debugPrint('[OnlineControl] Live frame stream notice: $e');
      },
    );

    _telemetrySub?.cancel();
    _telemetrySub = FirebaseFirestore.instance
        .collection('registered_computers')
        .doc(activeId)
        .collection('telemetry')
        .doc('latest')
        .snapshots()
        .listen(
      (doc) {
        final d = doc.data();
        if (d == null || !mounted) return;
        setState(() {
          _cpuPercent = (d['cpu_usage'] ?? d['cpu_percent'] ?? d['cpu']) is num
              ? ((d['cpu_usage'] ?? d['cpu_percent'] ?? d['cpu']) as num).toDouble()
              : _cpuPercent;
          _ramPercent = (d['memory_usage'] ?? d['ram_percent'] ?? d['ram']) is num
              ? ((d['memory_usage'] ?? d['ram_percent'] ?? d['ram']) as num).toDouble()
              : _ramPercent;
        });
      },
      onError: (_) {},
    );
  }

  Future<void> _publishViewerHeartbeat(String deviceId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('registered_computers')
          .doc(deviceId)
          .collection('viewer_sessions')
          .doc(uid)
          .set({
        'viewer_uid': uid,
        'active_until_ms': DateTime.now().millisecondsSinceEpoch + 26000,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void _clearViewerHeartbeat(String? deviceId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (deviceId == null || uid == null) return;
    unawaited(
      FirebaseFirestore.instance
          .collection('registered_computers')
          .doc(deviceId)
          .collection('viewer_sessions')
          .doc(uid)
          .set({'active_until_ms': 0}, SetOptions(merge: true))
          .catchError((_) {}),
    );
  }

  Future<void> _refreshAndReconnect() async {
    if (_isRefreshingConnection) return;
    HapticFeedback.mediumImpact();
    setState(() => _isRefreshingConnection = true);
    final activeId = ref.read(remoteConnectProvider).activeComputerId ?? _boundDeviceId;
    try {
      await ref.read(remoteConnectProvider.notifier).refreshComputers();
      if (activeId != null) {
        await _publishViewerHeartbeat(activeId);
        await ref.read(webrtcDesktopProvider.notifier).forceReconnect(activeId);
      }
      if (mounted) {
        OneovaSmartStatus.show(
          context,
          title: 'Live Connection Refreshed',
          subtitle: 'Synchronized screen stream, input bridge, and telemetry.',
          kind: OneovaStatusKind.success,
          duration: const Duration(milliseconds: 2600),
          source: 'Online Control',
        );
      }
    } catch (e) {
      if (mounted) {
        OneovaSmartStatus.show(
          context,
          title: 'Refresh Notice',
          subtitle: e.toString(),
          kind: OneovaStatusKind.warning,
          source: 'Online Control',
          actionLabel: 'Retry',
          onAction: _refreshAndReconnect,
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshingConnection = false);
    }
  }

  /// Sends a control packet over WebRTC DataChannel when open, and falls back
  /// seamlessly to Firestore `registered_computers/{id}/commands` for ALL actions!
  void _sendControlPacket(Map<String, dynamic> packet) {
    final activeId = ref.read(remoteConnectProvider).activeComputerId ?? _boundDeviceId;
    if (activeId == null) return;

    final sentViaDc = ref
        .read(webrtcDesktopProvider.notifier)
        .sendControlPacket(activeId, packet);
    if (sentViaDc) return;

    final action = (packet['action'] ?? '').toString();
    if (action.isEmpty) return;

    // Coalesce high-frequency relative mouse_move over Firestore so it never floods
    if (action == 'mouse_move') {
      _pendingDx += (packet['dx'] as num?)?.toDouble() ?? 0;
      _pendingDy += (packet['dy'] as num?)?.toDouble() ?? 0;
      if (_moveCoalesceTimer?.isActive ?? false) return;
      _moveCoalesceTimer = Timer(const Duration(milliseconds: 110), () {
        final dx = _pendingDx;
        final dy = _pendingDy;
        _pendingDx = 0;
        _pendingDy = 0;
        if (dx.abs() > 0.5 || dy.abs() > 0.5) {
          ref.read(remoteConnectProvider.notifier).sendCommand(
            'system',
            'mouse_move',
            {'dx': dx, 'dy': dy},
            targetComputerId: activeId,
          );
        }
      });
      return;
    }

    if (action == 'ai_command') {
      ref.read(remoteConnectProvider.notifier).sendCommand(
        'system',
        'execute_ai_task',
        packet,
        targetComputerId: activeId,
      );
      return;
    }

    ref.read(remoteConnectProvider.notifier).sendCommand(
      'system',
      action,
      packet,
      targetComputerId: activeId,
    );
  }

  Future<void> _sendCommand(
    String command,
    String commandName, [
    Map<String, dynamic>? extraPayload,
  ]) async {
    final activeComputerId =
        ref.read(remoteConnectProvider).activeComputerId ?? _boundDeviceId;
    if (activeComputerId == null) {
      OneovaSmartStatus.show(
        context,
        title: 'No Computer Selected',
        subtitle: 'Pair or select a computer first.',
        kind: OneovaStatusKind.warning,
        source: 'Online Control',
      );
      return;
    }

    if (mounted) {
      setState(() => _isRendering = command == 'render_and_send');
    }

    final commandId = await ref.read(remoteConnectProvider.notifier).sendCommand(
      'system',
      command,
      extraPayload ?? {},
      targetComputerId: activeComputerId,
    );

    if (!mounted) return;
    if (commandId != null) {
      OneovaSmartStatus.show(
        context,
        title: commandName,
        subtitle: 'Dispatched live to workstation.',
        kind: OneovaStatusKind.success,
        duration: const Duration(milliseconds: 2200),
        source: 'Online Control',
      );
      if (command == 'render_and_send') {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _isRendering = false);
        });
      }
    } else {
      setState(() => _isRendering = false);
      OneovaSmartStatus.show(
        context,
        title: 'Command Failed',
        subtitle: 'Could not dispatch "$commandName". Check connection.',
        kind: OneovaStatusKind.error,
        source: 'Online Control',
        actionLabel: 'Reconnect',
        onAction: _refreshAndReconnect,
      );
    }
  }

  Rect _computeRenderedScreenRect(Size viewport) {
    final renderer = ref.read(webrtcDesktopProvider).connections[_boundDeviceId]?.renderer;
    final vw = renderer?.videoWidth ?? 0;
    final vh = renderer?.videoHeight ?? 0;
    final src = vw > 0 && vh > 0
        ? Size(vw.toDouble(), vh.toDouble())
        : Size(
            _remoteWidth > 0 ? _remoteWidth.toDouble() : 1920.0,
            _remoteHeight > 0 ? _remoteHeight.toDouble() : 1080.0,
          );
    final fitted = applyBoxFit(BoxFit.contain, src, viewport);
    final dstW = fitted.destination.width;
    final dstH = fitted.destination.height;
    final left = (viewport.width - dstW) / 2.0;
    final top = (viewport.height - dstH) / 2.0;
    return Rect.fromLTWH(left, top, dstW, dstH);
  }

  ({double nx, double ny})? _localToNormalized(Offset localPos, Size viewport) {
    final rect = _computeRenderedScreenRect(viewport);
    if (rect.width <= 1 || rect.height <= 1) return null;
    if (!rect.inflate(12).contains(localPos)) return null;
    final nx = ((localPos.dx - rect.left) / rect.width).clamp(0.0, 1.0);
    final ny = ((localPos.dy - rect.top) / rect.height).clamp(0.0, 1.0);
    return (nx: nx, ny: ny);
  }

  void _triggerTapRipple(Offset localPos, double nx, double ny) {
    setState(() {
      _tapRipplePos = localPos;
      _tapRippleSeq++;
      _cursorNx = nx;
      _cursorNy = ny;
    });
    final seq = _tapRippleSeq;
    Future.delayed(const Duration(milliseconds: 520), () {
      if (mounted && _tapRippleSeq == seq) {
        setState(() => _tapRipplePos = null);
      }
    });
  }

  // ── Touch → mouse ────────────────────────────────────────────────────────
  // One finger is the mouse: tap = click where you touch, drag = the cursor
  // follows the finger, hold then drag = click-and-drag, hold and release =
  // right-click. Two fingers: pinch = zoom into the stream, drag = scroll the
  // computer (or move around while zoomed in), quick tap = right-click.
  final Map<int, Offset> _touches = {};
  Offset? _touchDownPos;
  DateTime? _touchDownAt;
  bool _touchMoved = false;
  bool _grabArmed = false;
  bool _leftButtonHeld = false;
  Timer? _grabTimer;
  String _twoMode = '';
  double _twoStartDist = 0;
  Offset _twoStartFocal = Offset.zero;
  Offset _twoLastFocal = Offset.zero;
  Matrix4 _twoStartMatrix = Matrix4.identity();
  DateTime? _twoStartAt;
  bool _hadTwoFingers = false;
  Offset? _lastTapScene;
  DateTime? _lastTapAt;
  double _zoom = 1.0;
  DateTime? _padLastTapAt;
  bool _railOnRight = true;
  bool? _wasLandscape;
  static const double _railWidth = 68;
  static const _railSideKey = 'online_control_rail_right';
  late final WebRTCDesktopService _webrtcService = ref.read(webrtcDesktopProvider.notifier);
  LiveKeyboardStyle? _keyboardStyle;

  Offset _toScene(Offset local) => _transformationController.toScene(local);

  void _onZoomChanged() {
    final s = _transformationController.value.getMaxScaleOnAxis();
    if ((s - _zoom).abs() > 0.01 && mounted) setState(() => _zoom = s);
  }

  void _resetZoom() {
    HapticFeedback.selectionClick();
    _transformationController.value = Matrix4.identity();
  }

  /// High-rate packets ride the unordered fast lane; dropped if not connected.
  void _sendFast(Map<String, dynamic> packet) {
    final id = ref.read(remoteConnectProvider).activeComputerId ?? _boundDeviceId;
    if (id == null) return;
    ref.read(webrtcDesktopProvider.notifier).sendFastPacket(id, packet);
  }

  void _moveCursorTo(Offset local, Size viewport) {
    final norm = _localToNormalized(_toScene(local), viewport);
    if (norm == null) return;
    _cursorNx = norm.nx;
    _cursorNy = norm.ny;
    _sendFast({'a': 'mt', 'nx': norm.nx, 'ny': norm.ny});
  }

  void _onViewportPointerDown(PointerDownEvent e, Size viewport) {
    if (!_isTouchMouseActive) return;
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 1) {
      _hadTwoFingers = false;
      _touchDownPos = e.localPosition;
      _touchDownAt = DateTime.now();
      _touchMoved = false;
      _grabArmed = false;
      _grabTimer?.cancel();
      _grabTimer = Timer(const Duration(milliseconds: 420), () {
        final down = _touchDownPos;
        if (_touches.length == 1 && !_touchMoved && down != null && mounted) {
          _grabArmed = true;
          HapticFeedback.mediumImpact();
          _moveCursorTo(down, viewport);
        }
      });
    } else if (_touches.length == 2) {
      _grabTimer?.cancel();
      if (_leftButtonHeld) _releaseLeft();
      _hadTwoFingers = true;
      final pts = _touches.values.toList();
      _twoStartDist = (pts[0] - pts[1]).distance;
      _twoStartFocal = (pts[0] + pts[1]) / 2;
      _twoLastFocal = _twoStartFocal;
      _twoStartMatrix = _transformationController.value.clone();
      _twoStartAt = DateTime.now();
      _twoMode = '';
    }
  }

  void _onViewportPointerMove(PointerMoveEvent e, Size viewport) {
    if (!_isTouchMouseActive || !_touches.containsKey(e.pointer)) return;
    _touches[e.pointer] = e.localPosition;

    if (_touches.length == 1 && !_hadTwoFingers) {
      final down = _touchDownPos;
      if (down == null) return;
      if (!_touchMoved && (e.localPosition - down).distance > 8) {
        _touchMoved = true;
        _grabTimer?.cancel();
        if (_grabArmed && !_leftButtonHeld) {
          _moveCursorTo(down, viewport);
          _leftButtonHeld = true;
          HapticFeedback.selectionClick();
          _sendControlPacket({'action': 'mouse_left_down'});
        }
      }
      if (_touchMoved) _moveCursorTo(e.localPosition, viewport);
      return;
    }

    if (_touches.length >= 2) {
      final pts = _touches.values.take(2).toList();
      final dist = (pts[0] - pts[1]).distance;
      final focal = (pts[0] + pts[1]) / 2;
      if (_twoMode.isEmpty) {
        if ((dist - _twoStartDist).abs() > 22) {
          _twoMode = 'pinch';
        } else if ((focal - _twoStartFocal).distance > 10) {
          _twoMode = _zoom > 1.02 ? 'pan' : 'scroll';
        }
      }
      switch (_twoMode) {
        case 'pinch':
        case 'pan':
          final startScale = _twoStartMatrix.getMaxScaleOnAxis();
          final scale = _twoMode == 'pinch' && _twoStartDist > 0
              ? (startScale * dist / _twoStartDist).clamp(1.0, 6.0)
              : startScale;
          _applyZoom(scale, focal, viewport);
        case 'scroll':
          final d = focal - _twoLastFocal;
          _sendFast({'a': 'sc', 'dx': d.dx * 1.4, 'dy': d.dy * 1.4});
      }
      _twoLastFocal = focal;
    }
  }

  /// Zooms so the point first under the fingers stays under them, and keeps
  /// the stream edge-to-edge (no empty gutters while zoomed in).
  void _applyZoom(double scale, Offset focal, Size viewport) {
    final scene = MatrixUtils.transformPoint(
      Matrix4.inverted(_twoStartMatrix),
      _twoStartFocal,
    );
    final tx = (focal.dx - scene.dx * scale).clamp(viewport.width * (1 - scale), 0.0);
    final ty = (focal.dy - scene.dy * scale).clamp(viewport.height * (1 - scale), 0.0);
    _transformationController.value = Matrix4.diagonal3Values(scale, scale, 1.0)
      ..setTranslationRaw(tx, ty, 0.0);
  }

  void _onViewportPointerUp(PointerUpEvent e, Size viewport) {
    if (!_isTouchMouseActive) return;
    final wasCount = _touches.length;
    _touches.remove(e.pointer);

    if (wasCount >= 2) {
      final start = _twoStartAt;
      if (_twoMode.isEmpty &&
          start != null &&
          DateTime.now().difference(start).inMilliseconds < 320) {
        _dispatchNormalizedTap(_toScene(_twoStartFocal), viewport, rightClick: true);
      }
      _twoStartAt = null;
      if (_touches.length < 2) _twoMode = 'done';
      return;
    }
    if (_touches.isNotEmpty) return;

    _grabTimer?.cancel();
    if (_hadTwoFingers) {
      _resetTouch();
      return;
    }
    if (_leftButtonHeld) {
      _releaseLeft();
    } else if (_grabArmed && !_touchMoved) {
      _dispatchNormalizedTap(_toScene(e.localPosition), viewport, rightClick: true);
    } else if (!_touchMoved &&
        _touchDownAt != null &&
        DateTime.now().difference(_touchDownAt!).inMilliseconds < 380) {
      final scene = _toScene(e.localPosition);
      final now = DateTime.now();
      final lastAt = _lastTapAt;
      final lastPos = _lastTapScene;
      final isDouble = lastAt != null &&
          lastPos != null &&
          now.difference(lastAt).inMilliseconds < 320 &&
          (scene - lastPos).distance < 28;
      if (isDouble) {
        _dispatchNormalizedTap(scene, viewport, doubleClick: true);
        _lastTapAt = null;
      } else {
        _dispatchNormalizedTap(scene, viewport);
        _lastTapAt = now;
        _lastTapScene = scene;
      }
    }
    _resetTouch();
  }

  void _onViewportPointerCancel(PointerCancelEvent e) {
    _touches.remove(e.pointer);
    if (_touches.isEmpty) {
      if (_leftButtonHeld) _releaseLeft();
      _resetTouch();
    }
  }

  void _releaseLeft() {
    _leftButtonHeld = false;
    _sendControlPacket({'action': 'mouse_left_up'});
  }

  void _resetTouch() {
    _grabTimer?.cancel();
    _grabArmed = false;
    _touchMoved = false;
    _touchDownPos = null;
    _touchDownAt = null;
    _hadTwoFingers = false;
    _twoMode = '';
  }

  void _dispatchNormalizedTap(
    Offset localPos,
    Size viewport, {
    bool rightClick = false,
    bool doubleClick = false,
  }) {
    final norm = _localToNormalized(localPos, viewport);
    if (norm == null) return;
    _triggerTapRipple(localPos, norm.nx, norm.ny);
    if (rightClick) {
      HapticFeedback.heavyImpact();
      _sendControlPacket({
        'action': 'mouse_right_click_normalized',
        'nx': norm.nx,
        'ny': norm.ny,
      });
    } else if (doubleClick) {
      HapticFeedback.mediumImpact();
      _sendControlPacket({
        'action': 'mouse_double_click_normalized',
        'nx': norm.nx,
        'ny': norm.ny,
      });
    } else {
      HapticFeedback.lightImpact();
      _sendControlPacket({
        'action': 'mouse_click_normalized',
        'nx': norm.nx,
        'ny': norm.ny,
      });
    }
  }

  void _handleZoomDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.1) {
      _transformationController.value = Matrix4.identity();
    } else {
      final pos = _doubleTapPosition ?? Offset.zero;
      final x = -pos.dx * 1.4;
      final y = -pos.dy * 1.4;
      _transformationController.value = Matrix4.diagonal3Values(2.4, 2.4, 1.0)
        ..setTranslationRaw(x, y, 0.0);
    }
  }

  void _toggleOrientation() {
    final orientation = MediaQuery.of(context).orientation;
    if (orientation == Orientation.portrait) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  Future<void> _syncClipboardSheet() async {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        decoration: BoxDecoration(
          color: sheetCtx.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          border: Border.all(color: sheetCtx.border, width: 1.0),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: sheetCtx.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Live Clipboard Bridge',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: sheetCtx.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Transfer copied text instantly between your phone and linked computer.',
                style: GoogleFonts.inter(fontSize: 12, color: sheetCtx.textSecondary),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                        onPressed: () async {
                          Navigator.pop(sheetCtx);
                          final data = await Clipboard.getData(Clipboard.kTextPlain);
                          final text = data?.text ?? '';
                          if (text.isEmpty) {
                            if (mounted) {
                              OneovaSmartStatus.show(
                                context,
                                title: 'Mobile Clipboard Empty',
                                kind: OneovaStatusKind.warning,
                                source: 'Clipboard',
                              );
                            }
                            return;
                          }
                          await _sendCommand('sync_clipboard', 'Sent Clipboard to Mac', {
                            'text': text,
                          });
                        },
                        icon: const Icon(Icons.upload_rounded, size: 17),
                        label: Text(
                          'Phone → Computer',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: sheetCtx.border, width: 1.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                        onPressed: () async {
                          Navigator.pop(sheetCtx);
                          final cmdId = await ref
                              .read(remoteConnectProvider.notifier)
                              .sendCommand('system', 'sync_clipboard', {'text': ''});
                          if (cmdId == null) return;
                          final sub = ref
                              .read(remoteConnectProvider.notifier)
                              .listenToCommand(cmdId);
                          if (sub == null) return;
                          late StreamSubscription<DocumentSnapshot> listener;
                          listener = sub.listen((snap) async {
                            final d = snap.data() as Map<String, dynamic>?;
                            if (d == null) return;
                            if (d['status'] == 'completed') {
                              await listener.cancel();
                              final macClip = (d['clipboard_text'] ?? '').toString();
                              if (macClip.isNotEmpty) {
                                await Clipboard.setData(ClipboardData(text: macClip));
                              }
                              if (mounted) {
                                OneovaSmartStatus.show(
                                  context,
                                  title: macClip.isNotEmpty
                                      ? 'Copied from Computer (${macClip.length} chars)'
                                      : 'Computer Clipboard Empty',
                                  subtitle: macClip.isNotEmpty ? macClip : null,
                                  kind: OneovaStatusKind.success,
                                  source: 'Clipboard',
                                );
                              }
                            }
                          });
                        },
                        icon: Icon(
                          Icons.download_rounded,
                          size: 17,
                          color: sheetCtx.textPrimary,
                        ),
                        label: Text(
                          'Computer → Phone',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: sheetCtx.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _loggedFirstBuild = false;

  @override
  Widget build(BuildContext context) {
    if (!_loggedFirstBuild) {
      _loggedFirstBuild = true;
      debugPrint('[OnlineControl] panel first build');
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => debugPrint('[OnlineControl] panel first frame painted'),
      );
    }
    final remoteState = ref.watch(remoteConnectProvider);
    final webrtcState = ref.watch(webrtcDesktopProvider);

    final activeComputer = remoteState.activeComputer ??
        LinkedComputer(id: 'unknown', name: 'Remote Workstation', isOnline: false);
    final activeComputerId = activeComputer.id == 'unknown' ? null : activeComputer.id;

    if (activeComputerId != null && _boundDeviceId != activeComputerId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bindActiveComputerStreams());
    }

    if (_wasOnline != activeComputer.isOnline && activeComputerId != null) {
      final nowOnline = activeComputer.isOnline;
      _wasOnline = nowOnline;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        OneovaSmartStatus.show(
          context,
          title: nowOnline
              ? '${activeComputer.name} Back Online'
              : '${activeComputer.name} Connection Interrupted',
          subtitle: nowOnline
              ? 'Live screen & interactive bridge restored automatically.'
              : 'Auto-reconnect active in background. Tap Reconnect to retry now.',
          kind: nowOnline ? OneovaStatusKind.success : OneovaStatusKind.warning,
          source: 'Online Control',
          actionLabel: nowOnline ? null : 'Reconnect',
          onAction: nowOnline ? null : _refreshAndReconnect,
        );
      });
    }

    final connection =
        activeComputerId != null ? webrtcState.connections[activeComputerId] : null;
    final hasWebRtcVideo =
        connection?.status == WebRTCStatus.connected &&
            connection?.hasVideoStream == true &&
            connection?.renderer != null;
    final hasCloudFrame = _liveFrameBytes != null && _liveFrameBytes!.isNotEmpty;

    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    if (_wasLandscape != landscape) {
      _wasLandscape = landscape;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        SystemChrome.setEnabledSystemUIMode(
          landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        );
      });
    }
    final leftInset = landscape && !_railOnRight ? _railWidth : 0.0;
    final rightInset = landscape && _railOnRight ? _railWidth : 0.0;

    return Scaffold(
      backgroundColor: context.bg,
      // The Stack must fill the screen: its only non-positioned children are
      // hidden overlays (SizedBox.shrink), which otherwise size it to 0×0 and
      // the whole panel renders as a blank black page.
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Live computer screen (beside the side rail in landscape).
          Positioned(
            top: 0,
            bottom: 0,
            left: leftInset,
            right: rightInset,
            child: Material(
              color: context.bg,
              child: _buildInteractiveLiveViewport(
                activeComputer: activeComputer,
                connection: connection,
                hasWebRtcVideo: hasWebRtcVideo,
                hasCloudFrame: hasCloudFrame,
              ),
            ),
          ),

          // 2. Status top bar (portrait; the rail carries status in landscape)
          if (!landscape)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildFloatingTopBar(
              computer: activeComputer,
              allComputers: remoteState.linkedComputers,
              hasWebRtcVideo: hasWebRtcVideo,
              hasCloudFrame: hasCloudFrame,
              connection: connection,
            ),
          ),

          // 3. Open Mac Apps Switcher Strip (if toggled)
          if (_isAppsRibbonVisible)
            Positioned(
              top: landscape ? 10 : MediaQuery.of(context).padding.top + 56,
              left: 12 + leftInset,
              right: 12 + rightInset,
              child: _buildOpenAppsStrip(activeComputer),
            ),

          // 4. Floating Precision Trackpad Overlay
          _buildPrecisionTrackpadOverlay(),

          // 5. Virtual Keyboard, Hotkeys & Wispr Dictation Ribbon
          if (!_isAiBarVisible) _buildVirtualKeyboardRibbon(leftInset, rightInset, landscape),

          // Zoom badge (tap to reset) while zoomed into the stream.
          if (_zoom > 1.02)
            Positioned(
              top: landscape ? 10 : MediaQuery.of(context).padding.top + 62,
              right: 12 + rightInset,
              child: GestureDetector(
                onTap: _resetZoom,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    '${_zoom.toStringAsFixed(1)}×  ·  Reset',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),

          // 6. Inline Ova Shared-Account AI Agent Command Bar
          if (_isAiBarVisible) _buildInlineOvaAgentBar(landscape),

          // 7. Compact Bottom Interactive HUD Pill
          if (!_isAiBarVisible && !landscape) _buildFloatingMicroHud(),
          if (landscape) _buildSideRail(activeComputer),
        ],
      ),
    );
  }

  Widget _buildInteractiveLiveViewport({
    required LinkedComputer activeComputer,
    required WebRTCConnection? connection,
    required bool hasWebRtcVideo,
    required bool hasCloudFrame,
  }) {
    if (!hasWebRtcVideo && !hasCloudFrame) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: context.border, width: 1.0),
              boxShadow: AppShadows.sm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: activeComputer.isOnline
                            ? AppColors.brandBlue
                            : AppColors.brandPink,
                      ),
                      Icon(
                        Icons.desktop_mac_rounded,
                        size: 20,
                        color: context.textPrimary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  activeComputer.isOnline
                      ? 'Synchronizing Live Screen...'
                      : '${activeComputer.name} Is Offline or Sleeping',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  activeComputer.isOnline
                      ? 'Establishing interactive screen bridge with ${activeComputer.name}.'
                      : 'Keep Oneova Desktop open on your computer—this panel auto-reconnects as soon as a heartbeat arrives.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.4,
                    color: context.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 38,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                        onPressed: _refreshAndReconnect,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: Text(
                          'Refresh Now',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 38,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: context.border, width: 1.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                        onPressed: () => _showPasskeyUnlockDialog(context),
                        icon: const Icon(
                          Icons.lock_open_rounded,
                          size: 15,
                          color: AppColors.brandPink,
                        ),
                        label: Text(
                          'Wake',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        final fittedRect = _computeRenderedScreenRect(viewport);
        final cursorOffset = Offset(
          fittedRect.left + _cursorNx * fittedRect.width,
          fittedRect.top + _cursorNy * fittedRect.height,
        );

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _onViewportPointerDown(e, viewport),
          onPointerMove: (e) => _onViewportPointerMove(e, viewport),
          onPointerUp: (e) => _onViewportPointerUp(e, viewport),
          onPointerCancel: _onViewportPointerCancel,
          child: GestureDetector(
            onDoubleTapDown: _isTouchMouseActive
                ? null
                : (details) => _doubleTapPosition = details.localPosition,
            onDoubleTap: _isTouchMouseActive ? null : _handleZoomDoubleTap,
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 1.0,
              maxScale: 6.0,
              // In Control mode the gestures above drive zoom and pan, so one
              // finger is always the mouse and two fingers zoom/scroll.
              panEnabled: !_isTouchMouseActive,
              scaleEnabled: !_isTouchMouseActive,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: hasWebRtcVideo
                        ? RTCVideoView(
                            connection!.renderer!,
                            objectFit:
                                RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                          )
                        : Image.memory(
                            _liveFrameBytes!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                          ),
                  ),

                  // Live macOS Cursor Reticle (shown on Cloud Frame Bridge)
                  if (!hasWebRtcVideo && hasCloudFrame)
                    Positioned(
                      left: cursorOffset.dx - 9,
                      top: cursorOffset.dy - 9,
                      child: IgnorePointer(
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.brandBlue.withValues(alpha: 0.28),
                            border: Border.all(color: Colors.white, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.brandBlue.withValues(alpha: 0.5),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Interactive Touch Ripple
                  if (_tapRipplePos != null)
                    Positioned(
                      left: _tapRipplePos!.dx - 20,
                      top: _tapRipplePos!.dy - 20,
                      child: IgnorePointer(
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.brandPink.withValues(alpha: 0.22),
                            border: Border.all(
                              color: AppColors.brandPink,
                              width: 1.5,
                            ),
                          ),
                        )
                            .animate(key: ValueKey(_tapRippleSeq))
                            .scale(
                              begin: const Offset(0.45, 0.45),
                              end: const Offset(1.25, 1.25),
                              duration: 360.ms,
                              curve: Curves.easeOutCubic,
                            )
                            .fadeOut(duration: 380.ms),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloatingTopBar({
    required LinkedComputer computer,
    required List<LinkedComputer> allComputers,
    required bool hasWebRtcVideo,
    required bool hasCloudFrame,
    required WebRTCConnection? connection,
  }) {
    final transportLabel = hasWebRtcVideo
        ? 'WEBRTC 30FPS'
        : hasCloudFrame
            ? 'LIVE STREAM'
            : (connection?.status == WebRTCStatus.connecting
                ? 'CONNECTING'
                : 'RECONNECTING');

    final telemetryLabel = _cpuPercent != null
        ? 'CPU ${_cpuPercent!.round()}%${_ramPercent != null ? " • RAM ${_ramPercent!.round()}%" : ""}'
        : (computer.activeWindow ?? 'Desktop');

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: context.surface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: context.border, width: 1.0),
                boxShadow: AppShadows.sm,
              ),
              child: Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    tooltip: 'Back',
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: context.textPrimary,
                      size: 16,
                    ),
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/hub/home');
                      }
                    },
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: (hasWebRtcVideo || hasCloudFrame || computer.isOnline)
                          ? AppColors.brandBlue
                          : AppColors.brandPink,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: allComputers.length > 1
                          ? () => _showDeviceSwitcherSheet(allComputers, computer.id)
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  computer.name,
                                  style: GoogleFonts.inter(
                                    color: context.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (allComputers.length > 1)
                                Icon(
                                  Icons.arrow_drop_down_rounded,
                                  size: 16,
                                  color: context.textSecondary,
                                ),
                            ],
                          ),
                          Text(
                            '${computer.activeWindow ?? "Desktop"} • $telemetryLabel',
                            style: GoogleFonts.inter(
                              color: context.textSecondary,
                              fontSize: 9.8,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(
                        color: AppColors.brandBlue.withValues(alpha: 0.4),
                        width: 1.0,
                      ),
                    ),
                    child: Text(
                      transportLabel,
                      style: GoogleFonts.inter(
                        color: AppColors.brandBlue,
                        fontSize: 8.8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    padding: EdgeInsets.zero,
                    tooltip: 'Refresh & Reconnect Stream',
                    onPressed: _isRefreshingConnection ? null : _refreshAndReconnect,
                    icon: _isRefreshingConnection
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: AppColors.brandBlue,
                            ),
                          )
                        : Icon(
                            Icons.refresh_rounded,
                            color: context.textPrimary,
                            size: 18,
                          ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    padding: EdgeInsets.zero,
                    tooltip: 'Status & Error History',
                    onPressed: () => OneovaSmartStatus.showHistorySheet(context),
                    icon: Icon(
                      Icons.history_rounded,
                      color: context.textPrimary,
                      size: 18,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    padding: EdgeInsets.zero,
                    tooltip: 'Hardware Telemetry',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const TelemetryDashboardScreen(),
                        ),
                      );
                    },
                    icon: Icon(
                      Icons.speed_rounded,
                      color: context.textSecondary,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOpenAppsStrip(LinkedComputer computer) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: context.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Row(
            children: [
              const Icon(Icons.apps_rounded, size: 15, color: AppColors.brandBlue),
              const SizedBox(width: 6),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _openApps.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final app = _openApps[index];
                    final isCurrent =
                        (computer.activeWindow ?? '').toLowerCase() == app.toLowerCase();
                    return Center(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _sendCommand('switch_app', 'Switched to $app', {
                            'appName': app,
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isCurrent ? AppColors.brandBlue : context.surfaceMid,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            border: Border.all(
                              color: isCurrent ? AppColors.brandBlue : context.border,
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            app,
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: isCurrent ? Colors.white : context.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _isAppsRibbonVisible = false),
                icon: Icon(Icons.close_rounded, size: 15, color: context.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineOvaAgentBar(bool landscape) {
    final computer = ref.read(remoteConnectProvider).activeComputer;
    final copilot = OvaLiveCopilot(
      computerName: computer?.name ?? 'your computer',
      activeWindow: computer?.activeWindow,
      docked: landscape,
      onClose: () => setState(() => _isAiBarVisible = false),
    );
    if (!landscape) {
      return Positioned(left: 0, right: 0, bottom: 0, child: copilot);
    }
    final width = MediaQuery.sizeOf(context).width * 0.40;
    return Positioned(
      top: 0,
      bottom: 0,
      width: width,
      left: _railOnRight ? 0 : null,
      right: _railOnRight ? null : 0,
      child: copilot,
    );
  }

  Widget _buildFloatingMicroHud() {
    return Positioned(
      left: 8,
      right: 8,
      bottom: MediaQuery.of(context).padding.bottom + 10,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: context.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: context.border, width: 1.0),
                boxShadow: AppShadows.sm,
              ),
              child: _isHudCollapsed ? _buildCollapsedHud() : _buildExpandedHud(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedHud() {
    return InkWell(
      onTap: () => setState(() => _isHudCollapsed = false),
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.brandBlue,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Online Control Tools',
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.unfold_more_rounded, size: 16, color: context.textSecondary),
          ],
        ),
      ),
    );
  }

  /// Every control the panel offers, in one place. The portrait pill and the
  /// landscape side rail both render this list; [primary] items are shown
  /// directly, the rest sit under "More".
  List<({IconData icon, String label, bool active, bool special, bool primary, VoidCallback onTap})>
      _controlItems() {
    void toggle(void Function() change) {
      HapticFeedback.lightImpact();
      setState(change);
    }

    return [
      (
        icon: _isTouchMouseActive ? Icons.touch_app_rounded : Icons.visibility_rounded,
        label: _isTouchMouseActive ? 'Control' : 'View',
        active: _isTouchMouseActive,
        special: false,
        primary: true,
        onTap: () => toggle(() => _isTouchMouseActive = !_isTouchMouseActive),
      ),
      (
        icon: Icons.mouse_rounded,
        label: 'Mouse pad',
        active: _isTrackpadVisible,
        special: false,
        primary: true,
        onTap: () => toggle(() => _isTrackpadVisible = !_isTrackpadVisible),
      ),
      (
        icon: Icons.keyboard_rounded,
        label: 'Keyboard',
        active: _isKeyboardRibbonVisible,
        special: false,
        primary: true,
        onTap: () => toggle(() {
          _isKeyboardRibbonVisible = !_isKeyboardRibbonVisible;
          if (_isKeyboardRibbonVisible) _isAiBarVisible = false;
        }),
      ),
      (
        icon: Icons.auto_awesome_rounded,
        label: 'Ova',
        active: _isAiBarVisible,
        special: true,
        primary: true,
        onTap: () => toggle(() {
          _isAiBarVisible = !_isAiBarVisible;
          if (_isAiBarVisible) _isKeyboardRibbonVisible = false;
        }),
      ),
      (
        icon: Icons.apps_rounded,
        label: 'Apps',
        active: _isAppsRibbonVisible,
        special: false,
        primary: true,
        onTap: () => toggle(() => _isAppsRibbonVisible = !_isAppsRibbonVisible),
      ),
      (
        icon: Icons.content_paste_go_rounded,
        label: 'Clipboard',
        active: false,
        special: false,
        primary: false,
        onTap: _syncClipboardSheet,
      ),
      (
        icon: Icons.lock_open_rounded,
        label: 'Wake & unlock',
        active: false,
        special: false,
        primary: false,
        onTap: () => _showPasskeyUnlockDialog(context),
      ),
      (
        icon: Icons.fit_screen_rounded,
        label: 'Fit screen',
        active: false,
        special: false,
        primary: false,
        onTap: _resetZoom,
      ),
      (
        icon: Icons.screen_rotation_rounded,
        label: 'Rotate',
        active: false,
        special: false,
        primary: false,
        onTap: _toggleOrientation,
      ),
      (
        icon: Icons.tune_rounded,
        label: 'Settings',
        active: false,
        special: false,
        primary: false,
        onTap: () => _showStudioControlsModal(context),
      ),
    ];
  }

  void _showMoreControls() {
    HapticFeedback.selectionClick();
    final secondary = _controlItems().where((i) => !i.primary).toList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: sheetCtx.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: sheetCtx.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final i in secondary)
                ListTile(
                  dense: true,
                  leading: Icon(i.icon, color: sheetCtx.textPrimary),
                  title: Text(i.label,
                      style: GoogleFonts.inter(fontSize: 14, color: sheetCtx.textPrimary)),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    i.onTap();
                  },
                ),
              if (MediaQuery.orientationOf(context) == Orientation.landscape)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.swap_horiz_rounded, color: sheetCtx.textPrimary),
                  title: Text(_railOnRight ? 'Move controls to the left' : 'Move controls to the right',
                      style: GoogleFonts.inter(fontSize: 14, color: sheetCtx.textPrimary)),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _swapRailSide();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _swapRailSide() {
    HapticFeedback.mediumImpact();
    setState(() => _railOnRight = !_railOnRight);
    SharedPreferences.getInstance().then((p) => p.setBool(_railSideKey, _railOnRight));
  }

  Widget _buildExpandedHud() {
    final items = _controlItems().where((i) => i.primary);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHudIconButton(
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: 'Collapse toolbar',
            onTap: () => setState(() => _isHudCollapsed = true),
          ),
          _buildHudDivider(),
          for (final i in items)
            _buildHudIconButton(
              icon: i.icon,
              tooltip: i.label,
              isActive: i.active,
              isSpecial: i.special,
              activeColor: i.special ? AppColors.brandPink : null,
              onTap: i.onTap,
            ),
          _buildHudDivider(),
          _buildHudIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: 'More',
            onTap: _showMoreControls,
          ),
        ],
      ),
    );
  }

  /// Landscape: controls live in a slim side rail (left or right, remembered).
  Widget _buildSideRail(LinkedComputer computer) {
    final items = _controlItems().where((i) => i.primary);
    final connected = ref.watch(webrtcDesktopProvider
            .select((s) => s.connections[_boundDeviceId]?.isDataChannelOpen)) ==
        true;
    Widget railButton(IconData icon, String label, VoidCallback onTap,
        {bool active = false, bool special = false}) {
      final accent = special ? AppColors.brandPink : AppColors.brandBlue;
      final fg = active || special ? accent : context.textPrimary;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          width: _railWidth - 12,
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: active ? accent.withValues(alpha: 0.55) : Colors.transparent),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(height: 3),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 9.5, fontWeight: FontWeight.w600, color: fg)),
          ]),
        ),
      );
    }

    return Positioned(
      top: 0,
      bottom: 0,
      left: _railOnRight ? null : 0,
      right: _railOnRight ? 0 : null,
      width: _railWidth,
      child: Container(
        decoration: BoxDecoration(
          color: context.surface,
          border: Border(
            left: _railOnRight ? BorderSide(color: context.border) : BorderSide.none,
            right: _railOnRight ? BorderSide.none : BorderSide(color: context.border),
          ),
        ),
        child: SafeArea(
          left: !_railOnRight,
          right: _railOnRight,
          child: Column(
            children: [
              const SizedBox(height: 6),
              railButton(Icons.arrow_back_rounded, 'Back', () => context.pop()),
              const SizedBox(height: 4),
              Tooltip(
                message: '${computer.name} • ${connected ? 'Live' : 'Connecting'}',
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: connected ? const Color(0xFF2EBD6B) : const Color(0xFFF5A623),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final i in items) ...[
                        railButton(i.icon, i.label, i.onTap, active: i.active, special: i.special),
                        const SizedBox(height: 4),
                      ],
                    ],
                  ),
                ),
              ),
              railButton(Icons.swap_horiz_rounded, 'Side', _swapRailSide),
              railButton(Icons.more_horiz_rounded, 'More', _showMoreControls),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHudIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool isActive = false,
    bool isSpecial = false,
    Color? activeColor,
  }) {
    final accent = activeColor ?? (isSpecial ? AppColors.brandPink : AppColors.brandBlue);
    final fg = (isActive || isSpecial) ? accent : context.textPrimary;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: (isActive || isSpecial)
                ? accent.withValues(alpha: 0.16)
                : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? accent.withValues(alpha: 0.6) : Colors.transparent,
              width: 1.0,
            ),
          ),
          child: Icon(icon, size: 17, color: fg),
        ),
      ),
    );
  }

  Widget _buildHudDivider() {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: context.border,
    );
  }

  Widget _buildPrecisionTrackpadOverlay() {
    if (!_isTrackpadVisible) return const SizedBox.shrink();

    return Positioned(
      left: _trackpadPosition.dx,
      top: _trackpadPosition.dy,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 224,
            height: 184,
            decoration: BoxDecoration(
              color: context.surface.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: context.border, width: 1.0),
              boxShadow: AppShadows.sm,
            ),
            child: Column(
              children: [
                GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _trackpadPosition = Offset(
                        (_trackpadPosition.dx + details.delta.dx)
                            .clamp(0.0, MediaQuery.of(context).size.width - 224),
                        (_trackpadPosition.dy + details.delta.dy)
                            .clamp(50.0, MediaQuery.of(context).size.height - 200),
                      );
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    color: context.surfaceMid,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.drag_indicator_rounded,
                              size: 15,
                              color: context.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Precision Trackpad',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: context.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: () => setState(() => _isTrackpadVisible = false),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            // Pointer acceleration: slow = precise, fast = far.
                            final d = details.delta;
                            final speed = d.distance;
                            final gain = (1.4 + speed * 0.12).clamp(1.4, 4.2);
                            _sendFast({'a': 'mv', 'dx': d.dx * gain, 'dy': d.dy * gain});
                          },
                          // No onDoubleTap: it would delay every single click.
                          onTap: () {
                            final now = DateTime.now();
                            final last = _padLastTapAt;
                            if (last != null && now.difference(last).inMilliseconds < 300) {
                              HapticFeedback.mediumImpact();
                              _sendControlPacket({'action': 'mouse_double_click'});
                              _padLastTapAt = null;
                            } else {
                              HapticFeedback.lightImpact();
                              _sendControlPacket({'action': 'mouse_left_click'});
                              _padLastTapAt = now;
                            }
                          },
                          onLongPress: () {
                            HapticFeedback.heavyImpact();
                            _sendControlPacket({'action': 'mouse_right_click'});
                          },
                          child: Container(
                            margin: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: context.surfaceMid,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              border: Border.all(color: context.border, width: 1.0),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.touch_app_rounded,
                                    size: 22,
                                    color: context.textMuted,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Glide • Tap L • Hold R',
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      color: context.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onVerticalDragUpdate: (details) {
                          _sendFast({'a': 'sc', 'dx': 0.0, 'dy': details.delta.dy * 2.0});
                        },
                        child: Container(
                          width: 28,
                          margin: const EdgeInsets.only(top: 6, bottom: 6, right: 6),
                          decoration: BoxDecoration(
                            color: context.surfaceMid,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(color: context.border, width: 1.0),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.swap_vert_rounded,
                              size: 16,
                              color: context.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 32,
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: context.border, width: 1.0)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _sendControlPacket({'action': 'mouse_left_click'});
                          },
                          child: Center(
                            child: Text(
                              'Left',
                              style: GoogleFonts.inter(
                                color: context.textPrimary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(width: 1, color: context.border),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setState(() => _isTrackpadDragLocked = !_isTrackpadDragLocked);
                            if (_isTrackpadDragLocked) {
                              HapticFeedback.heavyImpact();
                              _sendControlPacket({'action': 'mouse_left_down'});
                            } else {
                              HapticFeedback.lightImpact();
                              _sendControlPacket({'action': 'mouse_left_up'});
                            }
                          },
                          child: Container(
                            color: _isTrackpadDragLocked
                                ? AppColors.brandPink.withValues(alpha: 0.16)
                                : Colors.transparent,
                            child: Center(
                              child: Text(
                                _isTrackpadDragLocked ? 'Dragging' : 'Drag Lock',
                                style: GoogleFonts.inter(
                                  color: _isTrackpadDragLocked
                                      ? AppColors.brandPink
                                      : context.textPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(width: 1, color: context.border),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            _sendControlPacket({'action': 'mouse_right_click'});
                          },
                          child: Center(
                            child: Text(
                              'Right',
                              style: GoogleFonts.inter(
                                color: context.textPrimary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVirtualKeyboardRibbon(double leftInset, double rightInset, bool landscape) {
    if (!_isKeyboardRibbonVisible) return const SizedBox.shrink();
    final os = (ref.read(remoteConnectProvider).activeComputer?.os ?? '').toLowerCase();
    final style = _keyboardStyle ??
        (os.contains('win') ? LiveKeyboardStyle.windows : LiveKeyboardStyle.mac);
    return Positioned(
      left: 6 + leftInset,
      right: 6 + rightInset,
      bottom: landscape
          ? 6
          : MediaQuery.of(context).padding.bottom + (_isHudCollapsed ? 58 : 62),
      child: LiveKeyboard(
        style: style,
        onStyleChanged: (s) => setState(() => _keyboardStyle = s),
        onClose: () => setState(() => _isKeyboardRibbonVisible = false),
        onKey: (k) => _sendControlPacket({'action': 'key_tap', 'key': k}),
        onCombo: (c) => _sendControlPacket({'action': 'key_combination', 'combo': c}),
      ),
    );
  }

  void _showDeviceSwitcherSheet(List<LinkedComputer> computers, String currentId) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        decoration: BoxDecoration(
          color: sheetCtx.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          border: Border.all(color: sheetCtx.border, width: 1.0),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Switch Active Workstation',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: sheetCtx.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              for (final c in computers)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.desktop_mac_rounded,
                    color: c.isOnline ? AppColors.brandBlue : sheetCtx.textMuted,
                  ),
                  title: Text(
                    c.name,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: sheetCtx.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    c.isOnline
                        ? 'Online • ${c.activeWindow ?? "Desktop"}'
                        : 'Offline',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: sheetCtx.textSecondary,
                    ),
                  ),
                  trailing: c.id == currentId
                      ? const Icon(Icons.check_circle_rounded, color: AppColors.brandBlue)
                      : null,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    ref.read(remoteConnectProvider.notifier).setActiveComputer(c.id);
                    _bindActiveComputerStreams();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPasskeyUnlockDialog(BuildContext context) async {
    final passkeyController = TextEditingController();
    bool isObscured = true;
    bool isUnlocking = false;
    bool rememberForBiometrics = true;
    final activeComputerId =
        ref.read(remoteConnectProvider).activeComputerId ?? 'default';
    final savedPasskey =
        await _secureStorage.read(key: 'workstation_passkey_$activeComputerId');
    final hasSavedPasskey = savedPasskey != null && savedPasskey.isNotEmpty;

    if (!context.mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
              ),
              decoration: BoxDecoration(
                color: dialogCtx.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.xl),
                ),
                border: Border.all(color: dialogCtx.border, width: 1.0),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: dialogCtx.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.brandBlue.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: const Icon(
                          Icons.vpn_key_rounded,
                          color: AppColors.brandBlue,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Wake & Unlock Workstation',
                              style: GoogleFonts.inter(
                                color: dialogCtx.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15.5,
                              ),
                            ),
                            Text(
                              hasSavedPasskey
                                  ? '1-Tap Biometric Resume ready'
                                  : 'Resume workstation session seamlessly from sleep',
                              style: GoogleFonts.inter(
                                color: hasSavedPasskey
                                    ? AppColors.brandPink
                                    : dialogCtx.textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      icon: const Icon(Icons.fingerprint_rounded, size: 20),
                      label: Text(
                        hasSavedPasskey
                            ? 'Instant Biometric Resume'
                            : 'Wake Display with Biometrics',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: isUnlocking
                          ? null
                          : () async {
                              final biometrics =
                                  ref.read(oneovaBiometricsServiceProvider);
                              final authenticated = await biometrics.authenticate(
                                reason: 'Authenticate to wake & unlock workstation',
                              );
                              if (authenticated) {
                                setDialogState(() => isUnlocking = true);
                                final passToDispatch =
                                    hasSavedPasskey ? savedPasskey : '';
                                _sendControlPacket({
                                  'action': 'wake_and_unlock',
                                  'passkey': passToDispatch,
                                });
                                HapticFeedback.mediumImpact();
                                if (dialogCtx.mounted) {
                                  Navigator.pop(dialogCtx);
                                }
                                if (mounted) {
                                  OneovaSmartStatus.show(
                                    this.context,
                                    title: 'Biometric Wake Dispatched',
                                    kind: OneovaStatusKind.success,
                                    source: 'Remote Power',
                                  );
                                }
                              }
                            },
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passkeyController,
                    obscureText: isObscured,
                    style: GoogleFonts.inter(
                      color: dialogCtx.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: dialogCtx.surfaceMid,
                      hintText: 'Or enter computer password / PIN',
                      hintStyle: GoogleFonts.inter(
                        color: dialogCtx.textMuted,
                        fontSize: 12,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      isDense: true,
                      prefixIcon: Icon(
                        Icons.lock_outline_rounded,
                        color: dialogCtx.textSecondary,
                        size: 18,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isObscured
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: dialogCtx.textSecondary,
                          size: 18,
                        ),
                        onPressed: () =>
                            setDialogState(() => isObscured = !isObscured),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: BorderSide(color: dialogCtx.border, width: 1.0),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: BorderSide(color: dialogCtx.border, width: 1.0),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: const BorderSide(
                          color: AppColors.brandBlue,
                          width: 1.0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: rememberForBiometrics,
                        activeColor: AppColors.brandBlue,
                        checkColor: Colors.white,
                        onChanged: (val) => setDialogState(
                          () => rememberForBiometrics = val ?? true,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Store securely for 1-tap Biometric resume',
                          style: GoogleFonts.inter(
                            color: dialogCtx.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: dialogCtx.border, width: 1.0),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                            ),
                            onPressed: () {
                              _sendControlPacket({
                                'action': 'wake_and_unlock',
                                'passkey': '',
                              });
                              Navigator.pop(dialogCtx);
                              OneovaSmartStatus.show(
                                this.context,
                                title: 'Display Wake Sent',
                                kind: OneovaStatusKind.info,
                                source: 'Remote Power',
                              );
                            },
                            child: Text(
                              'Wake Only',
                              style: GoogleFonts.inter(
                                color: dialogCtx.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brandBlue,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                            ),
                            onPressed: isUnlocking
                                ? null
                                : () async {
                                    final pass = passkeyController.text.trim();
                                    setDialogState(() => isUnlocking = true);
                                    if (rememberForBiometrics && pass.isNotEmpty) {
                                      await _secureStorage.write(
                                        key: 'workstation_passkey_$activeComputerId',
                                        value: pass,
                                      );
                                    }
                                    _sendControlPacket({
                                      'action': 'wake_and_unlock',
                                      'passkey': pass,
                                    });
                                    HapticFeedback.lightImpact();
                                    if (dialogCtx.mounted) {
                                      Navigator.pop(dialogCtx);
                                    }
                                    if (mounted) {
                                      OneovaSmartStatus.show(
                                        this.context,
                                        title: 'Unlock Dispatched',
                                        kind: OneovaStatusKind.success,
                                        source: 'Remote Power',
                                      );
                                    }
                                  },
                            child: Text(
                              'Unlock & Resume',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showStudioControlsModal(BuildContext context) {
    final activeComputerId =
        ref.read(remoteConnectProvider).activeComputerId ?? _boundDeviceId;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DefaultTabController(
          length: 3,
          child: Container(
            height: MediaQuery.of(sheetContext).size.height * 0.54,
            decoration: BoxDecoration(
              color: sheetContext.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.xl),
              ),
              border: Border.all(color: sheetContext.border, width: 1.0),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: sheetContext.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                TabBar(
                  indicatorColor: AppColors.brandBlue,
                  labelColor: AppColors.brandBlue,
                  unselectedLabelColor: sheetContext.textSecondary,
                  tabs: const [
                    Tab(icon: Icon(Icons.tune_rounded, size: 18), text: 'Quick Actions'),
                    Tab(icon: Icon(Icons.chat_bubble_rounded, size: 18), text: 'Device Chat'),
                    Tab(icon: Icon(Icons.graphic_eq_rounded, size: 18), text: 'Live Voice'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildControlsTab(sheetContext),
                      _buildChatTab(sheetContext, activeComputerId),
                      _buildVoiceTab(sheetContext),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlsTab(BuildContext sheetCtx) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _buildActionButton(
                sheetCtx,
                Icons.movie_creation_rounded,
                _isRendering ? 'Rendering...' : 'Render',
                () => _sendCommand('render_and_send', 'Render Timeline'),
              ),
              _buildActionButton(
                sheetCtx,
                Icons.play_arrow_rounded,
                'Play / Pause',
                () => _sendCommand('play_pause', 'Play / Pause'),
              ),
              _buildActionButton(
                sheetCtx,
                Icons.sync_rounded,
                'Save Project',
                () => _sendCommand('sync_project', 'Save Project'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildActionButton(
                sheetCtx,
                Icons.bedtime_rounded,
                'Sleep Display',
                () async {
                  Navigator.pop(sheetCtx);
                  await ref.read(remoteConnectProvider.notifier).sleepWorkstation();
                  if (mounted) {
                    OneovaSmartStatus.show(
                      context,
                      title: 'Workstation Display Sleeping',
                      kind: OneovaStatusKind.info,
                      source: 'Remote Power',
                    );
                  }
                },
              ),
              _buildActionButton(
                sheetCtx,
                Icons.auto_awesome_rounded,
                'Open Ova Workspace',
                () {
                  Navigator.pop(sheetCtx);
                  context.push('/hub/ai');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext sheetCtx,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            decoration: BoxDecoration(
              color: sheetCtx.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: sheetCtx.border, width: 1.0),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: AppColors.brandBlue, size: 22),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: sheetCtx.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatTab(BuildContext sheetCtx, String? activeComputerId) {
    if (activeComputerId == null) {
      return Center(
        child: Text(
          'No computer connected',
          style: GoogleFonts.inter(color: sheetCtx.textSecondary),
        ),
      );
    }
    return RemoteChatView(deviceId: activeComputerId);
  }

  Widget _buildVoiceTab(BuildContext sheetCtx) {
    final voiceState = ref.watch(voiceAssistantProvider);
    final isVoiceActive = voiceState.state != VoiceState.idle;

    String statusText = 'Tap to speak with Ova';
    if (voiceState.state == VoiceState.listening) {
      statusText = 'Ova is listening...';
    } else if (voiceState.state == VoiceState.processing) {
      statusText = 'Ova is thinking...';
    } else if (voiceState.state == VoiceState.speaking) {
      statusText = 'Ova is speaking...';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brandBlue.withValues(alpha: 0.14),
              border: Border.all(color: AppColors.brandBlue, width: 1.5),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 36,
              color: AppColors.brandBlue,
            ),
          ),
          const SizedBox(height: 16),
          VoiceWaveVisualizer(isSpeaking: isVoiceActive, height: 42),
          const SizedBox(height: 16),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isVoiceActive ? AppColors.brandPink : AppColors.brandBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              onPressed: () {
                final voiceNotifier = ref.read(voiceAssistantProvider.notifier);
                if (voiceState.state == VoiceState.idle) {
                  voiceNotifier.startListening(continuous: true);
                } else if (voiceState.state == VoiceState.listening) {
                  voiceNotifier.stopListening(force: true);
                } else {
                  voiceNotifier.stopSpeaking(force: true);
                }
              },
              icon: Icon(isVoiceActive ? Icons.mic_rounded : Icons.mic_none_rounded, size: 18),
              label: Text(
                statusText,
                style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (voiceState.currentText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                '"${voiceState.currentText}"',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: sheetCtx.textSecondary,
                  fontStyle: FontStyle.italic,
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
