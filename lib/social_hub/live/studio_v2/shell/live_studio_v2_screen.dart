import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import '../../../../backend/live_studio/contracts/studio_ports.dart';
import '../../../../backend/live_studio/layout/layout.dart';
import '../../../../backend/live_studio/media/livekit_studio_room.dart';
import '../../../../backend/live_studio/media/studio_video_view.dart';
import '../../../../backend/live_studio/roles/studio_moderation_controller.dart';
import '../../../../backend/live_studio/roles/studio_request_queue_controller.dart';
import '../../../../backend/live_studio/session/studio_session_controller.dart';
import '../../../../backend/live_studio/settings/studio_settings_controller.dart';
import '../../../../backend/live_studio/social/studio_counts_controller.dart';
import '../../../../backend/live_studio/social/studio_reactions_controller.dart';
import '../../../../backend/live_studio/social/studio_share_service.dart';
import '../geometry/geometry.dart';
import '../join/join.dart';
import '../security/live_health_sheet.dart';
import '../security/security_advisory_banner.dart';
import '../settings/host_settings_sheet.dart';
import '../stage/stage.dart';
import '../table/table.dart';
import '../theme/live_studio_tokens.dart';
import 'shell_widgets.dart';

/// Live Studio v2 (feature flag `live_studio_v2`). Route: /live/studio2/:streamId.
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

  String get _id => widget.streamId;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
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
    _mediaSubs.add(room.activeSpeakers.listen((_) => _rebuild()));
    if (room is LiveKitStudioRoom) _mediaSubs.add(room.mediaChanged.listen((_) => _rebuild()));
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// Host / co-hosts run the auto-speaker leader election (ARCHITECTURE §8).
  void _syncLeader(StudioRole role, StudioRoomPort room, StudioState state, Map<String, StageMember> members) {
    final uid = ref.read(studioMyUidProvider);
    if (!role.isManager || uid == null) {
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
      final ended = await ref
          .read(studioModerationControllerProvider(_id).notifier)
          .endLive(confirm: studioConfirmFor(context, tokens));
      if (!ended) return;
    }
    if (mounted) _leave();
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
          if (t == StudioRoomTab.people) {
            _openPeople(tokens, s, members, role);
          } else {
            setState(() => _tab = t);
          }
        },
        room: _boundRoom,
      ),
    );
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
    if (geometry == null || base == null) {
      return Scaffold(
        backgroundColor: LiveStudioTokens.dark.base,
        body: Center(
          child: stateAsync.hasError || geometryAsync.hasError
              ? _Unavailable(onClose: _leave)
              : const CircularProgressIndicator(color: LiveStudioAccent.pink),
        ),
      );
    }
    if (base.status == StudioStatus.ended) {
      return Scaffold(backgroundColor: LiveStudioTokens.dark.base, body: _Unavailable(onClose: _leave, ended: true));
    }

    // The host previews unsaved setting edits immediately.
    final state = role == StudioRole.host
        ? base.copyWith(settings: ref.watch(studioPreviewSettingsProvider(_id)))
        : base;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncLeader(role, room, base, members);
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
          final comments = studio.commentsRect(o, state.settings.guestSize, viewport);
          final phone = o == StudioOrientation.phone;
          final host = members[state.hostId];

          final stage = StudioStage(
            geometry: geometry,
            state: state,
            members: members,
            orientation: o,
            isSpeaking: room.isSpeaking,
            isMuted: (uid) => !(members[uid]?.micOn ?? true) || room.isMicMuted(uid),
            videoBuilder: (uid, size) {
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
            tableContent: StudioTableContent(
              streamId: _id,
              phone: phone,
              onViewItem: (_) => setState(() => _tab = StudioRoomTab.goods),
            ),
            popoutContentBuilder: (context, target, size) {
              if (target.isTable) {
                return StudioTableContent(streamId: _id, phone: phone);
              }
              final h = room.cameraOf(target.uid!);
              return h == null ? const SizedBox.shrink() : StudioVideoView(h, fit: BoxFit.contain);
            },
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
                  onPeople: () => _openPeople(tokens, state, membersList, role),
                  onClose: () => _close(role, tokens),
                  onShare: () => _share(state),
                  onDrawer: () => _openDrawer(tokens, state, membersList, role),
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
                  tab: _tab,
                  onTab: (t) => t == StudioRoomTab.people
                      ? _openPeople(tokens, state, membersList, role)
                      : setState(() => _tab = t),
                  onPeople: () => _openPeople(tokens, state, membersList, role),
                  onClose: () => _close(role, tokens),
                  onShare: () => _share(state),
                );

          return Stack(fit: StackFit.expand, children: [
            Positioned.fill(child: stage),
            Positioned.fill(child: SafeArea(child: chrome)),
          ]);
        }),
      ),
    );
  }
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
    required this.tab,
    required this.onTab,
    required this.onPeople,
    required this.onClose,
    required this.onShare,
  });

  final String streamId;
  final LiveStudioTokens tokens;
  final StudioState state;
  final StageMember? host;
  final List<StageMember> members;
  final StudioRole role;
  final StudioRoomPort room;
  final Rect comments;
  final StudioRoomTab tab;
  final ValueChanged<StudioRoomTab> onTab;
  final VoidCallback onPeople;
  final VoidCallback onClose;
  final VoidCallback onShare;

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
            TableModePicker(streamId: streamId, kind: TableModePickerKind.capsule, tokens: t),
            const Spacer(),
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
        bottom: 26,
        child: SizedBox(
          height: 68,
          child: Row(children: [
            _ControlsGroup(streamId: streamId, tokens: t, state: state, role: role, room: room),
            const SizedBox(width: 12),
            Flexible(
              child: GlassBox(
                tokens: t,
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final d in kStudioTabs.take(4))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: RoomTabButton(
                          def: d,
                          tokens: t,
                          active: tab == d.tab,
                          onTap: () => onTab(d.tab),
                          count: d.tab == StudioRoomTab.people ? counts.participants : null,
                          dot: d.tab == StudioRoomTab.goods,
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
  const _ControlsGroup({required this.streamId, required this.tokens, required this.state, required this.role, required this.room});
  final String streamId;
  final LiveStudioTokens tokens;
  final StudioState state;
  final StudioRole role;
  final StudioRoomPort room;

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
        ShareToTableButton(streamId: streamId, tokens: t),
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
    required this.onPeople,
    required this.onClose,
    required this.onShare,
    required this.onDrawer,
  });

  final String streamId;
  final LiveStudioTokens tokens;
  final StudioState state;
  final StageMember? host;
  final StudioRole role;
  final StudioCamera camera;
  final Rect comments;
  final VoidCallback onPeople;
  final VoidCallback onClose;
  final VoidCallback onShare;
  final VoidCallback onDrawer;

  /// Compact table rail anchor in the phone artboard (SPEC §2: left 32, top 377).
  static const Offset _railAnchor = Offset(32, 377);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tokens;
    final counts = ref.watch(studioCountsProvider(streamId));
    final reactions = ref.watch(studioReactionsProvider(streamId));
    final rail = camera.artboardToUi(_railAnchor);
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
      // Compact table rail (also reachable in the drawer).
      Positioned(
        left: rail.dx,
        top: rail.dy,
        child: TableModePicker(streamId: streamId, kind: TableModePickerKind.rail, tokens: t),
      ),
      Positioned.fromRect(rect: comments, child: CommentFeed(streamId: streamId, tokens: t)),
      Positioned(right: 10, bottom: 62, width: 40, height: 150, child: FloatingHearts(streamId: streamId, rise: 130)),
      // Slim bottom bar.
      Positioned(
        left: 10,
        right: 10,
        bottom: 12,
        child: SizedBox(
          height: 44,
          child: Row(children: [
            Expanded(child: CommentBar(streamId: streamId, tokens: t, phone: true)),
            const SizedBox(width: 5),
            ShareToTableButton(streamId: streamId, tokens: t, variant: ShareToTableVariant.phone),
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
  });

  final String streamId;
  final LiveStudioTokens tokens;
  final StudioRole role;
  final StudioRoomTab tab;
  final int participants;
  final ValueChanged<StudioRoomTab> onTab;
  final StudioRoomPort? room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tokens;
    return _DrawerFrame(
      tokens: t,
      title: 'Live features',
      children: [
        Text('On the table', style: LiveStudioType.s(12, FontWeight.w600, t.textMedium, height: 16)),
        const SizedBox(height: 6),
        TableModePicker(streamId: streamId, kind: TableModePickerKind.grid, tokens: t),
        const SizedBox(height: 12),
        Text('Room', style: LiveStudioType.s(12, FontWeight.w600, t.textMedium, height: 16)),
        const SizedBox(height: 6),
        Row(children: [
          for (final d in kStudioTabs)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _DrawerTab(
                  def: d,
                  tokens: t,
                  active: d.tab == tab,
                  count: d.tab == StudioRoomTab.people ? participants : null,
                  dot: d.tab == StudioRoomTab.goods || d.tab == StudioRoomTab.chat,
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
          ShareToTableButton(streamId: streamId, tokens: t, variant: ShareToTableVariant.drawer),
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
  const _Unavailable({required this.onClose, this.ended = false});
  final VoidCallback onClose;
  final bool ended;

  @override
  Widget build(BuildContext context) {
    const t = LiveStudioTokens.dark;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(ended ? Icons.live_tv_outlined : Icons.error_outline, size: 40, color: t.textMedium),
        const SizedBox(height: 12),
        Text(ended ? 'This live has ended' : 'This live is unavailable',
            style: LiveStudioType.s(17, FontWeight.w700, t.textHigh)),
        const SizedBox(height: 16),
        StudioPillButton(
          label: 'Back',
          icon: Icons.arrow_back,
          onTap: onClose,
          fill: LiveStudioAccent.blue,
          textColor: LiveStudioAccent.white,
        ),
      ]),
    );
  }
}
