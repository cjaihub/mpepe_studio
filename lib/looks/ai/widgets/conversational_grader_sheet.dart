import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../shared/theme/app_theme.dart';
import '../controllers/conversational_grader_controller.dart';
import '../models/ai_grade_command.dart';
import '../scopes/widgets/histogram_scope.dart';
import '../scopes/widgets/rgb_parade_scope.dart';
import '../scopes/widgets/scope_sentinel_banner.dart';
import '../scopes/widgets/vectorscope.dart';
import '../scopes/widgets/waveform_scope.dart';

/// Full interactive Conversational AI Color Grader sheet with GPU scopes,
/// Scope Sentinel auto-monitoring, semantic region selection, and agent diff reporting.
class ConversationalGraderSheet extends ConsumerStatefulWidget {
  final VoidCallback? onClose;

  const ConversationalGraderSheet({super.key, this.onClose});

  @override
  ConsumerState<ConversationalGraderSheet> createState() => _ConversationalGraderSheetState();
}

class _ConversationalGraderSheetState extends ConsumerState<ConversationalGraderSheet> {
  final TextEditingController _textController = TextEditingController();
  String _activeScopeTab = 'WAVEFORM'; // 'WAVEFORM', 'PARADE', 'VECTORSCOPE', 'HISTOGRAM', 'NONE'
  bool _showDiffReport = true;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _submit() {
    final query = _textController.text.trim();
    if (query.isEmpty) return;
    _textController.clear();
    FocusScope.of(context).unfocus();
    ref.read(conversationalGraderControllerProvider.notifier).submitPrompt(query);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(conversationalGraderControllerProvider);
    final controller = ref.read(conversationalGraderControllerProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: context.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border.all(color: context.border, width: 1.0),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        top: 10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.border,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Header Toolbar: Title, Undo, Redo, Scope Switcher, Close
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome, size: 16, color: AppColors.brandBlue),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'AI Color Grader',
                        style: GoogleFonts.inter(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        state.activeLook.name,
                        style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
                      ),
                    ],
                  ),
                ),

                // Undo Button
                IconButton(
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  color: state.canUndo ? context.textPrimary : context.textMuted,
                  onPressed: state.canUndo ? controller.undo : null,
                  tooltip: 'Undo',
                ),

                // Redo Button
                IconButton(
                  icon: const Icon(Icons.redo_rounded, size: 18),
                  color: state.canRedo ? context.textPrimary : context.textMuted,
                  onPressed: state.canRedo ? controller.redo : null,
                  tooltip: 'Redo',
                ),

                // Close Button
                if (widget.onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: context.textPrimary,
                    onPressed: widget.onClose,
                  ),
              ],
            ),
          ),

          // Scope Sentinel Alert Banner (when anomaly detected)
          if (state.activeAlert != null)
            ScopeSentinelBanner(
              alert: state.activeAlert!,
              onApplyFix: () => controller.applySentinelFix(state.activeAlert!),
              onDismiss: controller.dismissSentinelAlert,
            ),

          // Scopes Tab Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: ['WAVEFORM', 'PARADE', 'VECTORSCOPE', 'HISTOGRAM', 'OFF'].map((tab) {
                final isSelected = _activeScopeTab == tab;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () {
                      try {
                        HapticFeedback.selectionClick();
                      } catch (_) {}
                      setState(() => _activeScopeTab = tab);
                    },
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.brandBlue : context.surfaceMid,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        tab,
                        style: GoogleFonts.firaCode(
                          fontSize: 9,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected ? Colors.white : context.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Active Scope Viewer
          if (_activeScopeTab != 'OFF')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: _buildScopeWidget(state),
            ),

          // Semantic Region Selector Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: SemanticGradeRegion.values.map((region) {
                  final isSelected = state.targetRegion == region;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () => controller.setTargetRegion(region),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.brandPink : context.surface,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          border: Border.all(
                            color: isSelected ? AppColors.brandPink : context.border,
                            width: 1.0,
                          ),
                        ),
                        child: Text(
                          region.label,
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isSelected ? Colors.white : context.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Agent Diff Report Card
          if (state.lastDiff != null && _showDiffReport)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.surface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.bolt_rounded, size: 14, color: AppColors.brandPink),
                            const SizedBox(width: 4),
                            Text(
                              'AGENT DIFF REPORT',
                              style: GoogleFonts.firaCode(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.brandPink,
                              ),
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _showDiffReport = false),
                          child: Icon(Icons.close_rounded, size: 14, color: context.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      state.lastDiff!.visualDeltaSummary,
                      style: GoogleFonts.inter(
                        fontSize: 12.0,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    if (state.lastDiff!.artisticRationale.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        state.lastDiff!.artisticRationale,
                        style: GoogleFonts.inter(
                          fontSize: 11.0,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // Suggested Next Prompts Chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: state.suggestedPrompts.map((prompt) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      label: Text(
                        prompt,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                      backgroundColor: context.surfaceMid,
                      side: BorderSide(color: context.border, width: 1.0),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                      onPressed: () => controller.submitPrompt(prompt),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Conversational Input Bar: Text + Voice Trigger
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.surface,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: context.border, width: 1.0),
                    ),
                    child: TextField(
                      controller: _textController,
                      onSubmitted: (_) => _submit(),
                      style: GoogleFonts.inter(fontSize: 12.5, color: context.textPrimary),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Ask AI grader (e.g. "Warm up skin", "Tokyo neon look")...',
                        hintStyle: GoogleFonts.inter(fontSize: 12, color: context.textMuted),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Submit / Mic Action Button
                InkWell(
                  onTap: _submit,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: state.isProcessing
                        ? const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeWidget(ConversationalGraderState state) {
    switch (_activeScopeTab) {
      case 'PARADE':
        return RgbParadeScope(data: state.scopeData, height: 100);
      case 'VECTORSCOPE':
        return Center(child: Vectorscope(data: state.scopeData, size: 110));
      case 'HISTOGRAM':
        return HistogramScope(data: state.scopeData, height: 90);
      case 'WAVEFORM':
      default:
        return WaveformScope(data: state.scopeData, height: 100);
    }
  }
}
