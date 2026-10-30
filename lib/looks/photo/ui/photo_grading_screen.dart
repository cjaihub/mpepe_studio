import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../../ai/models/scope_sentinel_alert.dart';
import '../../ai/scopes/models/scope_frame_data.dart';
import '../../ai/scopes/widgets/waveform_scope.dart';
import '../../ai/scopes/widgets/rgb_parade_scope.dart';
import '../../ai/scopes/widgets/vectorscope.dart';
import '../../ai/scopes/widgets/histogram_scope.dart';
import '../../ai/scopes/widgets/scope_sentinel_banner.dart';
import '../../ai/widgets/conversational_grader_sheet.dart';
import '../../ai/controllers/conversational_grader_controller.dart';
import '../controllers/photo_grading_controller.dart';
import '../models/photo_grading_models.dart';
import '../widgets/photo_simple_grading_deck.dart';
import '../widgets/photo_pro_nodes_deck.dart';
import '../widgets/photo_batch_dialog.dart';

/// Oneova Professional Photo Color Grading Studio.
///
/// Dual-theme executive UI offering Simple and Pro grading workflows,
/// real-time GPU scopes, Scope Sentinel monitoring, AI conversational grading,
/// batch application, and original-resolution export.
class PhotoGradingScreen extends ConsumerStatefulWidget {
  final String? initialImagePath;

  const PhotoGradingScreen({
    super.key,
    this.initialImagePath,
  });

  @override
  ConsumerState<PhotoGradingScreen> createState() => _PhotoGradingScreenState();
}

