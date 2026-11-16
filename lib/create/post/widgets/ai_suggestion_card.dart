import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../backend/publishing/models/publishing_destination.dart';
import '../../../shared/theme/app_theme.dart';
import '../services/openrouter_post_optimizer.dart';

class AISuggestionCard extends StatefulWidget {
  final VideoOptimizationPackage? optimization;
  final bool isAnalyzing;
  final bool autoOptimizeInBackground;
  final ValueChanged<bool>? onToggleAutoOptimize;
  final VoidCallback onReanalyze;
  final Function(String title) onApplyTitle;
  final Function(String description) onApplyDescription;
  final Function(List<String> hashtags) onApplyHashtags;
  final VoidCallback? onApplyAll;

  const AISuggestionCard({
    super.key,
    required this.optimization,
    required this.isAnalyzing,
    this.autoOptimizeInBackground = true,
    this.onToggleAutoOptimize,
    required this.onReanalyze,
    required this.onApplyTitle,
    required this.onApplyDescription,
    required this.onApplyHashtags,
    this.onApplyAll,
  });

  @override
  State<AISuggestionCard> createState() => _AISuggestionCardState();
}

class _AISuggestionCardState extends State<AISuggestionCard> {
  PlatformDestination _selectedPreviewPlatform = PlatformDestination.internal;
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final opt = widget.optimization;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.brandBlue.withValues(alpha: 0.32),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Compact Header Row: AI Status + Niche + Background Auto Switch
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.brandBlue, AppColors.brandPink],
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Center(
                    child: widget.isAnalyzing
                        ? const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.auto_awesome_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.isAnalyzing
                                  ? 'AI analyzing video clip & channel niche…'
                                  : 'AI Channel & Video Optimizer',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                              ),
                            ),
                          ),
                          if (!widget.isAnalyzing && opt != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.brandPink.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(AppRadius.xs),
                              ),
                              child: Text(
                                '${opt.viralScore}% Viral',
                                style: GoogleFonts.inter(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.brandPink,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.isAnalyzing
                            ? 'Runs in the background — you can post anytime'
                            : (opt != null
                                ? 'Niche: ${opt.detectedNiche}${opt.analyzedVideoFrame ? ' · Video clip analyzed' : ''}'
                                : 'Auto-generates title, caption & tags for your channel'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: context.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onToggleAutoOptimize != null)
                  Tooltip(
                    message: 'Auto-optimize in background when posting',
                    child: Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: widget.autoOptimizeInBackground,
                        activeThumbColor: AppColors.brandBlue,
                        onChanged: (v) {
                          HapticFeedback.selectionClick();
                          widget.onToggleAutoOptimize!(v);
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),

          if (!widget.isAnalyzing && opt != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 34,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.bolt_rounded, size: 15, color: Colors.white),
                        label: Text(
                          'Apply AI Title, Caption & Tags',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandBlue,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          if (widget.onApplyAll != null) {
                            widget.onApplyAll!();
                          } else {
                            widget.onApplyTitle(opt.suggestedTitle);
                            widget.onApplyDescription(opt.suggestedDescription);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 34,
                    child: OutlinedButton.icon(
                      icon: Icon(
                        _isExpanded ? Icons.expand_less_rounded : Icons.tune_rounded,
                        size: 15,
                      ),
                      label: Text(
                        _isExpanded ? 'Hide' : 'Preview',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.textPrimary,
                        side: BorderSide(color: context.border),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() => _isExpanded = !_isExpanded);
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    tooltip: 'Re-analyze video & title',
                    color: context.textSecondary,
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      widget.onReanalyze();
                    },
                  ),
                ],
              ),
            ),

            if (_isExpanded) ...[
              Divider(color: context.border, height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Suggested Title Row
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: context.surfaceMid,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AI SUGGESTED TITLE',
                                  style: GoogleFonts.inter(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                    color: context.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  opt.suggestedTitle,
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: context.textPrimary,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              widget.onApplyTitle(opt.suggestedTitle);
                            },
                            child: Text(
                              'Use Title',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brandBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Quick Action Buttons for Caption & Tags
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.notes_rounded, size: 14),
                            label: Text(
                              'Use Caption Only',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              widget.onApplyDescription(opt.suggestedDescription);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.brandBlue,
                              side: BorderSide(
                                color: AppColors.brandBlue.withValues(alpha: 0.35),
                              ),
                              minimumSize: const Size(0, 32),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.tag_rounded, size: 14),
                            label: Text(
                              'Add ${opt.suggestedHashtags.length} Niche Tags',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              widget.onApplyHashtags(opt.suggestedHashtags);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.brandPink,
                              side: BorderSide(
                                color: AppColors.brandPink.withValues(alpha: 0.35),
                              ),
                              minimumSize: const Size(0, 32),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Platform Preview Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          PlatformDestination.internal,
                          PlatformDestination.youtube,
                          PlatformDestination.tiktok,
                          PlatformDestination.instagram,
                          PlatformDestination.facebook,
                        ].map((dest) {
                          final isSelected = _selectedPreviewPlatform == dest;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              selected: isSelected,
                              label: Text(
                                dest.displayName,
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected ? Colors.white : context.textPrimary,
                                ),
                              ),
                              selectedColor: AppColors.brandBlue,
                              backgroundColor: context.surfaceMid,
                              visualDensity: VisualDensity.compact,
                              onSelected: (val) {
                                if (val) {
                                  setState(() => _selectedPreviewPlatform = dest);
                                }
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: context.surfaceMid,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: context.border, width: 0.8),
                      ),
                      child: Text(
                        opt.platformCaptions[_selectedPreviewPlatform] ??
                            opt.suggestedDescription,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          height: 1.38,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
