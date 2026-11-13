import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../backend/social/models/content.dart';
import '../../shared/theme/app_theme.dart';

/// Top of the reel options sheet: a short AI read of the reel (from its own
/// caption, tags and sound), an "Ask Ova" entry, and the reel's sound.
class AboutReelCard extends StatefulWidget {
  const AboutReelCard({super.key, required this.content, required this.authorName, required this.onAskOva});

  final Content content;
  final String authorName;

  /// Opens Ova on this reel with the typed question (may be empty).
  final ValueChanged<String> onAskOva;

  @override
  State<AboutReelCard> createState() => _AboutReelCardState();
}

class _AboutReelCardState extends State<AboutReelCard> {
  /// Summaries already made this session, by content id.
  static final Map<String, String> _cache = {};

  final _ask = TextEditingController();
  String? _summary;
  bool _failed = false;

  Content get c => widget.content;

  List<String> get _sources => [
        if (c.description.trim().isNotEmpty) 'Caption',
        if (c.hashtags.isNotEmpty) 'Tags',
        if (c.mediaMetadata.musicId != null || c.mediaMetadata.audioTrackUrl != null) 'Sound',
      ];

  @override
  void initState() {
    super.initState();
    _summary = _cache[c.id];
    if (_summary == null) _load();
  }

  @override
  void dispose() {
    _ask.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final caption = c.description.trim();
    if (caption.isEmpty && c.hashtags.isEmpty) {
      setState(() => _failed = true);
      return;
    }
    try {
      final r = await FirebaseFunctions.instance
          .httpsCallable('aiGateway', options: HttpsCallableOptions(timeout: const Duration(seconds: 20)))
          .call(<String, dynamic>{
        'prompt': 'In one or two short, neutral sentences, say what this short video is about. '
            'Use only these details and do not guess beyond them. Do not use any tools.\n'
            'Caption: "$caption"\n'
            'Hashtags: ${c.hashtags.map((h) => '#$h').join(' ')}\n'
            'Creator: ${widget.authorName}',
      });
      final text = (r.data is Map ? r.data['reply'] : null)?.toString().trim() ?? '';
      if (!mounted) return;
      if (text.isEmpty) {
        setState(() => _failed = true);
      } else {
        _cache[c.id] = text;
        setState(() => _summary = text);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSound = c.mediaMetadata.musicId != null || c.mediaMetadata.audioTrackUrl != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('About this reel',
            style: GoogleFonts.inter(color: context.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _summary != null
                  ? Text(_summary!,
                      key: const ValueKey('s'),
                      style: GoogleFonts.inter(color: context.textPrimary, fontSize: 14, height: 1.4))
                  : _failed
                      ? Text(
                          c.description.trim().isEmpty ? 'No description for this reel yet.' : c.description.trim(),
                          key: const ValueKey('f'),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(color: context.textSecondary, fontSize: 14, height: 1.4))
                      : Row(key: const ValueKey('l'), children: [
                          const SizedBox(
                              width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandPink)),
                          const SizedBox(width: 10),
                          Text('Ova is reading this reel…',
                              style: GoogleFonts.inter(color: context.textMuted, fontSize: 13)),
                        ]),
            ),
            if (_summary != null && _sources.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('From: ${_sources.join(' · ')}',
                  style: GoogleFonts.inter(color: context.textMuted, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 10),
            // Ask Ova about this reel.
            Container(
              height: 42,
              padding: const EdgeInsets.only(left: 12, right: 4),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: context.border),
              ),
              child: Row(children: [
                const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.brandPink),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _ask,
                    textInputAction: TextInputAction.send,
                    onSubmitted: widget.onAskOva,
                    style: GoogleFonts.inter(color: context.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Ask Ova…',
                      hintStyle: GoogleFonts.inter(color: context.textMuted, fontSize: 14),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Ask Ova',
                  icon: const Icon(Icons.send_rounded, size: 20, color: AppColors.brandBlue),
                  onPressed: () => widget.onAskOva(_ask.text),
                ),
              ]),
            ),
          ]),
        ),
        if (hasSound) ...[
          const SizedBox(height: 10),
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                gradient: const LinearGradient(colors: [AppColors.brandBlue, AppColors.brandPink]),
              ),
              child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.mediaMetadata.musicId != null ? 'Sound' : 'Original audio · ${widget.authorName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                Text('Audio', style: GoogleFonts.inter(color: context.textMuted, fontSize: 12)),
              ]),
            ),
          ]),
        ],
      ]),
    );
  }
}
