import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:share_plus/share_plus.dart';

import '../shared/theme/app_theme.dart';
import '../backend/social/models/remix_source.dart';
import '../backend/publishing/models/publishing_destination.dart';
import '../backend/connections/linked_accounts.dart'
    show LinkedAccount, LinkedPlatform, linkedAccountsProvider;
import '../shared/widgets/linked_destinations_picker.dart';
import '../youtube_manager/services/youtube_account_store.dart';
import 'post/providers/post_draft_provider.dart';
import '../services/pending_post_queue.dart';
import '../backend/social/services/video_playback_manager.dart';
import 'post/services/post_search_service.dart';
import 'post/services/openrouter_post_optimizer.dart';
import 'post/widgets/caption_editor.dart';
import 'post/widgets/ai_suggestion_card.dart';
import 'post/widgets/cover_picker_sheet.dart';
import 'post/widgets/collaborator_sheet.dart';
import 'post/widgets/advanced_settings_sheet.dart';
import 'post/widgets/draft_status_pill.dart';

class MediaPreviewScreen extends ConsumerStatefulWidget {
  final String mediaPath;
  final bool isVideo;

  /// Cover frame picked in Studio (a JPEG next to the export) and its time.
  final String? initialCoverPath;
  final int initialCoverTimeMs;

  /// Set when the post remixes someone's post (attribution + earnings share).
  final RemixSource? remixOf;

  const MediaPreviewScreen({
    super.key,
    required this.mediaPath,
    required this.isVideo,
    this.initialCoverPath,
    this.initialCoverTimeMs = 0,
    this.remixOf,
  });