class _PhotoGradingScreenState extends ConsumerState<PhotoGradingScreen> {
  ScopeSentinelAlert? _activeAlert;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialImagePath != null) {
        ref.read(photoGradingControllerProvider.notifier).setPhoto(
              path: widget.initialImagePath!,
            );
      }
      _evaluateTelemetryAlert();
    });
  }

  void _evaluateTelemetryAlert() {
    final look = ref.read(photoGradingControllerProvider).currentLook;
    if (look.primary.exposure > 1.2 || look.primary.highlights > 0.8) {
      setState(() {
        _activeAlert = ScopeSentinelAlert(
          id: 'alert_blown_hl',
          type: SentinelAlertType.blownHighlights,
          severity: SentinelSeverity.warning,
          headline: 'Blown Highlights Detected',
          description: 'Highlights exceed 98 IRE. Tap Fix to pull down gain and highlights.',
          suggestedFixLabel: 'Recover Highlights',
          applyFix: (cur) => cur.copyWith(
            primary: cur.primary.copyWith(
              exposure: cur.primary.exposure - 0.25,
              highlights: cur.primary.highlights - 0.35,
            ),
          ),
          timestamp: DateTime.now(),
        );
      });
    } else {
      if (_activeAlert != null) {
        setState(() => _activeAlert = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(photoGradingControllerProvider);
    final controller = ref.read(photoGradingControllerProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textMuted = isDark ? AppColors.textMuted : AppColors.lightTextMuted;

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
            'Photo Grading',
            style: GoogleFonts.inter(
              fontSize: 15.0,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
            ),
          ),
          actions: [
            // Scopes toggle button
            IconButton(
              icon: Icon(
                Icons.analytics_outlined,
                size: 20,
                color: state.isScopesVisible ? AppColors.brandBlue : textMuted,
              ),
              tooltip: 'Toggle Scopes',
              onPressed: () {
                HapticFeedback.selectionClick();
                controller.toggleScopes();
              },
            ),

            // AI Grader button
            IconButton(
              icon: const Icon(
                Icons.auto_awesome_rounded,
                size: 20,
                color: AppColors.brandPink,
              ),
              tooltip: 'AI Color Grader',
              onPressed: () => _openAiGraderSheet(state, controller),
            ),

            // Batch apply button
            IconButton(
              icon: const Icon(Icons.photo_library_outlined, size: 20),
              tooltip: 'Batch Grading',
              onPressed: () => _openBatchDialog(context),
            ),

            // Export button
            Padding(
              padding: const EdgeInsets.only(right: 12.0, left: 4.0),
              child: state.isExporting
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.0, color: AppColors.brandBlue),
                      ),
                    )
                  : ElevatedButton.icon(
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
                      onPressed: () => _handleExport(controller),
                    ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Mode & Status Toolbar
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: surfaceColor,
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? AppColors.outline : AppColors.lightBorder,
                    width: 1.0,
                  ),
                ),
              ),
              child: Row(
                children: [
                  _buildModeToggle(state, controller, isDark),
                  const SizedBox(width: 12),
                  if (state.statusMessage != null)
                    Expanded(
                      child: Text(
                        state.statusMessage!,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 11.0, color: textMuted),
                      ),
                    ),
                ],
              ),
            ),

            // Center Viewport
            Expanded(
              child: Stack(
                children: [
                  // Main Photo Canvas with A/B Compare gesture
                  GestureDetector(
                    onLongPressStart: (_) {
                      HapticFeedback.lightImpact();
                      controller.setComparing(true);
                    },
                    onLongPressEnd: (_) {
                      HapticFeedback.lightImpact();
                      controller.setComparing(false);
                    },
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      color: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF1F5F9),
                      alignment: Alignment.center,
                      child: _buildPhotoPreview(state, isDark),
                    ),
                  ),

                  // A/B Comparison Pill
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: state.isComparing
                            ? Colors.black87
                            : AppColors.brandBlue.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(6.0),
                        border: Border.all(color: Colors.white24, width: 1.0),
                      ),
                      child: Text(
                        state.isComparing ? 'ORIGINAL (HOLDING)' : 'GRADED',
                        style: GoogleFonts.inter(
                          fontSize: 10.0,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  // Scope Sentinel Alert Banner
                  if (_activeAlert != null)
                    Positioned(
                      top: 12,
                      right: 12,
                      left: 140,
                      child: ScopeSentinelBanner(
                        alert: _activeAlert!,
                        onDismiss: () => setState(() => _activeAlert = null),
                        onApplyFix: () {
                          HapticFeedback.mediumImpact();
                          final fixedLook = _activeAlert!.applyFix(state.currentLook);
                          controller.setLook(fixedLook);
                          setState(() => _activeAlert = null);
                        },
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

            // Bottom Grading Deck (Simple or Pro)
            if (state.mode == PhotoGradingMode.simple)
              PhotoSimpleGradingDeck(state: state)
            else
              PhotoProNodesDeck(state: state),
          ],
        ),
      ),
    );
  }

  Widget _buildModeToggle(PhotoGradingState state, PhotoGradingController controller, bool isDark) {
    return Container(
      height: 32,
      padding: const EdgeInsets.all(2.0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleOption(
            label: 'Simple',
            isSelected: state.mode == PhotoGradingMode.simple,
            onTap: () {
              HapticFeedback.selectionClick();
              controller.setMode(PhotoGradingMode.simple);
            },
          ),
          _buildToggleOption(
            label: 'Pro Nodes',
            isSelected: state.mode == PhotoGradingMode.pro,
            onTap: () {
              HapticFeedback.selectionClick();
              controller.setMode(PhotoGradingMode.pro);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildToggleOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(6.0),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoPreview(PhotoGradingState state, bool isDark) {
    if (state.activePhoto == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_size_select_actual_outlined, size: 56, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            'Ready to Grade Photo',
            style: GoogleFonts.inter(fontSize: 14.0, fontWeight: FontWeight.w600, color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            'Import a high-resolution photo or select from library',
            style: GoogleFonts.inter(fontSize: 12.0, color: AppColors.textMuted),
          ),
        ],
      );
    }

    final file = File(state.activePhoto!.path);
    if (!file.existsSync()) {
      return Center(
        child: Text(
          'Photo file not found: ${state.activePhoto!.path}',
          style: GoogleFonts.inter(fontSize: 12.0, color: Colors.redAccent),
        ),
      );
    }

    return Image.file(
      file,
      fit: BoxFit.contain,
    );
  }

  Widget _buildScopesOverlay(PhotoGradingState state, PhotoGradingController controller, bool isDark) {
    final scopeData = ScopeFrameData.fromLook(state.currentLook);

    return Container(
      width: 170,
      height: 120,
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xEE121212) : const Color(0xEEFFFFFF),
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.5), width: 1.0),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4)),
        ],
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

  void _openAiGraderSheet(PhotoGradingState state, PhotoGradingController controller) {
    HapticFeedback.mediumImpact();
    ref.read(conversationalGraderControllerProvider.notifier).setActiveLook(state.currentLook);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ConversationalGraderSheet(
          onClose: () {
            final aiLook = ref.read(conversationalGraderControllerProvider).activeLook;
            controller.setLook(aiLook);
            Navigator.of(context).pop();
          },
        );
      },
    ).then((_) {
      final aiLook = ref.read(conversationalGraderControllerProvider).activeLook;
      controller.setLook(aiLook);
    });
  }

  void _openBatchDialog(BuildContext context) {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (_) => const PhotoBatchDialog(),
    );
  }

  Future<void> _handleExport(PhotoGradingController controller) async {
    HapticFeedback.heavyImpact();
    try {
      final res = await controller.exportCurrentPhoto();
      if (mounted && res != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Exported at native resolution ${res.outputWidth}x${res.outputHeight}',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white),
            ),
            backgroundColor: AppColors.brandBlue,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e', style: GoogleFonts.inter(color: Colors.white)),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
