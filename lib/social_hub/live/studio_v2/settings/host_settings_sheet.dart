// LIVE STUDIO v2 — HostSettingsSheet (workstream #6, host only).
//
// Bottom sheet for stage customization. Colors come only from
// live_studio_tokens.dart; the sheet follows the theme being previewed, so the
// host sees the light/dark chrome immediately. Every control talks to
// [StudioSettingsController]; nothing here writes Firestore.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import '../../../../backend/live_studio/settings/settings_rules.dart';
import '../../../../backend/live_studio/settings/studio_catalog.dart';
import '../../../../backend/live_studio/settings/studio_settings_controller.dart';
import '../theme/live_studio_tokens.dart';

/// Opens the host settings sheet with a light haptic. Host only: callers must
/// not offer this to co-hosts, guests or viewers (the server rejects them).
Future<void> showHostSettingsSheet(BuildContext context, {required String streamId}) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: LiveStudioTokens.dark.base.withValues(alpha: 0),
    barrierColor: LiveStudioTokens.dimTint(0.45),
    builder: (_) => HostSettingsSheet(streamId: streamId),
  );
}

/// Semantics labels (shared with tests).
class HostSettingsLabels {
  HostSettingsLabels._();
  static const String sheet = 'Studio settings';
  static String studio(String label) => 'Studio background: $label';
  static const String themeDark = 'Theme: dark';
  static const String themeLight = 'Theme: light';
  static const String frameWidth = 'Frame width';
  static String frameColor(int index) => 'Frame color ${index + 1} of 4';
  static String guestSize(GuestSize s) => 'Guest size: ${_sizeName(s)}';
  static const String showNames = 'Show names';
  static const String studioDim = 'Studio dim';
  static String speakerMode(SpeakerMode m) => 'Speaker mode: ${_modeTitle(m)}';
}

String _sizeName(GuestSize s) => switch (s) {
      GuestSize.s => 'small',
      GuestSize.m => 'medium',
      GuestSize.l => 'large',
    };

String _modeTitle(SpeakerMode m) => switch (m) {
      SpeakerMode.hostPinned => 'Host pinned',
      SpeakerMode.autoActiveSpeaker => 'Auto active speaker',
      SpeakerMode.manual => 'Manual',
    };

String _modeHelp(SpeakerMode m) => switch (m) {
      SpeakerMode.hostPinned => 'You stay in the center; only your swaps move people.',
      SpeakerMode.autoActiveSpeaker => 'Whoever talks for 1.5 s takes the center (holds 4 s).',
      SpeakerMode.manual => 'Nobody moves unless you or a co-host swaps them.',
    };

const double _kTarget = 44;

class HostSettingsSheet extends ConsumerWidget {
  const HostSettingsSheet({super.key, required this.streamId});

