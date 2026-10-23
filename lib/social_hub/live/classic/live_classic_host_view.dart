import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../../backend/live/models/live_models.dart';
import '../../../backend/live/services/live_service.dart';
import '../../../backend/live/services/live_stage_media_controller.dart';
import '../../../shared/theme/app_theme.dart';
import 'live_classic_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CLASSIC HOST VIEW — the creator's own full-screen vertical live.
// Publishes camera + mic over the live stage WebRTC pipeline so followers in
// the classic viewer see it.
// ─────────────────────────────────────────────────────────────────────────────

class LiveClassicHostView extends ConsumerStatefulWidget {
  final LiveStream initial;
  final VoidCallback onEnd;
  final VoidCallback onOpenTools;

  const LiveClassicHostView({
    super.key,
    required this.initial,
    required this.onEnd,
    required this.onOpenTools,
  });

  @override
  ConsumerState<LiveClassicHostView> createState() =>
      _LiveClassicHostViewState();
}

class _LiveClassicHostViewState extends ConsumerState<LiveClassicHostView> {
  final String _me = FirebaseAuth.instance.currentUser?.uid ?? '';
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();
  Timer? _clock;
  Duration _elapsed = Duration.zero;
  int _hearts = 0;
  int _seenLikes = -1;
  String _syncedSig = '';

  String get _id => widget.initial.id;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() =>
            _elapsed = DateTime.now().difference(widget.initial.createdAt));
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _composer.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _sync(LiveStream s) {
    final sig = [_me, ...s.coHostIds].join(',');
    if (sig == _syncedSig) return;
    _syncedSig = sig;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(liveStageMediaProvider(_id).notifier).syncStage(
            publisherIds: {_me, ...s.coHostIds},
            selfIsPublisher: true,
          );
    });
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    _composerFocus.unfocus();
    await ref.read(liveServiceProvider).sendComment(_id, text).catchError((_) {});
  }

  Future<void> _share(LiveStream s) async {
    try {
      await SharePlus.instance.share(ShareParams(
        subject: s.title,
        text: "I'm live on Oneova: \"${s.title}\" — come watch!",
      ));
    } catch (_) {}
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final stream =
        ref.watch(liveStreamProvider(_id)).value ?? widget.initial;
    _sync(stream);
    final media = ref.watch(liveStageMediaProvider(_id));
    final comments = ref.watch(liveCommentsProvider(_id)).value ??
        const <LiveComment>[];
    final pending = (ref.watch(liveGuestRequestsProvider(_id)).value ??
            const <LiveGuestRequest>[])
        .where((r) => r.status == LiveGuestRequestStatus.pending)
        .length;

    if (_seenLikes >= 0 && stream.totalLikes > _seenLikes) {
      final delta = stream.totalLikes - _seenLikes;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _hearts += delta.clamp(0, 3));
      });
    }
    _seenLikes = stream.totalLikes;

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final user = FirebaseAuth.instance.currentUser;
    final ctrl = ref.read(liveStageMediaProvider(_id).notifier);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.brandBlack,
        resizeToAvoidBottomInset: false,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _composerFocus.unfocus(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClassicVideoBackdrop(
                renderer: media.localRenderer,
                hasVideo: media.isPublishing && !media.cameraOff,
                mirror: true,
                avatarUrl: user?.photoURL ?? '',
                statusText: media.error ??
                    (media.cameraOff ? 'Camera is off' : 'Starting camera…'),
              ),
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
              SafeArea(
                child: Stack(
                  children: [
                    Positioned(
                      top: 8,
                      left: 12,
                      right: 8,
                      child: Row(
                        children: [
                          ClassicHostPill(
                            name: stream.hostDisplayName,
                            avatarUrl: stream.hostAvatarUrl,
                            likes: stream.totalLikes,
                          ),
                          const Spacer(),
                          ClassicViewerBadge(count: stream.viewerCount),
                          const SizedBox(width: 6),
                          ClassicRoundButton(
                            icon: Icons.power_settings_new_rounded,
                            size: 34,
                            color: AppColors.brandPink,
                            tooltip: 'End LIVE',
                            onTap: widget.onEnd,
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 50,
                      left: 14,
                      child: Row(
                        children: [
                          const ClassicLiveBadge(),
                          const SizedBox(width: 6),
                          Text(_fmt(_elapsed),
                              style: GoogleFonts.inter(
                                  color: AppColors.brandWhite,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ])),
                        ],
                      ),
                    ),
                    if (pending > 0)
                      Positioned(
                        top: 48,
                        right: 12,
                        child: GestureDetector(
                          onTap: widget.onOpenTools,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.brandBlue,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.full),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.group_add_rounded,
                                    color: AppColors.brandWhite, size: 14),
                                const SizedBox(width: 5),
                                Text('$pending want to join',
                                    style: GoogleFonts.inter(
                                        color: AppColors.brandWhite,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        )
                            .animate(
                                onPlay: (c) => c.repeat(reverse: true))
                            .scale(
                                begin: const Offset(1, 1),
                                end: const Offset(1.05, 1.05),
                                duration: 700.ms),
                      ),
                    Positioned(
                      left: 12,
                      right: 90,
                      bottom: 62 + bottomInset,
                      height: 230,
                      child: ClassicCommentList(
                          comments: comments, hostId: stream.hostId),
                    ),
                    Positioned(
                      right: 6,
                      bottom: 56 + bottomInset,
                      child: ClassicFloatingHearts(bursts: _hearts),
                    ),
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
                              hint: 'Say something…',
                            ),
                          ),
                          const SizedBox(width: 8),
                          ClassicRoundButton(
                            icon: Icons.cameraswitch_rounded,
                            tooltip: 'Flip camera',
                            onTap: () => ctrl.switchCamera(),
                          ),
                          const SizedBox(width: 6),
                          ClassicRoundButton(
                            icon: media.micMuted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                            color: media.micMuted
                                ? AppColors.brandPink
                                : null,
                            tooltip: media.micMuted ? 'Unmute' : 'Mute',
                            onTap: ctrl.toggleMic,
                          ),
                          const SizedBox(width: 6),
                          ClassicRoundButton(
                            icon: Icons.reply_rounded,
                            tooltip: 'Share',
                            onTap: () => _share(stream),
                          ),
                          const SizedBox(width: 6),
                          ClassicRoundButton(
                            icon: Icons.more_horiz_rounded,
                            tooltip: 'More tools',
                            onTap: widget.onOpenTools,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
