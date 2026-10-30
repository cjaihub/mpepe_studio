// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/live/models/live_models.dart';
import '../../backend/live/services/live_service.dart';
import '../../backend/live/live_restream_service.dart';
import '../../backend/connections/linked_accounts.dart' show usableLinkedAccountsProvider;
import '../../shared/widgets/linked_destinations_picker.dart';
import '../../shared/theme/app_theme.dart';
import '../../backend/live/services/live_stage_media_controller.dart';
import '../../backend/live_studio/live_studio_flag.dart';
import '../../backend/live_studio/media/studio_media_api.dart';
import 'studio_v2/gaming/game_title_sheet.dart';
import 'classic/live_classic_host_view.dart';
import 'go_live/oneova_go_live_screen.dart';
import 'settings/live_advanced_settings_sheet.dart';
import 'widgets/oneova_live_creation_wizard.dart';
import 'widgets/oneova_live_media_desk_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BROADCASTER SETUP STATE
// ─────────────────────────────────────────────────────────────────────────────

class _BroadcastSetup {
  final String title;
  final String category;
  final String audienceMode;
  final String resolution;
  final int frameRate;
  final LiveStreamType type;
  final LiveStageScene stageScene;
  final LiveStageConfig stageConfig;
  final AIModeratorSettings aiModerator;

  const _BroadcastSetup({
    this.title = '',
    this.category = 'Entertainment',
    this.audienceMode = 'public',
    this.resolution = '1080p',
    this.frameRate = 60,
    this.type = LiveStreamType.singleHost,
    this.stageScene = LiveStageScene.minimalStudio,
    this.stageConfig = const LiveStageConfig(),
    this.aiModerator = const AIModeratorSettings(),
  });

