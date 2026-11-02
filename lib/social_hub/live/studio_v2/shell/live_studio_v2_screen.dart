import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import '../../../../backend/live_studio/contracts/studio_ports.dart';
import '../../../../backend/live_studio/layout/layout.dart';
import '../../../../backend/live_studio/media/livekit_studio_room.dart';
import '../../../../backend/live_studio/media/studio_media_api.dart';
import '../../../../backend/live_studio/media/studio_video_view.dart';
import '../../../../backend/live_studio/roles/studio_roles_api.dart' show StudioConfirmPrompt;
import '../../../../backend/live_studio/roles/studio_request_queue_controller.dart';
import '../../../../backend/live_studio/session/studio_session_controller.dart';
import '../../../../backend/live_studio/settings/studio_settings_controller.dart';
import '../../../../backend/live_studio/social/studio_counts_controller.dart';
import '../../../../backend/live_studio/social/studio_reactions_controller.dart';
import '../../../../backend/live_studio/social/studio_share_service.dart';
import '../gaming/gaming.dart';
import '../geometry/geometry.dart';
import '../join/join.dart';
import '../security/live_health_sheet.dart';
import '../security/security_advisory_banner.dart';
import '../settings/host_settings_sheet.dart';
import '../stage/stage.dart';
import '../table/table.dart';
import '../theme/live_studio_tokens.dart';
import '../../../../backend/live_studio/fun/studio_fun.dart';
import '../fun/fun_overlays.dart';
import '../fun/gifts_ui.dart';
import '../fun/live_control_hub.dart';
import '../fun/recording_decision_card.dart';
import 'live_session_status.dart';
import 'shell_widgets.dart';
import 'stage_panel_grid.dart';
import '../watch/watch_layer.dart';
import '../watch/watch_picker_sheet.dart';
import '../../../../backend/live_studio/watch/studio_watch.dart' show WatchKind, studioWatchProvider;
import '../../../../backend/live_studio/pool/studio_pool.dart';
import '../pool/live_pool_layer.dart';
import '../../../../shared/theme/app_theme.dart';

/// The stream doc (`live_streams/{id}`): status / endedReason / host info.
/// Catches server-side endings (sweeper, room closed) even if the room's
/// state.patch was missed during a network drop.
final _liveDocProvider = StreamProvider.autoDispose.family<Map<String, dynamic>?, String>(
    (ref, id) => FirebaseFirestore.instance.collection('live_streams').doc(id).snapshots().map((d) => d.data()));

/// The Live Studio (every live, every host). Route: /live/studio2/:streamId;
/// hosts arrive from the setup wizard (/live/setup), viewers via /live/viewer.
///
/// Composes the workstreams: stage (#3), table (#5), join/moderation (#4),
/// social (#2), settings (#6) on top of the media/session layer (#1).
class LiveStudioV2Screen extends ConsumerStatefulWidget {
  const LiveStudioV2Screen({super.key, required this.streamId});
  final String streamId;

  @override
  ConsumerState<LiveStudioV2Screen> createState() => _LiveStudioV2ScreenState();
}

class _LiveStudioV2ScreenState extends ConsumerState<LiveStudioV2Screen> {
  StudioRoomTab _tab = StudioRoomTab.room;
  LayoutLeader? _leader;
  Timer? _presenceTimer;
  final List<StreamSubscription<Object?>> _mediaSubs = [];
  StudioRoomPort? _boundRoom;
  bool _gameStarting = false;

  /// Host keep-alive (lsHeartbeat) so the server closes orphaned lives.
  Timer? _heartbeat;
  StudioLinkPhase _phase = StudioLinkPhase.connecting;
  bool _connectedOnce = false;

  /// Set when this client saw the live end (host tapped End, or heartbeat
  /// learned the server closed it); value is the end reason.
  String? _endedReason;
  int _peakViewers = 0;

  String get _id => widget.streamId;

  /// Game Live: start the host's screen share (if needed). With [tip], also
  /// shows "Your live keeps going…" (the "Switch to game" button).
  Future<void> _startGame(StudioRoomPort room, {bool tip = false}) async {
    if (_gameStarting) return;
    setState(() => _gameStarting = true);
    try {
      await startGameStreamFlow(context, room, showTip: tip);
    } finally {
      if (mounted) setState(() => _gameStarting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _heartbeat?.cancel();
    _presenceTimer?.cancel();
    _leader?.dispose();
    for (final s in _mediaSubs) {
      s.cancel();
    }
    super.dispose();
  }

  /// Rebuild when tracks publish/mute or speakers change (nameplates, video).
  void _bindRoom(StudioRoomPort room) {
    if (identical(room, _boundRoom)) return;
    for (final s in _mediaSubs) {
      s.cancel();
    }
    _mediaSubs.clear();
    _boundRoom = room;
    if (room is LiveKitStudioRoom && room.isConnected) {
      _connectedOnce = true;
      _phase = StudioLinkPhase.connected;
    }
    _mediaSubs.add(room.quality.listen(_onQuality));
    _mediaSubs.add(room.activeSpeakers.listen((_) => _rebuild()));
    if (room is LiveKitStudioRoom) _mediaSubs.add(room.mediaChanged.listen((_) => _rebuild()));
  }

  bool _rebuildQueued = false;

  /// Media events come in bursts (speakers, stream states, mutes): rebuild
  /// the studio at most once per ~2 frames instead of once per event.
  void _rebuild() {
    if (_rebuildQueued || !mounted) return;
    _rebuildQueued = true;
    Future.delayed(const Duration(milliseconds: 32), () {
      _rebuildQueued = false;
      if (mounted) setState(() {});
    });
  }

  void _onQuality(StudioLinkQuality q) {
    final StudioLinkPhase next;
    if (q == StudioLinkQuality.lost) {
      next = _connectedOnce ? StudioLinkPhase.reconnecting : StudioLinkPhase.connecting;
    } else {
      _connectedOnce = true;
      next = StudioLinkPhase.connected;
    }
    final room = _boundRoom;
    final fatal = room is LiveKitStudioRoom && room.fatalError != null;
    if ((next != _phase || fatal) && mounted) setState(() => _phase = next);
  }

  void _syncHeartbeat(StudioRole role) {
    if (role != StudioRole.host || _endedReason != null) {
      _heartbeat?.cancel();
      _heartbeat = null;
      return;
    }
    if (_heartbeat != null) return;
    unawaited(_beat());
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) => unawaited(_beat()));
  }

  Future<void> _beat() async {
    try {
      final ended = await ref.read(studioMediaApiProvider).heartbeat(_id);
      if (ended && mounted) _markEnded('timeout');
    } catch (_) {
      // Offline: LiveKit keeps reconnecting; the server sweeps after ~90 s.
    }
  }

  void _markEnded(String reason) {
    if (_endedReason != null) return;
    _stopLocalWork();
    if (mounted) setState(() => _endedReason = reason);
  }

