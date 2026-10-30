import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/theme/app_theme.dart';
import '../controllers/cloud_vision_controller.dart';
import '../models/cloud_vision_models.dart';
import '../widgets/ai_enhance_sheet.dart';
import '../widgets/relight_sheet.dart';
import '../widgets/rotoscope_prompt_sheet.dart';
import '../widgets/sky_replacement_sheet.dart';

/// Full-featured Cloud Vision GPU Studio Screen.
/// Provides:
/// - Natural language and interactive rotoscoping with SAM 2
/// - Neural upscale (2x/4x), denoise, and 60FPS frame interpolation
/// - 3D key/fill relighting with normal map estimation
/// - AI sky replacement with atmospheric spill harmonization
/// - Real-time progress HUD, A/B wipe comparison, and daily credit quotas
class CloudVisionStudioScreen extends ConsumerWidget {
  final String videoUrl;
  final String userId;

  const CloudVisionStudioScreen({
    super.key,
    this.videoUrl = 'https://storage.googleapis.com/oneova-sample-media/cinema_take_01.mp4',
    this.userId = 'user_studio_pro',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cloudVisionControllerProvider);
    final notifier = ref.read(cloudVisionControllerProvider.notifier);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Cloud Vision AI',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        actions: [
          // Cloud GPU Quota Badge
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: state.quota.hasRemainingQuota
                  ? AppColors.brandBlue.withValues(alpha: 0.12)
                  : Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: state.quota.hasRemainingQuota
                    ? AppColors.brandBlue.withValues(alpha: 0.3)
                    : Colors.red.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_done_rounded,
                  size: 13,
                  color: state.quota.hasRemainingQuota ? AppColors.brandBlue : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  '${state.quota.jobsRemaining}/${state.quota.dailyBudgetJobs} Credits',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: state.quota.hasRemainingQuota ? AppColors.brandBlue : Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Subheader: Task Selector Tabs
            _buildTaskSelector(context, state, notifier),

            // Error banner if any
            if (state.errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.red.withValues(alpha: 0.15),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 16, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        style: const TextStyle(fontSize: 11.5, color: Colors.red, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),

            // Main Monitor / Viewport
            Expanded(
              child: _buildCanvasMonitor(context, state, notifier),
            ),

            // Bottom Configuration Deck
            Container(
              decoration: BoxDecoration(
                color: context.surface,
                border: Border(top: BorderSide(color: context.border, width: 1.0)),
              ),
              padding: const EdgeInsets.all(14),
              child: _buildActiveTaskSheet(state, notifier),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskSelector(
    BuildContext context,
    CloudVisionState state,
    CloudVisionController notifier,
  ) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(bottom: BorderSide(color: context.border, width: 1.0)),
      ),
      child: Row(
        children: [
          _buildTabItem(context, 'Rotoscope', VisionTaskType.rotoscope, state, notifier),
          _buildTabItem(context, 'AI Enhance', VisionTaskType.enhance, state, notifier),
          _buildTabItem(context, 'Relight 3D', VisionTaskType.relight, state, notifier),
          _buildTabItem(context, 'Sky Replace', VisionTaskType.skyReplace, state, notifier),
        ],
      ),
    );
  }

  Widget _buildTabItem(
    BuildContext context,
    String label,
    VisionTaskType task,
    CloudVisionState state,
    CloudVisionController notifier,
  ) {
    final isSelected = state.activeTask == task;
    return Expanded(
      child: GestureDetector(
        onTap: () => notifier.selectTask(task),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.brandBlue.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? AppColors.brandBlue : Colors.transparent,
              width: 1.0,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? AppColors.brandBlue : context.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCanvasMonitor(
    BuildContext context,
    CloudVisionState state,
    CloudVisionController notifier,
  ) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Base Simulated Frame Canvas
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.videocam_rounded,
                  size: 48,
                  color: context.textMuted.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 8),
                Text(
                  '4K Source Timeline Monitor',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  '3840x2160 • 10-bit Rec.709',
                  style: TextStyle(fontSize: 10, color: context.textMuted),
                ),
              ],
            ),
          ),

          // Visual Overlay Indicators
          if (state.activeTask == VisionTaskType.rotoscope && state.activeOutputUrl != null)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.6), width: 3),
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.brandPink,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'SAM 2 MASK ACTIVE',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ),
            ),

          if (state.activeTask == VisionTaskType.skyReplace && state.activeOutputUrl != null)
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                height: 70,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.brandBlue.withValues(alpha: 0.4),
                      Colors.transparent,
                    ],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Sky Matched: ${state.selectedSky.name}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),

          // Processing HUD overlay
          if (state.isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.65),
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.brandBlue),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Processing on Cloud Run GPU...',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${(state.currentProgress * 100).toInt()}% completed',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: state.currentProgress,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation(AppColors.brandBlue),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: notifier.cancelCurrentJob,
                    icon: const Icon(Icons.close_rounded, size: 14, color: Colors.white70),
                    label: const Text('Cancel Task', style: TextStyle(fontSize: 11, color: Colors.white70)),
                  ),
                ],
              ),
            ),

          // Hold to Compare A/B Button
          Positioned(
            right: 12,
            bottom: 12,
            child: GestureDetector(
              onTapDown: (_) => notifier.toggleCompareSplitView(true),
              onTapUp: (_) => notifier.toggleCompareSplitView(false),
              onTapCancel: () => notifier.toggleCompareSplitView(false),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.compare_rounded, size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      state.compareSplitView ? 'Original' : 'Hold Compare',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTaskSheet(
    CloudVisionState state,
    CloudVisionController notifier,
  ) {
    switch (state.activeTask) {
      case VisionTaskType.rotoscope:
        return RotoscopePromptSheet(
          onExecute: () => notifier.executeCurrentTask(videoUrl: videoUrl, userId: userId),
        );
      case VisionTaskType.enhance:
        return AiEnhanceSheet(
          onExecute: () => notifier.executeCurrentTask(videoUrl: videoUrl, userId: userId),
        );
      case VisionTaskType.relight:
        return RelightSheet(
          onExecute: () => notifier.executeCurrentTask(videoUrl: videoUrl, userId: userId),
        );
      case VisionTaskType.skyReplace:
        return SkyReplacementSheet(
          onExecute: () => notifier.executeCurrentTask(videoUrl: videoUrl, userId: userId),
        );
    }
  }
}
