import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../backend/live/models/live_studio_models.dart';
import '../../../../shared/theme/obsidian_telemetry_tokens.dart';
import 'studio_world.dart' show LivePill;

// ─────────────────────────────────────────────────────────────────────────────
// SHARED
// ─────────────────────────────────────────────────────────────────────────────

String formatLiveCount(int count) {
  if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
  if (count >= 1000) {
    final k = count / 1000;
    return '${k >= 100 ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}K';
  }
  return '$count';
}

String formatPrice(num? price, String currency) {
  if (price == null) return 'Price on request';
  final fixed = price == price.roundToDouble()
      ? price.toInt().toString()
      : price.toStringAsFixed(2);
  return '$currency $fixed';
}

/// DESIGN.md Layer 3 glass: rgba(17,17,21,.85) + 20px blur + neon perimeter.
class GlassBox extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color borderColor;

  const GlassBox({
    super.key,
    required this.child,
    this.radius = OTRadius.lg,
    this.padding,
    this.borderColor = OTColors.hairline08,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: OTColors.glass85,
            borderRadius: r,
            border: Border.all(color: borderColor, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 44px icon button (ghost style from DESIGN.md).
class StudioIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final Color? color;
  final bool filled;

  const StudioIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = onPressed == null
        ? OTColors.textMuted
        : (color ?? (active ? OTColors.neonPink : OTColors.textMedium));
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        enabled: onPressed != null,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed == null
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    onPressed!();
                  },
            borderRadius: BorderRadius.circular(OTRadius.base),
            hoverColor: OTColors.pinkHover08,
            splashColor: OTColors.pinkHover08,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: filled
                    ? OTColors.surface2
                    : (active ? OTColors.pinkTint15 : null),
                borderRadius: BorderRadius.circular(OTRadius.base),
                border: filled ? Border.all(color: OTColors.hairline12) : null,
              ),
              child: Icon(icon, size: 20, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────────────────────────────────────

enum StudioJoinState { hidden, idle, pending, onStage, busy }

class StudioTopBar extends StatelessWidget {
  final String title;
  final int viewerCount;
  final bool compact;
  final StudioJoinState joinState;
  final VoidCallback onJoinPressed;
  final VoidCallback onShare;
  final VoidCallback onClose;

  const StudioTopBar({
    super.key,
    required this.title,
    required this.viewerCount,
    required this.compact,
    required this.joinState,
    required this.onJoinPressed,
    required this.onShare,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const LivePill(fontSize: 12),
        const SizedBox(width: OTSpace.sm),
        ViewerChip(count: viewerCount),
        const SizedBox(width: OTSpace.md),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: compact ? OTType.labelMd() : OTType.headlineSm()),
              if (!compact)
                Text('Interactive live room',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OTType.bodySm()),
            ],
          ),
        ),
        if (joinState != StudioJoinState.hidden) ...[
          _JoinButton(state: joinState, compact: compact, onPressed: onJoinPressed),
          const SizedBox(width: OTSpace.sm),
        ],
        StudioIconButton(
          icon: Icons.ios_share_rounded,
          label: 'Share live',
          onPressed: onShare,
          color: OTColors.textHigh,
        ),
        StudioIconButton(
          icon: Icons.close_rounded,
          label: 'Leave live',
          onPressed: onClose,
          color: OTColors.textHigh,
        ),
      ],
    );
  }
}

class ViewerChip extends StatelessWidget {
  final int count;
  const ViewerChip({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$count viewers',
      child: GlassBox(
        radius: OTRadius.full,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.visibility_outlined,
                  size: 14, color: OTColors.textMedium),
              const SizedBox(width: 5),
              Text(formatLiveCount(count), style: OTType.labelMd()),
            ],
          ),
        ),
      ),
    );
  }
}

