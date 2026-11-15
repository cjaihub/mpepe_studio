import '../create/services/remix_launcher.dart';
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
import 'package:oneova/backend/notifications/providers/notification_service.dart';
import '../social_hub/feed/widgets/author_side_panel.dart';
import 'widgets/comment_bottom_sheet.dart';
import 'package:oneova/backend/social/models/comment.dart';
import 'package:oneova/backend/social/services/comment_service.dart';
import 'package:oneova/backend/social/services/content_deletion_service.dart';
import 'widgets/story_viewer_screen.dart';
import 'providers/oneova_focus_mode_provider.dart';
import 'providers/live_activity_provider.dart';
import 'widgets/oneova_quick_privacy_sheet.dart';
import 'widgets/oneova_live_activity_overlay.dart';
import 'widgets/reel_likes_bottom_sheet.dart';
import '../backend/live/services/live_service.dart';
import '../backend/live/models/live_models.dart';
import '../backend/notifications/services/follower_alert_service.dart';
import 'widgets/about_reel_card.dart';
import '../social_hub/coins/coin_screens.dart' show UserGiftSheet;
import 'widgets/feed_pulse_card.dart';
import 'widgets/live_feed_card.dart';
import 'widgets/reel_palette.dart';
import 'widgets/rolling_count.dart';
import 'widgets/reel_comment_bar.dart';
import 'widgets/reel_destination_chip.dart';
import 'services/reel_prefetcher.dart';
import 'widgets/pending_post_pill.dart';
import '../services/pending_post_queue.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'widgets/circle_gesture_detector.dart';
import '../providers/settings_provider.dart';
import 'services/oneova_transcription_service.dart';
import 'widgets/oneova_caption_overlay.dart';
import 'widgets/reel_translated_caption.dart';
import 'widgets/oneova_transcript_sheet.dart';

import 'package:oneova/backend/social/models/audio_track.dart';
import 'package:oneova/backend/social/repositories/audio_track_repository.dart';
import 'package:oneova/backend/recommendation/algorithm/oneova_algorithm_models.dart';
import 'package:oneova/backend/recommendation/algorithm/online_feature_store.dart';
import '../auth/widgets/auth_interaction_gate.dart';
import '../social_hub/feed/widgets/share_sheet.dart';
import '../widgets/oneova_assistant_overlay.dart';
import '../backend/money/money_service.dart' show WatchTimeRecorder;
import 'dart:async';
import 'dart:ui';

class ShortVideoFeedScreen extends ConsumerStatefulWidget {
  final FeedMode initialMode;
  final String? initialVideoId;
  final bool openCommentsOnLoad;
  final String? highlightCommentId;
  final bool highlightReel;

  const ShortVideoFeedScreen({
    super.key,
    this.initialMode = FeedMode.forYou,
    this.initialVideoId,
    this.openCommentsOnLoad = false,
    this.highlightCommentId,
    this.highlightReel = false,
  });

  @override
  ConsumerState<ShortVideoFeedScreen> createState() => _ShortVideoFeedScreenState();
}

