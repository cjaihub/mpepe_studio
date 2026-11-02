import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../shared/theme/app_theme.dart';

/// Detects YouTube video links and renders an inline player card with auto-road
/// thumbnail preview and one-tap in-chat embedded playback.
class OvaYouTubeInlineCard extends StatefulWidget {
  final String videoId;
  final String? customTitle;
  final bool autoPlay;

  const OvaYouTubeInlineCard({
    super.key,
    required this.videoId,
    this.customTitle,
    this.autoPlay = false,
  });

  /// Extracts the first YouTube video ID from [text], or null if none.
  static String? extractVideoId(String text) {
    if (text.isEmpty) return null;
    final regExp = RegExp(
      r'(?:youtube\.com\/(?:[^\/\n\s]+\/\S+\/|(?:v|e(?:mbed)?|shorts)\/|\S*?[?&]v=)|youtu\.be\/)([a-zA-Z0-9_-]{11})',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(text);
    return match?.group(1);
  }

  @override
  State<OvaYouTubeInlineCard> createState() => _OvaYouTubeInlineCardState();
}

class _OvaYouTubeInlineCardState extends State<OvaYouTubeInlineCard> {
  bool _isPlaying = false;
  WebViewController? _webViewController;

  void _startPlayback() {
    setState(() {
      _isPlaying = true;
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse(
          'https://www.youtube.com/embed/${widget.videoId}?autoplay=1&playsinline=1&modestbranding=1&rel=0',
        ));
    });
  }

  void _openInYouTube() {
    launchUrl(
      Uri.parse('https://youtube.com/watch?v=${widget.videoId}'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final thumbUrl = 'https://img.youtube.com/vi/${widget.videoId}/hqdefault.jpg';

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
        boxShadow: AppShadows.sm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Video player area
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _isPlaying && _webViewController != null
                ? WebViewWidget(controller: _webViewController!)
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      // Thumbnail
                      Image.network(
                        thumbUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: context.surfaceMid,
                          child: const Center(
                            child: Icon(Icons.smart_display_rounded, size: 40, color: AppColors.brandPink),
                          ),
                        ),
                      ),
                      // Gradient overlay
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.65),
                            ],
                          ),
                        ),
                      ),
                      // Center Play Button
                      Center(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _startPlayback,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.brandPink,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.brandPink.withValues(alpha: 0.4),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                            ),
                          ),
                        ),
                      ),
                      // Top YouTube Badge
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.smart_display_rounded, size: 14, color: AppColors.brandPink),
                              const SizedBox(width: 4),
                              Text(
                                'YouTube',
                                style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          // Footer with controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.customTitle ?? 'YouTube Video',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _openInYouTube,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Text(
                          'Open app',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brandBlue),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.open_in_new_rounded, size: 12, color: AppColors.brandBlue),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