class _JoinButton extends StatelessWidget {
  final StudioJoinState state;
  final bool compact;
  final VoidCallback onPressed;
  const _JoinButton(
      {required this.state, required this.compact, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String label, bool enabled) = switch (state) {
      StudioJoinState.idle => (Icons.add_rounded, 'Request to join', true),
      StudioJoinState.pending => (Icons.hourglass_top_rounded, 'Requested', true),
      StudioJoinState.onStage => (Icons.logout_rounded, 'Leave stage', true),
      StudioJoinState.busy => (Icons.more_horiz_rounded, 'Please wait', false),
      StudioJoinState.hidden => (Icons.add_rounded, '', false),
    };
    final semantic = switch (state) {
      StudioJoinState.pending => 'Join request sent. Tap to cancel',
      _ => label,
    };
    return Semantics(
      button: true,
      label: semantic,
      enabled: enabled,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled
              ? () {
                  HapticFeedback.lightImpact();
                  onPressed();
                }
              : null,
          borderRadius: BorderRadius.circular(OTRadius.base),
          hoverColor: OTColors.pinkHover08,
          child: Container(
            height: 44,
            padding: EdgeInsets.symmetric(horizontal: compact ? 11 : 16),
            decoration: BoxDecoration(
              color: OTColors.surface2,
              borderRadius: BorderRadius.circular(OTRadius.base),
              border: Border.all(color: OTColors.hairline12),
            ),
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: OTColors.neonPink),
                  if (!compact) ...[
                    const SizedBox(width: 6),
                    Text(label, style: OTType.labelMd().copyWith(fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMENT FEED
// ─────────────────────────────────────────────────────────────────────────────

class StudioFeedItem {
  final String id;
  final String name;
  final String avatarUrl;
  final String text;
  final bool isSystem;
  final bool isHighlighted;
  final DateTime at;

  const StudioFeedItem({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.text,
    required this.at,
    this.isSystem = false,
    this.isHighlighted = false,
  });
}

class StudioCommentFeed extends StatelessWidget {
  /// Oldest → newest. Only the newest [maxVisible] are shown, newest at bottom.
  final List<StudioFeedItem> items;
  final int maxVisible;

  const StudioCommentFeed({super.key, required this.items, this.maxVisible = 5});

  @override
  Widget build(BuildContext context) {
    final visible = items.length <= maxVisible
        ? items
        : items.sublist(items.length - maxVisible);
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Live comments',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in visible)
            Padding(
              key: ValueKey(item.id),
              padding: const EdgeInsets.only(top: OTSpace.sm),
              child: _FeedRow(item: item)
                  .animate()
                  .fadeIn(duration: 250.ms)
                  .slideY(begin: 0.15, end: 0, duration: 250.ms),
            ),
        ],
      ),
    );
  }
}

class _FeedRow extends StatelessWidget {
  final StudioFeedItem item;
  const _FeedRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return GlassBox(
      radius: OTRadius.md,
      borderColor: item.isHighlighted ? OTColors.pinkBorder30 : OTColors.hairline08,
      padding: const EdgeInsets.fromLTRB(8, 7, 12, 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          StudioAvatar(name: item.name, url: item.avatarUrl, size: 28),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OTType.chat(weight: FontWeight.w600)),
                Text(item.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: OTType.chat(
                        color: item.isSystem
                            ? OTColors.textMedium
                            : OTColors.textHigh)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar with the #FF2D75 ring.
class StudioAvatar extends StatelessWidget {
  final String name;
  final String url;
  final double size;
  const StudioAvatar({super.key, required this.name, required this.url, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final fallback = Center(
      child: Text(initial,
          style: OTType.pill(size * 0.4, color: OTColors.textHigh)),
    );
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: OTColors.neonPink, width: 1.5),
      ),
      child: ClipOval(
        child: ColoredBox(
          color: OTColors.surface3,
          child: url.isEmpty
              ? fallback
              : Image.network(url,
                  fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHOW LOVE + FLOATING HEARTS
// ─────────────────────────────────────────────────────────────────────────────

class ShowLoveButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool showLabel;
  const ShowLoveButton({super.key, required this.onPressed, this.showLabel = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: 'Show love',
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                HapticFeedback.lightImpact();
                onPressed();
              },
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: OTColors.pinkTint15,
                  shape: BoxShape.circle,
                  border: Border.all(color: OTColors.neonPink, width: 1),
                  boxShadow: OTShadows.bloom,
                ),
                child: const Icon(Icons.favorite_rounded,
                    color: OTColors.neonPink, size: 26),
              ),
            ),
          ),
        ),
        if (showLabel) ...[
          const SizedBox(height: 6),
          ExcludeSemantics(child: Text('SHOW LOVE', style: OTType.labelSm())),
        ],
      ],
    );
  }
}

class FloatingHeartSpec {
  final int id;
  final double drift; // horizontal drift in px
  final double size;
  final bool cyan;
  const FloatingHeartSpec(
      {required this.id, required this.drift, required this.size, this.cyan = false});
}

/// Hearts that rise from the Show love button. Purely decorative.
class FloatingHeartsLayer extends StatelessWidget {
  final List<FloatingHeartSpec> hearts;
  final ValueChanged<int> onDone;
  final double height;

  const FloatingHeartsLayer({
    super.key,
    required this.hearts,
    required this.onDone,
    this.height = 260,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox(
          width: 80,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final h in hearts)
                Positioned(
                  key: ValueKey(h.id),
                  bottom: 0,
                  left: 40 - h.size / 2,
                  child: Icon(Icons.favorite_rounded,
                          size: h.size,
                          color: h.cyan ? OTColors.telemetryCyan : OTColors.neonPink)
                      .animate(onComplete: (_) => onDone(h.id))
                      .scaleXY(begin: 0.4, end: 1, duration: 300.ms, curve: Curves.easeOut)
                      .moveY(begin: 0, end: -height, duration: 2200.ms, curve: Curves.easeOut)
                      .moveX(begin: 0, end: h.drift, duration: 2200.ms, curve: Curves.easeInOut)
                      .fadeOut(delay: 1300.ms, duration: 900.ms),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TABS, COMPOSER, DOCK, PHONE SHEET
// ─────────────────────────────────────────────────────────────────────────────

enum StudioTab { lobby, goods, room, participants, activity }

extension StudioTabX on StudioTab {
  String get label => switch (this) {
        StudioTab.lobby => 'Lobby',
        StudioTab.goods => "Presenter's Goods",
        StudioTab.room => 'Interactive Map / Room',
        StudioTab.participants => 'Participants',
        StudioTab.activity => 'Activity & Chat',
      };

  IconData get icon => switch (this) {
        StudioTab.lobby => Icons.home_outlined,
        StudioTab.goods => Icons.inventory_2_outlined,
        StudioTab.room => Icons.map_outlined,
        StudioTab.participants => Icons.people_outline_rounded,
        StudioTab.activity => Icons.chat_bubble_outline_rounded,
      };
}

class StudioTabChip extends StatelessWidget {
  final StudioTab tab;
  final bool active;
  final bool showDot;
  final int? count;
  final bool iconOnly;
  final VoidCallback onTap;

  const StudioTabChip({
    super.key,
    required this.tab,
    required this.active,
    required this.onTap,
    this.showDot = false,
    this.count,
    this.iconOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? OTColors.textHigh : OTColors.textMedium;
    final semantic = [
      tab.label,
      if (count != null) '$count',
      if (showDot) 'new activity',
      if (active) 'selected',
    ].join(', ');
    final chip = Semantics(
        button: true,
        selected: active,
        label: semantic,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            borderRadius: BorderRadius.circular(OTRadius.base),
            hoverColor: OTColors.pinkHover08,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 44,
              padding: EdgeInsets.symmetric(horizontal: iconOnly ? 12 : 14),
              decoration: BoxDecoration(
                color: active ? OTColors.pinkTint15 : Colors.transparent,
                borderRadius: BorderRadius.circular(OTRadius.base),
                border: Border.all(
                  color: active ? OTColors.neonPink : Colors.transparent,
                  width: 1,
                ),
              ),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tab.icon, size: 18, color: active ? OTColors.neonPink : fg),
                    if (!iconOnly) ...[
                      const SizedBox(width: 8),
                      Text(tab.label,
                          style: OTType.labelMd(color: fg).copyWith(fontSize: 13)),
                    ],
                    if (count != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: OTColors.surface3,
                          borderRadius: BorderRadius.circular(OTRadius.full),
                        ),
                        child: Text(formatLiveCount(count!), style: OTType.labelSm()),
                      ),
                    ],
                    if (showDot) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            color: OTColors.neonPink, shape: BoxShape.circle),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    return iconOnly ? Tooltip(message: tab.label, child: chip) : chip;
  }
}

/// Comment input (#0E0E12, pink focus ring) + pink Send button. Enter sends.
class StudioComposer extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSend;
  final bool enabled;
  final String hint;

  const StudioComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    this.enabled = true,
    this.hint = 'Type a comment…',
  });

  @override
  State<StudioComposer> createState() => _StudioComposerState();
}

class _StudioComposerState extends State<StudioComposer> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant StudioComposer old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() => setState(() {});

