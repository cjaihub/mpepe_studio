import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../backend/live/models/live_models.dart';
import '../../../backend/live/models/live_studio_models.dart';
import '../../../backend/live/services/live_service.dart';
import '../../../backend/live/services/live_stage_media_controller.dart';
import '../../../backend/live/services/live_studio_service.dart';
import '../../../shared/theme/obsidian_telemetry_tokens.dart';
import 'live_studio_geometry.dart';
import 'live_studio_roster.dart';
import 'widgets/studio_chrome.dart';
import 'widgets/studio_panels.dart';
import 'widgets/studio_world.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LIVE STUDIO SCREEN
//
// Replaces the TikTok-style viewer. Guests are video windows mounted on the
// walls of a 3D broadcast studio photo (see live_studio_geometry.dart).
// Route: /live/studio/:streamId (and /live/viewer/:streamId).
// ─────────────────────────────────────────────────────────────────────────────

class LiveStudioScreen extends ConsumerStatefulWidget {
  final String streamId;

  /// Dim overlay over the studio photo (0 – 1).
  final double dimOpacity;

  const LiveStudioScreen({
    super.key,
    required this.streamId,
    this.dimOpacity = 0.15,
  });

  @override
  ConsumerState<LiveStudioScreen> createState() => _LiveStudioScreenState();
}

class _LiveStudioScreenState extends ConsumerState<LiveStudioScreen> {
  static const _geometry = kStudioGeometry;

  late final LiveService _live;
  late final LiveStudioService _studio;
  final String _selfUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final DateTime _openedAt = DateTime.now();

  // UI state
  StudioTab _tab = StudioTab.room;
  bool _showWall = true;
  bool _cleanView = false;
  bool _joinBusy = false;
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();

  // Hearts
  final List<FloatingHeartSpec> _hearts = [];
  int _heartSeq = 0;
  DateTime _lastLikeWrite = DateTime.fromMillisecondsSinceEpoch(0);
  final _rng = math.Random();
  StreamSubscription<List<LiveReaction>>? _reactionSub;
  final Set<String> _seenReactionIds = {};

  // Notification dots
  String? _seenActivityId;
  bool _activitySeeded = false;
  String? _seenFeaturedId;

  // Reconciliation caches
  Map<String, String> _assignment = const {};
  String _syncedStageSignature = '';
  String _publishedMediaSignature = '';
  bool _wasOnStage = false;
  bool _wasHost = false;

