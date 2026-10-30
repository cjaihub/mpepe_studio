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
import '../../../backend/calling/providers/call_signaling_service.dart';
import '../../../backend/calling/providers/webrtc_connection_manager.dart';
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

  /// The user accepted on the lock screen before Flutter was running.
  Future<void> _resumeAcceptedNativeCall() async {
    final calls = await CallKitService.activeCalls();
    for (final c in calls) {
      final callId = c.extra?['callId'] as String?;
      if (callId != null && c.isAccepted) {
        await ref.read(activeCallControllerProvider.notifier).acceptById(callId);
        _openScreen();
        return;
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
    openCallScreen(ref.read(routerProvider));
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

/// Draggable floating window for a minimised call.
class _MiniCallWindow extends ConsumerStatefulWidget {
  final VoidCallback onOpen;
  const _MiniCallWindow({required this.onOpen});

  @override
  ConsumerState<_MiniCallWindow> createState() => _MiniCallWindowState();
}

class _MiniCallWindowState extends ConsumerState<_MiniCallWindow> {
  Offset? _pos;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(activeCallControllerProvider);
    final media = ref.watch(callMediaServiceProvider);
    final mesh = ref.watch(webrtcConnectionManagerProvider);
    final controller = ref.read(activeCallControllerProvider.notifier);
    final head = callHeadline(s);
    final remote = s.remoteParticipants.where((p) => p.status == ParticipantStatus.joined).firstOrNull;
    final renderer = remote == null ? null : mesh.peers[remote.userId]?.renderer;
    final showVideo = renderer != null && remote != null && !remote.isVideoMuted;

    final size = MediaQuery.sizeOf(context);
    const w = 132.0;
    final h = showVideo ? 188.0 : 132.0;
    final pos = _pos ?? Offset(size.width - w - 14, size.height - h - 150);
    final textStyle = GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brandWhite);

    return Positioned(
      left: pos.dx.clamp(8.0, size.width - w - 8),
      top: pos.dy.clamp(MediaQuery.paddingOf(context).top + 8, size.height - h - 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onOpen();
        },
        onPanUpdate: (d) => setState(() => _pos = pos + d.delta),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: w,
            height: h,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.brandBlue,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.brandWhite.withValues(alpha: 0.18), width: 1),
              boxShadow: AppShadows.md,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (showVideo)
                  RTCVideoView(renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                else
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CallAvatar(url: head.avatar, name: head.name, size: 42),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(head.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle),
                      ),
                      const SizedBox(height: 22),
                    ],
                  ),
                Positioned(
                  left: 8,
                  right: 8,
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
                        AppColors.brandWhite.withValues(alpha: 0.2),
                        controller.toggleMute,
                      ),
                      const SizedBox(width: 6),
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
        child: Icon(icon, size: 14, color: AppColors.brandWhite),
      ),
    );
  }
}
