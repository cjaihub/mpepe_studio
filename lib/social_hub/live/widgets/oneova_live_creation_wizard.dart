import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONFIGURATION MODEL
// ─────────────────────────────────────────────────────────────────────────────

/// Complete configuration data emitted by the Oneova Live Creation Wizard.
class OneovaLiveCreationConfig {
  final String title;
  final String category;
  final String audienceMode;
  final String hostingMode;
  final bool viewerJoinRequests;
  final String inputSource;
  final String quality;
  final double skinSmoothing;
  final double studioLighting;
  final bool aiBackgroundBlur;
  final bool virtualGreenScreen;
  final String atmospherePreset;
  final bool bgMusicEnabled;
  final double bgMusicVolume;
  final String lowerThirdTicker;
  final String contentRating;
  final bool copyrightFairUseDeclared;
  final bool creatorConsentAgreed;
  final String streamServerUrl;
  final String streamKey;
  final bool isStreamKeyPersistent;
  final DateTime? streamKeyExpiresAt;
  final bool apiKeyEnabled;
  final String apiKey;
  final bool isAiModerationEnabled;
  final bool autoFilterToxicComments;
  final bool autoHighlightMoments;
  final bool chatSentimentAnalysis;

  /// 'classic' (full-screen vertical live) or 'studio' (Live Studio walls).
  final String layoutMode;

  const OneovaLiveCreationConfig({
    this.title = '',
    this.category = 'Music',
    this.audienceMode = 'Public',
    this.hostingMode = 'Solo Broadcast',
    this.viewerJoinRequests = true,
    this.inputSource = 'Camera (Front/Back)',
    this.quality = '1080p 60fps',
    this.skinSmoothing = 0.45,
    this.studioLighting = 0.50,
    this.aiBackgroundBlur = false,
    this.virtualGreenScreen = false,
    this.atmospherePreset = 'Cyber-Cinema 7.1',
    this.bgMusicEnabled = false,
    this.bgMusicVolume = 0.50,
    this.lowerThirdTicker = '',
    this.contentRating = 'All Ages',
    this.copyrightFairUseDeclared = true,
    this.creatorConsentAgreed = false,
    this.streamServerUrl = 'rtmps://live.oneova.com/live',
    this.streamKey = 'oneova_live_sec_7fa94b83e201',
    this.isStreamKeyPersistent = true,
    this.streamKeyExpiresAt,
    this.apiKeyEnabled = false,
    this.apiKey = 'ova_api_live_8f3d10a97b2c',
    this.isAiModerationEnabled = true,
    this.autoFilterToxicComments = true,
    this.autoHighlightMoments = true,
    this.chatSentimentAnalysis = true,
    this.layoutMode = 'classic',
  });

  OneovaLiveCreationConfig copyWith({
    String? title,
    String? category,
    String? audienceMode,
    String? hostingMode,
    bool? viewerJoinRequests,
    String? inputSource,
    String? quality,
    double? skinSmoothing,
    double? studioLighting,
    bool? aiBackgroundBlur,
    bool? virtualGreenScreen,
    String? atmospherePreset,
    bool? bgMusicEnabled,
    double? bgMusicVolume,
    String? lowerThirdTicker,
    String? contentRating,
    bool? copyrightFairUseDeclared,
    bool? creatorConsentAgreed,
    String? streamServerUrl,
    String? streamKey,
    bool? isStreamKeyPersistent,
    DateTime? streamKeyExpiresAt,
    bool? apiKeyEnabled,
    String? apiKey,
    bool? isAiModerationEnabled,
    bool? autoFilterToxicComments,
    bool? autoHighlightMoments,
    bool? chatSentimentAnalysis,
    String? layoutMode,
  }) {
    return OneovaLiveCreationConfig(
      title: title ?? this.title,
      category: category ?? this.category,
      audienceMode: audienceMode ?? this.audienceMode,
      hostingMode: hostingMode ?? this.hostingMode,
      viewerJoinRequests: viewerJoinRequests ?? this.viewerJoinRequests,
      inputSource: inputSource ?? this.inputSource,
      quality: quality ?? this.quality,
      skinSmoothing: skinSmoothing ?? this.skinSmoothing,
      studioLighting: studioLighting ?? this.studioLighting,
      aiBackgroundBlur: aiBackgroundBlur ?? this.aiBackgroundBlur,
      virtualGreenScreen: virtualGreenScreen ?? this.virtualGreenScreen,
      atmospherePreset: atmospherePreset ?? this.atmospherePreset,
      bgMusicEnabled: bgMusicEnabled ?? this.bgMusicEnabled,
      bgMusicVolume: bgMusicVolume ?? this.bgMusicVolume,
      lowerThirdTicker: lowerThirdTicker ?? this.lowerThirdTicker,
      contentRating: contentRating ?? this.contentRating,
      copyrightFairUseDeclared:
          copyrightFairUseDeclared ?? this.copyrightFairUseDeclared,
      creatorConsentAgreed:
          creatorConsentAgreed ?? this.creatorConsentAgreed,
      streamServerUrl: streamServerUrl ?? this.streamServerUrl,
      streamKey: streamKey ?? this.streamKey,
      isStreamKeyPersistent:
          isStreamKeyPersistent ?? this.isStreamKeyPersistent,
      streamKeyExpiresAt: streamKeyExpiresAt ?? this.streamKeyExpiresAt,
      apiKeyEnabled: apiKeyEnabled ?? this.apiKeyEnabled,
      apiKey: apiKey ?? this.apiKey,
      isAiModerationEnabled:
          isAiModerationEnabled ?? this.isAiModerationEnabled,
      autoFilterToxicComments:
          autoFilterToxicComments ?? this.autoFilterToxicComments,
      autoHighlightMoments:
          autoHighlightMoments ?? this.autoHighlightMoments,
      chatSentimentAnalysis:
          chatSentimentAnalysis ?? this.chatSentimentAnalysis,
      layoutMode: layoutMode ?? this.layoutMode,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIZARD WIDGET
// ─────────────────────────────────────────────────────────────────────────────

/// High-density, page-after-page creation wizard for Oneova Live Stage / Room.
/// Maximum 3 primary controls per page, dual-mode theme tokens, executive styling.
class OneovaLiveCreationWizard extends StatefulWidget {
  final ValueChanged<OneovaLiveCreationConfig>? onStartBroadcast;
  final VoidCallback? onClose;
  final OneovaLiveCreationConfig? initialConfig;
  final CameraController? existingCameraController;

  const OneovaLiveCreationWizard({
    super.key,
    this.onStartBroadcast,
    this.onClose,
    this.initialConfig,
    this.existingCameraController,
  });

  /// Opens the creation wizard as a full-screen or modal sheet.
  static Future<OneovaLiveCreationConfig?> showModal(
    BuildContext context, {
    OneovaLiveCreationConfig? initialConfig,
    CameraController? existingCameraController,
    ValueChanged<OneovaLiveCreationConfig>? onStartBroadcast,
  }) {
    return showModalBottomSheet<OneovaLiveCreationConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.94,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: OneovaLiveCreationWizard(
            initialConfig: initialConfig,
            existingCameraController: existingCameraController,
            onStartBroadcast: (cfg) {
              Navigator.of(ctx).pop(cfg);
              onStartBroadcast?.call(cfg);
            },
            onClose: () => Navigator.of(ctx).pop(),
          ),
        ),
      ),
    );
  }

