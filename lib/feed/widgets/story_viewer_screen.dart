import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:story_view/story_view.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:go_router/go_router.dart';
import '../../shared/theme/app_theme.dart';
import '../../backend/social/models/story.dart';
import '../../backend/social/services/story_service.dart';
import '../../backend/messaging_repository.dart';
import '../../backend/user_service.dart';

class StoryViewerScreen extends ConsumerStatefulWidget {
  final List<Story> stories;
  final String authorName;
  final String? authorAvatarUrl;
  final String? authorId;
  final bool isMine;

  const StoryViewerScreen({
    super.key,
    required this.stories,
    required this.authorName,
    this.authorAvatarUrl,
    this.authorId,
    this.isMine = false,
  });

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen> {
  final StoryController controller = StoryController();
  final StoryService _storyService = StoryService();
  final TextEditingController _replyController = TextEditingController();
  Player? _musicPlayer;
  String? _playingMusicUrl;

  /// Maps each flattened slide index in `StoryView` back to its parent `Story` index.
  final List<int> _slideToStoryIndex = [];

  int _currentIndex = 0;
  bool _isLiked = false;
  int _likeCount = 0;
  bool _isSendingReply = false;

  @override
  void initState() {
    super.initState();
    _syncStoryState(0);
    _recordViewForIndex(0);
  }

  void _syncStoryMusic(Story story) {
    final url = story.musicUrl?.trim() ?? '';
    if (url.isEmpty) {
      _playingMusicUrl = null;
      _musicPlayer?.setVolume(0.0);
      _musicPlayer?.pause();
      return;
    }
    if (_playingMusicUrl == url && _musicPlayer != null) {
      if (!_musicPlayer!.state.playing) {
        _musicPlayer!.setVolume(100.0);
        _musicPlayer!.play();
      }
      return;
    }
    _playingMusicUrl = url;
    _musicPlayer ??= Player();
    _musicPlayer!.setVolume(100.0);
    _musicPlayer!.setPlaylistMode(PlaylistMode.loop);
    _musicPlayer!.open(Media(url), play: true);
  }

  void _syncStoryState(int slideIndex) {
    final storyIdx = (slideIndex >= 0 && slideIndex < _slideToStoryIndex.length)
        ? _slideToStoryIndex[slideIndex]
        : slideIndex.clamp(0, widget.stories.length - 1);
    if (storyIdx >= 0 && storyIdx < widget.stories.length) {
      final story = widget.stories[storyIdx];
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      _syncStoryMusic(story);
      setState(() {
        _currentIndex = storyIdx;
        _isLiked = currentUid != null && story.likes.contains(currentUid);
        _likeCount = story.likes.length;
      });
    }
  }

  void _recordViewForIndex(int slideIndex) async {
    final storyIdx = (slideIndex >= 0 && slideIndex < _slideToStoryIndex.length)
        ? _slideToStoryIndex[slideIndex]
        : slideIndex.clamp(0, widget.stories.length - 1);
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null && storyIdx >= 0 && storyIdx < widget.stories.length) {
      final user = await ref.read(userProvider.notifier).getUser(currentUid);
      _storyService.recordStoryView(
        widget.stories[storyIdx].id,
        currentUid,
        viewerName: user?.fullName ?? user?.username ?? 'Viewer',
        viewerAvatar: user?.profilePhotoUrl ?? '',
      );
    }
  }

  @override
  void dispose() {
    _musicPlayer?.setVolume(0.0);
    _musicPlayer?.stop();
    _musicPlayer?.dispose();
    controller.dispose();
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || widget.stories.isEmpty) return;

    HapticFeedback.mediumImpact();
    final story = widget.stories[_currentIndex];
    final user = await ref.read(userProvider.notifier).getUser(currentUid);

    final newLiked = !_isLiked;
    setState(() {
      _isLiked = newLiked;
      _likeCount = newLiked ? _likeCount + 1 : (_likeCount > 0 ? _likeCount - 1 : 0);
    });

