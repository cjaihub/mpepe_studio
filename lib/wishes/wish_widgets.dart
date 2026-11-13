import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart';

/// Status pill shared by the list and detail screens.
class WishStatusChip extends StatelessWidget {
  const WishStatusChip({super.key, required this.status});
  final String status;

  static String labelOf(String s) => switch (s) {
        'planned' => 'Planned',
        'building' => 'Building',
        'shipped' => 'Shipped',
        'declined' => 'Not now',
        _ => 'Open',
      };

  static IconData iconOf(String s) => switch (s) {
        'planned' => Icons.event_note_rounded,
        'building' => Icons.construction_rounded,
        'shipped' => Icons.rocket_launch_rounded,
        'declined' => Icons.pause_circle_outline_rounded,
        _ => Icons.lightbulb_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final Color fg = switch (status) {
      'planned' || 'building' => AppColors.brandBlue,
      'shipped' => AppColors.brandPink,
      _ => context.textMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(iconOf(status), size: 13, color: fg),
        const SizedBox(width: 4),
        Text(labelOf(status), style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// "Me too" — the single reaction a person can give an idea.
class WishReactButton extends StatelessWidget {
  const WishReactButton({super.key, required this.reacted, required this.count, required this.onTap});
  final bool reacted;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = reacted ? AppColors.brandWhite : AppColors.brandBlue;
    return Material(
      color: reacted ? AppColors.brandBlue : AppColors.brandBlue.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(reacted ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined, size: 15, color: fg),
              const SizedBox(width: 5),
              Text(count > 0 ? 'Me too · $count' : 'Me too',
                  style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The official reply from the Oneova team, shown in a quiet blue strip.
class WishTeamReply extends StatelessWidget {
  const WishTeamReply({super.key, required this.text, this.maxLines});
  final String text;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.brandBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: AppColors.brandBlue, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.verified_rounded, size: 14, color: AppColors.brandBlue),
          const SizedBox(width: 4),
          Text('Oneova team',
              style: TextStyle(color: AppColors.brandBlue, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        Text(text,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
            style: TextStyle(color: context.textPrimary, fontSize: 13.5, height: 1.35)),
      ]),
    );
  }
}

class WishAvatar extends StatelessWidget {
  const WishAvatar({super.key, required this.url, required this.name, this.size = 28});
  final String url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: context.surfaceMid,
      backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
      child: url.isEmpty
          ? Text(name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
              style: TextStyle(color: context.textSecondary, fontSize: size * 0.42, fontWeight: FontWeight.w600))
          : null,
    );
  }
}

String wishCategoryLabel(String c) => switch (c) {
      'creator_money' => 'Creator money',
      'ai' => 'AI',
      '' => '',
      _ => '${c[0].toUpperCase()}${c.substring(1)}',
    };
