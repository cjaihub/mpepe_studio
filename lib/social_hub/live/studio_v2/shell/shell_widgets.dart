import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import '../../../../backend/live_studio/social/studio_comment_feed_controller.dart';
import '../../../../backend/live_studio/social/studio_counts_controller.dart';
import '../../../../backend/live_studio/social/studio_follow_controller.dart';
import '../../../../backend/live_studio/fun/studio_fun.dart';
import '../../../../backend/live_studio/social/studio_reactions_controller.dart';
import '../../../../backend/live_studio/session/studio_session_controller.dart';
import '../fun/gif_picker.dart';
import '../fun/gifts_ui.dart';
import '../theme/live_studio_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LIVE STUDIO v2 — UI SHELL BUILDING BLOCKS (SPEC §1, §3).
// Sizes and colors follow the HTML prototype; colors come from the tokens.
// ─────────────────────────────────────────────────────────────────────────────

/// Frosted glass capsule/group (rgba glass + blur 20 + hairline + shadow).
class GlassBox extends StatelessWidget {
  const GlassBox({
    super.key,
    required this.tokens,
    required this.child,
    this.height,
    this.padding = EdgeInsets.zero,
    this.radius = 9999,
    this.phone = false,
  });

  final LiveStudioTokens tokens;
  final Widget child;
  final double? height;
  final EdgeInsets padding;
  final double radius;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(color: tokens.glassShadow(), blurRadius: phone ? 18 : 24, offset: Offset(0, phone ? 6 : 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
              sigmaX: LiveStudioTokens.glassBlurSigma, sigmaY: LiveStudioTokens.glassBlurSigma),
          child: Container(
            height: height,
            padding: padding,
            decoration: BoxDecoration(
              color: tokens.glass,
              borderRadius: r,
              border: Border.all(color: phone ? tokens.glassBorderPhone : tokens.glassBorderLandscape),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Round 44 px (default) icon button with focus ring, press scale and a label.
class StudioRoundButton extends StatefulWidget {
  const StudioRoundButton({
    super.key,
    required this.tokens,
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 44,
    this.iconSize = 20,
    this.fill,
    this.border,
    this.color,
    this.gradient,
    this.shadow,
    this.badge,
  });

  final LiveStudioTokens tokens;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color? fill;
  final Color? border;
  final Color? color;
  final Gradient? gradient;
  final List<BoxShadow>? shadow;
  final Widget? badge;

  @override
  State<StudioRoundButton> createState() => _StudioRoundButtonState();
}

class _StudioRoundButtonState extends State<StudioRoundButton> {
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    // Keep the touch target at least 44 px even for smaller visuals.
    final target = math.max(44.0, widget.size);
    return Semantics(
      button: true,
      label: widget.label,
      enabled: widget.onTap != null,
      child: FocusableActionDetector(
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onTap?.call();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onTap == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  widget.onTap!();
                },
          child: SizedBox(
            width: target,
            height: target,
            child: Center(
              child: AnimatedScale(
                scale: _down ? LiveStudioMotion.pressScale : 1,
                duration: LiveStudioMotion.press,
                child: Stack(clipBehavior: Clip.none, children: [
                  Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.gradient == null ? (widget.fill ?? t.ghostFill) : null,
                      gradient: widget.gradient,
                      border: widget.border == null && widget.gradient != null
                          ? null
                          : Border.all(color: _focus ? t.focusRing : (widget.border ?? t.ghostBorder),
                              width: _focus ? 2 : 1),
                      boxShadow: widget.shadow,
                    ),
                    child: Icon(widget.icon, size: widget.iconSize, color: widget.color ?? t.textHigh),
                  ),
                  if (widget.badge != null) Positioned(top: -6, right: -4, child: widget.badge!),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pill button (text + optional leading icon), e.g. Follow, room tabs.
class StudioPillButton extends StatelessWidget {
  const StudioPillButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.fill,
    required this.textColor,
    this.border,
    this.icon,
    this.iconColor,
    this.height = 44,
    this.padding = const EdgeInsets.symmetric(horizontal: 14),
    this.fontSize = 13,
    this.weight = FontWeight.w600,
    this.trailing,
    this.semanticsLabel,
    this.shadow,
  });

  final String label;
  final VoidCallback? onTap;
  final Color fill;
  final Color textColor;
  final Color? border;
  final IconData? icon;
  final Color? iconColor;
  final double height;
  final EdgeInsets padding;
  final double fontSize;
  final FontWeight weight;
  final Widget? trailing;
  final String? semanticsLabel;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(9999),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onTap!();
                },
          child: Container(
            height: height,
            constraints: const BoxConstraints(minHeight: 36, minWidth: 44),
            padding: padding,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(9999),
              border: Border.all(color: border ?? fill),
              boxShadow: shadow,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: iconColor ?? textColor),
                const SizedBox(width: 7),
              ],
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LiveStudioType.s(fontSize, weight, textColor, height: fontSize + 3)),
              if (trailing != null) ...[const SizedBox(width: 7), trailing!],
            ]),
          ),
        ),
      ),
    );
  }
}

