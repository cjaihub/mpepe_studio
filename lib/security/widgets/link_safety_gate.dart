import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/theme/app_theme.dart';
import '../ova_guard_service.dart';

/// Wraps a tappable link (e.g. a chat link card) with Ova Guard's verdict.
///
/// - dangerous: the link is replaced by a "Dangerous link blocked" box that
///   cannot be opened;
/// - suspicious: a warning banner shows, and opening asks first;
/// - safe / unknown: [child] as is.
///
/// The verdict comes from the server's `safety` field when the server could
/// read the message, otherwise from `guardCheckLinks` (only the link is sent).
class LinkSafetyGate extends ConsumerStatefulWidget {
  final String url;
  final Map<String, dynamic>? serverSafety;
  final bool onBlue;
  final Widget child;

  const LinkSafetyGate({
    super.key,
    required this.url,
    required this.child,
    this.serverSafety,
    this.onBlue = false,
  });

  @override
  ConsumerState<LinkSafetyGate> createState() => _LinkSafetyGateState();
}

class _LinkSafetyGateState extends ConsumerState<LinkSafetyGate> {
  LinkSafety? _checked;

  @override
  void initState() {
    super.initState();
    if (widget.serverSafety == null) {
      ref.read(ovaGuardServiceProvider).checkLinks([widget.url]).then((r) {
        if (mounted && r.isNotEmpty) setState(() => _checked = r.first);
      });
    }
  }

  (String verdict, String? reason) get _verdict {
    final s = widget.serverSafety;
    if (s != null) {
      final blocked = List<String>.from(s['blockedLinks'] as List? ?? const []);
      final reasons = List<String>.from(s['reasons'] as List? ?? const []);
      final reason = reasons.isEmpty ? null : reasons.first;
      if (blocked.isNotEmpty || s['verdict'] == 'dangerous') return ('dangerous', reason);
      return (s['verdict'] as String? ?? 'safe', reason);
    }
    final c = _checked;
    if (c == null) return ('safe', null);
    return (c.verdict, c.reasons.isEmpty ? null : c.reasons.first);
  }

  Future<void> _openAnyway(String? reason) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Open this link?',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
        content: Text(
          '${reason ?? 'Ova Guard thinks this link may be a scam.'}\n\n'
          'Never enter your password, codes or card details on a page you reached from a message.',
          style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: ctx.textSecondary),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay safe'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open anyway')),
        ],
      ),
    );
    if (ok == true) await launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final (verdict, reason) = _verdict;
    if (verdict == 'safe') return widget.child;
    final fg = widget.onBlue ? AppColors.brandWhite : context.textPrimary;
    final muted = widget.onBlue ? AppColors.brandWhite.withValues(alpha: 0.8) : context.textMuted;
    final banner = Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.brandPink.withValues(alpha: widget.onBlue ? 0.28 : 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.6)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(verdict == 'dangerous' ? Icons.gpp_bad_rounded : Icons.warning_amber_rounded,
            size: 18, color: widget.onBlue ? AppColors.brandWhite : AppColors.brandPink),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(verdict == 'dangerous' ? 'Dangerous link blocked' : 'Be careful with this link',
                style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
            const SizedBox(height: 2),
            Text(
              reason ??
                  (verdict == 'dangerous'
                      ? 'It is on a list of sites that steal accounts or spread malware.'
                      : 'It looks like a scam or a fake website.'),
              style: GoogleFonts.inter(fontSize: 11, height: 1.3, color: muted),
            ),
            if (verdict == 'dangerous')
              Text(Uri.tryParse(widget.url)?.host ?? '',
                  style: GoogleFonts.inter(fontSize: 10.5, color: muted, decoration: TextDecoration.lineThrough)),
          ]),
        ),
      ]),
    );
    if (verdict == 'dangerous') return banner;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      banner,
      const SizedBox(height: 6),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openAnyway(reason),
        child: AbsorbPointer(child: widget.child),
      ),
    ]);
  }
}
