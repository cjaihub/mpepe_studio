import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart';
import '../services/ova_auth_coach.dart';

/// One-line Ova feedback shown right under a field. Animates between hints
/// so the user sees each change as it happens.
class OvaInlineHint extends StatelessWidget {
  final OvaHint? hint;
  final EdgeInsetsGeometry padding;

  const OvaInlineHint(this.hint, {super.key, this.padding = const EdgeInsets.only(top: 6)});

  @override
  Widget build(BuildContext context) {
    final h = hint;
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topLeft,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, -0.25), end: Offset.zero).animate(anim),
            child: child,
          ),
        ),
        child: h == null
            ? const SizedBox(width: double.infinity, key: ValueKey('none'))
            : Padding(
                key: ValueKey(h),
                padding: padding,
                child: _HintRow(hint: h),
              ),
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  final OvaHint hint;
  const _HintRow({required this.hint});

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (hint.tone) {
      OvaHintTone.success => (AppColors.brandBlue, Icons.check_circle_rounded),
      OvaHintTone.warning => (AppColors.brandPink, Icons.info_rounded),
      OvaHintTone.error => (AppColors.brandPink, Icons.error_rounded),
      OvaHintTone.working => (AppColors.brandBlue, Icons.auto_awesome_rounded),
      OvaHintTone.info => (context.textSecondary, Icons.auto_awesome_rounded),
    };
    return Semantics(
      liveRegion: true,
      label: 'Ova: ${hint.text}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.only(top: 0.5),
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: hint.tone == OvaHintTone.working
                ? const SizedBox(
                    width: 9,
                    height: 9,
                    child: CircularProgressIndicator(strokeWidth: 1.4, color: AppColors.brandBlue),
                  )
                : Icon(icon, size: 11, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(
                  text: 'Ova · ',
                  style: TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.w800),
                ),
                TextSpan(text: hint.text),
              ]),
              style: TextStyle(
                color: hint.tone == OvaHintTone.info ? context.textSecondary : color,
                fontSize: 11.2,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
