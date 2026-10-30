import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../looks/device/models/surface_ceiling.dart';
import '../../looks/device/providers/device_providers.dart';
import '../../shared/theme/app_theme.dart';

/// Camera & Live Settings screen with Device Advisor safe ceilings,
/// live thermal state HUD, and the safeguarded Pro Override toggle.
class CameraAndLiveSettingsScreen extends ConsumerStatefulWidget {
  const CameraAndLiveSettingsScreen({super.key});

  @override
  ConsumerState<CameraAndLiveSettingsScreen> createState() =>
      _CameraAndLiveSettingsScreenState();
}

class _CameraAndLiveSettingsScreenState
    extends ConsumerState<CameraAndLiveSettingsScreen> {
  bool _isReRunningBenchmark = false;

  Future<void> _handleReRunBenchmark() async {
    setState(() => _isReRunningBenchmark = true);
    try {
      final caps = await ref.read(hardwareCapabilitiesProvider.future);
      final benchmarkService = ref.read(deviceBenchmarkServiceProvider);
      await benchmarkService.runBenchmark(capabilities: caps, force: true);
      ref.invalidate(deviceBenchmarkResultProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.brandBlue,
            content: Text(
              'Benchmark recalibration complete!',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.brandPink,
            content: Text(
              'Benchmark failed: $e',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isReRunningBenchmark = false);
      }
    }
  }

  Future<void> _handleToggleProOverride(bool currentValue) async {
    HapticFeedback.lightImpact();

    if (currentValue) {
      // Disabling does not require a scary prompt
      await ref.read(proOverrideProvider.notifier).setOverride(false);
      return;
    }

    // Enabling requires mandatory confirmation dialog safeguard
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: ctx.border, width: 1.0),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.brandPink, size: 22),
            const SizedBox(width: 8),
            Text(
              'Enable Pro Override?',
              style: GoogleFonts.inter(
                fontSize: 16.0,
                fontWeight: FontWeight.w700,
                color: ctx.textPrimary,
              ),
            ),
          ],
        ),
        content: Text(
          'Pro override allows you to bypass the Device Advisor recommended safe ceilings.\n\n'
          'Running settings beyond your hardware limits (e.g. 4K60 Live on unsupported tiers) '
          'may cause severe thermal throttling, frame stutter, and rapid battery depletion.\n\n'
          'The Thermal Governor will continue active background protection and will step down quality '
          'if critical temperatures are reached.\n\n'
          'Proceed at your own risk?',
          style: GoogleFonts.inter(
            fontSize: 12.5,
            height: 1.45,
            color: ctx.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontSize: 13.0,
                fontWeight: FontWeight.w600,
                color: ctx.textMuted,
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Enable (At Own Risk)',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(proOverrideProvider.notifier).setOverride(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final advisor = ref.watch(deviceAdvisorProvider);
    final benchmarkAsync = ref.watch(deviceBenchmarkResultProvider);
    final thermalSnap = ref.watch(thermalGovernorProvider).currentSnapshot;
    final isProOverride = ref.watch(proOverrideProvider);
    final enforcement = ref.watch(advisorEnforcementProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Camera & Live Settings',
              style: GoogleFonts.inter(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            Text(
              'Device intelligence & thermal governor',
              style: GoogleFonts.inter(
                fontSize: 11.0,
                color: context.textMuted,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Live Studio: everything for going live, side by side.
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: context.border),
            ),
            child: Column(children: [
              for (final (icon, title, subtitle, route) in const [
                (Icons.sensors_rounded, 'Go live', 'Setup wizard: mode, layout, audience', '/live/setup'),
                (Icons.cell_tower_rounded, 'Live destinations', 'Restream to Facebook, YouTube, TikTok…', '/settings/live_destinations'),
                (Icons.video_library_rounded, 'Live recordings', 'Your saved 1080p lives', '/settings/live_recordings'),
              ])
                ListTile(
                  leading: Icon(icon, color: AppColors.brandBlue),
                  title: Text(title,
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary)),
                  subtitle: Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: context.textMuted)),
                  trailing: Icon(Icons.chevron_right_rounded, color: context.textMuted),
                  onTap: () => context.push(route),
                ),
            ]),
          ),
          // Pro Override Active Warning Banner
          if (isProOverride) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.brandPink.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.5), width: 1.0),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.brandPink, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PRO OVERRIDE ACTIVE',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: AppColors.brandPink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Hardware ceilings bypassed. Thermal Governor active protection is safeguarding against emergency overheating.',
                          style: GoogleFonts.inter(
                            fontSize: 11.0,
                            color: context.textPrimary,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 250.ms),
            const SizedBox(height: 14),
          ],

          // 1. Pro Override Toggle Card
          _buildSectionHeader('ADVANCED CONTROLS'),
          Container(
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border, width: 1.0),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Pro override, at your own risk',
                                style: GoogleFonts.inter(
                                  fontSize: 13.0,
                                  fontWeight: FontWeight.w700,
                                  color: context.textPrimary,
                                ),
                              ),
                              if (isProOverride) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.brandPink,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'ACTIVE',
                                    style: GoogleFonts.inter(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Bypass Device Advisor safe ceilings. Thermal Governor will step down only on critical thermal spikes.',
                            style: GoogleFonts.inter(
                              fontSize: 11.0,
                              color: context.textMuted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch.adaptive(
                      value: isProOverride,
                      activeTrackColor: AppColors.brandPink,
                      onChanged: (val) => _handleToggleProOverride(isProOverride),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 2. Hardware Capabilities & Benchmark Card
          _buildSectionHeader('HARDWARE INTELLIGENCE'),
          Container(
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border, width: 1.0),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          advisor.capabilities.model,
                          style: GoogleFonts.inter(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ),
                        ),
                        Text(
                          '${advisor.capabilities.socModel} · ${advisor.capabilities.totalRamGb.toStringAsFixed(1)} GB RAM',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.brandBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.brandBlue, width: 1.0),
                      ),
                      child: Text(
                        advisor.effectiveTier.label,
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandBlue,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: context.border),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        label: 'BENCHMARK SCORE',
                        value: benchmarkAsync.maybeWhen(
                          data: (b) => '${b.performanceScore.toStringAsFixed(1)} / 100',
                          orElse: () => 'Measuring...',
                        ),
                        subtext: benchmarkAsync.maybeWhen(
                          data: (b) => '${b.medianFrameMsTier2} ms / frame',
                          orElse: () => '',
                        ),
                      ),
                    ),
                    Expanded(
                      child: _buildMetricTile(
                        label: 'THERMAL SLOPE',
                        value: benchmarkAsync.maybeWhen(
                          data: (b) => '${(b.thermalSlope * 100).toStringAsFixed(2)} %/s',
                          orElse: () => '—',
                        ),
                        subtext: 'Sustained load slope',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 36,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: context.border, width: 1.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                    onPressed: _isReRunningBenchmark ? null : _handleReRunBenchmark,
                    icon: _isReRunningBenchmark
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(
                      _isReRunningBenchmark ? 'Calibrating...' : 'Recalibrate Benchmark (5s)',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 3. Safe Ceilings per Surface Card
          _buildSectionHeader('DEVICE ADVISOR CEILINGS'),
          Container(
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Column(
              children: [
                _buildCeilingTile(
                  surface: SurfaceType.live,
                  ceiling: advisor.liveCeiling,
                  icon: Icons.podcasts_rounded,
                  showDivider: true,
                ),
                _buildCeilingTile(
                  surface: SurfaceType.camera,
                  ceiling: advisor.cameraCeiling,
                  icon: Icons.videocam_rounded,
                  showDivider: true,
                ),
                _buildCeilingTile(
                  surface: SurfaceType.editor,
                  ceiling: advisor.editorCeiling,
                  icon: Icons.tune_rounded,
                  showDivider: false,
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 4. Live Thermal State HUD
          _buildSectionHeader('THERMAL GOVERNOR HUD'),
          Container(
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border, width: 1.0),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.thermostat_rounded,
                          color: thermalSnap.isSerious
                              ? AppColors.brandPink
                              : (thermalSnap.headroom >= 0.75 ? Colors.amber : AppColors.brandBlue),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Thermal Headroom',
                          style: GoogleFonts.inter(
                            fontSize: 13.0,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${(thermalSnap.headroom * 100).toInt()}%',
                      style: GoogleFonts.inter(
                        fontSize: 14.0,
                        fontWeight: FontWeight.w800,
                        color: thermalSnap.isSerious ? AppColors.brandPink : context.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: thermalSnap.headroom.clamp(0.0, 1.2) / 1.2,
                    minHeight: 6,
                    backgroundColor: context.surfaceMid,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      thermalSnap.isCritical
                          ? AppColors.brandPink
                          : (thermalSnap.headroom >= 0.85 ? Colors.amber : AppColors.brandBlue),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Mitigation Level: Tier ${thermalSnap.activeMitigationTier} '
                      '${thermalSnap.activeMitigationTier == 0 ? "(Full Quality)" : "(Throttled)"}',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: context.textSecondary,
                      ),
                    ),
                    Text(
                      'Enforcement: ${enforcement.name.toUpperCase()}',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandBlue,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: AppColors.brandBlue,
        ),
      ),
    );
  }

  Widget _buildMetricTile({required String label, required String value, required String subtext}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: context.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        if (subtext.isNotEmpty)
          Text(
            subtext,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              color: context.textSecondary,
            ),
          ),
      ],
    );
  }

  Widget _buildCeilingTile({
    required SurfaceType surface,
    required SurfaceCeiling ceiling,
    required IconData icon,
    required bool showDivider,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, color: AppColors.brandBlue, size: 17),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      surface.label,
                      style: GoogleFonts.inter(
                        fontSize: 13.0,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Max: ${ceiling.maxWidth}x${ceiling.maxHeight} @ ${ceiling.maxFps}fps · '
                      'Beauty: ${(ceiling.maxBeautyLevel * 100).toInt()}% · ML: ${ceiling.maxSegmentationFps}fps',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, indent: 56, endIndent: 14, color: context.border),
      ],
    );
  }
}