class _ShortVideoFeedScreenState extends ConsumerState<ShortVideoFeedScreen>
    with RouteAware, WidgetsBindingObserver {
  late PageController _pageController;
  int _currentIndex = 0;
  DateTime _currentVideoStartTime = DateTime.now();
  String? _highlightedContentId;
  Timer? _highlightClearTimer;
  String? _lastHandledDeepLinkSignature;
  
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
  bool _isRouteCurrent = true;
  bool _isAppResumed = true;
  bool _lastTickerEnabled = true;
  VideoPlaybackManager? _playbackManager;
  OnlineFeatureStore? _featureStore;

  void _safeAnimateToNextPage() {
    if (!mounted) return;
    try {
      if (_pageController.hasClients && _pageController.positions.length == 1) {
        final pos = _pageController.positions.first;
        if (pos.haveDimensions && pos is PageMetrics) {
          final pageMetrics = pos as PageMetrics;
          final current = pageMetrics.page?.round() ?? _currentPage;
          final target = current + 1;
          if (target < _pages.length) {
            _pageController.animateToPage(
              target,
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeInOutCubic,
            ).catchError((_) {});
          }
        }
      }
    } catch (_) {}
  }

  void _safeJumpToPage(int page) {
    if (!mounted) return;
    try {
      if (_pageController.hasClients && _pageController.positions.length == 1) {
        final pos = _pageController.positions.first;
        if (pos.haveDimensions) {
          _pageController.jumpToPage(page);
        }
      }
    } catch (_) {}
  }

  // Focus mode: enters by itself once a reel has played for 3s, then
  // stays until the user presses Back or draws a circle (which opens Ova).
  static const Duration _autoFocusAfter = Duration(seconds: 3);
  bool _autoFocusArmed = false;
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
          _safeAnimateToNextPage();
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
    WidgetsBinding.instance.addObserver(this);
    debugPrint('[ShortVideoFeedScreen] initState called');
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _currentMode = widget.initialMode;
    _pageController = PageController(initialPage: 0);
    final playback = ref.read(settingsProvider).value?['playback'];
    if (playback is Map) {
      _isAutoScrollEnabled = playback['autoScroll'] as bool? ?? _isAutoScrollEnabled;
      _isLoopModeEnabled = playback['loopVideos'] as bool? ?? _isLoopModeEnabled;
    }
    _loadFeed();
    // Posts that didn't finish uploading last time pick up where they left off.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(pendingPostQueueProvider.notifier).resumeAll();
    });
  }

  @override
  void didUpdateWidget(ShortVideoFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sig = '${widget.initialVideoId}|${widget.openCommentsOnLoad}|${widget.highlightCommentId}|${widget.highlightReel}';
    final oldSig = '${oldWidget.initialVideoId}|${oldWidget.openCommentsOnLoad}|${oldWidget.highlightCommentId}|${oldWidget.highlightReel}';
    if (sig != oldSig && widget.initialVideoId != null && widget.initialVideoId!.isNotEmpty) {
      _focusDeepLinkedVideo(
        widget.initialVideoId!,
        openComments: widget.openCommentsOnLoad,
        commentId: widget.highlightCommentId,
        highlight: widget.highlightReel || widget.openCommentsOnLoad,
      );
    }
  }

  Future<void> _focusDeepLinkedVideo(
    String videoId, {
    required bool openComments,
    String? commentId,
    required bool highlight,
  }) async {
    final sig = '$videoId|$openComments|$commentId|$highlight';
    if (_lastHandledDeepLinkSignature == sig) return;
    _lastHandledDeepLinkSignature = sig;

    Content? target;
    int existingPageIdx = _pages.indexWhere((p) => p is Content && p.id == videoId);
    if (existingPageIdx >= 0) {
      target = _pages[existingPageIdx] as Content;
    } else {
      try {
        final doc = await FirebaseFirestore.instance.collection('content').doc(videoId).get();
        if (doc.exists) {
          target = Content.fromFirestore(doc);
        }
      } catch (e) {
        debugPrint('[ShortVideoFeedScreen] Error fetching deep-linked video $videoId: $e');
      }
      if (!mounted || target == null) return;
      final inserted = target;
      setState(() {
        _pages.removeWhere((p) => p is Content && p.id == inserted.id);
        _feed.removeWhere((c) => c.id == inserted.id);
        final insertPage = _pages.isEmpty ? 0 : _currentPage;
        final insertFeed = _pages.take(insertPage).whereType<Content>().length;
        _pages.insert(insertPage, inserted);
        _feed.insert(insertFeed, inserted);
        existingPageIdx = insertPage;
        _currentIndex = insertFeed;
      });
    }

    if (!mounted) return;
    if (existingPageIdx >= 0 && existingPageIdx != _currentPage) {
      _safeJumpToPage(existingPageIdx);
      _onPageChanged(existingPageIdx);
    } else {
      final feedIdx = _feed.indexWhere((c) => c.id == target?.id);
      if (feedIdx >= 0) _warmAround(feedIdx);
      if (target != null) ref.read(videoPlaybackManagerProvider).ensureCurrentPlaying(target.id);
    }

    if (highlight && target != null) {
      _triggerHighlightReel(target.id);
    }

    if (openComments && target != null) {
      final contentForSheet = target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        CommentBottomSheet.show(
          context,
          contentForSheet,
          autoFocus: commentId == null || commentId.isEmpty,
          initialCommentId: commentId,
        );
      });
    }
  }

  void _triggerHighlightReel(String contentId) {
    _highlightClearTimer?.cancel();
    setState(() => _highlightedContentId = contentId);
    HapticFeedback.mediumImpact();
    _highlightClearTimer = Timer(const Duration(milliseconds: 3600), () {
      if (mounted) {
        setState(() => _highlightedContentId = null);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playbackManager = ref.read(videoPlaybackManagerProvider);
    _featureStore = ref.read(onlineFeatureStoreProvider);
    final modalRoute = ModalRoute.of(context);
    if (modalRoute != null) {
      homeBranchRouteObserver.subscribe(this, modalRoute);
    }
  }

  @override
  void didPushNext() {
    // Another screen was pushed over this feed (e.g. StoryViewer, Profile).
    // Instantly auto-mute audio and pause playback.
    debugPrint('[ShortVideoFeedScreen] didPushNext: route covered, auto-muting reels');
    _isRouteCurrent = false;
    _playbackManager?.setScreenActive(false);
    super.didPushNext();
  }

  @override
  void didPopNext() {
    // Returned back to this feed after the top route was popped.
    debugPrint('[ShortVideoFeedScreen] didPopNext: returned to feed, restoring active reel');
    _isRouteCurrent = true;
    final mgr = _playbackManager;
    if (mounted && _lastTickerEnabled && _isAppResumed && mgr != null) {
      mgr.setScreenActive(true);
      final item = _currentPage < _pages.length ? _pages[_currentPage] : null;
      if (item is Content) {
        mgr.ensureCurrentPlaying(item.id);
      } else {
        mgr.pauseAllSlots(clearActive: true);
      }
    }
    super.didPopNext();
  }

  @override
  void didPop() {
    _isRouteCurrent = false;
    _playbackManager?.setScreenActive(false);
    super.didPop();
  }

  @override
  void deactivate() {
    _playbackManager?.setScreenActive(false);
    super.deactivate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final mgr = _playbackManager;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _isAppResumed = false;
      mgr?.setScreenActive(false);
    } else if (state == AppLifecycleState.resumed) {
      _isAppResumed = true;
      if (_isRouteCurrent && _lastTickerEnabled && mounted && mgr != null) {
        mgr.setScreenActive(true);
        final item = _currentPage < _pages.length ? _pages[_currentPage] : null;
        if (item is Content) {
          mgr.ensureCurrentPlaying(item.id);
        } else {
          mgr.pauseAllSlots(clearActive: true);
        }
      }
    }
  }

  /// Counts continuous playback of the current reel; at 3s enters focus mode
  /// (once). Skips while another tab/route is on top or a live card is shown.
  void _scheduleAutoFocus() {
    _autoFocusTimer?.cancel();
    _playedFor = Duration.zero;
    if (!_autoFocusArmed) return;
    const tick = Duration(milliseconds: 500);
    _autoFocusTimer = Timer.periodic(tick, (t) {
      if (!mounted || !context.mounted || !_autoFocusArmed) return t.cancel();
      if (!_isRouteCurrent || !_isAppResumed || !_lastTickerEnabled) return;
      try {
        if (ref.read(oneovaFocusModeProvider)) return t.cancel();
        final item = _currentPage < _pages.length ? _pages[_currentPage] : null;
        final playing = item is Content &&
            ((_playbackManager ?? ref.read<VideoPlaybackManager>(videoPlaybackManagerProvider))
                    .getController(item.id)
                    ?.player
                    .state
                    .playing ??
                false);
        _playedFor = playing ? _playedFor + tick : Duration.zero;
        if (_playedFor >= _autoFocusAfter) {
          t.cancel();
          ref.read(oneovaFocusModeProvider.notifier).set(true);
        }
      } catch (_) {
        t.cancel();
      }
    });
  }

  /// Focus mode keeps the top phone status bar hidden.
  void _onFocusChanged(bool focus) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (_reelFullScreen != focus && mounted) {
      setState(() => _reelFullScreen = focus);
    }
    if (focus) {
      _autoFocusArmed = false; // one time only
      _autoFocusTimer?.cancel();
    }
    final cur = _currentContent;
    if (cur != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(videoPlaybackManagerProvider).ensureCurrentPlaying(cur.id);
        }
      });
    }
  }

  void _toggleFullScreenMode([bool? targetValue]) {
    final next = targetValue ?? !(_reelFullScreen || ref.read(oneovaFocusModeProvider));
    final activeId = _currentContent?.id;
    final savedPage = _currentPage;
    setState(() => _reelFullScreen = next);
    ref.read(oneovaFocusModeProvider.notifier).set(next);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pageController.hasClients && _currentPage != savedPage) {
        _safeJumpToPage(savedPage);
      }
      if (activeId != null) {
        ref.read(videoPlaybackManagerProvider).ensureCurrentPlaying(activeId);
      }
    });
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

  /// Live `content` subscription behind the current tab. The first snapshot
  /// is ranked; later ones slot newly published reels/photos in right after
  /// the page being watched, so other users' posts arrive without a refresh.
  StreamSubscription<List<Content>>? _feedSub;
  int _feedGeneration = 0;
  bool _feedPrimed = false;
  bool _feedRanking = false;
  List<Content>? _pendingFeedSnapshot;

  // Paging past the live head of the feed: older pages are fetched once the
  // viewer is within [_pageAheadTrigger] reels of the end, so the prefetch
  // window (ReelPrefetcher.windowSize = 60) always has 50+ reels ahead to work on.
  static const int _pageSize = 40;
  static const int _pageAheadTrigger = 55;
  DateTime? _oldestLoaded;
  bool _loadingOlder = false;
  bool _noOlder = false;

  void _noteOldest(Iterable<Content> items) {
    for (final c in items) {
      final o = _oldestLoaded;
      if (o == null || c.createdAt.isBefore(o)) _oldestLoaded = c.createdAt;
    }
  }

  /// Keeps the rolling window warm around reel [index]: player pool,
  /// disk prefetch, decoded covers for upcoming reels, and the next page.
  void _warmAround(int index) {
    if (!mounted || !context.mounted || _feed.isEmpty) return;
    try {
      ref.read(videoPlaybackManagerProvider).initializeAndPreload(_feed, index);
      ref.read(reelPrefetcherProvider).update(_feed, index);
      final mq = MediaQuery.maybeOf(context);
      final rawPx = mq != null ? (mq.size.width * mq.devicePixelRatio) : 780.0;
      final rawWidth = rawPx.isFinite ? rawPx.round() : 780;
      final cacheWidth = rawWidth > 0 ? rawWidth : 780;
      for (var i = index + 1; i <= index + 4 && i < _feed.length; i++) {
        if (!mounted || !context.mounted) return;
        final c = _feed[i];
        final url = c.type == ContentType.photo ? c.mediaUrl : c.mediaMetadata.thumbnailUrl;
        if (url == null || url.isEmpty) continue;
        precacheImage(
          ResizeImage.resizeIfNeeded(
            cacheWidth,
            null,
            CachedNetworkImageProvider(url, cacheManager: ReelPrefetcher.thumbCache),
          ),
          context,
          onError: (_, _) {},
        );
      }
      if (_feed.length - index <= _pageAheadTrigger) _loadOlder();
    } catch (_) {}
  }

  Future<void> _loadOlder() async {
    final before = _oldestLoaded;
    if (_loadingOlder || _noOlder || before == null) return;
    _loadingOlder = true;
    final generation = _feedGeneration;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    try {
      final service = ref.read(recommendationServiceProvider);
      final page = await service.fetchOlderCandidates(uid, _currentMode, before: before, limit: _pageSize);
      if (!mounted || generation != _feedGeneration) return;
      if (page.isEmpty) {
        _noOlder = true;
        return;
      }
      _noteOldest(page);
      final present = _feed.map((c) => c.id).toSet();
      final unseen = page.where((c) => !present.contains(c.id)).toList();
      final ranked = unseen.isEmpty ? const <Content>[] : await service.rankCandidates(uid, _currentMode, unseen);
      if (!mounted || generation != _feedGeneration || ranked.isEmpty) return;
      setState(() {
        _feed.addAll(ranked);
        _pages.addAll(ranked);
      });
      ref.read(reelPrefetcherProvider).update(_feed, _currentIndex);

      // If the buffer is still below the 55 threshold, chain another continuation page
      if (_feed.length - _currentIndex < _pageAheadTrigger && !_noOlder) {
        _loadingOlder = false;
        await _loadOlder();
      }
    } catch (e) {
      debugPrint('[ShortVideoFeedScreen] older page failed: $e');
    } finally {
      _loadingOlder = false;
    }
  }

  void _loadFeed() {
    debugPrint('[ShortVideoFeedScreen] subscribing to live feed ($_currentMode)');
    final generation = ++_feedGeneration;
    _feedPrimed = false;
    _feedRanking = false;
    _pendingFeedSnapshot = null;
    _oldestLoaded = null;
    _noOlder = false;
    _loadingOlder = false;
    _feedSub?.cancel();

    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    if (uid != 'unknown') {
      ref.read(onlineFeatureStoreProvider).hydrateProfile(uid);
    }
    _feedSub = ref.read(recommendationServiceProvider).watchFeedCandidates(uid, _currentMode).listen(
      (items) => _onFeedSnapshot(generation, uid, items),
      onError: (Object e) {
        debugPrint('Error loading feed: $e');
        if (mounted && generation == _feedGeneration && !_feedPrimed) {
          setState(() => _isLoading = false);
        }
      },
    );
  }

  Future<void> _onFeedSnapshot(int generation, String uid, List<Content> items) async {
    if (generation != _feedGeneration) return;
    if (_feedRanking) {
      _pendingFeedSnapshot = items;
      return;
    }
    _feedRanking = true;
    try {
      if (!_feedPrimed) {
        await _primeFeed(generation, uid, items);
      } else {
        await _mergeNewContent(generation, uid, items);
      }
    } catch (e) {
      debugPrint('Error loading feed: $e');
      if (mounted && generation == _feedGeneration && !_feedPrimed) {
        setState(() => _isLoading = false);
      }
    } finally {
      _feedRanking = false;
    }
    final pending = _pendingFeedSnapshot;
    _pendingFeedSnapshot = null;
    if (pending != null && generation == _feedGeneration) {
      await _onFeedSnapshot(generation, uid, pending);
    }
  }

  Future<void> _primeFeed(int generation, String uid, List<Content> items) async {
    final perfMonitor = ref.read(performanceMonitorProvider);
    _noteOldest(items);
    final rawRecs = await perfMonitor.measureApiLatency(
      'feed.fetchRecommendations',
      () => ref.read(recommendationServiceProvider).rankCandidates(uid, _currentMode, items),
    );
    final recommendations = List<Content>.from(rawRecs);

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

    if (!mounted || generation != _feedGeneration) return;
    _feedPrimed = true;
    final seenIds = <String>{};
    final deduped = <Content>[
      for (final c in recommendations)
        if (seenIds.add(c.id)) c,
    ];
    setState(() {
      _feed = List<Content>.of(deduped);
      _pages = List<Object>.of(deduped);
      _currentPage = 0;
      _isLoading = false;
    });
    _mergeLiveStreams(ref.read(activeLiveStreamsProvider).value ?? const []);

    if (_feed.isNotEmpty) {
      _warmAround(0);
      _attachAutoScrollListener();
      _scheduleAutoFocus();
      if (widget.initialVideoId != null && widget.initialVideoId!.isNotEmpty) {
        final vid = widget.initialVideoId!;
        if (widget.highlightReel || widget.openCommentsOnLoad) {
          _triggerHighlightReel(vid);
        }
        if (widget.openCommentsOnLoad) {
          final target = _feed.firstWhere((c) => c.id == vid, orElse: () => _feed.first);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            CommentBottomSheet.show(
              context,
              target,
              autoFocus: widget.highlightCommentId == null || widget.highlightCommentId!.isEmpty,
              initialCommentId: widget.highlightCommentId,
            );
          });
        }
      }
    }
  }

  /// Slots items that weren't in the feed yet (fresh uploads) in right after
  /// the current page, newest first. Items already on screen keep their place;
  /// their likes/comments/visibility update through their own doc stream.
  Future<void> _mergeNewContent(int generation, String uid, List<Content> items) async {
    final present = _feed.map((c) => c.id).toSet();
    final unseen = items.where((c) => !present.contains(c.id)).toList();
    if (unseen.isEmpty) return;
    final rawFresh = await ref.read(recommendationServiceProvider).filterCandidates(uid, unseen);
    if (rawFresh.isEmpty || !mounted || generation != _feedGeneration) return;
    final fresh = List<Content>.from(rawFresh)..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final wasEmpty = _feed.isEmpty;
    setState(() {
      final pageAt = wasEmpty ? 0 : math.min(_currentPage + 1, _pages.length);
      // Keep _feed in the same order as the reels in _pages.
      final feedAt = _pages.take(pageAt).whereType<Content>().length;
      _pages.insertAll(pageAt, fresh);
      _feed.insertAll(feedAt, fresh);
    });

    if (wasEmpty) {
      _warmAround(0);
      _attachAutoScrollListener();
      _scheduleAutoFocus();
    }
  }

  @override
  void dispose() {
    homeBranchRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _feedSub?.cancel();
    _autoFocusTimer?.cancel();
    _highlightClearTimer?.cancel();
    _playerCompletionSub?.cancel();
    _playerCompletionSub = null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _featureStore?.flushProfile(uid);
    }
    _playbackManager?.disposeAll();
    _pageController.dispose();
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

  /// Reels shown this session (for the occasional feedback card).
  int _reelsSeen = 0;

  Future<void> _maybeQueuePulse(int page, Content item) async {
    _reelsSeen++;
    if (!await FeedPulsePolicy.shouldAsk(_reelsSeen) || !mounted) return;
    setState(() => _pages.insert(math.min(page + 1, _pages.length), FeedPulseSlot(item)));
  }

  void _onPageChanged(int page) {
    final previousWasVideo = _currentPage < _pages.length && _pages[_currentPage] is Content;
    _currentPage = page;
    final item = page < _pages.length ? _pages[page] : null;
    if (item is! Content) {
      // Live card: every reel goes inactive (and pauses) while it is on screen.
      _playerCompletionSub?.cancel();
      ref.read(videoPlaybackManagerProvider).pauseAllSlots(clearActive: true);
      _currentVideoStartTime = DateTime.now();
      setState(() {});
      return;
    }
    final index = _feed.indexOf(item);
    if (index < 0) return;
    _maybeQueuePulse(page, item);

    final recommendationService = ref.read(recommendationServiceProvider);
    final now = DateTime.now();
    final dwellMs = now.difference(_currentVideoStartTime).inMilliseconds;
    _currentVideoStartTime = now;
    
    if (previousWasVideo && _feed.isNotEmpty && _currentIndex < _feed.length) {
      final prevVideo = _feed[_currentIndex];
      final rawDurationMs = prevVideo.mediaMetadata.duration?.inMilliseconds ?? 0;
      final videoDurationMs = rawDurationMs > 0 ? rawDurationMs : 15000;
      final safeDwellMs = math.max(0, dwellMs);
      final rawRate = safeDwellMs / videoDurationMs;
      final completionRate = rawRate.isFinite ? rawRate.clamp(0.0, 5.0) : 0.0;
      final loopCount = rawRate.isFinite ? rawRate.floor() : 0;
      final isFastSkip = safeDwellMs < 1500;

      final telemetry = VideoWatchTelemetry(
        userId: FirebaseAuth.instance.currentUser?.uid ?? 'currentUser',
        contentId: prevVideo.id,
        authorId: prevVideo.authorId,
        hashtags: prevVideo.hashtags,
        audioTrackId: prevVideo.mediaMetadata.musicId,
        dwellTimeMs: safeDwellMs,
        videoDurationMs: videoDurationMs,
        completionRate: completionRate,
        loopCount: loopCount,
        isFastSkip: isFastSkip,
        timestamp: now,
      );
      recommendationService.recordWatchTelemetry(telemetry);
      // Real watch time for the creator's insights (only when the length is known and > 0).
      if (rawDurationMs > 0) {
        WatchTimeRecorder.instance.add(prevVideo.id, safeDwellMs, videoDurationMs);
      }
    }

    setState(() {
      _currentIndex = index;
    });

    _warmAround(index);
    _attachAutoScrollListener();
    _scheduleAutoFocus();
    if (_feed.isNotEmpty && index < _feed.length) {
      ref.read(videoPlaybackManagerProvider).setLooping(_feed[index].id, _isLoopModeEnabled);
      // Auto-transcribe active reel & pre-transcribe next reel in advance
      final transcription = ref.read(oneovaTranscriptionServiceProvider);
      transcription.preTranscribeInAdvance(_feed[index]);
      if (index + 1 < _feed.length) {
        transcription.preTranscribeInAdvance(_feed[index + 1]);
      }
    }
    
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'currentUser';
    if (index < _feed.length) {
      ref.read(interactionRepositoryProvider).recordView(uid, _feed[index].id);
      recommendationService.trackEvent(uid, _feed[index].id, ContentInteractionType.impression, {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (tickerEnabled != _lastTickerEnabled) {
      _lastTickerEnabled = tickerEnabled;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!tickerEnabled) {
          ref.read(videoPlaybackManagerProvider).setScreenActive(false);
        } else if (_isRouteCurrent && _isAppResumed) {
          ref.read(videoPlaybackManagerProvider).setScreenActive(true);
          final item = _currentPage < _pages.length ? _pages[_currentPage] : null;
          if (item is Content) {
            ref.read(videoPlaybackManagerProvider).ensureCurrentPlaying(item.id);
          } else {
            ref.read(videoPlaybackManagerProvider).pauseAllSlots(clearActive: true);
          }
        }
      });
    }

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
    // Portrait feed: each reel sits in a rounded screen frame between the
    // brand header and the comment row. Focus mode and landscape stay full-bleed.
    // Framed reel design (docs/design/reel-feed-framed/) — the user chose it
    // on 2026-11-14 ("Switch to framed") after trying full-bleed. Keep it on;
    // full-bleed remains only for focus mode and landscape.
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    // Full-screen / Focus reel: video fills the extended frame, header,
    // stories and bottom nav hide; reel actions + comment input stay visible.
    final fullScreenActive = _reelFullScreen || isFocusMode;
    final immersive = _framedDesignEnabled && fullScreenActive && portrait;
    final framed = _framedDesignEnabled && !fullScreenActive && portrait;
    _framedLayout = framed;
    // The framed design keeps the bottom nav on screen; full-screen hides it.
    final peek = ref.watch(reelsNavPeekProvider);
    if ((framed && !peek) || (immersive && peek)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(reelsNavPeekProvider.notifier).set(framed);
      });
    }
    final pad = MediaQuery.paddingOf(context);
    // The shell's bottom bar is usually already in the bottom padding; only
    // add it when it isn't, so the frame doesn't float above empty space.
    final navVisible = ref.watch(oneovaBottomNavVisibleProvider);
    final navH = navVisible && pad.bottom < 40 ? 56.0 : 0.0;
    final frameTop = pad.top + _framedHeaderHeight;
    final frameBottom = navH + pad.bottom + _framedCommentHeight;
    // Keeps the follow list warm for live-slot ranking.
    ref.watch(followedCreatorAlertsProvider);
    ref.listen<AsyncValue<List<LiveStream>>>(activeLiveStreamsProvider, (_, next) {
      final streams = next.value;
      if (streams != null) _mergeLiveStreams(streams);
    });

    return PopScope(
      // Back is the only way out of focus mode (taps and double-taps are not).
      canPop: !fullScreenActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && fullScreenActive) {
          HapticFeedback.lightImpact();
          _toggleFullScreenMode(false);
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
        enabled: fullScreenActive,
        onCircle: _summonAssistant,
        child: Stack(
        children: [
          Positioned.fill(
            key: const ValueKey('feed_framed_backdrop'),
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: framed ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 220),
                child: _FramedBackdrop(dark: _palette.dark),
              ),
            ),
          ),
          if (_pages.isEmpty)
            Builder(builder: (context) {
              // Nothing to watch: keep the bottom nav on screen.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !ref.read(reelsNavPeekProvider)) ref.read(reelsNavPeekProvider.notifier).set(true);
              });
              return _buildEmptyState();
            })
          else
            AnimatedPadding(
              key: const ValueKey('feed_animated_padding'),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              padding: framed
                  ? EdgeInsets.fromLTRB(0, frameTop, 0, frameBottom)
                  : (immersive
                      ? EdgeInsets.fromLTRB(0, math.max(pad.top, 2), 0, pad.bottom + _framedCommentHeight)
                      : EdgeInsets.zero),
              child: PageView.builder(
              key: const ValueKey('short_video_feed_pageview'),
              controller: _pageController,
              scrollDirection: Axis.vertical,
              // Builds the reel above and below too, so a swipe lands on a
              // page whose cover (and warm player) is already laid out.
              allowImplicitScrolling: true,
              onPageChanged: _onPageChanged,
              itemCount: _pages.length,
              itemBuilder: (context, index) => _buildPage(index, isFocusMode: fullScreenActive, framed: framed, immersive: immersive),
            ),
            ),

          // Legibility scrims behind the top row/stories and the caption block
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildScrim(
              height: MediaQuery.paddingOf(context).top + 150,
              top: true,
              visible: !fullScreenActive && !framed,
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildScrim(height: 300, top: false, visible: !fullScreenActive && !framed),
          ),

          // Framed design: brand header, in-frame chips.
          if (framed) ...[
            Positioned(left: 0, right: 0, top: pad.top, child: _buildFramedHeader()),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              left: 12,
              right: 12,
              top: frameTop + 10,
              child: _buildFrameChips(),
            ),
          ],

          // Full-screen reel with extended frame: top chips to control or exit back to standard frame.
          if (immersive)
            Positioned(
              top: math.max(pad.top, 8) + 8,
              left: 12,
              right: 12,
              child: _buildFrameChips(),
            ),

          // Comment input row: visible in both Framed AND Full-Screen (immersive) modes!
          if ((framed || immersive) && _currentContent != null)
            Positioned(
              left: 8,
              right: 8,
              bottom: (framed ? navH : 0) + pad.bottom + 4,
              child: _FramedCommentRow(
                key: ValueKey('fcr_${_currentContent!.id}'),
                content: _currentContent!,
              ),
            ),

          // Top ambient navigation & stories overlay (slides & fades out in focus mode)
          if (!framed && !immersive)
          SafeArea(
            child: AnimatedSlide(
              offset: fullScreenActive ? const Offset(0, -0.6) : Offset.zero,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubic,
              child: AnimatedOpacity(
                opacity: fullScreenActive ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 220),
                child: IgnorePointer(
                  ignoring: fullScreenActive,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: _buildTopOverlay(),
                  ),
                ),
              ),
            ),
          ),

          // Posting progress / one-tap retry, under the stories row.
          if (!fullScreenActive && !immersive)
            Positioned(
              top: framed ? frameTop + 48 : MediaQuery.paddingOf(context).top + 128,
              left: framed ? 22 : 12,
              child: const PendingPostPill(),
            ),

          // Subtle buffering line at bottom when active reel is loading
          Positioned(
            left: framed ? 30 : 0,
            right: framed ? 30 : 0,
            bottom: framed ? frameBottom + 5 : 0,
            child: ValueListenableBuilder<bool>(
              valueListenable: ref.read(videoPlaybackManagerProvider).activeReelBuffering,
              builder: (context, isBuffering, _) {
                if (!isBuffering) return const SizedBox.shrink();
                return const SizedBox(
                  height: 2.0,
                  child: LinearProgressIndicator(
                    minHeight: 2.0,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.brandBlue),
                  ),
                );
              },
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


  /// True while the portrait framed design is showing.
  bool _framedLayout = false;

  /// Full-screen reel chosen from the frame's button.
  bool _reelFullScreen = false;
  /// User's choice 2026-11-14: framed reels. Don't switch off without asking them.
  final bool _framedDesignEnabled = true;
  /// Header with stories stays visible across reel scrolls; only hides in full-screen.
  static const double _framedHeaderFull = 102;
  static const double _framedHeaderSlim = 40;
  static const double _framedCommentHeight = 40;
  bool get _framedStories => true;
  double get _framedHeaderHeight => _framedStories ? _framedHeaderFull : _framedHeaderSlim;

  Content? get _currentContent {
    final item = _currentPage < _pages.length ? _pages[_currentPage] : null;
    return item is Content ? item : null;
  }

  /// The reel's screen frame: 25px top and bottom corners, zero side space, hairline border.
  Widget _framedCard(Widget child, {bool highlighted = false}) {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: highlighted
                    ? AppColors.brandPink.withValues(alpha: 0.55)
                    : AppColors.brandBlue.withValues(alpha: _palette.dark ? 0.22 : 0.14),
                blurRadius: highlighted ? 32 : 24,
                spreadRadius: highlighted ? 2 : -6,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: highlighted
                    ? AppColors.brandBlue.withValues(alpha: 0.45)
                    : AppColors.brandPink.withValues(alpha: _palette.dark ? 0.12 : 0.08),
                blurRadius: highlighted ? 24 : 16,
                spreadRadius: highlighted ? 1 : -8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: Stack(fit: StackFit.expand, children: [
              ColoredBox(color: _palette.dark ? const Color(0xFF0F131D) : Colors.black),
              child,
              IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: highlighted
                          ? AppColors.brandPink
                          : (_palette.dark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.08)),
                      width: highlighted ? 2.2 : 1.0,
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// Search · Trends · LIVE · Shop · bell, then stories.
  Widget _buildFramedHeader() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: _framedHeaderSlim - 4,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            _buildSearchButton(),
            Expanded(child: Center(child: _buildFramedTabs())),
            const _RingingBell(),
          ]),
        ),
      ),
      // Stories only at the top of the feed; they fold away once you swipe.
      AnimatedSize(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: _framedStories
            ? SizedBox(
                height: _framedHeaderFull - _framedHeaderSlim,
                child: Padding(padding: const EdgeInsets.only(left: 12), child: _buildStoriesList()),
              )
            : const SizedBox(width: double.infinity),
      ),
    ]);
  }

  Widget _buildFramedTabs() {
    final following = _currentMode == FeedMode.following;
    final hasLive = _pages.any((p) => p is LiveFeedSlot);
    void setMode(FeedMode m) {
      if (_currentMode == m) return;
      setState(() {
        _currentMode = m;
        _currentIndex = 0;
        _currentPage = 0;
      });
      _safeJumpToPage(0);
      _loadFeed();
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // Trends = the main feed; long-press switches to people you follow.
        GestureDetector(
          onLongPress: () {
            HapticFeedback.mediumImpact();
            setMode(following ? FeedMode.forYou : FeedMode.following);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(following ? 'Showing trends' : 'Showing people you follow'),
              duration: const Duration(milliseconds: 1200),
              behavior: SnackBarBehavior.floating,
            ));
          },
          child: _buildTopTabItem(following ? 'Following' : 'Trends', true, () => setMode(FeedMode.forYou)),
        ),
        const SizedBox(width: 14),
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            final next = _pages.indexWhere((p) => p is LiveFeedSlot, _currentPage + 1);
            final any = next >= 0 ? next : _pages.indexWhere((p) => p is LiveFeedSlot);
            if (any >= 0) {
              _pageController.animateToPage(any, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('No one is live right now.'),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(label: 'Go live', onPressed: () => context.push('/live/setup')),
              ));
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _palette.dark ? AppColors.brandPink : AppColors.brandPink.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: AppColors.brandPink.withValues(alpha: _palette.dark ? 1 : 0.4)),
              boxShadow: _palette.dark && hasLive ? [BoxShadow(color: AppColors.brandPink.withValues(alpha: 0.5), blurRadius: 10)] : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(shape: BoxShape.circle, color: _palette.dark ? Colors.white : AppColors.brandPink),
              ),
              const SizedBox(width: 5),
              Text('LIVE',
                  style: GoogleFonts.inter(
                    color: _palette.dark ? Colors.white : AppColors.brandPink,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  )),
            ]),
          ),
        ),
        const SizedBox(width: 14),
        _buildTopTabItem('Shop', false, () => context.push('/shops')),
      ]),
    );
  }

  Widget _frameChip({required Widget child, required VoidCallback onTap, VoidCallback? onLongPress}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: DefaultTextStyle(
              style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.92), fontSize: 11, fontWeight: FontWeight.w600),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  /// Auto · Loop (left) and Fullscreen + Captions (right), inside the frame.
  Widget _buildFrameChips() {
    final cc = ref.watch(oneovaCaptionsEnabledProvider);
    return Row(children: [
      _frameChip(
        onTap: () {
          setState(() => _isAutoScrollEnabled = !_isAutoScrollEnabled);
          _savePlaybackPref('autoScroll', _isAutoScrollEnabled);
          _attachAutoScrollListener();
        },
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isAutoScrollEnabled ? const Color(0xFF34D399) : Colors.white38,
            ),
          ),
          const SizedBox(width: 5),
          const Text('Auto'),
        ]),
      ),
      const SizedBox(width: 6),
      _frameChip(
        onTap: () => _updateLoopMode(!_isLoopModeEnabled),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_isLoopModeEnabled ? Icons.repeat_rounded : Icons.repeat_one_rounded,
              size: 12, color: _isLoopModeEnabled ? Colors.white : Colors.white54),
          const SizedBox(width: 4),
          Text('Loop', style: TextStyle(color: _isLoopModeEnabled ? Colors.white : Colors.white54)),
        ]),
      ),
      const Spacer(),
      _frameChip(
        onTap: () => _toggleFullScreenMode(),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            (_reelFullScreen || ref.watch(oneovaFocusModeProvider))
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            size: 15,
            color: (_reelFullScreen || ref.watch(oneovaFocusModeProvider))
                ? AppColors.brandPink
                : Colors.white,
          ),
          const SizedBox(width: 3),
          Text((_reelFullScreen || ref.watch(oneovaFocusModeProvider)) ? 'Exit' : 'Full'),
        ]),
      ),
      const SizedBox(width: 6),
      _frameChip(
        onTap: () => ref.read(oneovaCaptionsEnabledProvider.notifier).toggle(),
        onLongPress: () async {
          final item = _currentContent;
          if (item == null) return;
          final t = await ref.read(oneovaTranscriptionServiceProvider).getTranscript(
                item.id,
                mediaUrl: item.mediaUrl,
                fallbackText: item.description,
                duration: item.mediaMetadata.duration,
              );
          if (!mounted || t == null) return;
          final player = ref.read(videoPlaybackManagerProvider).getPlayer(item.id);
          showOneovaTranscriptSheet(
            context,
            transcript: t,
            currentPositionMs: player?.state.position.inMilliseconds ?? 0,
            onSeek: (ms) => player?.seek(Duration(milliseconds: ms)),
          );
        },
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(cc ? Icons.closed_caption_rounded : Icons.closed_caption_outlined,
              size: 13, color: cc ? AppColors.brandPink : Colors.white),
          const SizedBox(width: 4),
          const Text('Captions'),
        ]),
      ),
    ]);
  }

  /// One feed page (reel, live slot or feedback card).
  Widget _buildPage(int index, {required bool isFocusMode, bool framed = false, bool immersive = false}) {
                final isScreenActive = ref.watch(videoPlaybackManagerProvider).isScreenActive;
                final item = _pages[index];
                if (item is FeedPulseSlot) {
                  final card = FeedPulseCard(
                    key: ValueKey(item.id),
                    slot: item,
                    onDone: () => _safeAnimateToNextPage(),
                  );
                  return (framed || immersive) ? _framedCard(card) : card;
                }
                if (item is LiveFeedSlot) {
                  final live = LiveFeedCard(
                    key: ValueKey('live_${item.streamId}'),
                    initial: item.initial,
                    isActive: index == _currentPage && isScreenActive,
                    onSkip: () => _safeAnimateToNextPage(),
                  );
                  return (framed || immersive) ? _framedCard(live) : live;
                }
                final content = item as Content;
                final isHighlighted = _highlightedContentId != null && _highlightedContentId == content.id;
                final item0 = _ShortVideoItem(
                      key: ValueKey(content.id),
                      content: content,
                      isActive: index == _currentPage && isScreenActive,
                      isFullScreen: isFocusMode && !(framed || immersive),
                      framed: framed || immersive,
                      immersive: immersive,
                      onToggleFullScreen: (framed || immersive)
                          ? () => _toggleFullScreenMode()
                          : null,
                    );
                if (framed || immersive) return _framedCard(item0, highlighted: isHighlighted);
                return RepaintBoundary(
                  child: _buildCinemaFrame(index: index, cinema: isFocusMode, child: item0),
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
        return AnimatedBuilder(
          animation: _pageController,
          child: child,
          builder: (context, child) {
            double page = _currentPage.toDouble();
            try {
              if (mounted &&
                  _pageController.hasClients &&
                  _pageController.positions.length == 1) {
                final pos = _pageController.positions.first;
                if (pos.haveDimensions && pos is PageMetrics) {
                  final pageMetrics = pos as PageMetrics;
                  final p = pageMetrics.page;
                  if (p != null) page = p;
                }
              }
            } catch (_) {}
            final delta = (page - index).abs().clamp(0.0, 1.0);
            final scale = 1.0 - (0.04 * delta) - (0.02 * t);
            final double radius = 18.0 + (8.0 * t);
            return Opacity(
              opacity: (1.0 - 0.35 * delta * (0.3 + 0.7 * t)).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 1.0,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    clipBehavior: Clip.antiAliasWithSaveLayer,
                    child: child,
                  ),
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

  Widget _buildTopTabItem(String label, bool isSelected, VoidCallback onTap, {IconData? icon}) {
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
              child: icon == null
                  ? Text(label)
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icon, size: 15, color: isSelected ? _palette.fg : _palette.fgSoft, shadows: _palette.textShadow),
                      const SizedBox(width: 4),
                      Text(label),
                    ]),
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

  /// Scales down instead of overflowing on narrow phones (360dp).
  Widget _buildFeedTabs() {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
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
            _safeJumpToPage(0);
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
            _safeJumpToPage(0);
            _loadFeed();
          },
        ),
        const SizedBox(width: 18),
        _buildTopTabItem(
          'Biz & Shop',
          false,
          () => context.push('/shops'),
          icon: Icons.storefront_rounded,
        ),
      ],
      ),
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
            const SizedBox(width: 8),
            Expanded(child: Center(child: _buildFeedTabs())),
            const SizedBox(width: 8),
            const _RingingBell(),
          ],
        ),
        const SizedBox(height: 4),
        // Stories
        SizedBox(height: 70, child: _buildStoriesList()),
        const SizedBox(height: 6),
        // Executive Reel Control Dock
        Align(
          alignment: Alignment.centerLeft,
          child: _buildReelControlDock(),
        ),
      ],
    );
  }

  /// Your story, people who are live, and unseen stories.
  Widget _buildStoriesList() {
    return Builder(
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
                      _framedLayout ? 'Your story' : 'Your Story',
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
          );
  }

  /// Playback toggles stay folded into one chip until the viewer opens them.
  bool _playbackOpen = false;

  Widget _buildReelControlDock() {
    final anyOn = _isAutoScrollEnabled || _isLoopModeEnabled;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: _playbackOpen
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: _buildReelControlDockFull()),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _playbackOpen = false);
                },
                child: Icon(Icons.close_rounded, size: 18, color: _palette.fgSoft),
              ),
            ])
          : GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _playbackOpen = true);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _palette.glass,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(color: _palette.glassBorder, width: 1.0),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.tune_rounded, size: 13, color: anyOn ? AppColors.brandPink : _palette.fgSoft),
                  const SizedBox(width: 4),
                  Text('Playback', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: _palette.fgSoft)),
                ]),
              ),
            ),
    );
  }

  Widget _buildReelControlDockFull() {
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
              _toggleFullScreenMode();
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
          Container(
            height: 10,
            width: 1,
            color: _palette.divider,
            margin: const EdgeInsets.symmetric(horizontal: 6),
          ),
          // YouTube-style Closed Captions (CC) toggle & unlock
          Consumer(
            builder: (context, ref, _) {
              final isCC = ref.watch(oneovaCaptionsEnabledProvider);
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(oneovaCaptionsEnabledProvider.notifier).toggle();
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        !isCC ? 'Captions ON (auto-transcribing)' : 'Captions OFF',
                      ),
                      backgroundColor: !isCC ? AppColors.brandBlue : AppColors.darkSurface,
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                onLongPress: () async {
                  if (_feed.isNotEmpty && _currentIndex < _feed.length) {
                    final item = _feed[_currentIndex];
                    final t = await ref.read(oneovaTranscriptionServiceProvider).getTranscript(
                      item.id,
                      mediaUrl: item.mediaUrl,
                      fallbackText: item.description,
                      duration: item.mediaMetadata.duration,
                    );
                    if (!mounted || !context.mounted) return;
                    if (t != null) {
                      final player = ref.read(videoPlaybackManagerProvider).getPlayer(item.id);
                      final pos = player?.state.position.inMilliseconds ?? 0;
                      showOneovaTranscriptSheet(
                        context,
                        transcript: t,
                        currentPositionMs: pos,
                        onSeek: (ms) => player?.seek(Duration(milliseconds: ms)),
                      );
                    }
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isCC ? Icons.closed_caption_rounded : Icons.closed_caption_outlined,
                      size: 13,
                      color: isCC ? AppColors.brandPink : _palette.fgSoft,
                    ),
                    const SizedBox(width: 2.5),
                    Text(
                      'CC',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: isCC ? FontWeight.w800 : FontWeight.w600,
                        color: isCC ? AppColors.brandPink : _palette.fgSoft,
                      ),
                    ),
                  ],
                ),
              );
            },
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
          radius: _framedLayout ? 19.5 : 19,
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
      width: _framedLayout ? 62 : 54,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 3),
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

  /// Inside the rounded screen frame (portrait feed): positions are relative
  /// to the frame and the comment bar sits under it, outside the reel.
  final bool framed;

  /// Full-screen reel (framed styling, extended frame): offsets include the
  /// phone's bottom inset since the nav is hidden.
  final bool immersive;

  /// One-tap toggle between standard framed reel and extended full-screen frame.
  final VoidCallback? onToggleFullScreen;

  const _ShortVideoItem({
    super.key,
    required this.content,
    required this.isActive,
    this.isFullScreen = false,
    this.framed = false,
    this.immersive = false,
    this.onToggleFullScreen,
  });

  @override
  ConsumerState<_ShortVideoItem> createState() => _ShortVideoItemState();
}

