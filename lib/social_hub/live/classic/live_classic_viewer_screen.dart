import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../../backend/live/models/live_models.dart';
import '../../../backend/live/services/live_service.dart';
import '../../../backend/live/services/live_stage_media_controller.dart';
import '../../../backend/social/repositories/relationship_repository.dart';
import '../../../shared/theme/app_theme.dart';
import '../studio/live_studio_screen.dart';
import 'live_classic_widgets.dart';
import '../../../backend/live_studio/live_studio_flag.dart';
import '../settings/live_advanced_settings_sheet.dart';
import '../studio_v2/shell/live_studio_v2_screen.dart';
import 'live_classic_host_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LIVE ROOM GATE — /live/viewer/:streamId
//
// Followers land here from the feed's live ring or a "… is LIVE" alert.
// Classic streams open the full-screen vertical viewer; streams the host
// started in Studio mode open the Live Studio (video windows on the walls).
// ─────────────────────────────────────────────────────────────────────────────

class LiveRoomGate extends ConsumerWidget {
  final String streamId;
  const LiveRoomGate({super.key, required this.streamId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(liveStreamProvider(streamId));
    return async.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.brandBlack,
        body: Center(
            child: CircularProgressIndicator(color: AppColors.brandPink)),
      ),
      error: (e, _) => ClassicEndedView(
        stream: null,
        headline: 'This LIVE is unavailable',
        onClose: () => _leave(context),
      ),
      data: (stream) {
        if (stream == null) {
          return ClassicEndedView(
            stream: null,
            headline: 'This LIVE is unavailable',
            onClose: () => _leave(context),
          );
        }
        final me = FirebaseAuth.instance.currentUser?.uid ?? '';
        final isHost = stream.hostId == me;

        if (stream.layoutMode == 'studio') {
          // v2 streams (lsStart) carry studioVersion 2; older ones stay on v1.
          final version = ref.watch(liveStudioVersionProvider(streamId)).value ?? 1;
          return version >= 2
              ? LiveStudioV2Screen(streamId: streamId)
              : LiveStudioScreen(streamId: streamId);
        }
        if (isHost) {
          return LiveClassicHostView(
            initial: stream,
            onEnd: () {
              ref.read(liveServiceProvider).endStream(streamId);
              _leave(context);
            },
            onOpenTools: () => showLiveAdvancedSettingsSheet(context),
          );
        }
        return LiveClassicViewerScreen(initialStreamId: streamId);
      },
    );
  }
}

void _leave(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/hub/home');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CLASSIC VIEWER — swipe up / down between live rooms.
// ─────────────────────────────────────────────────────────────────────────────

class LiveClassicViewerScreen extends ConsumerStatefulWidget {
  final String initialStreamId;
  const LiveClassicViewerScreen({super.key, required this.initialStreamId});

  @override
  ConsumerState<LiveClassicViewerScreen> createState() =>
      _LiveClassicViewerScreenState();
}

class _LiveClassicViewerScreenState
    extends ConsumerState<LiveClassicViewerScreen> {
  late List<String> _ids = [widget.initialStreamId];
  bool _queueLoaded = false;
  final _pager = PageController();

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _loadQueue(List<LiveStream> active) {
    if (_queueLoaded) return;
    _queueLoaded = true;
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    final more = active
        .where((s) =>
            s.id != widget.initialStreamId &&
            s.layoutMode != 'studio' &&
            s.hostId != me &&
            s.audienceMode != 'private')
        .map((s) => s.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ids = [widget.initialStreamId, ...more]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeLiveStreamsProvider).value;
    if (active != null) _loadQueue(active);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.brandBlack,
        resizeToAvoidBottomInset: false,
        body: PageView.builder(
          controller: _pager,
          scrollDirection: Axis.vertical,
          itemCount: _ids.length,
          itemBuilder: (_, i) =>
              _ClassicLiveRoom(key: ValueKey(_ids[i]), streamId: _ids[i]),
        ),
      ),
    );
  }
}

class _ClassicLiveRoom extends ConsumerStatefulWidget {
  final String streamId;
  const _ClassicLiveRoom({super.key, required this.streamId});

