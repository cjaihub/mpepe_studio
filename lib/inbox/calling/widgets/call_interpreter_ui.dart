import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/calling/interpreter/call_interpreter.dart';
import '../../../ova_assistant/widgets/ova_assistant_sheet.dart';
import '../../../shared/language/language_detector.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/compact/compact.dart';

/// Top-bar button: opens interpreter mode. Pink while my voice is translated;
/// a dot when someone's voice reaches me translated.
class CallTranslateButton extends ConsumerWidget {
  final Color fg;
  const CallTranslateButton({super.key, required this.fg});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(callInterpreterProvider);
    return IconButton(
      tooltip: 'Translate this call',
      onPressed: () => showCallInterpreterSheet(context),
      icon: Stack(clipBehavior: Clip.none, children: [
        Icon(Icons.translate_rounded, color: s.active ? AppColors.brandPink : fg, size: 22),
        if (s.hearingFrom.isNotEmpty)
          Positioned(
            right: -2,
            top: -2,
            child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.brandPink, shape: BoxShape.circle)),
          ),
      ]),
    );
  }
}

Future<void> showCallInterpreterSheet(BuildContext context) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (_) => const _InterpreterSheet(),
  );
}

class _InterpreterSheet extends ConsumerWidget {
  const _InterpreterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(callInterpreterProvider);
    final n = ref.read(callInterpreterProvider.notifier);
    final others = s.peerLangs.values.toSet().map(LanguageDetector.nameOf).join(', ');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 12),
          Text('Translate this call', style: AppTypography.pageTitle(context.textPrimary)),
          const SizedBox(height: 4),
          Text(
            'When someone speaks another language, translation starts by itself: they hear you in their language '
            'about a second after you speak, and you hear them in yours, with captions. '
            'You speak ${LanguageDetector.nameOf(s.myLang)}${others.isEmpty ? '' : '; they speak $others'}.',
            style: AppTypography.small(context.textSecondary),
          ),
          const SizedBox(height: 10),
          CompactGroup(children: [
            CompactRow(
              icon: Icons.record_voice_over_rounded,
              title: 'Live translation',
              subtitle: s.starting
                  ? 'Starting…'
                  : s.active
                      ? 'On: others hear you in their language'
                      : s.turnedOff
                          ? 'Off for this call'
                          : 'Starts by itself when languages differ',
              showChevron: false,
              trailing: Switch.adaptive(
                value: s.active || s.starting,
                activeTrackColor: AppColors.brandBlue,
                onChanged: s.starting ? null : (v) => v ? n.start() : n.stop(),
              ),
            ),
          ]),
          const CompactSectionHeader('Vertex Live Voice'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in kInterpreterVoices.entries)
              CompactChip(
                label: '${e.key} · ${e.value}',
                selected: s.voice == e.key,
                onTap: s.active ? null : () => n.setVoice(e.key),
              ),
          ]),
          const SizedBox(height: 12),
          CompactGroup(children: [
            CompactRow(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Ask Ova alongside this call',
              subtitle: 'Open Ova assistant in text so your call mic stays uninterrupted',
              onTap: () {
                Navigator.of(context).pop();
                OvaAssistantSheet.show(
                  context,
                  autoStartVoice: false,
                );
              },
            ),
          ]),
          if (s.error != null) ...[
            const SizedBox(height: 10),
            Text(s.error!, style: AppTypography.small(AppColors.brandPink)),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.lock_outline_rounded, size: 13, color: context.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Your voice goes to Oneova AI only while this is on, and to the others over the call’s encrypted link. Nothing is saved.',
                style: AppTypography.caption(context.textMuted),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Last two caption lines above the call controls. The translation is large,
/// the original small; lines fade after 8 seconds.
class CallCaptionsOverlay extends ConsumerStatefulWidget {
  final double bottom;
  const CallCaptionsOverlay({super.key, this.bottom = 150});

  @override
  ConsumerState<CallCaptionsOverlay> createState() => _CallCaptionsOverlayState();
}

class _CallCaptionsOverlayState extends ConsumerState<CallCaptionsOverlay> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-check once a second so old lines fade out on time.
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(callInterpreterProvider).captions.isNotEmpty) setState(() {});
    });
    final caps = ref.watch(callInterpreterProvider).captions;
    final now = DateTime.now();
    final recent = caps.where((c) => now.difference(c.at) < const Duration(seconds: 8)).toList();
    if (recent.isEmpty) return const SizedBox.shrink();
    final show = recent.length > 2 ? recent.sublist(recent.length - 2) : recent;
    return Positioned(
      left: 16,
      right: 16,
      bottom: widget.bottom,
      child: IgnorePointer(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final c in show)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.brandBlack.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(
                  c.mine ? (c.original.isEmpty ? c.translated : c.original) : (c.translated.isEmpty ? c.original : c.translated),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(color: AppColors.brandWhite, fontSize: 14, fontWeight: FontWeight.w600, height: 1.3),
                ),
                if (!c.mine && c.original.isNotEmpty && c.translated.isNotEmpty)
                  Text(c.original,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(color: AppColors.brandWhite.withValues(alpha: 0.65), fontSize: 11)),
              ]),
            ),
        ]),
      ),
    );
  }
}
