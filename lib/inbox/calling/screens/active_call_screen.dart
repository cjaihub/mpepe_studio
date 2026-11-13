import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/calling/models/call_participant.dart';
import '../../../backend/calling/providers/active_call_controller.dart';
import '../../../backend/calling/providers/call_media_service.dart';
import '../../../backend/calling/providers/call_room_controller.dart';
import '../../../backend/calling/providers/call_signaling_service.dart';
import '../../../backend/calling/providers/webrtc_connection_manager.dart';
import '../../../backend/calling/services/call_pip_service.dart';
import '../../../backend/calling/services/call_share_service.dart';
import '../../../shared/theme/app_theme.dart';
import '../widgets/call_invite_sheet.dart';
import '../widgets/call_panel_sheet.dart';
import '../widgets/call_share_sheet.dart';
import '../widgets/call_widgets.dart';

/// Full-screen call UI at `/call/active`: outgoing ringing, incoming
/// accept/decline, the in-call view (1:1 or group grid) and the end state.
///
/// Back / swipe-down minimises the call into the floating window; only the
/// end button hangs up.
class ActiveCallScreen extends ConsumerStatefulWidget {
  final String callId;
  final String? otherUserId;
  final String? otherUserName;
  final String? otherUserAvatar;
  final bool isVideo;
  final bool isCaller;

  /// True while this screen is on top, so the global overlay knows not to
  /// show the minimised window or push a second copy.
  static final ValueNotifier<bool> isVisible = ValueNotifier(false);

  const ActiveCallScreen({
    super.key,
    required this.callId,
    this.otherUserId,
    this.otherUserName,
    this.otherUserAvatar,
    this.isVideo = true,
    this.isCaller = true,
  });

  // Backwards compatibility alias
  String get roomId => callId;

  @override
  ConsumerState<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends ConsumerState<ActiveCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _localReady = false;
  String? _boundLocalStreamId;
  String? _boundLocalVideoTrackId;
  int _boundLocalRev = -1;
  bool _controlsVisible = true;
  bool _swapped = false;
  bool _closing = false;
  Offset? _pipOffset;
  Timer? _hideControls;
  final Set<String> _seenShared = {};
  bool _sharedPrimed = false;
  CallSoundEvent? _soundToast;
  Timer? _soundToastTimer;
  ActiveCallController? _callController;