/// LIVE status pill (red, pulsing dot).
class ShellLivePill extends StatefulWidget {
  const ShellLivePill({super.key, this.compact = false});
  final bool compact;

  @override
  State<ShellLivePill> createState() => _ShellLivePillState();
}

class _ShellLivePillState extends State<ShellLivePill> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: LiveStudioMotion.pulse)..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.compact;
    return Container(
      height: c ? 16 : 18,
      padding: EdgeInsets.symmetric(horizontal: c ? 6 : 7),
      decoration: BoxDecoration(color: LiveStudioAccent.liveRed, borderRadius: BorderRadius.circular(9999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FadeTransition(
          opacity: Tween(begin: 1.0, end: 0.35).animate(_c),
          child: ScaleTransition(
            scale: Tween(begin: 1.0, end: 0.7).animate(_c),
            child: Container(
              width: c ? 5 : 6,
              height: c ? 5 : 6,
              decoration: const BoxDecoration(color: LiveStudioAccent.white, shape: BoxShape.circle),
            ),
          ),
        ),
        SizedBox(width: c ? 4 : 5),
        Text('LIVE',
            style: LiveStudioType.s(c ? 9 : 10, FontWeight.w700, LiveStudioAccent.white,
                height: c ? 12 : 14, letter: 0.04)),
      ]),
    );
  }
}

/// Avatar circle: network photo, or the initial on [fill].
class StudioAvatar extends StatelessWidget {
  const StudioAvatar({super.key, required this.name, this.url = '', required this.size, required this.fill, this.ring, this.ringWidth = 2, this.textColor = LiveStudioAccent.white});
  final String name;
  final String url;
  final double size;
  final Color fill;
  final Color? ring;
  final double ringWidth;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: ring == null ? null : Border.all(color: ring!, width: ringWidth),
        image: url.isEmpty ? null : DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
      ),
      alignment: Alignment.center,
      child: url.isEmpty
          ? Text(initial, style: LiveStudioType.s(size * 0.4, FontWeight.w700, textColor))
          : null,
    );
  }
}

/// Host card: avatar with gradient ring, title, LIVE + viewers, Follow.
class HostCard extends ConsumerWidget {
  const HostCard({
    super.key,
    required this.tokens,
    required this.streamId,
    required this.title,
    required this.host,
    required this.phone,
  });

  final LiveStudioTokens tokens;
  final String streamId;
  final String title;
  final StageMember? host;
  final bool phone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(studioCountsProvider(streamId));
    final hostId = host?.uid ?? '';
    final follow = hostId.isEmpty ? null : ref.watch(studioFollowProvider(hostId));
    final following = follow?.isFollowing ?? false;
    final viewers = formatStudioCount(counts.viewers);
    final ring = phone ? 40.0 : 46.0;
    return GlassBox(
      tokens: tokens,
      phone: phone,
      height: phone ? 48 : 56,
      padding: phone ? const EdgeInsets.all(4) : const EdgeInsets.fromLTRB(5, 5, 6, 5),
      child: Row(mainAxisSize: phone ? MainAxisSize.max : MainAxisSize.min, children: [
        Container(
          width: ring,
          height: ring,
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [LiveStudioAccent.pink, LiveStudioAccent.blue],
            ),
          ),
          child: StudioAvatar(
            name: host?.displayName ?? title,
            url: host?.avatarUrl ?? '',
            size: ring - 4,
            fill: LiveStudioWorld.surface2,
            ring: tokens.ringOnGlass,
          ),
        ),
        SizedBox(width: phone ? 8 : 10),
        Flexible(
          fit: phone ? FlexFit.tight : FlexFit.loose,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LiveStudioType.s(phone ? 13 : 15, FontWeight.w700, tokens.textHigh,
                      height: phone ? 16 : 18)),
              SizedBox(height: phone ? 2 : 3),
              Row(mainAxisSize: MainAxisSize.min, children: [
                ShellLivePill(compact: phone),
                SizedBox(width: phone ? 6 : 8),
                Icon(Icons.visibility_outlined, size: phone ? 12 : 14, color: LiveStudioAccent.blue),
                const SizedBox(width: 3),
                Text(phone ? viewers : '$viewers watching',
                    semanticsLabel: '${counts.viewers} watching',
                    style: LiveStudioType.s(phone ? 11 : 12, FontWeight.w600, tokens.textMedium,
                        height: phone ? 14 : 16)),
                SizedBox(width: phone ? 6 : 8),
                _LiveStat(
                  icon: Icons.favorite_rounded,
                  color: LiveStudioAccent.pink,
                  value: ref.watch(studioReactionsProvider(streamId).select((r) => r.loves)),
                  label: 'loves',
                  tokens: tokens,
                  phone: phone,
                ),
                if ((ref.watch(studioGiftTotalsProvider(streamId)).value?.coins ?? 0) > 0) ...[
                  SizedBox(width: phone ? 6 : 8),
                  _LiveStat(
                    icon: Icons.card_giftcard_rounded,
                    color: LiveStudioAccent.cyan,
                    value: ref.watch(studioGiftTotalsProvider(streamId)).value!.coins,
                    label: 'gift coins',
                    tokens: tokens,
                    phone: phone,
                  ),
                ],
              ]),
            ],
          ),
        ),
        if (follow != null && follow.canFollow) ...[
          SizedBox(width: phone ? 8 : 4),
          StudioPillButton(
            label: following ? 'Following' : 'Follow',
            semanticsLabel: following ? 'Following ${host?.displayName ?? ''}' : 'Follow ${host?.displayName ?? ''}',
            onTap: follow.busy ? null : () => ref.read(studioFollowProvider(hostId).notifier).toggle(),
            fill: following ? tokens.followingFill : LiveStudioAccent.pink,
            border: following ? tokens.followingBorder : LiveStudioAccent.pink,
            textColor: following ? tokens.textHigh : LiveStudioAccent.white,
            height: 36,
            padding: EdgeInsets.symmetric(horizontal: phone ? 14 : 16),
            fontSize: phone ? 12 : 13,
            weight: FontWeight.w700,
          ),
        ],
      ]),
    );
  }
}

