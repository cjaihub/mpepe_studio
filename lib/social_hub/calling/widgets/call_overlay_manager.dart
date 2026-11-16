import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/calling/models/call_model.dart';
import '../../../backend/calling/models/call_participant.dart';
import '../../../backend/calling/providers/active_call_controller.dart';
import '../../../backend/calling/providers/call_media_service.dart';
import '../../../backend/calling/providers/call_room_controller.dart';
import '../../../backend/calling/providers/call_signaling_service.dart';
import '../../../backend/calling/providers/webrtc_connection_manager.dart';
import '../../../backend/calling/services/call_ice_config.dart';
import '../../../backend/calling/services/call_pip_service.dart';
import '../../../backend/calling/services/callkit_service.dart';
import '../../../backend/notifications/providers/push_notification_service.dart';
import '../../../inbox/calling/screens/active_call_screen.dart';
import '../../../inbox/calling/widgets/call_widgets.dart';
import '../../../shared/router.dart';
import '../../../shared/theme/app_theme.dart';

/// App-wide call host (wraps the router in `main.dart`):
/// * rings in-app for calls found by the Firestore listener;
/// * reacts to the native ringer (accept/decline from the lock screen,
///   including a cold start after the app was killed);
/// * registers push/VoIP tokens and call permissions after sign-in;
/// * shows the floating minimised call window on every screen.
class CallOverlayManager extends ConsumerStatefulWidget {
  final Widget child;

  const CallOverlayManager({super.key, required this.child});

  /// True when an accepted/incoming call arrived while `/splash` was still on
  /// screen; consumed once `/splash` hands off to `/hub/home`.
  static bool pendingOpenCall = false;

  static bool consumePendingOpenCall() {
    final v = pendingOpenCall;
    pendingOpenCall = false;
    return v;
  }

  @override
  ConsumerState<CallOverlayManager> createState() => _CallOverlayManagerState();
}

class _CallOverlayManagerState extends ConsumerState<CallOverlayManager> {
  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<CallModel>>? _incomingSub;
  StreamSubscription<CallEvent?>? _callkitSub;
  String? _bootstrappedUid;

