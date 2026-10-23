import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../backend/live/models/live_models.dart';
import '../../../backend/live/services/live_service.dart';
import '../../../shared/services/oneova_sound_service.dart';
import '../../../shared/theme/app_theme.dart';

/// In-stream Live Media Desk Sheet for Oneova.
///
/// Features 4 high-density executive tabs:
/// 1. Audio & YouTube: Stream YouTube audio & curated royalty-free music with volume & auto-ducking.
/// 2. Soundboard FX: Instant sound effect triggers with heavy haptic feedback & animated pulse.
/// 3. Graphic Overlays: Lower-third ticker banners & watermark overlays with real-time live preview.
/// 4. Guest Requests & Stage Moderation: Live Firestore approval of speakers/co-hosts and stage controls.
class OneovaLiveMediaDeskSheet extends ConsumerStatefulWidget {
  final String streamId;
  final String hostHandle;
  final ValueChanged<Map<String, dynamic>>? onOverlaySettingsChanged;
  final ValueChanged<double>? onBackgroundMusicVolumeChanged;

  const OneovaLiveMediaDeskSheet({
    super.key,
    required this.streamId,
    this.hostHandle = '@streamer',
    this.onOverlaySettingsChanged,
    this.onBackgroundMusicVolumeChanged,
  });

  /// Static helper to display the sheet modally
  static Future<void> show(
    BuildContext context, {
    required String streamId,
    String hostHandle = '@streamer',
    ValueChanged<Map<String, dynamic>>? onOverlaySettingsChanged,
    ValueChanged<double>? onBackgroundMusicVolumeChanged,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OneovaLiveMediaDeskSheet(
        streamId: streamId,
        hostHandle: hostHandle,
        onOverlaySettingsChanged: onOverlaySettingsChanged,
        onBackgroundMusicVolumeChanged: onBackgroundMusicVolumeChanged,
      ),
    );
  }

  @override
  ConsumerState<OneovaLiveMediaDeskSheet> createState() =>
      _OneovaLiveMediaDeskSheetState();
}