  void _send() {
    final text = widget.controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    widget.onSend(text);
    widget.controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final focused = widget.focusNode.hasFocus;
    return Row(
      children: [
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 44,
            decoration: BoxDecoration(
              color: OTColors.inputWell,
              borderRadius: BorderRadius.circular(OTRadius.base),
              border: Border.all(
                color: focused ? OTColors.neonPink : OTColors.hairline10,
                width: 1,
              ),
              boxShadow: focused
                  ? const [BoxShadow(color: OTColors.pinkFocus20, spreadRadius: 3)]
                  : const [],
            ),
            alignment: Alignment.centerLeft,
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              enabled: widget.enabled,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                _send();
                widget.focusNode.requestFocus();
              },
              maxLength: 1000,
              cursorColor: OTColors.neonPink,
              style: OTType.chat(),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                hintText: widget.enabled ? widget.hint : 'Sign in to comment',
                hintStyle: OTType.chat(color: OTColors.textMuted),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                semanticCounterText: '',
              ),
            ),
          ),
        ),
        const SizedBox(width: OTSpace.sm),
        Semantics(
          button: true,
          label: 'Send comment',
          child: Material(
            color: OTColors.neonPink,
            borderRadius: BorderRadius.circular(OTRadius.base),
            child: InkWell(
              borderRadius: BorderRadius.circular(OTRadius.base),
              hoverColor: OTColors.neonPinkHover,
              onTap: widget.enabled ? _send : null,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.send_rounded, size: 18, color: OTColors.textHigh),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Everything the dock / sheet needs, so both layouts share one source.
class StudioDockModel {
  final StudioTab activeTab;
  final ValueChanged<StudioTab> onTab;
  final Set<StudioTab> dots;
  final int participantCount;
  final bool showWallGuests;
  final VoidCallback onToggleWall;
  final bool cleanView;
  final VoidCallback onToggleCleanView;
  final bool canUseCamera;
  final bool cameraOff;
  final VoidCallback onToggleCamera;
  final bool micMuted;
  final VoidCallback onToggleMic;
  final TextEditingController composer;
  final FocusNode composerFocus;
  final ValueChanged<String> onSend;
  final bool canComment;

  const StudioDockModel({
    required this.activeTab,
    required this.onTab,
    required this.dots,
    required this.participantCount,
    required this.showWallGuests,
    required this.onToggleWall,
    required this.cleanView,
    required this.onToggleCleanView,
    required this.canUseCamera,
    required this.cameraOff,
    required this.onToggleCamera,
    required this.micMuted,
    required this.onToggleMic,
    required this.composer,
    required this.composerFocus,
    required this.onSend,
    required this.canComment,
  });

  List<Widget> utilityButtons() => [
        StudioIconButton(
          icon: Icons.grid_view_rounded,
          label: showWallGuests ? 'Hide guest windows' : 'Show guest windows',
          active: !showWallGuests,
          onPressed: onToggleWall,
        ),
        StudioIconButton(
          icon: Icons.view_quilt_outlined,
          label: cleanView ? 'Show comments' : 'Clean view (hide comments)',
          active: cleanView,
          onPressed: onToggleCleanView,
        ),
        StudioIconButton(
          icon: canUseCamera && cameraOff
              ? Icons.videocam_off_outlined
              : Icons.videocam_outlined,
          label: canUseCamera
              ? (cameraOff ? 'Turn camera on' : 'Turn camera off')
              : 'Join the stage to use your camera',
          active: canUseCamera && cameraOff,
          onPressed: canUseCamera ? onToggleCamera : null,
        ),
        if (canUseCamera)
          StudioIconButton(
            icon: micMuted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
            label: micMuted ? 'Unmute microphone' : 'Mute microphone',
            active: micMuted,
            onPressed: onToggleMic,
          ),
      ];

  List<Widget> tabChips({required bool iconOnly}) => [
        for (final t in StudioTab.values)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: StudioTabChip(
              tab: t,
              active: activeTab == t,
              iconOnly: iconOnly,
              showDot: dots.contains(t),
              count: t == StudioTab.participants ? participantCount : null,
              onTap: () => onTab(t),
            ),
          ),
      ];

  Widget composerWidget() => StudioComposer(
        controller: composer,
        focusNode: composerFocus,
        onSend: onSend,
        enabled: canComment,
      );
}

/// Landscape: one glass bar.
class StudioDock extends StatelessWidget {
  final StudioDockModel model;
  const StudioDock({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final iconOnly = c.maxWidth < 1180;
      final composerWidth = (c.maxWidth * 0.26).clamp(220.0, 360.0);
      return GlassBox(
        radius: OTRadius.lg,
        padding: const EdgeInsets.all(OTSpace.sm),
        child: Row(
          children: [
            ...model.utilityButtons(),
            Container(
              width: 1,
              height: 28,
              margin: const EdgeInsets.symmetric(horizontal: OTSpace.sm),
              color: OTColors.hairline12,
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: model.tabChips(iconOnly: iconOnly)),
              ),
            ),
            const SizedBox(width: OTSpace.sm),
            SizedBox(width: composerWidth, child: model.composerWidget()),
          ],
        ),
      );
    });
  }
}