  @override
  void initState() {
    super.initState();
    _callkitSub = FlutterCallkitIncoming.onEvent.listen(_onCallKitEvent, onError: (_) {});
    FlutterCallkitIncoming.onBackgroundMessage(callKitBackgroundEventHandler).catchError((_) {});
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuth);
    CallPipService.inPip.addListener(_onPipChanged);
  }

  /// The app shrank into system PiP while the call was minimised: bring the
  /// call screen up so the PiP window shows the call, not the feed.
  void _onPipChanged() {
    if (!CallPipService.inPip.value) return;
    final s = ref.read(activeCallControllerProvider);
    if (!s.isLive || ActiveCallScreen.isVisible.value) return;
    ref.read(activeCallControllerProvider.notifier).restore();
    _openScreen();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _incomingSub?.cancel();
    _callkitSub?.cancel();
    CallPipService.inPip.removeListener(_onPipChanged);
    super.dispose();
  }

  Future<void> _onAuth(User? user) async {
    _incomingSub?.cancel();
    _incomingSub = null;
    if (user == null) {
      _bootstrappedUid = null;
      return;
    }
    _incomingSub = ref.read(callSignalingServiceProvider).streamIncomingCalls().listen(
      (calls) {
        if (calls.isNotEmpty) _ring(calls.first);
      },
      onError: (Object e) => debugPrint('[CallHost] incoming listener: $e'),
    );
    if (_bootstrappedUid == user.uid) return;
    _bootstrappedUid = user.uid;
    unawaited(CallIceConfig.warmUp());
    // Accepted on the lock screen while the app was killed: connect first,
    // before any permission prompt or token work can delay the caller.
    await _resumeAcceptedNativeCall();
    try {
      await ref.read(pushNotificationServiceProvider).initialize();
    } catch (e) {
      debugPrint('[CallHost] push init: $e');
    }
    await CallKitService.requestPermissions();
    await CallKitService.registerVoipToken();
  }

  /// The user accepted on the lock screen before Flutter was running, or a
  /// stale CallKit entry lingered after an earlier crash.
  Future<void> _resumeAcceptedNativeCall() async {
    final calls = await CallKitService.activeCalls();
    for (final c in calls) {
      final callId = c.extra?['callId'] as String?;
      if (callId == null) continue;
      if (c.isAccepted) {
        await ref.read(activeCallControllerProvider.notifier).acceptById(callId);
        if (ref.read(activeCallControllerProvider).isLive) {
          _openScreen();
        }
        return;
      }
      final existing = await ref.read(callSignalingServiceProvider).getCall(callId).catchError((_) => null);
      if (existing == null || existing.isFinished) {
        await CallKitService.end(c.id);
      }
    }
  }

  Future<void> _ring(CallModel call) async {
    final controller = ref.read(activeCallControllerProvider.notifier);
    await controller.presentIncoming(call);
    if (ref.read(activeCallControllerProvider).phase == CallPhase.incoming &&
        ref.read(activeCallControllerProvider).call?.id == call.id) {
      _openScreen();
    }
  }

  void _openScreen() {
    if (!mounted) return;
    final router = ref.read(routerProvider);
    final loc = router.routerDelegate.currentConfiguration.uri.path;
    if (loc == '/splash' || loc.isEmpty || loc == '/') {
      CallOverlayManager.pendingOpenCall = true;
      return;
    }
    openCallScreen(router);
  }

  Future<void> _onCallKitEvent(CallEvent? event) async {
    if (event == null) return;
    final controller = ref.read(activeCallControllerProvider.notifier);
    final current = ref.read(activeCallControllerProvider).call;
    switch (event) {
      case CallEventActionDidUpdateDevicePushTokenVoip():
        await CallKitService.registerVoipToken();
        break;
      case CallEventActionCallAccept(:final callKitParams):
        final callId = callKitParams.extra?['callId'] as String?;
        if (callId == null) return;
        await controller.acceptById(callId);
        _openScreen();
        break;
      case CallEventActionCallDecline(:final callKitParams):
        final callId = callKitParams.extra?['callId'] as String?;
        if (callId == null) return;
        if (current?.id == callId) {
          if (ref.read(activeCallControllerProvider).phase == CallPhase.incoming) await controller.decline();
        } else {
          final signaling = ref.read(callSignalingServiceProvider);
          if (await signaling.myStatus(callId) == ParticipantStatus.ringing) await signaling.declineCall(callId);
        }
        break;
      case CallEventActionCallEnded(:final callKitParams):
        final callId = callKitParams.extra?['callId'] as String?;
        final s = ref.read(activeCallControllerProvider);
        if (callId != null && current?.id == callId && s.isBusy) await controller.hangUp();
        break;
      case CallEventActionCallToggleMute(:final isMuted):
        final media = ref.read(callMediaServiceProvider);
        if (media.isAudioMuted != isMuted) controller.toggleMute();
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(activeCallControllerProvider);
    // Keeps the sound pad, shared music and filters alive for every call.
    ref.watch(callRoomControllerProvider.select((r) => r.callId));
    return Stack(
      children: [
        widget.child,
        ValueListenableBuilder<bool>(
          valueListenable: ActiveCallScreen.isVisible,
          builder: (context, visible, _) {
            if (visible || !s.isMinimized || !s.isLive) return const SizedBox.shrink();
            return _MiniCallWindow(onOpen: () {
              ref.read(activeCallControllerProvider.notifier).restore();
              _openScreen();
            });
          },
        ),
      ],
    );
  }
}

/// Draggable floating window for a minimised call with camera preview & screen share support.
class _MiniCallWindow extends ConsumerStatefulWidget {
  final VoidCallback onOpen;
  const _MiniCallWindow({required this.onOpen});

  @override
  ConsumerState<_MiniCallWindow> createState() => _MiniCallWindowState();
}