/// A header counter (loves, gift coins) that rolls up when it changes.
class _LiveStat extends StatelessWidget {
  const _LiveStat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.tokens,
    required this.phone,
  });
  final IconData icon;
  final Color color;
  final int value;
  final String label;
  final LiveStudioTokens tokens;
  final bool phone;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$value $label',
        excludeSemantics: true,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: phone ? 12 : 14, color: color),
          const SizedBox(width: 3),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (c, a) => ClipRect(
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.8), end: Offset.zero).animate(a),
                child: FadeTransition(opacity: a, child: c),
              ),
            ),
            child: Text(formatStudioCount(value),
                key: ValueKey(value),
                style: LiveStudioType.s(phone ? 11 : 12, FontWeight.w700, tokens.textMedium, height: phone ? 14 : 16)),
          ),
        ]),
      );
}

/// Overlapping avatar stack + participant count (landscape header).
class ParticipantsStack extends StatelessWidget {
  const ParticipantsStack({super.key, required this.tokens, required this.members, required this.count, required this.onTap});
  final LiveStudioTokens tokens;
  final List<StageMember> members;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shown = members.take(3).toList();
    return Semantics(
      button: true,
      label: 'Participants, $count',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: GlassBox(
          tokens: tokens,
          height: 44,
          padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < shown.length; i++)
              Transform.translate(
                offset: Offset(-8.0 * (i + 1), 0),
                child: StudioAvatar(
                  name: shown[i].displayName,
                  url: shown[i].avatarUrl,
                  size: 28,
                  fill: studioHex(shown[i].accent, fallback: LiveStudioAccent.blue),
                  ring: tokens.ringOnGlass,
                ),
              ),
            SizedBox(width: shown.isEmpty ? 0 : 8.0 - 8.0 * shown.length),
            Text('$count', style: LiveStudioType.s(13, FontWeight.w700, tokens.textHigh, height: 16)),
          ]),
        ),
      ),
    );
  }
}

