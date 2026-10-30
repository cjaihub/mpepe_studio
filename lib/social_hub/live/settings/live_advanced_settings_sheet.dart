import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../looks/device/advisor/device_advisor.dart';
import '../../../looks/device/models/thermal_state.dart';
import '../../../looks/device/providers/device_providers.dart';
import '../../../looks/live/live_looks_controller.dart';
import '../../../looks/live/models/live_profile.dart';
import '../../../looks/models/oneova_look.dart';
import '../../../looks/providers/looks_providers.dart';
import '../../../shared/theme/app_theme.dart';

/// Opens the Advanced Live Settings sheet with haptic feedback.
Future<void> showLiveAdvancedSettingsSheet(BuildContext context) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => const LiveAdvancedSettingsSheet(),
  );
}

/// Advanced Live Settings Sheet (Phase 1, Live Settings UI).
/// Combines Video format, Look & Boost Beauty, Background, Audio, Profiles,
/// Scenes dock, Stream Health HUD, and AI Live Director.
class LiveAdvancedSettingsSheet extends ConsumerStatefulWidget {
  const LiveAdvancedSettingsSheet({super.key});

  @override
  ConsumerState<LiveAdvancedSettingsSheet> createState() =>
      _LiveAdvancedSettingsSheetState();
}