  /// Stops everything this screen runs for the live: heartbeat, leader
  /// election, presence polling, wakelock, and the room (camera, mic, screen
  /// share, foreground service). The provider's own dispose is then a no-op.
  void _stopLocalWork() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _leader?.dispose();
    _leader = null;
    unawaited(WakelockPlus.disable());
    final room = _boundRoom;
    if (room != null) unawaited(room.disconnect());
  }

  /// lsEnd in the background: the host is already out. Retries a few times;
  /// if every try fails the server closes the live once heartbeats stop.
  Future<void> _endOnServer() async {
    final api = ref.read(studioMediaApiProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await FirebaseFirestore.instance.collection('live_streams').doc(_id).update({
        'status': 'ended',
        'endedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await api.end(_id).timeout(const Duration(seconds: 12));
        return;
      } catch (_) {
        await Future<void>.delayed(Duration(seconds: 2 << attempt));
      }
    }
    messenger?.showSnackBar(const SnackBar(content: Text('Live session ended.')));
  }

  /// Host / co-hosts run the auto-speaker leader election (ARCHITECTURE §8).
  void _syncLeader(StudioRole role, StudioRoomPort room, StudioState state, Map<String, StageMember> members) {
    final uid = ref.read(studioMyUidProvider);
    if (!role.isManager || uid == null || _endedReason != null) {
      _leader?.dispose();
      _leader = null;
      _presenceTimer?.cancel();
      return;
    }
    _leader ??= LayoutLeader(
      selfUid: uid,
      room: room,
      commands: LayoutCommands(ref.read(studioCallPortProvider), _id),
    );
    _leader!
      ..updateState(state)
      ..updateMembers(members);
    _presenceTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      final r = _boundRoom;
      if (r is LiveKitStudioRoom) _leader?.updatePresence(r.connectedIdentities);
    });
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/hub/home');
    }
  }

  Future<void> _close(StudioRole role, LiveStudioTokens tokens) async {
    if (role == StudioRole.host) {
      final ok = await studioConfirmFor(context, tokens)(const StudioConfirmPrompt(
        title: 'End the live?',
        message: 'Everyone leaves the studio and the live stops for all viewers.',
        confirmLabel: 'End live',
      ));
      if (!ok || !mounted) return;
      HapticFeedback.mediumImpact();
      // Leave at once (camera, mic and screen stop now); the server closes
      // the room and tells the viewers in the background.
      _markEnded('host');
      unawaited(_endOnServer());
      return;
    }
    // Viewers / guests: drop media before the route animates out, so no
    // frozen frame slides away and nothing keeps running behind it.
    _stopLocalWork();
    _leave();
  }

  Widget _endedView(
      StudioRole role, Map<String, dynamic>? doc, StudioState? s, Map<String, StageMember> members, StudioCounts counts) {
    final hostId = (doc?['hostId'] as String?) ?? s?.hostId ?? '';
    final host = members[hostId];
    final created = doc?['createdAt'];
    final endedAt = doc?['endedAt'];
    Duration? duration;
    if (created is Timestamp) {
      final end = endedAt is Timestamp ? endedAt.toDate() : DateTime.now();
      duration = end.difference(created.toDate());
      if (duration.isNegative) duration = null;
    }
    final isHost = role == StudioRole.host || (hostId.isNotEmpty && hostId == ref.read(studioMyUidProvider));
    return Scaffold(
      backgroundColor: LiveStudioTokens.dark.base,
      body: StudioLiveEndedView(
        isHost: isHost,
        hostName: host?.displayName ?? (doc?['hostDisplayName'] as String?) ?? 'The host',
        hostAvatarUrl: host?.avatarUrl ?? (doc?['hostAvatarUrl'] as String?) ?? '',
        reason: _endedReason ?? (doc?['endedReason'] as String?),
        onClose: _leave,
        onViewHost: !isHost && hostId.isNotEmpty ? () => context.push('/profile/$hostId') : null,
        duration: isHost ? duration : null,
        viewers: isHost ? _peakViewers : null,
        loves: isHost ? counts.loves : null,
        extra: isHost ? RecordingDecisionCard(streamId: _id) : null,
      ),
    );
  }

  Future<void> _share(StudioState s) async {
    try {
      await ref.read(studioShareServiceProvider).share(_id, title: s.title);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Could not share this live')));
      }
    }
  }

  void _openPeople(LiveStudioTokens tokens, StudioState s, List<StageMember> members, StudioRole role) {
    setState(() => _tab = StudioRoomTab.people);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: LiveStudioAccent.clear,
      isScrollControlled: true,
      builder: (_) => _ParticipantsSheet(streamId: _id, tokens: tokens, state: s, members: members, myRole: role),
    );
  }

  void _onRoomTab(StudioRoomTab t, LiveStudioTokens tokens, StudioState s, List<StageMember> members, StudioRole role) {
    switch (t) {
      case StudioRoomTab.people:
        _openPeople(tokens, s, members, role);
      case StudioRoomTab.youtube || StudioRoomTab.browser:
        if (!role.isManager) return;
        showWatchTogetherSheet(context,
            streamId: _id, tokens: tokens, initial: t == StudioRoomTab.youtube ? WatchKind.youtube : WatchKind.browser);
      default:
        setState(() => _tab = t);
    }
  }

  void _openDrawer(LiveStudioTokens tokens, StudioState s, List<StageMember> members, StudioRole role) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: LiveStudioAccent.clear,
      barrierColor: LiveStudioTokens.dimTint(0.35),
      isScrollControlled: true,
      builder: (ctx) => _LiveFeaturesDrawer(
        streamId: _id,
        tokens: tokens,
        role: role,
        tab: _tab,
        participants: ref.read(studioCountsProvider(_id)).participants,
        onTab: (t) {
          Navigator.of(ctx).pop();
          _onRoomTab(t, tokens, s, members, role);
        },
        room: _boundRoom,
        gaming: s.isGaming,
        onSwitchToGame: s.isGaming && role == StudioRole.host && _boundRoom != null
            ? () {
                Navigator.of(ctx).pop();
                _startGame(_boundRoom!, tip: true);
              }
            : null,
      ),
    );
  }

  /// Game Live camera bubble content: host camera, or the avatar when off.
  Widget _hostPip(StudioRoomPort room, StageMember? host) {
    final cam = host != null && host.camOn ? room.cameraOf(host.uid) : null;
    final avatar = Center(
      child: StudioAvatar(
        name: host?.displayName ?? '',
        url: host?.avatarUrl ?? '',
        size: 72,
        fill: LiveStudioWorld.surface3,
      ),
    );
    return cam == null ? avatar : StudioVideoView(cam, placeholder: avatar);
  }

  @override
  Widget build(BuildContext context) {
    final geometryAsync = ref.watch(studioGeometryProvider);
    final stateAsync = ref.watch(studioSessionProvider(_id));
    final room = ref.watch(studioRoomProvider(_id));
    _bindRoom(room);
    final role = ref.watch(studioMyRoleProvider(_id)).value ?? StudioRole.viewer;
    final membersList = ref.watch(studioMembersProvider(_id)).value ?? const <StageMember>[];
    final members = {for (final m in membersList) m.uid: m};
    // Keep the social controllers alive for the whole screen.
    ref.watch(studioReactionsProvider(_id).select((s) => s.loves));

    final geometry = geometryAsync.value;
    final base = stateAsync.value;
    final doc = ref.watch(_liveDocProvider(_id)).value;
    final counts = ref.watch(studioCountsProvider(_id));
    if (counts.viewers > _peakViewers) _peakViewers = counts.viewers;
    if (_endedReason != null || doc?['status'] == 'ended' || base?.status == StudioStatus.ended) {
      if (_endedReason == null) {
        // Ended elsewhere (host, sweeper): release media now, not on pop.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _markEnded((doc?['endedReason'] as String?) ?? 'host');
        });
      }
      return _endedView(role, doc, base, members, counts);
    }
    final fatal = room is LiveKitStudioRoom ? room.fatalError : null;
    if (fatal != null && role != StudioRole.host && (doc == null || doc['status'] != 'live')) {
      // Cannot join (followers-only, blocked…): say why instead of spinning.
      final msg = fatal is FirebaseFunctionsException ? fatal.message : null;
      return Scaffold(backgroundColor: LiveStudioTokens.dark.base, body: _Unavailable(streamId: _id, onClose: _leave, message: msg));
    }

    final effectiveBase = base ?? (doc != null && doc['status'] == 'live' ? StudioState(
      schemaVersion: 1,
      streamId: _id,
      hostId: (doc['hostId'] as String?) ?? '',
      title: (doc['title'] as String?) ?? 'Live Studio',
      status: StudioStatus.live,
      seq: 0,
      settings: const StudioSettings(),
      stage: StageLayout(
        centerUid: (doc['hostId'] as String?) ?? '',
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        updatedBy: (doc['hostId'] as String?) ?? '',
      ),
      table: const TableState(),
      counts: const StudioCounts(viewers: 1),
    ) : null);

    if (geometry == null || effectiveBase == null) {
      return Scaffold(
        backgroundColor: LiveStudioTokens.dark.base,
        body: Center(
          child: ((stateAsync.hasError && (doc == null || doc['status'] != 'live')) || geometryAsync.hasError)
              ? _Unavailable(streamId: _id, onClose: _leave)
              : const CircularProgressIndicator(color: LiveStudioAccent.pink),
        ),
      );
    }

    // The host previews unsaved setting edits immediately.
    final state = role == StudioRole.host
        ? effectiveBase.copyWith(settings: ref.watch(studioPreviewSettingsProvider(_id)))
        : effectiveBase;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncLeader(role, room, effectiveBase, members);
      _syncHeartbeat(role);
    });
    final tokens = LiveStudioTokens.forTheme(state.settings.theme);

    return Scaffold(
      backgroundColor: tokens.base,
      resizeToAvoidBottomInset: false,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: state.settings.theme == StudioTheme.light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
        child: LayoutBuilder(builder: (context, box) {
          final viewport = box.biggest;
          final o = viewport.width > viewport.height ? StudioOrientation.landscape : StudioOrientation.phone;
          final studio = geometry.studio(state.settings.studioId);
          final camera = studio.camera(o, viewport);
          var comments = studio.commentsRect(o, state.settings.guestSize, viewport);
          final phone = o == StudioOrientation.phone;
          final host = members[state.hostId];
          final gaming = state.isGaming;
          // More people on stage than the studio world shows: an even grid
          // (1–10) instead, with the comments below / beside it.
          final onStage = state.stage.publishers.toSet().toList();
          final panel = !gaming && onStage.length > studioWorldCapacity(phone: phone);
          final pad = MediaQuery.paddingOf(context);
          final safe = Size(viewport.width - pad.horizontal, viewport.height - pad.vertical);
          // The scaffold does not resize for the keyboard (the stage must not
          // jump); the comment bar and feed lift above it instead.
          final keyboard = (MediaQuery.viewInsetsOf(context).bottom - pad.bottom).clamp(0.0, double.infinity);
          final Rect gridRect;
          if (phone) {
            gridRect = Rect.fromLTWH(6, 58, safe.width - 12, safe.height * 0.6);
            if (panel) comments = Rect.fromLTRB(10, gridRect.bottom + 8, safe.width * 0.78, safe.height - 64);
          } else {
            gridRect = Rect.fromLTRB(24, 84, safe.width * 0.68, safe.height - 108);
            if (panel) comments = Rect.fromLTRB(gridRect.right + 14, 84, safe.width - 112, safe.height - 108);
          }
          final isHost = role == StudioRole.host;
          final VoidCallback? switchToGame = gaming && isHost ? () => _startGame(room, tip: true) : null;

          final world = StudioStage(
            geometry: geometry,
            state: state,
            members: gaming ? gamingStageMembers(members, state.hostId) : members,
            orientation: o,
            isSpeaking: room.isSpeaking,
            isMuted: (uid) => !(members[uid]?.micOn ?? true) || room.isMicMuted(uid),
            showTable: !gaming,
            videoBuilder: (uid, size) {
              if (gaming) {
                return gamingVideoFor(
                  room: room,
                  uid: uid,
                  hostId: state.hostId,
                  renderSize: size,
                  viewerIsHost: isHost,
                  onStartGame: () => _startGame(room),
                  starting: _gameStarting,
                );
              }
              final h = room.cameraOf(uid);
              return h == null ? const SizedBox.shrink() : StudioVideoView(h);
            },
            // Viewers' taps open a local pop-out (ARCHITECTURE Q3);
            // managers swap the tapped guest into the center (broadcast).
            onTileTap: role.isManager
                ? (uid) {
                    final i = state.stage.wallIndexOf(uid);
                    if (i >= 0) LayoutCommands(ref.read(studioCallPortProvider), _id).swap(i);
                  }
                : null,
            tableContent: gaming
                ? null
                : StudioTableContent(
                    streamId: _id,
                    phone: phone,
                    onViewItem: (_) => setState(() => _tab = StudioRoomTab.goods),
                  ),
            popoutContentBuilder: (context, target, size) {
              if (target.isTable) {
                return StudioTableContent(streamId: _id, phone: phone);
              }
              if (gaming && target.uid == state.hostId) {
                final screen = room.tableScreen();
                if (screen != null) return StudioVideoView(screen, fit: BoxFit.contain);
              }
              final h = room.cameraOf(target.uid!);
              return h == null ? const SizedBox.shrink() : StudioVideoView(h, fit: BoxFit.contain);
            },
          );
          final stage = !panel
              ? world
              : ColoredBox(
                  color: tokens.base,
                  child: Stack(children: [
                    Positioned(
                      left: pad.left + gridRect.left,
                      top: pad.top + gridRect.top,
                      width: gridRect.width,
                      height: gridRect.height,
                      child: StagePanelGrid(
                        uids: onStage,
                        members: members,
                        tokens: tokens,
                        phone: phone,
                        hostId: state.hostId,
                        isSpeaking: room.isSpeaking,
                        isMuted: (uid) => !(members[uid]?.micOn ?? true) || room.isMicMuted(uid),
                        videoBuilder: (uid, size) {
                          final h = room.cameraOf(uid);
                          return h == null ? const SizedBox.shrink() : StudioVideoView(h);
                        },
                        onTileTap: role.isManager
                            ? (uid) {
                                if (uid == state.stage.centerUid) return;
                                final i = state.stage.wallIndexOf(uid);
                                final cmd = LayoutCommands(ref.read(studioCallPortProvider), _id);
                                unawaited((i >= 0 ? cmd.swap(i) : cmd.pin(uid)).then((_) {}, onError: (_) {}));
                              }
                            : null,
                      ),
                    ),
                  ]),
                );

          final chrome = phone
              ? _PhoneChrome(
                  streamId: _id,
                  tokens: tokens,
                  state: state,
                  host: host,
                  role: role,
                  camera: camera,
                  comments: comments,
                  keyboard: keyboard,
                  onPeople: () => _openPeople(tokens, state, membersList, role),
                  onClose: () => _close(role, tokens),
                  onShare: () => _share(state),
                  onDrawer: () => _openDrawer(tokens, state, membersList, role),
                  onSwitchToGame: switchToGame,
                )
              : _LandscapeChrome(
                  streamId: _id,
                  tokens: tokens,
                  state: state,
                  host: host,
                  members: membersList,
                  role: role,
                  room: room,
                  comments: comments,
                  keyboard: keyboard,
                  tab: _tab,
                  onTab: (t) => _onRoomTab(t, tokens, state, membersList, role),
                  onPeople: () => _openPeople(tokens, state, membersList, role),
                  onClose: () => _close(role, tokens),
                  onShare: () => _share(state),
                  onSwitchToGame: switchToGame,
                );

          final prefs = ref.watch(studioViewPrefsProvider);
          final broadcasting = doc?['broadcasting'];
          final recOn = broadcasting is Map && broadcasting['recording'] == true;
          final platforms = broadcasting is Map ? (broadcasting['platforms'] as List? ?? const []) : const [];
          return Stack(fit: StackFit.expand, children: [
            Positioned.fill(
              child: DoubleTapLove(
                onLove: () => ref.read(studioReactionsProvider(_id).notifier).tap(ReactionKind.love),
                child: stage,
              ),
            ),
            // Clean view fades the chrome out slowly (and back in).
            Positioned.fill(
              child: IgnorePointer(
                ignoring: prefs.cleanView,
                child: AnimatedOpacity(
                  opacity: prefs.cleanView ? 0 : 1,
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeInOutCubic,
                  child: SafeArea(child: chrome),
                ),
              ),
            ),
            // Watch together (YouTube / browser), above the stage; the host's
            // camera keeps streaming underneath.
            if (!gaming)
              Positioned.fill(
                child: SafeArea(
                  child: StudioWatchLayer(streamId: _id, tokens: tokens, phone: phone, canControl: role.isManager),
                ),
              ),
            Positioned.fill(
              child: SafeArea(child: StudioFunOverlay(streamId: _id, canManage: role.isManager, phone: phone)),
            ),
            Positioned.fill(child: SafeArea(child: StudioGiftOverlay(streamId: _id, phone: phone))),
            // Interactive 8-Ball Pool arena linked to live stage with split camera portions
            Positioned.fill(
              child: Consumer(
                builder: (context, ref, _) {
                  final pool = ref.watch(studioPoolProvider(_id)).value;
                  if (pool == null || pool.isClosed) return const SizedBox.shrink();
                  return LivePoolLayer(
                    streamId: _id,
                    room: room,
                    isHost: isHost,
                  );
                },
              ),
            ),
            Positioned.fill(
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: EdgeInsets.only(top: phone ? 60 : 72, right: 10),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      _ControlsButton(
                        clean: prefs.cleanView,
                        onTap: () => showLiveControlHub(
                          context,
                          streamId: _id,
                          isHost: role == StudioRole.host,
                          isManager: role.isManager,
                          room: room,
                          onStage: role.canPublish,
                        ),
                        onLongPress: () => ref
                            .read(studioViewPrefsProvider.notifier)
                            .set(prefs.copyWith(cleanView: !prefs.cleanView)),
                      ),
                      if (role != StudioRole.host)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: _GiftButton(onTap: () => showGiftSheet(context, _id)),
                        ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 500),
                        child: recOn || platforms.isNotEmpty
                            ? Padding(
                                key: const ValueKey('rec'),
                                padding: const EdgeInsets.only(top: 8),
                                child: _OnAirBadge(recording: recOn, platforms: platforms.length),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
            Positioned.fill(child: StudioConnectionBanner(phase: _phase)),
            if (gaming) ...[
              if (state.gameTitle case final game?)
                Positioned.fill(
                  child: SafeArea(
                    child: Stack(children: [
                      Positioned(
                        left: phone ? 8 : 24,
                        top: phone ? 58 : 76,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: phone ? 240 : 320),
                          child: NowPlayingPill(tokens: tokens, gameTitle: game, phone: phone),
                        ),
                      ),
                    ]),
                  ),
                ),
              Positioned.fill(
                child: SafeArea(
                  child: GamingPipBubble(
                    key: ValueKey('gaming-pip-${o.name}'),
                    insets: phone
                        ? const EdgeInsets.fromLTRB(10, 100, 10, 70)
                        : const EdgeInsets.fromLTRB(24, 84, 24, 110),
                    label: 'Host camera',
                    child: _hostPip(room, host),
                  ),
                ),
              ),
            ],
          ]);
        }),
      ),
    );
  }
}

