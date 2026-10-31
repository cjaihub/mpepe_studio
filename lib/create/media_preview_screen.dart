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
import '../services/upload_service.dart';
import '../backend/publishing/models/publishing_destination.dart';
import '../backend/connections/linked_accounts.dart' show LinkedPlatform;
import '../shared/widgets/linked_destinations_picker.dart';
import 'post/providers/post_draft_provider.dart';
import 'post/services/post_search_service.dart';
import 'post/services/openrouter_post_optimizer.dart';
import 'post/widgets/caption_editor.dart';
import 'post/widgets/ai_suggestion_card.dart';
import 'post/widgets/cover_picker_sheet.dart';
import 'post/widgets/collaborator_sheet.dart';
import 'post/widgets/advanced_settings_sheet.dart';
import 'post/widgets/draft_status_pill.dart';
import 'studio/widgets/studio_progress_dialog.dart';

class MediaPreviewScreen extends ConsumerStatefulWidget {
  final String mediaPath;
  final bool isVideo;

  /// Cover frame picked in Studio (a JPEG next to the export) and its time.
  final String? initialCoverPath;
  final int initialCoverTimeMs;

  const MediaPreviewScreen({
    super.key,
    required this.mediaPath,
    required this.isVideo,
    this.initialCoverPath,
    this.initialCoverTimeMs = 0,
  });

  @override
  ConsumerState<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends ConsumerState<MediaPreviewScreen> {
  // Text controllers
  late final TextEditingController _titleController;
  late final TextEditingController _captionController;

  // Media Player
  Player? _player;
  VideoController? _videoController;

  // Cover settings
  int _coverTimeMs = 0;
  String? _customCoverPath;

  // Collaborators & Tagged creators
  List<String> _collaborators = [];
  List<String> _taggedUsers = [];

  // Advanced settings (Age, Privacy, Interactions, Disclosures, Geo)
  AdvancedPostSettings _advancedSettings = const AdvancedPostSettings();

  // Destinations: Oneova always, plus the linked platforms this account
  // picked for posting (user_settings/{uid}.publishing.crossPostPlatforms).
  Set<PlatformDestination> get _selectedPlatforms => {
        PlatformDestination.internal,
        for (final id in ref.read(activeDestinationsProvider(DestinationPurpose.post)))
          ?_destinationFor(LinkedPlatform.fromId(id)),
      };

  static PlatformDestination? _destinationFor(LinkedPlatform? p) => switch (p) {
        LinkedPlatform.youtube => PlatformDestination.youtube,
        LinkedPlatform.tiktok => PlatformDestination.tiktok,
        LinkedPlatform.instagram => PlatformDestination.instagram,
        LinkedPlatform.facebook => PlatformDestination.facebook,
        _ => null,
      };

  // High-Fidelity & Fast-Trend settings
  bool _highQualityUploads = true;
  bool _fastTrendAccelerator = true;

  // AI Optimizer State
  VideoOptimizationPackage? _optimization;
  bool _isAnalyzing = false;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _captionController = TextEditingController();
    _customCoverPath = widget.initialCoverPath;
    _coverTimeMs = widget.initialCoverTimeMs;

    if (widget.isVideo) {
      _player = Player();
      _videoController = VideoController(_player!);
      _player!.open(Media(widget.mediaPath));
      _player!.setVolume(100.0);
      _player!.setPlaylistMode(PlaylistMode.loop);
    }

    // Initialize or restore draft from repository
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initDraftAndAi();
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
    _runAiOptimization();
  }