/// TikTok-style comment feed: bottom-aligned, top fade, rise-in, ≤ 50 rows.
class CommentFeed extends ConsumerWidget {
  const CommentFeed({super.key, required this.streamId, required this.tokens});
  final String streamId;
  final LiveStudioTokens tokens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comments = ref.watch(studioCommentFeedProvider(streamId).select((s) => s.items));
    final gifts = ref.watch(studioGiftFeedProvider(streamId)).value ?? const <StudioRecentGift>[];
    // Gifts appear in the comment stream too, in time order.
    final items = <Object>[...comments, ...gifts]
      ..sort((a, b) => _tsOf(a).compareTo(_tsOf(b)));
    final shown = items.length > StudioLimits.commentRenderCap
        ? items.sublist(items.length - StudioLimits.commentRenderCap)
        : items;
    return Semantics(
      liveRegion: true,
      label: 'Live comments',
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [LiveStudioAccent.clear, LiveStudioAccent.white],
          stops: [0, 0.38],
        ).createShader(r),
        child: ListView.builder(
          reverse: true,
          padding: EdgeInsets.zero,
          physics: const ClampingScrollPhysics(),
          itemCount: shown.length,
          itemBuilder: (context, i) {
            final item = shown[shown.length - 1 - i];
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: item is StudioRecentGift
                    ? _RiseIn(key: ValueKey('gift_${item.id}'), child: _GiftCommentRow(gift: item, tokens: tokens))
                    : _RiseIn(
                        key: ValueKey((item as StudioFeedItem).id),
                        child: _CommentRow(item: item, tokens: tokens),
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}

int _tsOf(Object o) => o is StudioRecentGift ? o.atMs : (o as StudioFeedItem).comment.ts;

/// A gift shown inside the comment stream.
class _GiftCommentRow extends StatelessWidget {
  const _GiftCommentRow({required this.gift, required this.tokens});
  final StudioRecentGift gift;
  final LiveStudioTokens tokens;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [giftColor(gift.gift).withValues(alpha: 0.35), tokens.commentBubble]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          StudioAvatar(name: gift.name, url: gift.avatarUrl, size: 26, fill: tokens.commentAvatar, ring: giftColor(gift.gift), ringWidth: 1.5),
          const SizedBox(width: 8),
          Flexible(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '${gift.name}  ', style: LiveStudioType.s(12, FontWeight.w600, tokens.textMedium, height: 18)),
              TextSpan(text: 'sent ${gift.gift.label}', style: LiveStudioType.s(13, FontWeight.w700, tokens.textHigh, height: 18)),
              if (gift.qty > 1) TextSpan(text: ' ×${gift.qty}', style: LiveStudioType.s(13, FontWeight.w900, tokens.textHigh, height: 18)),
            ])),
          ),
          const SizedBox(width: 6),
          Icon(giftIcon(gift.gift), size: 18, color: giftColor(gift.gift)),
        ]),
      );
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.item, required this.tokens});
  final StudioFeedItem item;
  final LiveStudioTokens tokens;

  @override
  Widget build(BuildContext context) {
    final c = item.comment;
    return Opacity(
      opacity: item.isPending ? 0.7 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
        decoration: BoxDecoration(color: tokens.commentBubble, borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          StudioAvatar(
            name: c.name,
            url: c.avatarUrl,
            size: 26,
            fill: tokens.commentAvatar,
            ring: LiveStudioAccent.blue,
            ringWidth: 1.5,
            textColor: tokens.textHigh,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${c.name}  ', style: LiveStudioType.s(12, FontWeight.w600, tokens.textMedium, height: 18)),
                  if (!(c.hasGif && c.text == 'GIF'))
                    if (c.isSystem)
                      TextSpan(
                        text: _systemText(c),
                        style: LiveStudioType.s(13, FontWeight.w400, tokens.systemText, height: 18),
                      )
                    else
                      ..._withMentions(c.text, LiveStudioType.s(13, FontWeight.w400, tokens.textHigh, height: 18)),
                  if (c.hasGif)
                    WidgetSpan(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 120,
                            height: c.gifW > 0 && c.gifH > 0 ? (120 * c.gifH / c.gifW).clamp(40, 160).toDouble() : 90,
                            child: Image.network(c.gifUrl!, fit: BoxFit.cover, gaplessPlayback: true),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  /// Comment text with @mentions in the accent color.
  static List<InlineSpan> _withMentions(String text, TextStyle style) {
    final spans = <InlineSpan>[];
    var i = 0;
    for (final m in kLiveMentionRe.allMatches(text)) {
      if (m.start > i) spans.add(TextSpan(text: text.substring(i, m.start), style: style));
      spans.add(TextSpan(text: m.group(0), style: style.copyWith(color: LiveStudioAccent.blueHover, fontWeight: FontWeight.w700)));
      i = m.end;
    }
    if (i < text.length) spans.add(TextSpan(text: text.substring(i), style: style));
    return spans;
  }

  static String _systemText(LiveStudioComment c) {
    if (c.text.isNotEmpty) return c.text;
    switch (c.system!) {
      case SystemLineKind.joined:
        return 'joined the live';
      case SystemLineKind.love:
        return 'sent love';
      case SystemLineKind.sparkles:
        return 'sent sparkles';
      case SystemLineKind.shared:
        return 'shared this live';
      case SystemLineKind.requested:
        return 'requested to join the stage';
      case SystemLineKind.onStage:
        return 'joined the stage';
    }
  }
}

/// ss-rise: from translateY 18 / scale .96 / opacity 0 to rest, 450 ms.
class _RiseIn extends StatefulWidget {
  const _RiseIn({super.key, required this.child});
  final Widget child;

  @override
  State<_RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<_RiseIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: LiveStudioMotion.rise)..forward();
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: LiveStudioMotion.riseCurve);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - _t.value)),
          child: Transform.scale(scale: 0.96 + 0.04 * _t.value, alignment: Alignment.bottomLeft, child: child),
        ),
      ),
    );
  }
}

