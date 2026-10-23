import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import '../services/ova_chat_controller.dart';

/// The one confirmation Ova shows before it sends, posts, replies, deletes
/// or taps. Compact, quiet and specific:
///   service badge · what · to whom, a folded preview of the exact content,
///   Cancel and a verb button ("Send", "Post"), a 2-minute expiry ring.
/// Public or destructive actions need press-and-hold so they can't fire on a
/// stray tap.
class OvaConfirmCard extends StatefulWidget {
  final OvaItem item;
  final OvaChatController chat;

  /// Tighter spacing for the floating dock.
  final bool dense;

  const OvaConfirmCard({super.key, required this.item, required this.chat, this.dense = false});

  @override
  State<OvaConfirmCard> createState() => _OvaConfirmCardState();
}

class _OvaConfirmCardState extends State<OvaConfirmCard> with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(vsync: this, duration: const Duration(milliseconds: 850));
  Timer? _tick;
  bool _expanded = false;

  OvaItem get _item => widget.item;
  bool get _pending => _item.confirmState == OvaConfirmState.pending;

  @override
  void initState() {
    super.initState();
    _hold.addStatusListener((s) {
      if (s == AnimationStatus.completed) _decide(true);
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_pending) return _tick?.cancel();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _hold.dispose();
    super.dispose();
  }

  void _decide(bool ok) {
    if (!_pending) return;
    ok ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
    widget.chat.decide(_item, ok);
    setState(() {});
  }

  static const _services = <String, (IconData, String)>{
    'gmail': (Icons.mail_rounded, 'Gmail'),
    'youtube': (Icons.smart_display_rounded, 'YouTube'),
    'facebook': (Icons.facebook_rounded, 'Facebook'),
    'whatsapp': (Icons.chat_rounded, 'WhatsApp'),
    'screen': (Icons.touch_app_rounded, 'On screen'),
    'phone': (Icons.phone_iphone_rounded, 'Phone'),
    'oneova': (Icons.auto_awesome_rounded, 'Oneova'),
  };

  @override
  Widget build(BuildContext context) {
    final p = _item.pending!;
    if (!_pending) return _settled(context, p.title);

    final svc = _services[p.service] ?? _services['oneova']!;
    final left = confirmTimeout - DateTime.now().difference(_item.createdAt);
    final frac = (left.inMilliseconds / confirmTimeout.inMilliseconds).clamp(0.0, 1.0);
    final pad = widget.dense ? 10.0 : 12.0;
    final detail = p.detail.trim();
    final long = detail.length > 160 || '\n'.allMatches(detail).length > 3;

    return Container(
      padding: EdgeInsets.fromLTRB(pad, pad, pad, pad - 2),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.35), width: 1),
        boxShadow: context.isDark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(svc.$1, size: 15, color: AppColors.brandBlue),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: -0.15, color: context.textPrimary)),
                const SizedBox(height: 1),
                Text(
                  [svc.$2, if (p.target != null && p.target!.isNotEmpty) p.target!].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: context.textMuted),
                ),
              ]),
            ),
            // Expiry ring: the approval goes stale after two minutes.
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                value: frac,
                strokeWidth: 1.6,
                backgroundColor: context.border,
                color: frac < 0.25 ? AppColors.brandPink : AppColors.brandBlue,
              ),
            ),
          ]),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 9),
            GestureDetector(
              onTap: long ? () => setState(() => _expanded = !_expanded) : null,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    borderRadius: BorderRadius.circular(10),
                    border: Border(left: BorderSide(color: AppColors.brandBlue.withValues(alpha: 0.6), width: 2)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      detail,
                      maxLines: _expanded ? 40 : 4,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: context.textPrimary),
                    ),
                    if (long)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(_expanded ? 'Show less' : 'Show all',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
                      ),
                  ]),
                ),
              ),
            ),
          ],
          if (p.note != null && p.note!.isNotEmpty) ...[
            const SizedBox(height: 7),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded, size: 12, color: context.textMuted),
              const SizedBox(width: 5),
              Expanded(child: Text(p.note!, style: GoogleFonts.inter(fontSize: 11, height: 1.35, color: context.textMuted))),
            ]),
          ],
          SizedBox(height: widget.dense ? 8 : 10),
          Row(children: [
            Expanded(
              child: TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                ),
                onPressed: () => _decide(false),
                child: Text('Cancel', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textSecondary)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: p.hold ? _holdButton(p.confirmLabel) : _tapButton(p.confirmLabel)),
          ]),
        ],
      ),
    ).animate().fadeIn(duration: 180.ms).scaleXY(begin: 0.98, end: 1, curve: Curves.easeOutCubic);
  }

  Widget _tapButton(String label) => SizedBox(
        height: 34,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brandBlue,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ),
          onPressed: () => _decide(true),
          child: Text(label, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      );

  Widget _holdButton(String label) => GestureDetector(
        onTapDown: (_) {
          HapticFeedback.selectionClick();
          _hold.forward();
        },
        onTapUp: (_) {
          if (_hold.status != AnimationStatus.completed) _hold.reverse();
        },
        onTapCancel: () {
          if (_hold.status != AnimationStatus.completed) _hold.reverse();
        },
        child: AnimatedBuilder(
          animation: _hold,
          builder: (context, _) => ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Container(
              height: 34,
              color: AppColors.brandBlue.withValues(alpha: 0.22),
              child: Stack(children: [
                FractionallySizedBox(widthFactor: _hold.value, child: Container(color: AppColors.brandBlue)),
                Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.fingerprint_rounded, size: 14, color: _hold.value > 0.45 ? Colors.white : context.textPrimary),
                    const SizedBox(width: 5),
                    Text(_hold.value > 0 ? 'Keep holding…' : 'Hold to $label',
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: _hold.value > 0.45 ? Colors.white : context.textPrimary)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _settled(BuildContext context, String title) {
    final ok = _item.confirmState == OvaConfirmState.confirmed;
    final label = ok ? 'Approved' : (_item.expired ? 'Expired' : 'Cancelled');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.border),
      ),
      child: Row(children: [
        Icon(ok ? Icons.check_circle_rounded : (_item.expired ? Icons.timer_off_rounded : Icons.cancel_rounded),
            size: 14, color: ok ? AppColors.brandBlue : context.textMuted),
        const SizedBox(width: 7),
        Expanded(
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary)),
        ),
        Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: ok ? AppColors.brandBlue : context.textMuted)),
      ]),
    ).animate().fadeIn(duration: 160.ms);
  }
}