/// Opens the Live controls hub; long-press toggles clean view.
class _ControlsButton extends StatelessWidget {
  const _ControlsButton({required this.clean, required this.onTap, required this.onLongPress});
  final bool clean;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Live controls',
        child: GestureDetector(
          onTap: onTap,
          onLongPress: () {
            HapticFeedback.mediumImpact();
            onLongPress();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: LiveStudioWorld.inWindow,
              shape: BoxShape.circle,
              border: Border.all(color: clean ? LiveStudioAccent.pink : LiveStudioWorld.nameplateBorder),
            ),
            child: Icon(clean ? Icons.visibility_rounded : Icons.tune_rounded, size: 20, color: LiveStudioWorld.textHigh),
          ),
        ),
      );
}

/// Opens the gift sheet (viewers, guests, co-hosts).
class _GiftButton extends StatelessWidget {
  const _GiftButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Send a gift',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [LiveStudioAccent.pink, LiveStudioAccent.pinkLight]),
              boxShadow: [BoxShadow(color: LiveStudioAccent.pinkA(0.4), blurRadius: 14)],
            ),
            child: const Icon(Icons.card_giftcard_rounded, size: 20, color: LiveStudioAccent.white),
          ),
        ),
      );
}

/// "REC" / restream indicator while the egress runs.
class _OnAirBadge extends StatelessWidget {
  const _OnAirBadge({required this.recording, required this.platforms});
  final bool recording;
  final int platforms;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: LiveStudioWorld.inWindow, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (recording) ...[
            const Icon(Icons.fiber_manual_record_rounded, size: 10, color: LiveStudioAccent.liveRed),
            const SizedBox(width: 4),
            Text('REC', style: LiveStudioType.s(10, FontWeight.w900, LiveStudioWorld.textHigh)),
          ],
          if (recording && platforms > 0) const SizedBox(width: 6),
          if (platforms > 0) ...[
            const Icon(Icons.cell_tower_rounded, size: 11, color: LiveStudioAccent.pink),
            const SizedBox(width: 3),
            Text('$platforms', style: LiveStudioType.s(10, FontWeight.w900, LiveStudioWorld.textHigh)),
          ],
        ]),
      );
}

