import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/pending_post_queue.dart';
import '../../shared/theme/app_theme.dart';
import 'reel_palette.dart';

/// Small pill on the feed for posts still uploading: live progress while it
/// runs, "Tap to retry" when it failed (one tap, no menu). Long-press asks
/// before discarding. Hidden when nothing is pending.
class PendingPostPill extends ConsumerWidget {
  const PendingPostPill({super.key});

  Future<void> _discard(BuildContext context, WidgetRef ref, PendingPost p) async {
    HapticFeedback.mediumImpact();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Discard this post?',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
        content: Text('It hasn\'t been posted yet. The copy saved for upload will be deleted.',
            style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: ctx.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandPink),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(pendingPostQueueProvider.notifier).discard(p.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<List<PendingPost>>(pendingPostQueueProvider, (prev, next) {
      final queue = ref.read(pendingPostQueueProvider.notifier);
      final messenger = ScaffoldMessenger.maybeOf(context);
      for (final r in queue.takeLinkRejections()) {
        messenger?.showSnackBar(SnackBar(content: Text('Posted, but the link wasn\'t added: ${r.message}')));
      }
      final discarded = queue.takeDiscarded();
      if (!discarded && prev != null && next.length < prev.length) {
        messenger?.showSnackBar(const SnackBar(
          backgroundColor: AppColors.brandBlue,
          behavior: SnackBarBehavior.floating,
          content: Text('Your post is live on Oneova'),
        ));
      }
    });
    final queue = ref.watch(pendingPostQueueProvider);
    if (queue.isEmpty) return const SizedBox.shrink();
    final p = queue.first;
    final failed = p.status == PendingPostStatus.failed;
    final palette = ReelPalette.of(context);
    final more = queue.length > 1 ? ' · ${queue.length}' : '';
    final label = failed
        ? 'Not posted · Tap to retry$more'
        : p.status == PendingPostStatus.linking
            ? 'Adding link…$more'
            : 'Posting ${(p.progress * 100).round()}%$more';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: failed
          ? () {
              HapticFeedback.lightImpact();
              ref.read(pendingPostQueueProvider.notifier).retry(p.id);
            }
          : null,
      onLongPress: failed ? () => _discard(context, ref, p) : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(5, 4, 11, 4),
        decoration: BoxDecoration(
          color: palette.glass,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: (failed ? AppColors.brandPink : AppColors.brandBlue).withValues(alpha: 0.6),
            width: 1.0,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 18,
            height: 18,
            child: failed
                ? const Icon(Icons.refresh_rounded, size: 16, color: AppColors.brandPink)
                : CircularProgressIndicator(
                    value: p.progress > 0 && p.progress < 1 ? p.progress : null,
                    strokeWidth: 2,
                    color: AppColors.brandBlue,
                  ),
          ),
          const SizedBox(width: 7),
          Text(label, style: GoogleFonts.inter(color: palette.fg, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.2, end: 0);
  }
}