  @override
  void initState() {
    super.initState();
    _live = ref.read(liveServiceProvider);
    _studio = ref.read(liveStudioServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _live.incrementViewerCount(widget.streamId).catchError((_) {});
      _studio.joinAsAudience(widget.streamId).catchError((_) {});
    });
    _reactionSub = _studio
        .watchReactionsSince(widget.streamId, _openedAt)
        .listen(_onReactions, onError: (_) {});
  }

  @override
  void dispose() {
    _reactionSub?.cancel();
    _live.decrementViewerCount(widget.streamId).catchError((_) {});
    if (_wasOnStage && !_wasHost) {
      // Leaving the room also leaves the stage.
      _leaveStageWrites().catchError((_) {});
    } else if (!_wasHost) {
      _studio.leaveAsAudience(widget.streamId).catchError((_) {});
    }
    _composer.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────
  // BUILD
  // ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final streamAsync = ref.watch(liveStreamProvider(widget.streamId));
    return Scaffold(
      backgroundColor: OTColors.obsidianBase,
      resizeToAvoidBottomInset: true,
      body: streamAsync.when(
        loading: () => const StudioLoading(label: 'Joining live'),
        error: (e, _) => _EndedView(message: "We couldn't load this live. $e"),
        data: (stream) {
          if (stream == null ||
              stream.status == LiveStreamStatus.ended ||
              stream.status == LiveStreamStatus.abandoned) {
            return const _EndedView();
          }
          return _buildStudio(context, stream);
        },
      ),
    );
  }

  Widget _buildStudio(BuildContext context, LiveStream stream) {
    final id = widget.streamId;
    final participantsAsync = ref.watch(liveParticipantsProvider(id));
    final requestsAsync = ref.watch(liveGuestRequestsProvider(id));
    final commentsAsync = ref.watch(liveCommentsProvider(id));
    final studioDoc = ref.watch(liveStudioDocProvider(id)).value;
    final featured = ref.watch(liveFeaturedProductProvider(id));
    final media = ref.watch(liveStageMediaProvider(id));

    final participants = participantsAsync.value ?? const <LiveParticipant>[];
    final requests = requestsAsync.value ?? const <LiveGuestRequest>[];
    final isHost = stream.hostId == _selfUid;

    return LayoutBuilder(builder: (context, constraints) {
      // Place the world from the full screen size so the on-screen keyboard
      // never rescales the studio; overlays use the (resizable) constraints.
      final viewport = MediaQuery.sizeOf(context);
      final placement = StudioWorldPlacement.forViewport(viewport, geometry: _geometry);
      final layout = placement.layoutOf(_geometry);

      final roster = buildStudioRoster(
        stream: stream,
        participants: participants,
        requests: requests,
        stageFocusUserId: studioDoc?.stageFocusUserId,
        slots: layout.slots,
        previous: _assignment,
        isPortraitVideo: (uid) {
          final r = media.rendererFor(uid, _selfUid);
          if (r == null || r.videoWidth == 0 || r.videoHeight == 0) return null;
          return r.videoHeight > r.videoWidth;
        },
      );
      _assignment = roster.assignment;

      final selfOnStage = roster.publisherIds.contains(_selfUid);
      _wasOnStage = selfOnStage;
      _wasHost = isHost;
      _scheduleReconcile(roster, participants, media, selfOnStage);

      final myRequest = requests.where((r) => r.userId == _selfUid).firstOrNull;
      final joinState = isHost
          ? StudioJoinState.hidden
          : _joinBusy
              ? StudioJoinState.busy
              : selfOnStage
                  ? StudioJoinState.onStage
                  : myRequest?.status == LiveGuestRequestStatus.pending
                      ? StudioJoinState.pending
                      : StudioJoinState.idle;

      final feed = _buildFeed(commentsAsync.value ?? const [], participants, requests);
      final latestFeedId = feed.isEmpty ? null : feed.last.id;
      final featuredId = featured.value?.id;
      // Messages that existed before we arrived don't count as new.
      if (!_activitySeeded && commentsAsync.hasValue) {
        _activitySeeded = true;
        _seenActivityId = latestFeedId;
      }
      if (_tab == StudioTab.activity) _seenActivityId = latestFeedId;
      if (_tab == StudioTab.goods) _seenFeaturedId = featuredId;
      final dots = <StudioTab>{
        if (latestFeedId != null && latestFeedId != _seenActivityId) StudioTab.activity,
        if (featuredId != null && featuredId != _seenFeaturedId) StudioTab.goods,
      };

      final dockModel = StudioDockModel(
        activeTab: _tab,
        onTab: (t) => setState(() => _tab = (_tab == t && t != StudioTab.room) ? StudioTab.room : t),
        dots: dots,
        participantCount: participants.length,
        showWallGuests: _showWall,
        onToggleWall: () => setState(() => _showWall = !_showWall),
        cleanView: _cleanView,
        onToggleCleanView: () => setState(() => _cleanView = !_cleanView),
        canUseCamera: selfOnStage && media.isPublishing,
        cameraOff: media.cameraOff,
        onToggleCamera: () => ref.read(liveStageMediaProvider(id).notifier).toggleCamera(),
        micMuted: media.micMuted,
        onToggleMic: () => ref.read(liveStageMediaProvider(id).notifier).toggleMic(),
        composer: _composer,
        composerFocus: _composerFocus,
        onSend: (text) => _live.sendComment(id, text).catchError((e) {
          _snack('Comment not sent: $e');
        }),
        canComment: _selfUid.isNotEmpty,
      );

      void closePanel() => setState(() => _tab = StudioTab.room);
      final panel = _panelFor(
        _tab,
        stream: stream,
        roster: roster,
        participants: participants,
        requests: requests,
        feed: feed,
        feedLoading: commentsAsync.isLoading,
        isHost: isHost,
        onClose: closePanel,
      );

      final world = StudioWorld(
        geometry: _geometry,
        placement: placement,
        roster: roster,
        media: media,
        selfUid: _selfUid,
        showTitle: stream.title,
        dimOpacity: widget.dimOpacity,
        showWallGuests: _showWall,
        onSwapToStage: isHost ? (m) => _swapToStage(m) : null,
      );

      final goodsCard = AsyncSnapshotLike<LiveProduct?>(
        data: featured.value,
        isLoading: featured.isLoading,
      );
      void openGoods() => setState(() => _tab = StudioTab.goods);
      final standOnScreen = placement.worldToScreen(_geometry.stand.center);
      final padding = MediaQuery.paddingOf(context);
      final topBar = StudioTopBar(
        title: stream.title,
        viewerCount: stream.viewerCount,
        compact: !placement.isLandscape,
        joinState: joinState,
        onJoinPressed: () => _onJoinPressed(joinState),
        onShare: () => _share(stream),
        onClose: isHost ? () => _confirmEnd(stream) : _close,
      );
      final loveButton = _loveButton(showLabel: placement.isLandscape);

      if (placement.isLandscape) {
        const margin = OTSpace.marginDesktop;
        const dockHeight = 60.0;
        final dockBottom = padding.bottom + OTSpace.margin;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            world,
            const _Scrims(top: 150, bottom: 240),
            if (featured.value != null || featured.isLoading)
              Positioned(
                left: standOnScreen.dx - 120,
                width: 240,
                top: standOnScreen.dy - 18 * placement.scale,
                // Card floats above the stand: shift up by its own height.
                child: FractionalTranslation(
                  translation: const Offset(0, -1),
                  child: GoodsCard(product: goodsCard, onViewItem: openGoods),
                ),
              ),
            Positioned(
              left: margin + padding.left,
              right: margin + padding.right,
              top: padding.top + OTSpace.margin,
              child: topBar,
            ),
            if (panel != null)
              Positioned(
                right: margin + padding.right + 56 + OTSpace.margin,
                top: padding.top + OTSpace.margin + 60,
                bottom: dockBottom + dockHeight + OTSpace.md,
                width: 380,
                child: GlassBox(
                  borderColor: OTColors.pinkBorder30,
                  padding: const EdgeInsets.all(OTSpace.margin),
                  child: panel,
                ),
              ),
            Positioned(
              left: margin + padding.left,
              right: margin + padding.right,
              bottom: dockBottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (!_cleanView)
                        SizedBox(width: 340, child: StudioCommentFeed(items: feed)),
                      const Spacer(),
                      loveButton,
                    ],
                  ),
                  const SizedBox(height: OTSpace.md),
                  SizedBox(height: dockHeight, child: StudioDock(model: dockModel)),
                ],
              ),
            ),
            if (media.error != null) _mediaError(media.error!, padding),
          ],
        );
      }

      // ── PHONE ─────────────────────────────────────────────────────────
      final panelHeight = math.min(viewport.height * 0.45, 420.0);
      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          world,
          const _Scrims(top: 120, bottom: 200),
          if (featured.value != null || featured.isLoading)
            Positioned(
              left: OTSpace.margin,
              right: OTSpace.margin,
              top: standOnScreen.dy - 30,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: GoodsCard(product: goodsCard, onViewItem: openGoods, compact: true),
                ),
              ),
            ),
          Positioned(
            left: OTSpace.margin,
            right: OTSpace.sm,
            top: padding.top + OTSpace.sm,
            child: topBar,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      OTSpace.margin, 0, OTSpace.margin, OTSpace.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: (_cleanView || panel != null)
                            ? const SizedBox.shrink()
                            : StudioCommentFeed(items: feed, maxVisible: 4),
                      ),
                      const SizedBox(width: OTSpace.md),
                      loveButton,
                    ],
                  ),
                ),
                StudioPhoneSheet(
                  model: dockModel,
                  panel: panel,
                  expandedPanelHeight: panelHeight,
                  onCollapse: closePanel,
                  bottomInset: padding.bottom,
                ),
              ],
            ),
          ),
          if (media.error != null) _mediaError(media.error!, padding),
        ],
      );
    });
  }

  Widget? _panelFor(
    StudioTab tab, {
    required LiveStream stream,
    required StudioRoster roster,
    required List<LiveParticipant> participants,
    required List<LiveGuestRequest> requests,
    required List<StudioFeedItem> feed,
    required bool feedLoading,
    required bool isHost,
    required VoidCallback onClose,
  }) {
    switch (tab) {
      case StudioTab.room:
        return null;
      case StudioTab.lobby:
        return StudioLobbyPanel(
            stream: stream,
            roster: roster,
            audienceCount: participants.length,
            onClose: onClose);
      case StudioTab.goods:
        return StudioGoodsPanel(streamId: stream.id, isHost: isHost, onClose: onClose);
      case StudioTab.participants:
        return StudioParticipantsPanel(
          stream: stream,
          roster: roster,
          participants: participants,
          requests: requests,
          isHost: isHost,
          selfUid: _selfUid,
          onPutOnStage: _swapToStage,
          onClose: onClose,
        );
      case StudioTab.activity:
        return StudioActivityPanel(items: feed, isLoading: feedLoading, onClose: onClose);
    }
  }

  Widget _loveButton({required bool showLabel}) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        Positioned(
          bottom: showLabel ? 76 : 60,
          child: FloatingHeartsLayer(
            hearts: List.of(_hearts),
            onDone: (hid) {
              if (!mounted) return;
              setState(() => _hearts.removeWhere((h) => h.id == hid));
            },
          ),
        ),
        ShowLoveButton(onPressed: _onLove, showLabel: showLabel),
      ],
    );
  }

  Widget _mediaError(String message, EdgeInsets padding) {
    return Positioned(
      left: OTSpace.margin,
      right: OTSpace.margin,
      top: padding.top + 72,
      child: Center(
        child: GlassBox(
          borderColor: OTColors.liveCrimson,
          radius: OTRadius.md,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.videocam_off_outlined, size: 18, color: OTColors.liveCrimson),
            const SizedBox(width: 8),
            Flexible(child: Text(message, style: OTType.bodySm(color: OTColors.textHigh))),
          ]),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // DATA → FEED
  // ───────────────────────────────────────────────────────────────────────

  List<StudioFeedItem> _buildFeed(
    List<LiveComment> comments, // newest first
    List<LiveParticipant> participants,
    List<LiveGuestRequest> requests,
  ) {
    final since = _openedAt.subtract(const Duration(seconds: 5));
    final items = <StudioFeedItem>[
      for (final c in comments.reversed)
        StudioFeedItem(
          id: 'c_${c.id}',
          name: c.authorDisplayName,
          avatarUrl: c.authorAvatarUrl,
          text: c.text,
          at: c.createdAt,
          isHighlighted: c.isHighlighted || c.isGift,
        ),
      for (final p in participants)
        if (p.userId != _selfUid && p.joinedAt.isAfter(since))
          StudioFeedItem(
            id: 'j_${p.userId}_${p.joinedAt.millisecondsSinceEpoch}',
            name: p.displayName,
            avatarUrl: p.avatarUrl,
            text: 'joined the live',
            at: p.joinedAt,
            isSystem: true,
          ),
      for (final r in requests)
        if (r.status == LiveGuestRequestStatus.pending && r.requestedAt.isAfter(since))
          StudioFeedItem(
            id: 'r_${r.userId}_${r.requestedAt.millisecondsSinceEpoch}',
            name: r.displayName,
            avatarUrl: r.avatarUrl,
            text: 'requested to join the stage',
            at: r.requestedAt,
            isSystem: true,
          ),
    ];
    items.sort((a, b) => a.at.compareTo(b.at));
    return items;
  }

  // ───────────────────────────────────────────────────────────────────────
  // MEDIA RECONCILIATION
  // ───────────────────────────────────────────────────────────────────────

  void _scheduleReconcile(
    StudioRoster roster,
    List<LiveParticipant> participants,
    LiveStageMediaState media,
    bool selfOnStage,
  ) {
    final stageSig = '${selfOnStage ? 1 : 0}|${(roster.publisherIds.toList()..sort()).join(',')}';
    final me = participants.where((p) => p.userId == _selfUid).firstOrNull;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ref.read(liveStageMediaProvider(widget.streamId).notifier);

      if (stageSig != _syncedStageSignature) {
        _syncedStageSignature = stageSig;
        controller.syncStage(
          publisherIds: roster.publisherIds,
          selfIsPublisher: selfOnStage,
        );
      }

      if (!media.isPublishing) {
        _publishedMediaSignature = '';
        return;
      }

      // Host muted me remotely → apply locally.
      if (me != null && me.isMuted && !media.micMuted &&
          _publishedMediaSignature.startsWith('0')) {
        controller.toggleMic();
        return;
      }

      final mediaSig = '${media.micMuted ? 1 : 0}${media.cameraOff ? 0 : 1}';
      final docMatches = me != null &&
          me.isMuted == media.micMuted &&
          me.isCameraOn == !media.cameraOff;
      if (mediaSig != _publishedMediaSignature || !docMatches) {
        _publishedMediaSignature = mediaSig;
        _studio
            .publishMediaState(widget.streamId,
                isMuted: media.micMuted, isCameraOn: !media.cameraOff)
            .catchError((_) {});
      }
    });
  }

  // ───────────────────────────────────────────────────────────────────────
  // ACTIONS
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _swapToStage(StageMember m) async {
    try {
      await _studio.setStageFocus(widget.streamId, m.isHost ? null : m.uid);
      if (mounted && _tab != StudioTab.room) setState(() => _tab = StudioTab.room);
    } catch (e) {
      _snack('Could not change the stage: $e');
    }
  }

  Future<void> _onJoinPressed(StudioJoinState state) async {
    if (_joinBusy) return;
    if (state == StudioJoinState.onStage) {
      final ok = await confirmStudioAction(context,
          title: 'Leave the stage?',
          message: 'Your camera and mic will stop broadcasting.',
          confirmLabel: 'Leave stage');
      if (!ok || !mounted) return;
    }
    setState(() => _joinBusy = true);
    try {
      switch (state) {
        case StudioJoinState.idle:
          await _live.requestToJoin(widget.streamId);
          _snack('Request sent. The host will let you on stage.');
          break;
        case StudioJoinState.pending:
        case StudioJoinState.onStage:
          await _leaveStageWrites();
          break;
        case StudioJoinState.hidden:
        case StudioJoinState.busy:
          break;
      }
    } catch (e) {
      _snack('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _joinBusy = false);
    }
  }

  /// Self-service leave/cancel that only touches docs a guest may write
  /// (LiveService.dropParticipant also edits the stream doc, which guests
  /// are not allowed to do).
  Future<void> _leaveStageWrites() => _studio.leaveStage(widget.streamId);

  void _onLove() {
    _spawnHeart(mine: true);
    final now = DateTime.now();
    if (now.difference(_lastLikeWrite) > const Duration(milliseconds: 300)) {
      _lastLikeWrite = now;
      _live.sendLikeReaction(widget.streamId).catchError((_) {});
    }
  }

  void _onReactions(List<LiveReaction> reactions) {
    if (!mounted) return;
    var spawned = 0;
    for (final r in reactions) {
      if (!_seenReactionIds.add(r.id)) continue;
      if (r.userId == _selfUid) continue; // already animated locally
      if (spawned++ < 6) _spawnHeart(mine: false);
    }
  }

  void _spawnHeart({required bool mine}) {
    if (!mounted) return;
    setState(() {
      if (_hearts.length >= 24) _hearts.removeAt(0);
      _hearts.add(FloatingHeartSpec(
        id: _heartSeq++,
        drift: (_rng.nextDouble() - 0.5) * 70,
        size: mine ? 26 + _rng.nextDouble() * 8 : 18 + _rng.nextDouble() * 6,
      ));
    });
  }

  Future<void> _share(LiveStream stream) async {
    try {
      await SharePlus.instance.share(ShareParams(
        subject: stream.title,
        text: 'Watch "${stream.title}" live with ${stream.hostDisplayName} on Oneova.',
      ));
    } catch (e) {
      _snack('Could not open share sheet');
    }
  }

  /// Host leaving the studio ends the live for everyone (after confirming).
  Future<void> _confirmEnd(LiveStream stream) async {
    final end = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OTColors.surface3,
        title: Text('End LIVE?', style: OTType.bodyMd()),
        content: Text('Your studio will close for all viewers and guests.',
            style: OTType.bodyMd()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('End LIVE')),
        ],
      ),
    );
    if (end != true) return;
    try {
      await _live.endStream(stream.id);
    } catch (e) {
      _snack('Could not end live: $e');
      return;
    }
    if (mounted) _close();
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/hub/home');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      backgroundColor: OTColors.surface3,
      content: Text(msg, style: OTType.bodyMd()),
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PIECES
// ─────────────────────────────────────────────────────────────────────────────

class _Scrims extends StatelessWidget {
  final double top;
  final double bottom;
  const _Scrims({required this.top, required this.bottom});

  @override
  Widget build(BuildContext context) {
    final solid = OTColors.obsidianBase.withValues(alpha: 0.85);
    final clear = OTColors.obsidianBase.withValues(alpha: 0);
    return Positioned.fill(
      child: IgnorePointer(
        child: Column(
          children: [
            Container(
              height: top,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [solid, clear],
                ),
              ),
            ),
            const Spacer(),
            Container(
              height: bottom,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [solid, clear],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EndedView extends StatelessWidget {
  final String? message;
  const _EndedView({this.message});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StudioEmptyState(
        icon: Icons.live_tv_outlined,
        title: 'This live has ended',
        message: message ?? 'Thanks for watching. The host has ended the broadcast.',
        action: StudioTextButton(
          label: 'Go back',
          icon: Icons.arrow_back_rounded,
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/hub/home'),
        ),
      ),
    );
  }
}
