import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../backend/live/models/live_models.dart';
import '../../../../backend/live/models/live_studio_models.dart';
import '../../../../backend/live/services/live_service.dart';
import '../../../../backend/live/services/live_studio_service.dart';
import '../../../../shared/theme/obsidian_telemetry_tokens.dart';
import '../live_studio_roster.dart';
import 'studio_chrome.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SHARED PANEL PIECES
// ─────────────────────────────────────────────────────────────────────────────

class StudioPanelFrame extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback? onClose;
  final Widget? trailing;

  const StudioPanelFrame({
    super.key,
    required this.title,
    required this.child,
    this.onClose,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: OTType.headlineSm()),
              ),
            ),
            ?trailing,
            if (onClose != null)
              StudioIconButton(
                icon: Icons.close_rounded,
                label: 'Close $title',
                onPressed: onClose,
              ),
          ],
        ),
        const SizedBox(height: OTSpace.sm),
        Expanded(child: child),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: OTSpace.md, bottom: OTSpace.sm),
        child: Semantics(
          header: true,
          child: Text(text.toUpperCase(),
              style: OTType.labelSm(color: OTColors.textMedium)),
        ),
      );
}

class StudioEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const StudioEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(OTSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: OTColors.surface2,
                borderRadius: BorderRadius.circular(OTRadius.md),
                border: Border.all(color: OTColors.hairline08),
              ),
              child: Icon(icon, color: OTColors.textMedium, size: 22),
            ),
            const SizedBox(height: OTSpace.md),
            Text(title, style: OTType.headlineSm(), textAlign: TextAlign.center),
            const SizedBox(height: OTSpace.xs),
            Text(message, style: OTType.bodySm(), textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: OTSpace.md),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class StudioLoading extends StatelessWidget {
  final String label;
  const StudioLoading({super.key, this.label = 'Loading…'});

  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          label: label,
          child: const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: OTColors.neonPink),
          ),
        ),
      );
}

/// Small 44px-tall text button used inside panels.
class StudioTextButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final IconData? icon;

  const StudioTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bg = primary ? OTColors.neonPink : OTColors.surface2;
    return Semantics(
      button: true,
      label: label,
      enabled: onPressed != null,
      child: Material(
        color: onPressed == null ? OTColors.surface2 : bg,
        borderRadius: BorderRadius.circular(OTRadius.base),
        child: InkWell(
          borderRadius: BorderRadius.circular(OTRadius.base),
          hoverColor: primary ? OTColors.neonPinkHover : OTColors.pinkHover08,
          onTap: onPressed == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onPressed!();
                },
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: primary
                ? null
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(OTRadius.base),
                    border: Border.all(color: OTColors.hairline12),
                  ),
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon,
                        size: 16,
                        color: primary ? OTColors.textHigh : OTColors.neonPink),
                    const SizedBox(width: 6),
                  ],
                  Text(label,
                      style: OTType.labelMd(
                              color: onPressed == null
                                  ? OTColors.textMuted
                                  : OTColors.textHigh)
                          .copyWith(fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> confirmStudioAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: OTColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OTRadius.lg),
        side: const BorderSide(color: OTColors.hairline08),
      ),
      title: Text(title, style: OTType.headlineSm()),
      content: Text(message, style: OTType.bodyMd(color: OTColors.textMedium)),
      actions: [
        StudioTextButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop(false)),
        StudioTextButton(
            label: confirmLabel, primary: true, onPressed: () => Navigator.of(ctx).pop(true)),
      ],
    ),
  );
  return ok ?? false;
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
    backgroundColor: OTColors.surface3,
    content: Text(msg, style: OTType.bodyMd()),
  ));
}

// ─────────────────────────────────────────────────────────────────────────────
// LOBBY
// ─────────────────────────────────────────────────────────────────────────────

class StudioLobbyPanel extends StatelessWidget {
  final LiveStream stream;
  final StudioRoster roster;
  final int audienceCount;
  final VoidCallback? onClose;