// ─── Landscape chrome ────────────────────────────────────────────────────────

class _LandscapeChrome extends ConsumerWidget {
  const _LandscapeChrome({
    required this.streamId,
    required this.tokens,
    required this.state,
    required this.host,
    required this.members,
    required this.role,
    required this.room,
    required this.comments,
    this.keyboard = 0,
    required this.tab,
    required this.onTab,
    required this.onPeople,
    required this.onClose,
    required this.onShare,
    this.onSwitchToGame,
  });

  final String streamId;
  final LiveStudioTokens tokens;
  final StudioState state;
  final StageMember? host;
  final List<StageMember> members;
  final StudioRole role;
  final StudioRoomPort room;
  final Rect comments;

  /// Keyboard height over the safe area (0 when hidden).
  final double keyboard;
  final StudioRoomTab tab;
  final ValueChanged<StudioRoomTab> onTab;
  final VoidCallback onPeople;
  final VoidCallback onClose;
  final VoidCallback onShare;

  /// Game Live host only.
  final VoidCallback? onSwitchToGame;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tokens;
    final counts = ref.watch(studioCountsProvider(streamId));
    final pending = role.isManager ? ref.watch(studioPendingRequestCountProvider(streamId)) : 0;
    final reactions = ref.watch(studioReactionsProvider(streamId));
    final stageMembers = [for (final uid in state.stage.publishers) if (members.any((m) => m.uid == uid)) members.firstWhere((m) => m.uid == uid)];
    return Stack(children: [
      // Header
      Positioned(
        left: 24,
        right: 24,
        top: 16,
        child: SizedBox(
          height: 56,
          child: Row(children: [
            Flexible(child: HostCard(tokens: t, streamId: streamId, title: state.title, host: host, phone: false)),
            const Spacer(),
            if (!state.isGaming) ...[
              TableModePicker(streamId: streamId, kind: TableModePickerKind.capsule, tokens: t),
              const Spacer(),
            ],
            ParticipantsStack(tokens: t, members: stageMembers, count: counts.participants, onTap: onPeople),
            const SizedBox(width: 8),
            if (role.isManager)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: StudioRoundButton(
                  tokens: t,
                  icon: Icons.person_add_alt,
                  label: 'Join requests, $pending',
                  fill: t.ghostFill,
                  color: t.textMedium,
                  onTap: () => showJoinRequestQueueSheet(context, streamId: streamId, tokens: t),
                  badge: pending > 0 ? _CountBadge(count: pending) : null,
                ),
              )
            else ...[
              RequestToJoinButton(streamId: streamId, tokens: t),
              const SizedBox(width: 8),
            ],
            StudioRoundButton(tokens: t, icon: Icons.ios_share, label: 'Share', color: t.textMedium, onTap: onShare),
            const SizedBox(width: 8),
            StudioRoundButton(
              tokens: t,
              icon: Icons.close,
              label: role == StudioRole.host ? 'End live' : 'Leave live',
              color: t.textMedium,
              onTap: onClose,
            ),
          ]),
        ),
      ),
      // Security advisories (host / co-hosts only; renders nothing otherwise).
      Positioned(
        top: 84,
        left: 0,
        right: 0,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SecurityAdvisoryBanner(streamId: streamId, role: role, tokens: t),
          ),
        ),
      ),
      // Comments — never over a screen (geometry-checked rect).
      Positioned.fromRect(rect: comments, child: CommentFeed(streamId: streamId, tokens: t)),
      // Love column
      Positioned(
        right: 24,
        bottom: 96,
        width: 76,
        height: 226,
        child: Stack(children: [
          Positioned.fill(child: FloatingHearts(streamId: streamId)),
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              StudioRoundButton(
                tokens: t,
                icon: Icons.favorite,
                label: 'Show love',
                size: 56,
                iconSize: 26,
                fill: LiveStudioAccent.pinkA(0.15),
                border: LiveStudioAccent.pink,
                color: LiveStudioAccent.pink,
                shadow: [BoxShadow(color: LiveStudioAccent.pinkA(0.35), blurRadius: 20)],
                onTap: () => ref.read(studioReactionsProvider(streamId).notifier).tap(ReactionKind.love),
              ),
              const SizedBox(height: 6),
              Text('SHOW LOVE', style: LiveStudioType.s(10, FontWeight.w600, t.textHigh, height: 14, letter: 0.06)),
              if (reactions.myLoves > 0)
                Text('+${reactions.myLoves}', style: LiveStudioType.s(12, FontWeight.w600, LiveStudioAccent.pink, height: 16)),
            ]),
          ),
        ]),
      ),
      // Bottom: controls · room tabs · comment bar
      Positioned(
        left: 24,
        right: 24,
        bottom: 26 + keyboard,
        child: SizedBox(
          height: 68,
          child: Row(children: [
            _ControlsGroup(streamId: streamId, tokens: t, state: state, role: role, room: room, onSwitchToGame: onSwitchToGame),
            const SizedBox(width: 12),
            Flexible(
              child: GlassBox(
                tokens: t,
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final d in studioTabsFor(role))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: RoomTabButton(
                          def: d,
                          tokens: t,
                          active: tab == d.tab,
                          onTap: () => onTab(d.tab),
                          count: d.tab == StudioRoomTab.people ? counts.participants : null,
                        ),
                      ),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: CommentBar(streamId: streamId, tokens: t, phone: false)),
          ]),
        ),
      ),
    ]);
  }
}