    await _storyService.toggleStoryLike(
      story.id,
      currentUid,
      userName: user?.fullName ?? user?.username ?? 'Viewer',
      userAvatar: user?.profilePhotoUrl ?? '',
      storyAuthorId: widget.authorId ?? story.authorId,
    );
  }

  Future<void> _sendReply(String message) async {
    final text = message.trim();
    if (text.isEmpty) return;

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final targetAuthorId = widget.authorId ?? (widget.stories.isNotEmpty ? widget.stories[_currentIndex].authorId : null);
    if (currentUid == null || targetAuthorId == null || targetAuthorId == currentUid) return;

    setState(() => _isSendingReply = true);
    HapticFeedback.lightImpact();

    try {
      final messagingRepo = ref.read(messagingRepositoryProvider);
      final chatId = await messagingRepo.getOrCreateDirectChat(currentUid, targetAuthorId);
      final storyUrl = widget.stories[_currentIndex].mediaUrl;
      final fullText = '💬 Replied to status: "$text"\n[Status Image: $storyUrl]';

      await messagingRepo.sendMessage(chatId, currentUid, fullText, recipientId: targetAuthorId);
      await _storyService.replyToStory(widget.stories[_currentIndex].id, currentUid, text);

      _replyController.clear();

      if (mounted) {
        FocusScope.of(context).unfocus();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reply sent to ${widget.authorName}!', style: const TextStyle(color: Colors.white)),
            backgroundColor: AppColors.brandBlue,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send reply: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingReply = false);
      }
    }
  }

  void _showViewersAndInsightsSheet(BuildContext context) {
    controller.pause();
    final story = widget.stories[_currentIndex];

    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DefaultTabController(
          length: 2,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.65,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                TabBar(
                  indicatorColor: AppColors.brandPink,
                  labelColor: context.textPrimary,
                  unselectedLabelColor: context.textMuted,
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.visibility_rounded, size: 16, color: AppColors.brandBlue),
                          const SizedBox(width: 6),
                          Text('Views (${story.viewers.length})', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.favorite_rounded, size: 16, color: AppColors.brandPink),
                          const SizedBox(width: 6),
                          Text('Likes ($_likeCount)', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TabBarView(
                    children: [
                      // Viewers Tab
                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _storyService.streamStoryViewers(story.id),
                        builder: (context, snapshot) {
                          final viewers = snapshot.data ?? [];
                          if (viewers.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.remove_red_eye_outlined, size: 36, color: Colors.white24),
                                  const SizedBox(height: 8),
                                  Text('No viewers yet', style: GoogleFonts.inter(color: context.textMuted)),
                                ],
                              ),
                            );
                          }
                          return ListView.builder(
                            itemCount: viewers.length,
                            itemBuilder: (context, index) {
                              final v = viewers[index];
                              final avatar = v['avatarUrl'] as String? ?? '';
                              final name = v['displayName'] as String? ?? 'Viewer';
                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: AppColors.brandBlue,
                                  backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                                  child: avatar.isEmpty ? Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white)) : null,
                                ),
                                title: Text(name, style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5)),
                                trailing: const Icon(Icons.visibility_rounded, color: AppColors.brandBlue, size: 16),
                              );
                            },
                          );
                        },
                      ),

                      // Likes Tab
                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _storyService.streamStoryLikes(story.id),
                        builder: (context, snapshot) {
                          final likes = snapshot.data ?? [];
                          if (likes.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.favorite_border_rounded, size: 36, color: Colors.white24),
                                  const SizedBox(height: 8),
                                  Text('No likes yet', style: GoogleFonts.inter(color: context.textMuted)),
                                ],
                              ),
                            );
                          }
                          return ListView.builder(
                            itemCount: likes.length,
                            itemBuilder: (context, index) {
                              final l = likes[index];
                              final avatar = l['avatarUrl'] as String? ?? '';
                              final name = l['displayName'] as String? ?? 'User';
                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: AppColors.brandPink,
                                  backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                                  child: avatar.isEmpty ? Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white)) : null,
                                ),
                                title: Text(name, style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5)),
                                trailing: const Icon(Icons.favorite_rounded, color: AppColors.brandPink, size: 18),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (dCtx) => AlertDialog(
                            backgroundColor: context.surface,
                            title: const Text('Delete this status?'),
                            content: const Text('This will permanently delete this status slide.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () => Navigator.pop(dCtx, true),
                                child: const Text('Delete', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await _storyService.deleteStory(story.id);
                          if (context.mounted) {
                            Navigator.pop(ctx);
                            context.pop();
                          }
                        }
                      },
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                      label: const Text('Delete Status', style: TextStyle(color: Colors.redAccent)),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showStorySettingsSheet(context);
                      },
                      icon: const Icon(Icons.settings_outlined, color: AppColors.brandBlue, size: 18),
                      label: const Text('Status Settings', style: TextStyle(color: AppColors.brandBlue)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      controller.play();
    });
  }

  void _showStorySettingsSheet(BuildContext context) {
    controller.pause();
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lock_person_rounded, color: AppColors.brandBlue, size: 22),
                    const SizedBox(width: 10),
                    Text('Status Privacy', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary)),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Choose who can view your active status updates:', style: GoogleFonts.inter(fontSize: 13, color: context.textSecondary)),
                const SizedBox(height: 16),
                _buildPrivacyTile(ctx, 'Public', 'Everyone on Oneova can view', Icons.public_rounded),
                _buildPrivacyTile(ctx, 'Followers Only', 'Only people who follow you', Icons.people_alt_rounded),
                _buildPrivacyTile(ctx, 'Close Friends', 'Only your selected VIP close circle', Icons.stars_rounded),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() => controller.play());
  }

  Widget _buildPrivacyTile(BuildContext ctx, String title, String subtitle, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: AppColors.brandBlue),
      title: Text(title, style: TextStyle(color: ctx.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
      subtitle: Text(subtitle, style: TextStyle(color: ctx.textMuted, fontSize: 12)),
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.pop(ctx);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status privacy set to: $title'),
            backgroundColor: AppColors.brandBlue,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stories.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('No active stories', style: GoogleFonts.inter(color: Colors.white70)),
        ),
      );
    }

    final currentStory = widget.stories[_currentIndex.clamp(0, widget.stories.length - 1)];

    _slideToStoryIndex.clear();
    final storyItems = <StoryItem>[];
    for (var sIdx = 0; sIdx < widget.stories.length; sIdx++) {
      final s = widget.stories[sIdx];
      if (s.mediaType == StoryMediaType.video) {
        _slideToStoryIndex.add(sIdx);
        storyItems.add(
          StoryItem.pageVideo(
            s.mediaUrl,
            controller: controller,
            duration: const Duration(seconds: 15),
            caption: s.caption != null && s.caption!.trim().isNotEmpty
                ? Text(
                    s.caption!.trim(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          ),
        );
      } else if (s.mediaType == StoryMediaType.text) {
        _slideToStoryIndex.add(sIdx);
        storyItems.add(
          StoryItem.text(
            title: s.caption?.trim().isNotEmpty == true ? s.caption!.trim() : s.mediaUrl,
            backgroundColor: AppColors.brandBlue,
            textStyle: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      } else {
        final urls = s.mediaUrls.isNotEmpty
            ? s.mediaUrls
            : (s.mediaUrl.isNotEmpty ? [s.mediaUrl] : const <String>[]);
        for (final imgUrl in urls) {
          _slideToStoryIndex.add(sIdx);
          storyItems.add(
            StoryItem.pageImage(
              url: imgUrl,
              controller: controller,
              duration: const Duration(seconds: 6),
              caption: s.caption != null && s.caption!.trim().isNotEmpty
                  ? Text(
                      s.caption!.trim(),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
          );
        }
      }
    }

    final avatar = widget.authorAvatarUrl ?? currentStory.authorAvatarUrl;
    final hasMusic = (currentStory.musicTitle ?? '').trim().isNotEmpty ||
        (currentStory.musicUrl ?? '').trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── StoryView Player ──────────────────────────────────────
          StoryView(
            storyItems: storyItems,
            controller: controller,
            onStoryShow: (item, index) {
              _syncStoryState(index);
              _recordViewForIndex(index);
            },
            onComplete: () {
              if (mounted) context.pop();
            },
            onVerticalSwipeComplete: (direction) {
              if (direction == Direction.down) {
                context.pop();
              } else if (direction == Direction.up && widget.isMine) {
                _showViewersAndInsightsSheet(context);
              }
            },
          ),

          // ── Top Author Header ─────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.brandBlue,
                    backgroundImage: avatar.isNotEmpty
                        ? NetworkImage(avatar)
                        : null,
                    child: avatar.isEmpty
                        ? Text(widget.authorName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.authorName,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.verified, color: AppColors.brandBlue, size: 14),
                          ],
                        ),
                        Text(
                          timeago.format(currentStory.createdAt),
                          style: GoogleFonts.inter(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                        if (hasMusic) ...[
                          const SizedBox(height: 3),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.music_note_rounded,
                                color: AppColors.brandPink,
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  [
                                    if ((currentStory.musicTitle ?? '').trim().isNotEmpty)
                                      currentStory.musicTitle!.trim()
                                    else
                                      'Attached Music',
                                    if ((currentStory.musicArtist ?? '').trim().isNotEmpty)
                                      currentStory.musicArtist!.trim(),
                                  ].join(' • '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.isMine)
                    IconButton(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      onPressed: () => _showStorySettingsSheet(context),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom Interaction Dock ───────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: widget.isMine
                    ? GestureDetector(
                        onTap: () => _showViewersAndInsightsSheet(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white70, size: 20),
                              const SizedBox(width: 6),
                              Text(
                                '${currentStory.viewers.length} views  •  $_likeCount likes',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Quick reaction emojis
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: ['🔥', '❤️', '👏', '😂', '😮', '💯'].map((emoji) {
                              return GestureDetector(
                                onTap: () => _sendReply(emoji),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(emoji, style: const TextStyle(fontSize: 18)),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: TextField(
                                    controller: _replyController,
                                    style: const TextStyle(color: Colors.white),
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: _sendReply,
                                    decoration: InputDecoration(
                                      hintText: 'Reply to ${widget.authorName}...',
                                      hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                                      border: InputBorder.none,
                                      suffixIcon: _isSendingReply
                                          ? const Padding(
                                              padding: EdgeInsets.all(12),
                                              child: SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                              ),
                                            )
                                          : IconButton(
                                              icon: const Icon(Icons.send_rounded, color: AppColors.brandPink, size: 18),
                                              onPressed: () => _sendReply(_replyController.text),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: _toggleLike,
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _isLiked ? AppColors.brandPink : Colors.white.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: Icon(
                                    _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ],
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
