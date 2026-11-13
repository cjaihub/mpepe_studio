import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart';

enum VerifiedKind { person, business }

/// The one verified badge used by the profile, the store, the shop header and
/// the live stage. Person: blue check. Business: blue storefront check;
/// level 2 (Verified Business) gets the pink ring.
class OneovaVerifiedBadge extends StatelessWidget {
  const OneovaVerifiedBadge({super.key, this.kind = VerifiedKind.person, this.level = 2, this.size = 16, this.showLabel = false});

  final VerifiedKind kind;
  final int level;
  final double size;
  final bool showLabel;

  String get label => switch ((kind, level)) {
        (VerifiedKind.business, >= 2) => 'Verified Business',
        (VerifiedKind.business, _) => 'Registered business',
        (_, >= 2) => 'ID verified',
        _ => 'Contact verified',
      };

  @override
  Widget build(BuildContext context) {
    final strong = level >= 2;
    final icon = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: strong ? AppColors.brandBlue : AppColors.brandBlue.withValues(alpha: 0.65),
        border: kind == VerifiedKind.business && strong ? Border.all(color: AppColors.brandPink, width: size * 0.09) : null,
      ),
      child: Icon(kind == VerifiedKind.business ? Icons.storefront_rounded : Icons.check_rounded, size: size * 0.62, color: Colors.white),
    );
    final badge = Semantics(label: label, child: icon);
    if (!showLabel) return Tooltip(message: label, child: badge);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      badge,
      SizedBox(width: size * 0.35),
      Text(label, style: TextStyle(fontSize: size * 0.75, fontWeight: FontWeight.w700, color: context.textPrimary)),
    ]);
  }
}
