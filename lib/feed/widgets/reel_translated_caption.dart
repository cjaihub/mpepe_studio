import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/reel_translation_service.dart';

/// The reel caption, shown in the viewer's language when the reel is in a
/// language they don't read, with one quiet "See original" link under it.
/// Shows the original text unchanged until a translation is ready.
class ReelTranslatedCaption extends ConsumerWidget {
  final String reelId;

  /// Full caption as stored (hashtags included); used to detect the language.
  final String caption;

  /// What to show when not translated (the feed may strip hashtags).
  final String originalText;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;

  const ReelTranslatedCaption({
    super.key,
    required this.reelId,
    required this.caption,
    required this.originalText,
    required this.style,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.watch(reelTranslationProvider((id: reelId, caption: caption))).value;
    final showOriginal = ref.watch(reelShowOriginalProvider(reelId));
    final translated = tr != null && tr.caption.isNotEmpty;
    final text = translated && !showOriginal ? tr.caption : originalText;

    final linkStyle = GoogleFonts.inter(
      color: (style.color ?? Colors.white).withValues(alpha: 0.72),
      fontSize: 11,
      fontWeight: FontWeight.w600,
      shadows: style.shadows,
    );
    final from = tr?.sourceName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          child: Text(text, key: ValueKey(text.hashCode), style: style, maxLines: maxLines, overflow: overflow),
        ),
        if (translated)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              ref.read(reelShowOriginalProvider(reelId).notifier).toggle();
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 3, bottom: 1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.translate_rounded, size: 11, color: linkStyle.color),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      showOriginal
                          ? 'See translation'
                          : (from == null ? 'Translated · See original' : 'Translated from $from · See original'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: linkStyle,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