  const StudioLobbyPanel({
    super.key,
    required this.stream,
    required this.roster,
    required this.audienceCount,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, int value) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(OTSpace.md),
            decoration: BoxDecoration(
              color: OTColors.surface2,
              borderRadius: BorderRadius.circular(OTRadius.md),
              border: Border.all(color: OTColors.hairline08),
            ),
            child: Semantics(
              label: '$label: $value',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatLiveCount(value), style: OTType.metricMd()),
                    const SizedBox(height: 2),
                    Text(label.toUpperCase(),
                        style: OTType.labelSm(color: OTColors.textMedium)),
                  ],
                ),
              ),
            ),
          ),
        );

    return StudioPanelFrame(
      title: 'Lobby',
      onClose: onClose,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Text(stream.title, style: OTType.headlineMd()),
          const SizedBox(height: OTSpace.sm),
          Row(
            children: [
              StudioAvatar(name: stream.hostDisplayName, url: stream.hostAvatarUrl),
              const SizedBox(width: OTSpace.sm),
              Expanded(
                child: Text('Hosted by ${stream.hostDisplayName}',
                    style: OTType.bodyMd(color: OTColors.textMedium)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: OTColors.surface2,
                  borderRadius: BorderRadius.circular(OTRadius.full),
                  border: Border.all(color: OTColors.hairline08),
                ),
                child: Text(stream.category,
                    style: OTType.labelSm(color: OTColors.textMedium)),
              ),
            ],
          ),
          const SizedBox(height: OTSpace.md),
          Row(children: [
            stat('Viewers', stream.viewerCount),
            const SizedBox(width: OTSpace.sm),
            stat('Likes', stream.totalLikes),
            const SizedBox(width: OTSpace.sm),
            stat('Comments', stream.totalComments),
          ]),
          const _SectionLabel('On stage now'),
          for (final m in roster.publishers)
            Padding(
              padding: const EdgeInsets.only(bottom: OTSpace.sm),
              child: Row(children: [
                StudioAvatar(name: m.displayName, url: m.avatarUrl, size: 28),
                const SizedBox(width: OTSpace.sm),
                Expanded(
                    child: Text(m.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OTType.chat(weight: FontWeight.w600))),
                Text(roster.center?.uid == m.uid ? 'Center stage' : m.roleLabel,
                    style: OTType.labelSm(
                        color: roster.center?.uid == m.uid
                            ? OTColors.neonPink
                            : OTColors.textMedium)),
              ]),
            ),
          const _SectionLabel('In the room'),
          Text('$audienceCount people in the participants list',
              style: OTType.bodySm()),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRESENTER'S GOODS
// ─────────────────────────────────────────────────────────────────────────────

class StudioGoodsPanel extends ConsumerWidget {
  final String streamId;
  final bool isHost;
  final VoidCallback? onClose;

  const StudioGoodsPanel({
    super.key,
    required this.streamId,
    required this.isHost,
    this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(liveProductsProvider(streamId));
    final featuredId =
        ref.watch(liveStudioDocProvider(streamId)).value?.featuredProductId;
    final service = ref.read(liveStudioServiceProvider);

    return StudioPanelFrame(
      title: "Presenter's Goods",
      onClose: onClose,
      trailing: isHost
          ? StudioIconButton(
              icon: Icons.add_rounded,
              label: 'Add product',
              color: OTColors.neonPink,
              onPressed: () => _showAddProduct(context, service),
            )
          : null,
      child: products.when(
        loading: () => const StudioLoading(label: 'Loading goods'),
        error: (e, _) => StudioEmptyState(
          icon: Icons.error_outline_rounded,
          title: "Couldn't load goods",
          message: '$e',
        ),
        data: (items) {
          if (items.isEmpty) {
            return StudioEmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No goods yet',
              message: isHost
                  ? 'Add the products you are presenting. Featured items appear on the stand.'
                  : 'Products shown by the host will appear here.',
              action: isHost
                  ? StudioTextButton(
                      label: 'Add product',
                      icon: Icons.add_rounded,
                      onPressed: () => _showAddProduct(context, service),
                    )
                  : null,
            );
          }
          return ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: OTSpace.sm),
            itemBuilder: (context, i) {
              final p = items[i];
              final featured = p.id == featuredId;
              return _ProductRow(
                product: p,
                featured: featured,
                isHost: isHost,
                onFeature: () async {
                  try {
                    await service.setFeaturedProduct(streamId, featured ? null : p.id);
                  } catch (e) {
                    if (context.mounted) _snack(context, 'Could not update: $e');
                  }
                },
                onOpen: p.productUrl.isEmpty
                    ? null
                    : () async {
                        final uri = Uri.tryParse(p.productUrl);
                        if (uri == null ||
                            !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                          if (context.mounted) _snack(context, 'Could not open link');
                        }
                      },
                onRemove: () async {
                  final ok = await confirmStudioAction(context,
                      title: 'Remove product?',
                      message: '"${p.name}" will be removed from this live.',
                      confirmLabel: 'Remove');
                  if (!ok) return;
                  try {
                    await service.removeProduct(streamId, p.id, wasFeatured: featured);
                  } catch (e) {
                    if (context.mounted) _snack(context, 'Could not remove: $e');
                  }
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showAddProduct(BuildContext context, LiveStudioService service) async {
    final name = TextEditingController();
    final price = TextEditingController();
    final currency = TextEditingController(text: 'USD');
    final image = TextEditingController();
    final link = TextEditingController();

    InputDecoration deco(String label) => InputDecoration(
          isDense: true,
          labelText: label,
          labelStyle: OTType.bodySm(),
          filled: true,
          fillColor: OTColors.inputWell,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(OTRadius.base),
            borderSide: const BorderSide(color: OTColors.hairline10),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(OTRadius.base),
            borderSide: const BorderSide(color: OTColors.neonPink),
          ),
        );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OTColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OTRadius.lg),
          side: const BorderSide(color: OTColors.pinkBorder30),
        ),
        title: Text('Add product', style: OTType.headlineSm()),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, style: OTType.bodyMd(), decoration: deco('Name')),
              const SizedBox(height: OTSpace.sm),
              Row(children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: price,
                    style: OTType.bodyMd(),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: deco('Price'),
                  ),
                ),
                const SizedBox(width: OTSpace.sm),
                Expanded(
                  child: TextField(
                      controller: currency, style: OTType.bodyMd(), decoration: deco('Currency')),
                ),
              ]),
              const SizedBox(height: OTSpace.sm),
              TextField(
                  controller: image,
                  style: OTType.bodyMd(),
                  keyboardType: TextInputType.url,
                  decoration: deco('Image URL (optional)')),
              const SizedBox(height: OTSpace.sm),
              TextField(
                  controller: link,
                  style: OTType.bodyMd(),
                  keyboardType: TextInputType.url,
                  decoration: deco('Product link (optional)')),
            ]),
          ),
        ),
        actions: [
          StudioTextButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop(false)),
          StudioTextButton(
              label: 'Add',
              primary: true,
              onPressed: () {
                if (name.text.trim().isEmpty) return;
                Navigator.of(ctx).pop(true);
              }),
        ],
      ),
    );

    if (saved == true) {
      try {
        await service.addProduct(
          streamId,
          name: name.text,
          price: num.tryParse(price.text.trim().replaceAll(',', '.')),
          currency: currency.text,
          imageUrl: image.text,
          productUrl: link.text,
        );
      } catch (e) {
        if (context.mounted) _snack(context, 'Could not add product: $e');
      }
    }
    name.dispose();
    price.dispose();
    currency.dispose();
    image.dispose();
    link.dispose();
  }
}

