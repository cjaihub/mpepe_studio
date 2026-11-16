import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/call_model.dart';
import '../models/call_participant.dart';
import '../services/call_ice_config.dart';
import '../services/call_pip_service.dart';
import '../services/callkit_service.dart';
import '../../social/services/video_playback_manager.dart';
import 'call_media_service.dart';
import 'call_signaling_service.dart';
import 'webrtc_connection_manager.dart';

/// Where the current call is in its life.
enum CallPhase { idle, outgoing, incoming, connecting, connected, reconnecting, ended }

class ActiveCallState {
  final CallPhase phase;
  final CallModel? call;
  final Map<String, CallParticipant> participants;
  final DateTime? connectedAt;

  /// When this device left the call, for the "Call ended · 3:24" summary.
  final DateTime? endedAt;
  final CallEndReason? endReason;
  final bool isMinimized;
  final String? errorMessage;

  const ActiveCallState({
    this.phase = CallPhase.idle,
    this.call,
    this.participants = const {},
    this.connectedAt,
    this.endedAt,
    this.endReason,
    this.isMinimized = false,
    this.errorMessage,
  });

  /// How long the two sides actually talked (null if it never connected).
  Duration? get talkTime =>
      connectedAt == null ? null : (endedAt ?? DateTime.now()).difference(connectedAt!);

  /// The caller's unanswered call (no answer, busy, declined): the end screen
  /// offers "Call again".
  bool get canRedial =>
      phase == CallPhase.ended &&
      connectedAt == null &&
      call != null &&
      call!.hostId == FirebaseAuth.instance.currentUser?.uid &&
      (endReason == CallEndReason.noAnswer ||
          endReason == CallEndReason.busy ||
          endReason == CallEndReason.declined ||
          endReason == CallEndReason.failed);

  /// Kept for older call sites.
  CallModel? get activeCall => call;
  bool get isConnecting => phase == CallPhase.connecting;

  bool get isBusy =>
      phase == CallPhase.outgoing ||
      phase == CallPhase.connecting ||
      phase == CallPhase.connected ||
      phase == CallPhase.reconnecting;

  bool get isLive => isBusy || phase == CallPhase.incoming;

  List<CallParticipant> get remoteParticipants {
    final me = FirebaseAuth.instance.currentUser?.uid;
    return participants.values.where((p) => p.userId != me).toList();
  }