  @override
  void initState() {
    super.initState();
    ActiveCallScreen.isVisible.value = true;
    _localRenderer.initialize().then((_) {
      if (!mounted) return;
      setState(() => _localReady = true);
      _bindLocal(ref.read(callMediaServiceProvider));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumeIfNeeded());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _callController = ref.read(activeCallControllerProvider.notifier);
  }

  /// Opened from a notification/deep link with only a call id.
  Future<void> _resumeIfNeeded() async {
    if (!mounted || !context.mounted) return;
    final controller = ref.read(activeCallControllerProvider.notifier);
    final s = ref.read(activeCallControllerProvider);
    if (s.isLive) {
      controller.restore();
      return;
    }
    if (widget.callId.isEmpty) {
      _close();
      return;
    }
    final signaling = ref.read(callSignalingServiceProvider);
    final call = await signaling.getCall(widget.callId);
    final mine = call == null ? null : await signaling.myStatus(call.id);
    if (!mounted) return;
    if (call != null && !call.isFinished && mine == ParticipantStatus.ringing) {
      await controller.presentIncoming(call);
    } else {
      _close();
    }
  }

  Future<void> _bindLocal(CallMediaState media) async {
    if (!_localReady) return;
    final stream = media.localStream;
    final videoTrack = stream?.getVideoTracks().firstOrNull;
    final nextStreamId = stream?.id;
    final nextTrackId = videoTrack?.id;
    if (_boundLocalStreamId == nextStreamId &&
        _boundLocalVideoTrackId == nextTrackId &&
        _boundLocalRev == media.streamRevision) {
      return;
    }
    _boundLocalStreamId = nextStreamId;
    _boundLocalVideoTrackId = nextTrackId;
    _boundLocalRev = media.streamRevision;
    try {
      if (stream != null && videoTrack != null) {
        await _localRenderer.setSrcObject(stream: stream, trackId: videoTrack.id);
      } else {
        _localRenderer.srcObject = stream;
      }
    } catch (_) {
      try {
        _localRenderer.srcObject = stream;
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hideControls?.cancel();
    _hideControls = Timer(const Duration(seconds: 5), () {
      if (!mounted || !context.mounted) return;
      final s = ref.read(activeCallControllerProvider);
      final video = ref.read(callMediaServiceProvider).isVideoOn;
      if (mounted && s.phase == CallPhase.connected && video) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/hub/messages');
    }
  }

  void _minimize() {
    HapticFeedback.lightImpact();
    (_callController ?? (mounted ? ref.read(activeCallControllerProvider.notifier) : null))?.minimize();
    _close();
  }

  @override
  void dispose() {
    ActiveCallScreen.isVisible.value = false;
    _hideControls?.cancel();
    _soundToastTimer?.cancel();
    try {
      _localRenderer.srcObject = null;
    } catch (_) {}
    try {
      _localRenderer.dispose();
    } catch (_) {}
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message, style: GoogleFonts.inter(fontSize: 12.5)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.brandBlue,
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(activeCallControllerProvider);
    final media = ref.watch(callMediaServiceProvider);
    final mesh = ref.watch(webrtcConnectionManagerProvider);
    final room = ref.watch(callRoomControllerProvider);
    final controller = ref.read(activeCallControllerProvider.notifier);

    ref.listen<CallMediaState>(callMediaServiceProvider, (_, m) => _bindLocal(m));
    ref.listen<CallSoundEvent?>(callRoomControllerProvider.select((r) => r.lastSound), (prev, next) {
      if (next == null || next.id == prev?.id) return;
      HapticFeedback.lightImpact();
      _soundToastTimer?.cancel();
      setState(() => _soundToast = next);
      _soundToastTimer = Timer(const Duration(milliseconds: 2200), () {
        if (mounted) setState(() => _soundToast = null);
      });
    });
    ref.listen<ActiveCallState>(activeCallControllerProvider, (prev, next) {
      if (next.errorMessage != null && next.errorMessage != prev?.errorMessage) {
        _showError(next.errorMessage!);
        controller.clearError();
      }
      // The controller holds the end state (summary, "Call again") and then
      // goes idle, which closes this screen.
      if (next.phase == CallPhase.idle && prev?.phase != CallPhase.idle) _close();
      if (next.phase == CallPhase.connected && prev?.phase != CallPhase.connected) _scheduleHide();
    });

    final callId = s.call?.id;
    if (callId != null && s.isBusy) {
      ref.listen<AsyncValue<List<CallSharedItem>>>(callSharedItemsProvider(callId), (_, next) {
        final list = next.value;
        if (list == null) return;
        final me = FirebaseAuth.instance.currentUser?.uid;
        final fresh = list.where((i) => !_seenShared.contains(i.id)).toList();
        _seenShared.addAll(list.map((i) => i.id));
        if (!_sharedPrimed) {
          _sharedPrimed = true;
          return;
        }
        for (final item in fresh.where((i) => i.senderId != me).take(1)) {
          _announceShared(item);
        }
      });
    }

    final head = callHeadline(
      s,
      fallbackName: widget.isCaller ? widget.otherUserName : null,
      fallbackAvatar: widget.isCaller ? widget.otherUserAvatar : null,
    );
    final joinedRemotes = s.remoteParticipants.where((p) => p.status == ParticipantStatus.joined).toList();
    final anyRemoteVideo = joinedRemotes.any(
          (p) => !p.isVideoMuted && (mesh.peers[p.userId]?.hasRemoteVideo ?? true),
        ) ||
        mesh.peers.values.any((p) => p.hasRemoteVideo);
    final showVideoStage = (s.phase == CallPhase.outgoing ||
            s.phase == CallPhase.connecting ||
            s.phase == CallPhase.connected ||
            s.phase == CallPhase.reconnecting) &&
        (media.isVideoOn || anyRemoteVideo);
    final isGroup = s.call?.isGroup ?? false;
    final hasRemoteInStage = joinedRemotes.isNotEmpty || mesh.peers.isNotEmpty;
    final showPipSelf = showVideoStage &&
        !isGroup &&
        hasRemoteInStage &&
        room.layout != CallLayout.split &&
        !(room.hideSelfView && !_swapped);
    // Android system PiP (auto-entered by the controller for video calls).
    final tiny = CallPipService.inPip.value || MediaQuery.sizeOf(context).width < 320;

    if (tiny) return _pipView(s, mesh, head);
    final isLive = s.isLive;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && isLive) _callController?.minimize();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: showVideoStage || context.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: showVideoStage ? AppColors.brandBlack : context.bg,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (!showVideoStage) return;
              setState(() => _controlsVisible = !_controlsVisible);
              if (_controlsVisible) _scheduleHide();
            },
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 600 && s.phase != CallPhase.incoming) _minimize();
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: showVideoStage
                      ? (isGroup
                          ? (room.layout == CallLayout.spotlight
                              ? _spotlight(s, mesh, media, room)
                              : _groupGrid(s, mesh, media, room))
                          : _oneToOneStage(s, mesh, media, head, room))
                      : _audioStage(s, media, head),
                ),
                if (showPipSelf) _localPreview(media, mesh, s, room),
                _topBar(s, media, room, head, onDark: showVideoStage),
                if (room.music != null && s.isBusy) _musicPill(room.music!, onDark: showVideoStage),
                if (media.isScreenSharingActive) _screenSharePill(media, onDark: showVideoStage),
                if (_soundToast != null) _soundToastView(_soundToast!),
                if (s.phase == CallPhase.connected && mesh.worstQuality == CallQuality.poor)
                  _weakLinkBanner(media),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedSlide(
                    offset: _controlsVisible || !showVideoStage ? Offset.zero : const Offset(0, 1.2),
                    duration: 220.ms,
                    curve: Curves.easeOutCubic,
                    child: s.phase == CallPhase.incoming
                        ? _incomingControls(s)
                        : s.canRedial
                            ? _redialControls(s)
                            : _inCallControls(s, media, onDark: showVideoStage),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _announceShared(CallSharedItem item) {
    HapticFeedback.mediumImpact();
    final what = item.kind == CallShareKind.image
        ? 'a photo'
        : item.kind == CallShareKind.video
            ? 'a video'
            : 'a file';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${item.senderName.isEmpty ? 'They' : item.senderName} shared $what',
            style: GoogleFonts.inter(fontSize: 12.5)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.brandBlue,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Open',
          textColor: AppColors.brandWhite,
          onPressed: () => openCallSharedItem(context, item),
        ),
      ));
  }

  /// "Now playing" pill for the shared music; opens the music panel.
  Widget _musicPill(CallMusic music, {required bool onDark}) {
    return Positioned(
      left: 0,
      right: 0,
      top: MediaQuery.paddingOf(context).top + 92,
      child: Center(
        child: GestureDetector(
          onTap: () => showCallPanel(context, initial: CallPanelTab.music),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 260),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: onDark ? AppColors.brandBlack.withValues(alpha: 0.55) : context.surface,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.5), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(music.playing ? Icons.graphic_eq_rounded : Icons.pause_rounded,
                    size: 14, color: AppColors.brandPink),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    music.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: onDark ? AppColors.brandWhite : context.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ).animate().fadeIn(duration: 200.ms),
    );
  }

  /// Live banner shown when screen sharing is active while camera is maintained ("stay camera").
  Widget _screenSharePill(CallMediaState media, {required bool onDark}) {
    final controller = ref.read(activeCallControllerProvider.notifier);
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 54,
      left: 16,
      right: 16,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.brandBlack.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.7), width: 1.2),
            boxShadow: AppShadows.md,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.brandPink,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Sharing screen · Camera active',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandWhite,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: controller.toggleScreenShare,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.brandPink,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    'Stop',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandWhite,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.2, end: 0),
    );
  }

  /// Who just played which sound, floating above the controls.
  Widget _soundToastView(CallSoundEvent e) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    final who = e.senderId == me ? 'You' : (e.senderName.isEmpty ? 'Someone' : e.senderName.split(' ').first);
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.paddingOf(context).bottom + 150,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.brandBlue,
            borderRadius: BorderRadius.circular(AppRadius.full),
            boxShadow: AppShadows.md,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(e.sound.icon, size: 18, color: AppColors.brandWhite),
              const SizedBox(width: 8),
              Text(
                '$who · ${e.sound.label}',
                style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brandWhite),
              ),
            ],
          ),
        ),
      ).animate(key: ValueKey(e.id)).fadeIn(duration: 160.ms).scale(begin: const Offset(0.8, 0.8)),
    );
  }

  /// Shown while the link is poor; on video, offers to drop the camera.
  Widget _weakLinkBanner(CallMediaState media) {
    final controller = ref.read(activeCallControllerProvider.notifier);
    return Positioned(
      left: 0,
      right: 0,
      top: MediaQuery.paddingOf(context).top + 58,
      child: Center(
        child: GestureDetector(
          onTap: media.isVideoOn ? controller.toggleCamera : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.brandBlack.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.6), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.network_check_rounded, size: 14, color: AppColors.brandPink),
                const SizedBox(width: 6),
                Text(
                  media.isVideoOn ? 'Weak connection · tap to turn off video' : 'Weak connection',
                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.brandWhite),
                ),
              ],
            ),
          ),
        ),
      ).animate().fadeIn(duration: 200.ms),
    );
  }

  /// End of an unanswered outgoing call: close, or ring them again.
  Widget _redialControls(ActiveCallState s) {
    final controller = ref.read(activeCallControllerProvider.notifier);
    final isVideo = s.call?.isVideo ?? false;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(56, 0, 56, 36),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CallControlButton(
              icon: Icons.close_rounded,
              label: 'Close',
              size: 60,
              onTap: _close,
            ),
            CallControlButton(
              icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
              label: 'Call again',
              size: 60,
              fill: AppColors.brandBlue,
              onTap: () async {
                try {
                  await controller.redial();
                } catch (e) {
                  if (mounted) _showError(e is StateError ? e.message : 'Could not start the call.');
                }
              },
            ),
          ],
        ),
      ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.2, end: 0),
    );
  }

  // ───────────────────────── Stages ─────────────────────────

  Widget _audioStage(ActiveCallState s, CallMediaState media, ({String name, String? avatar}) head) {
    final ringing = s.phase == CallPhase.outgoing || s.phase == CallPhase.incoming;
    final isGroup = s.call?.isGroup ?? false;
    final controller = ref.read(activeCallControllerProvider.notifier);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.brandBlue.withValues(alpha: context.isDark ? 0.22 : 0.08), context.bg],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 96),
            if (isGroup && s.phase != CallPhase.incoming && s.remoteParticipants.isNotEmpty)
              _groupAvatars(s)
            else
              RingingAvatar(url: head.avatar, name: head.name, pulsing: ringing),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                head.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: context.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            _statusLine(s, color: context.textSecondary),
            const SizedBox(height: 10),
            CallEncryptedChip(frameEncrypted: ref.watch(webrtcConnectionManagerProvider).allFrameEncrypted),
            if (s.isBusy) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: controller.toggleVoiceEnhance,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: media.isVoiceEnhanced
                        ? AppColors.brandBlue.withValues(alpha: context.isDark ? 0.24 : 0.1)
                        : context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                      color: media.isVoiceEnhanced
                          ? AppColors.brandBlue.withValues(alpha: 0.55)
                          : context.border,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.graphic_eq_rounded,
                        size: 13,
                        color: media.isVoiceEnhanced ? AppColors.brandBlue : context.textMuted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        media.isVoiceEnhanced ? 'HD Voice Clean · On' : 'Voice Clean · Off',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: media.isVoiceEnhanced ? AppColors.brandBlue : context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.04, end: 0),
      ),
    );
  }

  Widget _groupAvatars(ActiveCallState s) {
    final people = s.remoteParticipants
        .where((p) => p.status == ParticipantStatus.joined || p.status == ParticipantStatus.ringing)
        .take(4)
        .toList();
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      alignment: WrapAlignment.center,
      children: [
        for (final p in people)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: p.status == ParticipantStatus.joined ? 1 : 0.5,
                child: CallAvatar(url: p.avatar, name: p.name, size: 64),
              ),
              const SizedBox(height: 6),
              Text(
                p.status == ParticipantStatus.joined ? p.name.split(' ').first : 'Ringing…',
                style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
              ),
            ],
          ),
      ],
    );
  }

  Widget _statusLine(ActiveCallState s, {required Color color}) {
    final style = GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: color);
    if (s.phase == CallPhase.connected && s.connectedAt != null) {
      return CallTimerText(since: s.connectedAt!, style: style);
    }
    final label = callStatusLabel(s);
    final text = Text(label, style: style);
    if (s.phase == CallPhase.reconnecting) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.brandPink),
          ),
          const SizedBox(width: 8),
          text,
        ],
      );
    }
    return text;
  }

  bool _isRemoteVideoActive(CallParticipant? remote, PeerState? peer) {
    if (peer == null) return false;
    if (remote != null && remote.isVideoMuted) return false;
    return peer.hasRemoteVideo || peer.renderer.srcObject != null;
  }

  Widget _videoOrAvatar({
    required RTCVideoRenderer? renderer,
    required bool videoOn,
    required String name,
    String? avatar,
    bool mirror = false,
  }) {
    if (renderer != null && videoOn && (renderer.renderVideo || renderer.srcObject != null)) {
      return RTCVideoView(
        renderer,
        mirror: mirror,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    return Container(
      color: AppColors.darkSurface,
      alignment: Alignment.center,
      child: CallAvatar(url: avatar, name: name, size: 72),
    );
  }

  PeerState? _primaryPeer(ActiveCallState s, WebRTCMeshState mesh, CallParticipant? joinedRemote) {
    if (joinedRemote != null && mesh.peers.containsKey(joinedRemote.userId)) {
      return mesh.peers[joinedRemote.userId];
    }
    return mesh.peers.values.firstOrNull;
  }

  Widget _oneToOneStage(
    ActiveCallState s,
    WebRTCMeshState mesh,
    CallMediaState media,
    ({String name, String? avatar}) head,
    CallRoomState room,
  ) {
    final remote = s.remoteParticipants.where((p) => p.status == ParticipantStatus.joined).firstOrNull;
    final peer = _primaryPeer(s, mesh, remote);
    final remoteVideoOn = _isRemoteVideoActive(remote, peer);
    final localMirror = media.isFrontCamera && room.mirrorSelfView;

    // Outgoing / connecting before the other person joins: show our live camera
    // right away with a sleek floating recipient badge instead of a dark void.
    if (remote == null && peer == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _videoOrAvatar(
            renderer: _localReady ? _localRenderer : null,
            videoOn: media.isVideoOn,
            name: 'You',
            mirror: localMirror,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.brandBlack.withValues(alpha: 0.45),
                  Colors.transparent,
                  AppColors.brandBlack.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: const Alignment(0, -0.45),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RingingAvatar(
                    url: head.avatar,
                    name: head.name,
                    pulsing: s.phase == CallPhase.outgoing,
                    size: 76,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    head.name,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandWhite,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _statusLine(s, color: AppColors.brandWhite.withValues(alpha: 0.85)),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // 50/50 Dual Split-Screen Camera Exchange: both cameras visible full-width
    // in real time so both users see each other and their own camera together.
    if (room.layout == CallLayout.split) {
      final remotePane = _splitPane(
        renderer: peer?.renderer,
        videoOn: remoteVideoOn,
        name: remote?.name.isNotEmpty == true ? remote!.name : head.name,
        avatar: remote?.avatar ?? head.avatar,
        muted: remote?.isAudioMuted ?? false,
        isSelf: false,
      );
      final localPane = _splitPane(
        renderer: _localReady ? _localRenderer : null,
        videoOn: media.isVideoOn,
        name: 'You',
        muted: media.isAudioMuted,
        mirror: localMirror,
        isSelf: true,
        canFlip: media.isVideoOn,
      );
      final top = _swapped ? localPane : remotePane;
      final bottom = _swapped ? remotePane : localPane;
      return Column(
        children: [
          Expanded(child: top),
          Container(height: 1, color: AppColors.brandWhite.withValues(alpha: 0.16)),
          Expanded(child: bottom),
        ],
      );
    }

    final remoteView = _videoOrAvatar(
      renderer: peer?.renderer,
      videoOn: remoteVideoOn,
      name: head.name,
      avatar: head.avatar,
    );
    final localView = _videoOrAvatar(
      renderer: _localReady ? _localRenderer : null,
      videoOn: media.isVideoOn,
      name: 'You',
      mirror: localMirror,
    );
    return _swapped ? localView : remoteView;
  }

  Widget _splitPane({
    required RTCVideoRenderer? renderer,
    required bool videoOn,
    required String name,
    String? avatar,
    bool muted = false,
    bool mirror = false,
    bool isSelf = false,
    bool canFlip = false,
  }) {
    final controller = ref.read(activeCallControllerProvider.notifier);
    return Stack(
      fit: StackFit.expand,
      children: [
        _videoOrAvatar(renderer: renderer, videoOn: videoOn, name: name, avatar: avatar, mirror: mirror),
        Positioned(
          left: 12,
          bottom: isSelf ? MediaQuery.paddingOf(context).bottom + 92 : 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.brandBlack.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: AppColors.brandWhite.withValues(alpha: 0.14), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (muted) ...[
                  const Icon(Icons.mic_off_rounded, size: 12, color: AppColors.brandPink),
                  const SizedBox(width: 4),
                ],
                Text(
                  isSelf ? 'You' : name.split(' ').first,
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brandWhite),
                ),
              ],
            ),
          ),
        ),
        if (isSelf)
          Positioned(
            right: 12,
            bottom: MediaQuery.paddingOf(context).bottom + 90,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _cameraMiniAction(
                  icon: Icons.swap_vert_rounded,
                  tooltip: 'Swap top and bottom cameras',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _swapped = !_swapped);
                  },
                ),
                if (canFlip) ...[
                  const SizedBox(width: 6),
                  _cameraMiniAction(
                    icon: Icons.flip_camera_ios_rounded,
                    tooltip: 'Switch front/rear camera',
                    onTap: controller.switchCamera,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _cameraMiniAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.brandBlack.withValues(alpha: 0.56),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.brandWhite.withValues(alpha: 0.2), width: 1),
          ),
          child: Icon(icon, size: 15, color: AppColors.brandWhite),
        ),
      ),
    );
  }

  Widget _localPreview(CallMediaState media, WebRTCMeshState mesh, ActiveCallState s, CallRoomState room) {
    final size = MediaQuery.sizeOf(context);
    const w = 108.0, h = 154.0;
    final offset = _pipOffset ?? Offset(size.width - w - 14, MediaQuery.paddingOf(context).top + 64);
    final remote = s.remoteParticipants.where((p) => p.status == ParticipantStatus.joined).firstOrNull;
    final peer = _primaryPeer(s, mesh, remote);
    final remoteVideoOn = _isRemoteVideoActive(remote, peer);
    final controller = ref.read(activeCallControllerProvider.notifier);
    final child = _swapped
        ? _videoOrAvatar(
            renderer: peer?.renderer,
            videoOn: remoteVideoOn,
            name: remote?.name ?? '',
            avatar: remote?.avatar,
          )
        : _videoOrAvatar(
            renderer: _localReady ? _localRenderer : null,
            videoOn: media.isVideoOn,
            name: 'You',
            mirror: media.isFrontCamera && room.mirrorSelfView,
          );
    return Positioned(
      left: offset.dx.clamp(8.0, size.width - w - 8),
      top: offset.dy.clamp(MediaQuery.paddingOf(context).top + 8, size.height - h - 180),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _swapped = !_swapped);
        },
        onPanUpdate: (d) => setState(() => _pipOffset = offset + d.delta),
        child: Container(
          width: w,
          height: h,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.brandWhite.withValues(alpha: 0.25), width: 1),
            boxShadow: AppShadows.md,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppColors.brandBlack.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.swap_horiz_rounded, size: 13, color: AppColors.brandWhite),
                ),
              ),
              if (!_swapped && media.isVideoOn)
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: controller.switchCamera,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppColors.brandBlue.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.flip_camera_ios_rounded, size: 13, color: AppColors.brandWhite),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ).animate().fadeIn(duration: 250.ms).scale(begin: const Offset(0.92, 0.92)),
    );
  }

  Widget _selfTile(CallMediaState media, CallRoomState room) => _tile(
        name: 'You',
        renderer: _localReady ? _localRenderer : null,
        videoOn: media.isVideoOn,
        muted: media.isAudioMuted,
        mirror: media.isFrontCamera && room.mirrorSelfView,
      );

  Widget _remoteTile(CallParticipant p, WebRTCMeshState mesh) {
    final peer = mesh.peers[p.userId];
    return _tile(
      name: p.name,
      avatar: p.avatar,
      renderer: peer?.renderer,
      videoOn: p.status == ParticipantStatus.joined && _isRemoteVideoActive(p, peer),
      muted: p.isAudioMuted,
      ringing: p.status == ParticipantStatus.ringing,
      link: peer?.link,
    );
  }

  /// Group call, one big tile (the pinned person, else the first one in)
  /// with everyone else in a strip.
  Widget _spotlight(ActiveCallState s, WebRTCMeshState mesh, CallMediaState media, CallRoomState room) {
    final others = s.remoteParticipants
        .where((p) => p.status == ParticipantStatus.joined || p.status == ParticipantStatus.ringing)
        .toList();
    final joined = others.where((p) => p.status == ParticipantStatus.joined).toList();
    final main = joined.where((p) => p.userId == room.pinnedUid).firstOrNull ?? joined.firstOrNull;
    final strip = <Widget>[
      if (!room.hideSelfView) _selfTile(media, room),
      for (final p in others.where((p) => p.userId != main?.userId))
        GestureDetector(
          onTap: () => ref.read(callRoomControllerProvider.notifier).pin(p.userId),
          child: _remoteTile(p, mesh),
        ),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 56, 6, 120),
        child: Column(
          children: [
            Expanded(child: main == null ? _selfTile(media, room) : _remoteTile(main, mesh)),
            if (strip.isNotEmpty) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: 128,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: strip.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => SizedBox(width: 96, child: strip[i]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _groupGrid(ActiveCallState s, WebRTCMeshState mesh, CallMediaState media, CallRoomState room) {
    final tiles = <Widget>[
      if (!room.hideSelfView) _selfTile(media, room),
      for (final p in s.remoteParticipants.where(
        (p) => p.status == ParticipantStatus.joined || p.status == ParticipantStatus.ringing,
      ))
        _remoteTile(p, mesh),
    ];
    final cols = tiles.length <= 2 ? 1 : 2;
    final rows = (tiles.length / cols).ceil();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 56, 6, 120),
        child: LayoutBuilder(builder: (context, c) {
          final tileW = (c.maxWidth - (cols - 1) * 6) / cols;
          final tileH = (c.maxHeight - (rows - 1) * 6) / rows;
          return Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in tiles) SizedBox(width: tileW, height: tileH, child: t),
            ],
          );
        }),
      ),
    );
  }

  Widget _tile({
    required String name,
    String? avatar,
    RTCVideoRenderer? renderer,
    required bool videoOn,
    bool muted = false,
    bool mirror = false,
    bool ringing = false,
    PeerLinkState? link,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _videoOrAvatar(renderer: renderer, videoOn: videoOn, name: name, avatar: avatar, mirror: mirror),
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.brandBlack.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (muted) ...[
                    const Icon(Icons.mic_off_rounded, size: 12, color: AppColors.brandPink),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    ringing
                        ? '${name.split(' ').first} · ringing'
                        : link == PeerLinkState.reconnecting
                            ? '${name.split(' ').first} · reconnecting'
                            : name.split(' ').first,
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brandWhite),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }

  Widget _pipView(ActiveCallState s, WebRTCMeshState mesh, ({String name, String? avatar}) head) {
    final remote = s.remoteParticipants.where((p) => p.status == ParticipantStatus.joined).firstOrNull;
    final peer = _primaryPeer(s, mesh, remote);
    return ColoredBox(
      color: AppColors.brandBlack,
      child: _videoOrAvatar(
        renderer: peer?.renderer,
        videoOn: _isRemoteVideoActive(remote, peer),
        name: head.name,
        avatar: head.avatar,
      ),
    );
  }

  // ───────────────────────── Chrome ─────────────────────────

  Widget _topBar(
    ActiveCallState s,
    CallMediaState media,
    CallRoomState room,
    ({String name, String? avatar}) head, {
    required bool onDark,
  }) {
    final fg = onDark ? AppColors.brandWhite : context.textPrimary;
    final controller = ref.read(activeCallControllerProvider.notifier);
    final canInvite = s.isBusy && s.phase != CallPhase.outgoing && s.call != null;
    final isOneToOneVideo = onDark &&
        !(s.call?.isGroup ?? false) &&
        (s.phase == CallPhase.connected || s.phase == CallPhase.reconnecting);
    return SafeArea(
      child: AnimatedOpacity(
        opacity: _controlsVisible || !onDark ? 1 : 0,
        duration: 200.ms,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Minimise',
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: fg, size: 28),
                onPressed: s.phase == CallPhase.incoming || s.phase == CallPhase.ended ? _close : _minimize,
              ),
              Expanded(
                child: onDark
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            head.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700, color: fg),
                          ),
                          _statusLine(s, color: AppColors.brandWhite.withValues(alpha: 0.8)),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              if (isOneToOneVideo)
                IconButton(
                  tooltip: room.layout == CallLayout.split ? 'Picture-in-picture view' : 'Dual split-screen cameras',
                  icon: Icon(
                    room.layout == CallLayout.split
                        ? Icons.picture_in_picture_alt_rounded
                        : Icons.vertical_split_rounded,
                    color: room.layout == CallLayout.split ? AppColors.brandPink : fg,
                    size: 21,
                  ),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    ref.read(callRoomControllerProvider.notifier).setLayout(
                          room.layout == CallLayout.split ? CallLayout.grid : CallLayout.split,
                        );
                  },
                ),
              if (s.call != null && (s.phase == CallPhase.connected || s.phase == CallPhase.reconnecting))
                IconButton(
                  tooltip: 'Effects, sounds, music and people',
                  icon: Icon(Icons.tune_rounded, color: fg, size: 22),
                  onPressed: () => showCallPanel(context),
                ),
              if (s.call != null && (s.phase == CallPhase.connected || s.phase == CallPhase.reconnecting))
                IconButton(
                  tooltip: 'Share photo, video or file',
                  icon: Icon(Icons.attach_file_rounded, color: fg, size: 22),
                  onPressed: () => showCallShareSheet(context, ref, callId: s.call!.id, chatId: s.call!.chatId),
                ),
              if (s.call != null && (s.phase == CallPhase.connected || s.phase == CallPhase.reconnecting))
                IconButton(
                  tooltip: media.isScreenSharingActive ? 'Stop screen sharing' : 'Share screen',
                  icon: Icon(
                    media.isScreenSharingActive ? Icons.stop_screen_share_rounded : Icons.screen_share_rounded,
                    color: media.isScreenSharingActive ? AppColors.brandPink : fg,
                    size: 22,
                  ),
                  onPressed: controller.toggleScreenShare,
                ),
              if (canInvite)
                IconButton(
                  tooltip: 'Add people',
                  icon: Icon(Icons.person_add_alt_1_rounded, color: fg, size: 22),
                  onPressed: () => showCallInviteSheet(context, ref),
                )
              else
                const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _incomingControls(ActiveCallState s) {
    final controller = ref.read(activeCallControllerProvider.notifier);
    final isVideo = s.call?.isVideo ?? false;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 0, 40, 36),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CallControlButton(
              icon: Icons.call_end_rounded,
              label: 'Decline',
              size: 64,
              fill: AppColors.brandPink,
              onTap: controller.decline,
            ),
            CallControlButton(
              icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
              label: 'Accept',
              size: 64,
              fill: AppColors.brandBlue,
              onTap: () => controller.accept(),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(begin: const Offset(1, 1), end: const Offset(1.06, 1.06), duration: 700.ms),
          ],
        ),
      ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.2, end: 0),
    );
  }

  Widget _inCallControls(ActiveCallState s, CallMediaState media, {required bool onDark}) {
    final controller = ref.read(activeCallControllerProvider.notifier);
    final ended = s.phase == CallPhase.ended;
    final routeIcon = audioRouteIcon(media.audioRoute);
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
        decoration: BoxDecoration(
          color: onDark ? AppColors.brandBlack.withValues(alpha: 0.45) : context.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(
            color: onDark ? AppColors.brandWhite.withValues(alpha: 0.08) : context.border,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            CallControlButton(
              icon: routeIcon,
              label: audioRouteLabel(media.audioRoute),
              active: media.audioRoute != AudioRoute.earpiece,
              onDark: onDark,
              onTap: ended
                  ? null
                  : () => media.outputs.length > 2 || media.hasBluetooth
                      ? _showAudioRoutes()
                      : controller.toggleSpeaker(),
            ),
            CallControlButton(
              icon: media.isVideoOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              label: media.isVideoOn ? 'Camera' : 'Video',
              active: media.isVideoOn,
              onDark: onDark,
              onTap: ended ? null : controller.toggleCamera,
            ),
            CallControlButton(
              icon: media.isAudioMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: media.isAudioMuted ? 'Unmute' : 'Mute',
              active: media.isAudioMuted,
              onDark: onDark,
              onTap: ended ? null : controller.toggleMute,
            ),
            CallControlButton(
              icon: media.isScreenSharingActive ? Icons.stop_screen_share_rounded : Icons.screen_share_rounded,
              label: media.isScreenSharingActive ? 'Stop Share' : 'Share',
              active: media.isScreenSharingActive,
              onDark: onDark,
              onTap: ended ? null : controller.toggleScreenShare,
            ),
            if (media.isVideoOn)
              CallControlButton(
                icon: Icons.flip_camera_ios_rounded,
                label: 'Flip',
                onDark: onDark,
                onTap: ended ? null : controller.switchCamera,
              ),
            CallControlButton(
              icon: Icons.call_end_rounded,
              label: ended ? 'Ended' : 'End',
              fill: AppColors.brandPink,
              onTap: ended ? null : controller.hangUp,
            ),
          ],
        ),
      ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.15, end: 0),
    );
  }

  void _showAudioRoutes() {
    HapticFeedback.lightImpact();
    final controller = ref.read(activeCallControllerProvider.notifier);
    ref.read(callMediaServiceProvider.notifier).refreshOutputs();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final media = ref.watch(callMediaServiceProvider);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: ctx.border, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 12),
                Text('Audio output',
                    style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
                const SizedBox(height: 6),
                for (final o in media.outputs)
                  ListTile(
                    dense: true,
                    leading: Icon(audioRouteIcon(o.route), color: AppColors.brandBlue, size: 20),
                    title: Text(
                      o.route == AudioRoute.bluetooth && o.label.isNotEmpty ? o.label : audioRouteLabel(o.route),
                      style: GoogleFonts.inter(fontSize: 13, color: ctx.textPrimary),
                    ),
                    trailing: media.audioRoute == o.route
                        ? const Icon(Icons.check_rounded, color: AppColors.brandBlue, size: 18)
                        : null,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      controller.selectAudioRoute(o.route, deviceId: o.deviceId);
                      Navigator.of(ctx).pop();
                    },
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// Opens the call screen if it isn't already showing.
void openCallScreen(GoRouter router) {
  if (ActiveCallScreen.isVisible.value) return;
  if (kDebugMode) debugPrint('[Call] opening /call/active');
  router.push('/call/active');
}