class _ShortVideoItemState extends ConsumerState<_ShortVideoItem> with TickerProviderStateMixin {
  bool get _landscape => MediaQuery.orientationOf(context) == Orientation.landscape;
  double _itemHeight = 0;
  int _photoPageIndex = 0;
  final PageController _photoPageController = PageController();

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
  /// The like button: ambient hearts rise from here.
  final GlobalKey _likeAnchorKey = GlobalKey();

  bool? _optimisticIsSaved;
  int _optimisticSaveDelta = 0;

  final int _optimisticShareDelta = 0;

  Offset? _lastTapPosition;
  Offset? _burstHeartPosition;
  bool _showBurstHeart = false;
  bool _followJustConfirmed = false;
  bool _captionExpanded = false;
  bool _showPlayPauseIndicator = false;
  Timer? _playPauseFadeTimer;
  VideoPlaybackManager? _playbackManager;

  ReelPalette get _p => ReelPalette.of(context);

  /// Live copies of this reel's doc and of the viewer's like/save marks.
  /// Subscribed once per page (not per build), so rebuilds never resubscribe.
  late final ValueNotifier<Content> _live = ValueNotifier(widget.content);
  final ValueNotifier<bool> _liked = ValueNotifier(false);
  final ValueNotifier<bool> _saved = ValueNotifier(false);
  final List<StreamSubscription> _subs = [];

