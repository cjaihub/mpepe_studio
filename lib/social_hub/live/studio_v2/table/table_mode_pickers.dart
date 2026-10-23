// LIVE STUDIO v2 — table mode pickers (workstream #5, SPEC §3).
//
// - [TableModeCapsule]: landscape header, "On the table" + 4 chips; the
//   active chip expands with its label.
// - [TableModeRail]: phone, vertical 4×30px.
// - [TableModeGrid]: phone drawer, 44px buttons with labels.
//
// Managers (host / co-host) switch the mode. For everyone else the picker is
// read-only (`interactive: false`: shows the current mode, taps do nothing),
// or hidden with `hideWhenReadOnly: true`. [TableModePicker] binds a picker
// to [studioTableControllerProvider].

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import '../../../../backend/live_studio/table/studio_table_controller.dart';
import '../theme/live_studio_tokens.dart';
import 'table_metrics.dart';

/// Shared picker inputs.
abstract class _PickerBase extends StatelessWidget {
  const _PickerBase({
    super.key,
    required this.tokens,
    required this.active,
    this.interactive = true,
    this.hideWhenReadOnly = false,
    this.onPick,
  });

  final LiveStudioTokens tokens;
  final TableMode active;

  /// False for viewers / guests: the current mode shows but cannot change.
  final bool interactive;
  final bool hideWhenReadOnly;
  final ValueChanged<TableMode>? onPick;

  bool get _enabled => interactive && onPick != null;

  Widget chip(TableMode mode, Widget Function(bool on, Color fg, Color icon) body,
      {required double radius, double? width, double height = 0}) {
    final on = mode == active;
    final fg = on ? tokens.textHigh : tokens.modeIdleText;
    final ic = on ? LiveStudioAccent.pink : tokens.modeIdleIcon;
    return Semantics(
      button: true,
      selected: on,
      enabled: _enabled,
      label: 'Put ${TableModeCopy.label(mode)} on the table',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _enabled && !on ? () => onPick!(mode) : null,
        child: AnimatedContainer(
          duration: LiveStudioMotion.hover,
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: on ? tokens.activeFill : tokens.modeIdleFill,
            border: Border.all(color: on ? LiveStudioAccent.pink : tokens.modeIdleBorder),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: body(on, fg, ic),
        ),
      ),
    );
  }

  Widget glass({required Widget child, required BorderRadius radius, required double sigma, required Color border,
          List<BoxShadow>? shadow}) =>
      DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius, boxShadow: shadow),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.glass,
                borderRadius: radius,
                border: Border.all(color: border),
              ),
              child: child,
            ),
          ),
        ),
      );

  Widget buildPicker(BuildContext context);

  @override
  Widget build(BuildContext context) =>
      !interactive && hideWhenReadOnly ? const SizedBox.shrink() : buildPicker(context);
}

/// Landscape header capsule (44px tall).
class TableModeCapsule extends _PickerBase {
  const TableModeCapsule({
    super.key,
    required super.tokens,
    required super.active,
    super.interactive,
    super.hideWhenReadOnly,
    super.onPick,
  });

  @override
  Widget buildPicker(BuildContext context) => glass(
        radius: const BorderRadius.all(Radius.circular(9999)),
        sigma: LiveStudioTokens.glassBlurSigma,
        border: tokens.glassBorderLandscape,
        shadow: [BoxShadow(color: tokens.glassShadow(), blurRadius: 24, offset: const Offset(0, 8))],
        child: SizedBox(
          height: 42, // 44 incl. the 1px border
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.only(left: 10, right: 6),
                child: Text('On the table',
                    style: LiveStudioType.s(11, FontWeight.w600, tokens.textMedium, height: 14)),
              ),
              for (final m in TableMode.values) ...[
                const SizedBox(width: 4),
                chip(
                  m,
                  (on, fg, ic) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(TableModeCopy.icon(m), size: 16, color: ic),
                      if (on) ...[
                        const SizedBox(width: 6),
                        Text(TableModeCopy.label(m),
                            style: LiveStudioType.s(12, FontWeight.w600, fg, height: 16)),
                      ],
                    ]),
                  ),
                  radius: 9999,
                  height: 34,
                ),
              ],
            ]),
          ),
        ),
      );
}

/// Phone vertical rail: 4 × 30px.
class TableModeRail extends _PickerBase {
  const TableModeRail({
    super.key,
    required super.tokens,
    required super.active,
    super.interactive,
    super.hideWhenReadOnly,
    super.onPick,
  });

  @override
  Widget buildPicker(BuildContext context) => glass(
        radius: const BorderRadius.all(Radius.circular(9999)),
        sigma: LiveStudioTokens.railBlurSigma,
        border: tokens.glassBorderPhone,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final (i, m) in TableMode.values.indexed) ...[
              if (i > 0) const SizedBox(height: 4),
              chip(
                m,
                (on, fg, ic) => Center(child: Icon(TableModeCopy.icon(m), size: 14, color: ic)),
                radius: 9999,
                width: 30,
                height: 30,
              ),
            ],
          ]),
        ),
      );
}

/// Phone drawer: "On the table" + 4 × 44px buttons with labels.
class TableModeGrid extends _PickerBase {
  const TableModeGrid({
    super.key,
    required super.tokens,
    required super.active,
    super.interactive,
    super.hideWhenReadOnly,
    super.onPick,
  });

  @override
  Widget buildPicker(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('On the table', style: LiveStudioType.s(12, FontWeight.w600, tokens.textMedium, height: 16)),
          const SizedBox(height: 6),
          Row(children: [
            for (final (i, m) in TableMode.values.indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: chip(
                  m,
                  (on, fg, ic) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(TableModeCopy.icon(m), size: 16, color: ic),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(TableModeCopy.label(m),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LiveStudioType.s(12, FontWeight.w600, fg, height: 16)),
                    ),
                  ]),
                  radius: 12,
                  height: 44,
                ),
              ),
            ],
          ]),
        ],
      );
}

enum TableModePickerKind { capsule, rail, grid }

/// A picker bound to the table controller: managers switch, others read-only.
class TableModePicker extends ConsumerWidget {
  const TableModePicker({
    super.key,
    required this.streamId,
    required this.kind,
    required this.tokens,
    this.hideWhenReadOnly = false,
    this.onPicked,
  });

  final String streamId;
  final TableModePickerKind kind;
  final LiveStudioTokens tokens;
  final bool hideWhenReadOnly;

  /// After a pick (e.g. close the drawer).
  final VoidCallback? onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(studioTableControllerProvider(streamId));
    void pick(TableMode m) {
      unawaited(ref.read(studioTableControllerProvider(streamId).notifier).setMode(m));
      onPicked?.call();
    }

    final active = view.shownMode;
    final interactive = view.canManage;
    return switch (kind) {
      TableModePickerKind.capsule => TableModeCapsule(
          tokens: tokens, active: active, interactive: interactive, hideWhenReadOnly: hideWhenReadOnly, onPick: pick),
      TableModePickerKind.rail => TableModeRail(
          tokens: tokens, active: active, interactive: interactive, hideWhenReadOnly: hideWhenReadOnly, onPick: pick),
      TableModePickerKind.grid => TableModeGrid(
          tokens: tokens, active: active, interactive: interactive, hideWhenReadOnly: hideWhenReadOnly, onPick: pick),
    };
  }
}