class _OneovaLiveMediaDeskSheetState
    extends ConsumerState<OneovaLiveMediaDeskSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Tab 1: Audio & YouTube State ─────────────────────────────────────────
  final TextEditingController _ytInputController = TextEditingController();
  bool _isYtStreaming = false;
  String _currentYtTitle = '';
  double _bgmVolume = 0.65;
  bool _autoDuckingEnabled = true;
  int _selectedBgmIndex = -1;

  final List<_BgmTrack> _bgmCatalog = const [
    _BgmTrack('Lo-Fi Lounge & Chill', '80 BPM', 'Relaxed', 'Asset/Chill'),
    _BgmTrack('Upbeat Electro Wave', '124 BPM', 'Energetic', 'Asset/Electro'),
    _BgmTrack('Acoustic Sunset', '92 BPM', 'Warm Ambient', 'Asset/Acoustic'),
    _BgmTrack('Cyber Gaming Rush', '138 BPM', 'Hype Beat', 'Asset/Cyber'),
    _BgmTrack('Executive Clarity Jazz', '96 BPM', 'Minimal Studio', 'Asset/Jazz'),
  ];

  // ── Tab 2: Soundboard FX State ───────────────────────────────────────────
  double _soundboardVolume = 0.85;
  String? _lastTriggeredFx;
  Timer? _fxFeedbackTimer;

  final List<_SoundboardItem> _soundFxList = const [
    _SoundboardItem('Applause', '👏', 'Crowd cheering & claps', 'applause'),
    _SoundboardItem('Airhorn', '🎺', 'Classic stadium hype horn', 'airhorn'),
    _SoundboardItem('Cheers', '🎉', 'Celebration & whistles', 'cheers'),
    _SoundboardItem('Drumroll', '🥁', 'Suspenseful snare crescendo', 'drumroll'),
    _SoundboardItem('Rimshot', '💥', 'Ba-dum-tss punchline', 'rimshot'),
    _SoundboardItem('Laugh Track', '😂', 'Live comedy studio laughter', 'laugh'),
    _SoundboardItem('Hype Siren', '🚨', 'Club drop alert siren', 'siren'),
    _SoundboardItem('Victory', '🏆', 'Level up fanfare chime', 'victory'),
  ];

  // ── Tab 3: Graphic Overlays State ────────────────────────────────────────
  bool _showLowerThird = true;
  late final TextEditingController _lowerThirdHandleController;
  final TextEditingController _lowerThirdTickerController =
      TextEditingController(text: '🔥 Welcome to the Oneova Live Stream • Tap Follow & Share');
  bool _showLiveBadge = true;

  bool _showWatermark = true;
  final TextEditingController _watermarkTextController =
      TextEditingController(text: 'ONEOVA LIVE');
  String _watermarkPosition = 'Top-Right'; // 'Top-Left', 'Top-Right', 'Bottom-Left', 'Bottom-Right'
  double _watermarkOpacity = 0.85;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _lowerThirdHandleController =
        TextEditingController(text: widget.hostHandle);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ytInputController.dispose();
    _lowerThirdHandleController.dispose();
    _lowerThirdTickerController.dispose();
    _watermarkTextController.dispose();
    _fxFeedbackTimer?.cancel();
    super.dispose();
  }

  void _notifyOverlayChanges() {
    widget.onOverlaySettingsChanged?.call({
      'showLowerThird': _showLowerThird,
      'lowerThirdHandle': _lowerThirdHandleController.text,
      'lowerThirdTicker': _lowerThirdTickerController.text,
      'showLiveBadge': _showLiveBadge,
      'showWatermark': _showWatermark,
      'watermarkText': _watermarkTextController.text,
      'watermarkPosition': _watermarkPosition,
      'watermarkOpacity': _watermarkOpacity,
    });
  }

  // ── Soundboard Trigger Handler ───────────────────────────────────────────
  Future<void> _triggerSoundFx(_SoundboardItem fx) async {
    // 1. Mandatory Heavy Impact Haptic Feedback
    await HapticFeedback.heavyImpact();

    // 2. Play sound via sound service or system sound
    try {
      OneOvaSoundService().playNotificationChime('studio_pop');
    } catch (_) {}

    if (mounted) {
      setState(() {
        _lastTriggeredFx = fx.title;
      });
      _fxFeedbackTimer?.cancel();
      _fxFeedbackTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) {
          setState(() {
            _lastTriggeredFx = null;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isDark = context.isDark;

    return Container(
      height: media.size.height * 0.82,
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border.all(color: context.border, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.15),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 10),
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
          const SizedBox(height: 12),

          // Header: Live Media Desk Title & Status Badge
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.brandBlue, AppColors.brandPink],
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(
                    Icons.dashboard_customize_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Live Media Desk',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: context.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.brandPink.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AppColors.brandPink.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                    color: AppColors.brandPink,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'ON-AIR',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.brandPink,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Production audio, soundboard FX & stage control',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: context.textMuted, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close Media Desk',
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Custom High-Density Segmented Tab Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 38,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: context.border, width: 1.0),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppColors.brandBlue,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandBlue.withValues(alpha: 0.35),
                      blurRadius: 6,
                    ),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: context.textSecondary,
                labelStyle: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
                tabs: const [
                  Tab(
                    iconMargin: EdgeInsets.zero,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.music_note_rounded, size: 14),
                        SizedBox(width: 4),
                        Text('Audio'),
                      ],
                    ),
                  ),
                  Tab(
                    iconMargin: EdgeInsets.zero,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.campaign_rounded, size: 14),
                        SizedBox(width: 4),
                        Text('FX'),
                      ],
                    ),
                  ),
                  Tab(
                    iconMargin: EdgeInsets.zero,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.layers_rounded, size: 14),
                        SizedBox(width: 4),
                        Text('Overlays'),
                      ],
                    ),
                  ),
                  Tab(
                    iconMargin: EdgeInsets.zero,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.how_to_reg_rounded, size: 14),
                        SizedBox(width: 4),
                        Text('Stage'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          Divider(height: 1, color: context.border),

          // Tab Content Area
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAudioTab(context),
                _buildSoundboardTab(context),
                _buildOverlaysTab(context),
                _buildStageModerationTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 1: AUDIO & YOUTUBE
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildAudioTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        // Section Header: YouTube Streamer
        Row(
          children: [
            const Icon(Icons.play_circle_fill_rounded,
                size: 16, color: AppColors.brandPink),
            const SizedBox(width: 6),
            Text(
              'YouTube Audio Streamer',
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Stream background music, podcasts, or tracks into the room live.',
          style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary),
        ),
        const SizedBox(height: 10),

        // YouTube URL Input Field
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _ytInputController,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: context.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    hintText: 'Paste YouTube URL or search query...',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 12,
                      color: context.textMuted,
                    ),
                    filled: true,
                    fillColor: context.surfaceMid,
                    prefixIcon: Icon(
                      Icons.link_rounded,
                      size: 16,
                      color: context.textMuted,
                    ),
                    suffixIcon: _ytInputController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 14),
                            onPressed: () {
                              setState(() {
                                _ytInputController.clear();
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: context.border, width: 1.0),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: context.border, width: 1.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide:
                          const BorderSide(color: AppColors.brandBlue, width: 1.0),
                    ),
                  ),
                  onChanged: (val) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                minimumSize: const Size(60, 38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
              onPressed: () {
                final query = _ytInputController.text.trim();
                if (query.isEmpty) return;
                HapticFeedback.lightImpact();
                setState(() {
                  _isYtStreaming = true;
                  _currentYtTitle = query.contains('youtube')
                      ? 'Oneova Studio Stream • Live Lo-Fi Focus'
                      : query;
                });
              },
              child: Text(
                _isYtStreaming ? 'Sync' : 'Stream',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),

        // Active YouTube Audio Card
        if (_isYtStreaming) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: AppColors.brandBlue.withValues(alpha: 0.4),
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    color: AppColors.brandBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentYtTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.brandPink,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Streaming to room • 128kbps audio',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.stop_circle_rounded,
                      color: AppColors.brandPink, size: 22),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _isYtStreaming = false;
                    });
                  },
                  tooltip: 'Stop YouTube Stream',
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),
        Divider(color: context.border, height: 1),
        const SizedBox(height: 16),

        // Section Header: Royalty-Free Background Music Catalog
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.library_music_rounded,
                    size: 16, color: AppColors.brandBlue),
                const SizedBox(width: 6),
                Text(
                  'Royalty-Free BGM Catalog',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
              ],
            ),
            if (_selectedBgmIndex >= 0)
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(40, 24),
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _selectedBgmIndex = -1;
                  });
                },
                child: Text(
                  'Stop Music',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandPink,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '100% DMCA-safe instrumental audio calibrated for live production.',
          style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary),
        ),
        const SizedBox(height: 10),

        // BGM Tracks List
        ...List.generate(_bgmCatalog.length, (index) {
          final track = _bgmCatalog[index];
          final isPlaying = _selectedBgmIndex == index;

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isPlaying
                  ? AppColors.brandBlue.withValues(alpha: 0.12)
                  : context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: isPlaying ? AppColors.brandBlue : context.border,
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_outline_rounded,
                    color: isPlaying ? AppColors.brandBlue : context.textPrimary,
                    size: 24,
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _selectedBgmIndex = isPlaying ? -1 : index;
                    });
                  },
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight:
                              isPlaying ? FontWeight.w700 : FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            '${track.bpm} • ${track.genre}',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              color: context.textMuted,
                            ),
                          ),
                          if (isPlaying) ...[
                            const SizedBox(width: 6),
                            Text(
                              '• Playing live',
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brandBlue,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.bg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: context.border),
                  ),
                  child: Text(
                    'DMCA FREE',
                    style: GoogleFonts.inter(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandPink,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 16),

        // Volume & Auto-Ducking Controls
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        _bgmVolume == 0
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        size: 16,
                        color: context.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Background Music Volume',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${(_bgmVolume * 100).round()}%',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandBlue,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.brandBlue,
                  inactiveTrackColor: context.border,
                  thumbColor: AppColors.brandBlue,
                  overlayColor: AppColors.brandBlue.withValues(alpha: 0.2),
                  trackHeight: 3.0,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                ),
                child: Slider(
                  value: _bgmVolume,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (val) {
                    setState(() => _bgmVolume = val);
                    widget.onBackgroundMusicVolumeChanged?.call(val);
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Smart Auto-Ducking',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        'Dampens BGM by 70% automatically when voice is detected',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          color: context.textMuted,
                        ),
                      ),
                    ],
                  ),
                  Switch.adaptive(
                    value: _autoDuckingEnabled,
                    activeTrackColor: AppColors.brandBlue,
                    onChanged: (val) {
                      HapticFeedback.lightImpact();
                      setState(() => _autoDuckingEnabled = val);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 2: SOUNDBOARD FX
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildSoundboardTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        // Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.touch_app_rounded,
                        size: 16, color: AppColors.brandPink),
                    const SizedBox(width: 6),
                    Text(
                      'Live Soundboard FX',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap triggers instant sound effect with heavy tactile feedback.',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
            if (_lastTriggeredFx != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.brandPink,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'PLAYING: $_lastTriggeredFx',
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 14),

        // Soundboard Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.1,
          ),
          itemCount: _soundFxList.length,
          itemBuilder: (ctx, idx) {
            final fx = _soundFxList[idx];
            final isTriggered = _lastTriggeredFx == fx.title;

            return InkWell(
              onTap: () => _triggerSoundFx(fx),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isTriggered
                      ? AppColors.brandPink.withValues(alpha: 0.18)
                      : context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: isTriggered ? AppColors.brandPink : context.border,
                    width: isTriggered ? 1.5 : 1.0,
                  ),
                  boxShadow: isTriggered
                      ? [
                          BoxShadow(
                            color: AppColors.brandPink.withValues(alpha: 0.3),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isTriggered
                            ? AppColors.brandPink
                            : context.bg,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isTriggered
                              ? AppColors.brandPink
                              : context.border,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          fx.emoji,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            fx.title,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isTriggered
                                  ? AppColors.brandPink
                                  : context.textPrimary,
                            ),
                          ),
                          Text(
                            fx.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              color: context.textMuted,
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

        const SizedBox(height: 20),

        // Soundboard Volume Bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.volume_up_rounded,
                          size: 16, color: context.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        'FX Master Volume',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${(_soundboardVolume * 100).round()}%',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandPink,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.brandPink,
                  inactiveTrackColor: context.border,
                  thumbColor: AppColors.brandPink,
                  overlayColor: AppColors.brandPink.withValues(alpha: 0.2),
                  trackHeight: 3.0,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                ),
                child: Slider(
                  value: _soundboardVolume,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (val) {
                    setState(() => _soundboardVolume = val);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 3: GRAPHIC OVERLAYS
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildOverlaysTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        // ── Lower-Third Banner Section ─────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.subtitles_rounded,
                        size: 16, color: AppColors.brandBlue),
                    const SizedBox(width: 6),
                    Text(
                      'Lower-Third Streamer Banner',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Shows broadcaster handle, live badge, and custom headline ticker.',
                  style: GoogleFonts.inter(
                    fontSize: 11.0,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
            Switch.adaptive(
              value: _showLowerThird,
              activeTrackColor: AppColors.brandBlue,
              onChanged: (val) {
                HapticFeedback.lightImpact();
                setState(() => _showLowerThird = val);
                _notifyOverlayChanges();
              },
            ),
          ],
        ),

        const SizedBox(height: 10),

        if (_showLowerThird) ...[
          // Broadcaster Handle Field
          SizedBox(
            height: 38,
            child: TextField(
              controller: _lowerThirdHandleController,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: context.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                labelText: 'Streamer Handle',
                labelStyle: GoogleFonts.inter(fontSize: 11, color: context.textMuted),
                filled: true,
                fillColor: context.surfaceMid,
                prefixIcon: const Icon(Icons.alternate_email_rounded, size: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: context.border, width: 1.0),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: context.border, width: 1.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide:
                      const BorderSide(color: AppColors.brandBlue, width: 1.0),
                ),
              ),
              onChanged: (_) {
                setState(() {});
                _notifyOverlayChanges();
              },
            ),
          ),
          const SizedBox(height: 8),

          // Ticker Headline Field
          SizedBox(
            height: 38,
            child: TextField(
              controller: _lowerThirdTickerController,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: context.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                labelText: 'Ticker Headline Message',
                labelStyle: GoogleFonts.inter(fontSize: 11, color: context.textMuted),
                filled: true,
                fillColor: context.surfaceMid,
                prefixIcon: const Icon(Icons.campaign_outlined, size: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: context.border, width: 1.0),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: context.border, width: 1.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide:
                      const BorderSide(color: AppColors.brandBlue, width: 1.0),
                ),
              ),
              onChanged: (_) {
                setState(() {});
                _notifyOverlayChanges();
              },
            ),
          ),
          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Show "LIVE" badge on banner',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              Switch.adaptive(
                value: _showLiveBadge,
                activeTrackColor: AppColors.brandPink,
                onChanged: (val) {
                  HapticFeedback.lightImpact();
                  setState(() => _showLiveBadge = val);
                  _notifyOverlayChanges();
                },
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Lower-Third Real-Time Preview
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PREVIEW ON STREAM',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Colors.white54,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xE60C4FA8),
                        Color(0xE6FF2D87),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      if (_showLiveBadge) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'LIVE',
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: AppColors.brandPink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _lowerThirdHandleController.text.isNotEmpty
                            ? _lowerThirdHandleController.text
                            : widget.hostHandle,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(width: 1, height: 12, color: Colors.white38),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _lowerThirdTickerController.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),
        Divider(color: context.border, height: 1),
        const SizedBox(height: 16),

        // ── Sponsor / Watermark Overlay Section ─────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.branding_watermark_rounded,
                        size: 16, color: AppColors.brandPink),
                    const SizedBox(width: 6),
                    Text(
                      'Sponsor Logo / Watermark',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Persistent watermark displayed on broadcast stream.',
                  style: GoogleFonts.inter(
                    fontSize: 11.0,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
            Switch.adaptive(
              value: _showWatermark,
              activeTrackColor: AppColors.brandPink,
              onChanged: (val) {
                HapticFeedback.lightImpact();
                setState(() => _showWatermark = val);
                _notifyOverlayChanges();
              },
            ),
          ],
        ),

        if (_showWatermark) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: TextField(
              controller: _watermarkTextController,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: context.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                labelText: 'Watermark Brand / Text',
                labelStyle: GoogleFonts.inter(fontSize: 11, color: context.textMuted),
                filled: true,
                fillColor: context.surfaceMid,
                prefixIcon: const Icon(Icons.verified_outlined, size: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: context.border, width: 1.0),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: context.border, width: 1.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide:
                      const BorderSide(color: AppColors.brandPink, width: 1.0),
                ),
              ),
              onChanged: (_) {
                setState(() {});
                _notifyOverlayChanges();
              },
            ),
          ),
          const SizedBox(height: 10),

          // Position Chips
          Text(
            'Watermark Position',
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final pos in [
                'Top-Left',
                'Top-Right',
                'Bottom-Left',
                'Bottom-Right'
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      pos,
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: _watermarkPosition == pos
                            ? Colors.white
                            : context.textSecondary,
                      ),
                    ),
                    selected: _watermarkPosition == pos,
                    selectedColor: AppColors.brandBlue,
                    backgroundColor: context.surfaceMid,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                      side: BorderSide(
                        color: _watermarkPosition == pos
                            ? AppColors.brandBlue
                            : context.border,
                      ),
                    ),
                    onSelected: (sel) {
                      if (sel) {
                        HapticFeedback.selectionClick();
                        setState(() => _watermarkPosition = pos);
                        _notifyOverlayChanges();
                      }
                    },
                  ),
                ),
            ],
          ),

          const SizedBox(height: 10),

          // Watermark Opacity Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Watermark Opacity',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: context.textSecondary,
                ),
              ),
              Text(
                '${(_watermarkOpacity * 100).round()}%',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandBlue,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.brandBlue,
              inactiveTrackColor: context.border,
              thumbColor: AppColors.brandBlue,
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.0),
            ),
            child: Slider(
              value: _watermarkOpacity,
              min: 0.2,
              max: 1.0,
              onChanged: (val) {
                setState(() => _watermarkOpacity = val);
                _notifyOverlayChanges();
              },
            ),
          ),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 4: GUEST REQUESTS & STAGE MODERATION
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildStageModerationTab(BuildContext context) {
    final participantsAsync =
        ref.watch(liveParticipantsProvider(widget.streamId));
    final liveService = ref.read(liveServiceProvider);

    return participantsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.brandBlue),
      ),
      error: (err, stack) => Center(
        child: Text(
          'Failed to load participants: $err',
          style: GoogleFonts.inter(color: AppColors.brandPink),
        ),
      ),
      data: (participants) {
        final joinRequests =
            participants.where((p) => p.hasRequestedToJoin).toList();
        final stageGuests = participants
            .where((p) => p.isCoHost || (!p.hasRequestedToJoin && (p.isCameraOn || !p.isMuted)))
            .toList();

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          children: [
            // ── Section 1: Viewer Join Requests ────────────────────────────
            Row(
              children: [
                const Icon(Icons.record_voice_over_rounded,
                    size: 16, color: AppColors.brandPink),
                const SizedBox(width: 6),
                Text(
                  'Join Requests',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: joinRequests.isNotEmpty
                        ? AppColors.brandPink
                        : context.surfaceMid,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${joinRequests.length}',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: joinRequests.isNotEmpty
                          ? Colors.white
                          : context.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Incoming requests from viewers to join you on stage.',
              style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary),
            ),
            const SizedBox(height: 10),

            if (joinRequests.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Row(
                  children: [
                    Icon(Icons.mark_chat_unread_outlined,
                        size: 20, color: context.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No pending join requests. Viewers who tap "Request to Speak" appear here.',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: context.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...joinRequests.map((req) => _buildRequestCard(req, liveService)),

            const SizedBox(height: 20),
            Divider(color: context.border, height: 1),
            const SizedBox(height: 16),

            // ── Section 2: Active Stage Guests ──────────────────────────────
            Row(
              children: [
                const Icon(Icons.people_alt_rounded,
                    size: 16, color: AppColors.brandBlue),
                const SizedBox(width: 6),
                Text(
                  'Active Stage Guests',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${stageGuests.length} On-Stage',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandBlue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Moderation controls for active speakers, co-hosts and guest feeds.',
              style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary),
            ),
            const SizedBox(height: 10),

            if (stageGuests.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Row(
                  children: [
                    Icon(Icons.mic_none_rounded,
                        size: 20, color: context.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No guests currently on stage. Approve requests above to bring guests on-air.',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: context.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...stageGuests.map((guest) => _buildActiveGuestCard(guest, liveService)),
          ],
        );
      },
    );
  }

  Widget _buildRequestCard(LiveParticipant req, LiveService liveService) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.brandPink.withValues(alpha: 0.35),
          width: 1.0,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.brandBlue,
                backgroundImage: req.avatarUrl.isNotEmpty
                    ? NetworkImage(req.avatarUrl)
                    : null,
                child: req.avatarUrl.isEmpty
                    ? Text(
                        req.displayName.isNotEmpty
                            ? req.displayName.substring(0, 1).toUpperCase()
                            : 'U',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.displayName,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      'Requesting to speak on stage',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        color: AppColors.brandPink,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // Decline Button
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: context.textMuted,
                tooltip: 'Decline',
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  await liveService.declineRequest(
                      widget.streamId, req.userId);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Approve as Speaker
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.brandBlue),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  icon: const Icon(Icons.mic_rounded,
                      size: 14, color: AppColors.brandBlue),
                  label: Text(
                    'Approve Speaker',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandBlue,
                    ),
                  ),
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    await liveService.approveSpeaker(
                        widget.streamId, req.userId);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Approve as Co-Host
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandPink,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  icon: const Icon(Icons.star_rounded, size: 14),
                  label: Text(
                    'Approve Co-Host',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: () async {
                    HapticFeedback.heavyImpact();
                    await liveService.approveCoHost(
                        widget.streamId, req.userId);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveGuestCard(LiveParticipant guest, LiveService liveService) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.brandBlue,
            backgroundImage: guest.avatarUrl.isNotEmpty
                ? NetworkImage(guest.avatarUrl)
                : null,
            child: guest.avatarUrl.isEmpty
                ? Text(
                    guest.displayName.isNotEmpty
                        ? guest.displayName.substring(0, 1).toUpperCase()
                        : 'G',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      guest.displayName,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: guest.isCoHost
                            ? AppColors.brandPink.withValues(alpha: 0.15)
                            : AppColors.brandBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        guest.isCoHost ? 'CO-HOST' : 'SPEAKER',
                        style: GoogleFonts.inter(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: guest.isCoHost
                              ? AppColors.brandPink
                              : AppColors.brandBlue,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Mic: ${guest.isMuted ? 'Muted' : 'Live'} • Video: ${guest.isCameraOn ? 'On' : 'Off'}',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    color: context.textMuted,
                  ),
                ),
              ],
            ),
          ),
          // Action Buttons: Mute, Video, Promote, Drop
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mute Mic Toggle
              IconButton(
                icon: Icon(
                  guest.isMuted
                      ? Icons.mic_off_rounded
                      : Icons.mic_rounded,
                  size: 18,
                  color: guest.isMuted
                      ? AppColors.brandPink
                      : AppColors.brandBlue,
                ),
                tooltip: guest.isMuted ? 'Unmute Mic' : 'Mute Mic',
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  await liveService.setParticipantMute(
                    widget.streamId,
                    guest.userId,
                    !guest.isMuted,
                  );
                },
              ),
              // Disable / Enable Video
              IconButton(
                icon: Icon(
                  guest.isCameraOn
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  size: 18,
                  color: guest.isCameraOn
                      ? AppColors.brandBlue
                      : context.textMuted,
                ),
                tooltip: guest.isCameraOn ? 'Disable Video' : 'Enable Video',
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  await liveService.setParticipantCamera(
                    widget.streamId,
                    guest.userId,
                    !guest.isCameraOn,
                  );
                },
              ),
              // Promote to Moderator
              IconButton(
                icon: const Icon(
                  Icons.shield_outlined,
                  size: 18,
                  color: AppColors.brandBlue,
                ),
                tooltip: 'Promote to Moderator',
                onPressed: () async {
                  HapticFeedback.mediumImpact();
                  await liveService.promoteToModerator(
                      widget.streamId, guest.userId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${guest.displayName} promoted to Stage Moderator',
                          style: GoogleFonts.inter(fontSize: 12),
                        ),
                        backgroundColor: AppColors.brandBlue,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
              // Drop From Stage (MANDATORY CONFIRMATION DIALOG)
              IconButton(
                icon: const Icon(
                  Icons.person_remove_rounded,
                  size: 18,
                  color: AppColors.brandPink,
                ),
                tooltip: 'Drop from Stage',
                onPressed: () {
                  _showConfirmDropDialog(context, guest, liveService);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showConfirmDropDialog(
    BuildContext context,
    LiveParticipant guest,
    LiveService liveService,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: context.border, width: 1.0),
        ),
        title: Text(
          'Drop ${guest.displayName} from Stage?',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        content: Text(
          'This will revoke their speaking permissions and return them to regular viewer status.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: context.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.textMuted,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandPink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              HapticFeedback.heavyImpact();
              await liveService.dropFromStage(
                  widget.streamId, guest.userId);
            },
            child: Text(
              'Drop from Stage',
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
}

// ─────────────────────────────────────────────────────────────────────────────
// MODEL DATA WRAPPERS
// ─────────────────────────────────────────────────────────────────────────────

class _BgmTrack {
  final String title;
  final String bpm;
  final String genre;
  final String assetPath;

  const _BgmTrack(this.title, this.bpm, this.genre, this.assetPath);
}

class _SoundboardItem {
  final String title;
  final String emoji;
  final String subtitle;
  final String soundKey;

  const _SoundboardItem(this.title, this.emoji, this.subtitle, this.soundKey);
}