/// True while the live comment box is focused (the phone bar then gives the
/// input the full width and hides its other buttons).
final studioComposerOpenProvider = NotifierProvider.autoDispose<_ComposerOpen, bool>(_ComposerOpen.new);

class _ComposerOpen extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) {
    if (state != v) state = v;
  }
}

/// One-tap reactions, sent as a comment.
const List<String> kLiveQuickReactions = ['❤️', '🔥', '😂', '👏', '😍', '😮', '🎉', '💯'];

/// Emoji inserted at the cursor.
const List<String> kLiveEmojis = [
  '😀', '😃', '😄', '😁', '😆', '🥹', '😅', '🤣', '😂', '🙂', '😉', '😊', '😇', '🥰', '😍', '🤩',
  '😘', '😋', '😜', '🤪', '😎', '🤓', '🥳', '😏', '😌', '🤔', '🤫', '🤭', '😴', '😮', '😱', '😭',
  '😤', '😡', '🥺', '😬', '🙏', '👏', '🙌', '👍', '👎', '👋', '🤝', '💪', '✌️', '🤞', '👀', '💃',
  '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '💔', '💯', '🔥', '✨', '⭐', '🎉', '🎶', '🌹', '👑',
];

/// "@name" mention token: no spaces, up to 40 chars.
final RegExp kLiveMentionRe = RegExp(r'@[^\s@]{1,40}');

/// The @query being typed at the cursor (without "@"), or null.
String? liveMentionQueryAt(TextEditingValue v) {
  final sel = v.selection;
  if (!sel.isValid || !sel.isCollapsed) return null;
  final before = v.text.substring(0, sel.baseOffset);
  final m = RegExp(r'(^|\s)@([^\s@]{0,40})$').firstMatch(before);
  return m?.group(2);
}

/// Mention handle for a display name ("Amina K." → "AminaK.").
String liveMentionHandle(String name) => name.replaceAll(RegExp(r'\s+'), '');

class _MentionCandidate {
  const _MentionCandidate(this.uid, this.name, this.avatarUrl);
  final String uid;
  final String name;
  final String avatarUrl;
}

/// The live comment box: text, emoji tray with quick reactions, GIFs
/// (lsGifSearch), @mentions of people on stage and recent commenters, and
/// sparkles / love. The tray floats above the bar (an overlay, so it never
/// shifts the stage and stays tappable).
class CommentBar extends ConsumerStatefulWidget {
  const CommentBar({super.key, required this.streamId, required this.tokens, required this.phone});
  final String streamId;
  final LiveStudioTokens tokens;
  final bool phone;

  @override
  ConsumerState<CommentBar> createState() => _CommentBarState();
}