/// Mic · camera · S/M/L · Share-to-table (+ host settings).
class _ControlsGroup extends ConsumerWidget {
  const _ControlsGroup({required this.streamId, required this.tokens, required this.state, required this.role, required this.room, this.onSwitchToGame});
  final String streamId;
  final LiveStudioTokens tokens;
  final StudioState state;
  final StudioRole role;
  final StudioRoomPort room;
  final VoidCallback? onSwitchToGame;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tokens;
    final me = ref.watch(studioMyUidProvider) ?? '';
    final members = ref.watch(studioMembersProvider(streamId)).value ?? const <StageMember>[];
    StageMember? self;
    for (final m in members) {
      if (m.uid == me) self = m;
    }
    final micOn = self?.micOn ?? false;
    final camOn = self?.camOn ?? false;
    final size = state.settings.guestSize;
    return GlassBox(
      tokens: t,
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (role.canPublish) ...[
          _MediaToggle(tokens: t, on: micOn, onIcon: Icons.mic, offIcon: Icons.mic_off, onLabel: 'Mute microphone', offLabel: 'Unmute microphone', onTap: () => room.setMicEnabled(!micOn)),
          _MediaToggle(tokens: t, on: camOn, onIcon: Icons.videocam, offIcon: Icons.videocam_off, onLabel: 'Turn camera off', offLabel: 'Turn camera on', onTap: () => room.setCameraEnabled(!camOn)),
        ],
        if (role == StudioRole.host) ...[
          const SizedBox(width: 6),
          Semantics(
            container: true,
            label: 'Guest window size',
            child: Container(
              height: 44,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: t.ghostFill,
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(color: t.ghostBorder),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.view_column_outlined, size: 16, color: t.textMedium),
                ),
                for (final g in GuestSize.values)
                  _SizeChip(
                    tokens: t,
                    label: g.wire.toUpperCase(),
                    semantics: '${const {'s': 'Small', 'm': 'Medium', 'l': 'Large'}[g.wire]} guest windows',
                    active: g == size,
                    onTap: () => ref.read(studioSettingsControllerProvider(streamId).notifier).setGuestSize(g),
                  ),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          StudioRoundButton(
            tokens: t,
            icon: Icons.tune,
            label: 'Studio settings',
            color: t.textMedium,
            onTap: () => showHostSettingsSheet(context, streamId: streamId),
          ),
        ],
        if (role.isManager)
          StudioRoundButton(
            tokens: t,
            icon: Icons.health_and_safety_outlined,
            label: 'Live health',
            color: t.textMedium,
            onTap: () => showLiveHealthSheet(context, streamId: streamId, tokens: t),
          ),
        const SizedBox(width: 6),
        if (!state.isGaming)
          ShareToTableButton(streamId: streamId, tokens: t)
        else if (onSwitchToGame != null)
          SwitchToGameButton(tokens: t, onTap: onSwitchToGame),
      ]),
    );
  }
}

