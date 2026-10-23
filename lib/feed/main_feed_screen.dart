import 'package:oneova/shared/widgets/animated_loading_indicator.dart';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../social_hub/profile/public_profile_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:oneova/backend/social/models/content.dart';
import 'package:oneova/backend/social/models/relationship.dart';
import 'package:oneova/backend/social/repositories/interaction_repository.dart';
import 'package:oneova/backend/social/repositories/relationship_repository.dart';
import 'package:oneova/backend/social/services/video_playback_manager.dart';
import 'package:oneova/backend/social/services/recommendation_service.dart';
import 'package:oneova/backend/social/services/story_service.dart';
import 'package:oneova/backend/observability/performance_monitor.dart';
import 'package:oneova/backend/user_service.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/backend/messaging_repository.dart';
import 'package:oneova/shared/widgets/creation_type_modal.dart';
import 'package:oneova/backend/notifications/providers/notification_service.dart';
import '../social_hub/feed/widgets/author_side_panel.dart';
import 'widgets/comment_bottom_sheet.dart';
import 'package:oneova/backend/social/models/comment.dart';
import 'package:oneova/backend/social/services/comment_service.dart';
import 'widgets/story_viewer_screen.dart';
import 'providers/oneova_focus_mode_provider.dart';
import 'providers/live_activity_provider.dart';
import 'widgets/oneova_quick_privacy_sheet.dart';
import 'widgets/oneova_live_activity_overlay.dart';
import 'widgets/reel_likes_bottom_sheet.dart';
import '../backend/live/services/live_service.dart';
import '../backend/live/models/live_models.dart';
import '../backend/notifications/services/follower_alert_service.dart';
import 'widgets/live_feed_card.dart';
import 'widgets/reel_palette.dart';
import 'widgets/rolling_count.dart';
import 'widgets/reel_comment_bar.dart';
import 'widgets/circle_gesture_detector.dart';
import '../providers/settings_provider.dart';

import 'package:oneova/backend/social/models/audio_track.dart';
import 'package:oneova/backend/social/repositories/audio_track_repository.dart';
import 'package:oneova/backend/recommendation/algorithm/oneova_algorithm_models.dart';
import 'package:oneova/backend/recommendation/algorithm/online_feature_store.dart';
import '../auth/widgets/auth_interaction_gate.dart';
import '../backend/routing/oneova_share_engine.dart';
import '../shared/widgets/advanced_voice_interface.dart';
import '../widgets/oneova_assistant_overlay.dart';
import 'dart:async';
import 'dart:ui';

class ShortVideoFeedScreen extends ConsumerStatefulWidget {
  final FeedMode initialMode;
  final String? initialVideoId;

  const ShortVideoFeedScreen({
    super.key,
    this.initialMode = FeedMode.forYou,
    this.initialVideoId,
  });

  @override
  ConsumerState<ShortVideoFeedScreen> createState() => _ShortVideoFeedScreenState();
}

class _ShortVideoFeedScreenState extends ConsumerState<ShortVideoFeedScreen> {
  late PageController _pageController;
  int _currentIndex = 0;
  DateTime _currentVideoStartTime = DateTime.now();
  
  FeedMode _currentMode = FeedMode.forYou;
  List<Content> _feed = [];
  /// What the PageView actually scrolls: reels from [_feed] plus live
  /// sessions ([LiveFeedSlot]) slotted in between as creators go live.
  List<Object> _pages = [];
  int _currentPage = 0;
  static const int _maxLiveSlots = 8;
  bool _isLoading = true;
  bool _isAutoScrollEnabled = false;
  bool _isLoopModeEnabled = true;
  StreamSubscription? _playerCompletionSub;

  // Focus mode: enters by itself once a reel has played for 3s, then
  // stays until the user presses Back or draws a circle (which opens Ova).
  static const Duration _autoFocusAfter = Duration(seconds: 3);
  bool _autoFocusArmed = true;
  Timer? _autoFocusTimer;
  Duration _playedFor = Duration.zero;
  ReelPalette _palette = const ReelPalette(dark: true);

  /// Applies `user_settings.playback` (Settings → Reels & Playback).
  void _applyPlaybackPrefs(Map<String, dynamic>? settings) {
    final playback = settings?['playback'];
    if (playback is! Map) return;
    final auto = playback['autoScroll'] as bool? ?? _isAutoScrollEnabled;
    final loop = playback['loopVideos'] as bool? ?? _isLoopModeEnabled;
    if (auto != _isAutoScrollEnabled) {
      _isAutoScrollEnabled = auto;
      _attachAutoScrollListener();
    }
    if (loop != _isLoopModeEnabled) _updateLoopMode(loop, persist: false);
  }

  void _savePlaybackPref(String key, bool value) {
    ref.read(settingsProvider.notifier).updateSetting('playback', key, value);
  }