class _MiniCallWindowState extends ConsumerState<_MiniCallWindow> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _localReady = false;
  String? _boundLocalTrackId;
  Offset? _pos;

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize().then((_) {
      if (mounted) setState(() => _localReady = true);
    });
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    super.dispose();
  }

  void _syncLocalTrack(CallMediaState media) {
    if (!_localReady) return;
    final stream = media.isScreenSharingActive ? media.screenStream : media.localStream;
    final track = stream?.getVideoTracks().firstOrNull;
    if (track?.id == _boundLocalTrackId) return;
    _boundLocalTrackId = track?.id;
    if (stream != null && track != null) {
      _localRenderer.srcObject = stream;
    } else {
      _localRenderer.srcObject = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(activeCallControllerProvider);
    final media = ref.watch(callMediaServiceProvider);
    final mesh = ref.watch(webrtcConnectionManagerProvider);
    final controller = ref.read(activeCallControllerProvider.notifier);
    _syncLocalTrack(media);

    final head = callHeadline(s);
    final remote = s.remoteParticipants.where((p) => p.status == ParticipantStatus.joined).firstOrNull;
    final peer = remote != null && mesh.peers.containsKey(remote.userId)
        ? mesh.peers[remote.userId]
        : mesh.peers.values.firstOrNull;
    final renderer = peer?.renderer;

    final remoteVideoActive = renderer != null &&
        (renderer.renderVideo || renderer.srcObject != null) &&
        (peer?.hasRemoteVideo ?? false) &&
        !(remote?.isVideoMuted ?? false);

    final localVideoActive = (media.isVideoOn || media.isScreenSharingActive) &&
        _localReady &&
        _localRenderer.srcObject != null;

    final showVideo = remoteVideoActive || localVideoActive;

    final size = MediaQuery.sizeOf(context);
    const w = 138.0;
    final h = showVideo ? 198.0 : 138.0;
    final pos = _pos ?? Offset(size.width - w - 16, size.height - h - 140);
    final textStyle = GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.brandWhite);

    return Positioned(
      left: pos.dx.clamp(8.0, size.width - w - 8),
      top: pos.dy.clamp(MediaQuery.paddingOf(context).top + 8, size.height - h - 16),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onOpen();
        },
        onPanUpdate: (d) => setState(() => _pos = pos + d.delta),
        onPanEnd: (_) {
          final centerX = pos.dx + w / 2;
          final targetX = centerX < size.width / 2 ? 12.0 : size.width - w - 12.0;
          setState(() => _pos = Offset(targetX, pos.dy));
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: w,
            height: h,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: media.isScreenSharingActive
                    ? AppColors.brandPink
                    : AppColors.brandWhite.withValues(alpha: 0.22),
                width: 1.5,
              ),
              boxShadow: AppShadows.md,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (remoteVideoActive)
                  RTCVideoView(renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                else if (localVideoActive)
                  RTCVideoView(
                    _localRenderer,
                    mirror: media.isFrontCamera && !media.isScreenSharingActive,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                else
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CallAvatar(url: head.avatar, name: head.name, size: 44),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(head.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),

                // Corner PiP self-view when remote video is shown and local camera is on ("stay camera")
                if (remoteVideoActive && localVideoActive)
                  Positioned(
                    top: 6,
                    right: 6,
                    width: 44,
                    height: 58,
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.brandWhite.withValues(alpha: 0.35), width: 1),
                        color: AppColors.brandBlack,
                      ),
                      child: RTCVideoView(
                        _localRenderer,
                        mirror: media.isFrontCamera && !media.isScreenSharingActive,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),

                // Live status gradient vignette
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 56,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          AppColors.brandBlack.withValues(alpha: 0.85),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // Screen sharing badge if active
                if (media.isScreenSharingActive)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.brandPink,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.screen_share_rounded, size: 10, color: AppColors.brandWhite),
                          const SizedBox(width: 3),
                          Text('LIVE', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w800, color: AppColors.brandWhite)),
                        ],
                      ),
                    ),
                  ),

                // Bottom row: Timer / Status + Mute + Hangup
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: 6,
                  child: Row(
                    children: [
                      Expanded(
                        child: s.phase == CallPhase.connected && s.connectedAt != null
                            ? CallTimerText(since: s.connectedAt!, style: textStyle)
                            : Text(callStatusLabel(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle),
                      ),
                      _miniButton(
                        media.isAudioMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        media.isAudioMuted ? AppColors.brandPink : AppColors.brandWhite.withValues(alpha: 0.22),
                        controller.toggleMute,
                      ),
                      const SizedBox(width: 4),
                      _miniButton(Icons.call_end_rounded, AppColors.brandPink, controller.hangUp),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ).animate().fadeIn(duration: 220.ms).scale(begin: const Offset(0.9, 0.9)),
    );
  }

  Widget _miniButton(IconData icon, Color fill, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
        child: Icon(icon, size: 13, color: AppColors.brandWhite),
      ),
    );
  }
}
