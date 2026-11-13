import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../social_hub/feed/widgets/share_sheet.dart';
import '../backend/social/models/content.dart';
import '../backend/social/repositories/interaction_repository.dart';
import '../backend/social/services/content_deletion_service.dart';
import '../backend/social/services/video_playback_manager.dart';
import '../shared/audio/mic_coordinator.dart';
import '../shared/theme/app_theme.dart';
import 'widgets/comment_bottom_sheet.dart';
import 'widgets/reel_destination_chip.dart';
import 'widgets/reel_palette.dart';

/// One post on its own (opened from a profile grid): plays it, with like,
/// comment, save, share, and Delete for the author.
class PostViewerScreen extends ConsumerStatefulWidget {
  final String contentId;
  const PostViewerScreen({super.key, required this.contentId});

  @override
  ConsumerState<PostViewerScreen> createState() => _PostViewerScreenState();
}

class _PostViewerScreenState extends ConsumerState<PostViewerScreen> with RouteAware {
  Player? _player;
  VideoController? _video;
  String? _openedUrl;
  bool _deleting = false;
  bool _routeCurrent = true;
  bool _appResumed = true;
  late final AppLifecycleListener _lifecycle;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  bool get _canPlay =>
      mounted &&
      _routeCurrent &&
      _appResumed &&
      !_deleting &&
      MicCoordinator.instance.owner.value == null;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onPause: () => _onLifecycle(false),
      onInactive: () => _onLifecycle(false),
      onHide: () => _onLifecycle(false),
      onResume: () => _onLifecycle(true),
      onShow: () => _onLifecycle(true),
    );
    MicCoordinator.instance.owner.addListener(_syncPlayback);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(videoPlaybackManagerProvider).setScreenActive(false);
    });
    if (_uid.isNotEmpty) ref.read(interactionRepositoryProvider).recordView(_uid, widget.contentId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      mainFeedRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    _routeCurrent = false;
    _syncPlayback();
    super.didPushNext();
  }

  @override
  void didPopNext() {
    _routeCurrent = true;
    _syncPlayback();
    super.didPopNext();
  }

  @override
  void didPop() {
    _routeCurrent = false;
    _syncPlayback();
    super.didPop();
  }

  void _onLifecycle(bool resumed) {
    _appResumed = resumed;
    _syncPlayback();
  }

  void _syncPlayback() {
    final p = _player;
    if (p == null) return;
    if (_canPlay) {
      p.setVolume(100.0);
      if (!p.state.playing) p.play();
    } else {
      p.setVolume(0.0);
      p.pause();
    }
  }

  @override
  void deactivate() {
    _player?.setVolume(0.0);
    _player?.pause();
    super.deactivate();
  }

  @override
  void dispose() {
    mainFeedRouteObserver.unsubscribe(this);
    MicCoordinator.instance.owner.removeListener(_syncPlayback);
    _lifecycle.dispose();
    _player?.setVolume(0.0);
    _player?.stop();
    _player?.dispose();
    super.dispose();
  }

  void _ensurePlayer(Content c) {
    final isVideo = c.type != ContentType.photo && c.mediaUrl.isNotEmpty;
    if (!isVideo || _openedUrl == c.mediaUrl) return;
    _openedUrl = c.mediaUrl;
    if (_player == null) {
      final p = Player();
      p.stream.playing.listen((playing) {
        if (playing && !_canPlay) {
          p.setVolume(0.0);
          p.pause();
        }
      });
      _player = p;
    }
    _video ??= VideoController(_player!);
    _player!
      ..setVolume(_canPlay ? 100.0 : 0.0)
      ..setPlaylistMode(PlaylistMode.loop)
      ..open(Media(c.mediaUrl), play: _canPlay);
  }

  Future<void> _delete(Content c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Delete this post?', style: GoogleFonts.inter(color: ctx.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('It will be removed from Oneova for everyone, with its likes and comments. This can\'t be undone.',
            style: GoogleFonts.inter(color: ctx.textSecondary, fontSize: 13, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: ctx.textSecondary))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.brandPink, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    await _player?.pause();
    try {
      await ContentDeletionService().deleteOwnPost(c.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post deleted')));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete: $e'), backgroundColor: AppColors.brandPink));
    }
  }

  Future<void> _share(Content c) async {
    ShareSheet.show(context, postId: c.id, authorId: c.authorId, content: c);
  }

  @override
  Widget build(BuildContext context) {
    final doc = FirebaseFirestore.instance.collection('content').doc(widget.contentId);
    return Scaffold(
      backgroundColor: AppColors.brandBlack,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: doc.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return _message('This post is not available.');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.brandBlue));
          if (!snap.data!.exists) return _message(_deleting ? 'Deleting…' : 'This post was removed.');
          final c = Content.fromFirestore(snap.data!);
          _ensurePlayer(c);
          final isOwner = c.authorId == _uid;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (_video != null && c.type != ContentType.photo)
                GestureDetector(
                  onTap: () => _player?.playOrPause(),
                  child: Video(controller: _video!, fit: BoxFit.contain, controls: NoVideoControls),
                )
              else
                CachedNetworkImage(imageUrl: c.mediaUrl, fit: BoxFit.contain),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: SafeArea(
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: AppColors.brandWhite),
                        onPressed: () => context.pop(),
                      ),
                      const Spacer(),
                      if (isOwner)
                        IconButton(
                          tooltip: 'Delete post',
                          icon: _deleting
                              ? const SizedBox(
                                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandWhite))
                              : const Icon(Icons.delete_outline_rounded, color: AppColors.brandWhite),
                          onPressed: _deleting ? null : () => _delete(c),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 90,
                child: _Rail(content: c, uid: _uid, onComment: () => CommentBottomSheet.show(context, c), onShare: () => _share(c)),
              ),
              if (c.description.isNotEmpty || c.destination != null)
                Positioned(
                  left: 14,
                  right: 80,
                  bottom: 28,
                  child: SafeArea(
                    child: ReelTheme(
                      palette: const ReelPalette(dark: true),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (c.description.isNotEmpty)
                            Text(
                              c.description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: AppColors.brandWhite,
                                fontSize: 13,
                                height: 1.35,
                                shadows: const [Shadow(blurRadius: 6)],
                              ),
                            ),
                          if (c.destination != null) ReelDestinationChip(contentId: c.id, destination: c.destination!),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _message(String text) => SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.brandWhite),
                onPressed: () => context.pop(),
              ),
            ),
            Expanded(
              child: Center(child: Text(text, style: GoogleFonts.inter(color: AppColors.brandWhite, fontSize: 14))),
            ),
          ],
        ),
      );
}