  @override
  State<OneovaLiveCreationWizard> createState() =>
      _OneovaLiveCreationWizardState();
}

class _OneovaLiveCreationWizardState extends State<OneovaLiveCreationWizard>
    with TickerProviderStateMixin {
  late final PageController _pageController;
  int _currentStep = 0;
  static const int _totalSteps = 5;

  // Form state
  late String _title;
  late String _category;
  late String _audienceMode;
  late String _hostingMode;
  late bool _viewerJoinRequests;
  late String _inputSource;
  late String _quality;
  late double _skinSmoothing;
  late double _studioLighting;
  late bool _aiBackgroundBlur;
  late bool _virtualGreenScreen;
  late String _atmospherePreset;
  late bool _bgMusicEnabled;
  late double _bgMusicVolume;
  late String _lowerThirdTicker;
  late String _contentRating;
  late bool _copyrightFairUseDeclared;
  late bool _creatorConsentAgreed;

  // Persistent 30-Day Stream Key & AI Moderation state
  late String _streamServerUrl;
  late String _streamKey;
  late bool _isStreamKeyPersistent;
  late DateTime _streamKeyExpiresAt;
  late bool _apiKeyEnabled;
  late String _apiKey;
  late bool _isAiModerationEnabled;
  late bool _autoFilterToxicComments;
  late bool _autoHighlightMoments;
  late bool _chatSentimentAnalysis;
  bool _obscureStreamKey = true;
  bool _obscureApiKey = true;

  // Controllers
  late final TextEditingController _titleController;
  late final TextEditingController _tickerController;
  late final TextEditingController _scenePromptController;
  bool _isGeneratingScene = false;

  // Camera Management
  CameraController? _internalCameraCtrl;
  bool _cameraInitialized = false;

  CameraController? get _activeCamera =>
      widget.existingCameraController ?? _internalCameraCtrl;

  @override
  void initState() {
    super.initState();
    final init = widget.initialConfig ?? const OneovaLiveCreationConfig();
    _title = init.title.isEmpty ? 'Late Night Jam' : init.title;
    _category = init.category;
    _audienceMode = init.audienceMode;
    _hostingMode = init.hostingMode;
    _viewerJoinRequests = init.viewerJoinRequests;
    _inputSource = init.inputSource;
    _quality = init.quality;
    _skinSmoothing = init.skinSmoothing;
    _studioLighting = init.studioLighting;
    _aiBackgroundBlur = init.aiBackgroundBlur;
    _virtualGreenScreen = init.virtualGreenScreen;
    _atmospherePreset = init.atmospherePreset;
    _bgMusicEnabled = init.bgMusicEnabled;
    _bgMusicVolume = init.bgMusicVolume;
    _lowerThirdTicker = init.lowerThirdTicker.isEmpty
        ? '🔥 Welcome to Oneova Live Stage · Ask questions in comments'
        : init.lowerThirdTicker;
    _contentRating = init.contentRating;
    _copyrightFairUseDeclared = init.copyrightFairUseDeclared;
    _creatorConsentAgreed = init.creatorConsentAgreed;

    _streamServerUrl = init.streamServerUrl;
    _streamKey = init.streamKey.isNotEmpty
        ? init.streamKey
        : 'oneova_live_sec_${math.Random().nextInt(0xFFFFFFF).toRadixString(16).padLeft(8, '0')}';
    _isStreamKeyPersistent = init.isStreamKeyPersistent;
    _streamKeyExpiresAt = init.streamKeyExpiresAt ??
        DateTime.now().add(const Duration(days: 30));
    _apiKeyEnabled = init.apiKeyEnabled;
    _apiKey = init.apiKey.isNotEmpty
        ? init.apiKey
        : 'ova_api_live_${math.Random().nextInt(0xFFFFFFF).toRadixString(16).padLeft(8, '0')}';
    _isAiModerationEnabled = init.isAiModerationEnabled;
    _autoFilterToxicComments = init.autoFilterToxicComments;
    _autoHighlightMoments = init.autoHighlightMoments;
    _chatSentimentAnalysis = init.chatSentimentAnalysis;

    _titleController = TextEditingController(text: _title);
    _tickerController = TextEditingController(text: _lowerThirdTicker);
    _scenePromptController = TextEditingController();

    _pageController = PageController();

    if (widget.existingCameraController == null) {
      _initCamera();
    } else {
      _cameraInitialized = widget.existingCameraController!.value.isInitialized;
    }
  }

  void _regenerateStreamKey() {
    HapticFeedback.mediumImpact();
    final newKey =
        'oneova_live_sec_${math.Random().nextInt(0xFFFFFFF).toRadixString(16).padLeft(8, '0')}${math.Random().nextInt(0xFFFFFFF).toRadixString(16).padLeft(8, '0')}';
    final newExpiry = DateTime.now().add(const Duration(days: 30));
    setState(() {
      _streamKey = newKey;
      _streamKeyExpiresAt = newExpiry;
      _isStreamKeyPersistent = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '30-Day Stream Key regenerated! Active until ${_streamKeyExpiresAt.month}/${_streamKeyExpiresAt.day}/${_streamKeyExpiresAt.year}',
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.brandBlue,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$label copied to clipboard!',
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.brandBlue,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final frontCam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        frontCam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() {
        _internalCameraCtrl = ctrl;
        _cameraInitialized = true;
      });
    } catch (e) {
      debugPrint('[OneovaLiveWizard] Camera init error (using studio fallback): $e');
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _titleController.dispose();
    _tickerController.dispose();
    _scenePromptController.dispose();
    final internalCtrl = _internalCameraCtrl;
    _internalCameraCtrl = null;
    _cameraInitialized = false;
    internalCtrl?.dispose();
    super.dispose();
  }

  Widget _buildSafeCameraPreview(CameraController? ctrl,
      {required Widget fallback}) {
    if (ctrl == null || !ctrl.value.isInitialized) {
      return fallback;
    }
    try {
      return ctrl.buildPreview();
    } catch (_) {
      return fallback;
    }
  }

  OneovaLiveCreationConfig _buildCurrentConfig() {
    return OneovaLiveCreationConfig(
      title: _title.trim().isEmpty ? 'Oneova Live Stage' : _title.trim(),
      category: _category,
      audienceMode: _audienceMode,
      hostingMode: _hostingMode,
      viewerJoinRequests: _viewerJoinRequests,
      inputSource: _inputSource,
      quality: _quality,
      skinSmoothing: _skinSmoothing,
      studioLighting: _studioLighting,
      aiBackgroundBlur: _aiBackgroundBlur,
      virtualGreenScreen: _virtualGreenScreen,
      atmospherePreset: _atmospherePreset,
      bgMusicEnabled: _bgMusicEnabled,
      bgMusicVolume: _bgMusicVolume,
      lowerThirdTicker: _lowerThirdTicker,
      contentRating: _contentRating,
      copyrightFairUseDeclared: _copyrightFairUseDeclared,
      creatorConsentAgreed: _creatorConsentAgreed,
      streamServerUrl: _streamServerUrl,
      streamKey: _streamKey,
      isStreamKeyPersistent: _isStreamKeyPersistent,
      streamKeyExpiresAt: _streamKeyExpiresAt,
      apiKeyEnabled: _apiKeyEnabled,
      apiKey: _apiKey,
      isAiModerationEnabled: _isAiModerationEnabled,
      autoFilterToxicComments: _autoFilterToxicComments,
      autoHighlightMoments: _autoHighlightMoments,
      chatSentimentAnalysis: _chatSentimentAnalysis,
    );
  }

  void _goToStep(int step) {
    if (step < 0 || step >= _totalSteps) return;
    HapticFeedback.lightImpact();
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
    );
  }

  void _onNext() {
    if (_currentStep < _totalSteps - 1) {
      _goToStep(_currentStep + 1);
    } else {
      _startBroadcast();
    }
  }

  void _onBack() {
    if (_currentStep > 0) {
      _goToStep(_currentStep - 1);
    } else {
      if (widget.onClose != null) {
        widget.onClose!();
      } else {
        Navigator.of(context).maybePop();
      }
    }
  }

  void _startBroadcast() {
    if (!_creatorConsentAgreed) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please accept the Creator Consent Agreement to broadcast on Oneova.',
            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.brandPink,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    final config = _buildCurrentConfig();
    widget.onStartBroadcast?.call(config);
  }

  void _showGuidelinesModal() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OneovaGuidelinesSheet(
        onAccept: () {
          setState(() => _creatorConsentAgreed = true);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = context.bg;
    final surface = context.surface;
    final border = context.border;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // Top Header: Back, Step / "Almost there!", Close
            _buildTopHeader(surface, border),

            // Animated step progress bar
            _buildStepProgressBar(),

            // Multi-step pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (idx) {
                  setState(() => _currentStep = idx);
                },
                children: [
                  _buildStep1Identity(),
                  _buildStep2HostingAndVideo(),
                  _buildStep3BeautyRetouch(),
                  _buildStep4MediaAtmosphere(),
                  _buildStep5RegulationsGoLive(),
                ],
              ),
            ),

            // Bottom action bar (Steps 1 to 4)
            if (_currentStep < _totalSteps - 1)
              _buildBottomActionBar(surface, border),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TOP HEADER & PROGRESS
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildTopHeader(Color surface, Color border) {
    final isLastStep = _currentStep == _totalSteps - 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        border: Border(bottom: BorderSide(color: border, width: 1.0)),
      ),
      child: Row(
        children: [
          // Back button
          InkWell(
            onTap: _onBack,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: border, width: 1.0),
              ),
              child: Icon(
                _currentStep == 0 ? Icons.close : Icons.arrow_back_ios_new,
                size: 16,
                color: context.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Title & progress text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Oneova Live Stage',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (isLastStep)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.brandPink.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppColors.brandPink.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome,
                                size: 10, color: AppColors.brandPink),
                            const SizedBox(width: 3),
                            Text(
                              'Almost there!',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brandPink,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                Text(
                  _getStepSubtitle(_currentStep),
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Step counter badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.brandBlue.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              '${_currentStep + 1} / $_totalSteps',
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.brandBlue,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Close button
          InkWell(
            onTap: () {
              if (widget.onClose != null) {
                widget.onClose!();
              } else {
                Navigator.of(context).maybePop();
              }
            },
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: border, width: 1.0),
              ),
              child: Icon(
                Icons.close,
                size: 16,
                color: context.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getStepSubtitle(int step) {
    switch (step) {
      case 0:
        return 'Step 1 of 5 · Broadcast Identity & Topic';
      case 1:
        return 'Step 2 of 5 · Hosting Mode & Video Input';
      case 2:
        return 'Step 3 of 5 · Studio Beauty & Retouch';
      case 3:
        return 'Step 4 of 5 · Media Desk & Atmosphere';
      case 4:
        return 'Step 5 of 5 · Compliance & Regulations';
      default:
        return '';
    }
  }

  Widget _buildStepProgressBar() {
    return Container(
      height: 3.5,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: context.surface,
      child: Row(
        children: List.generate(_totalSteps, (idx) {
          final isCompleted = idx <= _currentStep;
          final isCurrent = idx == _currentStep;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: idx == _totalSteps - 1 ? 0 : 4),
              height: 3.5,
              decoration: BoxDecoration(
                color: isCompleted
                    ? (isCurrent && idx == _totalSteps - 1
                        ? AppColors.brandPink
                        : AppColors.brandBlue)
                    : context.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // BOTTOM ACTION BAR
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildBottomActionBar(Color surface, Color border) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: border, width: 1.0)),
      ),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(80, 40),
                foregroundColor: context.textPrimary,
                side: BorderSide(color: border, width: 1.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: _onBack,
              child: Text(
                'Back',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: _onNext,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Next Step',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward, size: 15, color: Colors.white),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // STEP 1: BROADCAST IDENTITY & CATEGORY
  // Max 3 primary controls:
  // Control 1: Title input with 3 AI suggestion chips
  // Control 2: Category picker
  // Control 3: Audience mode
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildStep1Identity() {
    final aiSuggestions = [
      'Late Night Jam',
      'Tech & Live Code',
      'Creator Q&A',
    ];

    final categories = [
      {'name': 'Music', 'icon': Icons.music_note_outlined},
      {'name': 'Gaming', 'icon': Icons.sports_esports_outlined},
      {'name': 'Tech', 'icon': Icons.code_outlined},
      {'name': 'Entertainment', 'icon': Icons.movie_outlined},
      {'name': 'Biz', 'icon': Icons.business_center_outlined},
    ];

    final audienceModes = [
      {
        'title': 'Public',
        'desc': 'Discoverable worldwide across Oneova Live Hub',
        'icon': Icons.public,
      },
      {
        'title': 'Followers Only',
        'desc': 'Restricted strictly to your verified community',
        'icon': Icons.group_outlined,
      },
      {
        'title': 'Private Room',
        'desc': 'Passcode & private invite link · encrypted in transit',
        'icon': Icons.lock_outline,
      },
    ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Control 1: Title input with 3 AI suggestion chips
          _buildControlHeader(
            icon: Icons.edit_note,
            title: 'BROADCAST TITLE',
            badge: 'Control 1 of 3',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            onChanged: (val) => setState(() => _title = val),
            maxLength: 80,
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'What is your broadcast about?',
              hintStyle: GoogleFonts.inter(
                color: context.textMuted,
                fontSize: 12.5,
              ),
              filled: true,
              fillColor: context.surfaceMid,
              counterText: '${_title.length}/80',
              counterStyle: GoogleFonts.inter(
                color: context.textMuted,
                fontSize: 10.5,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: context.border, width: 1.0),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: context.border, width: 1.0),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide:
                    const BorderSide(color: AppColors.brandBlue, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // AI Suggestion Chips
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 13, color: AppColors.brandPink),
              const SizedBox(width: 4),
              Text(
                'AI Ideas:',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandPink,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: aiSuggestions.map((suggestion) {
                      final isSelected = _title == suggestion;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _title = suggestion;
                              _titleController.text = suggestion;
                            });
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.brandPink.withValues(alpha: 0.2)
                                  : context.surfaceMid,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.brandPink
                                    : context.border,
                                width: 1.0,
                              ),
                            ),
                            child: Text(
                              suggestion,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? AppColors.brandPink
                                    : context.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Control 2: Category picker
          _buildControlHeader(
            icon: Icons.category_outlined,
            title: 'BROADCAST CATEGORY',
            badge: 'Control 2 of 3',
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: categories.map((cat) {
                final name = cat['name'] as String;
                final icon = cat['icon'] as IconData;
                final isSelected = _category == name;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _category = name);
                    },
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.brandBlue
                            : context.surfaceMid,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.brandBlue
                              : context.border,
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            icon,
                            size: 15,
                            color: isSelected ? Colors.white : context.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            name,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : context.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 18),

          // Control 3: Audience mode
          _buildControlHeader(
            icon: Icons.visibility_outlined,
            title: 'AUDIENCE & PRIVACY MODE',
            badge: 'Control 3 of 3',
          ),
          const SizedBox(height: 8),
          Column(
            children: audienceModes.map((item) {
              final title = item['title'] as String;
              final desc = item['desc'] as String;
              final icon = item['icon'] as IconData;
              final isSelected = _audienceMode == title;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _audienceMode = title);
                  },
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.brandBlue.withValues(alpha: 0.08)
                          : context.surfaceMid,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.brandBlue
                            : context.border,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.brandBlue
                                : context.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: context.border),
                          ),
                          child: Icon(
                            icon,
                            size: 17,
                            color: isSelected ? Colors.white : context.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: context.textPrimary,
                                ),
                              ),
                              Text(
                                desc,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: isSelected
                              ? AppColors.brandBlue
                              : context.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // STEP 2: HOSTING MODE & VIDEO INPUT
  // Max 3 primary controls:
  // Control 1: Hosting Mode toggle: "Solo Broadcast" vs "Multi-Host Room" (with viewer join requests enabled)
  // Control 2: Input Source selector: "Camera (Front/Back)" vs "Screen Share Mode" vs "Multi-Input"
  // Control 3: Quality & Framerate chips (1080p 60fps, 720p 60fps, 480p 30fps)
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildStep2HostingAndVideo() {
    final inputSources = [
      {
        'title': 'Camera (Front/Back)',
        'sub': 'Studio HDR Camera',
        'icon': Icons.videocam_outlined,
      },
      {
        'title': 'Screen Share Mode',
        'sub': 'With floating circular PIP',
        'icon': Icons.screen_share_outlined,
      },
      {
        'title': 'Multi-Input',
        'sub': 'Dual feed / RTMP deck',
        'icon': Icons.dashboard_customize_outlined,
      },
    ];

    final qualities = [
      {'label': '1080p 60fps', 'note': 'Ultra HD · 6.0 Mbps'},
      {'label': '720p 60fps', 'note': 'Crisp HD · 3.5 Mbps'},
      {'label': '480p 30fps', 'note': 'Saver · 1.5 Mbps'},
    ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Control 1: Hosting Mode toggle
          _buildControlHeader(
            icon: Icons.person_pin_outlined,
            title: 'HOSTING ARCHITECTURE',
            badge: 'Control 1 of 3',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildHostModeCard(
                  title: 'Solo Broadcast',
                  subtitle: 'Single creator stage',
                  icon: Icons.person_outline,
                  isSelected: _hostingMode == 'Solo Broadcast',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _hostingMode = 'Solo Broadcast');
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildHostModeCard(
                  title: 'Multi-Host Room',
                  subtitle: 'Up to 4 co-hosts live',
                  icon: Icons.groups_outlined,
                  isSelected: _hostingMode == 'Multi-Host Room',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _hostingMode = 'Multi-Host Room');
                  },
                ),
              ),
            ],
          ),
          // Sub-switch for Viewer Join Requests when Multi-Host Room is active
          if (_hostingMode == 'Multi-Host Room') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: AppColors.brandBlue.withValues(alpha: 0.3),
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_add_alt_1_outlined,
                      size: 16, color: AppColors.brandBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Viewer Join Requests',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ),
                        ),
                        Text(
                          'Allow live viewers to request stage mic',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: _viewerJoinRequests,
                    activeTrackColor: AppColors.brandBlue,
                    activeThumbColor: Colors.white,
                    onChanged: (val) {
                      HapticFeedback.lightImpact();
                      setState(() => _viewerJoinRequests = val);
                    },
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 18),

          // Control 2: Input Source selector
          _buildControlHeader(
            icon: Icons.input_outlined,
            title: 'PRIMARY VIDEO SOURCE',
            badge: 'Control 2 of 3',
          ),
          const SizedBox(height: 8),
          Column(
            children: inputSources.map((src) {
              final title = src['title'] as String;
              final sub = src['sub'] as String;
              final icon = src['icon'] as IconData;
              final isSelected = _inputSource == title;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _inputSource = title);
                  },
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.brandBlue.withValues(alpha: 0.08)
                          : context.surfaceMid,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.brandBlue
                            : context.border,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.brandBlue
                                : context.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: context.border),
                          ),
                          child: Icon(
                            icon,
                            size: 17,
                            color: isSelected ? Colors.white : context.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: context.textPrimary,
                                ),
                              ),
                              Text(
                                sub,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (title == 'Screen Share Mode')
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.brandPink.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'PIP Active',
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brandPink,
                              ),
                            ),
                          ),
                        const SizedBox(width: 6),
                        Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: isSelected
                              ? AppColors.brandBlue
                              : context.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 18),

          // Control 3: Quality & Framerate chips
          _buildControlHeader(
            icon: Icons.hd_outlined,
            title: 'RESOLUTION & FRAMERATE',
            badge: 'Control 3 of 3',
          ),
          const SizedBox(height: 8),
          Row(
            children: qualities.map((q) {
              final label = q['label'] as String;
              final note = q['note'] as String;
              final isSelected = _quality == label;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _quality = label);
                    },
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.brandBlue
                            : context.surfaceMid,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.brandBlue
                              : context.border,
                          width: 1.0,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            label,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? Colors.white
                                  : context.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            note,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 18),

          // 30-Day Persistent RTMP/WebRTC Stream Key Card
          _buildPersistentStreamKeyCard(),

          const SizedBox(height: 14),

          // Ova AI Live Moderation Engine Card
          _buildAiModeratorCard(),
        ],
      ),
    );
  }

  Widget _buildPersistentStreamKeyCard() {
    final expiryFormatted =
        '${_streamKeyExpiresAt.year}-${_streamKeyExpiresAt.month.toString().padLeft(2, '0')}-${_streamKeyExpiresAt.day.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.brandBlue.withValues(alpha: 0.35),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with 30-day Active badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.vpn_key_rounded,
                  color: AppColors.brandBlue,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '30-DAY PERSISTENT STREAM KEYS',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      'Dedicated RTMP & WebRTC endpoint with auto-failover',
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '30-DAY ACTIVE',
                      style: GoogleFonts.inter(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Ingestion Server URL field
          Text(
            'RTMP / WEBRTC INGEST SERVER',
            style: GoogleFonts.inter(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _streamServerUrl,
                    style: GoogleFonts.firaCode(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: context.textPrimary,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _copyToClipboard(_streamServerUrl, 'Ingest Server URL'),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.copy_rounded,
                      size: 15,
                      color: context.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Stream Key Field
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'STREAM KEY (OBS / VMIX / HARDWARE)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: context.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Expires: $expiryFormatted',
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: context.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _obscureStreamKey
                        ? '••••••••••••••••••••••••'
                        : _streamKey,
                    style: GoogleFonts.firaCode(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _obscureStreamKey = !_obscureStreamKey);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _obscureStreamKey
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 15,
                      color: context.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => _copyToClipboard(_streamKey, 'Stream Key'),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.copy_rounded,
                      size: 15,
                      color: context.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Stream Key Regeneration Button
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              InkWell(
                onTap: _regenerateStreamKey,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.refresh_rounded, size: 13, color: AppColors.brandBlue),
                      const SizedBox(width: 4),
                      Text(
                        'Regenerate Key (Reset 30 Days)',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const Divider(height: 16),

          // Developer API Key Toggle
          Row(
            children: [
              const Icon(Icons.terminal_rounded, size: 16, color: AppColors.brandPink),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Developer API Key & WebRTC Bot Access',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      'Enable custom automation, multi-cam ingest & bot listeners',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _apiKeyEnabled,
                activeTrackColor: AppColors.brandPink,
                activeThumbColor: Colors.white,
                onChanged: (val) {
                  HapticFeedback.lightImpact();
                  setState(() => _apiKeyEnabled = val);
                },
              ),
            ],
          ),

          // API Key Display if enabled
          if (_apiKeyEnabled) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: AppColors.brandPink.withValues(alpha: 0.35),
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _obscureApiKey ? 'ova_api_••••••••••••••••' : _apiKey,
                      style: GoogleFonts.firaCode(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _obscureApiKey = !_obscureApiKey);
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        _obscureApiKey
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 14,
                        color: context.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => _copyToClipboard(_apiKey, 'Developer API Key'),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.copy_rounded,
                        size: 14,
                        color: context.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAiModeratorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: _isAiModerationEnabled
              ? AppColors.brandPink.withValues(alpha: 0.4)
              : context.border,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.brandPink.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: AppColors.brandPink,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OVA AI LIVE MODERATION SENTINEL',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      'On-device AI safety shield, hype detector & sentiment gauge',
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _isAiModerationEnabled,
                activeTrackColor: AppColors.brandPink,
                activeThumbColor: Colors.white,
                onChanged: (val) {
                  HapticFeedback.lightImpact();
                  setState(() => _isAiModerationEnabled = val);
                },
              ),
            ],
          ),

          if (_isAiModerationEnabled) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Feature 1: Toxicity & Harassment Filter
            _buildAiModOption(
              icon: Icons.filter_alt_outlined,
              title: 'Auto-Filter Toxic Comments',
              subtitle: 'Quarantines harassment, profanity & spam in under 100ms',
              value: _autoFilterToxicComments,
              onChanged: (val) {
                HapticFeedback.lightImpact();
                setState(() => _autoFilterToxicComments = val);
              },
            ),

            const SizedBox(height: 8),

            // Feature 2: Auto-Highlight Viral Moments
            _buildAiModOption(
              icon: Icons.auto_awesome_motion_outlined,
              title: 'Auto-Highlight Viral Moments',
              subtitle: 'Detects chat hypes, crowd reactions & audio peaks for instant clips',
              value: _autoHighlightMoments,
              onChanged: (val) {
                HapticFeedback.lightImpact();
                setState(() => _autoHighlightMoments = val);
              },
            ),

            const SizedBox(height: 8),

            // Feature 3: Chat Sentiment Analysis
            _buildAiModOption(
              icon: Icons.insights_outlined,
              title: 'Chat Sentiment Analysis',
              subtitle: 'Real-time viewer sentiment score & mood temperature meter',
              value: _chatSentimentAnalysis,
              onChanged: (val) {
                HapticFeedback.lightImpact();
                setState(() => _chatSentimentAnalysis = val);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAiModOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.brandBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: AppColors.brandBlue,
            activeThumbColor: Colors.white,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildHostModeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandBlue.withValues(alpha: 0.08)
              : context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isSelected ? AppColors.brandBlue : context.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? AppColors.brandBlue : context.textPrimary,
                ),
                const Spacer(),
                Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: isSelected ? AppColors.brandBlue : context.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                color: context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // STEP 3: STUDIO BEAUTY & RETOUCH FILTERS
  // Max 3 primary controls:
  // Control 1: Skin Smoothing slider with real-time percentage badge
  // Control 2: Studio Ring Light & Warm Glow slider
  // Control 3: AI Background Blur / Virtual Green Screen toggle
  // Includes a compact live camera preview frame showing filter effects applied!
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildStep3BeautyRetouch() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Compact live camera preview frame with filter effects applied!
          _buildCompactLivePreview(),

          const SizedBox(height: 16),

          // Control 1: Skin Smoothing slider with real-time percentage badge
          _buildControlHeader(
            icon: Icons.face_retouching_natural,
            title: 'SKIN SMOOTHING & RETOUCH',
            badge: 'Control 1 of 3',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.brandPink.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.brandPink.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                '${(_skinSmoothing * 100).toInt()}%',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandPink,
                ),
              ),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.brandPink,
              inactiveTrackColor: context.border,
              thumbColor: AppColors.brandPink,
              trackHeight: 3.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: _skinSmoothing,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: (val) {
                setState(() => _skinSmoothing = val);
              },
            ),
          ),

          const SizedBox(height: 12),

          // Control 2: Studio Ring Light & Warm Glow slider
          _buildControlHeader(
            icon: Icons.wb_sunny_outlined,
            title: 'STUDIO RING LIGHT & WARM GLOW',
            badge: 'Control 2 of 3',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                '${(_studioLighting * 100).toInt()}%',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFFF9800),
                ),
              ),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFFF9800),
              inactiveTrackColor: context.border,
              thumbColor: const Color(0xFFFF9800),
              trackHeight: 3.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: _studioLighting,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: (val) {
                setState(() => _studioLighting = val);
              },
            ),
          ),

          const SizedBox(height: 12),

          // Control 3: AI Background Blur / Virtual Green Screen toggle
          _buildControlHeader(
            icon: Icons.auto_fix_high_outlined,
            title: 'AI BACKGROUND & GREEN SCREEN',
            badge: 'Control 3 of 3',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildFilterModeCard(
                  title: 'Default Stage',
                  subtitle: 'Natural feed',
                  icon: Icons.panorama_fish_eye,
                  isSelected: !_aiBackgroundBlur && !_virtualGreenScreen,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _aiBackgroundBlur = false;
                      _virtualGreenScreen = false;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildFilterModeCard(
                  title: 'AI Bokeh Blur',
                  subtitle: 'Studio depth',
                  icon: Icons.blur_on,
                  isSelected: _aiBackgroundBlur,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _aiBackgroundBlur = !_aiBackgroundBlur;
                      if (_aiBackgroundBlur) _virtualGreenScreen = false;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildFilterModeCard(
                  title: 'Green Screen',
                  subtitle: 'Chroma stage',
                  icon: Icons.panorama_photosphere_outlined,
                  isSelected: _virtualGreenScreen,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _virtualGreenScreen = !_virtualGreenScreen;
                      if (_virtualGreenScreen) _aiBackgroundBlur = false;
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterModeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandBlue.withValues(alpha: 0.1)
              : context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isSelected ? AppColors.brandBlue : context.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? AppColors.brandBlue : context.textPrimary,
            ),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 9.5,
                color: context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactLivePreview() {
    final hasCamera = _cameraInitialized && _activeCamera != null;

    return Container(
      height: 175,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background feed: Camera or Simulated Studio Viewport
          if (hasCamera)
            _buildSafeCameraPreview(_activeCamera,
                fallback: _buildSimulatedStudioView())
          else
            _buildSimulatedStudioView(),

          // AI Background blur simulation
          if (_aiBackgroundBlur)
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 4.5, sigmaY: 4.5),
              child: Container(
                color: Colors.black.withValues(alpha: 0.15),
              ),
            ),

          // Virtual Green Screen Chroma backdrop simulation
          if (_virtualGreenScreen)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF00FF66).withValues(alpha: 0.35),
                    const Color(0xFF003311).withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),

          // Skin Smoothing soft-contrast overlay
          if (_skinSmoothing > 0.05)
            Container(
              color: Colors.white.withValues(alpha: _skinSmoothing * 0.12),
            ),

          // Studio Ring Light & Warm Glow Radial illumination
          if (_studioLighting > 0.05)
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.9,
                  colors: [
                    Colors.transparent,
                    const Color(0xFFFFB300)
                        .withValues(alpha: _studioLighting * 0.38),
                  ],
                ),
              ),
            ),

          // Top Badges overlay: LIVE PREVIEW & RETOUCH ACTIVE
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.brandPink,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'LIVE PREVIEW',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome, size: 10, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    'OVA RETOUCH AI',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Filter Status Strip
          Positioned(
            bottom: 8,
            left: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Smooth: ${(_skinSmoothing * 100).toInt()}% · Warmth: ${(_studioLighting * 100).toInt()}%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _virtualGreenScreen
                        ? 'Chroma Studio'
                        : (_aiBackgroundBlur ? 'Bokeh Blur' : 'Natural Feed'),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandPink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulatedStudioView() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E293B),
            Color(0xFF0A0F1D),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.brandPink.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                    gradient: const LinearGradient(
                      colors: [AppColors.brandBlue, AppColors.brandPink],
                    ),
                  ),
                  child: const Icon(
                    Icons.person,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: AppColors.brandPink,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.star, size: 10, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Studio Camera Feed Ready',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // STEP 4: LIVE MEDIA DESK & ATMOSPHERE
  // Max 3 primary controls:
  // Control 1: AI Stage Atmosphere preset selector (Neon Stadium, Cyber Loft, Acoustic Lounge, Hologram Galaxy)
  // Control 2: Background Music / YouTube audio stream toggle & volume preview
  // Control 3: Lower-Third graphic banner ticker text input
  // ───────────────────────────────────────────────────────────────────────────

  String _matchAiScenePreset(String prompt) {
    final lower = prompt.toLowerCase();
    if (lower.contains('cinema') ||
        lower.contains('movie') ||
        lower.contains('7.1') ||
        lower.contains('cyber-cinema')) {
      return 'Cyber-Cinema 7.1';
    } else if (lower.contains('stadium') ||
        lower.contains('arena') ||
        lower.contains('concert') ||
        lower.contains('neon stadium')) {
      return 'Neon Stadium';
    } else if (lower.contains('acoustic') ||
        lower.contains('loft') ||
        lower.contains('lounge') ||
        lower.contains('jazz') ||
        lower.contains('sunset')) {
      return 'Acoustic Loft';
    } else if (lower.contains('executive') ||
        lower.contains('suite') ||
        lower.contains('obsidian') ||
        lower.contains('vip') ||
        lower.contains('corporate')) {
      return 'Executive Suite';
    } else if (lower.contains('cosmic') ||
        lower.contains('hologram') ||
        lower.contains('galaxy') ||
        lower.contains('nebula') ||
        lower.contains('space')) {
      return 'Cosmic Hologram';
    }
    return 'Cyber-Cinema 7.1';
  }

  Future<void> _generateAiScene(String prompt) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) return;
    setState(() => _isGeneratingScene = true);
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 350));
    final matched = _matchAiScenePreset(cleanPrompt);
    if (mounted) {
      setState(() {
        _atmospherePreset = matched;
        _isGeneratingScene = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✨ Ova AI Generated: $matched stage active!'),
          backgroundColor: AppColors.brandBlue,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildAiSceneGeneratorCard() {
    final templates = [
      'Cyber-Cinema 7.1',
      'Neon Stadium',
      'Acoustic Loft',
      'Executive Suite',
      'Cosmic Hologram',
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.brandBlue.withValues(alpha: 0.35),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.brandPink.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: AppColors.brandPink, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OVA AI SCENE GENERATOR',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      'Prompt futuristic 3D stages & 7.1 spatial lighting',
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.brandBlue, width: 0.8),
                ),
                child: Text(
                  'PRO AI',
                  style: GoogleFonts.inter(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.brandBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Prompt Input Field
          Container(
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _scenePromptController,
                    style: GoogleFonts.inter(fontSize: 12, color: context.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'e.g., Cyber-Cinema 7.1, Neon Stadium...',
                      hintStyle: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    onSubmitted: (val) => _generateAiScene(val),
                  ),
                ),
                if (_isGeneratingScene)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandPink),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.auto_awesome_rounded, color: AppColors.brandPink, size: 18),
                    onPressed: () => _generateAiScene(_scenePromptController.text),
                    tooltip: 'Generate Stage Scene',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Quick template pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: templates.map((tmpl) {
                final isCurrent = _atmospherePreset == tmpl;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () {
                      _scenePromptController.text = tmpl;
                      _generateAiScene(tmpl);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? AppColors.brandBlue.withValues(alpha: 0.15)
                            : context.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isCurrent ? AppColors.brandBlue : context.border,
                          width: isCurrent ? 1.2 : 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bolt_rounded,
                            size: 11,
                            color: isCurrent ? AppColors.brandPink : context.textMuted,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            tmpl,
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                              color: isCurrent ? context.textPrimary : context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep4MediaAtmosphere() {
    final atmospherePresets = [
      {
        'title': 'Cyber-Cinema 7.1',
        'sub': '7.1 spatial immersion & cyan halo',
        'icon': Icons.movie_filter_outlined,
        'colors': [AppColors.brandBlue, const Color(0xFF00E5FF)],
      },
      {
        'title': 'Neon Stadium',
        'sub': 'Electric blue & magenta arena',
        'icon': Icons.stadium_outlined,
        'colors': [AppColors.brandBlue, AppColors.brandPink],
      },
      {
        'title': 'Acoustic Loft',
        'sub': 'Warm timber & sunset ambient',
        'icon': Icons.queue_music_outlined,
        'colors': [const Color(0xFFFF8A00), const Color(0xFF1A1F3C)],
      },
      {
        'title': 'Executive Suite',
        'sub': 'Sleek obsidian & mint neon',
        'icon': Icons.business_center_outlined,
        'colors': [const Color(0xFF0A192F), const Color(0xFF00FFA3)],
      },
      {
        'title': 'Cosmic Hologram',
        'sub': 'Deep cosmic stellar nebula',
        'icon': Icons.auto_awesome_outlined,
        'colors': [const Color(0xFF4C1D95), const Color(0xFF00E5FF)],
      },
    ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // OVA AI Scene Generator Card
          _buildAiSceneGeneratorCard(),
          const SizedBox(height: 14),

          // Control 1: AI Stage Atmosphere preset selector
          _buildControlHeader(
            icon: Icons.stadium_outlined,
            title: 'AI STAGE ATMOSPHERE PRESET',
            badge: 'Control 1 of 3',
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: atmospherePresets.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.1,
            ),
            itemBuilder: (ctx, i) {
              final p = atmospherePresets[i];
              final title = p['title'] as String;
              final sub = p['sub'] as String;
              final icon = p['icon'] as IconData;
              final colors = p['colors'] as List<Color>;
              final isSelected = _atmospherePreset == title;

              return InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _atmospherePreset = title);
                },
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.brandBlue.withValues(alpha: 0.08)
                        : context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.brandBlue
                          : context.border,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: colors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(icon, size: 16, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                              ),
                            ),
                            Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                color: context.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 18),

          // Control 2: Background Music / YouTube audio stream toggle & volume preview
          _buildControlHeader(
            icon: Icons.music_note_outlined,
            title: 'BACKGROUND MUSIC / AUDIO STREAM',
            badge: 'Control 2 of 3',
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _bgMusicEnabled
                            ? AppColors.brandPink.withValues(alpha: 0.15)
                            : context.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.graphic_eq,
                        size: 16,
                        color: _bgMusicEnabled
                            ? AppColors.brandPink
                            : context.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Studio Lo-Fi / YouTube Sync Stream',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                          Text(
                            _bgMusicEnabled
                                ? 'Audio stream active with ducking'
                                : 'Background audio is muted',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _bgMusicEnabled,
                      activeTrackColor: AppColors.brandPink,
                      activeThumbColor: Colors.white,
                      onChanged: (val) {
                        HapticFeedback.lightImpact();
                        setState(() => _bgMusicEnabled = val);
                      },
                    ),
                  ],
                ),
                if (_bgMusicEnabled) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.volume_up_outlined,
                          size: 15, color: AppColors.brandPink),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppColors.brandPink,
                            inactiveTrackColor: context.border,
                            thumbColor: AppColors.brandPink,
                            trackHeight: 3.0,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12),
                          ),
                          child: Slider(
                            value: _bgMusicVolume,
                            min: 0.0,
                            max: 1.0,
                            onChanged: (val) {
                              setState(() => _bgMusicVolume = val);
                            },
                          ),
                        ),
                      ),
                      Text(
                        '${(_bgMusicVolume * 100).toInt()}%',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Animated VU audio meter
                      const _VuMeterWidget(barCount: 5, height: 16),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Control 3: Lower-Third graphic banner ticker text input
          _buildControlHeader(
            icon: Icons.text_fields_outlined,
            title: 'LOWER-THIRD GRAPHIC BANNER TICKER',
            badge: 'Control 3 of 3',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tickerController,
            onChanged: (val) => setState(() => _lowerThirdTicker = val),
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'e.g., Live Q&A · Drop questions in chat · Follow now',
              hintStyle: GoogleFonts.inter(
                color: context.textMuted,
                fontSize: 12,
              ),
              filled: true,
              fillColor: context.surfaceMid,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: context.border, width: 1.0),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: context.border, width: 1.0),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide:
                    const BorderSide(color: AppColors.brandBlue, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Live Lower-Third Preview Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.brandPink.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.brandPink,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'TICKER PREVIEW',
                    style: GoogleFonts.inter(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _lowerThirdTicker.isEmpty
                        ? 'Oneova Live Stage Active...'
                        : _lowerThirdTicker,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
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

  // ───────────────────────────────────────────────────────────────────────────
  // STEP 5: INTERNATIONAL REGULATIONS, COMPLIANCE & CONSENT
  // Max 3 primary controls:
  // Control 1: Content Rating selector: "All Ages" vs "18+ Mature / Sensitive"
  // Control 2: Copyright & Music Fair-Use Declaration toggle
  // Control 3: Creator Consent Agreement checkbox with "View Guidelines" modal link
  // Live Broadcast Summary Card with Camera/Audio Monitor and glowing "Start Oneova Live Broadcast" CTA button
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildStep5RegulationsGoLive() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Control 1: Content Rating selector
          _buildControlHeader(
            icon: Icons.verified_user_outlined,
            title: 'CONTENT AUDIENCE RATING',
            badge: 'Control 1 of 3',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildRatingCard(
                  title: 'All Ages',
                  subtitle: 'General audience · Safe for all viewers',
                  icon: Icons.verified_outlined,
                  isSelected: _contentRating == 'All Ages',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _contentRating = 'All Ages');
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildRatingCard(
                  title: '18+ Mature',
                  subtitle: 'Adult themes · Restricted to 18+',
                  icon: Icons.explicit_outlined,
                  isSelected: _contentRating == '18+ Mature / Sensitive',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _contentRating = '18+ Mature / Sensitive');
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Control 2: Copyright & Music Fair-Use Declaration toggle
          _buildControlHeader(
            icon: Icons.copyright_outlined,
            title: 'COPYRIGHT & FAIR-USE DECLARATION',
            badge: 'Control 2 of 3',
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Row(
              children: [
                const Icon(Icons.gavel_outlined,
                    size: 18, color: AppColors.brandBlue),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fair-Use & Broadcast Licensing',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        'I declare that all broadcasted audio and video comply with DMCA & International IP Treaties.',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _copyrightFairUseDeclared,
                  activeTrackColor: AppColors.brandBlue,
                  activeThumbColor: Colors.white,
                  onChanged: (val) {
                    HapticFeedback.lightImpact();
                    setState(() => _copyrightFairUseDeclared = val);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Control 3: Creator Consent Agreement checkbox with "View Guidelines" modal link
          _buildControlHeader(
            icon: Icons.assignment_outlined,
            title: 'CREATOR CONSENT & COMMUNITY SAFETY',
            badge: 'Control 3 of 3',
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _creatorConsentAgreed
                  ? AppColors.brandBlue.withValues(alpha: 0.08)
                  : context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: _creatorConsentAgreed
                    ? AppColors.brandBlue
                    : context.border,
                width: 1.0,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _creatorConsentAgreed,
                  activeColor: AppColors.brandBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  onChanged: (val) {
                    HapticFeedback.lightImpact();
                    setState(() => _creatorConsentAgreed = val ?? false);
                  },
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'I agree to Oneova Community Guidelines, Anti-Harassment Regulations, and Creator Code of Conduct.',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: _showGuidelinesModal,
                        child: Text(
                          'View Guidelines & Policies →',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brandBlue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Live Broadcast Summary Card with Camera/Audio Monitor
          _buildSummaryCard(),

          const SizedBox(height: 18),

          // Glowing "Start Oneova Live Broadcast" CTA button
          _buildGlowingCtaButton(),

          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildRatingCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandBlue.withValues(alpha: 0.08)
              : context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isSelected ? AppColors.brandBlue : context.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? AppColors.brandBlue : context.textPrimary,
                ),
                const Spacer(),
                Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: isSelected ? AppColors.brandBlue : context.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final hasCamera = _cameraInitialized && _activeCamera != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Mini Camera/Audio Monitor Frame
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.brandPink.withValues(alpha: 0.4),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasCamera)
                      _buildSafeCameraPreview(
                        _activeCamera,
                        fallback: Container(
                          color: const Color(0xFF0F172A),
                          child: const Icon(Icons.videocam,
                              size: 20, color: Colors.white54),
                        ),
                      )
                    else
                      Container(
                        color: const Color(0xFF0F172A),
                        child: const Icon(Icons.videocam,
                            size: 20, color: Colors.white54),
                      ),
                    // Live mini VU meter at bottom
                    const Positioned(
                      bottom: 3,
                      left: 4,
                      right: 4,
                      child: _VuMeterWidget(barCount: 4, height: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Broadcast Title & Quick Metrics
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title.isEmpty ? 'Oneova Live Broadcast' : _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _buildSummaryBadge(_category, AppColors.brandBlue),
                        const SizedBox(width: 5),
                        _buildSummaryBadge(_quality, AppColors.brandPink),
                        const SizedBox(width: 5),
                        _buildSummaryBadge(_audienceMode, context.textSecondary),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Atmosphere: $_atmospherePreset · $_hostingMode',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        _buildSummaryBadge(
                          '30-Day Key Active',
                          const Color(0xFF10B981),
                        ),
                        if (_isAiModerationEnabled)
                          _buildSummaryBadge(
                            'Ova AI Shield On',
                            AppColors.brandPink,
                          ),
                        if (_apiKeyEnabled)
                          _buildSummaryBadge(
                            'API Key Ready',
                            AppColors.brandBlue,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Live Encoder Ready · Latency: Ultra-Low (180ms)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF10B981),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _contentRating,
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildGlowingCtaButton() {
    final enabled = _creatorConsentAgreed;

    return InkWell(
      onTap: _startBroadcast,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 42,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          gradient: enabled
              ? const LinearGradient(
                  colors: [AppColors.brandBlue, AppColors.brandPink],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : LinearGradient(
                  colors: [
                    context.surfaceMid,
                    context.surfaceMid,
                  ],
                ),
          border: Border.all(
            color: enabled ? Colors.transparent : context.border,
            width: 1.0,
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.brandPink.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.sensors,
              size: 18,
              color: enabled ? Colors.white : context.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              'Start Oneova Live Broadcast',
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
                color: enabled ? Colors.white : context.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // HELPER WIDGETS
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildControlHeader({
    required IconData icon,
    required String title,
    required String badge,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.brandBlue),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: context.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (trailing != null)
          trailing
        else
          Text(
            badge,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: context.textMuted,
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REAL-TIME VU AUDIO METER WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class _VuMeterWidget extends StatefulWidget {
  final int barCount;
  final double height;

  const _VuMeterWidget({
    this.barCount = 5,
    this.height = 18,
  });

  @override
  State<_VuMeterWidget> createState() => _VuMeterWidgetState();
}

class _VuMeterWidgetState extends State<_VuMeterWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (ctx, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(widget.barCount, (i) {
            final phase = (i * 0.28);
            final val = math.sin((_animCtrl.value * math.pi) + phase).abs();
            final barH = math.max(3.0, val * widget.height);

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.2),
              width: 2.5,
              height: barH,
              decoration: BoxDecoration(
                color: i % 2 == 0 ? AppColors.brandPink : AppColors.brandBlue,
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          }),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPLIANCE & REGULATIONS GUIDELINES MODAL
// ─────────────────────────────────────────────────────────────────────────────

class _OneovaGuidelinesSheet extends StatelessWidget {
  final VoidCallback onAccept;

  const _OneovaGuidelinesSheet({required this.onAccept});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: context.border, width: 1.0),
      ),
      padding: EdgeInsets.fromLTRB(
          18, 12, 18, MediaQuery.paddingOf(context).bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Row(
            children: [
              const Icon(Icons.gavel_rounded,
                  color: AppColors.brandBlue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Oneova Live Broadcaster Standards',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Text(
            'Broadcasting on Oneova requires strict adherence to international digital media regulations and community trust requirements:',
            style: GoogleFonts.inter(
              fontSize: 11.5,
              color: context.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),

          // Rule items
          _buildRuleItem(
            context,
            icon: Icons.shield_outlined,
            title: '1. Community Safety & Anti-Harassment',
            desc:
                'Zero-tolerance for hate speech, targeted bullying, violence, or dangerous behavior. Real-time AI moderation automatically halts flagged rooms.',
          ),
          const SizedBox(height: 10),
          _buildRuleItem(
            context,
            icon: Icons.copyright_outlined,
            title: '2. Copyright & Intellectual Property',
            desc:
                'You must possess explicit licenses or fair-use exemptions for all background music, visuals, and rebroadcasted content. DMCA notices trigger instant strikes.',
          ),
          const SizedBox(height: 10),
          _buildRuleItem(
            context,
            icon: Icons.storefront_outlined,
            title: '3. Commercial & Sponsorship Disclosure',
            desc:
                'All brand partnerships, sponsored endorsements, and affiliate promos must be disclosed via Oneova creator lower-third banners in compliance with FTC guidelines.',
          ),
          const SizedBox(height: 10),
          _buildRuleItem(
            context,
            icon: Icons.lock_outline,
            title: '4. Real-time AI Moderation & Recording',
            desc:
                'Live audio and video feeds are subject to automated safety scanning. Repeated violations lead to irrevocable creator account termination.',
          ),

          const SizedBox(height: 18),

          // Accept button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            onPressed: onAccept,
            child: Text(
              'I Understand & Accept Guidelines',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.brandPink),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  color: context.textSecondary,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