  ActiveCallState copyWith({
    CallPhase? phase,
    CallModel? call,
    Map<String, CallParticipant>? participants,
    DateTime? connectedAt,
    DateTime? endedAt,
    CallEndReason? endReason,
    bool? isMinimized,
    String? errorMessage,
  }) {
    return ActiveCallState(
      phase: phase ?? this.phase,
      call: call ?? this.call,
      participants: participants ?? this.participants,
      connectedAt: connectedAt ?? this.connectedAt,
      endedAt: endedAt ?? this.endedAt,
      endReason: endReason ?? this.endReason,
      isMinimized: isMinimized ?? this.isMinimized,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// How long "Connecting…" may last after the call is answered before we give
/// up instead of leaving both phones stuck.
const Duration kCallConnectTimeout = Duration(seconds: 30);

/// How long a dropped call may try to recover (ICE restart, network handover)
/// before it is ended for both sides.
const Duration kCallReconnectTimeout = Duration(seconds: 30);

final activeCallControllerProvider =
    NotifierProvider<ActiveCallController, ActiveCallState>(ActiveCallController.new);

/// Single source of truth for calling. Screens only read this state and call
/// these methods; nothing else talks to WebRTC directly.
class ActiveCallController extends Notifier<ActiveCallState> {
  StreamSubscription<CallModel?>? _callSub;
  StreamSubscription<List<CallParticipant>>? _participantsSub;
  StreamSubscription<List<ConnectivityResult>>? _netSub;
  Timer? _ringTimer;
  Timer? _resetTimer;
  Timer? _netDebounce;
  Timer? _connectWatchdog;
  Timer? _reconnectWatchdog;
  List<ConnectivityResult>? _lastNet;
  bool _finishing = false;
  bool _nativeConnectedMarked = false;

  @visibleForTesting
  static bool shouldRestartOnConnectivityChange(
    List<ConnectivityResult> previous,
    List<ConnectivityResult> next,
  ) {
    final nextActive = next.where((r) => r != ConnectivityResult.none).toSet();
    if (nextActive.isEmpty) return false;
    final prevActive = previous.where((r) => r != ConnectivityResult.none).toSet();
    if (prevActive.isEmpty) return true;
    return !setEquals(prevActive, nextActive);
  }

  Future<({bool allowMic, bool noiseCancellation})> _readCallSettings() async {
    final uid = _me;
    if (uid.isEmpty) return (allowMic: true, noiseCancellation: true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('user_settings')
          .doc(uid)
          .get()
          .timeout(const Duration(milliseconds: 500));
      final calls = doc.data()?['calls'];
      if (calls is Map) {
        return (
          allowMic: calls['allowMic'] as bool? ?? true,
          noiseCancellation: calls['noiseCancellation'] as bool? ?? true,
        );
      }
    } catch (_) {}
    return (allowMic: true, noiseCancellation: true);
  }

  CallSignalingService get _signaling => ref.read(callSignalingServiceProvider);
  CallMediaService get _media => ref.read(callMediaServiceProvider.notifier);
  WebRTCConnectionManager get _mesh => ref.read(webrtcConnectionManagerProvider.notifier);
  String get _me => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  ActiveCallState build() {
    ref.listen<WebRTCMeshState>(webrtcConnectionManagerProvider, (_, mesh) => _onMesh(mesh));
    ref.listen<CallMediaState>(callMediaServiceProvider, (_, _) => _syncDevice());
    listenSelf((_, _) => _syncDevice());
    ref.onDispose(_cancelSubs);
    return const ActiveCallState();
  }

  CallKitParams _paramsFor(CallModel call) {
    final isIncoming = call.hostId != _me;
    String name = call.callerName;
    String? avatar = call.callerAvatar;
    if (!isIncoming) {
      final others = state.remoteParticipants;
      if (call.isGroup) {
        name = call.title ?? 'Group call';
      } else if (others.isNotEmpty) {
        name = others.first.name;
        avatar = others.first.avatar;
      }
    } else if (call.isGroup && call.title != null) {
      name = call.title!;
    }
    return CallKitService.params(
      callkitId: call.callkitId.isEmpty ? call.id : call.callkitId,
      callId: call.id,
      callerName: name,
      avatar: avatar,
      isVideo: call.isVideo,
      isGroup: call.isGroup,
      hostId: call.hostId,
    );
  }

  // ───────────────────────── Outgoing ─────────────────────────

  /// Places a call. Throws with a readable message if the mic/camera can't be
  /// opened or the call can't be created.
  Future<CallModel> startCall({
    required List<String> targetUserIds,
    required bool isVideo,
    String? chatId,
    String? title,
  }) async {
    if (state.isBusy) {
      throw StateError('You are already in a call.');
    }
    final targets = targetUserIds.where((t) => t.isNotEmpty && t != _me).toSet().toList();
    if (targets.length + 1 > WebRTCConnectionManager.maxMeshParticipants) {
      throw StateError(
        'Group calls support up to ${WebRTCConnectionManager.maxMeshParticipants} people.',
      );
    }
    _resetTimer?.cancel();
    _finishing = false;
    _nativeConnectedMarked = false;
    state = const ActiveCallState(phase: CallPhase.outgoing);
    ref.read(videoPlaybackManagerProvider).setCallActive(true);
    unawaited(CallIceConfig.warmUp());
    late ({bool allowMic, bool noiseCancellation}) callPrefs;
    try {
      final setup = await Future.wait([
        _askBluetooth(),
        _readCallSettings(),
      ]);
      callPrefs = setup[1] as ({bool allowMic, bool noiseCancellation});
      await _media.initializeMedia(
        video: isVideo,
        voiceEnhanced: callPrefs.noiseCancellation,
        startMuted: !callPrefs.allowMic,
      );
    } catch (e) {
      ref.read(videoPlaybackManagerProvider).setCallActive(false);
      state = const ActiveCallState();
      if (e is StateError) rethrow;
      throw StateError('Allow microphone${isVideo ? ' and camera' : ''} access to call.');
    }
    try {
      final call = await _signaling.createCall(
        targetUserIds: targets,
        isVideo: isVideo,
        chatId: chatId,
        title: title,
        audioMuted: !callPrefs.allowMic,
      );
      state = state.copyWith(call: call, phase: CallPhase.outgoing);
      _mesh.attach(call.id);
      _watch(call.id);
      _ringTimer = Timer(kCallRingTimeout, _onRingTimeout);
      _watchNetwork();
      _syncDevice();
      HapticFeedback.lightImpact();
      // Android: foreground service + ongoing notification. iOS: CallKit call.
      unawaited(CallKitService.startOngoing(_paramsFor(call)));
      return call;
    } catch (e) {
      ref.read(videoPlaybackManagerProvider).setCallActive(false);
      await _media.disposeMedia();
      state = const ActiveCallState();
      rethrow;
    }
  }

  Future<void> _onRingTimeout() async {
    final call = state.call;
    if (call == null || state.phase != CallPhase.outgoing) return;
    try {
      await _signaling.cancelRinging(call.id, timedOut: true);
    } catch (e) {
      debugPrint('[Call] ring timeout cancel failed: $e');
    }
    await _finish(CallEndReason.noAnswer);
  }

  /// Rings more people into the current call.
  Future<void> invite(List<String> userIds) async {
    final call = state.call;
    if (call == null) return;
    final total = state.participants.values
            .where((p) => p.status == ParticipantStatus.joined || p.status == ParticipantStatus.ringing)
            .length +
        userIds.length;
    if (total > WebRTCConnectionManager.maxMeshParticipants) {
      throw StateError(
        'Group calls support up to ${WebRTCConnectionManager.maxMeshParticipants} people.',
      );
    }
    await _signaling.addParticipants(call.id, userIds);
  }

  // ───────────────────────── Incoming ─────────────────────────

  /// A call is ringing this user (from the Firestore listener or a push while
  /// the app is open). Rings natively too, or auto-replies busy.
  Future<void> presentIncoming(CallModel call) async {
    if (state.call?.id == call.id) return;
    if (await _signaling.isBlockedPair(_me, call.hostId)) {
      unawaited(_signaling.declineCall(call.id).catchError((_) {}));
      return;
    }
    if (state.isBusy) {
      await _signaling.markBusy(call.id);
      return;
    }
    if (state.phase == CallPhase.incoming) {
      // Already ringing for another call: tell this caller we're busy.
      await _signaling.markBusy(call.id);
      return;
    }
    _resetTimer?.cancel();
    _finishing = false;
    ref.read(videoPlaybackManagerProvider).setCallActive(true);
    state = ActiveCallState(phase: CallPhase.incoming, call: call);
    _watch(call.id);
    // The caller's own timeout normally ends the ring; this covers a caller
    // whose app died mid-ring so the callee never rings forever.
    _ringTimer?.cancel();
    _ringTimer = Timer(kCallRingTimeout + const Duration(seconds: 10), () {
      if (state.phase == CallPhase.incoming && state.call?.id == call.id) {
        unawaited(_signaling.declineCall(call.id).catchError((_) {}));
        _finish(CallEndReason.noAnswer, remote: true);
      }
    });
    HapticFeedback.heavyImpact();
    await CallKitService.showIncoming(_paramsFor(call));
    unawaited(_signaling.markDelivered(call.id));
  }

  /// Accepts a ringing call by id (used when the native UI accepted while the
  /// app was in the background or killed).
  Future<void> acceptById(String callId) async {
    if (state.call?.id == callId && state.phase != CallPhase.incoming) return;
    // A cold start can deliver the same accept twice (event + active calls).
    if (!_acceptingIds.add(callId)) return;
    try {
      await _acceptById(callId);
    } finally {
      _acceptingIds.remove(callId);
    }
  }

  final Set<String> _acceptingIds = {};

  Future<void> _acceptById(String callId) async {
    final call = await _signaling.getCall(callId);
    if (call == null || call.isFinished) {
      // The caller hung up before the answer got through: clear the native
      // call so the ongoing notification doesn't linger.
      final stale = call ?? state.call;
      if (stale != null) await CallKitService.end(_paramsFor(stale).id);
      return;
    }
    await accept(incoming: call, fromNativeUi: true);
  }

  Future<void> accept({CallModel? incoming, bool fromNativeUi = false}) async {
    final call = incoming ?? state.call;
    if (call == null) return;
    _resetTimer?.cancel();
    _finishing = false;
    _nativeConnectedMarked = false;
    ref.read(videoPlaybackManagerProvider).setCallActive(true);
    unawaited(CallIceConfig.warmUp());
    if (state.call?.id != call.id) {
      state = ActiveCallState(phase: CallPhase.connecting, call: call);
      _watch(call.id);
    } else {
      state = state.copyWith(phase: CallPhase.connecting);
    }
    _ringTimer?.cancel();
    _armConnectWatchdog();
    final params = _paramsFor(call);
    if (!fromNativeUi) {
      // Accepted in our own UI: stop the native ringer, then register the
      // ongoing call (Android foreground service).
      if (defaultTargetPlatform == TargetPlatform.android) {
        await CallKitService.hideIncoming(params);
        unawaited(CallKitService.startOngoing(params));
      } else {
        await CallKitService.end(params.id);
      }
    }
    late ({bool allowMic, bool noiseCancellation}) callPrefs;
    try {
      final setup = await Future.wait([
        _askBluetooth(),
        _readCallSettings(),
      ]);
      callPrefs = setup[1] as ({bool allowMic, bool noiseCancellation});
      await _media.initializeMedia(
        video: call.isVideo,
        voiceEnhanced: callPrefs.noiseCancellation,
        startMuted: !callPrefs.allowMic,
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Allow microphone${call.isVideo ? ' and camera' : ''} access to answer.');
      await decline();
      return;
    }
    try {
      _mesh.attach(call.id);
      _watchNetwork();
      _syncDevice();
      if (!call.isGroup) {
        // 1:1 fast path: start WebRTC offer + ICE exchange with the host in
        // parallel with Firestore accept signaling to shave 400–900ms off setup.
        await Future.wait([
          _signaling.acceptCall(call.id, videoOn: call.isVideo, audioMuted: !callPrefs.allowMic),
          _mesh.connectTo(call.hostId, offerer: true),
        ]);
      } else {
        final results = await Future.wait([
          _signaling.acceptCall(call.id, videoOn: call.isVideo, audioMuted: !callPrefs.allowMic),
          _signaling.fetchParticipants(call.id),
        ]);
        final current = results[1] as List<CallParticipant>;
        final others = current.where(
          (p) => p.userId != _me && p.status == ParticipantStatus.joined,
        );
        final ids = (others.isEmpty ? [call.hostId] : others.map((p) => p.userId)).toSet();
        await Future.wait([
          for (final id in ids) _mesh.connectTo(id, offerer: true),
        ]);
      }
      if (!_nativeConnectedMarked) {
        _nativeConnectedMarked = true;
        await CallKitService.setConnected(params.id);
      }
    } catch (e) {
      debugPrint('[Call] accept failed: $e');
      state = state.copyWith(errorMessage: 'Could not connect the call.');
      await _finish(CallEndReason.failed);
    }
  }

  Future<void> decline() async {
    final call = state.call;
    if (call == null) return;
    HapticFeedback.mediumImpact();
    await CallKitService.end(_paramsFor(call).id);
    await _signaling.declineCall(call.id);
    await _finish(CallEndReason.declined, silent: true);
  }

  // ───────────────────────── In call ─────────────────────────

  Future<void> hangUp() async {
    final call = state.call;
    if (call == null) {
      state = const ActiveCallState();
      return;
    }
    HapticFeedback.mediumImpact();
    if (state.phase == CallPhase.incoming) return decline();
    try {
      final anyoneJoined = state.participants.values.any(
        (p) => p.userId != _me && p.status == ParticipantStatus.joined,
      );
      if (call.hostId == _me && !anyoneJoined) {
        await _signaling.cancelRinging(call.id, timedOut: false);
      } else {
        await _signaling.leaveCall(call.id);
      }
    } catch (e) {
      debugPrint('[Call] hangUp signaling failed: $e');
    }
    await _finish(CallEndReason.hangup);
  }

  /// Kept for older call sites.
  Future<void> endCall() => hangUp();

  void toggleMute() {
    _media.toggleAudio();
    final muted = ref.read(callMediaServiceProvider).isAudioMuted;
    HapticFeedback.selectionClick();
    final call = state.call;
    if (call != null) {
      unawaited(_signaling.updateMediaState(call.id, audioMuted: muted));
      unawaited(FlutterCallkitIncoming.muteCall(_paramsFor(call).id, isMuted: muted).catchError((_) {}));
    }
  }

  /// Camera on/off; turning it on in an audio call upgrades to video.
  Future<void> toggleCamera() async {
    final on = !ref.read(callMediaServiceProvider).isVideoOn;
    HapticFeedback.selectionClick();
    try {
      final track = await _media.setVideoOn(on);
      await _mesh.replaceVideoTrack(track);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Camera unavailable.');
      return;
    }
    final call = state.call;
    if (call != null) unawaited(_signaling.updateMediaState(call.id, videoMuted: !on));
    _syncDevice();
  }

  Future<void> switchCamera() async {
    HapticFeedback.selectionClick();
    final replaced = await _media.switchCamera();
    if (replaced != null) {
      await _mesh.replaceVideoTrack(replaced);
    }
  }

  /// Shares device screen in real time while keeping camera preview active ("stay camera").
  Future<void> toggleScreenShare() async {
    final media = ref.read(callMediaServiceProvider);
    HapticFeedback.selectionClick();
    try {
      if (media.isScreenSharing) {
        final camTrack = await _media.stopScreenShare();
        await _mesh.replaceVideoTrack(camTrack);
      } else {
        final screenTrack = await _media.startScreenShare();
        if (screenTrack != null) {
          await _mesh.replaceVideoTrack(screenTrack);
        }
      }
    } catch (e) {
      debugPrint('[Call] toggleScreenShare error: $e');
      state = state.copyWith(errorMessage: 'Could not toggle screen share.');
    }
    _syncDevice();
  }

  /// Toggles zero-cost Studio Voice Clean (hardware + WebRTC DSP) for crystal
  /// clear voice in both audio and video calls.
  Future<void> toggleVoiceEnhance() async {
    HapticFeedback.selectionClick();
    final replaced = await _media.toggleVoiceEnhanced();
    if (replaced != null) {
      await _mesh.replaceAudioTrack(replaced);
    }
  }

  Future<void> toggleSpeaker() async {
    HapticFeedback.selectionClick();
    await _media.toggleSpeaker();
  }

  Future<void> selectAudioRoute(AudioRoute route, {String? deviceId}) =>
      _media.selectRoute(route, deviceId: deviceId);

  void minimize() {
    if (!state.isLive) return;
    state = state.copyWith(isMinimized: true);
  }

  void restore() => state = state.copyWith(isMinimized: false);

  void clearError() {
    state = ActiveCallState(
      phase: state.phase,
      call: state.call,
      participants: state.participants,
      connectedAt: state.connectedAt,
      endedAt: state.endedAt,
      endReason: state.endReason,
      isMinimized: state.isMinimized,
    );
  }

  /// "Call again" from the end screen of an unanswered call.
  Future<CallModel?> redial() async {
    final s = state;
    final call = s.call;
    if (!s.canRedial || call == null) return null;
    _resetTimer?.cancel();
    final targets = call.participantIds.where((id) => id != _me).toList();
    return startCall(
      targetUserIds: targets,
      isVideo: call.isVideo,
      chatId: call.chatId,
      title: call.isGroup ? call.title : null,
    );
  }

  // ───────────────────────── Internals ─────────────────────────

  void _watch(String callId) {
    _callSub?.cancel();
    _participantsSub?.cancel();
    _callSub = _signaling.watchCall(callId).listen((call) {
      if (call == null || state.call?.id != callId) return;
      state = state.copyWith(call: call);
      if (call.isFinished) {
        _finish(call.endReason ?? CallEndReason.hangup, remote: true);
      }
    });
    _participantsSub = _signaling.watchParticipants(callId).listen(_onParticipants);
  }

  void _onParticipants(List<CallParticipant> list) {
    final map = {for (final p in list) p.userId: p};
    final previous = state.participants;
    state = state.copyWith(participants: map);
    final me = map[_me];

    // Answered on another of my devices, or I was marked missed/busy.
    if (state.phase == CallPhase.incoming && me != null && me.status != ParticipantStatus.ringing) {
      _finish(CallEndReason.cancelled, silent: true);
      return;
    }

    for (final p in list) {
      if (p.userId == _me) continue;
      final was = previous[p.userId]?.status;
      if (p.status == ParticipantStatus.joined && was != ParticipantStatus.joined) {
        _ringTimer?.cancel();
        if (state.phase == CallPhase.outgoing) {
          final alreadyConnected = ref.read(webrtcConnectionManagerProvider).anyConnected;
          if (alreadyConnected) {
            state = state.copyWith(
              phase: CallPhase.connected,
              connectedAt: state.connectedAt ?? DateTime.now(),
            );
          } else {
            state = state.copyWith(phase: CallPhase.connecting);
            _armConnectWatchdog();
          }
        }
        HapticFeedback.lightImpact();
        _ensurePeer(p.userId);
      }
      if (p.status != ParticipantStatus.joined && was == ParticipantStatus.joined) {
        _mesh.removePeer(p.userId);
      }
    }

    // 1:1 outgoing: the other side said no.
    final call = state.call;
    if (call != null && !call.isGroup && state.phase == CallPhase.outgoing) {
      final other = list.where((p) => p.userId != _me);
      if (other.isNotEmpty) {
        final s = other.first.status;
        if (s == ParticipantStatus.declined) _finish(CallEndReason.declined, remote: true);
        if (s == ParticipantStatus.busy) _finish(CallEndReason.busy, remote: true);
        if (s == ParticipantStatus.missed) _finish(CallEndReason.noAnswer, remote: true);
      }
    }

    // 1:1 in call: the other person hung up or dropped. Don't wait for the
    // call document to settle, or the screen hangs on "Reconnecting…".
    if (call != null && !call.isGroup &&
        (state.phase == CallPhase.connecting ||
            state.phase == CallPhase.connected ||
            state.phase == CallPhase.reconnecting)) {
      final other = list.where((p) => p.userId != _me);
      if (other.isNotEmpty) {
        final s = other.first.status;
        final prev = previous[other.first.userId]?.status;
        if ((s == ParticipantStatus.left || s == ParticipantStatus.dropped) && prev == ParticipantStatus.joined) {
          unawaited(_signaling.settleCall(call.id).catchError((_) {}));
          _finish(CallEndReason.hangup, remote: true);
        }
      }
    }
  }

  void _armConnectWatchdog() {
    _connectWatchdog?.cancel();
    _connectWatchdog = Timer(kCallConnectTimeout, () {
      if (state.phase != CallPhase.connecting) return;
      debugPrint('[Call] media never connected; ending call');
      state = state.copyWith(errorMessage: 'Could not connect. Check your network.');
      _dropCall();
    });
  }

  void _armReconnectWatchdog() {
    if (_reconnectWatchdog?.isActive ?? false) return;
    _reconnectWatchdog = Timer(kCallReconnectTimeout, () {
      if (state.phase != CallPhase.reconnecting) return;
      debugPrint('[Call] could not recover the connection; ending call');
      state = state.copyWith(errorMessage: 'Connection lost.');
      _dropCall();
    });
  }

  /// Leaves the call as `dropped` (not a deliberate hang-up) and cleans up.
  Future<void> _dropCall() async {
    final call = state.call;
    if (call != null) {
      try {
        await _signaling.markDropped(call.id);
      } catch (e) {
        debugPrint('[Call] markDropped failed: $e');
      }
    }
    await _finish(CallEndReason.failed);
  }

  /// Safety net for two people joining at the same moment: if neither sent
  /// an offer, the higher uid does.
  void _ensurePeer(String uid) {
    Timer(const Duration(milliseconds: 1400), () {
      final me = state.participants[_me];
      if (me?.status != ParticipantStatus.joined) return;
      if (state.participants[uid]?.status != ParticipantStatus.joined) return;
      if (ref.read(webrtcConnectionManagerProvider).peers.containsKey(uid)) return;
      if (_me.compareTo(uid) > 0) _mesh.connectTo(uid, offerer: true);
    });
  }

  void _onMesh(WebRTCMeshState mesh) {
    if (!state.isBusy) return;
    if (mesh.anyConnected) {
      _ringTimer?.cancel();
      _connectWatchdog?.cancel();
      _reconnectWatchdog?.cancel();
      final call = state.call;
      if (!_nativeConnectedMarked && call != null) {
        _nativeConnectedMarked = true;
        unawaited(CallKitService.setConnected(_paramsFor(call).id));
      }
      if (state.phase != CallPhase.connected) {
        state = state.copyWith(
          phase: CallPhase.connected,
          connectedAt: state.connectedAt ?? DateTime.now(),
        );
        HapticFeedback.mediumImpact();
      }
    } else if (mesh.anyReconnecting && state.phase == CallPhase.connected) {
      state = state.copyWith(phase: CallPhase.reconnecting);
      _armReconnectWatchdog();
    }
  }

  void _watchNetwork() {
    _netSub?.cancel();
    _netSub = Connectivity().onConnectivityChanged.listen((result) {
      final previous = _lastNet;
      _lastNet = result;
      if (previous == null) return;
      final hasNet = result.any((r) => r != ConnectivityResult.none);
      if (!hasNet) {
        if (state.phase == CallPhase.connected) {
          state = state.copyWith(phase: CallPhase.reconnecting);
          _armReconnectWatchdog();
        }
        return;
      }
      // Restart WebRTC ICE across both offline→online and Wi-Fi↔cellular handovers.
      if (shouldRestartOnConnectivityChange(previous, result)) {
        _netDebounce?.cancel();
        _netDebounce = Timer(const Duration(milliseconds: 700), () => _mesh.restartAll());
      }
    });
  }

  /// Android 12+ hides Bluetooth headsets from the audio router until
  /// "Nearby devices" is allowed. Asked once, never blocks the call.
  Future<void> _askBluetooth() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final status = await Permission.bluetoothConnect.status;
      if (status.isDenied) {
        final after = await Permission.bluetoothConnect.request();
        if (after.isGranted && ref.read(callMediaServiceProvider).localStream != null) {
          unawaited(_media.refreshOutputs());
        }
      }
    } catch (_) {}
  }

  bool? _wakelockOn;

  /// Keeps the phone in step with the call: screen awake for video, screen
  /// off at the ear for audio on the earpiece, ringback while the other side
  /// rings, and system PiP for video.
  void _syncDevice() {
    final media = ref.read(callMediaServiceProvider);
    final busy = state.isBusy;
    final wake = busy && (media.isVideoOn || media.isScreenSharingActive);
    if (_wakelockOn != wake) {
      _wakelockOn = wake;
      (wake ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((_) {});
    }
    CallPipService.setWakeScreen(state.phase == CallPhase.incoming || busy);
    CallPipService.setProximity(
      busy && media.localStream != null && !media.isVideoOn && !media.isScreenSharingActive && media.audioRoute == AudioRoute.earpiece,
    );
    CallPipService.setRingback(state.phase == CallPhase.outgoing && state.call != null);
    final inCall = state.phase == CallPhase.connected || state.phase == CallPhase.reconnecting;
    final mesh = ref.read(webrtcConnectionManagerProvider);
    final remoteVideo = state.remoteParticipants.any(
          (p) => p.status == ParticipantStatus.joined && !p.isVideoMuted,
        ) ||
        mesh.peers.values.any((p) => p.hasRemoteVideo);
    CallPipService.setAutoEnter(inCall && (media.isVideoOn || remoteVideo) && !media.isScreenSharingActive);
  }

  Future<void> _finish(CallEndReason reason, {bool remote = false, bool silent = false}) async {
    if (_finishing) return;
    _finishing = true;
    _nativeConnectedMarked = false;
    final call = state.call;
    _ringTimer?.cancel();
    _netDebounce?.cancel();
    _connectWatchdog?.cancel();
    _reconnectWatchdog?.cancel();
    _netSub?.cancel();
    _netSub = null;
    _lastNet = null;
    _callSub?.cancel();
    _participantsSub?.cancel();
    _callSub = null;
    _participantsSub = null;

    // Missed incoming call: leave a native missed-call notification.
    if (call != null && state.phase == CallPhase.incoming && remote && !silent) {
      await CallKitService.showMissed(_paramsFor(call));
    }
    if (call != null) await CallKitService.end(_paramsFor(call).id);

    await _mesh.leaveMesh();
    await _media.disposeMedia();
    _finishing = false;

    // Releases background media muting so reels/audio resume smoothly
    ref.read(videoPlaybackManagerProvider).setCallActive(false);

    state = ActiveCallState(
      phase: CallPhase.ended,
      call: call,
      participants: state.participants,
      connectedAt: state.connectedAt,
      endedAt: DateTime.now(),
      endReason: reason,
      errorMessage: state.errorMessage,
    );
    _resetTimer?.cancel();
    // An unanswered outgoing call stays on screen a little longer so the
    // caller can tap "Call again".
    final hold = silent ? 300 : (state.canRedial ? 5000 : 1500);
    _resetTimer = Timer(Duration(milliseconds: hold), () {
      if (state.phase == CallPhase.ended) state = const ActiveCallState();
    });
  }

  void _cancelSubs() {
    ref.read(videoPlaybackManagerProvider).setCallActive(false);
    _callSub?.cancel();
    _participantsSub?.cancel();
    _netSub?.cancel();
    _ringTimer?.cancel();
    _resetTimer?.cancel();
    _netDebounce?.cancel();
    _connectWatchdog?.cancel();
    _reconnectWatchdog?.cancel();
  }
}