  void _attachAutoScrollListener() {
    _playerCompletionSub?.cancel();
    _playerCompletionSub = null;
    if (!_isAutoScrollEnabled || _feed.isEmpty || _currentIndex >= _feed.length) return;

    final currentItem = _feed[_currentIndex];
    final player = ref.read(videoPlaybackManagerProvider).getPlayer(currentItem.id);
    if (player != null) {
      _playerCompletionSub = player.stream.completed.listen((isCompleted) {
        if (isCompleted && _isAutoScrollEnabled && mounted && _currentPage < _pages.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeInOutCubic,
          );
        }
      });
    }
  }

  void _updateLoopMode(bool looping, {bool persist = true}) {
    if (persist) _savePlaybackPref('loopVideos', looping);
    if (mounted) {
      setState(() {
        _isLoopModeEnabled = looping;
      });
    }
    if (_feed.isNotEmpty && _currentIndex < _feed.length) {
      ref.read(videoPlaybackManagerProvider).setLooping(_feed[_currentIndex].id, looping);
    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint('[ShortVideoFeedScreen] initState called');
    _currentMode = widget.initialMode;
    _pageController = PageController(initialPage: 0);
    final playback = ref.read(settingsProvider).value?['playback'];
    if (playback is Map) {
      _isAutoScrollEnabled = playback['autoScroll'] as bool? ?? _isAutoScrollEnabled;
      _isLoopModeEnabled = playback['loopVideos'] as bool? ?? _isLoopModeEnabled;
    }
    _loadFeed();
  }

  /// Counts continuous playback of the current reel; at 3s enters focus mode
  /// (once). Skips while another tab/route is on top or a live card is shown.
  void _scheduleAutoFocus() {
    _autoFocusTimer?.cancel();
    _playedFor = Duration.zero;
    if (!_autoFocusArmed) return;
    const tick = Duration(milliseconds: 500);
    _autoFocusTimer = Timer.periodic(tick, (t) {
      if (!mounted || !_autoFocusArmed) return t.cancel();
      if (ref.read(oneovaFocusModeProvider)) return t.cancel();
      final visible = TickerMode.valuesOf(context).enabled && (ModalRoute.of(context)?.isCurrent ?? true);
      final item = _currentPage < _pages.length ? _pages[_currentPage] : null;
      final playing = item is Content &&
          (ref.read(videoPlaybackManagerProvider).getController(item.id)?.player.state.playing ?? false);
      _playedFor = (visible && playing) ? _playedFor + tick : Duration.zero;
      if (_playedFor >= _autoFocusAfter) {
        t.cancel();
        ref.read(oneovaFocusModeProvider.notifier).set(true);
      }
    });
  }

  /// Focus mode hides the status bar too; only Back (or a circle) leaves it.
  void _onFocusChanged(bool focus) {
    SystemChrome.setEnabledSystemUIMode(focus ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    if (focus) {
      _autoFocusArmed = false; // one time only
      _autoFocusTimer?.cancel();
    }
  }

  /// Circle drawn in focus mode: leave it and bring up Ova for this reel.
  void _summonAssistant() {
    HapticFeedback.mediumImpact();
    final item = _currentPage < _pages.length ? _pages[_currentPage] : null;
    ref.read(oneovaFocusModeProvider.notifier).set(false);
    OneOvaAssistantOverlay.show(
      context,
      userId: FirebaseAuth.instance.currentUser?.uid,
      contentId: item is Content ? item.id : null,
      initialPrompt: item is Content ? 'Tell me about this reel: "${item.description}"' : null,
    );
  }

  Future<void> _loadFeed() async {
    debugPrint('[ShortVideoFeedScreen] _loadFeed started');
    final perfMonitor = ref.read(performanceMonitorProvider);
    
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      if (uid != 'unknown') {
        ref.read(onlineFeatureStoreProvider).hydrateProfile(uid);
      }
      List<Content> recommendations = [];
      
      final rawFeed = await perfMonitor.measureApiLatency(
        'feed.fetchRecommendations',
        () => ref.read(recommendationServiceProvider).getFeed(uid, _currentMode)
      );

      recommendations = rawFeed;

      if (widget.initialVideoId != null && widget.initialVideoId!.isNotEmpty) {
        try {
          final targetDoc = await FirebaseFirestore.instance.collection('content').doc(widget.initialVideoId).get();
          if (targetDoc.exists) {
            final targetContent = Content.fromFirestore(targetDoc);
            recommendations.removeWhere((c) => c.id == targetContent.id);
            recommendations.insert(0, targetContent);
          }
        } catch (e) {
          debugPrint('Error fetching initial shared video: $e');
        }
      }
      
      if (mounted) {
        setState(() {
          _feed = recommendations;
          _pages = List<Object>.of(recommendations);
          _currentPage = 0;
          _isLoading = false;
        });
        _mergeLiveStreams(ref.read(activeLiveStreamsProvider).value ?? const []);
        
        if (_feed.isNotEmpty) {
          ref.read(videoPlaybackManagerProvider).initializeAndPreload(_feed, 0);
          _attachAutoScrollListener();
          _scheduleAutoFocus();
        }
      }
    } catch (e) {
      debugPrint('Error loading feed: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _autoFocusTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _playerCompletionSub?.cancel();
    _pageController.dispose();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      ref.read(onlineFeatureStoreProvider).flushProfile(uid);
    }
    ref.read(videoPlaybackManagerProvider).disposeAll();
    super.dispose();
  }

  /// Slots live sessions into the scroll. On first load they are spread
  /// through the feed; streams that start later are placed right after the
  /// current page so the next swipe lands on them. Ended sessions stay where
  /// they are and flip to their "ended" state.
  void _mergeLiveStreams(List<LiveStream> streams) {
    if (!mounted || _isLoading) return;
    final present = _pages.whereType<LiveFeedSlot>().map((l) => l.streamId).toSet();
    final followed = (ref.read(followedCreatorAlertsProvider).value ?? const [])
        .map((c) => c.creatorId)
        .toSet();
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final candidates = streams
        .where((s) => !present.contains(s.id) && s.hostId != myUid && s.audienceMode != 'private')
        .where((s) => _currentMode != FeedMode.following || followed.contains(s.hostId))
        .toList()
      ..sort((a, b) {
        final fa = followed.contains(a.hostId) ? 0 : 1;
        final fb = followed.contains(b.hostId) ? 0 : 1;
        return fa != fb ? fa - fb : b.viewerCount - a.viewerCount;
      });
    final room = _maxLiveSlots - present.length;
    if (candidates.isEmpty || room <= 0) return;

    setState(() {
      final firstLoad = present.isEmpty && _currentPage == 0;
      var insertAt = firstLoad ? math.min(1, _pages.length) : _currentPage + 1;
      for (final stream in candidates.take(room)) {
        _pages.insert(math.min(insertAt, _pages.length), LiveFeedSlot(stream));
        insertAt += firstLoad ? 5 : 1;
      }
    });
  }

  void _onPageChanged(int page) {
    final previousWasVideo = _currentPage < _pages.length && _pages[_currentPage] is Content;
    _currentPage = page;
    final item = page < _pages.length ? _pages[page] : null;
    if (item is! Content) {
      // Live card: every reel goes inactive (and pauses) while it is on screen.
      _playerCompletionSub?.cancel();
      _currentVideoStartTime = DateTime.now();
      setState(() {});
      return;
    }
    final index = _feed.indexOf(item);
    if (index < 0) return;

    final recommendationService = ref.read(recommendationServiceProvider);
    final now = DateTime.now();
    final dwellMs = now.difference(_currentVideoStartTime).inMilliseconds;
    _currentVideoStartTime = now;
    
    if (previousWasVideo && _feed.isNotEmpty && _currentIndex < _feed.length) {
      final prevVideo = _feed[_currentIndex];
      final videoDurationMs = prevVideo.mediaMetadata.duration?.inMilliseconds ?? 15000;
      final completionRate = (dwellMs / videoDurationMs).clamp(0.0, 5.0);
      final loopCount = (dwellMs / videoDurationMs).floor();
      final isFastSkip = dwellMs < 1500;

      final telemetry = VideoWatchTelemetry(
        userId: FirebaseAuth.instance.currentUser?.uid ?? 'currentUser',
        contentId: prevVideo.id,
        authorId: prevVideo.authorId,
        hashtags: prevVideo.hashtags,
        audioTrackId: prevVideo.mediaMetadata.musicId,
        dwellTimeMs: dwellMs,
        videoDurationMs: videoDurationMs,
        completionRate: completionRate,
        loopCount: loopCount,
        isFastSkip: isFastSkip,
        timestamp: now,
      );
      recommendationService.recordWatchTelemetry(telemetry);
    }

    setState(() {
      _currentIndex = index;
    });

    ref.read(videoPlaybackManagerProvider).initializeAndPreload(_feed, index);
    _attachAutoScrollListener();
    _scheduleAutoFocus();
    if (_feed.isNotEmpty && index < _feed.length) {
      ref.read(videoPlaybackManagerProvider).setLooping(_feed[index].id, _isLoopModeEnabled);
    }
    
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'currentUser';
    if (index < _feed.length) {
      ref.read(interactionRepositoryProvider).recordView(uid, _feed[index].id);
      recommendationService.trackEvent(uid, _feed[index].id, ContentInteractionType.impression, {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reels follow Light / Dark mode unless the user pinned them to dark.
    final reelsTheme = (ref.watch(settingsProvider).value?['playback'] as Map?)?['reelsTheme'];
    _palette = ReelPalette(dark: reelsTheme == 'dark' || Theme.of(context).brightness == Brightness.dark);
    ref.listen<AsyncValue<Map<String, dynamic>>>(settingsProvider, (_, next) => _applyPlaybackPrefs(next.value));

    if (_isLoading) {
      return Scaffold(
        backgroundColor: _palette.bg,
        body: const Center(child: AnimatedLoadingIndicator()),
      );
    }

    final isFocusMode = ref.watch(oneovaFocusModeProvider);
    ref.listen<bool>(oneovaFocusModeProvider, (_, next) => _onFocusChanged(next));
    // Keeps the follow list warm for live-slot ranking.
    ref.watch(followedCreatorAlertsProvider);
    ref.listen<AsyncValue<List<LiveStream>>>(activeLiveStreamsProvider, (_, next) {
      final streams = next.value;
      if (streams != null) _mergeLiveStreams(streams);
    });

    return PopScope(
      // Back is the only way out of focus mode (taps and double-taps are not).
      canPop: !isFocusMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isFocusMode) {
          HapticFeedback.lightImpact();
          ref.read(oneovaFocusModeProvider.notifier).set(false);
        }
      },
      child: ReelTheme(
      palette: _palette,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: _palette.systemOverlay,
      child: Scaffold(
      backgroundColor: _palette.bg,
      extendBodyBehindAppBar: true,
      body: OneovaCircleGesture(
        enabled: isFocusMode,
        onCircle: _summonAssistant,
        child: Stack(
        children: [
          if (_pages.isEmpty)
            _buildEmptyState()
          else
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              onPageChanged: _onPageChanged,
              itemCount: _pages.length,
              itemBuilder: (context, index) {
                final item = _pages[index];
                if (item is LiveFeedSlot) {
                  return LiveFeedCard(
                    key: ValueKey('live_${item.streamId}'),
                    initial: item.initial,
                    isActive: index == _currentPage,
                    onSkip: () => _pageController.nextPage(
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeInOutCubic,
                    ),
                  );
                }
                final content = item as Content;
                return _buildCinemaFrame(
                  index: index,
                  cinema: isFocusMode,
                  child: _ShortVideoItem(
                    key: ValueKey(content.id),
                    content: content,
                    isActive: index == _currentPage,
                    isFullScreen: isFocusMode,
                  ),
                );
              },
            ),

          // Legibility scrims behind the top row/stories and the caption block
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildScrim(
              height: MediaQuery.paddingOf(context).top + 150,
              top: true,
              visible: !isFocusMode,
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildScrim(height: 300, top: false, visible: !isFocusMode),
          ),

          // Top ambient navigation & stories overlay (slides & fades out in focus mode)
          SafeArea(
            child: AnimatedSlide(
              offset: isFocusMode ? const Offset(0, -0.6) : Offset.zero,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubic,
              child: AnimatedOpacity(
                opacity: isFocusMode ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 220),
                child: IgnorePointer(
                  ignoring: isFocusMode,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: _buildTopOverlay(),
                  ),
                ),
              ),
            ),
          ),

        ],
      ),
      ),
    ),
      ),
      ),
    );
  }


  /// Cinematic frame for focus mode: the full-screen reel gets curved corners,
  /// and while scrolling the outgoing/incoming reels shrink and dim slightly so
  /// pages feel like cards sliding past each other.
  Widget _buildCinemaFrame({required int index, required bool cinema, required Widget child}) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: cinema ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
      child: child,
      builder: (context, t, child) {
        if (t == 0.0) return child!;
        return AnimatedBuilder(
          animation: _pageController,
          child: child,
          builder: (context, child) {
            double page = _currentPage.toDouble();
            if (_pageController.hasClients && _pageController.position.haveDimensions) {
              page = _pageController.page ?? page;
            }
            final delta = (page - index).abs().clamp(0.0, 1.0);
            final scale = 1.0 - 0.06 * delta * t;
            return Opacity(
              opacity: (1.0 - 0.35 * delta * t).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: scale,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(34.0 * t),
                  child: child,
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Soft gradient that keeps overlay text legible over bright video frames.
  Widget _buildScrim({required double height, required bool top, required bool visible}) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 220),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [
                _palette.scrim.withValues(alpha: _palette.scrimStrength),
                _palette.scrim.withValues(alpha: _palette.scrimStrength * 0.4),
                _palette.scrim.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brandBlue.withValues(alpha: 0.18),
                border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.5)),
              ),
              child: Icon(Icons.play_circle_outline_rounded, color: _palette.fg, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              _currentMode == FeedMode.following ? 'No reels from people you follow yet' : 'No reels yet',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: _palette.fg, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.2),
            ),
            const SizedBox(height: 6),
            Text(
              'Discover creators or pull in the latest reels.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: _palette.fgSoft, fontSize: 12.5),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FeedPillButton(
                  label: 'Discover',
                  icon: Icons.explore_outlined,
                  filled: true,
                  onTap: () => context.push('/hub/discover'),
                ),
                const SizedBox(width: 10),
                _FeedPillButton(
                  label: 'Refresh',
                  icon: Icons.refresh_rounded,
                  onTap: () {
                    setState(() => _isLoading = true);
                    _loadFeed();
                  },
                ),
              ],
            ),
          ],
        ),
      ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0),
    );
  }

  Widget _buildTopTabItem(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              style: GoogleFonts.inter(
                color: isSelected ? _palette.fg : _palette.fgSoft,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 14,
                letterSpacing: -0.2,
                shadows: _palette.textShadow,
              ),
              child: Text(label),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              width: isSelected ? 16 : 0,
              height: 2.5,
              decoration: BoxDecoration(
                color: isSelected ? (_palette.dark ? Colors.white : AppColors.brandBlue) : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.brandBlue.withValues(alpha: 0.9),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchButton() {
    return _GlassIconButton(
      icon: Icons.search_rounded,
      tooltip: 'Search',
      onTap: () {
        AuthInteractionGate.requireAuth(
          context,
          actionTitle: 'search creators and trends',
          onAuthenticated: () => context.push('/hub/discover'),
        );
      },
    );
  }

  Widget _buildFeedTabs() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTopTabItem(
          'Following',
          _currentMode == FeedMode.following,
          () {
            setState(() {
              _currentMode = FeedMode.following;
              _currentIndex = 0;
              _currentPage = 0;
            });
            _loadFeed();
          },
        ),
        const SizedBox(width: 18),
        _buildTopTabItem(
          'For You',
          _currentMode == FeedMode.forYou,
          () {
            setState(() {
              _currentMode = FeedMode.forYou;
              _currentIndex = 0;
              _currentPage = 0;
            });
            _loadFeed();
          },
        ),
        const SizedBox(width: 18),
        _buildTopTabItem(
          'Biz',
          false,
          () {
            context.push('/biz_feed');
          },
        ),
      ],
    );
  }

  /// Landscape has little height: one row with search, tabs, the playback
  /// dock and the bell. Stories stay in portrait.
  Widget _buildLandscapeTopRow() {
    return Align(
      alignment: Alignment.topCenter,
      child: Row(
      children: [
        _buildSearchButton(),
        const SizedBox(width: 12),
        Expanded(child: Center(heightFactor: 1, child: _buildFeedTabs())),
        const SizedBox(width: 12),
        _buildReelControlDock(),
        const SizedBox(width: 10),
        const _RingingBell(),
      ],
      ),
    );
  }

  Widget _buildTopOverlay() {
    if (MediaQuery.orientationOf(context) == Orientation.landscape) {
      return _buildLandscapeTopRow();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Nav Bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSearchButton(),
            _buildFeedTabs(),
            const _RingingBell(),
          ],
        ),
        const SizedBox(height: 4),
        // Stories
        SizedBox(
          height: 70,
          child: Builder(
            builder: (context) {
              final storiesAsync = ref.watch(feedStoriesStreamProvider);
              final storyGroups = storiesAsync.value ?? [];
              final liveStreamsAsync = ref.watch(activeLiveStreamsProvider);
              final activeLiveStreams = liveStreamsAsync.value ?? [];
              final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
              final currentUserAsync = ref.watch(currentUserProfileProvider);
              final currentUser = currentUserAsync.value;
              final myAvatarUrl = (currentUser?.profilePhotoUrl != null && currentUser!.profilePhotoUrl!.isNotEmpty)
                  ? currentUser.profilePhotoUrl!
                  : (FirebaseAuth.instance.currentUser?.photoURL ?? '');

              // Check if current user has an active unexpired status
              UserStoryGroup? myGroup;
              for (final g in storyGroups) {
                if (g.authorId == currentUserId && g.stories.isNotEmpty) {
                  myGroup = g;
                  break;
                }
              }
              final bool hasMyStatus = myGroup != null && myGroup.stories.isNotEmpty;

              // Filter out current user and ensure only authors who have active stories appear
              final otherStoryGroups = storyGroups
                  .where((g) => g.authorId != currentUserId && g.stories.isNotEmpty)
                  .toList();

              return ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 2),
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      final activeGroup = myGroup;
                      if (hasMyStatus && activeGroup != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StoryViewerScreen(
                              stories: activeGroup.stories,
                              authorName: 'Your Story',
                              isMine: true,
                            ),
                          ),
                        );
                      } else {
                        context.push('/create/camera');
                      }
                    },
                    onLongPress: () {
                      HapticFeedback.mediumImpact();
                      context.push('/create/camera');
                    },
                    child: _buildStoryBubble(
                      'Your Story',
                      myAvatarUrl,
                      isAdd: !hasMyStatus,
                      hasRing: hasMyStatus,
                    ),
                  ),
                  ...activeLiveStreams.map((stream) {
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        context.push('/live/viewer/${stream.id}');
                      },
                      child: _buildStoryBubble(
                        stream.hostDisplayName.isNotEmpty ? stream.hostDisplayName : 'Live Stage',
                        stream.hostAvatarUrl.isNotEmpty
                            ? stream.hostAvatarUrl
                            : 'assets/images/oneova_logo.jpg',
                        isLive: true,
                      ),
                    );
                  }),
                  ...otherStoryGroups.map((group) {
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StoryViewerScreen(
                              stories: group.stories,
                              authorName: group.authorName,
                              isMine: false,
                            ),
                          ),
                        );
                      },
                      child: _buildStoryBubble(
                        group.authorName,
                        group.authorAvatarUrl,
                        hasRing: group.hasUnviewed,
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        // Executive Reel Control Dock
        Align(
          alignment: Alignment.centerLeft,
          child: _buildReelControlDock(),
        ),
      ],
    );
  }

  Widget _buildReelControlDock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _palette.glass,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: _palette.glassBorder, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Auto-scroll toggle
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _isAutoScrollEnabled = !_isAutoScrollEnabled;
              });
              _savePlaybackPref('autoScroll', _isAutoScrollEnabled);
              _attachAutoScrollListener();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_isAutoScrollEnabled ? 'Auto-Scroll ON: Reels advance automatically' : 'Auto-Scroll OFF'),
                  backgroundColor: _isAutoScrollEnabled ? AppColors.brandBlue : AppColors.darkSurface,
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isAutoScrollEnabled ? Icons.motion_photos_auto : Icons.motion_photos_off_rounded,
                  size: 13,
                  color: _isAutoScrollEnabled ? AppColors.brandPink : _palette.fgSoft,
                ),
                const SizedBox(width: 3.5),
                Text(
                  'Auto',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: _isAutoScrollEnabled ? FontWeight.w800 : FontWeight.w600,
                    color: _isAutoScrollEnabled ? AppColors.brandPink : _palette.fgSoft,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 10,
            width: 1,
            color: _palette.divider,
            margin: const EdgeInsets.symmetric(horizontal: 6),
          ),
          // Loop toggle
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _updateLoopMode(!_isLoopModeEnabled);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isLoopModeEnabled ? Icons.repeat_rounded : Icons.repeat_one_rounded,
                  size: 13,
                  color: _isLoopModeEnabled ? AppColors.brandPink : _palette.fgSoft,
                ),
                const SizedBox(width: 3.5),
                Text(
                  _isLoopModeEnabled ? 'Loop' : 'Once',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: _isLoopModeEnabled ? FontWeight.w800 : FontWeight.w600,
                    color: _isLoopModeEnabled ? AppColors.brandPink : _palette.fgSoft,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 10,
            width: 1,
            color: _palette.divider,
            margin: const EdgeInsets.symmetric(horizontal: 6),
          ),
          // Full Screen Immersion toggle
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              ref.read(oneovaFocusModeProvider.notifier).set(true);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fullscreen_rounded, size: 14, color: _palette.fg),
                const SizedBox(width: 2.5),
                Text(
                  'Focus',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _palette.fg,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildStoryBubble(String name, String image, {bool isAdd = false, bool hasRing = false, bool isLive = false}) {
    final bool isNetwork = image.isNotEmpty && image.startsWith('http');
    final bool isAsset = image.isNotEmpty && image.startsWith('assets/');
    final bool ringed = hasRing || isLive;

    Widget avatar = Container(
      decoration: ringed
          ? BoxDecoration(
              shape: BoxShape.circle,
              gradient: isLive
                  ? null
                  : const LinearGradient(
                      colors: [AppColors.brandBlue, AppColors.brandPink],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              color: isLive ? AppColors.brandPink : null,
            )
          : BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _palette.glassBorder, width: 1.0),
            ),
      padding: const EdgeInsets.all(2),
      child: Container(
        decoration: BoxDecoration(shape: BoxShape.circle, color: _palette.bg),
        padding: const EdgeInsets.all(1.5),
        child: CircleAvatar(
          radius: 19,
          backgroundColor: _palette.placeholder,
          backgroundImage: isNetwork
              ? NetworkImage(image)
              : isAsset
                  ? AssetImage(image) as ImageProvider
                  : const AssetImage('assets/images/oneova_logo.jpg') as ImageProvider,
          child: (!isNetwork && !isAsset)
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'O',
                  style: GoogleFonts.inter(color: _palette.fg, fontSize: 12, fontWeight: FontWeight.w800),
                )
              : null,
        ),
      ),
    );

    if (isLive) {
      // Gentle breathing pulse so live hosts stand out in the row
      avatar = avatar
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(begin: 1.0, end: 1.05, duration: 900.ms, curve: Curves.easeInOut);
    }

    return SizedBox(
      width: 54,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                avatar,
                if (isAdd)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        color: AppColors.brandBlue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.2),
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 11),
                    ),
                  ),
                if (isLive)
                  Positioned(
                    bottom: -3,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.brandPink,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                          border: Border.all(color: _palette.bg, width: 1.0),
                        ),
                        child: Text(
                          'LIVE',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 7.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              name,
              style: GoogleFonts.inter(
                color: _palette.fg,
                fontSize: 10.0,
                fontWeight: FontWeight.w600,
                shadows: _palette.textShadow,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 250.ms).slideX(begin: 0.12, end: 0, curve: Curves.easeOutCubic);
  }
}