class _CommentBarState extends ConsumerState<CommentBar> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _link = LayerLink();
  final _tray = OverlayPortalController();
  bool _emoji = false;
  String? _mention;
  double _width = 280;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText);
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _text.removeListener(_onText);
    _focus.removeListener(_onFocus);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setOpen(bool v) {
    // Riverpod forbids provider writes during build / dispose.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(studioComposerOpenProvider.notifier).set(v);
    });
  }

  void _onFocus() {
    _setOpen(_focus.hasFocus || _emoji);
    _syncTray();
  }

  void _onText() {
    final q = liveMentionQueryAt(_text.value);
    if (q != _mention) {
      setState(() => _mention = q);
      _syncTray();
    }
  }

  void _syncTray() {
    final show = _emoji || (_mention != null && _focus.hasFocus);
    if (show && !_tray.isShowing) _tray.show();
    if (!show && _tray.isShowing) _tray.hide();
  }

  void _toggleEmoji() {
    HapticFeedback.selectionClick();
    setState(() => _emoji = !_emoji);
    _setOpen(_emoji || _focus.hasFocus);
    _syncTray();
  }

  void _closeTray() {
    if (_emoji) setState(() => _emoji = false);
    _setOpen(_focus.hasFocus);
    _syncTray();
  }

  void _insert(String s) {
    final v = _text.value;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
    final next = v.text.replaceRange(sel.start, sel.end, s);
    if (next.characters.length > StudioLimits.commentMaxLength) return;
    _text.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: sel.start + s.length));
  }

  void _pickMention(_MentionCandidate c) {
    final v = _text.value;
    final at = v.selection.baseOffset;
    final before = v.text.substring(0, at);
    final start = before.lastIndexOf('@');
    if (start < 0) return;
    final handle = '@${liveMentionHandle(c.name)} ';
    final next = v.text.replaceRange(start, at, handle);
    _text.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: start + handle.length));
    HapticFeedback.selectionClick();
  }

  Future<void> _send([String? text]) async {
    final v = text ?? _text.text;
    if (v.trim().isEmpty) return;
    if (text == null) _text.clear();
    HapticFeedback.lightImpact();
    final ok = await ref.read(studioCommentFeedProvider(widget.streamId).notifier).send(v);
    if (!ok && mounted && text == null && _text.text.isEmpty) _text.text = v;
  }

  Future<void> _sendGif() async {
    _closeTray();
    final gif = await showGifPicker(context);
    if (gif == null || !mounted) return;
    final caption = _text.text;
    _text.clear();
    final ok = await ref.read(studioCommentFeedProvider(widget.streamId).notifier).send(caption, gif: gif);
    if (!ok && mounted && _text.text.isEmpty) _text.text = caption;
  }

  List<_MentionCandidate> _candidates(String q) {
    final me = ref.read(studioMyUidProvider);
    final seen = <String>{};
    final out = <_MentionCandidate>[];
    void add(String uid, String name, String url) {
      if (uid.isEmpty || uid == me || name.trim().isEmpty || !seen.add(uid)) return;
      final handle = liveMentionHandle(name).toLowerCase();
      if (q.isNotEmpty && !handle.contains(q.toLowerCase()) && !name.toLowerCase().contains(q.toLowerCase())) return;
      out.add(_MentionCandidate(uid, name, url));
    }

    for (final m in ref.read(studioMembersProvider(widget.streamId)).value ?? const <StageMember>[]) {
      add(m.uid, m.displayName, m.avatarUrl);
    }
    final items = ref.read(studioCommentFeedProvider(widget.streamId)).items;
    for (final it in items.reversed) {
      if (!it.isSystem) add(it.comment.uid, it.comment.name, it.comment.avatarUrl);
      if (out.length >= 12) break;
    }
    return out;
  }

  Widget _trayView(BuildContext context) {
    final t = widget.tokens;
    final q = _mention;
    final Widget body;
    if (q != null && _focus.hasFocus) {
      final list = _candidates(q);
      body = list.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text('No one to mention yet', style: LiveStudioType.s(12, FontWeight.w500, t.textMedium)),
            )
          : SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final c = list[i];
                  return Semantics(
                    button: true,
                    label: 'Mention ${c.name}',
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () => _pickMention(c),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
                        decoration: BoxDecoration(
                          color: t.ghostFill,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: t.ghostBorder, width: 1),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          StudioAvatar(name: c.name, url: c.avatarUrl, size: 28, fill: t.commentAvatar, textColor: t.textHigh),
                          const SizedBox(width: 6),
                          Text(c.name, style: LiveStudioType.s(12.5, FontWeight.w600, t.textHigh)),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            );
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
          child: Row(children: [
            Text('Quick reactions', style: LiveStudioType.s(11, FontWeight.w700, t.textMedium)),
            const Spacer(),
            Semantics(
              button: true,
              label: 'Close emoji',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: _closeTray,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: t.textMedium),
                ),
              ),
            ),
          ]),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            children: [
              for (final e in kLiveQuickReactions)
                Semantics(
                  button: true,
                  label: 'Send $e',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => _send(e),
                    child: Container(
                      width: 44,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(color: t.ghostFill, borderRadius: BorderRadius.circular(12)),
                      alignment: Alignment.center,
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 12, thickness: 1, color: t.ghostBorder),
        SizedBox(
          height: 150,
          child: GridView.count(
            crossAxisCount: widget.phone ? 8 : 10,
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            children: [
              for (final e in kLiveEmojis)
                Semantics(
                  button: true,
                  label: 'Insert $e',
                  excludeSemantics: true,
                  child: InkResponse(
                    onTap: () => _insert(e),
                    radius: 22,
                    child: Center(child: Text(e, style: const TextStyle(fontSize: 22))),
                  ),
                ),
            ],
          ),
        ),
      ]);
    }
    return Positioned(
      width: _width,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        offset: const Offset(0, -8),
        child: TapRegion(
          groupId: _link,
          child: Material(
            color: LiveStudioAccent.clear,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [t.drawerTop, t.drawerBottom],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: t.drawerBorder, width: 1),
                  ),
                  child: body,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final p = widget.phone;
    final reactions = ref.read(studioReactionsProvider(widget.streamId).notifier);
    final open = ref.watch(studioComposerOpenProvider);
    ref.listen(studioCommentFeedProvider(widget.streamId).select((s) => s.errorSeq), (_, _) {
      final err = ref.read(studioCommentFeedProvider(widget.streamId)).error;
      if (err != null && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(err)));
      }
    });
    final small = p ? 32.0 : 40.0;
    return LayoutBuilder(builder: (context, box) {
      if (box.hasBoundedWidth) _width = math.max(240, box.maxWidth);
      return OverlayPortal(
        controller: _tray,
        overlayChildBuilder: _trayView,
        child: CompositedTransformTarget(
          link: _link,
          child: TapRegion(
            groupId: _link,
            onTapOutside: (_) {
              if (_emoji) _closeTray();
            },
            child: GlassBox(
              tokens: t,
              phone: p,
              height: p ? 42 : 64,
              padding: p ? const EdgeInsets.fromLTRB(4, 0, 3, 0) : const EdgeInsets.fromLTRB(8, 0, 8, 0),
              child: Row(children: [
                StudioRoundButton(
                  tokens: t,
                  icon: _emoji ? Icons.keyboard_alt_outlined : Icons.emoji_emotions_outlined,
                  label: _emoji ? 'Close emoji' : 'Emoji and quick reactions',
                  size: small,
                  iconSize: p ? 19 : 22,
                  fill: LiveStudioAccent.clear,
                  border: LiveStudioAccent.clear,
                  color: _emoji ? LiveStudioAccent.pink : t.textMedium,
                  onTap: _toggleEmoji,
                ),
                Expanded(
                  child: Semantics(
                    textField: true,
                    label: 'Comment',
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      maxLength: StudioLimits.commentMaxLength,
                      textInputAction: TextInputAction.send,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _send(),
                      onTapOutside: (_) {
                        if (!_emoji && _mention == null) _focus.unfocus();
                      },
                      cursorColor: LiveStudioAccent.pink,
                      style: LiveStudioType.s(14, FontWeight.w400, t.textHigh, height: p ? 18 : 20),
                      decoration: InputDecoration(
                        isDense: true,
                        counterText: '',
                        border: InputBorder.none,
                        hintText: p ? 'Add a comment… @ to mention' : 'Say something nice… @ to mention',
                        hintStyle: LiveStudioType.s(14, FontWeight.w400, t.placeholder),
                      ),
                    ),
                  ),
                ),
                StudioRoundButton(
                  tokens: t,
                  icon: Icons.gif_box_rounded,
                  label: 'Send a GIF',
                  size: small,
                  iconSize: p ? 20 : 22,
                  fill: LiveStudioAccent.clear,
                  border: LiveStudioAccent.clear,
                  color: LiveStudioAccent.blue,
                  onTap: _sendGif,
                ),
                if (!p || !open)
                  StudioRoundButton(
                    tokens: t,
                    icon: Icons.auto_awesome,
                    label: 'Send sparkles',
                    size: small,
                    iconSize: p ? 18 : 20,
                    fill: LiveStudioAccent.clear,
                    border: LiveStudioAccent.clear,
                    color: LiveStudioAccent.teal,
                    onTap: () => reactions.tap(ReactionKind.sparkles),
                  ),
                if (!p)
                  StudioRoundButton(
                    tokens: t,
                    icon: Icons.favorite,
                    label: 'Send love',
                    size: 40,
                    fill: LiveStudioAccent.clear,
                    border: LiveStudioAccent.clear,
                    color: LiveStudioAccent.pink,
                    onTap: () => reactions.tap(ReactionKind.love),
                  ),
                StudioRoundButton(
                  tokens: t,
                  icon: Icons.send_rounded,
                  label: 'Send comment',
                  size: p ? 34 : 48,
                  iconSize: p ? 16 : 20,
                  fill: LiveStudioAccent.pink,
                  border: LiveStudioAccent.pink,
                  color: LiveStudioAccent.white,
                  shadow: [BoxShadow(color: LiveStudioAccent.pinkA(0.4), blurRadius: p ? 12 : 16, offset: Offset(0, p ? 4 : 6))],
                  onTap: _send,
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }
}

/// Floating hearts (ss-float): rise 120 px, scale .6→1.1, fade, 3.2 s.
class FloatingHearts extends ConsumerStatefulWidget {
  const FloatingHearts({super.key, required this.streamId, this.rise = 120, this.maxLive = 24});
  final String streamId;
  final double rise;
  final int maxLive;

  @override
  ConsumerState<FloatingHearts> createState() => _FloatingHeartsState();
}

class _FloatingHeartsState extends ConsumerState<FloatingHearts> with TickerProviderStateMixin {
  final _hearts = <_Heart>[];
  final _rng = math.Random();
  StreamSubscription<StudioReactionBurst>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(studioReactionsProvider(widget.streamId).notifier).bursts.listen(_onBurst);
  }

  void _onBurst(StudioReactionBurst b) {
    if (!mounted) return;
    final n = math.min(b.count, 6);
    for (var i = 0; i < n; i++) {
      if (_hearts.length >= widget.maxLive) break;
      final c = AnimationController(vsync: this, duration: LiveStudioMotion.heartFloat);
      final h = _Heart(
        c,
        b.kind == ReactionKind.sparkles ? LiveStudioAccent.teal : LiveStudioAccent.pink,
        b.kind == ReactionKind.sparkles ? Icons.auto_awesome : Icons.favorite,
        (_rng.nextDouble() - 0.5) * 30,
        b.local ? 22 : 14 + _rng.nextDouble() * 6,
      );
      setState(() => _hearts.add(h));
      Future.delayed(Duration(milliseconds: 90 * i), () {
        if (mounted) {
          c.forward().whenComplete(() {
            if (!mounted) return;
            setState(() => _hearts.remove(h));
            c.dispose();
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final h in _hearts) {
      h.c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(clipBehavior: Clip.none, children: [
        for (final h in _hearts)
          AnimatedBuilder(
            animation: h.c,
            builder: (context, _) {
              final v = h.c.value;
              final opacity = v < 0.15 ? v / 0.15 : 1 - (v - 0.15) / 0.85;
              return Positioned(
                left: 0,
                right: 0,
                bottom: widget.rise * v,
                child: Transform.translate(
                  offset: Offset(h.dx * v, 0),
                  child: Opacity(
                    opacity: opacity.clamp(0, 1).toDouble(),
                    child: Transform.scale(scale: 0.6 + 0.5 * v, child: Icon(h.icon, color: h.color, size: h.size)),
                  ),
                ),
              );
            },
          ),
      ]),
    );
  }
}

class _Heart {
  _Heart(this.c, this.color, this.icon, this.dx, this.size);
  final AnimationController c;
  final Color color;
  final IconData icon;
  final double dx;
  final double size;
}

/// Room tabs. Lobby, Goods, Map / Room and Activity & Chat had no content
/// behind them and are no longer shown; the live shows Participants and,
/// for the host / co-hosts, the Watch together entries (YouTube, Browser).
enum StudioRoomTab { lobby, goods, room, people, chat, youtube, browser }

class StudioTabDef {
  const StudioTabDef(this.tab, this.label, this.short, this.icon);
  final StudioRoomTab tab;
  final String label;
  final String short;
  final IconData icon;
}

const List<StudioTabDef> kStudioTabs = [
  StudioTabDef(StudioRoomTab.people, 'Participants', 'Participants', Icons.group_outlined),
  StudioTabDef(StudioRoomTab.youtube, 'Watch YouTube together', 'YouTube', Icons.smart_display_outlined),
  StudioTabDef(StudioRoomTab.browser, 'Browse together', 'Browser', Icons.public),
];

/// Tabs [role] can use (Watch together is for the host / co-hosts).
List<StudioTabDef> studioTabsFor(StudioRole role) => [
      for (final d in kStudioTabs)
        if (role.isManager || d.tab == StudioRoomTab.people) d,
    ];

class RoomTabButton extends StatelessWidget {
  const RoomTabButton({
    super.key,
    required this.def,
    required this.tokens,
    required this.active,
    required this.onTap,
    this.count,
    this.dot = false,
  });

  final StudioTabDef def;
  final LiveStudioTokens tokens;
  final bool active;
  final VoidCallback onTap;
  final int? count;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return StudioPillButton(
      label: def.label,
      semanticsLabel: count != null ? '${def.label}, $count' : def.label,
      onTap: onTap,
      icon: def.icon,
      iconColor: active ? LiveStudioAccent.pink : t.textMedium,
      fill: active ? t.activeFill : LiveStudioAccent.clear,
      border: active ? LiveStudioAccent.pink : LiveStudioAccent.clear,
      textColor: active ? t.textHigh : t.textMedium,
      trailing: count != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(color: LiveStudioAccent.blue, borderRadius: BorderRadius.circular(9999)),
              child: Text('$count', style: LiveStudioType.s(11, FontWeight.w700, LiveStudioAccent.white, height: 15)),
            )
          : dot
              ? Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(color: LiveStudioAccent.pink, shape: BoxShape.circle),
                )
              : null,
    );
  }
}
