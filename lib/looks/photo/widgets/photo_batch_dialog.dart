import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../controllers/photo_grading_controller.dart';
import '../models/photo_grading_models.dart';

/// Modal dialog for managing and executing batch grading across multiple photos.
class PhotoBatchDialog extends ConsumerStatefulWidget {
  const PhotoBatchDialog({super.key});

  @override
  ConsumerState<PhotoBatchDialog> createState() => _PhotoBatchDialogState();
}

class _PhotoBatchDialogState extends ConsumerState<PhotoBatchDialog> {
  final TextEditingController _pathInputController = TextEditingController();
  BatchGradingReport? _lastReport;

  @override
  void dispose() {
    _pathInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(photoGradingControllerProvider);
    final controller = ref.read(photoGradingControllerProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.outline : AppColors.lightBorder;
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final textMuted = isDark ? AppColors.textMuted : AppColors.lightTextMuted;

    return Dialog(
      backgroundColor: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(color: borderColor, width: 1.0),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: const Icon(Icons.photo_library_rounded, size: 20, color: AppColors.brandBlue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Batch Photo Grading',
                        style: GoogleFonts.inter(
                          fontSize: 16.0,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        'Apply "${state.currentLook.name}" across queued photos',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 24),

            // Queue count and action bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Queued Photos (${state.batchQueue.length})',
                  style: GoogleFonts.inter(
                    fontSize: 13.0,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                if (state.batchQueue.isNotEmpty)
                  TextButton(
                    onPressed: state.isExporting ? null : () => controller.clearBatchQueue(),
                    child: Text(
                      'Clear Queue',
                      style: GoogleFonts.inter(fontSize: 12.0, color: Colors.redAccent),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Queued list
            Expanded(
              child: state.batchQueue.isEmpty
                  ? Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight,
                        borderRadius: BorderRadius.circular(10.0),
                        border: Border.all(color: borderColor, width: 1.0),
                      ),
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 36, color: textMuted),
                          const SizedBox(height: 8),
                          Text(
                            'No photos in batch queue',
                            style: GoogleFonts.inter(fontSize: 13.0, fontWeight: FontWeight.w600, color: textPrimary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add photos below to apply this grade in one batch',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(fontSize: 11.5, color: textMuted),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: state.batchQueue.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final path = state.batchQueue[index];
                        final filename = path.split('/').last;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight,
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(color: borderColor, width: 1.0),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.image_outlined, size: 18, color: AppColors.brandBlue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  filename,
                                  style: GoogleFonts.inter(fontSize: 12.0, fontWeight: FontWeight.w500, color: textPrimary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline_rounded, size: 18, color: Colors.redAccent),
                                onPressed: state.isExporting ? null : () => controller.removeFromBatchQueue(path),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),

            // Success Report Banner
            if (_lastReport != null) ...[
              Container(
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: Colors.green, width: 1.0),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Completed: ${_lastReport!.successCount}/${_lastReport!.totalCount} photos graded in ${_lastReport!.totalDuration.inMilliseconds}ms',
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Progress bar if batch is running
            if (state.isExporting) ...[
              LinearProgressIndicator(
                value: state.exportProgress > 0 ? state.exportProgress : null,
                backgroundColor: isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.brandBlue),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 6),
              Text(
                state.statusMessage ?? 'Processing batch...',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.brandBlue, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
            ],

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: borderColor, width: 1.0),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      'Add Active Photo',
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    onPressed: state.activePhoto != null && !state.isExporting
                        ? () {
                            HapticFeedback.selectionClick();
                            controller.addToBatchQueue([state.activePhoto!.path]);
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                    ),
                    icon: const Icon(Icons.bolt_rounded, size: 18),
                    label: Text(
                      'Run Batch',
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    onPressed: state.batchQueue.isNotEmpty && !state.isExporting
                        ? () async {
                            HapticFeedback.heavyImpact();
                            try {
                              final report = await controller.runBatchExport();
                              if (context.mounted) {
                                setState(() => _lastReport = report);
                              }
                            } catch (_) {}
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