class _ShortVideoItem extends ConsumerStatefulWidget {
  final Content content;
  final bool isActive;
  final bool isFullScreen;

  const _ShortVideoItem({
    super.key,
    required this.content,
    required this.isActive,
    this.isFullScreen = false,
  });

  @override
  ConsumerState<_ShortVideoItem> createState() => _ShortVideoItemState();
}

class _ShortVideoItemState extends ConsumerState<_ShortVideoItem> with TickerProviderStateMixin {
  bool get _landscape => MediaQuery.orientationOf(context) == Orientation.landscape;
  double _itemHeight = 0;

  late AnimationController _vinylController;
  late AnimationController _likePulseController;
  late AnimationController _burstHeartController;
  AudioTrack? _audioTrack;
  bool _showAuthorPanel = false;

  /// Like state the user just asked for, shown until Firestore agrees
  /// (`users/{uid}/likes/{id}` and `content/{id}.likeCount` change together
  /// in one transaction). Cleared on failure, which rolls the UI back.
  bool? _pendingLiked;
  bool _serverLiked = false;
  int _serverLikeCount = 0;
  // likeCount the optimistic ±1 was applied to; once the live count moves
  // off it, the server value already includes this tap.
  int? _likeBaseCount;
  bool _likeBusy = false;
  // A tap made while a write is still in flight: applied when it finishes.
  bool? _queuedLiked;
  final GlobalKey<FloatingHeartsState> _floatingHeartsKey = GlobalKey<FloatingHeartsState>();