  Future<void> _runAiOptimization() async {
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

      final result = await optimizer.analyzeAndOptimize(
        mediaPath: widget.mediaPath,
        isVideo: widget.isVideo,
        currentCaption: _captionController.text.trim(),
        durationMs: durationMs,
        aspectRatio: aspect,
        destinations: _selectedPlatforms.toList(),
      );

      if (mounted) {
        setState(() {
          _optimization = result;
          _isAnalyzing = false;
          // If no custom cover or scrubbed timestamp is set yet, recommend AI frame
          if (_coverTimeMs == 0 && _customCoverPath == null && result.recommendedCoverTimeMs > 0) {
            _coverTimeMs = result.recommendedCoverTimeMs;
          }
        });
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
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
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
    _syncStateToDraft();

    // Stays on this screen until the upload lands: progress, then either
    // home with the post live, or the error with Retry (nothing is lost).
    final contentId = await runStudioTask<String>(
      context,
      title: widget.isVideo ? 'Posting reel' : 'Posting photo',
      describeError: (e) => e is FirebaseException
          ? 'Upload failed (${e.code}). Check your connection and try again.'
          : (e is StateError ? e.message : 'Upload failed: $e'),
      task: (onProgress) => UploadService.uploadPostInBackground(
        mediaPath: widget.mediaPath,
        isVideo: widget.isVideo,
        title: _titleController.text.trim().isEmpty ? null : _titleController.text.trim(),
        caption: _captionController.text.trim(),
        privacy: _advancedSettings.privacy,
        allowComments: _advancedSettings.allowComments,
        allowDuet: _advancedSettings.allowDuet,
        allowStitch: _advancedSettings.allowStitch,
        allowDownload: _advancedSettings.allowDownload,
        highQualityUploads: _highQualityUploads,
        location: _advancedSettings.location,
        link: _advancedSettings.link,
        geoRadiusTier: _advancedSettings.geoRadiusTier,
        coverTimeMs: _coverTimeMs,
        customCoverPath: _customCoverPath,
        ageRestriction: _advancedSettings.ageRestriction,
        isAiGenerated: _advancedSettings.isAiGenerated,
        isBrandedContent: _advancedSettings.isBrandedContent,
        destinations: _selectedPlatforms.toList(),
        collaborators: _collaborators,
        taggedUserIds: _taggedUsers,
        isFastTrendBoosted: _fastTrendAccelerator,
        durationMs: widget.isVideo ? _player?.state.duration.inMilliseconds : null,
        aspectRatio: widget.isVideo &&
                _player?.state.width != null &&
                _player?.state.height != null &&
                _player!.state.height! > 0
            ? (_player!.state.width! / _player!.state.height!)
            : null,
        onProgress: onProgress,
      ),
    );

    if (!mounted) return;
    setState(() => _isPosting = false);
    if (contentId == null) return;

    unawaited(ref.read(postDraftProvider.notifier).discardCurrentDraft());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.brandBlue,
        behavior: SnackBarBehavior.floating,
        content: Text(widget.isVideo ? 'Your reel is live on Oneova' : 'Your photo is live on Oneova'),
      ),
    );
    context.go('/hub/home?v=$contentId');
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
    final hasContent = _titleController.text.isNotEmpty || _captionController.text.isNotEmpty;
    if (!hasContent) return true;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        title: Text(
          'Save Reel Draft?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: context.textPrimary),
        ),
        content: Text(
          'You have unsaved changes. Do you want to save this reel as a draft so you can resume later?',
          style: GoogleFonts.inter(fontSize: 13, color: context.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: Text('Discard', style: GoogleFonts.inter(color: AppColors.brandPink, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'keep'),
            child: Text('Keep Editing', style: GoogleFonts.inter(color: context.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            child: Text('Save Draft', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white)),
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

  @override
  Widget build(BuildContext context) {
    final searchService = ref.watch(postSearchServiceProvider);
    final draftState = ref.watch(postDraftProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: context.bg,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final shouldPop = await _onWillPop();
              if (shouldPop && mounted) context.pop();
            },
          ),
          backgroundColor: context.bg,
          title: Text(
            widget.isVideo ? 'Publish Reel' : 'Publish Photo',
            style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 17),
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
              // Top Row: Caption Editor + Cover Thumbnail Scrubber Preview
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Caption & Title Editor
                  Expanded(
                    child: CaptionEditor(
                      titleController: _titleController,
                      captionController: _captionController,
                      searchService: searchService,
                      onChanged: _syncStateToDraft,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Cover Thumbnail Preview & Selector
                  GestureDetector(
                    onTap: _openCoverPicker,
                    child: Column(
                      children: [
                        Container(
                          width: 86,
                          height: 132,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            color: context.surfaceMid,
                            border: Border.all(color: AppColors.brandBlue, width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.brandBlue.withValues(alpha: 0.18),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (_customCoverPath != null)
                                Image.file(File(_customCoverPath!), fit: BoxFit.cover)
                              else if (_videoController != null)
                                Video(controller: _videoController!, fit: BoxFit.cover, controls: NoVideoControls)
                              else
                                Image.file(File(widget.mediaPath), fit: BoxFit.cover),
                              Container(
                                color: Colors.black.withValues(alpha: 0.25),
                              ),
                              Positioned(
                                bottom: 6,
                                left: 4,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
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
              const SizedBox(height: 12),

              // AI Director Video Suggestion Card (Live Background Analysis)
              AISuggestionCard(
                optimization: _optimization,
                isAnalyzing: _isAnalyzing,
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
                    _captionController.text = current.isEmpty ? tagStr : '$current $tagStr';
                  });
                  _syncStateToDraft();
                },
              ),
              const SizedBox(height: 8),

              // Cross-Platform Multi-Channel Syndication
              _buildSyndicationBar(),
              const SizedBox(height: 12),

              // Interactive Options Section
              _buildOptionsGroup(),

              const SizedBox(height: 36),
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
                // 1. Save to Device Action
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
                    child: Icon(Icons.download_rounded, color: context.textPrimary, size: 20),
                  ),
                ),
                const SizedBox(width: 8),

                // 2. Draft Button
                Expanded(
                  flex: 1,
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton(
                      onPressed: _manualSaveDraft,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: context.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
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

                // 3. Post Reel Now Primary CTA
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton(
                      onPressed: _isPosting ? null : _onPost,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        elevation: 4,
                        shadowColor: AppColors.brandBlue.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                      ),
                      child: _isPosting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.rocket_launch, color: Colors.white, size: 17),
                                const SizedBox(width: 8),
                                Text(
                                  widget.isVideo ? 'Post Reel' : 'Post Photo',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
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

  Widget _buildSyndicationBar() {
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
              Text(
                'CROSS-PLATFORM SYNDICATION',
                style: GoogleFonts.inter(
                  color: context.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                '${ref.watch(activeDestinationsProvider(DestinationPurpose.post)).length + 1} Active',
                style: GoogleFonts.inter(
                  color: AppColors.brandBlue,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildPlatformChip(PlatformDestination.internal, 'Oneova Reels', Icons.flash_on, isMandatory: true),
          const SizedBox(height: 8),
          // Linked accounts only; the choice is saved for the account.
          const LinkedDestinationsPicker(purpose: DestinationPurpose.post),
        ],
      ),
    );
  }

  Widget _buildPlatformChip(
    PlatformDestination platform,
    String label,
    IconData icon, {
    bool isMandatory = false,
  }) {
    final isSelected = _selectedPlatforms.contains(platform);
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: FilterChip(
        avatar: Icon(
          icon,
          size: 15,
          color: isSelected ? Colors.white : context.textSecondary,
        ),
        label: Text(label),
        selected: isSelected,
        showCheckmark: false,
        selectedColor: isMandatory ? AppColors.brandBlue : AppColors.brandPink,
        backgroundColor: context.surfaceMid,
        labelStyle: GoogleFonts.inter(
          color: isSelected ? Colors.white : context.textPrimary,
          fontSize: 11.5,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: BorderSide(
            color: isSelected ? Colors.transparent : context.border,
            width: 1.0,
          ),
        ),
        onSelected: (_) {},
      ),
    );
  }

  Widget _buildOptionsGroup() {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border),
      ),
      child: Column(
        children: [
          // 1. Collaborators & Tagging
          ListTile(
            dense: true,
            leading: const Icon(Icons.group_add_outlined, color: AppColors.brandBlue, size: 22),
            title: Text(
              _collaborators.isEmpty && _taggedUsers.isEmpty
                  ? 'Tag People & Co-Authors'
                  : 'Collaborators & Tags (${_collaborators.length + _taggedUsers.length})',
              style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.textPrimary),
            ),
            subtitle: Text(
              _collaborators.isNotEmpty
                  ? '${_collaborators.length} Co-authors • ${_taggedUsers.length} Tagged'
                  : 'Invite co-authors and tag featured creators',
              style: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: _openCollaboratorSheet,
          ),
          Divider(color: context.border, height: 1),

          // 2. Advanced Settings (Age restriction, Privacy, Interactions, Geo)
          ListTile(
            dense: true,
            leading: const Icon(Icons.tune_rounded, color: AppColors.brandPink, size: 22),
            title: Text(
              'Advanced Settings & Privacy',
              style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.textPrimary),
            ),
            subtitle: Text(
              'Age: ${_advancedSettings.ageRestriction.toUpperCase()} • ${_advancedSettings.privacy.toUpperCase()} • ${_advancedSettings.geoRadiusTier}',
              style: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: _openAdvancedSettingsSheet,
          ),
          Divider(color: context.border, height: 1),

          // 3. Fast-Trend Boost Engine Toggle
          SwitchListTile(
            dense: true,
            secondary: const Icon(Icons.bolt, color: AppColors.brandPink, size: 22),
            title: Text(
              'Fast-Trend Accelerator (ONPA-Flow)',
              style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.textPrimary),
            ),
            subtitle: Text(
              'Gives your post an early boost so more people see it first',
              style: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted),
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

          // 4. High-Fidelity Master Lossless Toggle
          SwitchListTile(
            dense: true,
            secondary: const Icon(Icons.high_quality, color: AppColors.brandBlue, size: 22),
            title: Text(
              'Master Lossless Fidelity',
              style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.textPrimary),
            ),
            subtitle: Text(
              'Preserves full 1080p60 stream and raw studio color gamut',
              style: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted),
            ),
            activeThumbColor: AppColors.brandBlue,
            value: _highQualityUploads,
            onChanged: (v) {
              HapticFeedback.lightImpact();
              setState(() => _highQualityUploads = v);
              _syncStateToDraft();
            },
          ),
        ],
      ),
    );
  }
}