class _MediaToggle extends StatelessWidget {
  const _MediaToggle({required this.tokens, required this.on, required this.onIcon, required this.offIcon, required this.onLabel, required this.offLabel, required this.onTap});
  final LiveStudioTokens tokens;
  final bool on;
  final IconData onIcon;
  final IconData offIcon;
  final String onLabel;
  final String offLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: StudioRoundButton(
          tokens: tokens,
          icon: on ? onIcon : offIcon,
          label: on ? onLabel : offLabel,
          fill: on ? tokens.ghostFill : LiveStudioAccent.redA(0.14),
          border: on ? tokens.ghostBorder : LiveStudioAccent.redA(0.6),
          color: on ? tokens.textHigh : LiveStudioAccent.liveRed,
          onTap: onTap,
        ),
      );
}

class _SizeChip extends StatelessWidget {
  const _SizeChip({required this.tokens, required this.label, required this.semantics, required this.active, required this.onTap});
  final LiveStudioTokens tokens;
  final String label;
  final String semantics;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: active,
        label: semantics,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: LiveStudioMotion.hover,
            width: 34,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? LiveStudioAccent.blue : LiveStudioAccent.clear,
              borderRadius: BorderRadius.circular(9999),
            ),
            child: Text(label,
                style: LiveStudioType.s(12, FontWeight.w700, active ? LiveStudioAccent.white : tokens.textMedium, height: 16)),
          ),
        ),
      );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 18),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: LiveStudioAccent.pink, borderRadius: BorderRadius.circular(9999)),
        child: Text('$count',
            textAlign: TextAlign.center,
            style: LiveStudioType.s(10, FontWeight.w700, LiveStudioAccent.white, height: 14)),
      );
}

// ─── Phone chrome ────────────────────────────────────────────────────────────

class _PhoneChrome extends ConsumerWidget {
  const _PhoneChrome({
    required this.streamId,
    required this.tokens,
    required this.state,
    required this.host,
    required this.role,
    required this.camera,
    required this.comments,
    this.keyboard = 0,
    required this.onPeople,
    required this.onClose,
    required this.onShare,
    required this.onDrawer,
    this.onSwitchToGame,
  });

  final String streamId;
  final LiveStudioTokens tokens;
  final StudioState state;
  final StageMember? host;
  final StudioRole role;
  final StudioCamera camera;
  final Rect comments;

  /// Keyboard height over the safe area (0 when hidden).
  final double keyboard;
  final VoidCallback onPeople;
  final VoidCallback onClose;
  final VoidCallback onShare;
  final VoidCallback onDrawer;

  /// Game Live host only.
  final VoidCallback? onSwitchToGame;

