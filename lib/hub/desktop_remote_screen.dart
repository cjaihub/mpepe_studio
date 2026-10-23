import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../backend/remote_connect_service.dart';
import '../backend/webrtc_desktop_service.dart';
import '../backend/voice_assistant_service.dart';
import '../auth/services/oneova_biometrics_service.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/voice_wave_visualizer.dart';
import 'messaging/remote_chat_view.dart';
import 'telemetry_dashboard_screen.dart';

class DesktopRemoteScreen extends ConsumerStatefulWidget {
  const DesktopRemoteScreen({super.key});

  @override
  ConsumerState<DesktopRemoteScreen> createState() => _DesktopRemoteScreenState();
}

class _DesktopRemoteScreenState extends ConsumerState<DesktopRemoteScreen> with WidgetsBindingObserver {
  // Viewer and zoom transformation
  final TransformationController _transformationController = TransformationController();
  Offset? _doubleTapPosition;

  // Interaction modes
  bool _isTouchMouseActive = false;
  bool _isTrackpadVisible = false;
  bool _isKeyboardRibbonVisible = false;
  bool _isHudCollapsed = false;

  // Trackpad position on screen & drag lock
  Offset _trackpadPosition = const Offset(20, 110);
  bool _isTrackpadDragLocked = false;

  // Direct Touch-to-Mouse pointer tracking & Drag-and-drop
  int _pointerCount = 0;
  Offset? _lastPointerPos;
  Offset? _firstPointerDownPos;
  DateTime? _pointerDownTime;
  Timer? _dragHoldTimer;
  bool _isDragging = false;
  final double _mouseSensitivity = 1.75;

  // Secure storage for biometric passkeys
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // Virtual keyboard text controller
  final TextEditingController _keyboardInputController = TextEditingController();

