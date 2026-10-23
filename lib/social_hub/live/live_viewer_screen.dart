// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/live/models/live_models.dart';
import '../../backend/live/services/live_service.dart';
import '../../shared/theme/app_theme.dart';
import 'widgets/oneova_virtual_stage_room.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VIEWER SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class LiveViewerScreen extends ConsumerStatefulWidget {
  final String streamId;
  const LiveViewerScreen({super.key, required this.streamId});

  @override
  ConsumerState<LiveViewerScreen> createState() => _LiveViewerScreenState();
}

class _LiveViewerScreenState extends ConsumerState<LiveViewerScreen>
    with TickerProviderStateMixin {
  // ── Tabs ──────────────────────────────────────────────────────────────────
  int _activeTab = 0;
  // 0=Lobby  1=Presenter's Goods  2=Interactive Map/Room  3=Participants  4=Activity & Chat

  // ── Multi-Cam Slots (7 Draggable Panoramic Cove Wall Screens) ─────────────
  List<StageScreenSlot> _slots = [
    const StageScreenSlot(id: 'slot_0', displayName: 'David K.', role: 'Guest Speaker'),
    const StageScreenSlot(id: 'slot_1', displayName: 'Stage Cam A', role: 'Angle A'),
    const StageScreenSlot(id: 'slot_2', displayName: 'Elena Vance', role: 'Co-Host'),
    const StageScreenSlot(id: 'slot_3', displayName: 'Host Stream', role: 'Host', isHost: true),
    const StageScreenSlot(id: 'slot_4', displayName: 'Marcus Tech', role: 'VIP Guest'),
    const StageScreenSlot(id: 'slot_5', displayName: 'Chloe Bloom', role: 'Special Guest'),
    const StageScreenSlot(id: 'slot_6', displayName: 'Media Deck', role: 'Video Deck'),
  ];

  // ── Guest Camera Access & Stage Feed ──────────────────────────────────────
  CameraController? _guestCameraCtrl;
  List<CameraDescription> _guestCameras = [];
  int _guestCameraIdx = 0;
  bool _isGuestCameraActive = false;
  bool _isGuestMicMuted = false;

  // ── Comment input ─────────────────────────────────────────────────────────
  final TextEditingController _commentCtrl = TextEditingController();
  final FocusNode _commentFocus = FocusNode();

  // ── Hearts animation ──────────────────────────────────────────────────────
  final List<_FloatingHeart> _hearts = [];
  Timer? _heartTimer;

  // ── Join notification ─────────────────────────────────────────────────────
  String? _joinNotification;
  Timer? _notifTimer;
  int _prevParticipantCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(liveServiceProvider).incrementViewerCount(widget.streamId);
    });
  }

  @override
  void dispose() {
    ref.read(liveServiceProvider).decrementViewerCount(widget.streamId);
    _guestCameraCtrl?.dispose();
    _commentCtrl.dispose();
    _commentFocus.dispose();
    _heartTimer?.cancel();
    _notifTimer?.cancel();
    for (final h in _hearts) {
      h.controller.dispose();
    }
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GUEST CAMERA PERMISSION & STAGE ACCESS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _startGuestCamera() async {
    try {
      _guestCameras = await availableCameras();
      if (_guestCameras.isEmpty) {
        _showSnack('No camera available on this device');
        return;
      }
      final frontIdx = _guestCameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.front);
      _guestCameraIdx = frontIdx >= 0 ? frontIdx : 0;
      final ctrl = CameraController(
        _guestCameras[_guestCameraIdx],
        ResolutionPreset.medium,
        enableAudio: !_isGuestMicMuted,
      );
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() {
        _guestCameraCtrl?.dispose();
        _guestCameraCtrl = ctrl;
        _isGuestCameraActive = true;
        _slots[1] = const StageScreenSlot(
          id: 'guest_me',
          displayName: 'You (On Stage)',
          isHost: false,
          isLocalUser: true,
          role: 'On Stage',
          isAudioActive: true,
        );
      });
      await ref.read(liveServiceProvider).requestToJoin(widget.streamId);
      _showSnack('Camera access granted! You are streaming on the live stage.');
    } catch (e) {
      debugPrint('[LiveViewer] Camera start error: $e');
      _showSnack('Camera access required to stream on stage');
    }
  }

  Future<void> _flipGuestCamera() async {
    if (_guestCameras.length < 2) return;
    HapticFeedback.lightImpact();
    _guestCameraIdx = (_guestCameraIdx + 1) % _guestCameras.length;
    final ctrl = CameraController(
      _guestCameras[_guestCameraIdx],
      ResolutionPreset.medium,
      enableAudio: !_isGuestMicMuted,
    );
    await ctrl.initialize();
    if (!mounted) {
      ctrl.dispose();
      return;
    }
    setState(() {
      _guestCameraCtrl?.dispose();
      _guestCameraCtrl = ctrl;
    });
  }

  void _leaveGuestStage() {
    HapticFeedback.mediumImpact();
    _guestCameraCtrl?.dispose();
    setState(() {
      _guestCameraCtrl = null;
      _isGuestCameraActive = false;
      _slots[1] = const StageScreenSlot(
        id: 'slot_1',
        displayName: 'Stage Cam A',
        role: 'Angle A',
      );
    });
    _showSnack('You stepped down from the live stage');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CLICK-TO-CENTER & FOCUS
  // ─────────────────────────────────────────────────────────────────────────

  void _focusParticipant(LiveParticipant participant) {
    HapticFeedback.mediumImpact();
    setState(() {
      final currentCenter = _slots[3];
      _slots[3] = StageScreenSlot(
        id: participant.userId,
        displayName: participant.displayName,
        avatarUrl: participant.avatarUrl,
        isHost: participant.isCoHost,
        role: participant.isCoHost ? 'Co-Host' : 'Guest',
      );
      _slots[2] = currentCenter;
      _activeTab = 0; // Return to stage
    });
    _showSnack('${participant.displayName} focused on center screen');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REACTIONS
  // ─────────────────────────────────────────────────────────────────────────

  void _spawnHeart() {
    HapticFeedback.lightImpact();
    ref.read(liveServiceProvider).sendLikeReaction(widget.streamId);

    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    final rng = math.Random();
    final colors = [
      AppColors.brandPink,
      AppColors.brandPink.withValues(alpha: 0.8),
      Colors.white.withValues(alpha: 0.9),
      AppColors.brandBlue.withValues(alpha: 0.7),
    ];

    final heart = _FloatingHeart(
      x: 0.82 + rng.nextDouble() * 0.14,
      size: 20 + rng.nextDouble() * 14,
      color: colors[rng.nextInt(colors.length)],
      controller: ctrl,
    );

    setState(() => _hearts.add(heart));
    ctrl.forward().then((_) {
      if (mounted) setState(() => _hearts.remove(heart));
      ctrl.dispose();
    });
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    _commentCtrl.clear();
    _commentFocus.unfocus();
    await ref.read(liveServiceProvider).sendComment(widget.streamId, text);
  }

  void _promptJoinWithCamera() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              24, 20, 24, MediaQuery.paddingOf(ctx).bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.videocam,
                        color: AppColors.brandBlue, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Join Live Multi-Cam Stage',
                            style: GoogleFonts.inter(
                                color: context.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        Text('Stream live with your camera & mic',
                            style: GoogleFonts.inter(
                                color: context.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Grant camera access to appear directly on the multi-cam stage with the host. You can flip your camera or mute your microphone anytime.',
                style: GoogleFonts.inter(
                    color: context.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: context.border),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Cancel',
                          style: GoogleFonts.inter(
                              color: context.textSecondary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _startGuestCamera();
                      },
                      icon: const Icon(Icons.videocam_outlined, size: 18),
                      label: Text('Grant Access',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13)),
        backgroundColor: context.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _checkParticipantJoin(List<LiveParticipant> participants) {
    if (participants.length > _prevParticipantCount &&
        participants.isNotEmpty) {
      final newest = participants.first;
      _notifTimer?.cancel();
      setState(() => _joinNotification = '${newest.displayName} joined the live');
      _notifTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _joinNotification = null);
      });
    }
    _prevParticipantCount = participants.length;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final streamAsync = ref.watch(liveStreamProvider(widget.streamId));
    final participantsAsync =
        ref.watch(liveParticipantsProvider(widget.streamId));

    participantsAsync.whenData((p) => _checkParticipantJoin(p));

    return Scaffold(
      backgroundColor: context.bg,
      resizeToAvoidBottomInset: true,
      body: streamAsync.when(
        data: (stream) {
          if (stream == null) {
            return const _StreamEndedView();
          }
          return _buildMain(context, stream, participantsAsync);
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.brandBlue),
        ),
        error: (e, _) => _StreamEndedView(errorMessage: e.toString()),
      ),
    );
  }

  Widget _buildMain(
    BuildContext context,
    LiveStream stream,
    AsyncValue<List<LiveParticipant>> participantsAsync,
  ) {
    final size = MediaQuery.sizeOf(context);
    final viewerStr = _formatCount(stream.viewerCount);
    final participantCount =
        participantsAsync.asData?.value.length ?? 0;

    final primaryColor = _parseColor(stream.stageConfig.primaryColorHex, AppColors.brandBlue);
    final accentColor = _parseColor(stream.stageConfig.accentColorHex, AppColors.brandPink);

    return Stack(
      children: [
        // Cinematic Deep Atmosphere Background
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.35),
                radius: 1.25,
                colors: [
                  primaryColor.withValues(alpha: 0.22),
                  const Color(0xFF040A1A),
                  context.bg,
                ],
              ),
            ),
          ),
        ),

        // Floating hearts
        ..._buildHeartWidgets(size),

        SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── TOP BAR ────────────────────────────────────────────────
              _buildTopBar(stream, viewerStr),

              // ── STAGE AREA ─────────────────────────────────────────────
              Expanded(
                flex: _activeTab == 0 ? 6 : 3,
                child: _activeTab == 0
                    ? _buildStage(stream, primaryColor, accentColor)
                    : _buildTabContent(stream, participantsAsync),
              ),

              // ── BOTTOM NAV + CHAT ──────────────────────────────────────
              _buildBottomSection(stream, participantCount, primaryColor, accentColor),
            ],
          ),
        ),

        // Join notification bubble
        if (_joinNotification != null)
          Positioned(
            left: 16,
            bottom: 280,
            child: _buildJoinNotification(_joinNotification!),
          ),

        // Show Love button (right side)
        Positioned(
          right: 12,
          bottom: 320,
          child: _buildShowLoveBtn(accentColor),
        ),

        // Floating Guest Controls (when camera is on stage)
        if (_isGuestCameraActive)
          Positioned(
            left: 16,
            bottom: 310,
            child: _buildGuestStageToolbar(),
          ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TOP BAR
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTopBar(LiveStream stream, String viewerStr) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          // Live badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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
                )
                    .animate(onPlay: (c) => c.repeat())
                    .fade(begin: 0.4, end: 1.0, duration: 600.ms),
                const SizedBox(width: 6),
                Text('Live',
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Viewer count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.remove_red_eye_outlined,
                    color: Colors.white70, size: 13),
                const SizedBox(width: 5),
                Text(viewerStr,
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Spacer(),
          // Streamer avatar + name
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.brandBlue.withValues(alpha: 0.4),
                backgroundImage: stream.hostAvatarUrl.isNotEmpty
                    ? NetworkImage(stream.hostAvatarUrl)
                    : null,
                child: stream.hostAvatarUrl.isEmpty
                    ? Text(
                        stream.hostDisplayName.isNotEmpty
                            ? stream.hostDisplayName[0].toUpperCase()
                            : '?',
                        style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700))
                    : null,
              ),
              const SizedBox(width: 6),
              Text(
                stream.hostDisplayName,
                style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(width: 10),
          // Close
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STAGE (Lobby view with interactive Click-to-Focus, Dragging, and Camera)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStage(LiveStream stream, Color primaryColor, Color accentColor) {
    final hasGuestCam = _isGuestCameraActive &&
        _guestCameraCtrl != null &&
        _guestCameraCtrl!.value.isInitialized;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: OneovaVirtualStageRoom(
        stream: stream,
        isHost: false,
        showTopHud: false,
        localCameraController: hasGuestCam ? _guestCameraCtrl : null,
        initialSlots: _slots,
        onSlotsChanged: (updatedSlots) {
          setState(() => _slots = updatedSlots);
        },
        customLowerThird: stream.mediaDeskConfig.lowerThirdText ?? stream.title,
        atmospherePresetOverride: stream.stageConfig.atmospherePreset,
        onRequestToJoin: _promptJoinWithCamera,
        onShowLove: _spawnHeart,
        onTapPresentationTable: () {
          setState(() => _activeTab = 1);
        },
        onClose: () => Navigator.of(context).maybePop(),
      ),
    );
  }



  Widget _buildGuestStageToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandBlue.withValues(alpha: 0.3),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _flipGuestCamera,
            child: const Icon(Icons.flip_camera_android,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _isGuestMicMuted = !_isGuestMicMuted);
              _showSnack(_isGuestMicMuted ? 'Mic muted' : 'Mic active');
            },
            child: Icon(
              _isGuestMicMuted ? Icons.mic_off : Icons.mic,
              color: _isGuestMicMuted ? AppColors.brandPink : Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _leaveGuestStage,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.brandPink,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Leave',
                style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }



  // ─────────────────────────────────────────────────────────────────────────
  // TAB CONTENT
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTabContent(
      LiveStream stream, AsyncValue<List<LiveParticipant>> participantsAsync) {
    switch (_activeTab) {
      case 1:
        return _buildPresenterGoods(stream);
      case 2:
        return _buildInteractiveRoom(stream);
      case 3:
        return _buildParticipantsList(participantsAsync);
      case 4:
        return _buildActivityChat();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPresenterGoods(LiveStream stream) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inventory_2_outlined,
              color: AppColors.textMuted, size: 44),
          const SizedBox(height: 12),
          Text("Presenter's Goods",
              style: GoogleFonts.inter(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Products shown by the host will appear here',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  color: AppColors.textMuted, fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _buildInteractiveRoom(LiveStream stream) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppColors.brandBlue.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.map_outlined,
                color: AppColors.brandBlue, size: 40),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(
                  begin: const Offset(0.95, 0.95),
                  end: const Offset(1.05, 1.05),
                  duration: 2000.ms),
          const SizedBox(height: 14),
          Text('Interactive Map / Room',
              style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Interactive 3D Stage & spatial audio room active',
              style: GoogleFonts.inter(
                  color: AppColors.textMuted, fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _buildParticipantsList(
      AsyncValue<List<LiveParticipant>> participantsAsync) {
    return participantsAsync.when(
      data: (participants) {
        if (participants.isEmpty) {
          return Center(
            child: Text('No participants yet',
                style: GoogleFonts.inter(
                    color: AppColors.textMuted, fontSize: 13)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: participants.length,
          separatorBuilder: (context, index) => Divider(
              height: 1, color: Colors.white.withValues(alpha: 0.07)),
          itemBuilder: (ctx, i) {
            final p = participants[i];
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              onTap: () => _focusParticipant(p),
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.brandBlue.withValues(alpha: 0.3),
                backgroundImage: p.avatarUrl.isNotEmpty
                    ? NetworkImage(p.avatarUrl)
                    : null,
                child: p.avatarUrl.isEmpty
                    ? Text(
                        p.displayName.isNotEmpty
                            ? p.displayName[0].toUpperCase()
                            : '?',
                        style: GoogleFonts.inter(
                            color: Colors.white, fontSize: 12))
                    : null,
              ),
              title: Text(p.displayName,
                  style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              subtitle: Text(
                p.isCoHost ? 'Co-host · Tap to put on big screen' : 'Tap to focus on center',
                style: GoogleFonts.inter(
                  color: p.isCoHost ? AppColors.brandBlue : AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
              trailing: const Icon(Icons.fullscreen, color: Colors.white54, size: 20),
            );
          },
        );
      },
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.brandBlue)),
      error: (e, _) => Center(
          child: Text('Error loading participants',
              style: GoogleFonts.inter(
                  color: AppColors.textMuted, fontSize: 13))),
    );
  }

  Widget _buildActivityChat() {
    final commentsAsync = ref.watch(liveCommentsProvider(widget.streamId));
    return commentsAsync.when(
      data: (comments) {
        if (comments.isEmpty) {
          return Center(
            child: Text('No comments yet. Be the first!',
                style: GoogleFonts.inter(
                    color: AppColors.textMuted, fontSize: 13)),
          );
        }
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.all(16),
          itemCount: comments.length,
          itemBuilder: (ctx, i) {
            final c = comments[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.brandBlue.withValues(alpha: 0.3),
                    backgroundImage: c.authorAvatarUrl.isNotEmpty
                        ? NetworkImage(c.authorAvatarUrl)
                        : null,
                    child: c.authorAvatarUrl.isEmpty
                        ? Text(
                            c.authorDisplayName.isNotEmpty
                                ? c.authorDisplayName[0].toUpperCase()
                                : '?',
                            style: GoogleFonts.inter(
                                color: Colors.white, fontSize: 10))
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.authorDisplayName,
                            style: GoogleFonts.inter(
                                color: c.isModerator
                                    ? AppColors.brandBlue
                                    : AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(c.text,
                            style: GoogleFonts.inter(
                                color: c.isGift
                                    ? AppColors.brandPink
                                    : Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w400)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.brandBlue)),
      error: (err, stack) => const SizedBox.shrink(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BOTTOM SECTION
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBottomSection(LiveStream stream, int participantCount,
      Color primaryColor, Color accentColor) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
            top: BorderSide(color: context.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 32,
            height: 3,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 5-Tab navigation
          SizedBox(
            height: 64,
            child: Row(
              children: [
                _buildViewerTab(0, Icons.home_outlined, 'Lobby', primaryColor),
                _buildViewerTab(
                  1,
                  Icons.monitor_outlined,
                  "Goods",
                  primaryColor,
                  badge: true,
                ),
                _buildViewerTab(
                  2,
                  Icons.map_outlined,
                  'Map / Room',
                  primaryColor,
                  active: true,
                ),
                _buildViewerTab(
                  3,
                  Icons.people_outline,
                  'Participants',
                  primaryColor,
                  count: participantCount,
                ),
                _buildViewerTab(
                  4,
                  Icons.chat_bubble_outline,
                  'Activity',
                  primaryColor,
                  badge: true,
                ),
              ],
            ),
          ),

          // Comment input
          Padding(
            padding: EdgeInsets.fromLTRB(
                12, 6, 12, MediaQuery.paddingOf(context).bottom + 12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.surfaceMid,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: context.border),
                    ),
                    child: TextField(
                      controller: _commentCtrl,
                      focusNode: _commentFocus,
                      style: GoogleFonts.inter(
                          color: context.textPrimary, fontSize: 13),
                      onSubmitted: (_) => _sendComment(),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        hintText: 'Type a comment...',
                        hintStyle: GoogleFonts.inter(
                            color: AppColors.textMuted, fontSize: 12.5),
                        border: InputBorder.none,
                        prefixIcon: const Icon(Icons.chat_bubble_outline,
                            color: AppColors.textMuted, size: 16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendComment,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 5),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text('LIVE',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            )),
                        const SizedBox(width: 4),
                        const Icon(Icons.chat_bubble,
                            color: Colors.white, size: 14),
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

  Widget _buildViewerTab(
    int index,
    IconData icon,
    String label,
    Color primaryColor, {
    bool badge = false,
    bool active = false,
    int count = 0,
  }) {
    final isActive = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _activeTab = index);
        },
        child: AnimatedContainer(
          duration: 160.ms,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isActive
                ? primaryColor.withValues(alpha: 0.15)
                : Colors.transparent,
          ),
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    color: isActive ? primaryColor : AppColors.textMuted,
                    size: 22,
                  ),
                  if (badge || count > 0)
                    Positioned(
                      right: -5,
                      top: -4,
                      child: Container(
                        width: count > 0 ? null : 8,
                        height: 8,
                        padding: count > 0
                            ? const EdgeInsets.symmetric(horizontal: 4)
                            : EdgeInsets.zero,
                        decoration: BoxDecoration(
                          color: AppColors.brandPink,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: count > 0
                            ? Text(
                                count > 99 ? '99+' : '$count',
                                style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 7,
                                    fontWeight: FontWeight.w800),
                              )
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: isActive ? primaryColor : AppColors.textMuted,
                  fontSize: 9,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FLOATING HEARTS
  // ─────────────────────────────────────────────────────────────────────────

  List<Widget> _buildHeartWidgets(Size size) {
    return _hearts.map((h) {
      return AnimatedBuilder(
        animation: h.controller,
        builder: (ctx, _) {
          final t = h.controller.value;
          final y = 0.7 - (t * 0.45);
          final wobble = math.sin(t * math.pi * 4) * 12;
          return Positioned(
            left: size.width * h.x + wobble,
            top: size.height * y,
            child: Opacity(
              opacity: (1.0 - t * 1.2).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.7 + t * 0.5,
                child: Icon(Icons.favorite, color: h.color, size: h.size),
              ),
            ),
          );
        },
      );
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHOW LOVE BUTTON
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildShowLoveBtn(Color accentColor) {
    return GestureDetector(
      onTap: _spawnHeart,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accentColor, const Color(0xFF8B00FF)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.5),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.favorite, color: Colors.white, size: 24),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(
                  begin: const Offset(0.92, 0.92),
                  end: const Offset(1.08, 1.08),
                  duration: 1200.ms),
          const SizedBox(height: 5),
          Text('SHOW\nLOVE',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: accentColor,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              )),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // JOIN NOTIFICATION
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildJoinNotification(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(
              radius: 12, backgroundColor: AppColors.brandBlue),
          const SizedBox(width: 8),
          Text(msg,
              style: GoogleFonts.inter(
                  color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideX(begin: -0.3, end: 0, duration: 300.ms);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UTILS
  // ─────────────────────────────────────────────────────────────────────────

  Color _parseColor(String hex, Color fallback) {
    try {
      final clean = hex.replaceAll('#', '');
      if (clean.length == 6) {
        return Color(int.parse('0xFF$clean'));
      }
    } catch (_) {}
    return fallback;
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STREAM ENDED VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _StreamEndedView extends StatelessWidget {
  final String? errorMessage;
  const _StreamEndedView({this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.border),
              ),
              child: Icon(Icons.live_tv_outlined,
                  color: context.textMuted, size: 38),
            ),
            const SizedBox(height: 20),
            Text(
              'Stream Ended',
              style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage ??
                  'This live stream has ended. Thank you for watching!',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text('Go Back',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FLOATING HEART DATA
// ─────────────────────────────────────────────────────────────────────────────

class _FloatingHeart {
  final double x;
  final double size;
  final Color color;
  final AnimationController controller;

  _FloatingHeart({
    required this.x,
    required this.size,
    required this.color,
    required this.controller,
  });
}