  @override
  ConsumerState<_ClassicLiveRoom> createState() => _ClassicLiveRoomState();
}

class _ClassicLiveRoomState extends ConsumerState<_ClassicLiveRoom> {
  late final LiveService _live = ref.read(liveServiceProvider);
  final String _me = FirebaseAuth.instance.currentUser?.uid ?? '';
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();

  String _syncedHost = '';
  int _hearts = 0;
  int _seenLikes = -1;
  bool _requested = false;
  bool _cleanView = false;
  Offset? _tapHeartAt;

  @override
  void initState() {
    super.initState();
    _live.incrementViewerCount(widget.streamId);
  }

  @override
  void dispose() {
    _live.decrementViewerCount(widget.streamId);
    _composer.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _syncMedia(LiveStream s) {
    if (_syncedHost == s.hostId) return;
    _syncedHost = s.hostId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(liveStageMediaProvider(widget.streamId).notifier).syncStage(
            publisherIds: {s.hostId, ...s.coHostIds},
            selfIsPublisher: false,
          );
    });
  }

  void _like([Offset? at]) {
    HapticFeedback.lightImpact();
    setState(() {
      _hearts++;
      _tapHeartAt = at;
    });
    _live.sendLikeReaction(widget.streamId).catchError((_) {});
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    _composerFocus.unfocus();
    try {
      await _live.sendComment(widget.streamId, text);
    } catch (e) {
      _snack('Comment not sent');
    }
  }

  Future<void> _requestJoin() async {
    if (_requested) return;
    HapticFeedback.mediumImpact();
    try {
      await _live.requestToJoin(widget.streamId);
      setState(() => _requested = true);
      _snack('Request sent — the host will be notified');
    } catch (_) {
      _snack('Could not send request');
    }
  }

  Future<void> _share(LiveStream s) async {
    try {
      await SharePlus.instance.share(ShareParams(
        subject: s.title,
        text: 'Watch "${s.title}" live with ${s.hostDisplayName} on Oneova.',
      ));
    } catch (_) {
      _snack('Could not open share sheet');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13)),
      backgroundColor: context.surface,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(liveStreamProvider(widget.streamId));
    final stream = async.value;

    if (async.isLoading && stream == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.brandPink));
    }
    if (stream == null ||
        stream.status == LiveStreamStatus.ended ||
        stream.status == LiveStreamStatus.abandoned) {
      return ClassicEndedView(stream: stream, onClose: () => _leave(context));
    }

    _syncMedia(stream);
    final media = ref.watch(liveStageMediaProvider(widget.streamId));
    final comments =
        ref.watch(liveCommentsProvider(widget.streamId)).value ??
            const <LiveComment>[];

    // Remote likes from other viewers also float a heart.
    if (_seenLikes >= 0 && stream.totalLikes > _seenLikes) {
      final delta = stream.totalLikes - _seenLikes;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _hearts += delta.clamp(0, 3));
      });
    }
    _seenLikes = stream.totalLikes;

    final hostVideo = media.renderers[stream.hostId];
    final hasVideo = media.hasLiveVideo(stream.hostId, _me);
    final isSelf = stream.hostId == _me;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _composerFocus.unfocus(),
      onDoubleTapDown: (d) => _tapHeartAt = d.localPosition,
      onDoubleTap: () => _like(_tapHeartAt),
      onLongPress: () {
        HapticFeedback.selectionClick();
        setState(() => _cleanView = !_cleanView);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClassicVideoBackdrop(
            renderer: hostVideo,
            hasVideo: hasVideo,
            avatarUrl: stream.hostAvatarUrl,
            statusText: media.error ?? 'Connecting to live…',
          ),
          // Legibility gradients
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.brandBlack.withValues(alpha: 0.4),
                    Colors.transparent,
                    Colors.transparent,
                    AppColors.brandBlack.withValues(alpha: 0.6),
                  ],
                  stops: const [0, 0.18, 0.55, 1],
                ),
              ),
            ),
          ),

          // Double-tap heart burst at the tap point
          if (_tapHeartAt != null)
            Positioned(
              key: ValueKey('tap$_hearts'),
              left: _tapHeartAt!.dx - 40,
              top: _tapHeartAt!.dy - 40,
              child: const IgnorePointer(
                child: Icon(Icons.favorite_rounded,
                    color: AppColors.brandPink, size: 80),
              )
                  .animate()
                  .scale(
                      begin: const Offset(0.3, 0.3),
                      end: const Offset(1.1, 1.1),
                      duration: 260.ms,
                      curve: Curves.easeOutBack)
                  .then()
                  .fadeOut(duration: 350.ms)
                  .moveY(end: -30, duration: 350.ms),
            ),

          AnimatedOpacity(
            opacity: _cleanView ? 0 : 1,
            duration: 220.ms,
            child: IgnorePointer(
              ignoring: _cleanView,
              child: SafeArea(
                child: Stack(
                  children: [
                    // ── Top bar ──
                    Positioned(
                      top: 8,
                      left: 12,
                      right: 8,
                      child: Row(
                        children: [
                          StreamBuilder<bool>(
                            stream: ref
                                .read(relationshipRepositoryProvider)
                                .watchIsFollowing(_me, stream.hostId),
                            builder: (_, snap) => ClassicHostPill(
                              name: stream.hostDisplayName,
                              avatarUrl: stream.hostAvatarUrl,
                              likes: stream.totalLikes,
                              showFollow: !isSelf && _me.isNotEmpty,
                              isFollowing: snap.data ?? false,
                              onTap: () =>
                                  context.push('/profile/${stream.hostId}'),
                              onFollow: () {
                                HapticFeedback.mediumImpact();
                                ref
                                    .read(relationshipRepositoryProvider)
                                    .followUser(_me, stream.hostId)
                                    .catchError((_) => _snack(
                                        'Could not follow right now'));
                              },
                            ),
                          ),
                          const Spacer(),
                          ClassicViewerBadge(count: stream.viewerCount),
                          const SizedBox(width: 6),
                          ClassicRoundButton(
                            icon: Icons.close_rounded,
                            size: 34,
                            tooltip: 'Leave',
                            onTap: () => _leave(context),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 50,
                      left: 14,
                      right: 80,
                      child: Row(
                        children: [
                          const ClassicLiveBadge(),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              stream.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                  color: AppColors.brandWhite,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Comments ──
                    Positioned(
                      left: 12,
                      right: 90,
                      bottom: 62 + bottomInset,
                      height: 230,
                      child: ClassicCommentList(
                          comments: comments, hostId: stream.hostId),
                    ),

                    // ── Floating hearts ──
                    Positioned(
                      right: 6,
                      bottom: 56 + bottomInset,
                      child: ClassicFloatingHearts(bursts: _hearts),
                    ),

                    // ── Bottom bar ──
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 10 + bottomInset,
                      child: Row(
                        children: [
                          Expanded(
                            child: ClassicCommentField(
                              controller: _composer,
                              focusNode: _composerFocus,
                              onSend: _send,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (stream.allowGuestRequests && !isSelf)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ClassicRoundButton(
                                icon: _requested
                                    ? Icons.hourglass_top_rounded
                                    : Icons.group_add_outlined,
                                tooltip: 'Request to join',
                                onTap: _requestJoin,
                              ),
                            ),
                          ClassicRoundButton(
                            icon: Icons.card_giftcard_rounded,
                            color: AppColors.brandPink,
                            tooltip: 'Gift',
                            onTap: () => ClassicGiftSheet.show(context,
                                onSend: (type) {
                              _live
                                  .sendGift(widget.streamId, type, 1)
                                  .catchError((_) => _snack('Gift not sent'));
                              setState(() => _hearts += 3);
                            }),
                          ),
                          const SizedBox(width: 6),
                          ClassicRoundButton(
                            icon: Icons.reply_rounded,
                            tooltip: 'Share',
                            onTap: () => _share(stream),
                          ),
                          const SizedBox(width: 6),
                          ClassicRoundButton(
                            icon: Icons.favorite_rounded,
                            color: AppColors.brandPink,
                            tooltip: 'Like',
                            onTap: _like,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