  final String streamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(studioSettingsControllerProvider(streamId));
    final ctl = ref.read(studioSettingsControllerProvider(streamId).notifier);
    final s = view.effective;
    final t = LiveStudioTokens.forTheme(s.theme);
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: HostSettingsLabels.sheet,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [t.drawerTop, t.drawerBottom],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: t.drawerBorder)),
            boxShadow: [BoxShadow(color: t.glassShadow(), blurRadius: 24, offset: const Offset(0, -6))],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: t.textDim, borderRadius: BorderRadius.circular(9999)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(HostSettingsLabels.sheet,
                            style: LiveStudioType.s(16, FontWeight.w700, t.textHigh)),
                      ),
                      if (view.saving)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: LiveStudioAccent.pink),
                          ),
                        ),
                      _Tappable(
                        tokens: t,
                        label: 'Close settings',
                        onTap: () => Navigator.of(context).maybePop(),
                        radius: 9999,
                        child: SizedBox(
                          width: _kTarget,
                          height: _kTarget,
                          child: Icon(Icons.close_rounded, size: 20, color: t.textMedium),
                        ),
                      ),
                    ],
                  ),
                ),
                if (view.error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Semantics(
                      liveRegion: true,
                      child: Text("Couldn't save that change. It was undone.",
                          style: LiveStudioType.s(12, FontWeight.w600, t.systemText)),
                    ),
                  ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Section(tokens: t, title: 'Studio background', child: _StudioPicker(
                          tokens: t, selected: s.studioId, onPick: ctl.setStudio)),
                        _Section(
                          tokens: t,
                          title: 'Theme',
                          child: _Segmented<StudioTheme>(
                            tokens: t,
                            values: StudioTheme.values,
                            selected: s.theme,
                            text: (v) => v == StudioTheme.dark ? 'Dark' : 'Light',
                            icon: (v) => v == StudioTheme.dark
                                ? Icons.dark_mode_rounded
                                : Icons.light_mode_rounded,
                            label: (v) => v == StudioTheme.dark
                                ? HostSettingsLabels.themeDark
                                : HostSettingsLabels.themeLight,
                            onPick: ctl.setTheme,
                          ),
                        ),
                        _Section(
                          tokens: t,
                          title: 'Frame width',
                          trailing: '${s.frameWidth} px',
                          child: _StudioSlider(
                            tokens: t,
                            label: HostSettingsLabels.frameWidth,
                            value: s.frameWidth.toDouble(),
                            min: StudioLimits.frameWidthMin.toDouble(),
                            max: StudioLimits.frameWidthMax.toDouble(),
                            divisions: StudioLimits.frameWidthMax - StudioLimits.frameWidthMin,
                            valueText: '${s.frameWidth} pixels',
                            onChanged: ctl.setFrameWidth,
                            onChangeEnd: (_) => ctl.flush(),
                          ),
                        ),
                        _Section(
                          tokens: t,
                          title: 'Frame color',
                          child: _Swatches(
                            tokens: t,
                            options: kFrameColorOptions[s.theme]!,
                            selected: s.frameColor,
                            onPick: ctl.setFrameColor,
                          ),
                        ),
                        _Section(
                          tokens: t,
                          title: 'Guest size',
                          note: 'Applies to the landscape wall. Phone tiles keep their size.',
                          child: _Segmented<GuestSize>(
                            tokens: t,
                            values: GuestSize.values,
                            selected: s.guestSize,
                            text: (v) => v.wire.toUpperCase(),
                            label: HostSettingsLabels.guestSize,
                            onPick: ctl.setGuestSize,
                          ),
                        ),
                        _SwitchRow(
                          tokens: t,
                          title: 'Show names',
                          subtitle: 'Nameplates under every guest.',
                          value: s.showNames,
                          onChanged: ctl.setShowNames,
                        ),
                        _Section(
                          tokens: t,
                          title: 'Studio dim',
                          trailing: '${(s.studioDim * 100).round()}%',
                          child: _StudioSlider(
                            tokens: t,
                            label: HostSettingsLabels.studioDim,
                            value: s.studioDim,
                            min: StudioLimits.studioDimMin,
                            max: StudioLimits.studioDimMax,
                            divisions: ((StudioLimits.studioDimMax - StudioLimits.studioDimMin) /
                                    kStudioDimStep)
                                .round(),
                            valueText: '${(s.studioDim * 100).round()} percent',
                            onChanged: ctl.setStudioDim,
                            onChangeEnd: (_) => ctl.flush(),
                          ),
                        ),
                        _Section(
                          tokens: t,
                          title: 'Speaker mode',
                          child: Column(
                            children: [
                              for (final m in SpeakerMode.values)
                                _ModeRow(
                                  tokens: t,
                                  mode: m,
                                  selected: s.speakerMode == m,
                                  onTap: () => ctl.setSpeakerMode(m),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Building blocks ─────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.tokens, required this.title, required this.child, this.trailing, this.note});

  final LiveStudioTokens tokens;
  final String title;
  final String? trailing;
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(title.toUpperCase(),
                        style: LiveStudioType.s(10.5, FontWeight.w800, tokens.textMedium, letter: 0.08)),
                  ),
                ),
                if (trailing != null)
                  ExcludeSemantics(
                    child: Text(trailing!,
                        style: LiveStudioType.s(12.5, FontWeight.w700, tokens.textHigh)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            child,
            if (note != null) ...[
              const SizedBox(height: 6),
              Text(note!, style: LiveStudioType.s(11, FontWeight.w500, tokens.textMedium)),
            ],
          ],
        ),
      );
}

/// Tap target with a keyboard focus ring (FocusableActionDetector) and a
/// Semantics button node.
class _Tappable extends StatefulWidget {
  const _Tappable({
    required this.tokens,
    required this.label,
    required this.onTap,
    required this.child,
    this.selected,
    this.radius = 12,
  });

  final LiveStudioTokens tokens;
  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool? selected;
  final double radius;

  @override
  State<_Tappable> createState() => _TappableState();
}

class _TappableState extends State<_Tappable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: widget.selected,
        label: widget.label,
        excludeSemantics: true,
        onTap: widget.onTap,
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
              widget.onTap();
              return null;
            }),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: LiveStudioMotion.press,
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.radius),
                border: _focused ? Border.all(color: widget.tokens.focusRing, width: 2) : null,
              ),
              child: widget.child,
            ),
          ),
        ),
      );
}

BoxDecoration _pill(LiveStudioTokens t, bool selected, {double radius = 10}) => BoxDecoration(
      color: selected ? t.activeFill : t.ghostFill,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: selected ? LiveStudioAccent.pink : t.ghostBorder),
    );

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.tokens,
    required this.values,
    required this.selected,
    required this.text,
    required this.label,
    required this.onPick,
    this.icon,
  });

  final LiveStudioTokens tokens;
  final List<T> values;
  final T selected;
  final String Function(T) text;
  final String Function(T) label;
  final IconData Function(T)? icon;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: _Tappable(
                tokens: tokens,
                label: label(values[i]),
                selected: values[i] == selected,
                radius: 10,
                onTap: () => onPick(values[i]),
                child: Container(
                  height: _kTarget,
                  alignment: Alignment.center,
                  decoration: _pill(tokens, values[i] == selected),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon!(values[i]),
                            size: 16,
                            color: values[i] == selected ? LiveStudioAccent.pink : tokens.textMedium),
                        const SizedBox(width: 6),
                      ],
                      Text(text(values[i]),
                          style: LiveStudioType.s(13, FontWeight.w700,
                              values[i] == selected ? tokens.textHigh : tokens.textMedium)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      );
}