  _BroadcastSetup copyWith({
    String? title,
    String? category,
    String? audienceMode,
    String? resolution,
    int? frameRate,
    LiveStreamType? type,
    LiveStageScene? stageScene,
    LiveStageConfig? stageConfig,
    AIModeratorSettings? aiModerator,
  }) =>
      _BroadcastSetup(
        title: title ?? this.title,
        category: category ?? this.category,
        audienceMode: audienceMode ?? this.audienceMode,
        resolution: resolution ?? this.resolution,
        frameRate: frameRate ?? this.frameRate,
        type: type ?? this.type,
        stageScene: stageScene ?? this.stageScene,
        stageConfig: stageConfig ?? this.stageConfig,
        aiModerator: aiModerator ?? this.aiModerator,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// LIVE BROADCASTER SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class LiveBroadcasterScreen extends ConsumerStatefulWidget {
  /// 'classic' (full-screen vertical live) or 'studio' (Live Studio walls).
  final String initialLayoutMode;

  const LiveBroadcasterScreen({super.key, this.initialLayoutMode = 'classic'});

  @override
  ConsumerState<LiveBroadcasterScreen> createState() =>
      _LiveBroadcasterScreenState();
}

class _LiveBroadcasterScreenState extends ConsumerState<LiveBroadcasterScreen>
    with TickerProviderStateMixin {
  // ── Camera ──────────────────────────────────────────────────────────────
  CameraController? _cameraCtrl;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIdx = 0;
  bool _cameraReady = false;

  // ── Live session ─────────────────────────────────────────────────────────
  LiveStream? _liveStream;
  _BroadcastSetup _setup = const _BroadcastSetup();
  final TextEditingController _commentCtrl = TextEditingController();

  // ── Control panel ────────────────────────────────────────────────────────
  int _activeTab = 0; // 0=Live 1=Audience 2=Interact 3=Tools 4=Settings
  bool _micEnabled = true;
  bool _beautyEnabled = false;
  CameraLensDirection _cameraDirection = CameraLensDirection.front;
  bool _showStudioDrawer = false;

  // ── Tabs ─────────────────────────────────────────────────────────────────
  final List<_TabItem> _tabs = const [
    _TabItem(Icons.radio_button_checked, 'Live'),
    _TabItem(Icons.people_outline, 'Audience'),
    _TabItem(Icons.touch_app_outlined, 'Interact'),
    _TabItem(Icons.key_outlined, 'Endpoints'),
    _TabItem(Icons.security_outlined, 'AI Moderator'),
  ];

  // ── Tool buttons ──────────────────────────────────────────────────────────
  final List<_ToolBtn> _toolBtns = const [
    _ToolBtn(Icons.flip_camera_android_outlined, 'Flip'),
    _ToolBtn(Icons.auto_awesome_outlined, 'Beauty'),
    _ToolBtn(Icons.tune_rounded, 'Media Desk'),
    _ToolBtn(Icons.filter_outlined, 'Filters'),
    _ToolBtn(Icons.star_outline, 'Effects'),
    _ToolBtn(Icons.mic_outlined, 'Mic'),
    _ToolBtn(Icons.share_outlined, 'Share'),
  ];

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    final oldCtrl = _cameraCtrl;
    _cameraCtrl = null;
    _cameraReady = false;
    oldCtrl?.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CAMERA INIT
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      final frontIdx = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.front);
      _selectedCameraIdx = frontIdx >= 0 ? frontIdx : 0;
      await _startCamera(_cameras[_selectedCameraIdx]);
    } catch (e) {
      debugPrint('[Broadcaster] Camera init error: $e');
    }
  }

  Future<void> _startCamera(CameraDescription cam) async {
    final oldCtrl = _cameraCtrl;
    _cameraCtrl = null;
    if (mounted) setState(() => _cameraReady = false);
    if (oldCtrl != null) {
      try {
        await oldCtrl.dispose();
      } catch (_) {}
    }

    final ctrl = CameraController(
      cam,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() {
        _cameraCtrl = ctrl;
        _cameraReady = true;
        _cameraDirection = cam.lensDirection;
      });
    } catch (e) {
      ctrl.dispose();
      debugPrint('[Broadcaster] Camera start error: $e');
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2) return;
    HapticFeedback.lightImpact();
    final nextIdx = (_selectedCameraIdx + 1) % _cameras.length;
    _selectedCameraIdx = nextIdx;
    await _startCamera(_cameras[_selectedCameraIdx]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LIVE ACTIONS & AI STAGE
  // ─────────────────────────────────────────────────────────────────────────

  /// Records the linked platforms this account picked to also go live on
  /// (Go LIVE → Platforms). Never blocks or fails the Oneova live itself.
  Future<void> _requestRestream(String streamId) async {
    try {
      final picked = ref.read(activeDestinationsProvider(DestinationPurpose.live));
      if (picked.isEmpty) return;
      final targets = ref.read(usableLinkedAccountsProvider).where((a) => picked.contains(a.platform.id));
      await ref.read(liveRestreamServiceProvider).request(streamId, targets);
    } catch (e) {
      debugPrint('[LiveBroadcaster] restream request failed: $e');
    }
  }

  Future<void> _startBroadcastFromConfig(OneovaLiveCreationConfig config) async {
    final title = config.title.trim().isNotEmpty
        ? config.title.trim()
        : 'Oneova Live Stage';
    HapticFeedback.mediumImpact();

    try {
      final isMultiHost = config.hostingMode.toLowerCase().contains('multi');
      final streamType =
          isMultiHost ? LiveStreamType.multiGuest : LiveStreamType.singleHost;

      LiveInputSourceMode inputSourceMode = LiveInputSourceMode.cameraOnly;
      if (config.inputSource.toLowerCase().contains('screen')) {
        inputSourceMode = LiveInputSourceMode.screenShareWithCameraPip;
      } else if (config.inputSource.toLowerCase().contains('multi')) {
        inputSourceMode = LiveInputSourceMode.multiInputHybrid;
      }

      final beautyConfig = LiveBeautyConfig(
        smoothSkinLevel: config.skinSmoothing,
        ringLightIntensity: config.studioLighting,
        backgroundBlurEnabled: config.aiBackgroundBlur,
        warmToneLevel: 0.35,
      );

      final mediaDeskConfig = LiveMediaDeskConfig(
        isMusicPlaying: config.bgMusicEnabled,
        musicVolume: config.bgMusicVolume,
        lowerThirdText: config.lowerThirdTicker.isNotEmpty
            ? config.lowerThirdTicker
            : null,
        backgroundMusicTitle:
            config.bgMusicEnabled ? 'Lo-Fi Chill Beats' : '',
      );

      final legalCompliance = LiveLegalCompliance(
        contentRating:
            config.contentRating.contains('18+') ? 'mature_18' : 'all_ages',
        hasCopyrightMusicConsent: config.copyrightFairUseDeclared,
        agreedToCommunityGuidelines: config.creatorConsentAgreed,
        consentedAt: DateTime.now(),
      );

      String res = '1080p';
      if (config.quality.contains('720p')) res = '720p';
      if (config.quality.contains('480p')) res = '480p';

      int fps = 60;
      if (config.quality.contains('30fps')) fps = 30;

      final stageScene = (config.atmospherePreset.contains('Galaxy') ||
              config.atmospherePreset.contains('Cosmic'))
          ? LiveStageScene.holographicStage
          : (config.atmospherePreset.contains('Loft') ||
                  config.atmospherePreset.contains('Acoustic')
              ? LiveStageScene.minimalStudio
              : LiveStageScene.eventHall);

      final stageConfig = await ref
          .read(liveServiceProvider)
          .generateAIStageConfig(config.atmospherePreset);

      final audienceMode = switch (config.audienceMode) {
        'Followers Only' => 'followers',
        'Private Room' => 'private',
        _ => 'public',
      };

      // Game Live runs on Live Studio v2 only.
      final gaming = config.layoutMode == 'gaming';
      final v2 = (config.layoutMode == 'studio' || gaming) &&
          await ref.read(liveStudioV2EnabledProvider.future);
      if (gaming && !v2) {
        _showSnack('Game Live is not available yet.');
        return;
      }

      // Live Studio v2 (flag live_studio_v2): server-authoritative start.
      if (v2) {
        String? gameTitle;
        if (gaming) {
          if (!mounted) return;
          gameTitle = await showGameTitleSheet(context);
          if (gameTitle == null) return; // dismissed: stay on the setup screen
        }
        final started = await ref
            .read(studioMediaApiProvider)
            .start(title, gaming: gaming, gameTitle: gameTitle);
        unawaited(_requestRestream(started.streamId));
        final preview = _cameraCtrl;
        _cameraCtrl = null;
        _cameraReady = false;
        await preview?.dispose();
        if (!mounted) return;
        context.pushReplacement('/live/studio2/${started.streamId}');
        return;
      }

      final stream = await ref.read(liveServiceProvider).startStream(
            title: title,
            type: streamType,
            stageScene: stageScene,
            stageConfig: stageConfig,
            aiModerator: _setup.aiModerator.copyWith(
              isAutoModerationEnabled: config.isAiModerationEnabled,
              autoFilterToxicComments: config.autoFilterToxicComments,
            ),
            inputSourceMode: inputSourceMode,
            beautyConfig: beautyConfig,
            mediaDeskConfig: mediaDeskConfig,
            legalCompliance: legalCompliance,
            allowGuestRequests: config.viewerJoinRequests,
            category: config.category,
            audienceMode: audienceMode,
            resolution: res,
            frameRate: fps,
            layoutMode: config.layoutMode,
          );

      unawaited(_requestRestream(stream.id));

      // Release the preview camera so WebRTC can open it for broadcasting.
      final preview = _cameraCtrl;
      _cameraCtrl = null;
      _cameraReady = false;
      await preview?.dispose();

      if (!mounted) return;
      if (config.layoutMode == 'studio') {
        context.pushReplacement('/live/studio/${stream.id}');
        return;
      }

      if (mounted) {
        setState(() {
          _liveStream = stream;
          _setup = _setup.copyWith(
            title: title,
            category: config.category,
            audienceMode: audienceMode,
            resolution: res,
            frameRate: fps,
            type: streamType,
            stageScene: stageScene,
            stageConfig: stageConfig,
          );
        });
      }
    } catch (e) {
      _showSnack('Failed to start live: $e');
    }
  }

  Future<void> _endLive() async {
    final confirmed = await _showEndConfirm();
    if (!confirmed) return;

    HapticFeedback.mediumImpact();
    if (_liveStream != null) {
      await ref.read(liveServiceProvider).endStream(_liveStream!.id);
    }
    if (mounted) context.pop();
  }

  Future<bool> _showEndConfirm() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: ctx.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('End Live?',
                style: GoogleFonts.inter(
                    color: ctx.textPrimary, fontWeight: FontWeight.w700)),
            content: Text(
                'Your live stream will end for all viewers.',
                style: GoogleFonts.inter(color: ctx.textSecondary)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style: GoogleFonts.inter(color: ctx.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandPink,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('End Live',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _liveStream == null) return;
    _commentCtrl.clear();
    await ref.read(liveServiceProvider).sendComment(_liveStream!.id, text);
  }

  Future<void> _updateResolution(String res) async {
    setState(() => _setup = _setup.copyWith(resolution: res));
    if (_liveStream != null) {
      await ref
          .read(liveServiceProvider)
          .updateStreamSettings(_liveStream!.id, resolution: res);
    }
  }

  Future<void> _updateFrameRate(int fps) async {
    setState(() => _setup = _setup.copyWith(frameRate: fps));
    if (_liveStream != null) {
      await ref
          .read(liveServiceProvider)
          .updateStreamSettings(_liveStream!.id, frameRate: fps);
    }
  }



  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13)),
        backgroundColor: context.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_liveStream == null) return _buildSetup();
    return _buildLiveView();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SETUP SCREEN
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSetup() {
    return OneovaGoLiveScreen(
      cameraController: _cameraReady ? _cameraCtrl : null,
      initialLayoutMode: widget.initialLayoutMode,
      onFlipCamera: _flipCamera,
      onGoLive: _startBroadcastFromConfig,
      onClose: () => context.pop(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LIVE VIEW (classic full-screen vertical)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildLiveView() {
    if (_liveStream == null) return const SizedBox.shrink();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endLive();
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: LiveClassicHostView(
              initial: _liveStream!,
              onEnd: _endLive,
              onOpenTools: () {
                HapticFeedback.selectionClick();
                setState(() => _showStudioDrawer = true);
              },
            ),
          ),
          if (_showStudioDrawer) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showStudioDrawer = false),
                child: ColoredBox(
                    color: AppColors.brandBlack.withValues(alpha: 0.3)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                type: MaterialType.transparency,
                child: _buildBottomSection(),
              ).animate().slideY(
                  begin: 0.25, end: 0, duration: 220.ms, curve: Curves.easeOut),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomSection() {
    return Container(
      decoration: BoxDecoration(
        color: context.surface.withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
            top: BorderSide(color: context.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          GestureDetector(
            onTap: () => setState(() => _showStudioDrawer = false),
            child: Container(
              width: 36,
              height: 12,
              alignment: Alignment.center,
              child: Container(
                width: 36,
                height: 3,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: context.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // Comment input + action row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: context.surfaceMid,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: context.border),
                    ),
                    child: TextField(
                      controller: _commentCtrl,
                      style: GoogleFonts.inter(
                          color: context.textPrimary, fontSize: 13),
                      onSubmitted: (_) => _sendComment(),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        hintText: 'Add a comment...',
                        hintStyle: GoogleFonts.inter(
                            color: AppColors.textMuted, fontSize: 12.5),
                        border: InputBorder.none,
                        prefixIcon: const Icon(Icons.chat_bubble_outline,
                            color: AppColors.textMuted, size: 16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Request to join pill
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.brandBlue.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add,
                            color: AppColors.brandBlue, size: 14),
                        const SizedBox(width: 4),
                        Text('Join',
                            style: GoogleFonts.inter(
                                color: AppColors.brandBlue,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _iconCircle(Icons.card_giftcard_outlined, () {}),
                const SizedBox(width: 8),
                _iconCircle(Icons.share_outlined, () {}),
              ],
            ),
          ),

          // ── TABS ──────────────────────────────────────────────────────
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _tabs.length,
              separatorBuilder: (context, index) => const SizedBox(width: 4),
              itemBuilder: (ctx, i) {
                final tab = _tabs[i];
                final active = _activeTab == i;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _activeTab = i);
                  },
                  child: AnimatedContainer(
                    duration: 160.ms,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.brandBlue
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: active
                          ? null
                          : Border.all(
                              color: context.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(tab.icon,
                            size: 15,
                            color: active
                                ? Colors.white
                                : context.textSecondary),
                        const SizedBox(width: 6),
                        Text(tab.label,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: active
                                  ? Colors.white
                                  : context.textSecondary,
                            )),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 6),

          // ── TAB CONTENT ───────────────────────────────────────────────
          if (_activeTab == 0) ...[
            // Standard Live tools
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _toolBtns.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final btn = _toolBtns[i];
                  final isActive = btn.label == 'Beauty' && _beautyEnabled;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      final media = _liveStream == null
                          ? null
                          : ref.read(
                              liveStageMediaProvider(_liveStream!.id).notifier);
                      if (btn.label == 'Flip') media?.switchCamera();
                      if (btn.label == 'Mic') {
                        media?.toggleMic();
                        setState(() => _micEnabled = !_micEnabled);
                      }
                      if (btn.label == 'Beauty') {
                        showLiveAdvancedSettingsSheet(context);
                      }
                      if (btn.label == 'Media Desk' && _liveStream != null) {
                        OneovaLiveMediaDeskSheet.show(
                          context,
                          streamId: _liveStream!.id,
                          hostHandle:
                              '@${_liveStream!.hostDisplayName.toLowerCase().replaceAll(' ', '')}',
                        );
                      }
                    },
                    child: AnimatedContainer(
                      duration: 150.ms,
                      width: 60,
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.brandBlue.withValues(alpha: 0.2)
                            : context.surfaceMid,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive
                              ? AppColors.brandBlue
                              : context.border,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(btn.icon,
                              color: isActive
                                  ? AppColors.brandBlue
                                  : context.textPrimary,
                              size: 22),
                          const SizedBox(height: 5),
                          Text(btn.label,
                              style: GoogleFonts.inter(
                                color: isActive
                                    ? AppColors.brandBlue
                                    : context.textSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              )),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 10),

            // Camera Mode / Resolution / Frame Rate row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(child: _buildCameraModeTile()),
                  const SizedBox(width: 8),
                  Expanded(child: _buildResolutionTile()),
                  const SizedBox(width: 8),
                  Expanded(child: _buildFrameRateTile()),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Audience Mode / Title / Category
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(child: _buildInfoTile(
                    Icons.visibility_outlined,
                    'Audience Mode',
                    _setup.audienceMode[0].toUpperCase() +
                        _setup.audienceMode.substring(1),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _buildInfoTile(
                    Icons.edit_outlined,
                    'Live Title',
                    _setup.title.isNotEmpty ? _setup.title : 'Tap to edit',
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _buildInfoTile(
                    Icons.category_outlined,
                    'Category',
                    _setup.category,
                  )),
                ],
              ),
            ),

            const SizedBox(height: 10),
          ] else if (_activeTab == 1) ...[
            _buildAudienceTab(),
          ] else if (_activeTab == 2) ...[
            _buildInteractTab(),
          ] else if (_activeTab == 3) ...[
            // 30-Day Stream Endpoints tab
            _buildEndpointsTab(),
          ] else if (_activeTab == 4) ...[
            // AI Moderator tab
            _buildAIModeratorTab(),
          ],

          // ── COMMENT INPUT + END LIVE (bottom strip) ───────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
                12, 4, 12, MediaQuery.paddingOf(context).bottom + 10),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: context.surfaceMid,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: context.border),
                    ),
                    child: TextField(
                      controller: _commentCtrl,
                      style: GoogleFonts.inter(
                          color: context.textPrimary, fontSize: 13),
                      onSubmitted: (_) => _sendComment(),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        hintText: 'Add a comment...',
                        hintStyle: GoogleFonts.inter(
                            color: AppColors.textMuted, fontSize: 12.5),
                        border: InputBorder.none,
                        prefixIcon: const Icon(Icons.chat_bubble_outline,
                            color: AppColors.textMuted, size: 16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _endLive,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.radio_button_checked,
                            color: Colors.white, size: 15),
                        const SizedBox(width: 6),
                        Text('End Live',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            )),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudienceTab() {
    if (_liveStream == null) return const SizedBox.shrink();
    final participantsAsync =
        ref.watch(liveParticipantsProvider(_liveStream!.id));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('AUDIENCE & CO-HOST REQUESTS',
                  style: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
              participantsAsync.when(
                data: (list) => Text('${list.length} in room',
                    style: GoogleFonts.inter(
                        color: AppColors.brandBlue,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
                loading: () => const SizedBox.shrink(),
                error: (err, stack) => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.border),
            ),
            child: participantsAsync.when(
              data: (list) {
                if (list.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('No audience join requests yet.',
                          style: GoogleFonts.inter(
                              color: AppColors.textMuted, fontSize: 12)),
                    ),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(10),
                  itemCount: list.length,
                  separatorBuilder: (context, index) =>
                      Divider(height: 12, color: context.border),
                  itemBuilder: (ctx, i) {
                    final p = list[i];
                    return Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor:
                              AppColors.brandBlue.withValues(alpha: 0.3),
                          backgroundImage: p.avatarUrl.isNotEmpty
                              ? NetworkImage(p.avatarUrl)
                              : null,
                          child: p.avatarUrl.isEmpty
                              ? Text(
                                  p.displayName.isNotEmpty
                                      ? p.displayName[0].toUpperCase()
                                      : '?',
                                  style: GoogleFonts.inter(
                                      color: Colors.white, fontSize: 10))
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.displayName,
                                  style: GoogleFonts.inter(
                                      color: context.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                              Text(
                                p.hasRequestedToJoin
                                    ? 'Requested with Camera'
                                    : (p.isCoHost ? 'Active Co-Host' : 'Audience'),
                                style: GoogleFonts.inter(
                                    color: p.hasRequestedToJoin
                                        ? AppColors.brandPink
                                        : AppColors.textMuted,
                                    fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                        if (p.hasRequestedToJoin)
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brandBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () async {
                              await ref
                                  .read(liveServiceProvider)
                                  .approveCoHost(_liveStream!.id, p.userId);
                              _showSnack('${p.displayName} brought to stage!');
                            },
                            child: const Text('Bring to Stage',
                                style: TextStyle(fontSize: 11)),
                          )
                        else if (p.isCoHost)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.brandBlue.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('On Stage',
                                style: GoogleFonts.inter(
                                    color: AppColors.brandBlue,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                          ),
                      ],
                    );
                  },
                );
              },
              loading: () => const Center(
                  child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                    color: AppColors.brandBlue, strokeWidth: 2),
              )),
              error: (err, stack) => Center(
                  child: Text('Error loading participants',
                      style: GoogleFonts.inter(
                          color: AppColors.textMuted, fontSize: 12))),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildInteractTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LIVE STAGE INTERACTIONS',
              style: GoogleFonts.inter(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _interactActionCard(
                  icon: Icons.poll_outlined,
                  title: 'Start Poll',
                  subtitle: 'Live voting',
                  color: AppColors.brandBlue,
                  onTap: () {
                    _showSnack('Audience poll launched');
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _interactActionCard(
                  icon: Icons.auto_awesome,
                  title: 'Spotlight',
                  subtitle: 'Feature Guest',
                  color: AppColors.brandPink,
                  onTap: () {
                    _showSnack('Guest spotlighted on stage');
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _interactActionCard(
                  icon: Icons.celebration_outlined,
                  title: 'Celebration',
                  subtitle: 'Love blast',
                  color: const Color(0xFF00D2FF),
                  onTap: () {
                    HapticFeedback.heavyImpact();
                    _showSnack('Celebration hearts broadcasted');
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _interactActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(title,
                style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
            Text(subtitle,
                style: GoogleFonts.inter(
                    color: AppColors.textMuted, fontSize: 9.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildEndpointsTab() {
    final endpoint = _liveStream?.endpoint;
    final serverUrl = endpoint?.serverUrl ?? 'rtmps://live.oneova.com/live';
    final streamKey = endpoint?.streamKey.isNotEmpty == true
        ? endpoint!.streamKey
        : 'ov_live_k928f0_${DateTime.now().millisecondsSinceEpoch}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('30-DAY PERSISTENT STREAM KEY',
                  style: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Active · 29d left',
                    style: GoogleFonts.inter(
                        color: AppColors.brandBlue,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ingestion Server URL',
                    style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 10)),
                Text(serverUrl,
                    style: GoogleFonts.inter(
                        color: context.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                Divider(height: 16, color: context.border),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Stream Key (RTMP/WebRTC)',
                              style: GoogleFonts.inter(
                                  color: AppColors.textMuted, fontSize: 10)),
                          Text(streamKey,
                              style: GoogleFonts.inter(
                                  color: context.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: AppColors.brandBlue, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: streamKey));
                        _showSnack('Stream key copied to clipboard');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildAIModeratorTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('OVA AI MODERATOR',
                  style: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
              Text('98% Positive Sentiment',
                  style: GoogleFonts.inter(
                      color: AppColors.brandPink,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield_outlined,
                        color: AppColors.brandBlue, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Auto-filter toxic comments & spam',
                          style: GoogleFonts.inter(
                              color: context.textPrimary, fontSize: 12)),
                    ),
                    const Icon(Icons.check_circle,
                        color: AppColors.brandBlue, size: 16),
                  ],
                ),
                Divider(height: 16, color: context.border),
                Row(
                  children: [
                    const Icon(Icons.push_pin_outlined,
                        color: AppColors.brandPink, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Auto-highlight VIP & audience questions',
                          style: GoogleFonts.inter(
                              color: context.textPrimary, fontSize: 12)),
                    ),
                    const Icon(Icons.check_circle,
                        color: AppColors.brandPink, size: 16),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCameraModeTile() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.camera_outlined,
                color: AppColors.textMuted, size: 13),
            const SizedBox(width: 5),
            Text('Camera Mode',
                style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          Row(
            children:
                [CameraLensDirection.front, CameraLensDirection.back].map((d) {
              final label = d == CameraLensDirection.front ? 'Front' : 'Back';
              final active = _cameraDirection == d;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _flipCamera(),
                  child: Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.brandBlue
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(label,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color:
                              active ? Colors.white : context.textSecondary,
                        )),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildResolutionTile() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.hd_outlined,
                color: AppColors.textMuted, size: 13),
            const SizedBox(width: 5),
            Text('Resolution',
                style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          Row(
            children: ['480p', '720p', '1080p'].map((r) {
              final active = _setup.resolution == r;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _updateResolution(r),
                  child: Container(
                    margin: const EdgeInsets.only(right: 3),
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.brandBlue
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(r,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color:
                              active ? Colors.white : context.textSecondary,
                        )),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFrameRateTile() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.timer_outlined,
                color: AppColors.textMuted, size: 13),
            const SizedBox(width: 5),
            Text('Frame Rate',
                style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          Row(
            children: [30, 60].map((fps) {
              final active = _setup.frameRate == fps;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _updateFrameRate(fps),
                  child: Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.brandBlue
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('$fps',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color:
                              active ? Colors.white : context.textSecondary,
                        )),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(icon, color: AppColors.textMuted, size: 11),
            const SizedBox(width: 4),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.textMuted, size: 13),
          ]),
          const SizedBox(height: 4),
          Text(value,
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _iconCircle(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.border),
        ),
        child: Icon(icon, color: context.textPrimary, size: 17),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS (local only)
// ─────────────────────────────────────────────────────────────────────────────

class _TabItem {
  final IconData icon;
  final String label;
  const _TabItem(this.icon, this.label);
}

class _ToolBtn {
  final IconData icon;
  final String label;
  const _ToolBtn(this.icon, this.label);
}
