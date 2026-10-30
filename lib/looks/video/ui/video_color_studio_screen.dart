import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../../ai/scopes/models/scope_frame_data.dart';
import '../../ai/scopes/widgets/waveform_scope.dart';
import '../../ai/scopes/widgets/rgb_parade_scope.dart';
import '../../ai/scopes/widgets/vectorscope.dart';
import '../../ai/scopes/widgets/histogram_scope.dart';
import '../../ai/widgets/conversational_grader_sheet.dart';
import '../../ai/controllers/conversational_grader_controller.dart';
import '../../photo/models/photo_grading_models.dart';
import '../controllers/video_color_timeline_controller.dart';
import '../widgets/video_timeline_strip.dart';
import '../widgets/shot_match_dialog.dart';
import '../widgets/video_export_dialog.dart';

/// Professional Video Color Grading Workstation.
///
/// Multi-clip timeline grading with adjustment layers, keyframe interpolation,
/// AI Shot Matching, tracked Boost Beauty, GPU scopes, and hardware-accelerated export.
class VideoColorStudioScreen extends ConsumerStatefulWidget {
  final String sequenceTitle;

  const VideoColorStudioScreen({
    super.key,
    this.sequenceTitle = 'Main Timeline Sequence',
  });

  @override
  ConsumerState<VideoColorStudioScreen> createState() => _VideoColorStudioScreenState();
}