  /// Compact table rail anchor in the phone artboard (SPEC §2: left 32, top 377).
  static const Offset _railAnchor = Offset(32, 377);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tokens;
    final counts = ref.watch(studioCountsProvider(streamId));
    final reactions = ref.watch(studioReactionsProvider(streamId));
    final rail = camera.artboardToUi(_railAnchor);
    final typing = ref.watch(studioComposerOpenProvider);
    final feed = keyboard > 0
        ? Rect.fromLTRB(comments.left, (comments.top - keyboard).clamp(64.0, comments.bottom), comments.right,
            comments.bottom - keyboard)
        : comments;
    return Stack(children: [
      // Header: host card, then compact Join / Participants / Close.
      Positioned(
        left: 8,
        right: 8,
        top: 10,
        child: Row(children: [
          Expanded(child: HostCard(tokens: t, streamId: streamId, title: state.title, host: host, phone: true)),
          const SizedBox(width: 4),
          if (role.isManager)
            StudioRoundButton(
              tokens: t,
              icon: Icons.person_add_alt,
              label: 'Join requests',
              size: 36,
              iconSize: 18,
              fill: t.glass,
              border: t.glassBorderPhone,
              onTap: () => showJoinRequestQueueSheet(context, streamId: streamId, tokens: t),
            )
          else
            RequestToJoinButton(streamId: streamId, tokens: t, compact: true),
          Semantics(
            button: true,
            label: 'Participants, ${counts.participants}',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: onPeople,
              child: SizedBox(
                height: 44,
                child: Center(
                  child: GlassBox(
                    tokens: t,
                    phone: true,
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.group_outlined, size: 16, color: t.textHigh),
                      const SizedBox(width: 3),
                      Text('${counts.participants}',
                          style: LiveStudioType.s(12, FontWeight.w700, t.textHigh, height: 16)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          StudioRoundButton(
            tokens: t,
            icon: Icons.close,
            label: role == StudioRole.host ? 'End live' : 'Leave live',
            size: 36,
            iconSize: 18,
            fill: t.glass,
            border: t.glassBorderPhone,
            onTap: onClose,
          ),
        ]),
      ),
      Positioned(
        top: 64,
        left: 8,
        right: 8,
        child: SecurityAdvisoryBanner(streamId: streamId, role: role, tokens: t),
      ),
      // Compact table rail (also reachable in the drawer). No table on Game Live.
      if (!state.isGaming)
        Positioned(
          left: rail.dx,
          top: rail.dy,
          child: TableModePicker(streamId: streamId, kind: TableModePickerKind.rail, tokens: t),
        ),
      if (feed.height > 40) Positioned.fromRect(rect: feed, child: CommentFeed(streamId: streamId, tokens: t)),
      Positioned(right: 10, bottom: 62, width: 40, height: 150, child: FloatingHearts(streamId: streamId, rise: 130)),
      // Slim bottom bar (while typing: the input alone, full width).
      AnimatedPositioned(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        left: 10,
        right: 10,
        bottom: 12 + keyboard,
        child: SizedBox(
          height: 44,
          child: Row(children: [
            Expanded(child: CommentBar(streamId: streamId, tokens: t, phone: true)),
            if (!typing) ...[
            const SizedBox(width: 5),
            if (!state.isGaming)
              ShareToTableButton(streamId: streamId, tokens: t, variant: ShareToTableVariant.phone)
            else if (onSwitchToGame != null)
              SwitchToGameButton(tokens: t, onTap: onSwitchToGame, compact: true),
            StudioRoundButton(
              tokens: t,
              icon: Icons.ios_share,
              label: 'Share this live',
              size: 40,
              iconSize: 18,
              fill: t.glass,
              border: t.glassBorderPhone,
              onTap: onShare,
            ),
            StudioRoundButton(
              tokens: t,
              icon: Icons.widgets_outlined,
              label: 'Live features',
              size: 40,
              iconSize: 18,
              fill: t.glass,
              border: t.glassBorderPhone,
              onTap: onDrawer,
              badge: Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 10, right: 8),
                decoration: BoxDecoration(
                  color: LiveStudioAccent.pink,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.ringOnGlass, width: 2),
                ),
              ),
            ),
            StudioRoundButton(
              tokens: t,
              icon: Icons.favorite,
              label: 'Show love',
              size: 40,
              iconSize: 20,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [LiveStudioAccent.pink, LiveStudioAccent.pinkLight],
              ),
              shadow: [BoxShadow(color: LiveStudioAccent.pinkA(0.45), blurRadius: 18, offset: const Offset(0, 6))],
              color: LiveStudioAccent.white,
              onTap: () => ref.read(studioReactionsProvider(streamId).notifier).tap(ReactionKind.love),
              badge: reactions.myLoves > 0
                  ? Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: LiveStudioAccent.white,
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Text('${reactions.myLoves}',
                          textAlign: TextAlign.center,
                          style: LiveStudioType.s(10, FontWeight.w700, LiveStudioAccent.pink, height: 14)),
                    )
                  : null,
            ),
            ],
          ]),
        ),
      ),
    ]);
  }
}

/// Phone "Live features" drawer: table modes, room tabs, controls.
class _LiveFeaturesDrawer extends ConsumerWidget {
  const _LiveFeaturesDrawer({
    required this.streamId,
    required this.tokens,
    required this.role,
    required this.tab,
    required this.participants,
    required this.onTab,
    required this.room,
    this.gaming = false,
    this.onSwitchToGame,
  });

  final String streamId;
  final LiveStudioTokens tokens;
  final StudioRole role;
  final StudioRoomTab tab;
  final int participants;
  final ValueChanged<StudioRoomTab> onTab;
  final StudioRoomPort? room;

  /// Game Live: no table section; the host gets "Switch to game".
  final bool gaming;
  final VoidCallback? onSwitchToGame;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tokens;
    final watching = ref.watch(studioWatchProvider(streamId)).value?.kind;
    return _DrawerFrame(
      tokens: t,
      title: 'Live features',
      children: [
        if (!gaming) ...[
          Text('On the table', style: LiveStudioType.s(12, FontWeight.w600, t.textMedium, height: 16)),
          const SizedBox(height: 6),
          TableModePicker(streamId: streamId, kind: TableModePickerKind.grid, tokens: t),
          const SizedBox(height: 8),
          if (role.isManager)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 38),
                  side: const BorderSide(color: AppColors.brandPink),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.sports_baseball, size: 16, color: AppColors.brandPink),
                label: const Text('Open 8-Ball Pool Arena', style: TextStyle(color: AppColors.brandPink, fontWeight: FontWeight.w700, fontSize: 13)),
                onPressed: () {
                  Navigator.of(context).pop();
                  ref.read(studioPoolApiProvider).openMatch(streamId, bestOf: 1);
                },
              ),
            ),
          const SizedBox(height: 12),
        ],
        Text('Room', style: LiveStudioType.s(12, FontWeight.w600, t.textMedium, height: 16)),
        const SizedBox(height: 6),
        Row(children: [
          for (final d in studioTabsFor(role))
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _DrawerTab(
                  def: d,
                  tokens: t,
                  active: d.tab == tab,
                  count: d.tab == StudioRoomTab.people ? participants : null,
                  // Dot: this is what everyone is watching right now.
                  dot: (d.tab == StudioRoomTab.youtube && watching == WatchKind.youtube) ||
                      (d.tab == StudioRoomTab.browser && watching == WatchKind.browser),
                  onTap: () => onTab(d.tab),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (role.canPublish && room != null) ...[
            StudioRoundButton(tokens: t, icon: Icons.mic_none, label: 'Microphone', fill: LiveStudioAccent.clear, border: LiveStudioAccent.clear, color: t.textMedium,
                onTap: () => room!.setMicEnabled(!(ref.read(studioMembersProvider(streamId)).value?.any((m) => m.uid == ref.read(studioMyUidProvider) && m.micOn) ?? false))),
            StudioRoundButton(tokens: t, icon: Icons.videocam_outlined, label: 'Camera', fill: LiveStudioAccent.clear, border: LiveStudioAccent.clear, color: t.textMedium,
                onTap: () => room!.setCameraEnabled(!(ref.read(studioMembersProvider(streamId)).value?.any((m) => m.uid == ref.read(studioMyUidProvider) && m.camOn) ?? false))),
          ],
          if (!gaming)
            ShareToTableButton(streamId: streamId, tokens: t, variant: ShareToTableVariant.drawer)
          else if (onSwitchToGame != null)
            SwitchToGameButton(tokens: t, onTap: onSwitchToGame, compact: true),
          if (role.isManager)
            StudioRoundButton(tokens: t, icon: Icons.health_and_safety_outlined, label: 'Live health', fill: LiveStudioAccent.clear, border: LiveStudioAccent.clear, color: t.textMedium,
                onTap: () {
                  Navigator.of(context).pop();
                  showLiveHealthSheet(context, streamId: streamId, tokens: t);
                }),
          if (role == StudioRole.host)
            StudioRoundButton(tokens: t, icon: Icons.tune, label: 'Studio settings', fill: LiveStudioAccent.clear, border: LiveStudioAccent.clear, color: t.textMedium,
                onTap: () {
                  Navigator.of(context).pop();
                  showHostSettingsSheet(context, streamId: streamId);
                }),
        ]),
      ],
    );
  }
}

