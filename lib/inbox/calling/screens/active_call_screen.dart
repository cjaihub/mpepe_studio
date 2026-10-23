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
import '../../../backend/calling/providers/call_signaling_service.dart';
import '../../../backend/calling/providers/webrtc_connection_manager.dart';
import '../../../backend/calling/services/call_pip_service.dart';
import '../../../backend/calling/services/call_share_service.dart';
import '../../../shared/theme/app_theme.dart';
import '../widgets/call_invite_sheet.dart';
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
  bool _controlsVisible = true;
  bool _swapped = false;
  bool _closing = false;
  Offset? _pipOffset;
  Timer? _hideControls;
  final Set<String> _seenShared = {};
  bool _sharedPrimed = false;

  @override
  void initState() {
    super.initState();
    ActiveCallScreen.isVisible.value = true;
    _localRenderer.initialize().then((_) {
      if (!mounted) return;
      setState(() => _localReady = true);
      _bindLocal(ref.read(callMediaServiceProvider).localStream);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumeIfNeeded());
  }

  /// Opened from a notification/deep link with only a call id.
  Future<void> _resumeIfNeeded() async {
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

  void _bindLocal(MediaStream? stream) {
    if (!_localReady) return;
    if (_localRenderer.srcObject?.id != stream?.id) {
      _localRenderer.srcObject = stream;
      if (mounted) setState(() {});
    }
  }

  void _scheduleHide() {
    _hideControls?.cancel();
    _hideControls = Timer(const Duration(seconds: 5), () {
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
    ref.read(activeCallControllerProvider.notifier).minimize();
    _close();
  }

  @override
  void dispose() {
    ActiveCallScreen.isVisible.value = false;
    CallPipService.setAutoEnter(false);
    _hideControls?.cancel();
    _localRenderer.srcObject = null;
    _localRenderer.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
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
    final controller = ref.read(activeCallControllerProvider.notifier);

    ref.listen<CallMediaState>(callMediaServiceProvider, (_, m) => _bindLocal(m.localStream));
    ref.listen<ActiveCallState>(activeCallControllerProvider, (prev, next) {
      if (next.errorMessage != null && next.errorMessage != prev?.errorMessage) {
        _showError(next.errorMessage!);
        controller.clearError();
      }
      if (next.phase == CallPhase.ended && prev?.phase != CallPhase.ended) {
        Future.delayed(const Duration(milliseconds: 1400), _close);
      }
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

    // Android system PiP when the user leaves the app mid video call.
    CallPipService.setAutoEnter(s.phase == CallPhase.connected && (media.isVideoOn || _anyRemoteVideo(s)));

    final head = callHeadline(
      s,
      fallbackName: widget.isCaller ? widget.otherUserName : null,
      fallbackAvatar: widget.isCaller ? widget.otherUserAvatar : null,
    );
    final joinedRemotes = s.remoteParticipants.where((p) => p.status == ParticipantStatus.joined).toList();
    final showVideoStage = (s.phase == CallPhase.connected || s.phase == CallPhase.reconnecting) &&
        (media.isVideoOn || joinedRemotes.any((p) => !p.isVideoMuted));
    final isGroup = s.call?.isGroup ?? false;
    final tiny = MediaQuery.sizeOf(context).width < 320; // Android PiP window

    if (tiny) return _pipView(s, mesh, head);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && ref.read(activeCallControllerProvider).isLive) controller.minimize();
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
                      ? (isGroup ? _groupGrid(s, mesh, media) : _oneToOneStage(s, mesh, media, head))
                      : _audioStage(s, head),
                ),
                if (showVideoStage && !isGroup) _localPreview(media, mesh, s),
                _topBar(s, head, onDark: showVideoStage),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedSlide(
                    offset: _controlsVisible || !showVideoStage ? Offset.zero : const Offset(0, 1.2),
                    duration: 220.ms,
                    curve: Curves.easeOutCubic,
                    child: s.phase == CallPhase.incoming
                        ? _incomingControls(s)
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

  bool _anyRemoteVideo(ActiveCallState s) =>
      s.remoteParticipants.any((p) => p.status == ParticipantStatus.joined && !p.isVideoMuted);

  // ───────────────────────── Stages ─────────────────────────

  Widget _audioStage(ActiveCallState s, ({String name, String? avatar}) head) {
    final ringing = s.phase == CallPhase.outgoing || s.phase == CallPhase.incoming;
    final isGroup = s.call?.isGroup ?? false;
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

  Widget _videoOrAvatar({
    required RTCVideoRenderer? renderer,
    required bool videoOn,
    required String name,
    String? avatar,
    bool mirror = false,
  }) {
    if (renderer != null && videoOn) {
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

  Widget _oneToOneStage(
    ActiveCallState s,
    WebRTCMeshState mesh,
    CallMediaState media,
    ({String name, String? avatar}) head,
  ) {
    final remote = s.remoteParticipants.where((p) => p.status == ParticipantStatus.joined).firstOrNull;
    final peer = remote == null ? null : mesh.peers[remote.userId];
    final remoteView = _videoOrAvatar(
      renderer: peer?.renderer,
      videoOn: remote != null && !remote.isVideoMuted,
      name: head.name,
      avatar: head.avatar,
    );
    final localView = _videoOrAvatar(
      renderer: _localReady ? _localRenderer : null,
      videoOn: media.isVideoOn,
      name: 'You',
      mirror: media.isFrontCamera,
    );
    return _swapped ? localView : remoteView;
  }

  Widget _localPreview(CallMediaState media, WebRTCMeshState mesh, ActiveCallState s) {
    final size = MediaQuery.sizeOf(context);
    const w = 104.0, h = 150.0;
    final offset = _pipOffset ?? Offset(size.width - w - 14, MediaQuery.paddingOf(context).top + 64);
    final remote = s.remoteParticipants.where((p) => p.status == ParticipantStatus.joined).firstOrNull;
    final peer = remote == null ? null : mesh.peers[remote.userId];
    final child = _swapped
        ? _videoOrAvatar(
            renderer: peer?.renderer,
            videoOn: remote != null && !remote.isVideoMuted,
            name: remote?.name ?? '',
            avatar: remote?.avatar,
          )
        : _videoOrAvatar(
            renderer: _localReady ? _localRenderer : null,
            videoOn: media.isVideoOn,
            name: 'You',
            mirror: media.isFrontCamera,
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
          child: child,
        ),
      ).animate().fadeIn(duration: 250.ms).scale(begin: const Offset(0.92, 0.92)),
    );
  }

  Widget _groupGrid(ActiveCallState s, WebRTCMeshState mesh, CallMediaState media) {
    final tiles = <Widget>[
      _tile(
        name: 'You',
        renderer: _localReady ? _localRenderer : null,
        videoOn: media.isVideoOn,
        muted: media.isAudioMuted,
        mirror: media.isFrontCamera,
      ),
      for (final p in s.remoteParticipants.where(
        (p) => p.status == ParticipantStatus.joined || p.status == ParticipantStatus.ringing,
      ))
        _tile(
          name: p.name,
          avatar: p.avatar,
          renderer: mesh.peers[p.userId]?.renderer,
          videoOn: p.status == ParticipantStatus.joined && !p.isVideoMuted,
          muted: p.isAudioMuted,
          ringing: p.status == ParticipantStatus.ringing,
          link: mesh.peers[p.userId]?.link,
        ),
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
    final peer = remote == null ? null : mesh.peers[remote.userId];
    return ColoredBox(
      color: AppColors.brandBlack,
      child: _videoOrAvatar(
        renderer: peer?.renderer,
        videoOn: remote != null && !remote.isVideoMuted,
        name: head.name,
        avatar: head.avatar,
      ),
    );
  }

  // ───────────────────────── Chrome ─────────────────────────

  Widget _topBar(ActiveCallState s, ({String name, String? avatar}) head, {required bool onDark}) {
    final fg = onDark ? AppColors.brandWhite : context.textPrimary;
    final canInvite = s.isBusy && s.phase != CallPhase.outgoing && s.call != null;
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
              if (s.call != null && (s.phase == CallPhase.connected || s.phase == CallPhase.reconnecting))
                IconButton(
                  tooltip: 'Share photo, video or file',
                  icon: Icon(Icons.attach_file_rounded, color: fg, size: 22),
                  onPressed: () => showCallShareSheet(context, ref, callId: s.call!.id, chatId: s.call!.chatId),
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