class _ProductRow extends StatelessWidget {
  final LiveProduct product;
  final bool featured;
  final bool isHost;
  final VoidCallback onFeature;
  final VoidCallback? onOpen;
  final VoidCallback onRemove;

  const _ProductRow({
    required this.product,
    required this.featured,
    required this.isHost,
    required this.onFeature,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    const placeholder =
        Icon(Icons.inventory_2_outlined, color: OTColors.telemetryCyan, size: 22);
    return Container(
      padding: const EdgeInsets.all(OTSpace.sm),
      decoration: BoxDecoration(
        color: OTColors.surface2,
        borderRadius: BorderRadius.circular(OTRadius.md),
        border: Border.all(
            color: featured ? OTColors.neonPink : OTColors.hairline08, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: OTColors.surface3,
              borderRadius: BorderRadius.circular(OTRadius.base),
            ),
            child: product.imageUrl.isEmpty
                ? placeholder
                : Image.network(product.imageUrl,
                    fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
          ),
          const SizedBox(width: OTSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (featured)
                  Text('ON THE STAND', style: OTType.labelSm(color: OTColors.neonPink)),
                Text(product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: OTType.labelMd().copyWith(fontSize: 14)),
                Text(formatPrice(product.price, product.currency),
                    style: OTType.labelMd(color: OTColors.textMedium)),
              ],
            ),
          ),
          if (onOpen != null)
            StudioIconButton(
                icon: Icons.open_in_new_rounded,
                label: 'Open ${product.name}',
                onPressed: onOpen),
          if (isHost) ...[
            StudioIconButton(
              icon: featured ? Icons.star_rounded : Icons.star_outline_rounded,
              label: featured ? 'Remove from stand' : 'Feature on stand',
              active: featured,
              onPressed: onFeature,
            ),
            StudioIconButton(
                icon: Icons.delete_outline_rounded,
                label: 'Remove ${product.name}',
                onPressed: onRemove),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PARTICIPANTS
// ─────────────────────────────────────────────────────────────────────────────

class StudioParticipantsPanel extends ConsumerWidget {
  final LiveStream stream;
  final StudioRoster roster;
  final List<LiveParticipant> participants;
  final List<LiveGuestRequest> requests;
  final bool isHost;
  final String selfUid;
  final ValueChanged<StageMember> onPutOnStage;
  final VoidCallback? onClose;

  const StudioParticipantsPanel({
    super.key,
    required this.stream,
    required this.roster,
    required this.participants,
    required this.requests,
    required this.isHost,
    required this.selfUid,
    required this.onPutOnStage,
    this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.read(liveServiceProvider);
    final stageIds = roster.publisherIds;
    final pending = requests
        .where((r) => r.status == LiveGuestRequestStatus.pending)
        .toList();
    final audience = participants
        .where((p) => !stageIds.contains(p.userId) && p.userId != stream.hostId)
        .toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    final overflowIds = roster.overflow.map((m) => m.uid).toSet();

    Future<void> run(Future<void> Function() action, String failMsg) async {
      try {
        await action();
      } catch (e) {
        if (context.mounted) _snack(context, '$failMsg: $e');
      }
    }

    Widget memberRow(StageMember m) {
      final isCenter = roster.center?.uid == m.uid;
      final subtitle = isCenter
          ? 'Center stage'
          : overflowIds.contains(m.uid)
              ? '${m.roleLabel} · no free wall slot'
              : m.roleLabel;
      return _PersonRow(
        name: m.uid == selfUid ? '${m.displayName} (You)' : m.displayName,
        avatarUrl: m.avatarUrl,
        subtitle: subtitle,
        subtitleAccent: isCenter,
        muted: m.isMuted,
        actions: [
          if (isHost && !isCenter)
            StudioIconButton(
              icon: Icons.center_focus_strong_outlined,
              label: 'Put ${m.displayName} on center stage',
              onPressed: () => onPutOnStage(m),
            ),
          // Hosts can mute guests; only the guest can unmute themselves.
          if (isHost && !m.isHost && !m.isMuted)
            StudioIconButton(
              icon: Icons.mic_off_outlined,
              label: 'Mute ${m.displayName}',
              onPressed: () => run(
                  () => live.setParticipantMute(stream.id, m.uid, true),
                  'Could not mute'),
            ),
          if (isHost && !m.isHost)
            StudioIconButton(
              icon: Icons.person_remove_outlined,
              label: 'Remove ${m.displayName} from stage',
              onPressed: () async {
                final ok = await confirmStudioAction(context,
                    title: 'Remove from stage?',
                    message: '${m.displayName} will stop broadcasting and return to the audience.',
                    confirmLabel: 'Remove');
                if (ok) {
                  await run(() => live.dropFromStage(stream.id, m.uid),
                      'Could not remove');
                }
              },
            ),
        ],
      );
    }

    return StudioPanelFrame(
      title: 'Participants',
      onClose: onClose,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _SectionLabel('On stage · ${roster.publishers.length}'),
          for (final m in roster.publishers) memberRow(m),
          if (pending.isNotEmpty) ...[
            _SectionLabel('Requests · ${pending.length}'),
            for (final r in pending)
              _PersonRow(
                name: r.displayName,
                avatarUrl: r.avatarUrl,
                subtitle: 'Wants to join as ${r.requestedRole.name}',
                actions: [
                  if (isHost) ...[
                    StudioIconButton(
                      icon: Icons.check_rounded,
                      label: 'Approve ${r.displayName}',
                      color: OTColors.telemetryCyan,
                      onPressed: () => run(
                          () => live.approveSpeaker(stream.id, r.userId), 'Could not approve'),
                    ),
                    StudioIconButton(
                      icon: Icons.close_rounded,
                      label: 'Decline ${r.displayName}',
                      color: OTColors.liveCrimson,
                      onPressed: () => run(
                          () => live.declineRequest(stream.id, r.userId), 'Could not decline'),
                    ),
                  ],
                ],
              ),
          ],
          _SectionLabel('Audience · ${audience.length}'),
          if (audience.isEmpty)
            Text('No one else in the participants list yet.', style: OTType.bodySm())
          else
            for (final p in audience)
              _PersonRow(
                name: p.userId == selfUid ? '${p.displayName} (You)' : p.displayName,
                avatarUrl: p.avatarUrl,
                subtitle: p.role == LiveGuestRole.moderator ? 'Moderator' : 'Viewer',
                actions: const [],
              ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final String subtitle;
  final bool subtitleAccent;
  final bool? muted;
  final List<Widget> actions;

  const _PersonRow({
    required this.name,
    required this.avatarUrl,
    required this.subtitle,
    required this.actions,
    this.subtitleAccent = false,
    this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: OTSpace.xs),
      child: Row(
        children: [
          StudioAvatar(name: name, url: avatarUrl, size: 32),
          const SizedBox(width: OTSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OTType.chat(weight: FontWeight.w600)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OTType.bodySm(
                        color: subtitleAccent ? OTColors.neonPink : OTColors.textMedium)),
              ],
            ),
          ),
          if (muted != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                muted! ? Icons.mic_off_rounded : Icons.mic_rounded,
                size: 16,
                color: muted! ? OTColors.liveCrimson : OTColors.telemetryCyan,
                semanticLabel: muted! ? 'Muted' : 'Mic on',
              ),
            ),
          ...actions,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTIVITY & CHAT
// ─────────────────────────────────────────────────────────────────────────────

class StudioActivityPanel extends StatelessWidget {
  final List<StudioFeedItem> items; // oldest → newest
  final bool isLoading;
  final VoidCallback? onClose;

  const StudioActivityPanel({
    super.key,
    required this.items,
    required this.isLoading,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (isLoading && items.isEmpty) {
      body = const StudioLoading(label: 'Loading chat');
    } else if (items.isEmpty) {
      body = const StudioEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'No messages yet',
        message: 'Be the first to say hello.',
      );
    } else {
      body = ListView.builder(
        reverse: true, // newest pinned at the bottom
        padding: EdgeInsets.zero,
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[items.length - 1 - i];
          return Padding(
            key: ValueKey(item.id),
            padding: const EdgeInsets.only(bottom: OTSpace.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StudioAvatar(name: item.name, url: item.avatarUrl, size: 28),
                const SizedBox(width: OTSpace.sm),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: '${item.name}  ',
                          style: OTType.chat(weight: FontWeight.w600)),
                      TextSpan(
                          text: item.text,
                          style: OTType.chat(
                              color: item.isSystem
                                  ? OTColors.textMedium
                                  : OTColors.textHigh)),
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
    return StudioPanelFrame(title: 'Activity & Chat', onClose: onClose, child: body);
  }
}