  @override
  ConsumerState<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends ConsumerState<MediaPreviewScreen> {
  // Text controllers
  late final TextEditingController _titleController;
  late final TextEditingController _captionController;
  Timer? _titleDebounce;
  String _lastOptimizedTitle = '';

  // Media Player
  Player? _player;
  VideoController? _videoController;
  late final AppLifecycleListener _lifecycleListener;

  // Cover settings
  int _coverTimeMs = 0;
  String? _customCoverPath;

  // Collaborators & Tagged creators
  List<String> _collaborators = [];
  List<String> _taggedUsers = [];

  // Advanced settings (Age, Privacy, Interactions, Disclosures, Geo)
  AdvancedPostSettings _advancedSettings = const AdvancedPostSettings();

  // Single selected connected channel (null = Oneova Only)
  Map<String, dynamic>? _selectedConnectedChannel;

  // Upload quality tier ('1080p_hd', '2k_60fps', '4k_master', 'original_raw')
  String _uploadQualityTier = '4k_master';
  bool _highQualityUploads = true;
  bool _fastTrendAccelerator = true;
  bool _autoOptimizeInBackground = true;

  // Destinations: Oneova always, plus the selected connected channel or saved post destinations
  Set<PlatformDestination> get _selectedPlatforms {
    final set = <PlatformDestination>{PlatformDestination.internal};
    final selPlat = (_selectedConnectedChannel?['platform'] ?? '').toString();
    if (selPlat == 'youtube') set.add(PlatformDestination.youtube);
    if (selPlat == 'tiktok') set.add(PlatformDestination.tiktok);
    if (selPlat == 'instagram') set.add(PlatformDestination.instagram);
    if (selPlat == 'facebook') set.add(PlatformDestination.facebook);
    for (final id in ref.read(activeDestinationsProvider(DestinationPurpose.post))) {
      final d = _destinationFor(LinkedPlatform.fromId(id));
      if (d != null && _selectedConnectedChannel == null) {
        set.add(d);
      }
    }
    return set;
  }

  static PlatformDestination? _destinationFor(LinkedPlatform? p) => switch (p) {
        LinkedPlatform.youtube => PlatformDestination.youtube,
        LinkedPlatform.tiktok => PlatformDestination.tiktok,
        LinkedPlatform.instagram => PlatformDestination.instagram,
        LinkedPlatform.facebook => PlatformDestination.facebook,
        _ => null,
      };

  // AI Optimizer State
  VideoOptimizationPackage? _optimization;
  bool _isAnalyzing = false;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _captionController = TextEditingController();
    _titleController.addListener(_onTitleChanged);
    _customCoverPath = widget.initialCoverPath;
    _coverTimeMs = widget.initialCoverTimeMs;

    if (widget.isVideo) {
      _player = Player();
      _videoController = VideoController(_player!);
      _player!.open(Media(widget.mediaPath));
      _player!.setVolume(100.0);
      _player!.setPlaylistMode(PlaylistMode.loop);
    }

    _lifecycleListener = AppLifecycleListener(
      onPause: () => _player?.pause(),
      onInactive: () => _player?.pause(),
      onHide: () => _player?.pause(),
      onResume: () {
        if (mounted && widget.isVideo) _player?.play();
      },
      onShow: () {
        if (mounted && widget.isVideo) _player?.play();
      },
    );

    // Initialize or restore draft from repository and pause background reels
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(videoPlaybackManagerProvider).setScreenActive(false);
      }
      _initDraftAndAi();
    });
  }

  void _onTitleChanged() {
    final current = _titleController.text.trim();
    if (current.length < 4 || current == _lastOptimizedTitle) return;
    _titleDebounce?.cancel();
    _titleDebounce = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      _lastOptimizedTitle = current;
      _runAiOptimization(autoApplyCaptionIfEmpty: _autoOptimizeInBackground);
    });
  }

  Future<void> _initDraftAndAi() async {
    final notifier = ref.read(postDraftProvider.notifier);
    await notifier.initializeForMedia(
      mediaPath: widget.mediaPath,
      isVideo: widget.isVideo,
    );

    final restored = ref.read(postDraftProvider).draft;
    if (restored != null && mounted) {
      setState(() {
        if (restored.title.isNotEmpty) _titleController.text = restored.title;
        if (restored.caption.isNotEmpty) _captionController.text = restored.caption;
        if (widget.initialCoverPath == null) {
          _coverTimeMs = restored.coverTimeMs;
          _customCoverPath = restored.coverImagePath;
        }
        _collaborators = List.from(restored.collaborators);
        _taggedUsers = List.from(restored.taggedUsers);
        _advancedSettings = AdvancedPostSettings(
          ageRestriction: restored.ageRestriction,
          privacy: restored.privacy,
          allowComments: restored.allowComments,
          allowDuet: restored.allowDuet,
          allowStitch: restored.allowStitch,
          allowRemix: restored.allowRemix,
          allowDownload: restored.allowDownload,
          isAiGenerated: restored.isAiGenerated,
          isBrandedContent: restored.isBrandedContent,
          geoRadiusTier: restored.geoRadiusTier,
          location: restored.location,
          link: restored.link,
        );
      });
    }

    // Launch background AI optimization non-blocking
    unawaited(_runAiOptimization(autoApplyCaptionIfEmpty: false));
  }

  Future<void> _runAiOptimization({bool autoApplyCaptionIfEmpty = false}) async {
    if (!mounted) return;
    setState(() => _isAnalyzing = true);

    try {
      final optimizer = ref.read(openRouterPostOptimizerProvider);
      final durationMs = widget.isVideo ? _player?.state.duration.inMilliseconds : null;
      final aspect = widget.isVideo &&
              _player?.state.width != null &&
              _player?.state.height != null &&
              _player!.state.height! > 0
          ? (_player!.state.width! / _player!.state.height!)
          : null;
      final selChannelLabel = _selectedConnectedChannel != null
          ? '${_selectedConnectedChannel!['platform']} (${_selectedConnectedChannel!['title']})'
          : null;

      final result = await optimizer.analyzeAndOptimize(
        mediaPath: widget.mediaPath,
        isVideo: widget.isVideo,
        currentTitle: _titleController.text.trim(),
        currentCaption: _captionController.text.trim(),
        selectedChannelLabel: selChannelLabel,
        durationMs: durationMs,
        aspectRatio: aspect,
        destinations: _selectedPlatforms.toList(),
      );

      if (mounted) {
        setState(() {
          _optimization = result;
          _isAnalyzing = false;
          if (_coverTimeMs == 0 &&
              _customCoverPath == null &&
              result.recommendedCoverTimeMs > 0) {
            _coverTimeMs = result.recommendedCoverTimeMs;
          }
          // When the user described their video title and auto-optimize is ON,
          // seamlessly populate the caption if they haven't typed one yet.
          if (autoApplyCaptionIfEmpty && _captionController.text.trim().isEmpty) {
            _captionController.text = result.suggestedDescription;
          }
        });
        if (autoApplyCaptionIfEmpty) _syncStateToDraft();
      }
    } catch (e) {
      debugPrint('[MediaPreviewScreen] AI background optimization error: $e');
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  void _syncStateToDraft() {
    final current = ref.read(postDraftProvider).draft;
    if (current == null) return;

    final updated = current.copyWith(
      title: _titleController.text.trim(),
      caption: _captionController.text.trim(),
      coverTimeMs: _coverTimeMs,
      coverImagePath: _customCoverPath,
      collaborators: _collaborators,
      taggedUsers: _taggedUsers,
      privacy: _advancedSettings.privacy,
      ageRestriction: _advancedSettings.ageRestriction,
      allowComments: _advancedSettings.allowComments,
      allowDuet: _advancedSettings.allowDuet,
      allowStitch: _advancedSettings.allowStitch,
      allowRemix: _advancedSettings.allowRemix,
      allowDownload: _advancedSettings.allowDownload,
      isAiGenerated: _advancedSettings.isAiGenerated,
      isBrandedContent: _advancedSettings.isBrandedContent,
      location: _advancedSettings.location,
      link: _advancedSettings.link,
      geoRadiusTier: _advancedSettings.geoRadiusTier,
      destinations: _selectedPlatforms.map((p) => p.name).toList(),
      isFastTrendBoosted: _fastTrendAccelerator,
    );

    ref.read(postDraftProvider.notifier).updateDraft(updated);
  }

  @override
  void dispose() {
    _titleDebounce?.cancel();
    _lifecycleListener.dispose();
    _player?.dispose();
    _titleController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> _saveToDevice() async {
    HapticFeedback.selectionClick();
    try {
      final file = File(widget.mediaPath);
      if (await file.exists()) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(widget.mediaPath)],
            text: '${_captionController.text.trim()} #oneova',
          ),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.brandBlue,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Saved to device gallery!',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[MediaPreviewScreen] Error saving to device: $e');
    }
  }

  Future<void> _manualSaveDraft() async {
    HapticFeedback.lightImpact();
    _syncStateToDraft();
    await ref.read(postDraftProvider.notifier).saveImmediately();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reel draft saved securely! You can resume editing anytime.'),
        backgroundColor: AppColors.brandBlue,
      ),
    );
    context.pop();
  }

  Future<void> _onPost() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in to publish on Oneova.'),
          backgroundColor: AppColors.brandPink,
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isPosting = true);

    // If background AI already finished and the user left title/caption empty
    // with auto-optimize enabled, apply the ready package immediately before queueing.
    var effectiveTitle = _titleController.text.trim();
    var effectiveCaption = _captionController.text.trim();
    if (_autoOptimizeInBackground && _optimization != null) {
      if (effectiveTitle.isEmpty) {
        effectiveTitle = _optimization!.suggestedTitle;
      }
      if (effectiveCaption.isEmpty) {
        effectiveCaption = _optimization!.suggestedDescription;
      }
    }

    _syncStateToDraft();

    final aspect = widget.isVideo &&
            _player?.state.width != null &&
            _player?.state.height != null &&
            _player!.state.height! > 0
        ? (_player!.state.width! / _player!.state.height!)
        : null;
    try {
      await ref.read(pendingPostQueueProvider.notifier).enqueue(
        mediaPath: widget.mediaPath,
        isVideo: widget.isVideo,
        coverPath: _customCoverPath,
        link: _advancedSettings.link,
        params: {
          'title': effectiveTitle.isEmpty ? null : effectiveTitle,
          'caption': effectiveCaption,
          'privacy': _advancedSettings.privacy,
          'allowComments': _advancedSettings.allowComments,
          'allowDuet': _advancedSettings.allowDuet,
          'allowStitch': _advancedSettings.allowStitch,
          'allowRemix': _advancedSettings.allowRemix,
          if (widget.remixOf != null) 'remixOf': widget.remixOf!.toJson(),
          'allowDownload': _advancedSettings.allowDownload,
          'highQualityUploads': _highQualityUploads,
          'uploadQualityTier': _uploadQualityTier,
          'autoOptimizeInBackground': _autoOptimizeInBackground,
          if (_selectedConnectedChannel != null)
            'selectedConnectedChannel': _selectedConnectedChannel,
          'location': _advancedSettings.location,
          'geoRadiusTier': _advancedSettings.geoRadiusTier,
          'coverTimeMs': _coverTimeMs,
          'ageRestriction': _advancedSettings.ageRestriction,
          'isAiGenerated': _advancedSettings.isAiGenerated,
          'isBrandedContent': _advancedSettings.isBrandedContent,
          'destinations': _selectedPlatforms.map((d) => d.name).toList(),
          'collaborators': _collaborators,
          'taggedUserIds': _taggedUsers,
          'isFastTrendBoosted': _fastTrendAccelerator,
          'durationMs': widget.isVideo ? _player?.state.duration.inMilliseconds : null,
          'aspectRatio': aspect,
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPosting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.brandPink,
        content: Text(
          e is StateError ? e.message : 'Couldn\'t save the post on this phone: $e',
        ),
      ));
      return;
    }

    if (!mounted) return;
    setState(() => _isPosting = false);
    unawaited(ref.read(postDraftProvider.notifier).discardCurrentDraft());
    context.go('/hub/home');
  }

  void _openCoverPicker() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return CoverPickerSheet(
          mediaPath: widget.mediaPath,
          isVideo: widget.isVideo,
          initialCoverTimeMs: _coverTimeMs,
          initialCustomImagePath: _customCoverPath,
          recommendedTimeMs: _optimization?.recommendedCoverTimeMs,
          onCoverSelected: (timeMs, customPath) {
            setState(() {
              _coverTimeMs = timeMs;
              _customCoverPath = customPath;
            });
            _syncStateToDraft();
          },
        );
      },
    );
  }

  void _openCollaboratorSheet() {
    HapticFeedback.lightImpact();
    final searchService = ref.read(postSearchServiceProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return CollaboratorSheet(
          initialCollaborators: _collaborators,
          initialTaggedUsers: _taggedUsers,
          searchService: searchService,
          onSave: (collabs, tagged) {
            setState(() {
              _collaborators = collabs;
              _taggedUsers = tagged;
            });
            _syncStateToDraft();
          },
        );
      },
    );
  }

  void _openAdvancedSettingsSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AdvancedSettingsSheet(
          initialSettings: _advancedSettings,
          onSave: (settings) {
            setState(() {
              _advancedSettings = settings;
            });
            _syncStateToDraft();
          },
        );
      },
    );
  }

  Future<bool> _onWillPop() async {
    final hasContent =
        _titleController.text.isNotEmpty || _captionController.text.isNotEmpty;
    if (!hasContent) return true;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        title: Text(
          'Save Reel Draft?',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: context.textPrimary,
          ),
        ),
        content: Text(
          'You have unsaved changes. Do you want to save this reel as a draft so you can resume later?',
          style: GoogleFonts.inter(fontSize: 13, color: context.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: Text(
              'Discard',
              style: GoogleFonts.inter(
                color: AppColors.brandPink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'keep'),
            child: Text(
              'Keep Editing',
              style: GoogleFonts.inter(color: context.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            child: Text(
              'Save Draft',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );

    if (action == 'save') {
      await ref.read(postDraftProvider.notifier).saveImmediately();
      return true;
    } else if (action == 'discard') {
      await ref.read(postDraftProvider.notifier).discardCurrentDraft();
      return true;
    }
    return false;
  }

  // ── Build ───────────────────────────────────────────────────────────────

  Widget _remixBanner(RemixSource r) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.brandPink.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: AppColors.brandPink, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Remix of ${r.authorName.isEmpty ? 'another creator' : '@${r.authorName}'}. They are credited on your post '
                'and get ${(kRemixOriginalShare * 100).round()}% of the gift coins it earns.',
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final searchService = ref.watch(postSearchServiceProvider);
    final draftState = ref.watch(postDraftProvider);
    final router = GoRouter.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          if (router.canPop()) {
            router.pop();
          } else {
            router.go('/hub/home');
          }
        }
      },
      child: Scaffold(
        backgroundColor: context.bg,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              HapticFeedback.lightImpact();
              final shouldPop = await _onWillPop();
              if (shouldPop && mounted) {
                if (router.canPop()) {
                  router.pop();
                } else {
                  router.go('/hub/home');
                }
              }
            },
          ),
          backgroundColor: context.bg,
          title: Text(
            widget.isVideo ? 'Publish Reel' : 'Publish Photo',
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          iconTheme: IconThemeData(color: context.textPrimary),
          centerTitle: true,
          elevation: 0,
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: DraftStatusPill(
                  draftState: draftState,
                  onTap: _manualSaveDraft,
                ),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.remixOf != null) _remixBanner(widget.remixOf!),

              // 1. Top Composer Row: Title + Caption Editor + Cover Preview
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CaptionEditor(
                      titleController: _titleController,
                      captionController: _captionController,
                      searchService: searchService,
                      onChanged: _syncStateToDraft,
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _openCoverPicker,
                    child: Column(
                      children: [
                        Container(
                          width: 84,
                          height: 128,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            color: context.surfaceMid,
                            border: Border.all(color: AppColors.brandBlue, width: 1.0),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (_customCoverPath != null)
                                Image.file(File(_customCoverPath!), fit: BoxFit.cover)
                              else if (_videoController != null)
                                Video(
                                  controller: _videoController!,
                                  fit: BoxFit.cover,
                                  controls: NoVideoControls,
                                )
                              else
                                Image.file(File(widget.mediaPath), fit: BoxFit.cover),
                              Positioned(
                                bottom: 6,
                                left: 4,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.72),
                                    borderRadius: BorderRadius.circular(AppRadius.xs),
                                  ),
                                  alignment: Alignment.center,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.crop, size: 10, color: Colors.white),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Cover',
                                        style: GoogleFonts.inter(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Edit Cover',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brandBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 2. Background AI Channel & Video Optimizer
              AISuggestionCard(
                optimization: _optimization,
                isAnalyzing: _isAnalyzing,
                autoOptimizeInBackground: _autoOptimizeInBackground,
                onToggleAutoOptimize: (val) {
                  setState(() => _autoOptimizeInBackground = val);
                },
                onReanalyze: _runAiOptimization,
                onApplyTitle: (title) {
                  setState(() => _titleController.text = title);
                  _syncStateToDraft();
                },
                onApplyDescription: (description) {
                  setState(() => _captionController.text = description);
                  _syncStateToDraft();
                },
                onApplyHashtags: (hashtags) {
                  setState(() {
                    final current = _captionController.text.trim();
                    final tagStr = hashtags.join(' ');
                    _captionController.text =
                        current.isEmpty ? tagStr : '$current $tagStr';
                  });
                  _syncStateToDraft();
                },
                onApplyAll: () {
                  final opt = _optimization;
                  if (opt == null) return;
                  setState(() {
                    _titleController.text = opt.suggestedTitle;
                    final hasTags = opt.suggestedDescription.contains('#');
                    _captionController.text = hasTags
                        ? opt.suggestedDescription
                        : '${opt.suggestedDescription}\n\n${opt.suggestedHashtags.join(' ')}';
                  });
                  _syncStateToDraft();
                },
              ),
              const SizedBox(height: 10),

              // 3. High-Quality Upload Options Card
              _buildUploadQualityCard(),
              const SizedBox(height: 10),

              // 4. Select One Connected Channel Card (Auto-Optimize & Auto-Post)
              _buildSingleConnectedChannelCard(),
              const SizedBox(height: 10),

              // 5. Clean Compact Settings Group
              _buildOptionsGroup(),

              const SizedBox(height: 32),
            ],
          ),
        ),

        // Bottom Navigation Bar with Action Buttons
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: context.surface,
              border: Border(top: BorderSide(color: context.border, width: 0.8)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: _saveToDevice,
                  tooltip: 'Save to Device Gallery',
                  icon: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: context.surfaceMid,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: context.border, width: 1.0),
                    ),
                    child: Icon(
                      Icons.download_rounded,
                      color: context.textPrimary,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton(
                      onPressed: _manualSaveDraft,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: context.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      child: Text(
                        'Draft',
                        style: GoogleFonts.inter(
                          color: context.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 40,
                    child: ElevatedButton(
                      onPressed: _isPosting ? null : _onPost,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      child: _isPosting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.rocket_launch_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _selectedConnectedChannel != null
                                        ? 'Post & Auto-Publish'
                                        : (widget.isVideo ? 'Post Reel' : 'Post Photo'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 3. Upload Quality Selector Card ──────────────────────────────────────

  Widget _buildUploadQualityCard() {
    const tiers = <({String id, String label, String sub, IconData icon})>[
      (
        id: '1080p_hd',
        label: '1080p HD',
        sub: 'Fast · Crisp',
        icon: Icons.hd_outlined,
      ),
      (
        id: '2k_60fps',
        label: '2K 60fps',
        sub: 'Smooth · HDR',
        icon: Icons.speed_rounded,
      ),
      (
        id: '4k_master',
        label: '4K Master',
        sub: 'Ultra HD Studio',
        icon: Icons.four_k_outlined,
      ),
      (
        id: 'original_raw',
        label: 'Original Raw',
        sub: 'Lossless Source',
        icon: Icons.high_quality_rounded,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.high_quality_rounded,
                    size: 15,
                    color: AppColors.brandBlue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'UPLOAD QUALITY',
                    style: GoogleFonts.inter(
                      color: context.textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                    ),
                  ),
                ],
              ),
              Text(
                _highQualityUploads ? 'Master Lossless Active' : 'Standard HD',
                style: GoogleFonts.inter(
                  color: AppColors.brandBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (int i = 0; i < tiers.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _buildQualityTierPill(tiers[i]),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQualityTierPill(
    ({String id, String label, String sub, IconData icon}) tier,
  ) {
    final isSelected = _uploadQualityTier == tier.id;
    return Material(
      color: isSelected
          ? AppColors.brandBlue
          : context.surfaceMid,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            _uploadQualityTier = tier.id;
            _highQualityUploads = tier.id != '1080p_hd';
          });
          _syncStateToDraft();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: isSelected ? AppColors.brandBlue : context.border,
              width: 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                tier.icon,
                size: 16,
                color: isSelected ? Colors.white : context.textPrimary,
              ),
              const SizedBox(height: 3),
              Text(
                tier.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : context.textPrimary,
                ),
              ),
              Text(
                tier.sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.85)
                      : context.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 4. Select One Connected Channel Card ─────────────────────────────────

  Widget _buildSingleConnectedChannelCard() {
    final ytAccounts =
        ref.watch(ytAccountsStreamProvider).value ?? const <YtLinkedAccount>[];
    final linkedAccounts =
        (ref.watch(linkedAccountsProvider).value ?? const <LinkedAccount>[])
            .where((a) =>
                a.platform.publish &&
                a.platform != LinkedPlatform.youtube &&
                a.isUsable)
            .toList();

    final channelOptions = <Map<String, dynamic>>[];

    for (final acc in ytAccounts) {
      if (acc.channels.isEmpty) {
        channelOptions.add({
          'key': 'youtube:${acc.googleId}:default',
          'platform': 'youtube',
          'googleId': acc.googleId,
          'channelId': '',
          'title': acc.accountName.isNotEmpty ? acc.accountName : acc.email,
          'subtitle': 'YouTube Channel',
        });
      } else {
        for (final ch in acc.channels) {
          channelOptions.add({
            'key': 'youtube:${acc.googleId}:${ch.id}',
            'platform': 'youtube',
            'googleId': acc.googleId,
            'channelId': ch.id,
            'title': ch.title,
            'subtitle': 'YouTube · ${ch.subscriberCount} subs',
          });
        }
      }
    }

    for (final acc in linkedAccounts) {
      channelOptions.add({
        'key': '${acc.platform.id}:${acc.accountId}',
        'platform': acc.platform.id,
        'accountId': acc.accountId,
        'title': acc.accountName.isNotEmpty ? acc.accountName : acc.platform.label,
        'subtitle': acc.platform.label,
      });
    }

    final selectedKey = _selectedConnectedChannel?['key']?.toString();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.hub_rounded,
                    size: 15,
                    color: AppColors.brandPink,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'CONNECTED CHANNEL (SELECT ONE)',
                    style: GoogleFonts.inter(
                      color: context.textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () => context.push('/social_hub'),
                child: Text(
                  '+ Manage Channels',
                  style: GoogleFonts.inter(
                    color: AppColors.brandBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _selectedConnectedChannel != null
                ? 'AI will tailor metadata for ${_selectedConnectedChannel!['title']} and publish automatically in the background.'
                : 'Select one connected channel to auto-optimize and auto-post alongside Oneova Reels.',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: context.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Option 0: Oneova Only
              _buildChannelOptionChip(
                icon: Icons.flash_on_rounded,
                title: 'Oneova Only',
                subtitle: 'Primary Feed',
                isSelected: selectedKey == null,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedConnectedChannel = null);
                  _syncStateToDraft();
                },
              ),
              // Each connected channel (single-select)
              for (final ch in channelOptions)
                _buildChannelOptionChip(
                  icon: _iconForPlatform(ch['platform'] as String),
                  title: ch['title'] as String,
                  subtitle: ch['subtitle'] as String,
                  isSelected: selectedKey == ch['key'],
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (selectedKey == ch['key']) {
                        _selectedConnectedChannel = null;
                      } else {
                        _selectedConnectedChannel = ch;
                      }
                    });
                    if (ch['platform'] == 'youtube' &&
                        (ch['googleId'] as String?)?.isNotEmpty == true &&
                        (ch['channelId'] as String?)?.isNotEmpty == true) {
                      unawaited(
                        ref.read(ytAccountStoreProvider.notifier).setActiveChannel(
                              ch['googleId'] as String,
                              ch['channelId'] as String,
                            ),
                      );
                    }
                    _syncStateToDraft();
                    if (_autoOptimizeInBackground) {
                      unawaited(_runAiOptimization());
                    }
                  },
                ),
              if (channelOptions.isEmpty)
                _buildChannelOptionChip(
                  icon: Icons.add_link_rounded,
                  title: 'Connect a Channel',
                  subtitle: 'YouTube, TikTok, IG, FB',
                  isSelected: false,
                  onTap: () => context.push('/social_hub'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _iconForPlatform(String platform) => switch (platform) {
        'youtube' => Icons.smart_display_rounded,
        'tiktok' => Icons.music_note_rounded,
        'instagram' => Icons.camera_alt_rounded,
        'facebook' => Icons.facebook_rounded,
        _ => Icons.public_rounded,
      };

  Widget _buildChannelOptionChip({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected ? AppColors.brandBlue : context.surfaceMid,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: isSelected ? AppColors.brandBlue : context.border,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? Icons.radio_button_checked_rounded : icon,
                size: 15,
                color: isSelected ? Colors.white : context.textPrimary,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : context.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.85)
                            : context.textMuted,
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

  // ── 5. Clean Compact Settings Group ──────────────────────────────────────

  Widget _buildOptionsGroup() {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border),
      ),
      child: Column(
        children: [
          // 1. Quick Privacy / Visibility Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.public_rounded, color: AppColors.brandBlue, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Who can watch',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                ),
                for (final mode in const [
                  ('public', 'Public'),
                  ('followers', 'Followers'),
                  ('private', 'Only Me'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _advancedSettings =
                              _advancedSettings.copyWith(privacy: mode.$1);
                        });
                        _syncStateToDraft();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _advancedSettings.privacy == mode.$1
                              ? AppColors.brandBlue
                              : context.surfaceMid,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                          border: Border.all(
                            color: _advancedSettings.privacy == mode.$1
                                ? AppColors.brandBlue
                                : context.border,
                          ),
                        ),
                        child: Text(
                          mode.$2,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _advancedSettings.privacy == mode.$1
                                ? Colors.white
                                : context.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(color: context.border, height: 1),

          // 2. Collaborators & Tagging
          ListTile(
            dense: true,
            leading: const Icon(
              Icons.group_add_outlined,
              color: AppColors.brandBlue,
              size: 20,
            ),
            title: Text(
              _collaborators.isEmpty && _taggedUsers.isEmpty
                  ? 'Tag People & Co-Authors'
                  : 'Collaborators & Tags (${_collaborators.length + _taggedUsers.length})',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
            subtitle: Text(
              _collaborators.isNotEmpty
                  ? '${_collaborators.length} Co-authors • ${_taggedUsers.length} Tagged'
                  : 'Invite co-authors and tag featured creators',
              style: GoogleFonts.inter(fontSize: 11, color: context.textMuted),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: _openCollaboratorSheet,
          ),
          Divider(color: context.border, height: 1),

          // 3. Fast-Trend Boost Engine Toggle
          SwitchListTile(
            dense: true,
            secondary: const Icon(Icons.bolt, color: AppColors.brandPink, size: 20),
            title: Text(
              'Fast-Trend Accelerator',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
            subtitle: Text(
              'Early discovery boost for your niche audience',
              style: GoogleFonts.inter(fontSize: 11, color: context.textMuted),
            ),
            activeThumbColor: AppColors.brandPink,
            value: _fastTrendAccelerator,
            onChanged: (v) {
              HapticFeedback.lightImpact();
              setState(() => _fastTrendAccelerator = v);
              _syncStateToDraft();
            },
          ),
          Divider(color: context.border, height: 1),

          // 4. More Settings (Age restriction, Interactions, Geo, Link)
          ListTile(
            dense: true,
            leading: const Icon(
              Icons.tune_rounded,
              color: AppColors.brandPink,
              size: 20,
            ),
            title: Text(
              'More Options & Audience Controls',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
            subtitle: Text(
              'Comments, Remix, Age (${_advancedSettings.ageRestriction.toUpperCase()}), Location & Links',
              style: GoogleFonts.inter(fontSize: 11, color: context.textMuted),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: _openAdvancedSettingsSheet,
          ),
        ],
      ),
    );
  }
}
