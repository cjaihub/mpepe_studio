// Oneova compact UI parts. Use these instead of hand-built boxes so every
// screen stays small, calm and consistent (see .agents/rules/oneova_build_vision.md §4).
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

const Duration _kAnim = Duration(milliseconds: 200);

bool _reduceMotion(BuildContext context) => MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// Small caps label above a group.
class CompactSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const CompactSectionHeader(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: AppTypography.micro(context.textMuted).copyWith(letterSpacing: 0.8),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// One quiet container that holds thin rows separated by hairlines.
class CompactGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const CompactGroup({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, thickness: 1, indent: 44, color: context.border));
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) CompactSectionHeader(title!),
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Column(mainAxisSize: MainAxisSize.min, children: rows),
          ),
        ),
      ],
    );
  }
}

/// A thin tappable row: icon, title, optional subtitle and value, chevron.
class CompactRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool dot;
  final bool showChevron;

  const CompactRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.dot = false,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final danger = Theme.of(context).colorScheme.error;
    final fg = destructive ? danger : context.textPrimary;
    final iconColor = destructive ? danger : AppColors.brandBlue;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 46),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.bodyMedium(fg)),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption(context.textMuted)),
                        ),
                    ],
                  ),
                ),
                if (dot)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 8),
                    decoration: const BoxDecoration(color: AppColors.brandPink, shape: BoxShape.circle),
                  ),
                if (value != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(value!, style: AppTypography.small(context.textMuted)),
                  ),
                if (trailing != null) Padding(padding: const EdgeInsets.only(left: 8), child: trailing),
                if (trailing == null && showChevron && onTap != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.chevron_right_rounded, size: 18, color: context.textMuted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small card (12 px padding, 12 px corners, hairline, no heavy shadow).
/// Only for things that must stand out.
class CompactCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool highlight;
  const CompactCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(12), this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.md);
    return Material(
      color: context.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: highlight ? AppColors.brandBlue.withValues(alpha: 0.45) : context.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Small pill chip, optionally selected.
class CompactChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  const CompactChip({super.key, required this.label, this.icon, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : context.textSecondary;
    return AnimatedContainer(
      duration: _reduceMotion(context) ? Duration.zero : _kAnim,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? AppColors.brandBlue : context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: selected ? AppColors.brandBlue : context.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.full),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
                Text(label, style: AppTypography.small(fg).copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows [summary] and reveals [details] on tap.
class CompactShowMore extends StatefulWidget {
  final Widget summary;
  final Widget details;
  final bool initiallyOpen;
  const CompactShowMore({super.key, required this.summary, required this.details, this.initiallyOpen = false});

  @override
  State<CompactShowMore> createState() => _CompactShowMoreState();
}

class _CompactShowMoreState extends State<CompactShowMore> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final d = _reduceMotion(context) ? Duration.zero : _kAnim;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () => setState(() => _open = !_open),
          child: Row(
            children: [
              Expanded(child: widget.summary),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: d,
                child: Icon(Icons.expand_more_rounded, size: 18, color: context.textMuted),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: d,
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _open ? Padding(padding: const EdgeInsets.only(top: 8), child: widget.details) : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// One small animated line for work Ova or an agent is doing in the
/// background ("Opening Chrome on your Mac…"). No logs or tool names.
class OvaActivityPill extends StatefulWidget {
  final String message;
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onStop;
  const OvaActivityPill({super.key, required this.message, this.icon = Icons.auto_awesome_rounded, this.onTap, this.onStop});

  @override
  State<OvaActivityPill> createState() => _OvaActivityPillState();
}

class _OvaActivityPillState extends State<OvaActivityPill> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      _c.stop();
      _c.value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: widget.message,
      child: Material(
        color: context.surfaceMid,
        shape: StadiumBorder(side: BorderSide(color: context.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: Tween<double>(begin: 0.45, end: 1).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.9, end: 1.05).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
                    child: Icon(widget.icon, size: 16, color: AppColors.brandBlue),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: AnimatedSwitcher(
                    duration: _reduceMotion(context) ? Duration.zero : _kAnim,
                    child: Text(
                      widget.message,
                      key: ValueKey(widget.message),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.small(context.textSecondary),
                    ),
                  ),
                ),
                if (widget.onStop != null) ...[
                  const SizedBox(width: 6),
                  InkResponse(
                    radius: 14,
                    onTap: widget.onStop,
                    child: Icon(Icons.stop_circle_outlined, size: 16, color: context.textMuted, semanticLabel: 'Stop'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
