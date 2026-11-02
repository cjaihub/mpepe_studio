import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';
import '../models/video_transcript_model.dart';

/// Shows the YouTube-style interactive transcript bottom sheet with clickable timestamps.
Future<void> showOneovaTranscriptSheet(
  BuildContext context, {
  required VideoTranscript transcript,
  required int currentPositionMs,
  required void Function(int positionMs) onSeek,
}) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => OneovaTranscriptSheet(
      transcript: transcript,
      initialPositionMs: currentPositionMs,
      onSeek: onSeek,
    ),
  );
}

class OneovaTranscriptSheet extends StatefulWidget {
  final VideoTranscript transcript;
  final int initialPositionMs;
  final void Function(int positionMs) onSeek;

  const OneovaTranscriptSheet({
    super.key,
    required this.transcript,
    required this.initialPositionMs,
    required this.onSeek,
  });

  @override
  State<OneovaTranscriptSheet> createState() => _OneovaTranscriptSheetState();
}

class _OneovaTranscriptSheetState extends State<OneovaTranscriptSheet> {
  final TextEditingController _searchController = TextEditingController();
  late int _activeMs;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _activeMs = widget.initialPositionMs;
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _copyAllTranscript() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: widget.transcript.fullText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Transcript copied to clipboard'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.brandBlue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.transcript.segments.where((seg) {
      if (_searchQuery.isEmpty) return true;
      return seg.text.toLowerCase().contains(_searchQuery);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.62,
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.closed_caption_rounded,
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
                        'Transcript',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        '${widget.transcript.language.toUpperCase()} · Auto-synced closed captions',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: context.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy full transcript',
                  icon: Icon(Icons.copy_rounded, size: 18, color: context.textSecondary),
                  onPressed: _copyAllTranscript,
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: Icon(Icons.close_rounded, size: 20, color: context.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: TextField(
              controller: _searchController,
              style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search inside video transcript...',
                hintStyle: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
                prefixIcon: Icon(Icons.search_rounded, size: 18, color: context.textMuted),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: context.surfaceMid,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: context.border, width: 1.0),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: context.border, width: 1.0),
                ),
              ),
            ),
          ),

          Divider(height: 1, color: context.border),

          // List of Segments with Timestamps
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No matching lines found',
                      style: GoogleFonts.inter(fontSize: 13, color: context.textMuted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final seg = filtered[index];
                      final isCurrent =
                          _activeMs >= seg.startMs && _activeMs <= seg.endMs;

                      return InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _activeMs = seg.startMs);
                          widget.onSeek(seg.startMs);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? AppColors.brandBlue.withValues(alpha: 0.12)
                                : context.surfaceMid,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(
                              color: isCurrent
                                  ? AppColors.brandBlue
                                  : context.border,
                              width: isCurrent ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Timestamp pill
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? AppColors.brandBlue
                                      : context.surface,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  seg.timestampLabel,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isCurrent
                                        ? Colors.white
                                        : AppColors.brandBlue,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  seg.text,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: isCurrent
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isCurrent
                                        ? context.textPrimary
                                        : context.textSecondary,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

