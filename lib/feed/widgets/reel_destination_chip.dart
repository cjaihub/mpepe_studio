import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/widgets/auth_interaction_gate.dart';
import '../../backend/social/models/content.dart';
import '../../security/ova_guard_service.dart';
import '../../shared/theme/app_theme.dart';
import 'reel_palette.dart';

/// Tappable product / shop / link chip on a reel. In-app destinations
/// (Biz products, shop, profiles, lives) open their route; web links open in
/// the browser only after Ova Guard checks them (`contentOpenDestination`,
/// which also counts the click; `guardCheckLinks` if that is unreachable).
class ReelDestinationChip extends ConsumerStatefulWidget {
  final String contentId;
  final ContentDestination destination;

  const ReelDestinationChip({super.key, required this.contentId, required this.destination});

  @override
  ConsumerState<ReelDestinationChip> createState() => _ReelDestinationChipState();
}

class _ReelDestinationChipState extends ConsumerState<ReelDestinationChip> {
  bool _busy = false;

  IconData get _icon => switch (widget.destination.kind) {
        'product' => Icons.shopping_bag_outlined,
        'shop' => Icons.storefront_outlined,
        'profile' => Icons.person_outline_rounded,
        'live' => Icons.sensors_rounded,
        _ => Icons.link_rounded,
      };

  Future<Map<String, dynamic>?> _open() async {
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('contentOpenDestination')
          .call({'contentId': widget.contentId});
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      debugPrint('[ReelDestinationChip] open: $e');
      return null;
    }
  }

  Future<void> _onTap() async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    final d = widget.destination;
    if (d.isInApp) {
      unawaited(_open()); // counts the click
      context.push(d.route!);
      return;
    }
    final url = d.url;
    if (url == null) return;
    setState(() => _busy = true);
    var verdict = d.verdict;
    String? reason;
    var target = url;
    final server = await _open();
    if (server != null) {
      verdict = server['verdict'] as String? ?? verdict;
      reason = (server['reasons'] as List?)?.firstOrNull?.toString();
      target = server['url'] as String? ?? '';
    } else {
      final local = await ref.read(ovaGuardServiceProvider).checkLinks([url]);
      if (local.isNotEmpty) {
        verdict = local.first.verdict;
        reason = local.first.reasons.firstOrNull;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (verdict == 'dangerous' || target.isEmpty) {
      await _blocked(reason);
      return;
    }
    if (verdict == 'suspicious' && !await _confirmSuspicious(reason)) return;
    final uri = Uri.tryParse(target);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Couldn\'t open this link.')));
      }
    }
  }

  Future<void> _blocked(String? reason) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ctx.surface,
          icon: const Icon(Icons.gpp_bad_rounded, color: AppColors.brandPink),
          title: Text('Link blocked by Ova Guard',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
          content: Text(reason ?? 'This link is on a list of sites that steal accounts or spread malware.',
              style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: ctx.textSecondary)),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );

  Future<bool> _confirmSuspicious(String? reason) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Open this link?',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
        content: Text(
          '${reason ?? 'Ova Guard thinks this link may be a scam.'}\n\n'
          'Never enter your password, codes or card details on a page you reached from a post.',
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
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final p = ReelPalette.of(context);
    final d = widget.destination;
    final warn = d.verdict == 'suspicious';
    final accent = d.kind == 'web' ? AppColors.brandBlue : AppColors.brandPink;
    final sub = d.kind == 'web' ? d.host?.replaceFirst(RegExp(r'^www\.'), '') : null;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => AuthInteractionGate.requireAuth(context, actionTitle: 'open links', onAuthenticated: _onTap),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.fromLTRB(4, 3, 10, 3),
          decoration: BoxDecoration(
            color: p.glass,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: accent.withValues(alpha: 0.6), width: 1.0),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(4),
                      child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.brandWhite),
                    )
                  : Icon(_icon, color: AppColors.brandWhite, size: 12),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                sub != null && sub != d.label ? '${d.label} · $sub' : d.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(color: p.fg, fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            ),
            if (warn) ...[
              const SizedBox(width: 4),
              const Icon(Icons.warning_amber_rounded, color: AppColors.brandPink, size: 13),
            ],
            const SizedBox(width: 2),
            Icon(d.kind == 'web' ? Icons.open_in_new_rounded : Icons.chevron_right_rounded, color: p.fgSoft, size: 13),
          ]),
        ),
      ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.2, end: 0),
    );
  }
}