  // Command state
  bool _isRendering = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activeComputerId = ref.read(remoteConnectProvider).activeComputerId;
      if (activeComputerId != null) {
        ref.read(webrtcDesktopProvider.notifier).connect(activeComputerId);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final activeComputerId = ref.read(remoteConnectProvider).activeComputerId;
      if (activeComputerId != null) {
        final webrtcState = ref.read(webrtcDesktopProvider);
        final conn = webrtcState.connections[activeComputerId];
        if (conn == null || conn.status != WebRTCStatus.connected) {
          ref.read(webrtcDesktopProvider.notifier).connect(activeComputerId);
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dragHoldTimer?.cancel();
    _transformationController.dispose();
    _keyboardInputController.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _sendControlPacket(Map<String, dynamic> packet) {
    final activeId = ref.read(remoteConnectProvider).activeComputerId;
    if (activeId == null) return;

    final sentViaDc = ref.read(webrtcDesktopProvider.notifier).sendControlPacket(activeId, packet);

    // Fallback to Firestore command channel for critical commands if data channel is not yet open
    if (!sentViaDc) {
      final action = packet['action']?.toString() ?? '';
      if (action == 'wake_and_unlock') {
        ref.read(remoteConnectProvider.notifier).sendCommand('system', 'wake_and_unlock', packet);
      } else if (action == 'key_tap' || action == 'key_combination') {
        ref.read(remoteConnectProvider.notifier).sendCommand('system', action, packet);
      } else if (action == 'type_text') {
        ref.read(remoteConnectProvider.notifier).sendCommand('system', 'type_text', packet);
      } else if (action == 'mouse_left_down' || action == 'mouse_left_up') {
        ref.read(remoteConnectProvider.notifier).sendCommand('system', action, packet);
      }
    }
  }

  void _sendCommand(String command, String commandName, [Map<String, dynamic>? extraPayload]) async {
    final activeComputerId = ref.read(remoteConnectProvider).activeComputerId;

    if (activeComputerId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active computer connected!'), backgroundColor: AppColors.brandPink),
        );
      }
      return;
    }

    if (mounted) {
      setState(() => _isRendering = command == 'render_and_send');
    }

    final commandId = await ref.read(remoteConnectProvider.notifier).sendCommand(
      'dr',
      command, 
      extraPayload ?? {},
    );

    if (!mounted) return;

    if (commandId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Command "$commandName" sent!'), 
          backgroundColor: AppColors.brandBlue,
          duration: const Duration(seconds: 2),
        ),
      );
      
      if (command == 'render_and_send') {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _isRendering = false);
        });
      }
    } else {
      if (mounted) setState(() => _isRendering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send command.'), backgroundColor: AppColors.brandPink),
      );
    }
  }

  void _handleDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.1) {
      _transformationController.value = Matrix4.identity();
    } else {
      final pos = _doubleTapPosition ?? Offset.zero;
      final x = -pos.dx * 1.5;
      final y = -pos.dy * 1.5;
      _transformationController.value = Matrix4.diagonal3Values(2.5, 2.5, 1.0)
        ..setTranslationRaw(x, y, 0.0);
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!_isTouchMouseActive) return;
    _pointerCount++;
    _lastPointerPos = event.localPosition;
    _firstPointerDownPos = event.localPosition;
    _pointerDownTime = DateTime.now();

    if (_pointerCount == 1) {
      _dragHoldTimer?.cancel();
      // Long press (360ms) engages mouse left click down (Drag & Drop mode)
      _dragHoldTimer = Timer(const Duration(milliseconds: 360), () {
        if (_pointerCount == 1 && mounted && _isTouchMouseActive) {
          setState(() => _isDragging = true);
          HapticFeedback.heavyImpact();
          _sendControlPacket({'action': 'mouse_left_down'});
        }
      });
    } else {
      _dragHoldTimer?.cancel();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_isTouchMouseActive || _lastPointerPos == null) return;
    final delta = event.localPosition - _lastPointerPos!;
    _lastPointerPos = event.localPosition;

    // If movement occurs before drag timer triggers, cancel hold timer so it stays normal glide
    if (!_isDragging && _firstPointerDownPos != null) {
      if ((event.localPosition - _firstPointerDownPos!).distance > 14) {
        _dragHoldTimer?.cancel();
      }
    }

    if (_pointerCount == 1) {
      // 1-finger glide moves cursor (and drags if _isDragging is active!)
      _sendControlPacket({
        'action': 'mouse_move',
        'dx': delta.dx * _mouseSensitivity,
        'dy': delta.dy * _mouseSensitivity,
      });
    } else if (_pointerCount >= 2) {
      // 2-finger drag scrolls wheel smoothly
      _sendControlPacket({
        'action': 'mouse_scroll',
        'dy': delta.dy * 0.9,
      });
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_isTouchMouseActive) return;
    _dragHoldTimer?.cancel();

    if (_isDragging) {
      setState(() => _isDragging = false);
      HapticFeedback.lightImpact();
      _sendControlPacket({'action': 'mouse_left_up'});
    } else {
      final downPos = _firstPointerDownPos;
      final downTime = _pointerDownTime;
      final wasTwoFinger = _pointerCount >= 2;

      if (downPos != null && downTime != null) {
        final dist = (event.localPosition - downPos).distance;
        final duration = DateTime.now().difference(downTime);

        if (dist < 18 && duration.inMilliseconds < 420) {
          if (wasTwoFinger) {
            // 2-finger tap right clicks
            HapticFeedback.mediumImpact();
            _sendControlPacket({'action': 'mouse_right_click'});
          } else {
            // 1-finger tap clicks
            HapticFeedback.lightImpact();
            _sendControlPacket({'action': 'mouse_left_click'});
          }
        }
      }
    }

    _pointerCount = (_pointerCount - 1).clamp(0, 10);
    if (_pointerCount == 0) {
      _lastPointerPos = null;
      _firstPointerDownPos = null;
      _pointerDownTime = null;
    }
  }

  void _toggleOrientation() {
    final orientation = MediaQuery.of(context).orientation;
    if (orientation == Orientation.portrait) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remoteState = ref.watch(remoteConnectProvider);
    final webrtcState = ref.watch(webrtcDesktopProvider);
    
    final activeComputerId = remoteState.activeComputerId;
    final connection = activeComputerId != null ? webrtcState.connections[activeComputerId] : null;
    final isConnected = connection?.status == WebRTCStatus.connected;
    
    final computer = remoteState.linkedComputers.firstWhere(
      (c) => c.id == activeComputerId,
      orElse: () => LinkedComputer(id: 'unknown', name: 'Remote Computer', isOnline: false),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Full-screen Video Stream (InteractiveViewer + ObjectFitContain)
          Positioned.fill(
            child: _buildDesktopStreamView(isConnected, connection),
          ),

          // 2. Translucent Ultra-Thin Floating Header (Height ~46px)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildFloatingTopBar(computer, isConnected, activeComputerId),
          ),

          // 3. Floating Precision Trackpad Overlay (if active)
          _buildPrecisionTrackpadOverlay(),

          // 4. Virtual Keyboard & Hotkeys Ribbon (if active)
          _buildVirtualKeyboardRibbon(),

          // 5. Floating Micro-HUD Toolbar (38-42px Glass Pill)
          _buildFloatingMicroHud(),
        ],
      ),
    );
  }

  Widget _buildDesktopStreamView(bool isConnected, dynamic connection) {
    if (!isConnected || connection?.renderer == null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (connection?.status == WebRTCStatus.connecting) ...[
                const CircularProgressIndicator(color: AppColors.brandBlue),
                const SizedBox(height: 16),
                Text(
                  'Connecting to Desktop Stream...',
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.desktop_mac_rounded, size: 48, color: AppColors.brandBlue),
                ),
                const SizedBox(height: 16),
                Text(
                  connection?.status == WebRTCStatus.error ? 'WebRTC Stream Offline' : 'Desktop Standby',
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Wake or connect your paired computer to start controlling',
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      behavior: HitTestBehavior.opaque,
      child: GestureDetector(
        onDoubleTapDown: (details) => _doubleTapPosition = details.localPosition,
        onDoubleTap: _handleDoubleTap,
        child: InteractiveViewer(
          transformationController: _transformationController,
          minScale: 0.8,
          maxScale: 5.0,
          boundaryMargin: const EdgeInsets.all(120.0),
          panEnabled: !_isTouchMouseActive,
          scaleEnabled: !_isTouchMouseActive,
          child: Center(
            child: RTCVideoView(
              connection.renderer!,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingTopBar(LinkedComputer computer, bool isConnected, String? activeComputerId) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.darkSurface.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.0),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () {
                      ref.read(remoteConnectProvider.notifier).disconnect();
                      context.pop();
                    },
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isConnected ? Colors.greenAccent : Colors.white24,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          computer.name,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (computer.activeWindow != null && computer.activeWindow!.isNotEmpty)
                          Text(
                            computer.activeWindow!,
                            style: GoogleFonts.inter(
                              color: AppColors.brandPink,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  // Direct touch mouse mode status badge
                  if (_isTouchMouseActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: _isDragging
                            ? AppColors.brandPink.withValues(alpha: 0.25)
                            : AppColors.brandBlue.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _isDragging
                              ? AppColors.brandPink.withValues(alpha: 0.6)
                              : AppColors.brandBlue.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        _isDragging ? '⚡ DRAGGING' : 'MOUSE MODE',
                        style: GoogleFonts.inter(
                          color: _isDragging ? AppColors.brandPink : AppColors.brandBlue,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.speed_rounded, color: Colors.white70, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const TelemetryDashboardScreen()));
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.cast_connected_rounded, 
                      color: isConnected ? Colors.greenAccent : Colors.white30,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () {
                      if (!isConnected && activeComputerId != null) {
                        ref.read(webrtcDesktopProvider.notifier).connect(activeComputerId);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingMicroHud() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 16,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.darkSurface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
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
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.greenAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Oneova HUD',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.unfold_more_rounded, size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedHud() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Minimize HUD button
        _buildHudIconButton(
          icon: Icons.keyboard_arrow_down_rounded,
          tooltip: 'Minimize HUD',
          onTap: () => setState(() => _isHudCollapsed = true),
        ),
        _buildHudDivider(),
        // Touch-to-Mouse Mode Toggle
        _buildHudIconButton(
          icon: _isTouchMouseActive ? Icons.touch_app_rounded : Icons.pan_tool_rounded,
          tooltip: _isTouchMouseActive ? 'Touch Mouse: ACTIVE' : 'Pinch/Zoom Mode',
          isActive: _isTouchMouseActive,
          activeColor: AppColors.brandBlue,
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _isTouchMouseActive = !_isTouchMouseActive);
          },
        ),
        // Fit / Reset Zoom button
        _buildHudIconButton(
          icon: Icons.fit_screen_rounded,
          tooltip: 'Reset Zoom / Fit',
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() {
              _transformationController.value = Matrix4.identity();
            });
          },
        ),
        // Precision Trackpad Overlay Toggle
        _buildHudIconButton(
          icon: Icons.mouse_rounded,
          tooltip: 'Trackpad Overlay',
          isActive: _isTrackpadVisible,
          activeColor: AppColors.brandBlue,
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _isTrackpadVisible = !_isTrackpadVisible);
          },
        ),
        // Virtual Keyboard & Hotkeys Ribbon Toggle
        _buildHudIconButton(
          icon: Icons.keyboard_rounded,
          tooltip: 'Virtual Keyboard',
          isActive: _isKeyboardRibbonVisible,
          activeColor: AppColors.brandBlue,
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _isKeyboardRibbonVisible = !_isKeyboardRibbonVisible);
          },
        ),
        // Sleep / Lockscreen Passkey Unlock Prompt
        _buildHudIconButton(
          icon: Icons.lock_open_rounded,
          tooltip: 'Wake & Unlock Passkey',
          onTap: () => _showPasskeyUnlockDialog(context),
        ),
        _buildHudDivider(),
        // Ova Desktop AI Summon Button (Glowing Pink Accent)
        _buildHudIconButton(
          icon: Icons.auto_awesome_rounded,
          tooltip: 'Ova Desktop AI Agent',
          isSpecial: true,
          activeColor: AppColors.brandPink,
          onTap: () {
            HapticFeedback.lightImpact();
            _showOvaAgentSummonSheet(context);
          },
        ),
        _buildHudDivider(),
        // Studio Controls Drawer (Timeline, Chat, Voice)
        _buildHudIconButton(
          icon: Icons.tune_rounded,
          tooltip: 'Studio Controls',
          onTap: () => _showStudioControlsModal(context),
        ),
        // Portrait / Landscape fullscreen toggle
        _buildHudIconButton(
          icon: Icons.screen_rotation_rounded,
          tooltip: 'Rotate Display',
          onTap: _toggleOrientation,
        ),
      ],
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
    final effectiveColor = isSpecial
        ? AppColors.brandPink
        : isActive
            ? (activeColor ?? AppColors.brandBlue)
            : Colors.white70;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isActive
                ? (activeColor ?? AppColors.brandBlue).withValues(alpha: 0.22)
                : isSpecial
                    ? AppColors.brandPink.withValues(alpha: 0.18)
                    : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive
                  ? (activeColor ?? AppColors.brandBlue).withValues(alpha: 0.6)
                  : isSpecial
                      ? AppColors.brandPink.withValues(alpha: 0.5)
                      : Colors.transparent,
              width: 1.0,
            ),
          ),
          child: Icon(icon, size: 17, color: effectiveColor),
        ),
      ),
    );
  }

  Widget _buildHudDivider() {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white12,
    );
  }

  Widget _buildPrecisionTrackpadOverlay() {
    if (!_isTrackpadVisible) return const SizedBox.shrink();

    return Positioned(
      left: _trackpadPosition.dx,
      top: _trackpadPosition.dy,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 220,
            height: 180,
            decoration: BoxDecoration(
              color: AppColors.darkSurface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12, width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Drag handle header
                GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _trackpadPosition = Offset(
                        (_trackpadPosition.dx + details.delta.dx).clamp(0.0, MediaQuery.of(context).size.width - 220),
                        (_trackpadPosition.dy + details.delta.dy).clamp(40.0, MediaQuery.of(context).size.height - 200),
                      );
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    color: Colors.white.withValues(alpha: 0.04),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.drag_indicator_rounded, size: 16, color: Colors.white38),
                            const SizedBox(width: 4),
                            Text('Trackpad', style: GoogleFonts.inter(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        InkWell(
                          onTap: () => setState(() => _isTrackpadVisible = false),
                          child: const Icon(Icons.close_rounded, size: 16, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                ),
                // Central touch pad area with scroll strip on right
                Expanded(
                  child: Row(
                    children: [
                      // Touch pad surface
                      Expanded(
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            _sendControlPacket({
                              'action': 'mouse_move',
                              'dx': details.delta.dx * 1.8,
                              'dy': details.delta.dy * 1.8,
                            });
                          },
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _sendControlPacket({'action': 'mouse_left_click'});
                          },
                          onDoubleTap: () {
                            HapticFeedback.mediumImpact();
                            _sendControlPacket({'action': 'mouse_double_click'});
                          },
                          onLongPress: () {
                            HapticFeedback.heavyImpact();
                            _sendControlPacket({'action': 'mouse_right_click'});
                          },
                          child: Container(
                            margin: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.touch_app_rounded, size: 24, color: Colors.white.withValues(alpha: 0.2)),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Drag • Tap: Left • Hold: Right',
                                    style: GoogleFonts.inter(fontSize: 8.5, color: Colors.white30),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Vertical scroll strip
                      GestureDetector(
                        onVerticalDragUpdate: (details) {
                          _sendControlPacket({
                            'action': 'mouse_scroll',
                            'dy': details.delta.dy * 0.9,
                          });
                        },
                        child: Container(
                          width: 28,
                          margin: const EdgeInsets.only(top: 6, bottom: 6, right: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.unfold_more_rounded, size: 16, color: Colors.white38),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Left, Drag Lock, & Right click buttons
                Container(
                  height: 32,
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.white12, width: 0.8)),
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
                              'Left (L)',
                              style: GoogleFonts.inter(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                      Container(width: 0.8, color: Colors.white12),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _isTrackpadDragLocked = !_isTrackpadDragLocked;
                            });
                            if (_isTrackpadDragLocked) {
                              HapticFeedback.heavyImpact();
                              _sendControlPacket({'action': 'mouse_left_down'});
                            } else {
                              HapticFeedback.lightImpact();
                              _sendControlPacket({'action': 'mouse_left_up'});
                            }
                          },
                          child: Container(
                            color: _isTrackpadDragLocked ? AppColors.brandPink.withValues(alpha: 0.25) : Colors.transparent,
                            child: Center(
                              child: Text(
                                _isTrackpadDragLocked ? '⚡ Dragging' : 'Drag',
                                style: GoogleFonts.inter(
                                  color: _isTrackpadDragLocked ? AppColors.brandPink : Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(width: 0.8, color: Colors.white12),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            _sendControlPacket({'action': 'mouse_right_click'});
                          },
                          child: Center(
                            child: Text(
                              'Right (R)',
                              style: GoogleFonts.inter(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
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

  Widget _buildVirtualKeyboardRibbon() {
    if (!_isKeyboardRibbonVisible) return const SizedBox.shrink();

    return Positioned(
      left: 12,
      right: 12,
      bottom: _isHudCollapsed ? 60 : 74,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.darkSurface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12, width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: minAxisSize(),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.keyboard_rounded, size: 16, color: AppColors.brandBlue),
                        const SizedBox(width: 6),
                        Text(
                          'Virtual Hotkeys & Input Ribbon',
                          style: GoogleFonts.inter(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: () => setState(() => _isKeyboardRibbonVisible = false),
                      child: const Padding(
                        padding: EdgeInsets.all(2.0),
                        child: Icon(Icons.close_rounded, size: 16, color: Colors.white54),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildHotkeyPill('Esc', () => _sendControlPacket({'action': 'key_tap', 'key': 'esc'})),
                      _buildHotkeyPill('Tab', () => _sendControlPacket({'action': 'key_tap', 'key': 'tab'})),
                      _buildHotkeyPill('Ctrl', () => _sendControlPacket({'action': 'key_tap', 'key': 'ctrl'})),
                      _buildHotkeyPill('Cmd ⌘', () => _sendControlPacket({'action': 'key_tap', 'key': 'cmd'})),
                      _buildHotkeyPill('Alt ⌥', () => _sendControlPacket({'action': 'key_tap', 'key': 'alt'})),
                      _buildHotkeyPill('Shift ⇧', () => _sendControlPacket({'action': 'key_tap', 'key': 'shift'})),
                      _buildHotkeyPill('Win ⊞', () => _sendControlPacket({'action': 'key_tap', 'key': 'win'})),
                      _buildHotkeyPill('Ctrl+C', () => _sendControlPacket({'action': 'key_combination', 'combo': 'ctrl+c'})),
                      _buildHotkeyPill('Ctrl+V', () => _sendControlPacket({'action': 'key_combination', 'combo': 'ctrl+v'})),
                      _buildHotkeyPill('Ctrl+Z', () => _sendControlPacket({'action': 'key_combination', 'combo': 'ctrl+z'})),
                      _buildHotkeyPill('Ctrl+A', () => _sendControlPacket({'action': 'key_combination', 'combo': 'ctrl+a'})),
                      _buildHotkeyPill('Save ⌘S', () => _sendControlPacket({'action': 'key_combination', 'combo': 'ctrl+s'})),
                      _buildHotkeyPill('←', () => _sendControlPacket({'action': 'key_tap', 'key': 'left'})),
                      _buildHotkeyPill('↑', () => _sendControlPacket({'action': 'key_tap', 'key': 'up'})),
                      _buildHotkeyPill('↓', () => _sendControlPacket({'action': 'key_tap', 'key': 'down'})),
                      _buildHotkeyPill('→', () => _sendControlPacket({'action': 'key_tap', 'key': 'right'})),
                      _buildHotkeyPill('⌫ Del', () => _sendControlPacket({'action': 'key_tap', 'key': 'backspace'})),
                      _buildHotkeyPill('Space', () => _sendControlPacket({'action': 'key_tap', 'key': 'space'})),
                      _buildHotkeyPill('Enter ⏎', () => _sendControlPacket({'action': 'key_tap', 'key': 'enter'}), isPrimary: true),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 34,
                        child: TextField(
                          controller: _keyboardInputController,
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Type string to send to active window...',
                            hintStyle: GoogleFonts.inter(color: Colors.white30, fontSize: 11),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                            filled: true,
                            fillColor: AppColors.darkSurfaceHighlight,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          ),
                          onSubmitted: (val) {
                            if (val.isNotEmpty) {
                              _sendControlPacket({'action': 'type_text', 'text': val});
                              _keyboardInputController.clear();
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 34,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          final text = _keyboardInputController.text;
                          if (text.isNotEmpty) {
                            _sendControlPacket({'action': 'type_text', 'text': text});
                            _keyboardInputController.clear();
                          }
                        },
                        child: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  MainAxisSize minAxisSize() => MainAxisSize.min;

  Widget _buildHotkeyPill(String title, VoidCallback onTap, {bool isPrimary = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: isPrimary ? AppColors.brandBlue : AppColors.darkSurfaceHighlight,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isPrimary ? AppColors.brandBlue : Colors.white12, width: 1.0),
          ),
          child: Text(
            title,
            style: GoogleFonts.inter(
              color: isPrimary ? Colors.white : Colors.white70,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  void _showPasskeyUnlockDialog(BuildContext context) async {
    final passkeyController = TextEditingController();
    bool isObscured = true;
    bool isUnlocking = false;
    bool rememberForBiometrics = true;
    final activeComputerId = ref.read(remoteConnectProvider).activeComputerId ?? 'default';
    final savedPasskey = await _secureStorage.read(key: 'workstation_passkey_$activeComputerId');
    final hasSavedPasskey = savedPasskey != null && savedPasskey.isNotEmpty;

    if (!context.mounted) return;

    showModalBottomSheet(
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
                color: AppColors.darkSurface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: Colors.white12, width: 1.0),
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
                        color: Colors.white24,
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
                          color: AppColors.brandBlue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.3)),
                        ),
                        child: const Icon(Icons.vpn_key_rounded, color: AppColors.brandBlue, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Wake & Unlock Workstation',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              hasSavedPasskey
                                  ? 'Passkey linked • 1-Tap Biometric Resume ready'
                                  : 'Resume workstation session seamlessly from sleep',
                              style: GoogleFonts.inter(
                                color: hasSavedPasskey ? AppColors.brandPink : Colors.white54,
                                fontSize: 11.5,
                                fontWeight: hasSavedPasskey ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.fingerprint_rounded, color: Colors.white, size: 22),
                    label: Text(
                      hasSavedPasskey
                          ? 'Instant Biometric Resume (Face / Touch ID)'
                          : 'Use Biometrics (Display Wake)',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    onPressed: isUnlocking
                        ? null
                        : () async {
                            final biometrics = ref.read(oneovaBiometricsServiceProvider);
                            final authenticated = await biometrics.authenticate(
                              reason: 'Authenticate to wake & unlock remote workstation',
                            );
                            if (authenticated) {
                              setDialogState(() => isUnlocking = true);
                              final passToDispatch = hasSavedPasskey ? savedPasskey : '';
                              _sendControlPacket({'action': 'wake_and_unlock', 'passkey': passToDispatch});
                              HapticFeedback.mediumImpact();
                              if (dialogCtx.mounted) {
                                Navigator.pop(dialogCtx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      hasSavedPasskey
                                          ? 'Biometric unlock verified — Workstation active!'
                                          : 'Biometric wake signal sent to desktop!',
                                    ),
                                    backgroundColor: AppColors.brandBlue,
                                  ),
                                );
                              }
                            }
                          },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(child: Divider(color: Colors.white12)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          hasSavedPasskey ? 'OR ENTER PASSKEY MANUALLY' : 'OR PASSKEY',
                          style: GoogleFonts.inter(fontSize: 10, color: Colors.white38, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Expanded(child: Divider(color: Colors.white12)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passkeyController,
                    obscureText: isObscured,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.darkSurfaceHighlight,
                      hintText: 'Enter computer password or PIN',
                      hintStyle: GoogleFonts.inter(color: Colors.white30, fontSize: 13),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      isDense: true,
                      prefixIcon: const Icon(Icons.lock_outline_rounded, color: Colors.white54, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(isObscured ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white54, size: 20),
                        onPressed: () => setDialogState(() => isObscured = !isObscured),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.brandBlue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Checkbox(
                        value: rememberForBiometrics,
                        activeColor: AppColors.brandBlue,
                        checkColor: Colors.white,
                        onChanged: (val) {
                          setDialogState(() => rememberForBiometrics = val ?? true);
                        },
                      ),
                      Expanded(
                        child: Text(
                          'Store passkey securely for 1-tap Biometric resume',
                          style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                        ),
                      ),
                      if (hasSavedPasskey)
                        TextButton(
                          onPressed: () async {
                            await _secureStorage.delete(key: 'workstation_passkey_$activeComputerId');
                            if (dialogCtx.mounted) {
                              Navigator.pop(dialogCtx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Saved passkey cleared from Keystore.'),
                                  backgroundColor: AppColors.brandPink,
                                ),
                              );
                            }
                          },
                          child: Text(
                            'Clear',
                            style: GoogleFonts.inter(color: AppColors.brandPink, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white24),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            _sendControlPacket({'action': 'wake_and_unlock', 'passkey': ''});
                            Navigator.pop(dialogCtx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Display wake command sent!'), backgroundColor: AppColors.brandBlue),
                            );
                          },
                          child: Text('Wake Screen Only', style: GoogleFonts.inter(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brandBlue,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
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
                                  _sendControlPacket({'action': 'wake_and_unlock', 'passkey': pass});
                                  HapticFeedback.lightImpact();
                                  if (dialogCtx.mounted) {
                                    Navigator.pop(dialogCtx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Wake and unlock command dispatched!'),
                                        backgroundColor: AppColors.brandBlue,
                                      ),
                                    );
                                  }
                                },
                          child: isUnlocking
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text('Unlock & Resume', style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
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

  void _showOvaAgentSummonSheet(BuildContext context) {
    final promptController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white12, width: 1.0),
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
                    color: Colors.white24,
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
                      color: AppColors.brandPink.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: AppColors.brandPink, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ova Desktop AI Agent',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'AI commanding active windows & workflows',
                          style: GoogleFonts.inter(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildAiSuggestionChip('🎬 Render Timeline', promptController),
                    const SizedBox(width: 8),
                    _buildAiSuggestionChip('🔄 Sync Project', promptController),
                    const SizedBox(width: 8),
                    _buildAiSuggestionChip('📁 Show Finder', promptController),
                    const SizedBox(width: 8),
                    _buildAiSuggestionChip('⚡ Fullscreen App', promptController),
                    const SizedBox(width: 8),
                    _buildAiSuggestionChip('🔒 Lock Screen', promptController),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: promptController,
                maxLines: 2,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.darkSurfaceHighlight,
                  hintText: 'Ask Ova to do anything on your computer...',
                  hintStyle: GoogleFonts.inter(color: Colors.white30, fontSize: 13),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.brandPink),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandPink,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                icon: const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
                label: Text(
                  'Command Computer',
                  style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                ),
                onPressed: () {
                  final text = promptController.text.trim();
                  if (text.isEmpty) return;
                  _sendCommand('execute_ai_task', 'Ova: $text', {'prompt': text});
                  _sendControlPacket({'action': 'ai_command', 'prompt': text});
                  Navigator.pop(sheetContext);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAiSuggestionChip(String label, TextEditingController controller) {
    return ActionChip(
      label: Text(label, style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
      backgroundColor: AppColors.darkSurfaceHighlight,
      side: const BorderSide(color: Colors.white12),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onPressed: () {
        controller.text = label;
      },
    );
  }

  void _showStudioControlsModal(BuildContext context) {
    final remoteState = ref.read(remoteConnectProvider);
    final activeComputerId = remoteState.activeComputerId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DefaultTabController(
          length: 3,
          child: Container(
            height: MediaQuery.of(sheetContext).size.height * 0.52,
            decoration: const BoxDecoration(
              color: AppColors.darkBackground,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: Colors.white12, width: 1.0)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const TabBar(
                  indicatorColor: AppColors.brandBlue,
                  labelColor: AppColors.brandBlue,
                  unselectedLabelColor: Colors.white54,
                  tabs: [
                    Tab(icon: Icon(Icons.touch_app_rounded, size: 18), text: "Studio"),
                    Tab(icon: Icon(Icons.chat_bubble_rounded, size: 18), text: "Chat"),
                    Tab(icon: Icon(Icons.graphic_eq_rounded, size: 18), text: "Voice"),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildControlsTab(),
                      _buildChatTab(activeComputerId),
                      _buildVoiceTab(),
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

  Widget _buildControlsTab() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(Icons.movie_creation_rounded, _isRendering ? 'Rendering...' : 'Render', () => _sendCommand('render_and_send', 'Render')),
              _buildActionButton(Icons.play_arrow_rounded, 'Play/Pause', () => _sendCommand('play_pause', 'Play')),
              _buildActionButton(Icons.sync_rounded, 'Sync', () => _sendCommand('sync_project', 'Sync')),
            ],
          ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.darkSurfaceHighlight,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Colors.white12, width: 1),
            ),
          ),
          onPressed: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 24),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatTab(String? activeComputerId) {
    if (activeComputerId == null) {
      return const Center(child: Text("No computer connected", style: TextStyle(color: Colors.white54)));
    }
    return RemoteChatView(deviceId: activeComputerId);
  }

  Widget _buildVoiceTab() {
    final voiceState = ref.watch(voiceAssistantProvider);
    final isVoiceActive = voiceState.state != VoiceState.idle;
    
    String statusText = "Tap to speak";
    if (voiceState.state == VoiceState.listening) {
      statusText = "Aria is listening...";
    } else if (voiceState.state == VoiceState.processing) {
      statusText = "Aria is thinking...";
    } else if (voiceState.state == VoiceState.speaking) {
      statusText = "Aria is speaking...";
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
             width: 120,
             height: 120,
             decoration: BoxDecoration(
               shape: BoxShape.circle,
               border: Border.all(color: AppColors.brandBlue, width: 2),
               image: const DecorationImage(
                 image: AssetImage('assets/images/ai_avatar.jpg'),
                 fit: BoxFit.cover,
               ),
               boxShadow: [
                 if (isVoiceActive)
                   BoxShadow(
                     color: AppColors.brandBlue.withValues(alpha: 0.5),
                     blurRadius: 20,
                     spreadRadius: 2,
                   )
               ]
             )
          ).animate(target: isVoiceActive ? 1 : 0).scale(begin: const Offset(1, 1), end: const Offset(1.05, 1.05)),
          const SizedBox(height: 24),
          
          VoiceWaveVisualizer(isSpeaking: isVoiceActive, height: 50),
          
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () {
              final voiceNotifier = ref.read(voiceAssistantProvider.notifier);
              if (voiceState.state == VoiceState.idle) {
                voiceNotifier.startListening(continuous: true);
              } else if (voiceState.state == VoiceState.listening) {
                voiceNotifier.stopListening(force: true);
              } else {
                voiceNotifier.stopSpeaking(force: true);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                color: isVoiceActive ? AppColors.brandBlue : AppColors.darkSurface,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: isVoiceActive ? Colors.transparent : AppColors.darkSurfaceHighlight, width: 2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isVoiceActive ? Icons.mic : Icons.mic_off,
                    size: 22,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    statusText,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ).animate(target: isVoiceActive ? 1 : 0).scale(begin: const Offset(1, 1), end: const Offset(1.05, 1.05)),
          ),
          if (voiceState.currentText.isNotEmpty) ...[
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Text(
                '"${voiceState.currentText}"',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ).animate().fadeIn(),
          ]
        ],
      ),
    );
  }
}
