import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/theme/app_theme.dart';

/// Floating Circular Camera PIP that renders the streamer's camera or avatar
/// over a screen-shared broadcast or gameplay in Oneova.
///
/// Features:
/// - Smooth inertia dragging with snap-to-edge (left/right).
/// - Dynamic pulsating gradient ring (`AppColors.brandBlue` & `AppColors.brandPink`).
/// - Real-time live mic audio waveform perimeter ring.
/// - Tap-to-expand quick controls overlay (Mute mic, Flip camera, Resize 100/140, Hide PIP, Close Screen Share).
/// - Full dual-mode Light & Dark luxury theme support.
class OneovaFloatingCameraPip extends StatefulWidget {
  final CameraController? cameraController;
  final String? avatarUrl;
  final String streamerName;
  final bool isMicMuted;
  final bool isCameraOff;
  final bool isScreenSharing;
  final VoidCallback? onToggleMic;
  final VoidCallback? onFlipCamera;
  final VoidCallback? onHidePip;
  final VoidCallback? onCloseScreenShare;
  final ValueChanged<bool>? onSizeChanged;
  final double initialTop;
  final double initialLeft;

  const OneovaFloatingCameraPip({
    super.key,
    this.cameraController,
    this.avatarUrl,
    this.streamerName = 'Streamer',
    this.isMicMuted = false,
    this.isCameraOff = false,
    this.isScreenSharing = true,
    this.onToggleMic,
    this.onFlipCamera,
    this.onHidePip,
    this.onCloseScreenShare,
    this.onSizeChanged,
    this.initialTop = 120.0,
    this.initialLeft = 16.0,
  });

  @override
  State<OneovaFloatingCameraPip> createState() =>
      _OneovaFloatingCameraPipState();
}