/// Phone: bottom sheet in #111115 with a drag handle. Expands to show the
/// active panel; drag down (or tap the handle) to collapse.
class StudioPhoneSheet extends StatelessWidget {
  final StudioDockModel model;
  final Widget? panel;
  final double expandedPanelHeight;
  final VoidCallback onCollapse;
  final double bottomInset;

  const StudioPhoneSheet({
    super.key,
    required this.model,
    required this.panel,
    required this.expandedPanelHeight,
    required this.onCollapse,
    required this.bottomInset,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 200) onCollapse();
      },
      child: Container(
        decoration: const BoxDecoration(
          color: OTColors.surface1,
          borderRadius: BorderRadius.vertical(top: Radius.circular(OTRadius.xl)),
          border: Border(top: BorderSide(color: OTColors.hairline08)),
        ),
        padding: EdgeInsets.fromLTRB(
            OTSpace.margin, 0, OTSpace.margin, OTSpace.sm + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: panel != null,
              label: panel != null ? 'Collapse panel' : 'Sheet handle',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: panel != null ? onCollapse : null,
                child: SizedBox(
                  height: 24,
                  width: 88,
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: OTColors.textMuted,
                        borderRadius: BorderRadius.circular(OTRadius.full),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: panel == null
                  ? const SizedBox(width: double.infinity)
                  : SizedBox(
                      height: expandedPanelHeight,
                      width: double.infinity,
                      child: panel,
                    ),
            ),
            SizedBox(
              height: 48,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ...model.utilityButtons(),
                    Container(
                      width: 1,
                      height: 24,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      color: OTColors.hairline12,
                    ),
                    ...model.tabChips(iconOnly: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: OTSpace.xs),
            model.composerWidget(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRESENTER'S GOODS CARD (glass card floating above the stand)
// ─────────────────────────────────────────────────────────────────────────────

class GoodsCard extends StatelessWidget {
  final AsyncSnapshotLike<LiveProduct?> product;
  final VoidCallback onViewItem;
  final bool compact;

  const GoodsCard({
    super.key,
    required this.product,
    required this.onViewItem,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = product.data;
    final Widget body;
    if (product.isLoading) {
      body = Row(children: [
        const _Thumb(url: '', loading: true),
        const SizedBox(width: 10),
        Expanded(child: Text('Loading goods…', style: OTType.bodySm())),
      ]);
    } else if (p == null) {
      return const SizedBox.shrink(); // nothing featured → stand stays empty
    } else {
      body = Row(children: [
        _Thumb(url: p.imageUrl),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OTType.labelMd().copyWith(fontSize: 14)),
              const SizedBox(height: 2),
              Text(formatPrice(p.price, p.currency),
                  style: OTType.labelMd(color: OTColors.textMedium)),
            ],
          ),
        ),
      ]);
    }

    final viewButton = Semantics(
      button: true,
      label: p == null ? 'View item' : 'View ${p.name}',
      child: Material(
        color: OTColors.neonPink,
        borderRadius: BorderRadius.circular(OTRadius.base),
        child: InkWell(
          onTap: p == null ? null : onViewItem,
          borderRadius: BorderRadius.circular(OTRadius.base),
          hoverColor: OTColors.neonPinkHover,
          child: SizedBox(
            height: 44,
            width: compact ? 88 : double.infinity,
            child: Center(
              child: ExcludeSemantics(
                child: Text('View item', style: OTType.labelMd().copyWith(fontSize: 13)),
              ),
            ),
          ),
        ),
      ),
    );

    return GlassBox(
      radius: OTRadius.md,
      borderColor: OTColors.pinkBorder30,
      padding: const EdgeInsets.all(OTSpace.md),
      child: compact
          ? Row(children: [Expanded(child: body), const SizedBox(width: 10), viewButton])
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("PRESENTER'S GOODS",
                    style: OTType.labelSm(color: OTColors.neonPink)),
                const SizedBox(height: OTSpace.sm),
                body,
                const SizedBox(height: OTSpace.md),
                viewButton,
              ],
            ),
    );
  }
}

/// Minimal async view so GoodsCard doesn't depend on Riverpod types.
class AsyncSnapshotLike<T> {
  final T? data;
  final bool isLoading;
  const AsyncSnapshotLike({this.data, this.isLoading = false});
}

class _Thumb extends StatelessWidget {
  final String url;
  final bool loading;
  const _Thumb({required this.url, this.loading = false});

  @override
  Widget build(BuildContext context) {
    const icon = Icon(Icons.inventory_2_outlined,
        size: 20, color: OTColors.telemetryCyan);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: OTColors.surface2,
        borderRadius: BorderRadius.circular(OTRadius.base),
        border: Border.all(color: OTColors.hairline08),
      ),
      clipBehavior: Clip.antiAlias,
      child: loading
          ? const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: OTColors.neonPink),
              ),
            )
          : (url.isEmpty
              ? icon
              : Image.network(url,
                  fit: BoxFit.cover, errorBuilder: (_, _, _) => icon)),
    );
  }
}