class _LiveAdvancedSettingsSheetState
    extends ConsumerState<LiveAdvancedSettingsSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _debounceTimer;

  // Local working settings
  String _selectedResolution = '1080p';
  int _selectedFps = 30;
  bool _isHdr = false;
  double _smooth = 0.5;
  double _tone = 0.4;
  double _brighten = 0.3;
  double _reshape = 0.2;
  String _bgMode = 'none'; // 'none', 'blur', 'image', 'green'
  double _bgBlurAmount = 0.5;
  bool _noiseSuppression = true;
  bool _echoCancellation = true;
  bool _voiceEnhance = true;

  // Active simulated AI Live Director alert
  LiveDirectorAlert? _currentAlert = const LiveDirectorAlert(
    id: 'backlit_01',
    title: 'Backlit Lighting Detected',
    explanation: 'Your background is brighter than your face. Tap Fix to lift shadows and balance exposure.',
    isFixable: true,
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadInitialState();
  }

  void _loadInitialState() {
    final liveState = ref.read(liveLooksControllerProvider);
    _smooth = liveState.beauty.smoothSkin;
    _tone = liveState.beauty.evenTone;
    _brighten = liveState.beauty.eyeBrighten;
    _reshape = liveState.beauty.faceSlim;
    _bgMode = liveState.background.mode;
    _bgBlurAmount = liveState.background.blurLevel;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _triggerDebouncedAutoSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
      final uid = ref.read(currentAuthUidProvider);
      if (uid.isEmpty) return;

      ref.read(looksRepositoryProvider).saveLiveSettings(uid, {
        'resolution': _selectedResolution,
        'fps': _selectedFps,
        'isHdr': _isHdr,
        'skinSmooth': _smooth,
        'skinTone': _tone,
        'eyeBrighten': _brighten,
        'faceSlim': _reshape,
        'bgMode': _bgMode,
        'bgBlurAmount': _bgBlurAmount,
        'noiseSuppression': _noiseSuppression,
        'echoCancellation': _echoCancellation,
        'voiceEnhance': _voiceEnhance,
      });
    });
  }

  void _updateBeauty() {
    final updatedBeauty = BoostBeautyConfig(
      isEnabled: true,
      smoothSkin: _smooth,
      evenTone: _tone,
      eyeBrighten: _brighten,
      faceSlim: _reshape,
    );
    ref.read(liveLooksControllerProvider.notifier).applyBeauty(updatedBeauty);
    _triggerDebouncedAutoSave();
  }

  void _applyLiveDirectorFix() {
    HapticFeedback.mediumImpact();
    // Smoothly lift shadows and warm up slightly to balance backlight
    final fixLook = ref.read(liveLooksControllerProvider).activeLook.copyWith(
          primary: ref.read(liveLooksControllerProvider).activeLook.primary.copyWith(
                shadows: 0.35,
                exposure: 0.15,
                contrast: 1.05,
              ),
          color: ref.read(liveLooksControllerProvider).activeLook.color.copyWith(
                temperature: 5.0,
              ),
        );
    ref.read(liveLooksControllerProvider.notifier).applyLook(
          fixLook,
          crossFade: const Duration(milliseconds: 400),
        );
    setState(() => _currentAlert = null);
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
    final advisor = ref.watch(deviceAdvisorProvider);
    final enforcement = ref.watch(advisorEnforcementProvider);
    final isProOverride = ref.watch(proOverrideProvider);
    final liveState = ref.watch(liveLooksControllerProvider);
    final thermalSnap = ref.watch(thermalGovernorProvider).currentSnapshot;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: context.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border(
          top: BorderSide(color: context.border, width: 1.0),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.border,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: AppColors.brandBlue,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Live Studio Settings',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        'Looks, Boost Beauty & Stream Health',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: context.textSecondary, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close settings',
                ),
              ],
            ),
          ),

          // Tab Bar
          TabBar(
            controller: _tabController,
            labelColor: AppColors.brandBlue,
            unselectedLabelColor: context.textSecondary,
            indicatorColor: AppColors.brandBlue,
            indicatorSize: TabBarIndicatorSize.tab,
            labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Looks & Beauty'),
              Tab(text: 'Format & Health'),
              Tab(text: 'Audio & FX'),
              Tab(text: 'Profiles & Scenes'),
            ],
          ),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLooksAndBeautyTab(context, liveState),
                _buildFormatAndHealthTab(context, advisor, enforcement, isProOverride, liveState, thermalSnap),
                _buildAudioAndFxTab(context),
                _buildProfilesAndScenesTab(context, liveState),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: Looks & Boost Beauty
  // ---------------------------------------------------------------------------
  Widget _buildLooksAndBeautyTab(BuildContext context, LiveLooksState liveState) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        // AI Live Director Chip Banner
        if (_currentAlert != null)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.brandPink.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.4), width: 1.0),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppColors.brandPink, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentAlert!.title,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _currentAlert!.explanation,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _applyLiveDirectorFix,
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.brandPink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: const Size(0, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  child: Text(
                    'Fix',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms),

        // Looks Carousel
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Realtime Look',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            if (liveState.isCompiling)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _buildLooksList(context, liveState),

        const SizedBox(height: 18),

        // Boost Beauty Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Boost Beauty (On-Device GPU)',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                'Natural Guard Active',
                style: GoogleFonts.inter(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandBlue,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        _buildSliderTile(
          context: context,
          title: 'Skin Smoothing',
          icon: Icons.face_retouching_natural_rounded,
          value: _smooth,
          onChanged: (v) {
            setState(() => _smooth = v);
            _updateBeauty();
          },
        ),
        _buildSliderTile(
          context: context,
          title: 'Even Tone',
          icon: Icons.tonality_rounded,
          value: _tone,
          onChanged: (v) {
            setState(() => _tone = v);
            _updateBeauty();
          },
        ),
        _buildSliderTile(
          context: context,
          title: 'Eye & Teeth Brighten',
          icon: Icons.visibility_rounded,
          value: _brighten,
          onChanged: (v) {
            setState(() => _brighten = v);
            _updateBeauty();
          },
        ),
        _buildSliderTile(
          context: context,
          title: 'Face Reshape (Natural Limit)',
          icon: Icons.auto_fix_high_rounded,
          value: _reshape,
          onChanged: (v) {
            setState(() => _reshape = v);
            _updateBeauty();
          },
        ),
      ],
    );
  }

  Widget _buildLooksList(BuildContext context, LiveLooksState liveState) {
    final sampleLooks = [
      const OneovaLook(id: 'neutral', name: 'Neutral'),
      const OneovaLook(
        id: 'cinematic',
        name: 'Cinematic',
        primary: LookPrimary(contrast: 1.15, highlights: -0.1, shadows: 0.05),
        color: LookColor(vibrance: 0.2),
      ),
      const OneovaLook(
        id: 'golden_hour',
        name: 'Golden Hour',
        color: LookColor(temperature: 15.0, tint: 2.0, vibrance: 0.25),
        primary: LookPrimary(exposure: 0.1),
      ),
      const OneovaLook(
        id: 'portrait_glow',
        name: 'Portrait Glow',
        primary: LookPrimary(contrast: 1.05, highlights: 0.1),
        color: LookColor(temperature: 5.0, saturation: 1.1),
      ),
      const OneovaLook(
        id: 'moody_film',
        name: 'Moody Film',
        primary: LookPrimary(contrast: 1.25, shadows: -0.15, blacks: 0.05),
        film: LookFilm(grain: 0.15),
      ),
    ];

    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sampleLooks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (ctx, idx) {
          final look = sampleLooks[idx];
          final isSelected = liveState.activeLook.id == look.id ||
              (look.id == 'neutral' && liveState.activeLook.name == 'Neutral Live');

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              ref.read(liveLooksControllerProvider.notifier).applyLook(look);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 84,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.brandBlue.withValues(alpha: 0.15)
                    : context.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: isSelected ? AppColors.brandBlue : context.border,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isSelected ? Icons.check_circle_rounded : Icons.palette_outlined,
                    color: isSelected ? AppColors.brandBlue : context.textSecondary,
                    size: 22,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    look.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? AppColors.brandBlue : context.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: Format & Stream Health HUD
  // ---------------------------------------------------------------------------
  Widget _buildFormatAndHealthTab(
    BuildContext context,
    DeviceAdvisor advisor,
    AdvisorEnforcementMode enforcement,
    bool isProOverride,
    LiveLooksState liveState,
    ThermalSnapshot thermalSnap,
  ) {
    final ceiling = advisor.liveCeiling;
    final stats = liveState.latestStats;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        // Health HUD Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Stream Health HUD',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildThermalPill(context, thermalSnap),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      context,
                      label: 'GPU Frame Time',
                      value: stats != null ? '${stats.averageFrameMs.toStringAsFixed(1)} ms' : '2.1 ms',
                      statusOk: (stats?.averageFrameMs ?? 2.1) < 16.0,
                    ),
                  ),
                  Expanded(
                    child: _buildMetricTile(
                      context,
                      label: 'Frame Rate',
                      value: stats != null ? '$_selectedFps fps' : '$_selectedFps fps',
                      statusOk: true,
                    ),
                  ),
                  Expanded(
                    child: _buildMetricTile(
                      context,
                      label: 'Dropped Frames',
                      value: '0.0%',
                      statusOk: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // Resolution Selector
        Text(
          'Broadcast Resolution',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: ['720p', '1080p', '4K'].map((res) {
            final isAboveCeiling = (res == '4K' && ceiling.maxHeight < 2160) ||
                (res == '1080p' && ceiling.maxHeight < 1080);
            final isDisabled = isAboveCeiling && enforcement == AdvisorEnforcementMode.enforce && !isProOverride;
            final isSelected = _selectedResolution == res;

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  onTap: isDisabled
                      ? () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '4K Live is capped by Device Advisor for this phone model. Enable Pro override in Settings to unlock.',
                                style: GoogleFonts.inter(fontSize: 12),
                              ),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      : () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedResolution = res);
                          _triggerDebouncedAutoSave();
                        },
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.brandBlue.withValues(alpha: 0.15)
                          : context.surface,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: isSelected ? AppColors.brandBlue : context.border,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              res,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                color: isDisabled
                                    ? context.textMuted
                                    : (isSelected ? AppColors.brandBlue : context.textPrimary),
                              ),
                            ),
                            if (isDisabled) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.lock_rounded, size: 12, color: context.textMuted),
                            ],
                          ],
                        ),
                        if (isAboveCeiling && !isDisabled)
                          Text(
                            'Pro Override',
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandPink,
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

        // FPS Selector
        Text(
          'Target Frame Rate',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [30, 60].map((fpsVal) {
            final isSelected = _selectedFps == fpsVal;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedFps = fpsVal);
                    _triggerDebouncedAutoSave();
                  },
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.brandBlue.withValues(alpha: 0.15)
                          : context.surface,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: isSelected ? AppColors.brandBlue : context.border,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$fpsVal FPS',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                        color: isSelected ? AppColors.brandBlue : context.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 18),

        _buildSwitchTile(
          context,
          title: 'HDR 10-Bit Broadcast',
          subtitle: 'Captures and streams wide dynamic range color',
          value: _isHdr,
          onChanged: (v) {
            setState(() => _isHdr = v);
            _triggerDebouncedAutoSave();
          },
        ),
      ],
    );
  }

  Widget _buildThermalPill(BuildContext context, ThermalSnapshot snap) {
    Color pillColor;
    String label;
    if (snap.activeMitigationTier == 0) {
      pillColor = Colors.green;
      label = 'Thermal: Nominal';
    } else if (snap.activeMitigationTier <= 2) {
      pillColor = Colors.orange;
      label = 'Tier ${snap.activeMitigationTier}: Mild Warm';
    } else {
      pillColor = Colors.red;
      label = 'Tier ${snap.activeMitigationTier}: Cooling Active';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: pillColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: pillColor.withValues(alpha: 0.4), width: 1.0),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: pillColor,
        ),
      ),
    );
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required String label,
    required String value,
    required bool statusOk,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 10, color: context.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: statusOk ? context.textPrimary : Colors.red,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: Audio & Background FX
  // ---------------------------------------------------------------------------
  Widget _buildAudioAndFxTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        Text(
          'Background Mode',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _buildChoiceChip(
              context,
              label: 'None',
              selected: _bgMode == 'none',
              onSelected: () => setState(() => _bgMode = 'none'),
            ),
            _buildChoiceChip(
              context,
              label: 'Depth Blur',
              selected: _bgMode == 'blur',
              onSelected: () => setState(() => _bgMode = 'blur'),
            ),
            _buildChoiceChip(
              context,
              label: 'Virtual Image',
              selected: _bgMode == 'image',
              onSelected: () => setState(() => _bgMode = 'image'),
            ),
            _buildChoiceChip(
              context,
              label: 'Green Screen',
              selected: _bgMode == 'green',
              onSelected: () => setState(() => _bgMode = 'green'),
            ),
          ],
        ),

        if (_bgMode == 'blur') ...[
          const SizedBox(height: 12),
          _buildSliderTile(
            context: context,
            title: 'Blur Intensity',
            icon: Icons.blur_on_rounded,
            value: _bgBlurAmount,
            onChanged: (v) {
              setState(() => _bgBlurAmount = v);
              _triggerDebouncedAutoSave();
            },
          ),
        ],

        const SizedBox(height: 18),

        Text(
          'Audio Optimization (LiveKit Native)',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 8),

        _buildSwitchTile(
          context,
          title: 'Noise Suppression',
          subtitle: 'Filters out ambient noise, AC, and fans',
          value: _noiseSuppression,
          onChanged: (v) {
            setState(() => _noiseSuppression = v);
            _triggerDebouncedAutoSave();
          },
        ),
        _buildSwitchTile(
          context,
          title: 'Echo Cancellation',
          subtitle: 'Prevents feedback without headphones',
          value: _echoCancellation,
          onChanged: (v) {
            setState(() => _echoCancellation = v);
            _triggerDebouncedAutoSave();
          },
        ),
        _buildSwitchTile(
          context,
          title: 'Voice Enhancement',
          subtitle: 'Boosts vocal clarity and presence',
          value: _voiceEnhance,
          onChanged: (v) {
            setState(() => _voiceEnhance = v);
            _triggerDebouncedAutoSave();
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 4: Profiles & Scenes Dock
  // ---------------------------------------------------------------------------
  Widget _buildProfilesAndScenesTab(BuildContext context, LiveLooksState liveState) {
    final uid = ref.watch(currentAuthUidProvider);
    final repo = ref.watch(looksRepositoryProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Live Profiles',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            TextButton.icon(
              onPressed: () => _promptSaveProfile(context, uid, repo),
              icon: const Icon(Icons.add, size: 16, color: AppColors.brandBlue),
              label: Text(
                'Save Profile',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandBlue,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        StreamBuilder<List<Map<String, dynamic>>>(
          stream: repo.streamLiveProfiles(uid),
          builder: (ctx, snap) {
            final profiles = snap.data ?? [];
            if (profiles.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No saved profiles yet. Tap "Save Profile" to capture your current settings snapshot.',
                  style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
                ),
              );
            }

            return Column(
              children: profiles.map((pMap) {
                final profile = LiveProfile.fromMap(pMap);
                final isCurrent = liveState.activeProfile?.id == profile.id;

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: isCurrent ? AppColors.brandBlue : context.border,
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.name,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                              ),
                            ),
                            Text(
                              '${profile.resolution} · ${profile.fps} FPS · Beauty ${(profile.beauty.smoothSkin * 100).toInt()}%',
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                color: context.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          ref.read(liveLooksControllerProvider.notifier).applyProfile(profile);
                        },
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 30),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        child: Text(
                          isCurrent ? 'Active' : 'Apply',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isCurrent ? AppColors.brandBlue : context.textSecondary,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        color: Colors.red.withValues(alpha: 0.7),
                        onPressed: () => _confirmDeleteProfile(context, uid, profile.id, repo),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),

        const SizedBox(height: 18),

        // Scenes Dock Section
        Text(
          'Live Scenes Dock (1-Tap Switch)',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        _buildScenesDock(context, uid, repo, liveState),
      ],
    );
  }

  Widget _buildScenesDock(
    BuildContext context,
    String uid,
    LooksRepository repo,
    LiveLooksState liveState,
  ) {
    final defaultScenes = [
      const LiveScene(id: 'scene_main', name: 'Main Camera', order: 1),
      const LiveScene(
        id: 'scene_cinematic',
        name: 'Cinematic Mood',
        order: 2,
        look: OneovaLook(
          name: 'Cinematic Mood',
          primary: LookPrimary(contrast: 1.15, shadows: 0.05),
          color: LookColor(vibrance: 0.2),
        ),
      ),
      const LiveScene(
        id: 'scene_portrait',
        name: 'Close-Up Beauty',
        order: 3,
        beauty: BoostBeautyConfig(smoothSkin: 0.7, eyeBrighten: 0.5),
      ),
    ];

    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: defaultScenes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (ctx, idx) {
          final scene = defaultScenes[idx];
          final isActive = liveState.activeScene?.id == scene.id;

          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              ref.read(liveLooksControllerProvider.notifier).switchScene(scene);
            },
            child: Container(
              width: 105,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.brandBlue.withValues(alpha: 0.15)
                    : context.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: isActive ? AppColors.brandBlue : context.border,
                  width: isActive ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isActive ? Icons.play_circle_fill_rounded : Icons.videocam_outlined,
                    size: 20,
                    color: isActive ? AppColors.brandBlue : context.textSecondary,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    scene.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive ? AppColors.brandBlue : context.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helper Widgets & Dialogs
  // ---------------------------------------------------------------------------
  Widget _buildSliderTile({
    required BuildContext context,
    required String title,
    required IconData icon,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.textSecondary),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: context.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.brandBlue,
                thumbColor: AppColors.brandBlue,
                trackHeight: 3.0,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: value.clamp(0.0, 1.0),
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '${(value * 100).toInt()}%',
              textAlign: TextAlign.end,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
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
          Switch(
            value: value,
            activeThumbColor: AppColors.brandBlue,
            onChanged: (v) {
              HapticFeedback.lightImpact();
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? Colors.white : context.textPrimary,
        ),
      ),
      selected: selected,
      selectedColor: AppColors.brandBlue,
      backgroundColor: context.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        side: BorderSide(
          color: selected ? AppColors.brandBlue : context.border,
          width: 1.0,
        ),
      ),
      onSelected: (_) {
        HapticFeedback.selectionClick();
        onSelected();
      },
    );
  }

  Future<void> _promptSaveProfile(BuildContext context, String uid, LooksRepository repo) async {
    final textController = TextEditingController(text: 'My Live Setup');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text(
          'Save Current Live Profile',
          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: ctx.textPrimary),
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Profile Name',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: GoogleFonts.inter(color: ctx.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            child: Text('Save', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true && uid.isNotEmpty) {
      final name = textController.text.trim().isNotEmpty ? textController.text.trim() : 'Live Setup';
      final id = 'profile_${DateTime.now().millisecondsSinceEpoch}';
      final liveState = ref.read(liveLooksControllerProvider);

      await repo.saveLiveProfile(uid, id, {
        'id': id,
        'name': name,
        'resolution': _selectedResolution,
        'fps': _selectedFps,
        'isHdr': _isHdr,
        'beauty': liveState.beauty.toMap(),
        'lookId': liveState.activeLook.id,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> _confirmDeleteProfile(
    BuildContext context,
    String uid,
    String profileId,
    LooksRepository repo,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text(
          'Delete Live Profile',
          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: ctx.textPrimary),
        ),
        content: Text(
          'Are you sure you want to delete this live profile? This action cannot be undone.',
          style: GoogleFonts.inter(fontSize: 12.5, color: ctx.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: GoogleFonts.inter(color: ctx.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            child: Text('Delete', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true && uid.isNotEmpty) {
      await repo.deleteLiveProfile(uid, profileId);
    }
  }
}
