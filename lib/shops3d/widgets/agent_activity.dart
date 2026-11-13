import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../shared/theme/app_theme.dart';

enum AgentState { idle, working, done, failed }

/// What Ova is doing for the seller right now.
///
/// Sits small at the bottom of the product creator: one line with the current
/// step and a thin progress bar. Tap to open the full activity log; tap again
/// (or the chevron) to tuck it away so it never blocks the form.
class AgentActivityBar extends StatefulWidget {
  const AgentActivityBar({
    super.key,
    required this.state,
    required this.now,
    this.progress,
    this.log = const [],
    this.action,
  });

  final AgentState state;

  /// The current step in plain words ("Reading your photos").
  final String now;

  /// 0..1, or null for an indeterminate step.
  final double? progress;

  /// Finished and current steps, oldest first.
  final List<String> log;

  /// Optional follow-up (label, handler), e.g. "Try again".
  final (String, VoidCallback)? action;

  @override
  State<AgentActivityBar> createState() => _AgentActivityBarState();
}

class _AgentActivityBarState extends State<AgentActivityBar> {
  bool _open = false;
  bool _mini = false;

  Color get _tone => switch (widget.state) {
        AgentState.failed => AppColors.brandPink,
        _ => AppColors.brandBlue,
      };

  IconData get _icon => switch (widget.state) {
        AgentState.done => Icons.check_circle_rounded,
        AgentState.failed => Icons.error_outline_rounded,
        _ => Icons.auto_awesome_rounded,
      };

  @override
  Widget build(BuildContext context) {
    if (widget.state == AgentState.idle) return const SizedBox.shrink();
    final working = widget.state == AgentState.working;

    if (_mini) {
      return Align(
        alignment: Alignment.centerRight,
        child: Tooltip(
          message: widget.now,
          child: GestureDetector(
            onTap: () => setState(() => _mini = false),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: context.surface,
                shape: BoxShape.circle,
                border: Border.all(color: context.border),
                boxShadow: AppShadows.sm,
              ),
              child: Stack(alignment: Alignment.center, children: [
                if (working)
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(value: widget.progress, strokeWidth: 2, color: _tone, backgroundColor: context.surfaceMid),
                  ),
                Icon(_icon, size: 16, color: _tone),
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border),
        boxShadow: AppShadows.sm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: widget.log.isEmpty
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    setState(() => _open = !_open);
                  },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              child: Row(
                children: [
                  Icon(_icon, size: 16, color: _tone)
                      .animate(target: working ? 1 : 0, onPlay: (c) => working ? c.repeat(reverse: true) : null)
                      .fade(begin: 1, end: 0.45, duration: 700.ms),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                      child: Text(
                        widget.now,
                        key: ValueKey(widget.now),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.small(context.textPrimary).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (widget.action != null)
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: _tone),
                      onPressed: widget.action!.$2,
                      child: Text(widget.action!.$1),
                    ),
                  if (widget.log.isNotEmpty)
                    Icon(_open ? Icons.expand_more_rounded : Icons.expand_less_rounded, size: 18, color: context.textMuted),
                  IconButton(
                    tooltip: 'Minimize',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.remove_rounded, size: 16, color: context.textMuted),
                    onPressed: () => setState(() {
                      _mini = true;
                      _open = false;
                    }),
                  ),
                ],
              ),
            ),
          ),
          if (working)
            LinearProgressIndicator(value: widget.progress, minHeight: 2, color: _tone, backgroundColor: context.surfaceMid),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: ListView(
                      shrinkWrap: true,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      children: [
                        for (final (i, line) in widget.log.reversed.indexed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(
                                  i == 0 && working ? Icons.more_horiz_rounded : Icons.check_rounded,
                                  size: 12,
                                  color: i == 0 && working ? _tone : context.textMuted,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(child: Text(line, style: AppTypography.caption(i == 0 ? context.textPrimary : context.textSecondary))),
                            ]),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
