// LIVE STUDIO v2 — "Share to the table" (workstream #5).
//
// Starts my table screen share, then sets the table to Screen
// (StudioTableController.shareScreenToTable). Managers only; hidden for
// everyone else unless [showWhenNotAllowed].

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../backend/live_studio/table/studio_table_controller.dart';
import '../theme/live_studio_tokens.dart';

enum ShareToTableVariant {
  /// Landscape controls group: 44px pill, icon + "Share".
  landscape,

  /// Phone bottom bar: 40px circle.
  phone,

  /// Phone drawer tools row: 44px ghost icon.
  drawer,
}

class ShareToTableButton extends ConsumerWidget {
  const ShareToTableButton({
    super.key,
    required this.streamId,
    required this.tokens,
    this.variant = ShareToTableVariant.landscape,
    this.showWhenNotAllowed = false,
    this.onShared,
  });

  final String streamId;
  final LiveStudioTokens tokens;
  final ShareToTableVariant variant;
  final bool showWhenNotAllowed;

  /// After a successful share (e.g. close the drawer).
  final VoidCallback? onShared;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(studioTableControllerProvider(streamId));
    final allowed = view.canManage;
    if (!allowed && !showWhenNotAllowed) return const SizedBox.shrink();
    final enabled = allowed && !view.busy;

    void tap() => unawaited(
          ref.read(studioTableControllerProvider(streamId).notifier).shareScreenToTable().then((ok) {
            if (ok) onShared?.call();
          }),
        );

    final Widget body;
    switch (variant) {
      case ShareToTableVariant.landscape:
        body = Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: LiveStudioAccent.blueA(0.16),
            border: Border.all(color: LiveStudioAccent.blueA(0.5)),
            borderRadius: const BorderRadius.all(Radius.circular(9999)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cast, size: 18, color: tokens.shareToTableText),
            const SizedBox(width: 7),
            Text('Share', style: LiveStudioType.s(13, FontWeight.w600, tokens.shareToTableText, height: 16)),
          ]),
        );
      case ShareToTableVariant.phone:
        body = Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: LiveStudioAccent.blueA(0.18),
            border: Border.all(color: LiveStudioAccent.blueA(0.5)),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.cast, size: 18, color: tokens.shareToTableText),
        );
      case ShareToTableVariant.drawer:
        body = SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.cast, size: 20, color: tokens.textMedium),
        );
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Share to the table',
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: enabled ? tap : null, child: body),
      ),
    );
  }
}
