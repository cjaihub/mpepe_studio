// LIVE STUDIO v2 — stage customization rules (workstream #6).
//
// Client mirror of functions/src/liveStudio/settings_logic.ts, used for the
// host's optimistic preview. The server stays authoritative; keep both in sync.

import '../contracts/studio_contracts.dart';

/// Wire keys of [StudioSettings] (also the only keys lsSetSettings accepts).
class StudioSettingsKeys {
  StudioSettingsKeys._();
  static const String studioId = 'studioId';
  static const String theme = 'theme';
  static const String frameWidth = 'frameWidth';
  static const String frameColor = 'frameColor';
  static const String guestSize = 'guestSize';
  static const String showNames = 'showNames';
  static const String studioDim = 'studioDim';
  static const String speakerMode = 'speakerMode';
  static const String layoutPreset = 'layoutPreset';

  static const List<String> all = [
    studioId, theme, frameWidth, frameColor, guestSize, showNames, studioDim, speakerMode,
    layoutPreset,
  ];
}

/// Studio dim slider step (SPEC §1.1).
const double kStudioDimStep = 0.05;

int clampFrameWidth(num v) =>
    v.round().clamp(StudioLimits.frameWidthMin, StudioLimits.frameWidthMax);

double clampStudioDim(num v) {
  final c = v.toDouble().clamp(StudioLimits.studioDimMin, StudioLimits.studioDimMax);
  return double.parse(((c / kStudioDimStep).round() * kStudioDimStep).toStringAsFixed(2));
}

/// Canonical option for [color] in [theme] (case-insensitive), or null.
String? frameColorOption(StudioTheme theme, String color) {
  final c = color.toLowerCase();
  for (final o in kFrameColorOptions[theme]!) {
    if (o.toLowerCase() == c) return o;
  }
  return null;
}

/// Same-index color in the [to] theme (index 0 when [color] is unknown).
String mapFrameColor(String color, StudioTheme from, StudioTheme to) {
  final c = color.toLowerCase();
  final i = kFrameColorOptions[from]!.indexWhere((o) => o.toLowerCase() == c);
  return kFrameColorOptions[to]![i >= 0 ? i : 0];
}

/// Repairs settings read from storage: a frame color that is not one of the
/// theme's options falls back to the theme default. Ranges are already
/// clamped by [StudioSettings.fromJson].
StudioSettings sanitizeSettings(StudioSettings s) =>
    frameColorOption(s.theme, s.frameColor) == null
        ? s.copyWith(frameColor: StudioSettings.defaultsFor(s.theme).frameColor)
        : s.copyWith(frameColor: frameColorOption(s.theme, s.frameColor));

/// Applies a wire-format [patch] to [base] the way the server will:
/// clamps ranges, snaps the dim, maps the frame color on a theme switch and
/// ignores values the server would reject (so the preview never shows them).
StudioSettings applySettingsPatch(StudioSettings base, Map<String, Object?> patch) {
  var next = base;
  final theme = patch[StudioSettingsKeys.theme];
  if (theme is String && StudioTheme.values.any((t) => t.wire == theme)) {
    final t = StudioTheme.fromWire(theme);
    next = next.copyWith(theme: t);
  }
  final studioId = patch[StudioSettingsKeys.studioId];
  if (studioId is String && studioId.isNotEmpty) next = next.copyWith(studioId: studioId);
  final fw = patch[StudioSettingsKeys.frameWidth];
  if (fw is num && fw.isFinite) next = next.copyWith(frameWidth: clampFrameWidth(fw));
  final fc = patch[StudioSettingsKeys.frameColor];
  final fcOpt = fc is String ? frameColorOption(next.theme, fc) : null;
  if (fcOpt != null) {
    next = next.copyWith(frameColor: fcOpt);
  } else if (next.theme != base.theme) {
    next = next.copyWith(frameColor: mapFrameColor(base.frameColor, base.theme, next.theme));
  }
  final gs = patch[StudioSettingsKeys.guestSize];
  if (gs is String && GuestSize.values.any((g) => g.wire == gs)) {
    next = next.copyWith(guestSize: GuestSize.fromWire(gs));
  }
  final sn = patch[StudioSettingsKeys.showNames];
  if (sn is bool) next = next.copyWith(showNames: sn);
  final dim = patch[StudioSettingsKeys.studioDim];
  if (dim is num && dim.isFinite) next = next.copyWith(studioDim: clampStudioDim(dim));
  final sm = patch[StudioSettingsKeys.speakerMode];
  if (sm is String && SpeakerMode.values.any((m) => m.wire == sm)) {
    next = next.copyWith(speakerMode: SpeakerMode.fromWire(sm));
  }
  final lp = patch[StudioSettingsKeys.layoutPreset];
  if (lp is String && LayoutPreset.values.any((m) => m.wire == lp)) {
    next = next.copyWith(layoutPreset: LayoutPreset.fromWire(lp));
  }
  return next;
}