class _StudioPicker extends ConsumerWidget {
  const _StudioPicker({required this.tokens, required this.selected, required this.onPick});

  final LiveStudioTokens tokens;
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(studioCatalogProvider);
    return catalog.when(
      loading: () => SizedBox(
        height: _kTarget,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: LiveStudioAccent.pink),
          ),
        ),
      ),
      error: (_, _) => Text('Studios could not be loaded.',
          style: LiveStudioType.s(12, FontWeight.w500, tokens.textMedium)),
      data: (studios) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final st in studios)
            _Tappable(
              tokens: tokens,
              label: HostSettingsLabels.studio(st.label),
              selected: st.id == selected,
              radius: 10,
              onTap: () => onPick(st.id),
              child: Container(
                constraints: const BoxConstraints(minHeight: _kTarget),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: _pill(tokens, st.id == selected),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam_rounded,
                        size: 16,
                        color: st.id == selected ? LiveStudioAccent.pink : tokens.textMedium),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(st.label,
                          overflow: TextOverflow.ellipsis,
                          style: LiveStudioType.s(12.5, FontWeight.w600, tokens.textHigh)),
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

class _StudioSlider extends StatelessWidget {
  const _StudioSlider({
    required this.tokens,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueText,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final LiveStudioTokens tokens;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueText;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        child: SizedBox(
          height: _kTarget,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: LiveStudioAccent.pink,
              inactiveTrackColor: tokens.ghostBorder,
              thumbColor: LiveStudioAccent.pink,
              overlayColor: LiveStudioAccent.pinkA(0.16),
              activeTickMarkColor: LiveStudioAccent.pinkA(0),
              inactiveTickMarkColor: LiveStudioAccent.pinkA(0),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              semanticFormatterCallback: (_) => valueText,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
      );
}

class _Swatches extends StatelessWidget {
  const _Swatches({required this.tokens, required this.options, required this.selected, required this.onPick});

  final LiveStudioTokens tokens;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            _Tappable(
              tokens: tokens,
              label: HostSettingsLabels.frameColor(i),
              selected: options[i].toLowerCase() == selected.toLowerCase(),
              radius: 9999,
              onTap: () => onPick(options[i]),
              child: SizedBox(
                width: _kTarget,
                height: _kTarget,
                child: Center(
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: studioHex(options[i]),
                      border: Border.all(
                        color: options[i].toLowerCase() == selected.toLowerCase()
                            ? tokens.textHigh
                            : tokens.ghostBorder,
                        width: options[i].toLowerCase() == selected.toLowerCase() ? 2 : 1,
                      ),
                    ),
                    child: options[i].toLowerCase() == selected.toLowerCase()
                        ? const Icon(Icons.check_rounded, size: 16, color: LiveStudioAccent.white)
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ],
      );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.tokens,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final LiveStudioTokens tokens;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _kTarget),
          child: Row(
            children: [
              Expanded(
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: LiveStudioType.s(13.5, FontWeight.w700, tokens.textHigh)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: LiveStudioType.s(11.5, FontWeight.w500, tokens.textMedium)),
                    ],
                  ),
                ),
              ),
              Semantics(
                label: HostSettingsLabels.showNames,
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: LiveStudioAccent.white,
                  activeTrackColor: LiveStudioAccent.pink,
                  inactiveThumbColor: tokens.textMedium,
                  inactiveTrackColor: tokens.ghostFill,
                  trackOutlineColor: WidgetStatePropertyAll(tokens.ghostBorder),
                  focusColor: tokens.focusRing.withValues(alpha: 0.35),
                ),
              ),
            ],
          ),
        ),
      );
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({required this.tokens, required this.mode, required this.selected, required this.onTap});

  final LiveStudioTokens tokens;
  final SpeakerMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _Tappable(
          tokens: tokens,
          label: HostSettingsLabels.speakerMode(mode),
          selected: selected,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: _pill(tokens, selected, radius: 12),
            child: Row(
              children: [
                Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    size: 18, color: selected ? LiveStudioAccent.pink : tokens.textMedium),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_modeTitle(mode),
                          style: LiveStudioType.s(13.5, FontWeight.w700, tokens.textHigh)),
                      const SizedBox(height: 2),
                      Text(_modeHelp(mode),
                          style: LiveStudioType.s(11.5, FontWeight.w500, tokens.textMedium)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