class _DrawerTab extends StatelessWidget {
  const _DrawerTab({required this.def, required this.tokens, required this.active, required this.onTap, this.count, this.dot = false});
  final StudioTabDef def;
  final LiveStudioTokens tokens;
  final bool active;
  final VoidCallback onTap;
  final int? count;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Semantics(
      button: true,
      selected: active,
      label: count != null ? '${def.label}, $count' : def.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 84,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: active ? t.activeFill : LiveStudioAccent.clear,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? LiveStudioAccent.pink : LiveStudioAccent.clear),
          ),
          child: Stack(clipBehavior: Clip.none, children: [
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(def.icon, size: 20, color: active ? LiveStudioAccent.pink : t.textMedium),
              const SizedBox(height: 6),
              Text(def.short,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: LiveStudioType.s(11, FontWeight.w600, active ? t.textHigh : t.textMedium, height: 13)),
            ]),
            if (count != null)
              Positioned(
                top: -3,
                right: -1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: LiveStudioAccent.blue, borderRadius: BorderRadius.circular(9999)),
                  child: Text('$count', style: LiveStudioType.s(10, FontWeight.w600, LiveStudioAccent.white, height: 13)),
                ),
              )
            else if (dot)
              Positioned(
                top: 0,
                right: 2,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: LiveStudioAccent.pink,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: LiveStudioAccent.pinkA(0.6), blurRadius: 8)],
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _DrawerFrame extends StatelessWidget {
  const _DrawerFrame({required this.tokens, required this.title, required this.children});
  final LiveStudioTokens tokens;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 22 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [t.drawerTop, t.drawerBottom],
          stops: const [0, 0.55],
        ),
        border: Border(top: BorderSide(color: t.drawerBorder)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: t.textDim, borderRadius: BorderRadius.circular(9999)),
          ),
        ),
        Row(children: [
          Expanded(child: Text(title, style: LiveStudioType.s(16, FontWeight.w700, t.textHigh, height: 20))),
          StudioRoundButton(
            tokens: t,
            icon: Icons.close,
            label: 'Close',
            fill: LiveStudioAccent.clear,
            border: LiveStudioAccent.clear,
            color: t.textMedium,
            onTap: () => Navigator.of(context).pop(),
          ),
        ]),
        ...children,
      ]),
    );
  }
}

/// Participants: on stage (with host actions) and overflow; managers also
/// see pending join requests.
class _ParticipantsSheet extends ConsumerWidget {
  const _ParticipantsSheet({required this.streamId, required this.tokens, required this.state, required this.members, required this.myRole});
  final String streamId;
  final LiveStudioTokens tokens;
  final StudioState state;
  final List<StageMember> members;
  final StudioRole myRole;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tokens;
    final me = ref.watch(studioMyUidProvider) ?? '';
    final onStage = state.stage.publishers.toSet();
    final sorted = [...members]..sort((a, b) {
        final sa = onStage.contains(a.uid) ? 0 : 1, sb = onStage.contains(b.uid) ? 0 : 1;
        return sa != sb ? sa - sb : a.joinedAtMs.compareTo(b.joinedAtMs);
      });
    return _DrawerFrame(
      tokens: t,
      title: 'Participants',
      children: [
        if (myRole.isManager)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StudioPillButton(
              label: 'Join requests (${ref.watch(studioPendingRequestCountProvider(streamId))})',
              icon: Icons.person_add_alt,
              onTap: () => showJoinRequestQueueSheet(context, streamId: streamId, tokens: t),
              fill: LiveStudioAccent.blueA(0.16),
              border: LiveStudioAccent.blueA(0.5),
              textColor: t.shareToTableText,
            ),
          ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
          child: ListView(shrinkWrap: true, children: [
            for (final m in sorted)
              SizedBox(
                height: 56,
                child: Row(children: [
                  StudioAvatar(name: m.displayName, url: m.avatarUrl, size: 36, fill: studioHex(m.accent, fallback: LiveStudioAccent.blue)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: LiveStudioType.s(14, FontWeight.w600, t.textHigh, height: 18)),
                      Text(
                        [
                          switch (m.role) { StudioRole.host => 'Host', StudioRole.coHost => 'Co-host', StudioRole.guest => 'Guest', StudioRole.viewer => 'Viewer' },
                          if (onStage.contains(m.uid)) (state.stage.overflow.contains(m.uid) ? 'Waiting to rotate in' : 'On stage'),
                          if (!m.micOn) 'Muted',
                        ].join(' · '),
                        style: LiveStudioType.s(12, FontWeight.w400, t.textMedium, height: 16),
                      ),
                    ]),
                  ),
                  ParticipantRowActions(
                    streamId: streamId,
                    member: m,
                    myUid: me,
                    myRole: myRole,
                    onStage: onStage.contains(m.uid),
                    tokens: t,
                  ),
                ]),
              ),
          ]),
        ),
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onClose, this.message, this.streamId});
  final VoidCallback onClose;
  final String? message;
  final String? streamId;

  @override
  Widget build(BuildContext context) {
    const t = LiveStudioTokens.dark;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, size: 40, color: t.textMedium),
        const SizedBox(height: 12),
        Text('This live is unavailable', style: LiveStudioType.s(17, FontWeight.w700, t.textHigh)),
        if (message != null && message!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message!, textAlign: TextAlign.center, style: LiveStudioType.s(13, FontWeight.w500, t.textMedium)),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StudioPillButton(
              label: 'Back',
              icon: Icons.arrow_back,
              onTap: onClose,
              fill: LiveStudioTokens.dark.ghostFill,
              textColor: LiveStudioAccent.white,
            ),
            if (streamId != null && streamId!.isNotEmpty) ...[
              const SizedBox(width: 12),
              StudioPillButton(
                label: 'Classic Live',
                icon: Icons.videocam,
                onTap: () => context.go('/live/viewer/$streamId'),
                fill: LiveStudioAccent.blue,
                textColor: LiveStudioAccent.white,
              ),
            ],
          ],
        ),
      ]),
    );
  }
}