  bool? _optimisticIsSaved;
  int _optimisticSaveDelta = 0;

  int _optimisticShareDelta = 0;

  Offset? _lastTapPosition;
  Offset? _burstHeartPosition;
  bool _showBurstHeart = false;
  bool _followJustConfirmed = false;
  bool _captionExpanded = false;

  ReelPalette get _p => ReelPalette.of(context);

  @override
  void initState() {
    super.initState();
    _vinylController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _likePulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _burstHeartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _loadAudioTrack();
  }

  Future<void> _loadAudioTrack() async {
    final musicId = widget.content.mediaMetadata.musicId;
    if (musicId != null && musicId.isNotEmpty) {
      final track = await ref.read(audioTrackRepositoryProvider).getAudioTrack(musicId);
      if (mounted) {
        setState(() {
          _audioTrack = track;
        });
      }
    }
  }

  @override
  void dispose() {
    _burstHeartController.dispose();
    _likePulseController.dispose();
    _vinylController.dispose();
    super.dispose();
  }

  void _triggerDoubleTapLike(Offset position) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    AuthInteractionGate.requireAuth(
      context,
      actionTitle: 'like videos',
      onAuthenticated: () {
        final playback = ref.read(settingsProvider).value?['playback'];
        if (playback is! Map || playback['likeHaptics'] != false) HapticFeedback.mediumImpact();
        final alreadyLiked = _pendingLiked ?? _serverLiked;
        setState(() {
          _burstHeartPosition = position;
          _showBurstHeart = true;
        });
        _likePulseController.forward(from: 0.0);
        _floatingHeartsKey.currentState?.burst(count: 4);
        _burstHeartController.forward(from: 0.0).then((_) {
          if (mounted) {
            setState(() {
              _showBurstHeart = false;
            });
          }
        });

        // Double-tapping a reel you already like only plays the animation:
        // one like per user, so the count never moves twice.
        if (alreadyLiked) return;
        _setLiked(uid, true, source: 'double_tap');
      },
    );
  }

  /// Optimistic like/unlike with rollback. The count shown is the live
  /// `likeCount` plus or minus one only while the write is in flight.
  Future<void> _setLiked(String uid, bool liked, {String source = 'button'}) async {
    if (uid.isEmpty) return;
    if (_likeBusy) {
      // Show the latest intent now; write it once the current one lands.
      setState(() {
        _queuedLiked = liked;
        _pendingLiked = liked;
      });
      return;
    }
    setState(() {
      _likeBusy = true;
      _pendingLiked = liked;
      _likeBaseCount = _serverLikeCount;
    });
    final repo = ref.read(interactionRepositoryProvider);
    try {
      if (liked) {
        await repo.likeContent(uid, widget.content.id);
      } else {
        await repo.unlikeContent(uid, widget.content.id);
      }
      if (!liked) return;
      ref.read(recommendationServiceProvider).trackEvent(
        uid,
        widget.content.id,
        ContentInteractionType.like,
        {'source': source},
      );
      emitLiveReactionEvent(
        contentId: widget.content.id,
        reactionType: 'like',
        ref: ref,
      );
      ref.read(glowingLoveBurstProvider.notifier).trigger();
    } catch (e) {
      if (!mounted) return;
      setState(() => _pendingLiked = null);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Couldn\'t update like. Check your connection.')),
      );
    } finally {
      if (mounted) {
        setState(() => _likeBusy = false);
        final queued = _queuedLiked;
        _queuedLiked = null;
        if (queued != null && queued != liked) _setLiked(uid, queued, source: source);
      }
    }
  }

  void _togglePlay() {
    final manager = ref.read(videoPlaybackManagerProvider);
    
    manager.togglePlayPause(widget.content.id);
    
    final isPlaying = manager.getController(widget.content.id)?.player.state.playing ?? false;
    if (isPlaying) {
// 0
    } else {
// 0
    }
  }

  @override
  void didUpdateWidget(_ShortVideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      ref.read(videoPlaybackManagerProvider).ensureCurrentPlaying(widget.content.id);
    } else if (!widget.isActive && oldWidget.isActive) {
      ref.read(videoPlaybackManagerProvider).getPlayer(widget.content.id)?.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    final playbackManager = ref.watch(videoPlaybackManagerProvider);
    final controller = playbackManager.getController(widget.content.id);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // Enters focus mode; once in, taps never leave it (only Back does).
        if (widget.isFullScreen) return;
        HapticFeedback.lightImpact();
        ref.read(oneovaFocusModeProvider.notifier).set(true);
      },
      onDoubleTapDown: (details) {
        _lastTapPosition = details.localPosition;
      },
      onDoubleTap: () {
        _triggerDoubleTapLike(_lastTapPosition ?? const Offset(180, 320));
      },
      onLongPress: widget.isFullScreen ? null : () => _showFeedControls(context),
      onHorizontalDragEnd: (details) {
        if (widget.isFullScreen) return;
        if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
          // Swipe left -> Creator Profile
          Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(targetUserId: widget.content.authorId)));
        } else if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
          // Swipe right -> Comments
          _showComments(context);
        }
      },
      child: LayoutBuilder(builder: (context, box) {
        _itemHeight = box.maxHeight;
        return Stack(
        fit: StackFit.expand,
        children: [
          // ── Video Player ──────────────────────────────────
          if (controller != null)
            Video(
              controller: controller,
              fit: _landscape ? BoxFit.contain : BoxFit.cover,
              controls: NoVideoControls,
            )
          else
            _buildThumbnail(),

          // ── Floating Bursting Heart Animation on Double Tap ──────
          if (_showBurstHeart && _burstHeartPosition != null)
            Positioned(
              left: _burstHeartPosition!.dx - 50,
              top: _burstHeartPosition!.dy - 50,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _burstHeartController,
                  builder: (context, _) {
                    final t = _burstHeartController.value;
                    final scale = t < 0.25
                        ? Tween<double>(begin: 0.2, end: 1.35).transform(Curves.easeOutBack.transform(t / 0.25))
                        : Tween<double>(begin: 1.35, end: 1.0).transform(Curves.easeIn.transform((t - 0.25) / 0.75));
                    final translateY = -45.0 * Curves.easeOutQuad.transform(t);
                    final opacity = (1.0 - Curves.easeIn.transform(t)).clamp(0.0, 1.0);

                    return Transform.translate(
                      offset: Offset(0, translateY),
                      child: Transform.scale(
                        scale: scale,
                        child: Opacity(
                          opacity: opacity,
                          child: SizedBox(
                            width: 100,
                            height: 100,
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.center,
                              children: [
                                // Radiating mini-hearts burst
                                for (int i = 0; i < 8; i++)
                                  Transform.translate(
                                    offset: Offset(
                                      math.cos(i * math.pi / 4) * 70 * Curves.easeOutCubic.transform(t),
                                      math.sin(i * math.pi / 4) * 70 * Curves.easeOutCubic.transform(t),
                                    ),
                                    child: Icon(
                                      Icons.favorite_rounded,
                                      size: 14,
                                      color: (i.isEven ? AppColors.brandPink : Colors.white)
                                          .withValues(alpha: (1.0 - t).clamp(0.0, 1.0)),
                                    ),
                                  ),
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.brandPink.withValues(alpha: 0.55),
                                        blurRadius: 32,
                                        spreadRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.favorite_rounded,
                                    size: 92,
                                    color: AppColors.brandPink,
                                    shadows: [Shadow(color: Colors.black38, blurRadius: 12)],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // ── Advanced Floating Rotated Activity Cards & Bubbles ──
          // (portrait only: in landscape they would cover the top bar)
          // In focus mode they stay on as ambient, self-fading comments & likes.
          if (widget.isActive && !_landscape)
            OneovaLiveActivityOverlay(
              contentId: widget.content.id,
              immersive: widget.isFullScreen,
              onCommentTap: () => _showComments(context),
              onLikesTap: () => ReelLikesBottomSheet.show(context, widget.content),
            ),

          // ── Engagement Rail Overlay (right: 8) ────────────
          if (widget.isActive)
            Positioned(
              right: 8,
              top: _landscape ? MediaQuery.paddingOf(context).top + 64 : null,
              bottom: _landscape ? 12 + MediaQuery.paddingOf(context).bottom : 66.0 + MediaQuery.paddingOf(context).bottom,
              child: AnimatedSlide(
                offset: widget.isFullScreen ? const Offset(1.2, 0) : Offset.zero,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                child: AnimatedOpacity(
                  opacity: widget.isFullScreen ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 220),
                  child: IgnorePointer(
                    ignoring: widget.isFullScreen,
                    // Landscape: shrink the rail to the available height.
                    // Landscape: the rail scrolls within the space left
                    // below the top row.
                    child: _landscape
                        ? SingleChildScrollView(child: _buildEngagementOverlay())
                        : _buildEngagementOverlay(),
                  ),
                ),
              ),
            ),
          // ── Content Info Overlay (left: 0, right: 70) ──────
          if (widget.isActive)
            Positioned(
              left: 0,
              right: _landscape ? null : 70,
              width: _landscape ? (MediaQuery.sizeOf(context).width * 0.45).clamp(280.0, 520.0) : null,
              bottom: _landscape ? 12 + MediaQuery.paddingOf(context).bottom : 66.0 + MediaQuery.paddingOf(context).bottom,
              child: AnimatedSlide(
                offset: widget.isFullScreen ? const Offset(0, 0.4) : Offset.zero,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                child: AnimatedOpacity(
                  opacity: widget.isFullScreen ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 220),
                  child: IgnorePointer(
                    ignoring: widget.isFullScreen,
                    child: _landscape
                        ? ConstrainedBox(
                            constraints: BoxConstraints(
                              // Feed height (above the bottom nav) minus the
                              // landscape top row.
                              maxHeight: (_itemHeight - MediaQuery.paddingOf(context).top - 80)
                                  .clamp(120.0, double.infinity),
                            ),
                            child: SingleChildScrollView(
                              reverse: true,
                              child: _buildContentInfoOverlay(controller?.player.state.playing ?? true),
                            ),
                          )
                        : _buildContentInfoOverlay(controller?.player.state.playing ?? true),
                  ),
                ),
              ),
            ),


          // ── Author Side Panel (left 25% slide-in) ─────────
          if (_showAuthorPanel)
            AuthorSidePanel(
              content: widget.content,
              onClose: () => setState(() => _showAuthorPanel = false),
            ),
        ],
      );
      }),
    );

  }

  Widget _buildThumbnail() {
    if (widget.content.mediaMetadata.thumbnailUrl != null) {
      return Image.network(
        widget.content.mediaMetadata.thumbnailUrl!,
        fit: _landscape ? BoxFit.contain : BoxFit.cover,
      );
    }
    return Container(color: _p.placeholder);
  }


  Widget _buildEngagementOverlay() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final interactionRepo = ref.read(interactionRepositoryProvider);
    final authorAsync = ref.watch(_reelAuthorProvider(widget.content.authorId));
    final author = authorAsync.value;
    final String avatarUrl = author?.profilePhotoUrl ?? '';
    final String initial = (author?.username?.isNotEmpty == true) 
        ? author!.username![0].toUpperCase() 
        : (widget.content.authorId.isNotEmpty ? widget.content.authorId[0].toUpperCase() : 'M');

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('content').doc(widget.content.id).snapshots(),
      builder: (context, contentSnap) {
        final content = contentSnap.hasData && contentSnap.data!.exists
            ? Content.fromFirestore(contentSnap.data!)
            : widget.content;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _PressScale(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PublicProfileScreen(targetUserId: widget.content.authorId),
                        ),
                      );
                    },
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 6),
                        ],
                      ),
                      child: ClipOval(
                        child: avatarUrl.isNotEmpty
                          ? Image.network(
                              avatarUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _avatarFallback(initial),
                            )
                          : _avatarFallback(initial),
                      ),
                    ),
                  ),
                  if (uid.isNotEmpty && uid != content.authorId)
                    Positioned(
                      bottom: -10,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Consumer(
                          builder: (context, ref, _) {
                            final state = ref
                                    .watch(followStateProvider((me: uid, them: content.authorId)))
                                    .value ??
                                FollowState.none;
                            final canFollow = state == FollowState.none || state == FollowState.followsYou;
                            // "+" while not followed; a brief check after a fresh
                            // follow, then the badge hides (live across devices).
                            final showCheck = _followJustConfirmed;
                            final showBadge = canFollow || showCheck;
                            return AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              transitionBuilder: (child, anim) => ScaleTransition(
                                scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                                child: FadeTransition(opacity: anim, child: child),
                              ),
                              child: !showBadge
                                  ? const SizedBox(key: ValueKey('none'), width: 18, height: 18)
                                  : GestureDetector(
                                      key: ValueKey(showCheck ? 'check' : 'plus'),
                                      behavior: HitTestBehavior.opaque,
                                      onTap: showCheck
                                          ? null
                                          : () {
                                              AuthInteractionGate.requireAuth(
                                                context,
                                                actionTitle: 'follow creators',
                                                onAuthenticated: () async {
                                                  HapticFeedback.mediumImpact();
                                                  setState(() => _followJustConfirmed = true);
                                                  try {
                                                    await ref.read(relationshipRepositoryProvider).followUser(uid, content.authorId);
                                                    ref.read(recommendationServiceProvider).trackEvent(
                                                      uid,
                                                      widget.content.id,
                                                      ContentInteractionType.follow,
                                                      {'source': 'rail_badge'},
                                                    );
                                                  } catch (e) {
                                                    if (mounted) setState(() => _followJustConfirmed = false);
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(content: Text('Could not follow creator')),
                                                      );
                                                    }
                                                    return;
                                                  }
                                                  Future.delayed(const Duration(milliseconds: 1200), () {
                                                    if (mounted) setState(() => _followJustConfirmed = false);
                                                  });
                                                },
                                              );
                                            },
                                      child: Padding(
                                        // Larger tap target than the 18px dot.
                                        padding: const EdgeInsets.all(4),
                                        child: Container(
                                          width: 18,
                                          height: 18,
                                          decoration: BoxDecoration(
                                            color: AppColors.brandBlue,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 1.2),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.brandBlue.withValues(alpha: 0.6),
                                                blurRadius: 6,
                                              ),
                                            ],
                                          ),
                                          child: Icon(
                                            showCheck ? Icons.check_rounded : Icons.add_rounded,
                                            color: Colors.white,
                                            size: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              StreamBuilder<bool>(
                stream: interactionRepo.watchIsLiked(uid, widget.content.id),
                builder: (context, snap) {
                  final serverLiked = snap.data ?? false;
                  _serverLiked = serverLiked;
                  _serverLikeCount = content.likeCount;
                  // Firestore caught up with the tap: stop overriding it.
                  if (!_likeBusy && _pendingLiked == serverLiked) _pendingLiked = null;
                  final isLiked = _pendingLiked ?? serverLiked;
                  final delta = (_pendingLiked == null ||
                          _pendingLiked == serverLiked ||
                          content.likeCount != _likeBaseCount)
                      ? 0
                      : (_pendingLiked! ? 1 : -1);
                  final displayLikeCount = math.max(0, content.likeCount + delta);

                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      AnimatedBuilder(
                        animation: _likePulseController,
                        builder: (context, child) {
                          final t = _likePulseController.value;
                          final scale = 1.0 + math.sin(t * math.pi) * 0.3;
                          return Transform.scale(scale: scale, child: child);
                        },
                        child: _buildRailAction(
                          isLiked ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                          displayLikeCount,
                          color: isLiked ? AppColors.brandPink : _p.fg,
                          accentColor: isLiked ? AppColors.brandPink : null,
                          glowColor: isLiked ? AppColors.brandPink : null,
                          onTap: () {
                            AuthInteractionGate.requireAuth(
                              context,
                              actionTitle: 'like videos',
                              onAuthenticated: () {
                                final next = !(_pendingLiked ?? _serverLiked);
                                _likePulseController.forward(from: 0.0);
                                if (next) _floatingHeartsKey.currentState?.burst();
                                _setLiked(uid, next);
                              },
                            );
                          },
                        ),
                      ),
                      // Hearts rise from the like button when liking.
                      Positioned(
                        bottom: 40,
                        child: FloatingHearts(key: _floatingHeartsKey),
                      ),
                    ],
                  );
                },
              ),
              _buildRailAction(
                Icons.chat_bubble_outline_rounded,
                content.commentCount,
                accentColor: AppColors.brandBlue,
                onTap: () {
                  AuthInteractionGate.requireAuth(
                    context,
                    actionTitle: 'comment on videos',
                    onAuthenticated: () => _showComments(context),
                  );
                },
              ),
              StreamBuilder<bool>(
                stream: interactionRepo.watchIsSaved(uid, widget.content.id),
                builder: (context, snap) {
                  final actualIsSaved = snap.data ?? false;
                  final isSaved = _optimisticIsSaved ?? actualIsSaved;
                  final displaySaveCount = content.saveCount + _optimisticSaveDelta;

                  return _buildRailAction(
                    isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                    displaySaveCount,
                    color: isSaved ? AppColors.brandBlue : _p.fg,
                    accentColor: AppColors.brandBlue,
                    glowColor: isSaved ? AppColors.brandBlue : null,
                    onTap: () {
                      AuthInteractionGate.requireAuth(
                        context,
                        actionTitle: 'save videos to your collection',
                        onAuthenticated: () async {
                          final prevSaved = isSaved;
                          setState(() {
                            _optimisticIsSaved = !prevSaved;
                            _optimisticSaveDelta += prevSaved ? -1 : 1;
                          });

                          try {
                            if (prevSaved) {
                              await interactionRepo.unsaveContent(uid, widget.content.id);
                            } else {
                              await interactionRepo.saveContent(uid, widget.content.id);
                              ref.read(recommendationServiceProvider).trackEvent(uid, widget.content.id, ContentInteractionType.save, {});
                            }
                          } catch (e) {
                            if (mounted) {
                              setState(() {
                                _optimisticIsSaved = prevSaved;
                                _optimisticSaveDelta += prevSaved ? 1 : -1;
                              });
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update save')));
                              }
                            }
                          } finally {
                            if (mounted) {
                              Future.delayed(const Duration(milliseconds: 500), () {
                                if (mounted) {
                                  setState(() {
                                    _optimisticIsSaved = null;
                                    _optimisticSaveDelta = 0;
                                  });
                                }
                              });
                            }
                          }
                        },
                      );
                    },
                  );
                },
              ),
              _buildRailAction(
                Icons.share_rounded,
                content.repostCount + _optimisticShareDelta,
                accentColor: AppColors.brandBlue,
                onTap: () {
                  AuthInteractionGate.requireAuth(
                    context,
                    actionTitle: 'share videos and generate links',
                    onAuthenticated: () async {
                      setState(() {
                        _optimisticShareDelta += 1;
                      });
                      try {
                        await interactionRepo.repostContent(uid, widget.content.id);
                        ref.read(recommendationServiceProvider).trackEvent(uid, widget.content.id, ContentInteractionType.share, {});
                        final shareUrl = OneovaShareEngine().generateWebShareUrl(widget.content.id);
                        await Clipboard.setData(ClipboardData(text: shareUrl));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Universal link copied: $shareUrl'),
                              backgroundColor: AppColors.brandBlue,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          setState(() {
                            _optimisticShareDelta -= 1;
                          });
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to share content')));
                          }
                        }
                      } finally {
                        if (mounted) {
                          Future.delayed(const Duration(milliseconds: 500), () {
                            if (mounted) {
                              setState(() {
                                _optimisticShareDelta = 0;
                              });
                            }
                          });
                        }
                      }
                    },
                  );
                },
              ),
              _PressScale(
                onTap: () {
                  HapticFeedback.lightImpact();
                  AuthInteractionGate.requireAuth(
                    context,
                    actionTitle: 'remix and create studio content',
                    onAuthenticated: () => CreationTypeModal.show(context),
                  );
                },
                child: Column(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [AppColors.brandBlue, AppColors.brandPink],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.0),
                        boxShadow: [
                          BoxShadow(color: AppColors.brandPink.withValues(alpha: 0.45), blurRadius: 10),
                        ],
                      ),
                      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 17),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'REMIX',
                      style: GoogleFonts.inter(
                        color: _p.fg,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        shadows: _p.textShadow,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _PressScale(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _openSound();
                },
                child: AnimatedBuilder(
                  animation: _vinylController,
                  builder: (_, child) {
                    return Transform.rotate(
                      angle: _vinylController.value * 2 * math.pi,
                      child: child,
                    );
                  },
                  child: Container(
                    width: 30,
                    height: 30,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const SweepGradient(
                        colors: [AppColors.darkSurface, AppColors.darkSurfaceHighlight, AppColors.darkSurface],
                      ),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.0),
                    ),
                    child: ClipOval(
                      child: (_audioTrack != null &&
                              _audioTrack!.coverImageUrl.startsWith('http') &&
                              !_audioTrack!.coverImageUrl.contains('example.com'))
                          ? Image.network(
                              _audioTrack!.coverImageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _discFallback(),
                            )
                          : _discFallback(),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );

  }

  Widget _avatarFallback(String initial) {
    return Container(
      color: _p.placeholder,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: GoogleFonts.inter(color: _p.fg, fontSize: 15, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _discFallback() {
    return Container(
      color: AppColors.brandBlue,
      alignment: Alignment.center,
      child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 11),
    );
  }

  /// Audio disc / sound ticker: open the track page, or the creator's profile
  /// for original sounds that have no catalogued track.
  void _openSound() {
    final musicId = _audioTrack?.id ?? widget.content.mediaMetadata.musicId;
    if (musicId != null && musicId.isNotEmpty) {
      context.push('/sound/$musicId');
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PublicProfileScreen(targetUserId: widget.content.authorId)),
      );
    }
  }

  Widget _buildRailAction(
    IconData icon,
    int count, {
    Color? color,
    Color? accentColor,
    Color? glowColor,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: _PressScale(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap?.call();
        },
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: glowColor != null ? glowColor.withValues(alpha: 0.22) : _p.glass,
                shape: BoxShape.circle,
                border: Border.all(
                  color: glowColor != null ? glowColor.withValues(alpha: 0.7) : _p.glassBorder,
                  width: 1.0,
                ),
                boxShadow: glowColor != null
                    ? [BoxShadow(color: glowColor.withValues(alpha: 0.45), blurRadius: 10)]
                    : null,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                  child: child,
                ),
                child: Icon(icon, key: ValueKey(icon), color: color ?? _p.fg, size: 19),
              ),
            ),
            const SizedBox(height: 3),
            RollingCount(
              value: math.max(0, count),
              style: GoogleFonts.inter(
                color: _p.fg,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
                shadows: _p.textShadow,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentInfoOverlay([bool isPlaying = true]) {
    final authorAsync = ref.watch(_reelAuthorProvider(widget.content.authorId));
    final author = authorAsync.value;
    final String username = author?.username?.isNotEmpty == true
        ? author!.username!
        : (author?.fullName.isNotEmpty == true
            ? author!.fullName
            : (widget.content.authorId.isNotEmpty ? widget.content.authorId : 'oneova_creator'));
    final String initial = username.isNotEmpty ? username[0].toUpperCase() : 'O';
    final String avatarUrl = author?.profilePhotoUrl ?? '';

    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final p = _p;
    final textShadow = p.textShadow;

    void openProfile() {
      HapticFeedback.selectionClick();
      Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(targetUserId: widget.content.authorId)));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Author pill ─────────────────────────────────────
          Row(
            children: [
              Flexible(
                child: _PressScale(
                  onTap: openProfile,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
                    decoration: BoxDecoration(
                      color: p.glass,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(color: p.glassBorder, width: 1.0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(color: AppColors.brandBlue, shape: BoxShape.circle),
                          child: ClipOval(
                            child: avatarUrl.isNotEmpty
                                ? Image.network(avatarUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => _pillInitial(initial))
                                : _pillInitial(initial),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '@$username',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(color: p.fg, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                          ),
                        ),
                        if (author?.isVerified ?? false) ...[
                          const SizedBox(width: 3),
                          Icon(Icons.verified_rounded, color: p.dark ? Colors.white : AppColors.brandBlue, size: 13),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (currentUid.isNotEmpty && currentUid != widget.content.authorId) ...[
                const SizedBox(width: 6),
                _PressScale(
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    try {
                      final chatId = await ref.read(messagingRepositoryProvider).getOrCreateDirectChat(currentUid, widget.content.authorId);
                      if (!mounted) return;
                      context.push('/hub/messages/$chatId');
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error opening chat: $e')));
                    }
                  },
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.send_rounded, color: Colors.white, size: 11),
                        const SizedBox(width: 4),
                        Text(
                          'Message',
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),

          // ── Caption (tap to expand) ─────────────────────────
          if (widget.content.description.isNotEmpty) ...[
            const SizedBox(height: 7),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _captionExpanded = !_captionExpanded),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topLeft,
                child: Text(
                  widget.content.description,
                  style: GoogleFonts.inter(
                    color: p.fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                    shadows: textShadow,
                  ),
                  maxLines: _captionExpanded ? 8 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],

          // ── Hashtags → hashtag explore ──────────────────────
          if (widget.content.hashtags.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 2,
              children: widget.content.hashtags.take(4).map((tag) {
                final clean = tag.startsWith('#') ? tag.substring(1) : tag;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push('/social/explore/hashtag/${Uri.encodeComponent(clean)}');
                  },
                  child: Text(
                    '#$clean',
                    style: GoogleFonts.inter(
                      color: p.dark ? Colors.white : AppColors.brandBlue,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      shadows: textShadow,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          // ── Shop chip (real Biz products only) ──────────────
          _ShopChip(authorId: widget.content.authorId, username: username),

          const SizedBox(height: 8),
          // ── Sound ───────────────────────────────────────────
          ReelLiveAudioWavesWidget(
            isPlaying: isPlaying,
            trackTitle: _audioTrack?.title ?? 'Original sound · @$username',
            artistName: _audioTrack?.ownerName,
            onTap: _openSound,
          ),
          const SizedBox(height: 8),

          // ── Add comment bar (tap mic = live transcription, hold = voice comment) ──
          ReelCommentBar(
            contentId: widget.content.id,
            contentAuthorId: widget.content.authorId,
            onOpenComments: () => AuthInteractionGate.requireAuth(
              context,
              actionTitle: 'comment on videos',
              onAuthenticated: () => _showComments(context, autoFocus: true),
            ),
            onOpenAssistant: () {
              HapticFeedback.lightImpact();
              OneOvaAssistantOverlay.show(
                context,
                userId: currentUid,
                contentId: widget.content.id,
                initialPrompt: 'What do you think of this reel by @$username: "${widget.content.description}"?',
              );
            },
            reactions: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildQuickReactionEmoji('😍', currentUid),
                const SizedBox(width: 6),
                _buildQuickReactionEmoji('🔥', currentUid),
              ],
            ),
          ),
          const SizedBox(height: 8), // Snug above bottom nav
        ],
      ),
    );
  }

  Widget _pillInitial(String initial) {
    return Center(
      child: Text(initial, style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }

  Widget _buildQuickReactionEmoji(String emoji, String currentUid) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AuthInteractionGate.requireAuth(
          context,
          actionTitle: 'react to reels',
          onAuthenticated: () async {
            HapticFeedback.lightImpact();
            try {
              final newComment = Comment(
                id: '',
                postId: widget.content.id,
                authorId: currentUid,
                content: emoji,
                createdAt: DateTime.now(),
              );
              await ref.read(commentServiceProvider).addComment(
                newComment,
                isCreator: widget.content.authorId == currentUid,
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Reacted $emoji to reel'),
                  duration: const Duration(milliseconds: 1200),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not post reaction: $e')),
              );
            }
          },
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: Text(emoji, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
  void _showFeedControls(BuildContext context) {
    HapticFeedback.mediumImpact();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final rec = ref.read(recommendationServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final player = ref.read(videoPlaybackManagerProvider).getController(widget.content.id)?.player;
    final isMuted = (player?.state.volume ?? 100) == 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) {
        Widget tile(IconData icon, String label, VoidCallback onTap, {Color? iconColor}) {
          return ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(icon, color: iconColor ?? sheetContext.textPrimary, size: 20),
            title: Text(
              label,
              style: GoogleFonts.inter(color: sheetContext.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.pop(sheetContext);
              onTap();
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: sheetContext.border,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              const SizedBox(height: 6),
              tile(Icons.visibility_off_outlined, 'Not interested', () {
                rec.markNotInterested(uid, widget.content.id);
                messenger.showSnackBar(const SnackBar(content: Text("We'll show fewer videos like this.")));
              }),
              tile(Icons.person_off_outlined, 'Hide this creator', () {
                rec.hideCreator(uid, widget.content.authorId);
                messenger.showSnackBar(const SnackBar(content: Text("You won't see videos from this creator.")));
              }),
              if (widget.content.hashtags.isNotEmpty)
                tile(Icons.tag_rounded, 'Hide #${widget.content.hashtags.first}', () {
                  rec.hideTopic(uid, widget.content.hashtags.first);
                  messenger.showSnackBar(SnackBar(content: Text("You won't see videos about #${widget.content.hashtags.first}.")));
                }),
              tile(Icons.info_outline_rounded, 'Why am I seeing this?', () async {
                final explanation = await rec.getWhyAmISeeingThis(widget.content.id, userId: uid.isEmpty ? null : uid);
                if (!context.mounted) return;
                showDialog(
                  context: context,
                  builder: (c) => AlertDialog(
                    backgroundColor: c.surface,
                    title: Text('About this video', style: TextStyle(color: c.textPrimary)),
                    content: Text('${explanation['reason']}', style: TextStyle(color: c.textSecondary)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('Close', style: TextStyle(color: AppColors.brandBlue)),
                      ),
                    ],
                  ),
                );
              }),
              tile(isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, isMuted ? 'Unmute' : 'Mute sound', () {
                if (player == null) return;
                final newVolume = isMuted ? 100.0 : 0.0;
                player.setVolume(newVolume);
                rec.trackEvent(uid, widget.content.id, ContentInteractionType.soundInteraction, {'volume': newVolume});
              }),
              tile(Icons.play_circle_outline_rounded, 'Play / Pause', _togglePlay),
              tile(Icons.shield_outlined, 'Live presence & privacy', () => OneovaQuickPrivacySheet.show(context),
                  iconColor: AppColors.brandBlue),
              tile(Icons.flag_outlined, 'Report', () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    backgroundColor: c.surface,
                    title: Text('Report this video?', style: TextStyle(color: c.textPrimary)),
                    content: Text('Our team will review it against the community guidelines.',
                        style: TextStyle(color: c.textSecondary)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancel', style: TextStyle(color: c.textSecondary))),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Report', style: TextStyle(color: AppColors.brandPink))),
                    ],
                  ),
                );
                if (confirmed != true) return;
                rec.trackEvent(uid, widget.content.id, ContentInteractionType.report, {});
                messenger.showSnackBar(const SnackBar(content: Text('Report submitted.')));
              }, iconColor: AppColors.brandPink),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }
  void _showComments(BuildContext context, {bool autoFocus = false}) {
    CommentBottomSheet.show(context, widget.content, autoFocus: autoFocus);
  }
}

// ─────────────────────────────────────────────────────────────
// Providers (file-scoped)
// ─────────────────────────────────────────────────────────────

final _reelAuthorProvider =
    StreamProvider.family<AppUser?, String>((ref, uid) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((snap) => (snap.exists && snap.data() != null)
          ? AppUser.fromMap(snap.data()!, snap.id)
          : null);
});

final _reelRelationshipProvider =
    StreamProvider.family<Relationship?, String>((ref, targetUid) {
  final currentUid = FirebaseAuth.instance.currentUser?.uid;
  if (currentUid == null) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection('relationships')
      .doc('${currentUid}_$targetUid')
      .snapshots()
      .map((s) => s.exists ? Relationship.fromFirestore(s) : null);
});

// ─────────────────────────────────────────────────────────────
// _ReelContentInfo — premium overlay with live author data
// ─────────────────────────────────────────────────────────────

class _ReelContentInfo extends ConsumerStatefulWidget {
  final Content content;
  final String currentUid;
  final VoidCallback onAuthorTap;

  const _ReelContentInfo({
    required this.content,
    required this.currentUid,
    required this.onAuthorTap,
  });

  @override
  ConsumerState<_ReelContentInfo> createState() => _ReelContentInfoState();
}

class _ReelContentInfoState extends ConsumerState<_ReelContentInfo> {
  bool _captionExpanded = false;

  @override
  Widget build(BuildContext context) {
    final authorAsync = ref.watch(_reelAuthorProvider(widget.content.authorId));
    final relAsync = ref.watch(_reelRelationshipProvider(widget.content.authorId));

    final author = authorAsync.asData?.value;
    final rel = relAsync.asData?.value;
    final isFollowing = rel?.status == RelationshipStatus.accepted;
    final isPending = rel?.status == RelationshipStatus.pending;
    final isSelf = widget.currentUid == widget.content.authorId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Author row ────────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Tappable avatar → opens side panel
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onAuthorTap();
              },
              child: _ReelAvatar(author: author)
                  .animate()
                  .fadeIn(duration: 300.ms)
                  .scaleXY(begin: 0.8, duration: 280.ms, curve: Curves.easeOutBack),
            ),

            const SizedBox(width: 10),

            // Name + @username (tappable → side panel)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onAuthorTap();
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            author?.fullName.isNotEmpty == true
                                ? author!.fullName
                                : '@${widget.content.authorId}',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              shadows: const [
                                Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 1)),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (author?.isVerified == true) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified_rounded, color: Colors.lightBlue, size: 15)
                              .animate().fadeIn(delay: 200.ms),
                        ],
                      ],
                    ),
                    if (author?.username != null && author!.username!.isNotEmpty)
                      Text(
                        '@${author.username}',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 10),

            // ── Live Follow Button ────────────────────────────
            if (!isSelf && widget.currentUid.isNotEmpty && !isFollowing)
              _ReelFollowButton(
                targetUserId: widget.content.authorId,
                currentUserId: widget.currentUid,
                isFollowing: isFollowing,
                isPending: isPending,
              ).animate().fadeIn(delay: 150.ms, duration: 280.ms),

            if (!isSelf && widget.currentUid.isNotEmpty)
              GestureDetector(
                onTap: () async {
                  try {
                    final chatId = await ref.read(messagingRepositoryProvider).getOrCreateDirectChat(widget.currentUid, widget.content.authorId);
                    if (!context.mounted) return;
                    context.push('/hub/messages/$chatId');
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error opening chat: $e')));
                  }
                },
                child: Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: AppColors.brandBlue.withValues(alpha: 0.3), blurRadius: 6),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.send_rounded, color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Chat',
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 8),

        // ── Caption ───────────────────────────────────────────
        if (widget.content.description.isNotEmpty)
          GestureDetector(
            onTap: () => setState(() => _captionExpanded = !_captionExpanded),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: Text(
                widget.content.description,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 5)],
                ),
                maxLines: _captionExpanded ? null : 2,
                overflow: _captionExpanded ? null : TextOverflow.ellipsis,
              ),
            ),
          ),

        const SizedBox(height: 8),

        // ── Hashtag chips ─────────────────────────────────────
        if (widget.content.hashtags.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: widget.content.hashtags.take(4).map((tag) {
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push('/social/explore/hashtag/$tag');
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
                    ),
                    child: Text(
                      '#$tag',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

        const SizedBox(height: 8),

        // ── Audio ticker ──────────────────────────────────────
        if (widget.content.mediaMetadata.musicId != null)
          _ReelAudioTicker(
            musicId: widget.content.mediaMetadata.musicId!,
            authorId: widget.content.authorId,
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// _ReelAvatar
// ─────────────────────────────────────────────────────────────

class _ReelAvatar extends StatelessWidget {
  final AppUser? author;
  const _ReelAvatar({required this.author});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        gradient: const LinearGradient(
          colors: [AppColors.brandBlue, AppColors.brandPink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandBlue.withValues(alpha: 0.4),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipOval(
        child: author?.profilePhotoUrl != null
            ? Image.network(
                author!.profilePhotoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() {
    final initial = (author?.fullName.isNotEmpty == true)
        ? author!.fullName[0].toUpperCase()
        : '?';
    return Center(
      child: Text(
        initial,
        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// _ReelFollowButton — live wired to RelationshipRepository
// ─────────────────────────────────────────────────────────────

class _ReelFollowButton extends ConsumerStatefulWidget {
  final String targetUserId;
  final String currentUserId;
  final bool isFollowing;
  final bool isPending;

  const _ReelFollowButton({
    required this.targetUserId,
    required this.currentUserId,
    required this.isFollowing,
    required this.isPending,
  });

  @override
  ConsumerState<_ReelFollowButton> createState() => _ReelFollowButtonState();
}

class _ReelFollowButtonState extends ConsumerState<_ReelFollowButton>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
      lowerBound: 0.92,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_loading) return;
    HapticFeedback.mediumImpact();
    await _pulseCtrl.reverse();
    await _pulseCtrl.forward();

    setState(() => _loading = true);
    try {
      final repo = ref.read(relationshipRepositoryProvider);
      if (widget.isFollowing) {
        await repo.unfollowUser(widget.currentUserId, widget.targetUserId);
      } else {
        await repo.followUser(widget.currentUserId, widget.targetUserId);
      }
    } catch (_) {
      // Silently fail
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.isFollowing
        ? 'Following'
        : widget.isPending
            ? 'Requested'
            : 'Follow';
    final isActive = !widget.isFollowing && !widget.isPending;

    return ScaleTransition(
      scale: _pulseCtrl,
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.brandBlue
                : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? AppColors.brandBlue : Colors.white38,
              width: 1.5,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppColors.brandBlue.withValues(alpha: 0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: _loading
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: AnimatedLoadingIndicator(size: 24, color: Colors.white),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.isFollowing) ...[
                        const Icon(Icons.check_rounded, color: Colors.white, size: 12),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 0.2,
                          shadows: const [Shadow(color: Colors.black38, blurRadius: 3)],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// _ReelAudioTicker — spinning vinyl + scrolling track name
// ─────────────────────────────────────────────────────────────

class _ReelAudioTicker extends StatefulWidget {
  final String musicId;
  final String authorId;
  const _ReelAudioTicker({required this.musicId, required this.authorId});

  @override
  State<_ReelAudioTicker> createState() => _ReelAudioTickerState();
}

class _ReelAudioTickerState extends State<_ReelAudioTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotCtrl;

  @override
  void initState() {
    super.initState();
    _rotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _rotCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/social/sound/${widget.musicId}'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RotationTransition(
            turns: _rotCtrl,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white38, width: 1.5),
                color: const Color(0xFF1A1A1A),
              ),
              child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 13),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Track · ${widget.musicId}',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────
// Shared home overlay primitives
// ─────────────────────────────────────────────────────────────

/// Snappy press-down scale (0.9) used across the home overlay controls.
class _PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _PressScale({required this.child, this.onTap});

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Compact frosted-glass circular button for the top row (Search / Bell).
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _GlassIconButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = ReelPalette.of(context);
    return Semantics(
      button: true,
      label: tooltip,
      child: _PressScale(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: p.glass,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.glassBorder, width: 1.0),
                ),
                child: Icon(icon, color: p.fg, size: 19),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedPillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;
  const _FeedPillButton({required this.label, required this.icon, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final p = ReelPalette.of(context);
    final fg = filled ? Colors.white : p.fg;
    return _PressScale(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: filled ? AppColors.brandBlue : p.glass,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: filled ? AppColors.brandBlue : p.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg, size: 16),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.inter(color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// Live count of the creator's Biz products (Firestore `biz_products.ownerId`).
final _creatorProductCountProvider = StreamProvider.family<int, String>((ref, ownerId) {
  if (ownerId.isEmpty) return Stream.value(0);
  return FirebaseFirestore.instance
      .collection('biz_products')
      .where('ownerId', isEqualTo: ownerId)
      .limit(20)
      .snapshots()
      .map((s) => s.docs.length);
});

/// "Shop …" chip — only shown when the creator actually sells something.
class _ShopChip extends ConsumerWidget {
  final String authorId;
  final String username;
  const _ShopChip({required this.authorId, required this.username});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(_creatorProductCountProvider(authorId)).value ?? 0;
    if (count == 0) return const SizedBox.shrink();
    final p = ReelPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: _PressScale(
        onTap: () {
          HapticFeedback.lightImpact();
          context.push('/biz_feed');
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 3, 10, 3),
          decoration: BoxDecoration(
            color: p.glass,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.55), width: 1.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(color: AppColors.brandPink, shape: BoxShape.circle),
                child: const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 12),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Shop @$username · ${count >= 20 ? '20+' : count} item${count == 1 ? '' : 's'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(color: p.fg, fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, color: p.fgSoft, size: 14),
            ],
          ),
        ),
      ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.2, end: 0),
    );
  }
}

/// Top-row bell. Shakes when the unread count goes up so new alerts are
/// noticeable without leaving the feed; the counter follows the user's
/// "Unread badges" setting.
class _RingingBell extends ConsumerStatefulWidget {
  const _RingingBell();

  @override
  ConsumerState<_RingingBell> createState() => _RingingBellState();
}

class _RingingBellState extends ConsumerState<_RingingBell> with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<int>>(unreadNotificationCountProvider, (prev, next) {
      final before = prev?.value;
      final now = next.value ?? 0;
      if (before != null && now > before) _shake.forward(from: 0);
    });
    final unreadCount = ref.watch(unreadNotificationCountProvider).value ?? 0;
    final showBadges = ref.watch(notificationPreferencesProvider).value?.showBadges ?? true;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            final t = _shake.value;
            final angle = math.sin(t * math.pi * 8) * 0.35 * (1 - t);
            return Transform.rotate(angle: angle, alignment: Alignment.topCenter, child: child);
          },
          child: _GlassIconButton(
            icon: unreadCount > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
            tooltip: 'Notifications',
            onTap: () => context.push('/notifications'),
          ),
        ),
        if (showBadges && unreadCount > 0)
          Positioned(
            top: -3,
            right: -5,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: AppColors.brandPink,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: ReelPalette.of(context).bg, width: 1.0),
                ),
                child: Center(
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, height: 1),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