  void _subscribeLive() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final repo = ref.read(interactionRepositoryProvider);
    _subs.add(FirebaseFirestore.instance.collection('content').doc(widget.content.id).snapshots().listen((d) {
      if (d.exists) _live.value = Content.fromFirestore(d);
    }, onError: (Object e) => debugPrint('[Reel] doc: $e')));
    if (uid.isEmpty) return;
    _subs.add(repo.watchIsLiked(uid, widget.content.id).listen((v) => _liked.value = v, onError: (_) {}));
    _subs.add(repo.watchIsSaved(uid, widget.content.id).listen((v) => _saved.value = v, onError: (_) {}));
  }

  @override
  void initState() {
    super.initState();
    // A reel starts playing: hide the bottom nav (it peeks back on pause).
    if (widget.isActive && !widget.framed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(reelsNavPeekProvider.notifier).set(false);
      });
    }
    _subscribeLive();
    // The record only spins on the reel that is on screen.
    _vinylController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.isActive) _vinylController.repeat();
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
        if (track != null &&
            track.contentUrl.trim().isNotEmpty &&
            widget.content.isPhotoOrCarousel) {
          _playbackManager?.attachAudioForPhotoReel(
            widget.content.id,
            track.contentUrl.trim(),
          );
        }
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playbackManager = ref.read(videoPlaybackManagerProvider);
  }

  @override
  void deactivate() {
    final player = _playbackManager?.getPlayer(widget.content.id);
    player?.setVolume(0.0);
    player?.pause();
    _vinylController.stop();
    super.deactivate();
  }

  @override
  void dispose() {
    _playPauseFadeTimer?.cancel();
    _photoPageController.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    _live.dispose();
    _liked.dispose();
    _saved.dispose();
    _burstHeartController.dispose();
    _likePulseController.dispose();
    _vinylController.dispose();
    super.dispose();
  }

  void _safeBurstFloatingHearts({int count = 4}) {
    try {
      if (_floatingHeartsKey.currentContext != null) {
        _floatingHeartsKey.currentState?.burst(count: count);
      }
    } catch (_) {}
  }

  // ignore: unused_element
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
        _safeBurstFloatingHearts(count: 4);
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
    // Paused: the bottom nav slides back; playing: it hides again.
    if (!widget.framed) ref.read(reelsNavPeekProvider.notifier).set(!isPlaying);
    setState(() {
      _showPlayPauseIndicator = true;
    });
    _playPauseFadeTimer?.cancel();
    if (isPlaying) {
      _playPauseFadeTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _showPlayPauseIndicator = false);
      });
    }
  }

  @override
  void didUpdateWidget(_ShortVideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      if (!widget.framed) ref.read(reelsNavPeekProvider.notifier).set(false);
      ref.read(videoPlaybackManagerProvider).ensureCurrentPlaying(widget.content.id);
      if (widget.content.isPhotoOrCarousel &&
          _audioTrack != null &&
          _audioTrack!.contentUrl.trim().isNotEmpty) {
        ref
            .read(videoPlaybackManagerProvider)
            .attachAudioForPhotoReel(widget.content.id, _audioTrack!.contentUrl.trim());
      }
      _vinylController.repeat();
    } else if (!widget.isActive && oldWidget.isActive) {
      final player = ref.read(videoPlaybackManagerProvider).getPlayer(widget.content.id);
      player?.setVolume(0.0);
      player?.pause();
      _vinylController.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final playbackManager = ref.watch(videoPlaybackManagerProvider);
    return ValueListenableBuilder<int>(
      valueListenable: playbackManager.slotsRevision,
      builder: (context, _, _) => _buildItem(context, playbackManager.getController(widget.content.id)),
    );
  }

  Widget _buildItem(BuildContext context, VideoController? controller) {
    final isMultiPhoto = widget.content.isPhotoOrCarousel && widget.content.mediaUrls.length > 1;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        if (widget.onToggleFullScreen != null) {
          widget.onToggleFullScreen!();
        } else {
          _togglePlay();
        }
      },
      onDoubleTapDown: (details) {
        _lastTapPosition = details.localPosition;
      },
      onDoubleTap: () {
        HapticFeedback.mediumImpact();
        _togglePlay();
      },
      onLongPress: widget.isFullScreen ? null : () => _showFeedControls(context),
      onHorizontalDragEnd: isMultiPhoto
          ? null
          : (details) {
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
        final halfReelHeight = ((_itemHeight > 120 ? _itemHeight : MediaQuery.sizeOf(context).height * 0.72) * 0.45)
            .clamp(180.0, 340.0);
        return Stack(
        fit: StackFit.expand,
        children: [
          // ── Video / Multi-Photo Player Surface ────────────────────
          // Cover stays visible underneath until the video decoder outputs its
          // first real frame (width > 0), eliminating black screen blinking.
          if (widget.content.isPhotoOrCarousel)
            _buildPhotoCarousel()
          else ...[
            _buildThumbnail(),
            if (controller != null)
              StreamBuilder<int?>(
                stream: controller.player.stream.width,
                initialData: controller.player.state.width,
                builder: (context, snap) {
                  final hasFrame = (snap.data ?? controller.player.state.width ?? 0) > 0;
                  return AnimatedOpacity(
                    opacity: hasFrame ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    child: RepaintBoundary(
                      child: Video(
                        controller: controller,
                        fit: _landscape ? BoxFit.contain : BoxFit.cover,
                        fill: Colors.transparent,
                        controls: NoVideoControls,
                      ),
                    ),
                  );
                },
              ),
          ],

          // ── Bottom Legibility Gradient Scrim (ensures owner & title are never hidden) ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 185,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.74),
                      Colors.black.withValues(alpha: 0.32),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Oneova Centered Play/Pause Indicator ─────────
          if (_showPlayPauseIndicator)
            Center(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _showPlayPauseIndicator ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: Icon(
                      (controller?.player.state.playing ?? false)
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                ),
              ),
            ),

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
              heartAnchor: _likeAnchorKey,
            ),

          // ── Engagement Rail Overlay (right: 8, constrained to half of the reel) ──
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            right: widget.framed ? 8 : 8,
            top: _landscape ? MediaQuery.paddingOf(context).top + 64 : null,
            bottom: widget.framed
                ? 14
                : _landscape
                ? 8.0 + MediaQuery.paddingOf(context).bottom
                : (ref.watch(oneovaBottomNavVisibleProvider) && !widget.isFullScreen
                    ? 56.0 + MediaQuery.paddingOf(context).bottom
                    : 6.0 + MediaQuery.paddingOf(context).bottom),
            child: AnimatedSlide(
              offset: widget.isFullScreen ? const Offset(1.2, 0) : Offset.zero,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubic,
              child: AnimatedOpacity(
                opacity: widget.isFullScreen ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 220),
                child: IgnorePointer(
                  ignoring: widget.isFullScreen,
                  child: _landscape
                      ? SingleChildScrollView(child: _buildEngagementOverlay())
                      // Portrait: strictly constrained to the lower half of the reel frame.
                      : ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: halfReelHeight),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.bottomCenter,
                            child: _buildEngagementOverlay(),
                          ),
                        ),
                ),
              ),
            ),
          ),
          // ── Realtime Auto-Synced Closed Caption (CC) Overlay ──
          if (widget.isActive)
            Positioned(
              left: 16,
              right: _landscape ? null : 76,
              bottom: widget.framed
                  ? 140
                  : _landscape
                  ? 120.0 + MediaQuery.paddingOf(context).bottom
                  : (ref.watch(oneovaBottomNavVisibleProvider) && !widget.isFullScreen
                      ? 186.0 + MediaQuery.paddingOf(context).bottom
                      : 136.0 + MediaQuery.paddingOf(context).bottom),
              child: OneovaCaptionOverlay(content: widget.content),
            ),
          // ── Content Info Overlay (Owner & Title never hidden) ──────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: 0,
            right: _landscape ? null : (widget.framed ? 58 : 66),
            width: _landscape ? (MediaQuery.sizeOf(context).width * 0.45).clamp(280.0, 520.0) : null,
            bottom: widget.framed
                ? 12
                : _landscape
                ? 8.0 + MediaQuery.paddingOf(context).bottom
                : (ref.watch(oneovaBottomNavVisibleProvider) && !widget.isFullScreen
                    ? 56.0 + MediaQuery.paddingOf(context).bottom
                    : 4.0 + MediaQuery.paddingOf(context).bottom),
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


          // ── Focus Mode (Clear Display) Floating Controls ──
          if (widget.isFullScreen)
            Positioned(
              left: 14,
              right: 14,
              bottom: 24.0 + MediaQuery.paddingOf(context).bottom,
              child: AnimatedOpacity(
                opacity: widget.isFullScreen ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 220),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Quick Comment Pill
                    _PressScale(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _showComments(context, autoFocus: true);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _p.glass,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          border: Border.all(color: _p.glassBorder, width: 1.0),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'Comment',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Quick Emojis
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _p.glass,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        border: Border.all(color: _p.glassBorder, width: 1.0),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildQuickReactionEmoji('❤️', FirebaseAuth.instance.currentUser?.uid ?? ''),
                          const SizedBox(width: 8),
                          _buildQuickReactionEmoji('🔥', FirebaseAuth.instance.currentUser?.uid ?? ''),
                          const SizedBox(width: 8),
                          _buildQuickReactionEmoji('😂', FirebaseAuth.instance.currentUser?.uid ?? ''),
                          const SizedBox(width: 8),
                          _buildQuickReactionEmoji('👏', FirebaseAuth.instance.currentUser?.uid ?? ''),
                        ],
                      ),
                    ),

                    // Exit Focus Mode Pill
                    _PressScale(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        ref.read(oneovaFocusModeProvider.notifier).set(false);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.brandBlue,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.0),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.brandBlue.withValues(alpha: 0.4),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.fullscreen_exit_rounded, color: Colors.white, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'Exit Clear Mode',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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

  Widget _buildPhotoCarousel() {
    final urls = widget.content.mediaUrls.isNotEmpty
        ? widget.content.mediaUrls
        : (widget.content.mediaUrl.isNotEmpty ? [widget.content.mediaUrl] : const <String>[]);
    if (urls.length <= 1) {
      return _buildThumbnail();
    }
    final mq = MediaQuery.maybeOf(context);
    final rawPx = mq != null ? (mq.size.width * mq.devicePixelRatio) : null;
    final rawWidth = (rawPx != null && rawPx.isFinite) ? rawPx.round() : null;
    final cacheWidth = (rawWidth != null && rawWidth > 0) ? rawWidth : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _photoPageController,
          itemCount: urls.length,
          onPageChanged: (idx) {
            HapticFeedback.selectionClick();
            setState(() => _photoPageIndex = idx);
          },
          itemBuilder: (context, idx) {
            final imgUrl = urls[idx];
            return Image(
              image: ResizeImage.resizeIfNeeded(
                cacheWidth,
                null,
                CachedNetworkImageProvider(imgUrl, cacheManager: ReelPrefetcher.thumbCache),
              ),
              fit: _landscape ? BoxFit.contain : BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _buildThumbnail(),
            );
          },
        ),
        // Top-right counter badge (e.g. 1 / 4)
        Positioned(
          top: 44,
          right: 12,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.collections_rounded, size: 12, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    '${_photoPageIndex + 1} / ${urls.length}',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Bottom-center dot indicators above the author/caption block
        Positioned(
          left: 0,
          right: 0,
          bottom: 112,
          child: IgnorePointer(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < urls.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: i == _photoPageIndex ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _photoPageIndex
                          ? AppColors.brandPink
                          : Colors.white.withValues(alpha: 0.48),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThumbnail() {
    final url = widget.content.isPhotoOrCarousel
        ? widget.content.mediaUrl
        : widget.content.mediaMetadata.thumbnailUrl;
    if (url == null || url.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _p.placeholder,
              _p.dark ? const Color(0xFF141414) : const Color(0xFFF1F5F9),
              _p.placeholder,
            ],
          ),
        ),
      );
    }
    // Decoded at screen width only (not the source size) to keep image memory low.
    final mq = MediaQuery.maybeOf(context);
    final rawPx = mq != null ? (mq.size.width * mq.devicePixelRatio) : null;
    final rawWidth = (rawPx != null && rawPx.isFinite) ? rawPx.round() : null;
    final cacheWidth = (rawWidth != null && rawWidth > 0) ? rawWidth : null;
    return Image(
      image: ResizeImage.resizeIfNeeded(
        cacheWidth,
        null,
        CachedNetworkImageProvider(url, cacheManager: ReelPrefetcher.thumbCache),
      ),
      fit: _landscape ? BoxFit.contain : BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _p.placeholder,
              _p.dark ? const Color(0xFF141414) : const Color(0xFFF1F5F9),
              _p.placeholder,
            ],
          ),
        ),
      ),
    );
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

    return ValueListenableBuilder<Content>(
      valueListenable: _live,
      builder: (context, content, _) {

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
              if (!widget.framed) Stack(
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
              if (!widget.framed) const SizedBox(height: 8),
              ValueListenableBuilder<bool>(
                valueListenable: _liked,
                builder: (context, serverLiked, _) {
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
                        child: KeyedSubtree(
                          key: _likeAnchorKey,
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
                                if (next) _safeBurstFloatingHearts(count: 3);
                                _setLiked(uid, next);
                              },
                            );
                          },
                        ),
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
              ValueListenableBuilder<bool>(
                valueListenable: _saved,
                builder: (context, actualIsSaved, _) {
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
              if (widget.framed) _buildGiftAction(),
              _buildRailAction(
                Icons.share_rounded,
                content.shareCount + _optimisticShareDelta,
                accentColor: AppColors.brandBlue,
                onTap: () {
                  AuthInteractionGate.requireAuth(
                    context,
                    actionTitle: 'share videos and generate links',
                    onAuthenticated: () {
                      ref.read(recommendationServiceProvider).trackEvent(uid, widget.content.id, ContentInteractionType.share, {});
                      ShareSheet.show(
                        context,
                        postId: widget.content.id,
                        authorId: widget.content.authorId,
                        content: widget.content,
                      );
                    },
                  );
                },
              ),
              if (!widget.framed) _PressScale(
                onTap: () {
                  HapticFeedback.lightImpact();
                  AuthInteractionGate.requireAuth(
                    context,
                    actionTitle: 'remix and create studio content',
                    onAuthenticated: () => RemixLauncher.start(context, widget.content),
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
              SizedBox(height: widget.framed ? 2 : 12),
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
                    width: widget.framed ? 36 : 30,
                    height: widget.framed ? 36 : 30,
                    padding: EdgeInsets.all(widget.framed ? 6 : 5),
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
    final f = widget.framed;
    return Padding(
      padding: EdgeInsets.only(bottom: f ? 8 : 8),
      child: _PressScale(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap?.call();
        },
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: glowColor != null
                    ? glowColor.withValues(alpha: 0.22)
                    : Colors.black.withValues(alpha: 0.38),
                shape: BoxShape.circle,
                border: Border.all(
                  color: glowColor != null
                      ? glowColor.withValues(alpha: 0.7)
                      : Colors.white.withValues(alpha: 0.18),
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
                child: Icon(icon, key: ValueKey(icon), color: color ?? Colors.white, size: 18),
              ),
            ),
            const SizedBox(height: 2),
            RollingCount(
              value: math.max(0, count),
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Framed rail: the pink Gift button (sends a coin gift to the creator).
  Widget _buildGiftAction() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _PressScale(
        onTap: () {
          HapticFeedback.mediumImpact();
          AuthInteractionGate.requireAuth(
            context,
            actionTitle: 'send gifts',
            onAuthenticated: () {
              final author = ref.read(_reelAuthorProvider(widget.content.authorId)).value;
              UserGiftSheet.show(
                context,
                toUid: widget.content.authorId,
                toName: author?.username?.isNotEmpty == true ? author!.username! : 'this creator',
              );
            },
          );
        },
        child: Column(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brandPink,
              border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
              boxShadow: [BoxShadow(color: AppColors.brandPink.withValues(alpha: 0.55), blurRadius: 14)],
            ),
            child: const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 2),
          Text('Gift',
              style: GoogleFonts.inter(
                color: AppColors.brandPink,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
              )),
        ]),
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
          if (widget.framed)
            _framedAuthorRow(author, username, initial, avatarUrl, currentUid, openProfile)
          else
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

          // ── Reel Title (always visible when provided) ───────
          if (widget.content.title != null &&
              widget.content.title!.trim().isNotEmpty &&
              widget.content.title!.trim() !=
                  widget.content.description.trim()) ...[
            const SizedBox(height: 6),
            Text(
              widget.content.title!.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                height: 1.25,
                shadows: textShadow,
              ),
            ),
          ],

          // ── Caption (tap to expand) ─────────────────────────
          if (widget.content.description.replaceAll(RegExp(r'(^|\s)#[\w\u00C0-\uFFFF]+'), '').trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _captionExpanded = !_captionExpanded),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topLeft,
                child: ReelTranslatedCaption(
                  reelId: widget.content.id,
                  caption: widget.content.description,
                  originalText: widget.content.hashtags.isEmpty
                      ? widget.content.description
                      : widget.content.description.replaceAll(RegExp(r'(^|\s)#[\w\u00C0-\uFFFF]+'), '').replaceAll(RegExp(r'\s{2,}'), ' ').trim(),
                  style: GoogleFonts.inter(
                    color: Colors.white,
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
                      color: widget.framed
                          ? (widget.content.hashtags.indexOf(tag).isEven
                              ? const Color(0xFF5EA2FF)
                              : AppColors.brandPink)
                          : (p.dark ? Colors.white : AppColors.brandBlue),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      shadows: textShadow,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          // ── Destination link (server-validated) ─────────────
          ValueListenableBuilder<Content>(
            valueListenable: _live,
            builder: (context, live, _) => live.destination == null
                ? const SizedBox.shrink()
                : ReelDestinationChip(contentId: live.id, destination: live.destination!),
          ),

          // ── Shop chip (real Biz products only) ──────────────
          if (!widget.framed) _ShopChip(authorId: widget.content.authorId, username: username),

          const SizedBox(height: 4),

          // ── Add comment bar (tap mic = live transcription, hold = voice comment) ──
          if (!widget.framed) ReelCommentBar(
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
                _buildQuickReactionEmoji('❤️', currentUid),
                const SizedBox(width: 4),
                _buildQuickReactionEmoji('🔥', currentUid),
                const SizedBox(width: 4),
                _buildQuickReactionEmoji('😂', currentUid),
                const SizedBox(width: 4),
                _buildQuickReactionEmoji('👏', currentUid),
                const SizedBox(width: 4),
                _buildQuickReactionEmoji('😍', currentUid),
              ],
            ),
          ),
          if (!widget.framed) const SizedBox(height: 2), // Snug flush above bottom nav
        ],
      ),
    );
  }

  /// Framed design: ringed avatar, name with verified tick, blue Follow pill.
  Widget _framedAuthorRow(AppUser? author, String username, String initial, String avatarUrl, String currentUid, VoidCallback openProfile) {
    final p = _p;
    final isSelf = currentUid.isNotEmpty && currentUid == widget.content.authorId;
    return Row(children: [
      _PressScale(
        onTap: openProfile,
        child: Container(
          width: 38,
          height: 38,
          padding: const EdgeInsets.all(1.5),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [AppColors.brandPink, AppColors.brandBlue]),
          ),
          child: Container(
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.bg),
            child: ClipOval(
              child: avatarUrl.isNotEmpty
                  ? Image.network(avatarUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => _pillInitial(initial))
                  : ColoredBox(color: AppColors.brandBlue, child: _pillInitial(initial)),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: GestureDetector(
          onTap: openProfile,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(
                '@$username',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
                ),
              ),
            ),
            if (author?.isVerified ?? false) ...[
              const SizedBox(width: 4),
              const Icon(Icons.verified_rounded, color: AppColors.brandBlue, size: 15),
            ],
          ]),
        ),
      ),
      if (!isSelf && currentUid.isNotEmpty) ...[
        const SizedBox(width: 8),
        StreamBuilder<bool>(
          stream: ref.read(relationshipRepositoryProvider).watchIsFollowing(currentUid, widget.content.authorId),
          builder: (context, snap) => (snap.data ?? false)
              ? const SizedBox.shrink()
              : _ReelFollowButton(
                  targetUserId: widget.content.authorId,
                  currentUserId: currentUid,
                  isFollowing: false,
                  isPending: false,
                ),
        ),
      ],
    ]);
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

  void _showSpeedSheet(BuildContext context, dynamic player) {
    HapticFeedback.lightImpact();
    final double currentRate = player?.state.rate ?? 1.0;
    const rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ctx.border,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Playback Speed',
                  style: GoogleFonts.inter(
                    color: ctx.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: rates.map((r) {
                    final isSelected = (currentRate - r).abs() < 0.05;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        player?.setRate(r);
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.brandBlue : ctx.surfaceMid,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          border: Border.all(
                            color: isSelected ? AppColors.brandBlue : ctx.border,
                            width: 1.0,
                          ),
                        ),
                        child: Text(
                          '${r}x',
                          style: GoogleFonts.inter(
                            color: isSelected ? Colors.white : ctx.textPrimary,
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFeedControls(BuildContext context) {
    HapticFeedback.mediumImpact();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final rec = ref.read(recommendationServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final player = ref.read(videoPlaybackManagerProvider).getController(widget.content.id)?.player;
    final isMuted = (player?.state.volume ?? 100) == 0;

    final author = ref.read(_reelAuthorProvider(widget.content.authorId)).value;
    final authorName = author?.username?.isNotEmpty == true
        ? author!.username!
        : (author?.fullName.isNotEmpty == true ? author!.fullName : 'this creator');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
          child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85),
          child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
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
              AboutReelCard(
                content: widget.content,
                authorName: authorName,
                onAskOva: (q) {
                  Navigator.pop(sheetContext);
                  OneOvaAssistantOverlay.show(
                    context,
                    userId: uid.isEmpty ? null : uid,
                    contentId: widget.content.id,
                    initialPrompt: q.trim().isNotEmpty
                        ? '${q.trim()} (about this reel by @$authorName: "${widget.content.description}")'
                        : 'Tell me about this reel by @$authorName: "${widget.content.description}"',
                  );
                },
              ),
              Divider(height: 20, color: sheetContext.border),
              tile(Icons.auto_awesome_rounded, 'Remix this reel', () {
                AuthInteractionGate.requireAuth(
                  context,
                  actionTitle: 'remix and create studio content',
                  onAuthenticated: () => RemixLauncher.start(context, widget.content),
                );
              }, iconColor: AppColors.brandPink),
              tile(Icons.check_circle_outline_rounded, 'Interested', () {
                rec.markInterested(uid, widget.content.id);
                messenger.showSnackBar(const SnackBar(content: Text("We'll show more videos like this.")));
              }),
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
              tile(Icons.info_outline_rounded, 'Why you’re seeing this', () async {
                final explanation = await rec.getWhyAmISeeingThis(widget.content.id, userId: uid.isEmpty ? null : uid);
                if (!context.mounted) return;
                showDialog(
                  context: context,
                  builder: (c) => AlertDialog(
                    backgroundColor: c.surface,
                    title: Text('Why you’re seeing this', style: TextStyle(color: c.textPrimary)),
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
              tile(
                Icons.fullscreen_rounded,
                'Clear Display (Focus Mode)',
                () {
                  HapticFeedback.lightImpact();
                  ref.read(oneovaFocusModeProvider.notifier).set(true);
                },
                iconColor: AppColors.brandBlue,
              ),
              tile(
                Icons.speed_rounded,
                'Playback Speed (${player?.state.rate ?? 1.0}x)',
                () => _showSpeedSheet(context, player),
                iconColor: AppColors.brandBlue,
              ),
              tile(Icons.shield_outlined, 'Live presence & privacy', () => OneovaQuickPrivacySheet.show(context),
                  iconColor: AppColors.brandBlue),
              if (widget.content.authorId == uid)
                tile(Icons.delete_outline_rounded, 'Delete post', () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      backgroundColor: c.surface,
                      title: Text('Delete this post?', style: TextStyle(color: c.textPrimary)),
                      content: Text('It will be removed for everyone, with its likes and comments. This can\'t be undone.',
                          style: TextStyle(color: c.textSecondary)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancel', style: TextStyle(color: c.textSecondary))),
                        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: AppColors.brandPink))),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  try {
                    player?.pause();
                    await ContentDeletionService().deleteOwnPost(widget.content.id);
                    messenger.showSnackBar(const SnackBar(content: Text('Post deleted.')));
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
                  }
                }, iconColor: AppColors.brandPink),
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
          ),
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
              child: ReelTranslatedCaption(
                reelId: widget.content.id,
                caption: widget.content.description,
                originalText: widget.content.description,
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
          context.push('/shops/$authorId');
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

/// Background behind the framed reel: deep base with soft brand light.
class _FramedBackdrop extends StatelessWidget {
  const _FramedBackdrop({required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF080B11) : const Color(0xFFF6F8FC),
          gradient: RadialGradient(
            center: const Alignment(0, 0.35),
            radius: 1.1,
            colors: dark
                ? [AppColors.brandBlue.withValues(alpha: 0.20), AppColors.brandPink.withValues(alpha: 0.06), const Color(0xFF080B11)]
                : [AppColors.brandBlue.withValues(alpha: 0.08), AppColors.brandPink.withValues(alpha: 0.04), const Color(0xFFF6F8FC)],
            stops: const [0, 0.45, 1],
          ),
        ),
      ),
    );
  }
}

/// Under the frame: comment pill, three quick reactions and the mic.
class _FramedCommentRow extends ConsumerWidget {
  const _FramedCommentRow({super.key, required this.content});
  final Content content;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final p = ReelPalette.of(context);
    final author = ref.watch(_reelAuthorProvider(content.authorId)).value;
    final name = author?.username?.isNotEmpty == true ? author!.username! : 'this creator';

    Widget reaction(String emoji) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => AuthInteractionGate.requireAuth(
            context,
            actionTitle: 'react to reels',
            onAuthenticated: () async {
              HapticFeedback.lightImpact();
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref.read(commentServiceProvider).addComment(
                      Comment(id: '', postId: content.id, authorId: uid, content: emoji, createdAt: DateTime.now()),
                      isCreator: content.authorId == uid,
                    );
                messenger.showSnackBar(SnackBar(
                  content: Text('Reacted $emoji'),
                  duration: const Duration(milliseconds: 1000),
                  behavior: SnackBarBehavior.floating,
                ));
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('Could not react: $e')));
              }
            },
          ),
          child: Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(right: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.glass,
              border: Border.all(color: p.glassBorder),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 15)),
          ),
        );

    return ReelCommentBar(
      framed: true,
      contentId: content.id,
      contentAuthorId: content.authorId,
      onOpenComments: () => AuthInteractionGate.requireAuth(
        context,
        actionTitle: 'comment on videos',
        onAuthenticated: () => CommentBottomSheet.show(context, content, autoFocus: true),
      ),
      onOpenAssistant: () => OneOvaAssistantOverlay.show(
        context,
        userId: uid.isEmpty ? null : uid,
        contentId: content.id,
        initialPrompt: 'What do you think of this reel by @$name: "${content.description}"?',
      ),
      reactions: Row(mainAxisSize: MainAxisSize.min, children: [reaction('🔥'), reaction('😂'), reaction('😍')]),
    );
  }
}