class _Rail extends ConsumerWidget {
  final Content content;
  final String uid;
  final VoidCallback onComment;
  final VoidCallback onShare;

  const _Rail({required this.content, required this.uid, required this.onComment, required this.onShare});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(interactionRepositoryProvider);
    Widget action(IconData icon, int count, VoidCallback onTap, {Color color = AppColors.brandWhite}) => GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Column(
              children: [
                Icon(icon, color: color, size: 30, shadows: const [Shadow(blurRadius: 6)]),
                const SizedBox(height: 2),
                Text('$count',
                    style: GoogleFonts.inter(
                      color: AppColors.brandWhite,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      shadows: const [Shadow(blurRadius: 4)],
                    )),
              ],
            ),
          ),
        );

    return Column(
      children: [
        StreamBuilder<bool>(
          stream: uid.isEmpty ? Stream.value(false) : repo.watchIsLiked(uid, content.id),
          builder: (context, s) {
            final liked = s.data ?? false;
            return action(
              liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              content.likeCount,
              () => liked ? repo.unlikeContent(uid, content.id) : repo.likeContent(uid, content.id),
              color: liked ? AppColors.brandPink : AppColors.brandWhite,
            );
          },
        ),
        action(Icons.mode_comment_outlined, content.commentCount, onComment),
        StreamBuilder<bool>(
          stream: uid.isEmpty ? Stream.value(false) : repo.watchIsSaved(uid, content.id),
          builder: (context, s) {
            final saved = s.data ?? false;
            return action(
              saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              content.saveCount,
              () => saved ? repo.unsaveContent(uid, content.id) : repo.saveContent(uid, content.id),
              color: saved ? AppColors.brandBlue : AppColors.brandWhite,
            );
          },
        ),
        action(Icons.share_rounded, content.shareCount, onShare),
      ],
    );
  }
}