class _OneovaFloatingCameraPipState extends State<OneovaFloatingCameraPip>
    with TickerProviderStateMixin {
  // ── Drag & Inertia Positions ─────────────────────────────────────────────
  Offset _position = const Offset(16, 120);
  bool _isDragging = false;
  late AnimationController _snapController;
  Animation<Offset>? _snapAnimation;

  // ── Audio Waveform & Pulse Border Animations ─────────────────────────────
  late AnimationController _waveController;
  late AnimationController _borderPulseController;

  // ── Size State (100 compact vs 140 expanded) ─────────────────────────────
  bool _isExpanded = false;
  static const double _compactSize = 100.0;
  static const double _expandedSize = 140.0;
  double get _currentSize => _isExpanded ? _expandedSize : _compactSize;

  // ── Controls Overlay ─────────────────────────────────────────────────────
  bool _showControls = false;

  @override
  void initState() {
    super.initState();
    _position = Offset(widget.initialLeft, widget.initialTop);

    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _borderPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _snapController.dispose();
    _waveController.dispose();
    _borderPulseController.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    if (_snapController.isAnimating) {
      _snapController.stop();
    }
    setState(() {
      _isDragging = true;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _position += details.delta;
    });
  }

  void _onPanEnd(DragEndDetails details, Size screenSize, EdgeInsets padding) {
    setState(() {
      _isDragging = false;
    });

    const edgeMargin = 16.0;
    final topBound = padding.top + 60.0;
    final bottomBound = screenSize.height - padding.bottom - _currentSize - 80.0;

    // Determine horizontal snap edge based on center line + horizontal velocity
    final velocityX = details.velocity.pixelsPerSecond.dx;
    final currentCenterX = _position.dx + (_currentSize / 2);
    final screenCenterX = screenSize.width / 2;

    double targetX;
    if (velocityX.abs() > 400) {
      targetX = velocityX < 0
          ? edgeMargin
          : screenSize.width - _currentSize - edgeMargin;
    } else {
      targetX = currentCenterX < screenCenterX
          ? edgeMargin
          : screenSize.width - _currentSize - edgeMargin;
    }

    // Projected Y with inertia dampening
    final velocityY = details.velocity.pixelsPerSecond.dy;
    double targetY = _position.dy + (velocityY * 0.08);
    targetY = targetY.clamp(topBound, bottomBound);

    final startOffset = _position;
    final endOffset = Offset(targetX, targetY);

    _snapAnimation = Tween<Offset>(begin: startOffset, end: endOffset).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
    )..addListener(() {
        setState(() {
          _position = _snapAnimation!.value;
        });
      });

    _snapController.forward(from: 0.0);
  }

  void _toggleExpanded() {
    HapticFeedback.selectionClick();
    setState(() {
      _isExpanded = !_isExpanded;
    });
    widget.onSizeChanged?.call(_isExpanded);
  }

  void _toggleControls() {
    HapticFeedback.lightImpact();
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenSize = media.size;
    final padding = media.padding;

    // Safety clamp in case of rotation or orientation resize
    final clampedX = _position.dx
        .clamp(
          8.0,
          math.max(8.0, screenSize.width - _currentSize - 8.0),
        )
        .toDouble();
    final clampedY = _position.dy
        .clamp(
          padding.top + 20.0,
          math.max(padding.top + 20.0, screenSize.height - _currentSize - 40.0),
        )
        .toDouble();

    final isNearRight = clampedX > (screenSize.width / 2);

    return Positioned(
      left: clampedX,
      top: clampedY,
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: (details) => _onPanEnd(details, screenSize, padding),
        onTap: _toggleControls,
        child: AnimatedScale(
          scale: _isDragging ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: isNearRight
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              // Main Circular Camera PIP with Waveform & Pulsing Gradient
              Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Outer Audio Waveform Ring (Active when mic is unmuted)
                  if (!widget.isMicMuted)
                    AnimatedBuilder(
                      animation: _waveController,
                      builder: (context, child) {
                        return CustomPaint(
                          size: Size(_currentSize + 24, _currentSize + 24),
                          painter: _MicWaveformRingPainter(
                            progress: _waveController.value,
                            primaryColor: AppColors.brandBlue,
                            accentColor: AppColors.brandPink,
                          ),
                        );
                      },
                    ),

                  // Circular Pulsing Gradient Border Container
                  AnimatedBuilder(
                    animation: _borderPulseController,
                    builder: (context, child) {
                      final pulseVal = _borderPulseController.value;
                      final glowOpacity = (0.25 + (pulseVal * 0.35)).clamp(0.0, 1.0);

                      return Container(
                        width: _currentSize,
                        height: _currentSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.brandPink.withValues(alpha: glowOpacity),
                              blurRadius: 12 + (pulseVal * 8),
                              spreadRadius: 1 + (pulseVal * 2),
                            ),
                            BoxShadow(
                              color: AppColors.brandBlue.withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.brandBlue,
                              AppColors.brandPink,
                            ],
                          ),
                        ),
                        padding: const EdgeInsets.all(2.5),
                        child: child,
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.bg,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _buildCameraOrAvatar(context),
                    ),
                  ),

                  // Screen Share Indicator Mini Pill (Top Center)
                  if (widget.isScreenSharing)
                    Positioned(
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.brandPink,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.brandPink.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.screen_share_rounded,
                              size: 9,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'PIP',
                              style: GoogleFonts.inter(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Status Badge on Bottom: Mute Indicator / Mic Status
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.isMicMuted
                            ? AppColors.brandPink
                            : AppColors.brandBlue,
                        border: Border.all(
                          color: context.bg,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Icon(
                        widget.isMicMuted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),

              // Interactive Quick Controls Toolbar Overlay
              if (_showControls) ...[
                const SizedBox(height: 8),
                _buildQuickControlsMenu(context, isNearRight),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Builds camera feed preview or user avatar fallback
  Widget _buildCameraOrAvatar(BuildContext context) {
    final hasActiveCamera = widget.cameraController != null &&
        widget.cameraController!.value.isInitialized &&
        !widget.isCameraOff;

    if (hasActiveCamera) {
      Widget? preview;
      try {
        preview = widget.cameraController!.buildPreview();
      } catch (_) {
        preview = null;
      }
      if (preview != null) {
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: widget.cameraController!.value.previewSize?.height ?? _currentSize,
              height: widget.cameraController!.value.previewSize?.width ?? _currentSize,
              child: preview,
            ),
          ),
        );
      }
    }

    // Avatar Fallback
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            context.surfaceMid,
            AppColors.brandBlue.withValues(alpha: 0.4),
          ],
        ),
      ),
      child: Center(
        child: widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
            ? ClipOval(
                child: Image.network(
                  widget.avatarUrl!,
                  width: _currentSize,
                  height: _currentSize,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) => _buildInitials(),
                ),
              )
            : _buildInitials(),
      ),
    );
  }

  Widget _buildInitials() {
    final initials = widget.streamerName.isNotEmpty
        ? widget.streamerName.substring(0, 1).toUpperCase()
        : 'O';
    return Text(
      initials,
      style: GoogleFonts.inter(
        fontSize: _isExpanded ? 36 : 26,
        fontWeight: FontWeight.w800,
        color: AppColors.brandPink,
        letterSpacing: -0.5,
      ),
    );
  }

  /// Compact floating quick controls menu
  Widget _buildQuickControlsMenu(BuildContext context, bool isNearRight) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: context.surface.withValues(alpha: context.isDark ? 0.92 : 0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: context.border,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.12),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mute / Unmute Mic
            _buildControlIconButton(
              icon: widget.isMicMuted
                  ? Icons.mic_off_rounded
                  : Icons.mic_rounded,
              tooltip: widget.isMicMuted ? 'Unmute Mic' : 'Mute Mic',
              activeColor: widget.isMicMuted ? AppColors.brandPink : null,
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onToggleMic?.call();
              },
            ),

            const SizedBox(width: 4),

            // Flip Camera
            _buildControlIconButton(
              icon: Icons.flip_camera_ios_rounded,
              tooltip: 'Flip Camera',
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onFlipCamera?.call();
              },
            ),

            const SizedBox(width: 4),

            // Resize (100 <-> 140)
            _buildControlIconButton(
              icon: _isExpanded
                  ? Icons.close_fullscreen_rounded
                  : Icons.open_in_full_rounded,
              tooltip: _isExpanded ? 'Compact PIP' : 'Expand PIP',
              activeColor: _isExpanded ? AppColors.brandBlue : null,
              onTap: _toggleExpanded,
            ),

            const SizedBox(width: 4),

            // Hide PIP
            _buildControlIconButton(
              icon: Icons.visibility_off_outlined,
              tooltip: 'Hide PIP',
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onHidePip?.call();
              },
            ),

            const SizedBox(width: 4),

            // Close Screen Share
            _buildControlIconButton(
              icon: Icons.stop_screen_share_rounded,
              tooltip: 'End Share',
              activeColor: AppColors.brandPink,
              onTap: () {
                HapticFeedback.heavyImpact();
                _showCloseShareDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? activeColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: activeColor != null
                ? activeColor.withValues(alpha: 0.15)
                : context.surfaceMid,
          ),
          child: Icon(
            icon,
            size: 16,
            color: activeColor ?? context.textPrimary,
          ),
        ),
      ),
    );
  }

  void _showCloseShareDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: context.border, width: 1.0),
        ),
        title: Text(
          'Stop Screen Share?',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        content: Text(
          'This will return your live stream back to main camera mode and dismiss the floating PIP.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: context.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.textMuted,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandPink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onCloseScreenShare?.call();
            },
            child: Text(
              'Stop Share',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter that paints reactive, undulating audio waveform bars
/// radiating around the circular perimeter of the PIP camera.
class _MicWaveformRingPainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final Color accentColor;

  static const int _barCount = 36;

  _MicWaveformRingPainter({
    required this.progress,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = (size.width / 2) - 10.0;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.0;

    for (int i = 0; i < _barCount; i++) {
      final angle = (i * (2 * math.pi / _barCount));

      // Multi-harmonic wave function for organic speech activity simulation
      final wave1 = math.sin((angle * 3) + (progress * 2 * math.pi));
      final wave2 = math.cos((angle * 5) - (progress * 4 * math.pi));
      final waveIntensity = ((wave1 + wave2) / 2).abs();

      // Radial bar length
      final barLength = 2.0 + (waveIntensity * 7.0);

      final startX = center.dx + (baseRadius * math.cos(angle));
      final startY = center.dy + (baseRadius * math.sin(angle));
      final endX = center.dx + ((baseRadius + barLength) * math.cos(angle));
      final endY = center.dy + ((baseRadius + barLength) * math.sin(angle));

      // Blend gradient color around circle
      final t = (math.sin(angle + (progress * math.pi)) + 1) / 2;
      paint.color = Color.lerp(primaryColor, accentColor, t)!
          .withValues(alpha: 0.35 + (waveIntensity * 0.55));

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MicWaveformRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
