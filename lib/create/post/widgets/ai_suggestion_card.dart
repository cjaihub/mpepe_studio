import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../backend/publishing/models/publishing_destination.dart';
import '../../../shared/theme/app_theme.dart';
import '../services/openrouter_post_optimizer.dart';

class AISuggestionCard extends StatefulWidget {
  final VideoOptimizationPackage? optimization;
  final bool isAnalyzing;
  final VoidCallback onReanalyze;
  final Function(String title) onApplyTitle;
  final Function(String description) onApplyDescription;
  final Function(List<String> hashtags) onApplyHashtags;

  const AISuggestionCard({
    super.key,
    required this.optimization,
    required this.isAnalyzing,
    required this.onReanalyze,
    required this.onApplyTitle,
    required this.onApplyDescription,
    required this.onApplyHashtags,
  });

  @override
  State<AISuggestionCard> createState() => _AISuggestionCardState();
}

class _AISuggestionCardState extends State<AISuggestionCard> {
  PlatformDestination _selectedPreviewPlatform = PlatformDestination.internal;
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.isAnalyzing) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.4), width: 1.0),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.brandBlue),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Director is analyzing your video in real-time…',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Synthesizing viral hooks, high-CTR titles & platform optimizations',
                    style: GoogleFonts.inter(fontSize: 11, color: context.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final opt = widget.optimization;
    if (opt == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.35), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: AI Optimizer + Viral Potential Score
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.brandBlue, AppColors.brandPink],
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome, size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        'AI VIRAL DIRECTOR',
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.brandPink.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${opt.viralScore}% Viral Score',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandPink,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Re-analyze',
                  color: context.textSecondary,
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    widget.onReanalyze();
                  },
                ),
                IconButton(
                  icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more, size: 20),
                  tooltip: _isExpanded ? 'Collapse' : 'Expand full package',
                  color: context.textSecondary,
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() => _isExpanded = !_isExpanded);
                  },
                ),
              ],
            ),
          ),

          // Suggested Title Pill
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
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
                          'SUGGESTED TITLE',
                          style: GoogleFonts.inter(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: context.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          opt.suggestedTitle,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      widget.onApplyTitle(opt.suggestedTitle);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: const Size(0, 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                    child: Text(
                      'Apply',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Suggested Description & Hashtags Quick Action
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.paste_rounded, size: 14),
                    label: Text(
                      'Apply AI Caption',
                      style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      widget.onApplyDescription(opt.suggestedDescription);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brandBlue,
                      side: BorderSide(color: AppColors.brandBlue.withValues(alpha: 0.4)),
                      minimumSize: const Size(0, 34),
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
                      'Insert All Tags (${opt.suggestedHashtags.length})',
                      style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      widget.onApplyHashtags(opt.suggestedHashtags);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brandPink,
                      side: BorderSide(color: AppColors.brandPink.withValues(alpha: 0.4)),
                      minimumSize: const Size(0, 34),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Expanded Content: Multi-Platform Previews & Viral Hooks
          if (_isExpanded) ...[
            const SizedBox(height: 12),
            Divider(color: context.border, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Text(
                'CROSS-PLATFORM SYNDICATION PREVIEWS',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: context.textMuted,
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  PlatformDestination.internal,
                  PlatformDestination.tiktok,
                  PlatformDestination.instagram,
                  PlatformDestination.youtube,
                  PlatformDestination.whatsappBusiness,
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
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : context.textPrimary,
                        ),
                      ),
                      selectedColor: AppColors.brandBlue,
                      backgroundColor: context.surfaceMid,
                      onSelected: (val) {
                        if (val) setState(() => _selectedPreviewPlatform = dest);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: context.border, width: 0.8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      opt.platformCaptions[_selectedPreviewPlatform] ?? opt.suggestedDescription,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.4,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.check, size: 14),
                        label: Text(
                          'Use This Variant',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          final caption = opt.platformCaptions[_selectedPreviewPlatform] ??
                              opt.suggestedDescription;
                          widget.onApplyDescription(caption);
                          final title = opt.platformTitles[_selectedPreviewPlatform];
                          if (title != null && title.isNotEmpty) {
                            widget.onApplyTitle(title);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