class _VideoColorStudioScreenState extends ConsumerState<VideoColorStudioScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoColorTimelineControllerProvider);
    final controller = ref.read(videoColorTimelineControllerProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.outline : AppColors.lightBorder;
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final textMuted = isDark ? AppColors.textMuted : AppColors.lightTextMuted;

    final activeClip = state.activeClip;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(52.0),
        child: AppBar(
          backgroundColor: surfaceColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          titleSpacing: 0,
          title: Text(
            widget.sequenceTitle,
            style: GoogleFonts.inter(
              fontSize: 15.0,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          actions: [
            // Scopes toggle
            IconButton(
              icon: Icon(
                Icons.analytics_outlined,
                size: 20,
                color: state.isScopesVisible ? AppColors.brandBlue : textMuted,
              ),
              tooltip: 'Scopes',
              onPressed: () {
                HapticFeedback.selectionClick();
                controller.toggleScopes();
              },
            ),

            // AI Shot Match button
            IconButton(
              icon: const Icon(Icons.compare_arrows_rounded, size: 20, color: AppColors.brandBlue),
              tooltip: 'Shot Matcher',
              onPressed: () {
                HapticFeedback.lightImpact();
                showDialog(context: context, builder: (_) => const ShotMatchDialog());
              },
            ),

            // AI Color Grader
            IconButton(
              icon: const Icon(Icons.auto_awesome_rounded, size: 20, color: AppColors.brandPink),
              tooltip: 'AI Color Grader',
              onPressed: () => _openAiGraderSheet(state, controller),
            ),

            // Export button
            Padding(
              padding: const EdgeInsets.only(right: 12.0, left: 4.0),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.file_upload_outlined, size: 16),
                label: Text(
                  'Export',
                  style: GoogleFonts.inter(fontSize: 12.0, fontWeight: FontWeight.w700),
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  showDialog(context: context, builder: (_) => const VideoExportDialog());
                },
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Center Video Monitor Canvas
            Expanded(
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: isDark ? const Color(0xFF0A0A0A) : const Color(0xFF0F172A),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.movie_creation_outlined, size: 52, color: Colors.white24),
                        const SizedBox(height: 10),
                        Text(
                          activeClip != null ? activeClip.clipName : 'No Active Clip',
                          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.white70),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Grade: ${state.effectiveLook.name}',
                          style: GoogleFonts.inter(fontSize: 12.0, fontWeight: FontWeight.w700, color: AppColors.brandPink),
                        ),
                      ],
                    ),
                  ),

                  // Timecode & Tracked Beauty overlay badge
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(6.0),
                            border: Border.all(color: Colors.white24, width: 1.0),
                          ),
                          child: Text(
                            'PLAYHEAD: ${state.playheadSeconds.toStringAsFixed(2)}s',
                            style: GoogleFonts.inter(
                              fontSize: 10.0,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (activeClip != null && activeClip.isTrackedBeautyEnabled) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.brandPink.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(6.0),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.face_retouching_natural_rounded, size: 12, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  'TRACKED BEAUTY',
                                  style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Floating GPU Scopes Overlay
                  if (state.isScopesVisible)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: _buildScopesOverlay(state, controller, isDark),
                    ),
                ],
              ),
            ),

            // Timeline Strip
            VideoTimelineStrip(
              clips: state.clips,
              activeClipId: state.activeClipId,
              adjustmentLayers: state.adjustmentLayers,
              playheadSeconds: state.playheadSeconds,
              onClipSelected: (clipId) => controller.selectClip(clipId),
              onPlayheadChanged: (sec) => controller.setPlayhead(sec),
            ),

            // Lower Clip Inspector & Color Controls
            if (activeClip != null)
              Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  border: Border(top: BorderSide(color: borderColor, width: 1.0)),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Clip Quick Action Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              activeClip.clipName,
                              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: textPrimary),
                            ),
                            const SizedBox(width: 8),
                            ActionChip(
                              label: Text(
                                activeClip.isBypassed ? 'BYPASSED' : 'ACTIVE',
                                style: GoogleFonts.inter(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: activeClip.isBypassed ? textMuted : Colors.green,
                                ),
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                controller.toggleActiveClipBypass();
                              },
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                              tooltip: 'Add Keyframe at Playhead',
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                controller.addKeyframeToActiveClip(
                                  timeSeconds: state.playheadSeconds - activeClip.startTimeSeconds,
                                  look: state.effectiveLook,
                                );
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.face_retouching_natural_rounded,
                                size: 18,
                                color: activeClip.isTrackedBeautyEnabled ? AppColors.brandPink : textMuted,
                              ),
                              tooltip: 'Toggle Tracked Boost Beauty',
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                controller.setTrackedBeauty(isEnabled: !activeClip.isTrackedBeautyEnabled);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Macro Sliders for Active Clip Grade
                    _buildSlider(
                      label: 'Grade Intensity',
                      value: activeClip.masterIntensity,
                      min: 0.0,
                      max: 1.0,
                      display: '${(activeClip.masterIntensity * 100).toInt()}%',
                      activeColor: AppColors.brandBlue,
                      onChanged: (v) => controller.updateActiveClipIntensity(v),
                    ),
                    _buildSlider(
                      label: 'Exposure',
                      value: state.effectiveLook.primary.exposure,
                      min: -2.0,
                      max: 2.0,
                      display: '${state.effectiveLook.primary.exposure.toStringAsFixed(2)} EV',
                      activeColor: AppColors.brandPink,
                      onChanged: (v) {
                        controller.updateActiveClipLook(
                          state.effectiveLook.copyWith(
                            primary: state.effectiveLook.primary.copyWith(exposure: v),
                          ),
                        );
                      },
                    ),
                    _buildSlider(
                      label: 'Warmth',
                      value: state.effectiveLook.color.temperature,
                      min: -100.0,
                      max: 100.0,
                      display: '${state.effectiveLook.color.temperature.toInt()}',
                      activeColor: Colors.amberAccent,
                      onChanged: (v) {
                        controller.updateActiveClipLook(
                          state.effectiveLook.copyWith(
                            color: state.effectiveLook.color.copyWith(temperature: v),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScopesOverlay(VideoColorTimelineState state, VideoColorTimelineController controller, bool isDark) {
    final scopeData = ScopeFrameData.fromLook(state.effectiveLook);

    return Container(
      width: 170,
      height: 120,
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xEE121212) : const Color(0xEEFFFFFF),
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.5), width: 1.0),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                state.activeScopeType.name.toUpperCase(),
                style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.brandBlue),
              ),
              GestureDetector(
                onTap: () {
                  final next = switch (state.activeScopeType) {
                    ScopeType.waveform => ScopeType.rgbParade,
                    ScopeType.rgbParade => ScopeType.vectorscope,
                    ScopeType.vectorscope => ScopeType.histogram,
                    ScopeType.histogram => ScopeType.waveform,
                  };
                  controller.toggleScopes(visible: true, type: next);
                },
                child: const Icon(Icons.swap_horiz_rounded, size: 14, color: AppColors.brandBlue),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: switch (state.activeScopeType) {
              ScopeType.waveform => WaveformScope(data: scopeData),
              ScopeType.rgbParade => RgbParadeScope(data: scopeData),
              ScopeType.vectorscope => Vectorscope(data: scopeData),
              ScopeType.histogram => HistogramScope(data: scopeData),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String display,
    required Color activeColor,
    required ValueChanged<double> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final textMuted = isDark ? AppColors.textMuted : AppColors.lightTextMuted;

    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(label, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w500, color: textPrimary)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
              activeTrackColor: activeColor,
              inactiveTrackColor: isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0),
              thumbColor: activeColor,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                onChanged(v);
              },
            ),
          ),
        ),
        SizedBox(
          width: 55,
          child: Text(display, textAlign: TextAlign.end, style: GoogleFonts.inter(fontSize: 11.0, fontWeight: FontWeight.w600, color: textMuted)),
        ),
      ],
    );
  }

  void _openAiGraderSheet(VideoColorTimelineState state, VideoColorTimelineController controller) {
    HapticFeedback.mediumImpact();
    ref.read(conversationalGraderControllerProvider.notifier).setActiveLook(state.effectiveLook);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ConversationalGraderSheet(
          onClose: () {
            final aiLook = ref.read(conversationalGraderControllerProvider).activeLook;
            controller.updateActiveClipLook(aiLook);
            Navigator.of(context).pop();
          },
        );
      },
    ).then((_) {
      final aiLook = ref.read(conversationalGraderControllerProvider).activeLook;
      controller.updateActiveClipLook(aiLook);
    });
  }
}
