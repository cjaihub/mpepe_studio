import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/live/models/live_models.dart';
import '../../../shared/theme/app_theme.dart';
import 'oneova_live_media_desk_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// STAGE SCREEN SLOT MODEL
// ─────────────────────────────────────────────────────────────────────────────

/// Represents an interactive, draggable video screen slot mounted to the
/// amphitheater's curved cove wall.
class StageScreenSlot {
  final String id;
  final String displayName;
  final String avatarUrl;
  final String role; // 'Host', 'Co-Host', 'Guest', 'Presentation', 'Media'
  final bool isHost;
  final bool isLocalUser;
  final bool isAudioActive;
  final bool isVideoActive;
  final String? mediaUrl;
  final Color? glowColor;

  const StageScreenSlot({
    required this.id,
    required this.displayName,
    this.avatarUrl = '',
    this.role = 'Guest',
    this.isHost = false,
    this.isLocalUser = false,
    this.isAudioActive = true,
    this.isVideoActive = true,
    this.mediaUrl,
    this.glowColor,
  });

  StageScreenSlot copyWith({
    String? id,
    String? displayName,
    String? avatarUrl,
    String? role,
    bool? isHost,
    bool? isLocalUser,
    bool? isAudioActive,
    bool? isVideoActive,
    String? mediaUrl,
    Color? glowColor,
  }) {
    return StageScreenSlot(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      isHost: isHost ?? this.isHost,
      isLocalUser: isLocalUser ?? this.isLocalUser,
      isAudioActive: isAudioActive ?? this.isAudioActive,
      isVideoActive: isVideoActive ?? this.isVideoActive,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      glowColor: glowColor ?? this.glowColor,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CO-HOST JOIN REQUEST MODEL
// ─────────────────────────────────────────────────────────────────────────────

class CoHostJoinRequest {
  final String id;
  final String name;
  final String handle;
  final String avatar;
  final String role; // 'Co-Host (Camera & Mic)', 'Speaker (Audio-Only)', 'Presenter'
  final bool hasCamera;
  final bool hasMic;
  final String requestedAgo;

  const CoHostJoinRequest({
    required this.id,
    required this.name,
    required this.handle,
    this.avatar = '',
    this.role = 'Co-Host (Camera & Mic)',
    this.hasCamera = true,
    this.hasMic = true,
    this.requestedAgo = 'Just now',
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// FLOATING LOVE HEART PARTICLE
// ─────────────────────────────────────────────────────────────────────────────

class _LoveHeart {
  final double startX;
  final double startY;
  final double endX;
  final double endY;
  final double size;
  final Color color;
  final AnimationController controller;

  _LoveHeart({
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.size,
    required this.color,
    required this.controller,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// VIRTUAL STAGE ROOM WIDGET
// ─────────────────────────────────────────────────────────────────────────────

/// 3D Virtual Amphitheater Stage Room for Oneova Live Streaming.
///
/// Features:
/// - Curved panoramic cove wall with 3D perspective-transformed draggable video screens
/// - Stage spotlights with volumetric light beams and floating acoustic sine waves
/// - Circular multi-tiered dais with glowing LED rim ticker ("SINGLE SEARCHING")
/// - Glowing central holographic "Presentation table for goods" with particle fountain
/// - Left-side "+ Request to join" floating button with guest request moderation queue
/// - Floor-level floating holographic comment section bubble
/// - Bottom-right "SHOW LOVE" button with curving neon heart fireworks
/// - Bottom-left studio mode dock (Layout, Presentation PIP, Camera)
/// - Top HUD: `Live 200k 👁` viewer count pill and Media Desk shortcuts
class OneovaVirtualStageRoom extends StatefulWidget {
  final LiveStream stream;
  final bool isHost;
  final CameraController? localCameraController;
  final List<StageScreenSlot>? initialSlots;
  final ValueChanged<List<StageScreenSlot>>? onSlotsChanged;
  final VoidCallback? onRequestToJoin;
  final VoidCallback? onOpenMediaDesk;
  final VoidCallback? onShowLove;
  final VoidCallback? onTapPresentationTable;
  final VoidCallback? onClose;
  final String? customLowerThird;
  final String? atmospherePresetOverride;
  final bool showTopHud;

  const OneovaVirtualStageRoom({
    super.key,
    required this.stream,
    this.isHost = false,
    this.localCameraController,
    this.initialSlots,
    this.onSlotsChanged,
    this.onRequestToJoin,
    this.onOpenMediaDesk,
    this.onShowLove,
    this.onTapPresentationTable,
    this.onClose,
    this.customLowerThird,
    this.atmospherePresetOverride,
    this.showTopHud = true,
  });

  @override
  State<OneovaVirtualStageRoom> createState() => _OneovaVirtualStageRoomState();
}

class _OneovaVirtualStageRoomState extends State<OneovaVirtualStageRoom>
    with TickerProviderStateMixin {
  // Slots on the curved wall (7 slots matching the architectural drawing)
  late List<StageScreenSlot> _slots;

  // Layout mode: 0 = Amphitheater Cove, 1 = Grid Multiview, 2 = Cinema Focus
  int _layoutMode = 0;

  // Active focused slot index
  int _focusedSlotIdx = 3; // Center slot is default focus

  // Animations
  late final AnimationController _waveController;
  late final AnimationController _glowController;
  late final AnimationController _tickerController;

  // Floating love hearts
  final List<_LoveHeart> _hearts = [];

  // Live comment ticker
  String _latestComment = 'babbe';
  final String _latestCommentUser = '@babbe_official';

  // Presentation table showcase items
  final List<Map<String, dynamic>> _goodsItems = [
    {
      'title': 'Oneova Cyber Stage Hoodie',
      'price': '\$68.00',
      'tag': 'Creator Exclusive',
      'icon': Icons.checkroom_rounded,
      'color': AppColors.brandPink,
    },
    {
      'title': 'Studio Lo-Fi FLAC Album',
      'price': '\$14.99',
      'tag': 'Live Release',
      'icon': Icons.album_rounded,
      'color': AppColors.brandBlue,
    },
    {
      'title': 'Stage Deck Slides (PDF)',
      'price': 'Free Access',
      'tag': 'Presentation',
      'icon': Icons.picture_as_pdf_rounded,
      'color': const Color(0xFF00E5FF),
    },
    {
      'title': 'VIP Backstage Access Pass',
      'price': '\$25.00',
      'tag': 'Stage Mic',
      'icon': Icons.confirmation_number_rounded,
      'color': const Color(0xFFFF9800),
    },
  ];

  // Public co-host join requests queue (for host)
  final List<CoHostJoinRequest> _guestJoinRequests = [
    const CoHostJoinRequest(
      id: 'req_1',
      name: 'Sarah Connor',
      handle: '@sarah_c',
      avatar: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=120',
      role: 'Co-Host (Camera & Mic)',
      hasCamera: true,
      hasMic: true,
      requestedAgo: '1m ago',
    ),
    const CoHostJoinRequest(
      id: 'req_2',
      name: 'Alex Miller',
      handle: '@alex_m',
      avatar: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=120',
      role: 'Speaker (Audio-Only)',
      hasCamera: false,
      hasMic: true,
      requestedAgo: '3m ago',
    ),
  ];

  // Draggable panels state
  int? _draggingSlotIndex;
  int? _hoveredDropTargetIndex;

  // Stream logs ticker for Cinema Focus mode
  final List<String> _streamLogs = [
    'AI Moderator: Safety Filter Active (0 flags)',
    '1080p60 WebRTC Ultra-Low Latency Active (140ms)',
    'Spatial Audio 7.1 Master Track Synced',
    '200k Viewers in Arena · Chat Sentiment 98% Positive',
  ];
  int _currentStreamLogIdx = 0;

  @override
  void initState() {
    super.initState();

    // Initialize the 7 wall slots based on user reference sketch
    _slots = widget.initialSlots ?? _buildDefaultSlots();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _tickerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  List<StageScreenSlot> _buildDefaultSlots() {
    final hostName = widget.stream.hostDisplayName.isEmpty
        ? 'Oneova Host'
        : widget.stream.hostDisplayName;

    return [
      // 0: Far-Left Upper (Elevated Stage Cam A / Studio Newsroom)
      const StageScreenSlot(
        id: 'slot_0_far_left_up',
        displayName: 'Studio Cam A',
        role: 'Stage Cam',
        glowColor: Color(0xFF00E5FF),
      ),
      // 1: Far-Left Lower (Desk Guest)
      const StageScreenSlot(
        id: 'slot_1_far_left_low',
        displayName: 'David K.',
        role: 'Guest Speaker',
        glowColor: AppColors.brandBlue,
      ),
      // 2: Mid-Left (Avatar with Holographic Chat Window)
      const StageScreenSlot(
        id: 'slot_2_mid_left',
        displayName: 'Elena Vance',
        role: 'Co-Host',
        glowColor: AppColors.brandPink,
      ),
      // 3: Center Main Display (Host Primary Stage)
      StageScreenSlot(
        id: 'slot_3_center_main',
        displayName: hostName,
        role: 'Host',
        isHost: true,
        isLocalUser: widget.isHost,
        glowColor: const Color(0xFF00F0FF),
      ),
      // 4: Mid-Right (Avatar with Hologram Desk)
      const StageScreenSlot(
        id: 'slot_4_mid_right',
        displayName: 'Marcus Tech',
        role: 'VIP Guest',
        glowColor: Color(0xFF8A2BE2),
      ),
      // 5: Far-Right Lower (Female Presenter)
      const StageScreenSlot(
        id: 'slot_5_far_right_low',
        displayName: 'Chloe Bloom',
        role: 'Special Guest',
        glowColor: AppColors.brandPink,
      ),
      // 6: Far-Right Upper (Media / Video playback feed with play button)
      const StageScreenSlot(
        id: 'slot_6_far_right_up',
        displayName: 'Media Desk Deck',
        role: 'Video Deck',
        glowColor: Color(0xFFFF2D87),
      ),
    ];
  }

  @override
  void dispose() {
    _waveController.dispose();
    _glowController.dispose();
    _tickerController.dispose();
    for (final h in _hearts) {
      h.controller.dispose();
    }
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // THEME & ATMOSPHERE PALETTE
  // ───────────────────────────────────────────────────────────────────────────

  _AtmosphereColors _getAtmosphereColors() {
    final preset = (widget.atmospherePresetOverride ??
            widget.stream.stageConfig.atmospherePreset)
        .toLowerCase();

    if (preset.contains('cyber') || preset.contains('cinema') || preset.contains('7.1')) {
      // Cyber-Cinema 7.1 (Spatial Audio, IMAX Curved Hologram, Electric Cyan & Magenta)
      return const _AtmosphereColors(
        primary: Color(0xFF00F0FF),
        secondary: AppColors.brandPink,
        ambientGlow: Color(0xFF00E5FF),
        spotlight: Color(0xFF00F0FF),
        floorRim: Color(0xFF00E5FF),
        bgTop: Color(0xFF020B1E),
        bgBottom: Color(0xFF01040D),
      );
    } else if (preset.contains('stadium') || preset.contains('arena')) {
      // Neon Stadium (Electric Blue Arena & Volumetric Cones)
      return const _AtmosphereColors(
        primary: AppColors.brandBlue,
        secondary: AppColors.brandPink,
        ambientGlow: Color(0xFF00F0FF),
        spotlight: Color(0xFF38BDF8),
        floorRim: Color(0xFF00F0FF),
        bgTop: Color(0xFF051329),
        bgBottom: Color(0xFF020712),
      );
    } else if (preset.contains('acoustic') || preset.contains('loft') || preset.contains('lounge')) {
      // Acoustic Loft (Warm Sunset Amber & Timber Atmosphere)
      return const _AtmosphereColors(
        primary: Color(0xFFFF9800),
        secondary: AppColors.brandPink,
        ambientGlow: Color(0xFFFFB300),
        spotlight: Color(0xFFFFD54F),
        floorRim: Color(0xFFFF9800),
        bgTop: Color(0xFF1C0E06),
        bgBottom: Color(0xFF0B0502),
      );
    } else if (preset.contains('executive') || preset.contains('suite') || preset.contains('keynote')) {
      // Executive Suite (Polished Obsidian Glass & Cyan Platinum Glow)
      return const _AtmosphereColors(
        primary: AppColors.brandBlue,
        secondary: Color(0xFF00D2FF),
        ambientGlow: Color(0xFF00E5FF),
        spotlight: Color(0xFF81D4FA),
        floorRim: Color(0xFF00D2FF),
        bgTop: Color(0xFF071120),
        bgBottom: Color(0xFF02060D),
      );
    } else if (preset.contains('cosmic') || preset.contains('galaxy') || preset.contains('hologram')) {
      // Cosmic Hologram (Deep Stellar Nebula & Ultraviolet Particles)
      return const _AtmosphereColors(
        primary: Color(0xFF9C27B0),
        secondary: AppColors.brandPink,
        ambientGlow: Color(0xFFE040FB),
        spotlight: Color(0xFFBA68C8),
        floorRim: Color(0xFFE040FB),
        bgTop: Color(0xFF140321),
        bgBottom: Color(0xFF06000B),
      );
    }

    // Default: Cyber-Cinema 7.1
    return const _AtmosphereColors(
      primary: Color(0xFF00F0FF),
      secondary: AppColors.brandPink,
      ambientGlow: Color(0xFF00E5FF),
      spotlight: Color(0xFF00F0FF),
      floorRim: Color(0xFF00E5FF),
      bgTop: Color(0xFF020B1E),
      bgBottom: Color(0xFF01040D),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // DRAG & DROP SWAPPING
  // ───────────────────────────────────────────────────────────────────────────

  void _swapSlots(int fromIndex, int toIndex) {
    if (fromIndex == toIndex) return;
    HapticFeedback.mediumImpact();
    setState(() {
      final temp = _slots[fromIndex];
      _slots[fromIndex] = _slots[toIndex];
      _slots[toIndex] = temp;
      if (_focusedSlotIdx == fromIndex) {
        _focusedSlotIdx = toIndex;
      } else if (_focusedSlotIdx == toIndex) {
        _focusedSlotIdx = fromIndex;
      }
    });
    widget.onSlotsChanged?.call(_slots);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // SHOW LOVE HEART BURST
  // ───────────────────────────────────────────────────────────────────────────

  void _triggerShowLove() {
    HapticFeedback.lightImpact();
    widget.onShowLove?.call();

    final rng = math.Random();
    final colors = [
      const Color(0xFF00F0FF),
      AppColors.brandPink,
      const Color(0xFFFF529A),
      Colors.white,
      const Color(0xFFB388FF),
    ];

    for (int i = 0; i < 3; i++) {
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 1800 + rng.nextInt(600)),
      );

      final heart = _LoveHeart(
        startX: 0.84 + (rng.nextDouble() * 0.04 - 0.02),
        startY: 0.72,
        endX: 0.76 + (rng.nextDouble() * 0.20),
        endY: 0.20 + (rng.nextDouble() * 0.15),
        size: 18 + rng.nextDouble() * 14,
        color: colors[rng.nextInt(colors.length)],
        controller: ctrl,
      );

      setState(() => _hearts.add(heart));

      ctrl.forward().then((_) {
        if (mounted) {
          setState(() => _hearts.remove(heart));
        }
        ctrl.dispose();
      });
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // BUILD
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = _getAtmosphereColors();

    return Container(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final totalHeight = constraints.maxHeight;
          final isCompact = totalHeight < 550;

          final daisHeight = isCompact
              ? (totalHeight * 0.40).clamp(160.0, 240.0)
              : 290.0;
          final coveBottom = isCompact ? (daisHeight * 0.70) : 230.0;
          final coveTop =
              isCompact ? (widget.showTopHud ? 56.0 : 16.0) : 75.0;
          final tableBottom = isCompact ? (daisHeight * 0.32) : 105.0;
          final reqJoinTop =
              isCompact ? totalHeight * 0.28 : totalHeight * 0.38;
          final commentBottom = isCompact ? 36.0 : 85.0;
          final loveBottom = isCompact ? 32.0 : 80.0;
          final dockBottom = isCompact ? 8.0 : 22.0;

          // The studio photo is rendered at its NATURAL aspect ratio
          // (full width, never stretched/zoomed/cropped); cards attach to it.
          final imgW = totalWidth;
          final imgH = totalWidth * _studioAspectH / _studioAspectW;
          final imgTop = (totalHeight - imgH) / 2;

          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Studio background photo (no overlays on top of it)
              _buildVirtualRoomBackground(colors, imgW, imgH, imgTop),

              // 2. Screens attached to the studio walls
              if (_layoutMode == 0)
                Positioned(
                  left: 0,
                  top: imgTop,
                  width: imgW,
                  height: imgH,
                  child: _buildAmphitheaterCove(colors,
                      imgW: imgW, imgH: imgH),
                )
              else
                Positioned(
                  top: coveTop,
                  left: 0,
                  right: 0,
                  bottom: coveBottom,
                  child: _buildAmphitheaterCove(colors),
                ),

              // 6. Glowing Central Holographic "Presentation table for goods"
              Positioned(
                left: 0,
                right: 0,
                bottom: tableBottom,
                child: Center(
                  child: _buildPresentationTableForGoods(colors),
                ),
              ),

              // 7. Left-Side "+ Request to join" Floating Stage Button
              Positioned(
                left: 14,
                top: reqJoinTop,
                child: _buildRequestToJoinButton(colors),
              ),

              // 8. Holographic Floor Comment Bubble ("Comment section babbe")
              Positioned(
                left: 20,
                bottom: commentBottom,
                child: _buildHolographicCommentBubble(colors),
              ),

              // 9. Floating Love Heart Reaction Fireworks
              ..._buildFloatingHearts(Size(totalWidth, totalHeight)),

              // 10. Bottom-Right "SHOW LOVE" Button
              Positioned(
                right: 22,
                bottom: loveBottom,
                child: _buildShowLoveButton(colors),
              ),

              // 11. Bottom-Left Studio Mode Controls Dock
              Positioned(
                left: 18,
                bottom: dockBottom,
                child: _buildStudioControlsDock(colors),
              ),

              // 12. Top HUD Bar: Live 200k badge, Media Desk shortcut, close button
              if (widget.showTopHud)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: _buildTopHudBar(colors),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 1. VIRTUAL ROOM BACKGROUND
  // ───────────────────────────────────────────────────────────────────────────

  static const double _studioAspectW = 1024;
  static const double _studioAspectH = 571;
  static const Color _neonBlue = Color(0xFF2E7BFF); // lifted brand blue glow
  static const Color _studioFill = Color(0xFF030811);

  Widget _buildVirtualRoomBackground(
      _AtmosphereColors colors, double imgW, double imgH, double imgTop) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: _studioFill),
        Positioned(
          left: 0,
          top: imgTop,
          width: imgW,
          height: imgH,
          // Box already has the photo's aspect ratio, so BoxFit.fill is a
          // 1:1 render – no squeeze, no zoom.
          child: Image.asset(
            'assets/images/live_studio_bg.jpg',
            fit: BoxFit.fill,
            filterQuality: FilterQuality.high,
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 3. FLOATING ACOUSTIC SINE WAVES
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildAcousticSineWaves(_AtmosphereColors colors) {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, child) {
        return CustomPaint(
          painter: _AcousticWavePainter(
            phase: _waveController.value * 2 * math.pi,
            primaryColor: colors.primary.withValues(alpha: 0.45),
            secondaryColor: colors.secondary.withValues(alpha: 0.35),
            cyanColor: colors.ambientGlow.withValues(alpha: 0.6),
          ),
        );
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 4. AMPHITHEATER COVE: CURVED WALL WITH DRAGGABLE 3D SCREENS
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildAmphitheaterCove(_AtmosphereColors colors,
      {double? imgW, double? imgH}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 360),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: _layoutMode == 2
          ? KeyedSubtree(
              key: const ValueKey('cinema_focus_view'),
              child: _buildCinemaFocusView(colors),
            )
          : (_layoutMode == 1
              ? KeyedSubtree(
                  key: const ValueKey('multiview_grid_view'),
                  child: _buildMultiviewGrid(colors),
                )
              : KeyedSubtree(
                  key: const ValueKey('cove_panoramic_view'),
                  child: _buildCovePanoramicWall(colors,
                      imgW: imgW, imgH: imgH),
                )),
    );
  }

  /// Cards are laid out in the coordinate space of the studio photograph
  /// (fractions of its width/height) so they stay attached to the same
  /// walls regardless of screen size. [imgW]/[imgH] is the rendered image.
  Widget _buildCovePanoramicWall(_AtmosphereColors colors,
      {double? imgW, double? imgH}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = imgW ?? constraints.maxWidth;
        final h = imgH ?? constraints.maxHeight;

        Widget slot(
          int i, {
          required double l,
          required double t,
          required double wf,
          required double hf,
          required double rotY,
          double scale = 1.0,
          bool main = false,
          bool media = false,
        }) {
          return Positioned(
            left: l * w,
            top: t * h,
            width: wf * w,
            height: hf * h,
            child: _build3DScreenSlot(
              i,
              colors,
              rotationY: rotY,
              scale: scale,
              isMainCenter: main,
              isMediaPlayback: media,
            ),
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Left glass balcony (upper) – attached to the left wall
            slot(0, l: 0.015, t: 0.04, wf: 0.19, hf: 0.50, rotY: 0.42),
            // Left lower desk wall
            slot(1, l: 0.03, t: 0.58, wf: 0.19, hf: 0.50, rotY: 0.45),
            // Mid-left – flanking the curved LED wall
            slot(2, l: 0.19, t: 0.30, wf: 0.17, hf: 0.52, rotY: 0.24),
            // Right glass balcony (upper)
            slot(6,
                l: 0.795,
                t: 0.04,
                wf: 0.19,
                hf: 0.50,
                rotY: -0.42,
                media: true),
            // Right lower desk wall
            slot(5, l: 0.78, t: 0.58, wf: 0.19, hf: 0.50, rotY: -0.45),
            // Mid-right
            slot(4, l: 0.64, t: 0.30, wf: 0.17, hf: 0.52, rotY: -0.24),
            // Center host card on the main curved LED screen (front-most)
            slot(3,
                l: 0.34,
                t: -0.02,
                wf: 0.32,
                hf: 0.86,
                rotY: 0.0,
                main: true),
          ],
        );
      },
    );
  }

  /// AI auto-arrange: host to the center LED screen, co-host / VIP guests to
  /// the flanking screens, active cameras before inactive, media deck on the
  /// upper-right wall.
  void _aiAutoArrangeStage() {
    HapticFeedback.mediumImpact();
    final pool = List<StageScreenSlot>.from(_slots);

    int priority(StageScreenSlot s) {
      var p = 0;
      if (s.isHost) p += 1000;
      if (s.isLocalUser) p += 500;
      final role = s.role.toLowerCase();
      if (role.contains('co-host')) p += 300;
      if (role.contains('vip') || role.contains('special')) p += 200;
      if (role.contains('guest')) p += 100;
      if (s.isVideoActive) p += 60;
      if (s.isAudioActive) p += 30;
      return p;
    }

    final media = pool.where((s) => s.role == 'Video Deck').toList();
    final people = pool.where((s) => s.role != 'Video Deck').toList()
      ..sort((a, b) => priority(b).compareTo(priority(a)));

    // Slot index order by visual importance on the wall.
    const order = [3, 2, 4, 1, 5, 0];
    final result = List<StageScreenSlot?>.filled(_slots.length, null);
    for (var i = 0; i < people.length && i < order.length; i++) {
      result[order[i]] = people[i];
    }
    if (media.isNotEmpty) result[6] = media.first;
    final leftovers = people.skip(order.length).toList();
    for (var i = 0; i < result.length; i++) {
      if (result[i] == null && leftovers.isNotEmpty) {
        result[i] = leftovers.removeAt(0);
      }
    }
    setState(() {
      for (var i = 0; i < _slots.length; i++) {
        _slots[i] = result[i] ?? _slots[i];
      }
      _focusedSlotIdx = 3;
      _layoutMode = 0;
    });
    widget.onSlotsChanged?.call(_slots);
  }

  Widget _build3DScreenSlot(
    int index,
    _AtmosphereColors colors, {
    required double rotationY,
    required double scale,
    bool isMainCenter = false,
    bool hasTopTabs = false,
    bool hasSideChatPanel = false,
    bool isMediaPlayback = false,
  }) {
    if (index >= _slots.length) return const SizedBox.shrink();
    final slot = _slots[index];
    final isFocused = _focusedSlotIdx == index;

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) {
        if (details.data != index) {
          HapticFeedback.selectionClick();
          setState(() => _hoveredDropTargetIndex = index);
        }
        return true;
      },
      onLeave: (_) {
        if (_hoveredDropTargetIndex == index) {
          setState(() => _hoveredDropTargetIndex = null);
        }
      },
      onAcceptWithDetails: (details) {
        setState(() {
          _hoveredDropTargetIndex = null;
          _draggingSlotIndex = null;
        });
        _swapSlots(details.data, index);
      },
      builder: (context, candidateData, rejectedData) {
        final isDropTarget =
            candidateData.isNotEmpty || _hoveredDropTargetIndex == index;

        return LongPressDraggable<int>(
          data: index,
          delay: const Duration(milliseconds: 150),
          onDragStarted: () {
            HapticFeedback.selectionClick();
            setState(() => _draggingSlotIndex = index);
          },
          onDragEnd: (_) {
            setState(() {
              _draggingSlotIndex = null;
              _hoveredDropTargetIndex = null;
            });
          },
          feedback: Material(
            color: Colors.transparent,
            child: _buildDragFeedbackScreen(slot, colors, isMainCenter),
          ),
          childWhenDragging: Opacity(
            opacity: _draggingSlotIndex == index ? 0.20 : 0.40,
            child: _buildTransformedScreen(
              slot,
              index,
              colors,
              rotationY: rotationY,
              scale: scale,
              isMainCenter: isMainCenter,
              hasTopTabs: hasTopTabs,
              hasSideChatPanel: hasSideChatPanel,
              isMediaPlayback: isMediaPlayback,
              isFocused: isFocused,
              isDropTarget: false,
            ),
          ),
          child: GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              setState(() {
                _focusedSlotIdx = index;
                _layoutMode = 2; // Smoothly zoom into Cinema Focus Spotlight
              });
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _buildTransformedScreen(
                  slot,
                  index,
                  colors,
                  rotationY: rotationY,
                  scale: scale,
                  isMainCenter: isMainCenter,
                  hasTopTabs: hasTopTabs,
                  hasSideChatPanel: hasSideChatPanel,
                  isMediaPlayback: isMediaPlayback,
                  isFocused: isFocused,
                  isDropTarget: isDropTarget,
                ),
                // Drag Handle Grip
                Positioned(
                  top: 5,
                  left: 5,
                  child: Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 0.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.drag_indicator_rounded,
                      size: 9,
                      color: Colors.white70,
                    ),
                  ),
                ),
                // Active Drop Target Overlay Indicator
                if (isDropTarget)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.brandPink.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.brandPink,
                          width: 2.0,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppColors.brandPink,
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            index == 3 ? 'DROP TO SPOTLIGHT' : 'DROP TO SWAP',
                            style: GoogleFonts.inter(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDragFeedbackScreen(
      StageScreenSlot slot, _AtmosphereColors colors, bool isMainCenter) {
    return Container(
      width: isMainCenter ? 170 : 120,
      height: isMainCenter ? 130 : 90,
      decoration: BoxDecoration(
        color: const Color(0xFF0A1020).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brandPink, width: 2.0),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPink.withValues(alpha: 0.6),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.open_with_rounded,
              color: AppColors.brandPink, size: 20),
          const SizedBox(height: 4),
          Text(
            slot.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Reordering ${slot.role}...',
            style: GoogleFonts.inter(
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
              color: colors.ambientGlow,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransformedScreen(
    StageScreenSlot slot,
    int index,
    _AtmosphereColors colors, {
    required double rotationY,
    required double scale,
    required bool isMainCenter,
    required bool hasTopTabs,
    required bool hasSideChatPanel,
    required bool isMediaPlayback,
    required bool isFocused,
    required bool isDropTarget,
  }) {
    // 3D Perspective Matrix Transformation
    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.0016) // depth perspective
      ..rotateY(rotationY);

    return Transform(
      transform: matrix,
      alignment: rotationY > 0 ? Alignment.centerRight : Alignment.centerLeft,
      child: Transform.scale(
        scale: scale,
        alignment: rotationY > 0 ? Alignment.centerRight : Alignment.centerLeft,
        child: _buildScreenContent(
          slot,
          index,
          colors,
          isMainCenter: isMainCenter,
          hasTopTabs: hasTopTabs,
          hasSideChatPanel: hasSideChatPanel,
          isMediaPlayback: isMediaPlayback,
          isFocused: isFocused,
          isDropTarget: isDropTarget,
        ),
      ),
    );
  }

  Widget _buildScreenContent(
    StageScreenSlot slot,
    int index,
    _AtmosphereColors colors, {
    required bool isMainCenter,
    required bool hasTopTabs,
    required bool hasSideChatPanel,
    required bool isMediaPlayback,
    required bool isFocused,
    bool isDropTarget = false,
  }) {
    final frameColor = isDropTarget
        ? AppColors.brandPink
        : (isMainCenter
            ? _neonBlue
            : (_isPinkFrame(index) ? AppColors.brandPink : _neonBlue));
    final isLive = slot.isVideoActive;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF050B1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: frameColor,
          width: isFocused || isMainCenter ? 1.8 : 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: frameColor.withValues(alpha: isFocused ? 0.55 : 0.38),
            blurRadius: isFocused ? 14 : 9,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Feed Content: Camera preview, media deck, or participant feed
          if (slot.isLocalUser &&
              widget.localCameraController != null &&
              widget.localCameraController!.value.isInitialized)
            _buildSafeCameraPreview(
              widget.localCameraController,
              fallback: isMainCenter
                  ? _buildMainCenterStageFeed(slot, colors)
                  : _buildParticipantVideoFeed(slot, colors, index),
            )
          else if (isMediaPlayback)
            _buildMediaPlaybackFeed(colors)
          else if (isMainCenter)
            _buildMainCenterStageFeed(slot, colors)
          else
            _buildParticipantVideoFeed(slot, colors, index),

          // CAM 1 tag (center card)
          if (isMainCenter)
            Positioned(
              top: 0,
              left: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF050B1A),
                  borderRadius: const BorderRadius.only(
                    bottomRight: Radius.circular(6),
                  ),
                  border: Border.all(color: _neonBlue, width: 0.8),
                ),
                child: Text(
                  'CAM 1',
                  style: GoogleFonts.inter(
                    fontSize: 6.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: _neonBlue,
                  ),
                ),
              ),
            ),

          // LIVE pill
          if (isLive)
            Positioned(
              top: 4,
              left: isMainCenter ? null : 4,
              right: isMainCenter ? 4 : null,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF050B1A).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppColors.brandPink, width: 0.9),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: AppColors.brandPink,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'LIVE',
                      style: GoogleFonts.inter(
                        fontSize: 6.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Drag handle (hint that cards are movable)
          if (!isMainCenter)
            Positioned(
              top: 4,
              right: 4,
              child: Icon(
                Icons.drag_indicator_rounded,
                size: 9,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),

          // Name label: HOST pill on center, plain legible text elsewhere
          if (isMainCenter)
            Positioned(
              left: 8,
              right: 8,
              bottom: 32,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF050B1A).withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _neonBlue, width: 0.9),
                  ),
                  child: Text(
                    'HOST • ${slot.displayName.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 7,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            )
          else
            Positioned(
              left: 6,
              right: 6,
              bottom: 5,
              child: Row(
                children: [
                  if (!slot.isAudioActive)
                    const Padding(
                      padding: EdgeInsets.only(right: 3),
                      child: Icon(Icons.mic_off_rounded,
                          size: 9, color: AppColors.brandPink),
                    ),
                  Expanded(
                    child: Text(
                      slot.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 4),
                          Shadow(color: Colors.black, blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSafeCameraPreview(CameraController? ctrl,
      {required Widget fallback}) {
    if (ctrl == null || !ctrl.value.isInitialized) {
      return fallback;
    }
    try {
      return ctrl.buildPreview();
    } catch (_) {
      return fallback;
    }
  }

  /// Alternating pink / blue neon frames (pink on even wall slots).
  bool _isPinkFrame(int index) => index == 0 || index == 2 || index == 5;

  Widget _buildMainCenterStageFeed(
      StageScreenSlot slot, _AtmosphereColors colors) {
    final onStage = _slots.where((s) => s.isVideoActive).length;
    final avatar = slot.avatarUrl.isNotEmpty
        ? slot.avatarUrl
        : widget.stream.hostAvatarUrl;

    Widget stat(String label, String value, Color valueColor) {
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              style: GoogleFonts.inter(
                fontSize: 5.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: Colors.white54,
              ),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 8.5,
                fontWeight: FontWeight.w900,
                color: valueColor,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0C2A66), Color(0xFF050B1A)],
                  ),
                ),
              ),
              if (avatar.isNotEmpty)
                Image.network(
                  avatar,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                )
              else
                const Center(
                  child:
                      Icon(Icons.person_rounded, size: 40, color: Colors.white70),
                ),
            ],
          ),
        ),
        // Brand gradient divider (blue → pink)
        Container(
          height: 1.5,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.brandBlue, AppColors.brandPink],
            ),
          ),
        ),
        Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          color: const Color(0xFF050B1A),
          child: Row(
            children: [
              stat(
                'AUDIO',
                slot.isAudioActive ? 'LIVE' : 'MUTED',
                slot.isAudioActive ? _neonBlue : AppColors.brandPink,
              ),
              stat('VIEWERS', _compactCount(widget.stream.viewerCount),
                  Colors.white),
              stat('ON STAGE', '$onStage', AppColors.brandPink),
            ],
          ),
        ),
      ],
    );
  }

  String _compactCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  Widget _buildMediaPlaybackFeed(_AtmosphereColors colors) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E0A2A), Color(0xFF0D0414)],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glowing Play Button
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brandPink.withValues(alpha: 0.25),
              border: Border.all(color: AppColors.brandPink, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandPink.withValues(alpha: 0.5),
                  blurRadius: 10,
                ),
              ],
            ),
            child: const Icon(Icons.play_arrow_rounded,
                size: 20, color: Colors.white),
          ),
          // Video Timeline Bar at bottom
          Positioned(
            bottom: 18,
            left: 8,
            right: 8,
            child: Container(
              height: 2.5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                children: [
                  Container(
                    width: 25,
                    decoration: BoxDecoration(
                      color: AppColors.brandPink,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantVideoFeed(
      StageScreenSlot slot, _AtmosphereColors colors, int index) {
    final isPink = _isPinkFrame(index);
    final tint = isPink ? AppColors.brandPink : AppColors.brandBlue;
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                tint.withValues(alpha: 0.35),
                const Color(0xFF050B1A),
              ],
            ),
          ),
        ),
        if (slot.avatarUrl.isNotEmpty)
          Image.network(
            slot.avatarUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          )
        else
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tint.withValues(alpha: 0.85),
                    border: Border.all(color: Colors.white38, width: 1.0),
                  ),
                  child: Center(
                    child: Text(
                      slot.displayName.isNotEmpty
                          ? slot.displayName[0].toUpperCase()
                          : '?',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  slot.role,
                  style: GoogleFonts.inter(
                    fontSize: 7.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMultiviewGrid(_AtmosphereColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: GridView.builder(
        itemCount: _slots.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.25,
        ),
        itemBuilder: (context, i) {
          final slot = _slots[i];
          return GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              setState(() {
                _focusedSlotIdx = i;
                _layoutMode = 2; // Smoothly zoom into Cinema Focus Spotlight
              });
            },
            child: _buildScreenContent(
              slot,
              i,
              colors,
              isMainCenter: i == 3,
              hasTopTabs: false,
              hasSideChatPanel: false,
              isMediaPlayback: i == 6,
              isFocused: _focusedSlotIdx == i,
            ),
          );
        },
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 4B. CINEMA FOCUS VIEW (Smooth Spotlight Zoom on Selected Participant)
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildCinemaFocusView(_AtmosphereColors colors) {
    final slot = _slots[_focusedSlotIdx.clamp(0, _slots.length - 1)];
    final tickerText = widget.customLowerThird?.trim().isNotEmpty == true
        ? widget.customLowerThird!.toUpperCase()
        : 'SINGLE SEARCHING · ON-AIR CINEMA 7.1';

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // 1. Atmospheric Deep Background Ambient Glow & Multi-layer Blur
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.25),
                      radius: 1.25,
                      colors: [
                        colors.primary.withValues(alpha: 0.35),
                        const Color(0xFF020714).withValues(alpha: 0.90),
                        context.bg,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Floating Background Wave Aura
            Positioned(
              top: 40,
              left: 0,
              right: 0,
              height: 100,
              child: Opacity(
                opacity: 0.45,
                child: _buildAcousticSineWaves(colors),
              ),
            ),

            // 2. Spotlighted Center Screen (Smooth cinematic zoom)
            Positioned(
              top: 50,
              bottom: 90,
              left: 14,
              right: 14,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colors.primary,
                    width: 2.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.45),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: colors.ambientGlow.withValues(alpha: 0.20),
                      blurRadius: 40,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // High-definition Screen feed
                    _buildScreenContent(
                      slot,
                      _focusedSlotIdx,
                      colors,
                      isMainCenter: true,
                      hasTopTabs: true,
                      hasSideChatPanel: false,
                      isMediaPlayback: slot.role == 'Video Deck',
                      isFocused: true,
                    ),

                    // Sci-Fi Corner Bracket Highlights
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: colors.ambientGlow, width: 2.0),
                            left: BorderSide(color: colors.ambientGlow, width: 2.0),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: colors.ambientGlow, width: 2.0),
                            right: BorderSide(color: colors.ambientGlow, width: 2.0),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 24,
                      left: 6,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: colors.ambientGlow, width: 2.0),
                            left: BorderSide(color: colors.ambientGlow, width: 2.0),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 24,
                      right: 6,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: colors.ambientGlow, width: 2.0),
                            right: BorderSide(color: colors.ambientGlow, width: 2.0),
                          ),
                        ),
                      ),
                    ),

                    // Top Bar Info Overlay
                    Positioned(
                      top: 10,
                      left: 12,
                      right: 12,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white12, width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  slot.isHost ? Icons.verified_rounded : Icons.mic_rounded,
                                  size: 13,
                                  color: colors.ambientGlow,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  slot.displayName,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: AppColors.brandPink.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: AppColors.brandPink, width: 0.7),
                                  ),
                                  child: Text(
                                    slot.role,
                                    style: GoogleFonts.inter(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.brandPink,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          // 1080p60 · SPOTLIGHT Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: colors.ambientGlow.withValues(alpha: 0.35)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '1080p60 · SPOTLIGHT',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                    color: colors.ambientGlow,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Exit Focus Button (Returns back to full stage cove)
                          InkWell(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              setState(() => _layoutMode = 0);
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Marquee Lower-Third Live Ticker Banner inside spotlight
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          border: Border(
                            top: BorderSide(
                              color: colors.ambientGlow.withValues(alpha: 0.35),
                              width: 0.8,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.brandPink,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                'LIVE TICKER',
                                style: GoogleFonts.inter(
                                  fontSize: 7.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tickerText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: colors.ambientGlow,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 3. Horizontal Participant Ribbon (Tap any participant to smoothly spotlight them in center)
            Positioned(
              top: 10,
              left: 14,
              right: 14,
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _slots.length,
                separatorBuilder: (ctx, index) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final s = _slots[i];
                  final isCurrent = i == _focusedSlotIdx;
                  return InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _focusedSlotIdx = i);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? colors.primary.withValues(alpha: 0.35)
                            : Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isCurrent ? colors.primary : Colors.white12,
                          width: isCurrent ? 1.4 : 0.8,
                        ),
                        boxShadow: isCurrent
                            ? [
                                BoxShadow(
                                  color: colors.primary.withValues(alpha: 0.35),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isCurrent ? AppColors.brandPink : Colors.white38,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            s.displayName,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
                              color: isCurrent ? Colors.white : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // 4. Streamlined Stream Logs and Live Comments
            Positioned(
              bottom: 12,
              left: 16,
              right: 90,
              child: _buildCinemaCommentStreamOverlay(colors),
            ),

            // 5. Floating Hearts & Show Love Button (in bottom-right)
            Positioned(
              bottom: 12,
              right: 16,
              child: _buildShowLoveButton(colors),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCinemaCommentStreamOverlay(_AtmosphereColors colors) {
    final currentLog = _streamLogs[_currentStreamLogIdx % _streamLogs.length];

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _currentStreamLogIdx = (_currentStreamLogIdx + 1) % _streamLogs.length;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.primary.withValues(alpha: 0.35), width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stream Event Log
            Row(
              children: [
                const Icon(Icons.bolt_rounded, color: AppColors.brandPink, size: 11),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    currentLog,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: colors.ambientGlow,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'TAP NEXT',
                  style: GoogleFonts.inter(
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            // Live Chat Comment Ticker
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 10),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white),
                      children: [
                        TextSpan(
                          text: '$_latestCommentUser: ',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            color: Colors.white70,
                          ),
                        ),
                        TextSpan(
                          text: _latestComment,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 6. GLOWING HOLOGRAPHIC "Presentation table for goods"
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildPresentationTableForGoods(_AtmosphereColors colors) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        widget.onTapPresentationTable?.call();
        _showGoodsShowcaseModal(context, colors);
      },
      child: AnimatedBuilder(
        animation: _glowController,
        builder: (context, child) {
          final glowVal = _glowController.value;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Floating Holographic Glass Panel / Tablet
              Container(
                width: 176,
                height: 86,
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colors.ambientGlow
                        .withValues(alpha: 0.75 + glowVal * 0.25),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.ambientGlow
                          .withValues(alpha: 0.35 + glowVal * 0.25),
                      blurRadius: 16 + glowVal * 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Rising sparkle particles
                    Positioned(
                      top: 6 + (glowVal * 6),
                      right: 12,
                      child: Icon(
                        Icons.auto_awesome,
                        size: 11,
                        color: colors.ambientGlow,
                      ),
                    ),
                    Positioned(
                      bottom: 8 + (glowVal * 4),
                      left: 10,
                      child: Icon(
                        Icons.star_rounded,
                        size: 9,
                        color: colors.secondary,
                      ),
                    ),
                    // Centered Text exactly as in reference drawing
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Presentation table\nfor goods',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.kalam(
                              fontSize: 12.0,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  color: colors.ambientGlow,
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.touch_app_rounded,
                                  size: 9, color: colors.ambientGlow),
                              const SizedBox(width: 3),
                              Text(
                                'Tap to inspect',
                                style: GoogleFonts.inter(
                                  fontSize: 7.5,
                                  fontWeight: FontWeight.w700,
                                  color: colors.ambientGlow,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 4),

              // Glowing Cylindrical Pedestal Rim Base
              Container(
                width: 165,
                height: 22,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(
                    Radius.elliptical(165, 22),
                  ),
                  border: Border.all(
                    color: colors.ambientGlow,
                    width: 2.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.ambientGlow.withValues(alpha: 0.6),
                      blurRadius: 14,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  gradient: LinearGradient(
                    colors: [
                      colors.ambientGlow.withValues(alpha: 0.9),
                      colors.primary,
                      colors.secondary,
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 7. LEFT-SIDE "+ Request to join" FLOATING STAGE BUTTON
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildRequestToJoinButton(_AtmosphereColors colors) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        if (widget.isHost) {
          _showHostCoHostPermissionSheet(context, colors);
        } else {
          widget.onRequestToJoin?.call();
          _showViewerCoHostRequestSheet(context, colors);
        }
      },
      child: Container(
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colors.ambientGlow.withValues(alpha: 0.7),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: colors.ambientGlow.withValues(alpha: 0.35),
              blurRadius: 12,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Plus inside square frame matching reference image
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: colors.ambientGlow,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.add,
                  size: 16,
                  color: colors.ambientGlow,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Request\nto join',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                height: 1.15,
                color: Colors.white,
              ),
            ),
            if (widget.isHost && _guestJoinRequests.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: AppColors.brandPink,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_guestJoinRequests.length}',
                  style: GoogleFonts.inter(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 8. HOLOGRAPHIC FLOOR COMMENT BUBBLE ("Comment section babbe")
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildHolographicCommentBubble(_AtmosphereColors colors) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _showLiveCommentInput(context, colors);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colors.ambientGlow.withValues(alpha: 0.4),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Comment section · $_latestCommentUser',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Colors.white60,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _latestComment,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.ambientGlow.withValues(alpha: 0.2),
                border: Border.all(
                  color: colors.ambientGlow,
                  width: 1.0,
                ),
              ),
              child: const Icon(
                Icons.person_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 9. FLOATING LOVE HEARTS
  // ───────────────────────────────────────────────────────────────────────────

  List<Widget> _buildFloatingHearts(Size size) {
    return _hearts.map((h) {
      return AnimatedBuilder(
        animation: h.controller,
        builder: (context, child) {
          final t = h.controller.value;
          // Curving path trajectory upward
          final curX = ui.lerpDouble(h.startX, h.endX, t)! +
              (math.sin(t * math.pi * 2) * 0.04);
          final curY = ui.lerpDouble(h.startY, h.endY, t)!;
          final opacity = (1.0 - t).clamp(0.0, 1.0);
          final scale = 0.6 + (t * 0.7);

          return Positioned(
            left: curX * size.width,
            top: curY * size.height,
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: Icon(
                  Icons.favorite_rounded,
                  size: h.size,
                  color: h.color,
                  shadows: [
                    Shadow(
                      color: h.color,
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }).toList();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 10. BOTTOM-RIGHT "SHOW LOVE" BUTTON
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildShowLoveButton(_AtmosphereColors colors) {
    return GestureDetector(
      onTap: _triggerShowLove,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.65),
              border: Border.all(
                color: AppColors.brandPink,
                width: 1.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandPink.withValues(alpha: 0.55),
                  blurRadius: 14,
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.favorite_rounded,
                size: 26,
                color: AppColors.brandPink,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'SHOW\nLOVE',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              height: 1.15,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 11. BOTTOM-LEFT STUDIO MODE DOCK
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildStudioControlsDock(_AtmosphereColors colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDockButton(
          icon: Icons.grid_view_rounded,
          isActive: _layoutMode == 0,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _layoutMode = 0);
          },
        ),
        const SizedBox(width: 8),
        _buildDockButton(
          icon: Icons.filter_none_rounded,
          isActive: _layoutMode == 1,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _layoutMode = 1);
          },
        ),
        const SizedBox(width: 8),
        _buildDockButton(
          icon: Icons.center_focus_strong_rounded,
          isActive: _layoutMode == 2,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _layoutMode = _layoutMode == 2 ? 0 : 2);
          },
        ),
        const SizedBox(width: 8),
        _buildDockButton(
          icon: Icons.videocam_rounded,
          isActive: false,
          onTap: () {
            HapticFeedback.selectionClick();
            _showStageCameraAngles(context, colors);
          },
        ),
        const SizedBox(width: 8),
        _buildDockButton(
          icon: Icons.auto_awesome_rounded,
          isActive: true,
          isAccentPink: true,
          onTap: _aiAutoArrangeStage,
        ),
      ],
    );
  }

  Widget _buildDockButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    bool isAccentPink = false,
  }) {
    final accent = isAccentPink ? AppColors.brandPink : _neonBlue;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFF050B1A).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? accent : Colors.white.withValues(alpha: 0.25),
            width: isActive ? 1.5 : 1.0,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.4),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: 16,
          color: isActive ? accent : Colors.white70,
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 12. TOP HUD BAR: Live 200k badge, Media Desk, Close
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildTopHudBar(_AtmosphereColors colors) {
    final viewers = widget.stream.viewerCount > 0
        ? widget.stream.viewerCount
        : 200000;
    final viewerStr = viewers >= 1000
        ? '${(viewers / 1000).toStringAsFixed(0)}k'
        : '$viewers';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // "Live 200k 👁" Badge matching reference image
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colors.ambientGlow.withValues(alpha: 0.4),
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.brandPink,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Live',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: colors.ambientGlow,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  viewerStr,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.remove_red_eye_outlined,
                  size: 13,
                  color: Colors.white70,
                ),
              ],
            ),
          ),

          const Spacer(),

          // Media Desk quick shortcut (soundboard, BGM, atmosphere)
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onOpenMediaDesk?.call();
              OneovaLiveMediaDeskSheet.show(
                context,
                streamId: widget.stream.id,
                hostHandle: '@${widget.stream.hostDisplayName.toLowerCase().replaceAll(' ', '')}',
              );
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.5),
                  width: 1.0,
                ),
              ),
              child: const Icon(
                Icons.tune_rounded,
                size: 17,
                color: Colors.white,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Close / Leave button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              if (widget.onClose != null) {
                widget.onClose!();
              } else {
                Navigator.of(context).maybePop();
              }
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1.0,
                ),
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 17,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // MODALS & ACTIONS
  // ───────────────────────────────────────────────────────────────────────────

  void _showGoodsShowcaseModal(BuildContext context, _AtmosphereColors colors) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.paddingOf(ctx).bottom + 20),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1020),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: colors.ambientGlow.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.storefront_rounded,
                      color: colors.ambientGlow, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Presentation Table · Featured Goods',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ..._goodsItems.map((item) {
                final color = item['color'] as Color;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101B33),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: color.withValues(alpha: 0.4),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: color.withValues(alpha: 0.4)),
                        ),
                        child: Icon(item['icon'] as IconData,
                            size: 20, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['title'] as String,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              item['tag'] as String,
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                color: Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            item['price'] as String,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: colors.ambientGlow,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: color,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(64, 26),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Selected: ${item['title']}',
                                    style: GoogleFonts.inter(),
                                  ),
                                  backgroundColor: color,
                                ),
                              );
                            },
                            child: Text(
                              'Inspect',
                              style: GoogleFonts.inter(
                                  fontSize: 10, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showHostCoHostPermissionSheet(
      BuildContext context, _AtmosphereColors colors) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.85,
              ),
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, MediaQuery.paddingOf(ctx).bottom + 20),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1020),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: colors.ambientGlow.withValues(alpha: 0.4)),
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white30,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.brandPink.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.supervised_user_circle_rounded,
                              color: AppColors.brandPink, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Stage Co-Host & Permission Control',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Grant camera & mic slots on the curved amphitheater wall',
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.brandBlue, width: 0.8),
                          ),
                          child: Text(
                            '${_guestJoinRequests.length} Pending',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: colors.ambientGlow,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Section 1: Pending Co-Host Requests
                    Text(
                      'PENDING VIEWER REQUESTS',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: colors.ambientGlow,
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (_guestJoinRequests.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF101B33),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Center(
                          child: Text(
                            'No pending co-host requests from viewers',
                            style: GoogleFonts.inter(color: Colors.white60, fontSize: 12),
                          ),
                        ),
                      )
                    else
                      ..._guestJoinRequests.map((req) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF101B33),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colors.primary.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: AppColors.brandBlue,
                                    child: Text(
                                      req.name.isNotEmpty ? req.name[0] : '?',
                                      style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w800, color: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          req.name,
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Text(
                                          '${req.handle} · ${req.requestedAgo}',
                                          style: GoogleFonts.inter(
                                            fontSize: 10.5,
                                            color: Colors.white60,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Device capability indicators
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: req.hasCamera
                                          ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                          : Colors.white12,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          req.hasCamera
                                              ? Icons.videocam_rounded
                                              : Icons.videocam_off_rounded,
                                          size: 11,
                                          color: req.hasCamera
                                              ? const Color(0xFF10B981)
                                              : Colors.white60,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          req.hasCamera ? 'Cam Ready' : 'No Cam',
                                          style: GoogleFonts.inter(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: req.hasCamera
                                                ? const Color(0xFF10B981)
                                                : Colors.white60,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.brandPink.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(
                                      Icons.mic_rounded,
                                      size: 11,
                                      color: AppColors.brandPink,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  // Grant Camera & Mic Button
                                  Expanded(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.brandPink,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        HapticFeedback.mediumImpact();
                                        setState(() {
                                          _guestJoinRequests.remove(req);
                                          // Find best slot (slot 1 or 2 or 5)
                                          int targetSlot = 1;
                                          if (_slots[1].displayName != 'David K.' &&
                                              !_slots[1].isHost) {
                                            targetSlot = 1;
                                          } else if (!_slots[2].isHost) {
                                            targetSlot = 2;
                                          } else if (!_slots[5].isHost) {
                                            targetSlot = 5;
                                          }
                                          _slots[targetSlot] = _slots[targetSlot].copyWith(
                                            displayName: req.name,
                                            role: 'Co-Host',
                                            isVideoActive: req.hasCamera,
                                            isAudioActive: req.hasMic,
                                            glowColor: AppColors.brandPink,
                                          );
                                        });
                                        widget.onSlotsChanged?.call(_slots);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '🎉 ${req.name} granted Co-Host access with Camera & Mic!',
                                              style: GoogleFonts.inter(),
                                            ),
                                            backgroundColor: AppColors.brandPink,
                                          ),
                                        );
                                      },
                                      child: Text(
                                        'Grant Cam & Mic',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Grant Mic Only
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: BorderSide(color: colors.primary.withValues(alpha: 0.6)),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      HapticFeedback.lightImpact();
                                      setState(() {
                                        _guestJoinRequests.remove(req);
                                        _slots[1] = _slots[1].copyWith(
                                          displayName: req.name,
                                          role: 'Speaker (Audio)',
                                          isVideoActive: false,
                                          isAudioActive: true,
                                          glowColor: colors.primary,
                                        );
                                      });
                                      widget.onSlotsChanged?.call(_slots);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '${req.name} granted Stage Mic Audio access!',
                                            style: GoogleFonts.inter(),
                                          ),
                                          backgroundColor: colors.primary,
                                        ),
                                      );
                                    },
                                    child: Text(
                                      'Mic Only',
                                      style: GoogleFonts.inter(
                                          fontSize: 10.5, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Decline
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded,
                                        size: 18, color: Colors.white60),
                                    onPressed: () {
                                      setModalState(() {
                                        _guestJoinRequests.remove(req);
                                      });
                                      setState(() {});
                                    },
                                    tooltip: 'Decline',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),

                    const SizedBox(height: 18),

                    // Section 2: Active Stage Participants Moderation
                    Text(
                      'ACTIVE STAGE CO-HOSTS & GUESTS',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: colors.ambientGlow,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(_slots.length, (i) {
                      final s = _slots[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF101B33),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: i == _focusedSlotIdx
                                ? colors.primary
                                : Colors.white10,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: s.isHost
                                    ? colors.ambientGlow
                                    : (s.isVideoActive ? const Color(0xFF10B981) : Colors.white38),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.displayName,
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    'Slot #$i · ${s.role}',
                                    style: GoogleFonts.inter(
                                      fontSize: 9.5,
                                      color: Colors.white60,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Mic Toggle
                            IconButton(
                              icon: Icon(
                                s.isAudioActive ? Icons.mic_rounded : Icons.mic_off_rounded,
                                size: 16,
                                color: s.isAudioActive ? AppColors.brandPink : Colors.white38,
                              ),
                              onPressed: () {
                                setModalState(() {
                                  _slots[i] = s.copyWith(isAudioActive: !s.isAudioActive);
                                });
                                setState(() {});
                                widget.onSlotsChanged?.call(_slots);
                              },
                              tooltip: 'Toggle Mic',
                            ),
                            // Cam Toggle
                            IconButton(
                              icon: Icon(
                                s.isVideoActive
                                    ? Icons.videocam_rounded
                                    : Icons.videocam_off_rounded,
                                size: 16,
                                color: s.isVideoActive ? colors.ambientGlow : Colors.white38,
                              ),
                              onPressed: () {
                                setModalState(() {
                                  _slots[i] = s.copyWith(isVideoActive: !s.isVideoActive);
                                });
                                setState(() {});
                                widget.onSlotsChanged?.call(_slots);
                              },
                              tooltip: 'Toggle Camera',
                            ),
                            // Spotlight button
                            InkWell(
                              onTap: () {
                                Navigator.pop(ctx);
                                HapticFeedback.mediumImpact();
                                setState(() {
                                  _focusedSlotIdx = i;
                                  _layoutMode = 2;
                                });
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                                decoration: BoxDecoration(
                                  color: colors.primary.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: colors.primary, width: 0.8),
                                ),
                                child: Text(
                                  'Spotlight',
                                  style: GoogleFonts.inter(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: colors.ambientGlow,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showViewerCoHostRequestSheet(
      BuildContext context, _AtmosphereColors colors) {
    bool cameraEnabled = true;
    bool micEnabled = true;
    bool isFrontCamera = true;
    bool hasAgreedToTerms = true;
    String selectedRole = 'Co-Host (Camera & Mic)';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Container(
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, MediaQuery.paddingOf(ctx).bottom + 20),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1020),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: colors.ambientGlow.withValues(alpha: 0.4)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white30,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: colors.ambientGlow.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.videocam_rounded, size: 22, color: colors.ambientGlow),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Request Stage Co-Host Access',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Join the amphitheater curved wall live with camera and mic',
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                color: Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Role Selection
                  Text(
                    'REQUESTED STAGE ROLE',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: colors.ambientGlow,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setModalState(() {
                              selectedRole = 'Co-Host (Camera & Mic)';
                              cameraEnabled = true;
                            });
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            decoration: BoxDecoration(
                              color: selectedRole == 'Co-Host (Camera & Mic)'
                                  ? AppColors.brandPink.withValues(alpha: 0.15)
                                  : const Color(0xFF101B33),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selectedRole == 'Co-Host (Camera & Mic)'
                                    ? AppColors.brandPink
                                    : Colors.white12,
                                width: 1.2,
                              ),
                            ),
                            child: Column(
                              children: [
                                const Icon(Icons.camera_front_rounded,
                                    size: 20, color: AppColors.brandPink),
                                const SizedBox(height: 5),
                                Text(
                                  'Co-Host (Cam+Mic)',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Full Stage Screen',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    color: Colors.white60,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setModalState(() {
                              selectedRole = 'Speaker (Audio-Only)';
                              cameraEnabled = false;
                            });
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            decoration: BoxDecoration(
                              color: selectedRole == 'Speaker (Audio-Only)'
                                  ? colors.primary.withValues(alpha: 0.15)
                                  : const Color(0xFF101B33),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selectedRole == 'Speaker (Audio-Only)'
                                    ? colors.primary
                                    : Colors.white12,
                                width: 1.2,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.mic_rounded, size: 20, color: colors.ambientGlow),
                                const SizedBox(height: 5),
                                Text(
                                  'Speaker (Audio-Only)',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Voice Channel',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    color: Colors.white60,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Camera & Mic Controls
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101B33),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.videocam_rounded, size: 18, color: Colors.white70),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Enable Stage Camera',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            if (cameraEnabled) ...[
                              InkWell(
                                onTap: () {
                                  setModalState(() => isFrontCamera = !isFrontCamera);
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white12,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.flip_camera_ios_rounded,
                                          size: 11, color: Colors.white70),
                                      const SizedBox(width: 4),
                                      Text(
                                        isFrontCamera ? 'Front' : 'Rear',
                                        style: GoogleFonts.inter(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Switch.adaptive(
                              value: cameraEnabled,
                              activeTrackColor: AppColors.brandPink,
                              activeThumbColor: Colors.white,
                              onChanged: (val) {
                                setModalState(() => cameraEnabled = val);
                              },
                            ),
                          ],
                        ),
                        const Divider(height: 14, color: Colors.white12),
                        Row(
                          children: [
                            const Icon(Icons.mic_rounded, size: 18, color: Colors.white70),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Enable Stage Microphone (HD Voice)',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            Switch.adaptive(
                              value: micEnabled,
                              activeTrackColor: AppColors.brandBlue,
                              activeThumbColor: Colors.white,
                              onChanged: (val) {
                                setModalState(() => micEnabled = val);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Agreement Checkbox
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: hasAgreedToTerms,
                        activeColor: AppColors.brandPink,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (val) {
                          setModalState(() => hasAgreedToTerms = val ?? false);
                        },
                      ),
                      Expanded(
                        child: Text(
                          'I agree to broadcast my camera and microphone in full compliance with Oneova Community Safety Standards.',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            color: Colors.white70,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Submit Button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasAgreedToTerms ? colors.ambientGlow : Colors.white24,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 42),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: hasAgreedToTerms
                        ? () {
                            Navigator.pop(ctx);
                            HapticFeedback.mediumImpact();
                            final newReq = CoHostJoinRequest(
                              id: 'req_${DateTime.now().millisecondsSinceEpoch}',
                              name: 'You (Live Viewer)',
                              handle: '@viewer_you',
                              role: selectedRole,
                              hasCamera: cameraEnabled,
                              hasMic: micEnabled,
                              requestedAgo: 'Just now',
                            );
                            setState(() {
                              _guestJoinRequests.insert(0, newReq);
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '✨ Co-Host request sent to the host! Camera & Mic ready.',
                                  style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700, color: Colors.black),
                                ),
                                backgroundColor: colors.ambientGlow,
                              ),
                            );
                          }
                        : null,
                    child: Text(
                      'Submit Stage Request',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showLiveCommentInput(BuildContext context, _AtmosphereColors colors) {
    final commentTextCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF0A1020),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: commentTextCtrl,
                    autofocus: true,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Type comment on stage...',
                      hintStyle: GoogleFonts.inter(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF141F36),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send_rounded,
                      color: Color(0xFF00F0FF)),
                  onPressed: () {
                    final text = commentTextCtrl.text.trim();
                    if (text.isNotEmpty) {
                      setState(() {
                        _latestComment = text;
                      });
                      Navigator.pop(ctx);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showStageCameraAngles(BuildContext context, _AtmosphereColors colors) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Stage Camera Angle switched to Dynamic Arena Mode',
          style: GoogleFonts.inter(),
        ),
        backgroundColor: colors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOM PAINTERS: SPOTLIGHT BEAM, SINE WAVES, & STEPPED DAIS
// ─────────────────────────────────────────────────────────────────────────────

class _AtmosphereColors {
  final Color primary;
  final Color secondary;
  final Color ambientGlow;
  final Color spotlight;
  final Color floorRim;
  final Color bgTop;
  final Color bgBottom;

  const _AtmosphereColors({
    required this.primary,
    required this.secondary,
    required this.ambientGlow,
    required this.spotlight,
    required this.floorRim,
    required this.bgTop,
    required this.bgBottom,
  });
}

class _AcousticWavePainter extends CustomPainter {
  final double phase;
  final Color primaryColor;
  final Color secondaryColor;
  final Color cyanColor;

  const _AcousticWavePainter({
    required this.phase,
    required this.primaryColor,
    required this.secondaryColor,
    required this.cyanColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final wave1 = Paint()
      ..color = cyanColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final wave2 = Paint()
      ..color = secondaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final path1 = Path();
    final path2 = Path();

    path1.moveTo(0, size.height * 0.5);
    path2.moveTo(0, size.height * 0.55);

    for (double x = 0; x <= size.width; x += 4) {
      final y1 = (size.height * 0.5) +
          math.sin((x / size.width * 4 * math.pi) + phase) * 16 +
          math.cos((x / size.width * 2 * math.pi) + phase * 0.7) * 8;
      final y2 = (size.height * 0.55) +
          math.sin((x / size.width * 3.5 * math.pi) + phase + 1.2) * 14;

      path1.lineTo(x, y1);
      path2.lineTo(x, y2);
    }

    canvas.drawPath(path1, wave1);
    canvas.drawPath(path2, wave2);
  }

  @override
  bool shouldRepaint(covariant _AcousticWavePainter oldDelegate) =>
      oldDelegate.phase != phase;
}
