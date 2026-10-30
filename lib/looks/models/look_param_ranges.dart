import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import 'oneova_look.dart';

/// Inclusive numeric range for one OneovaLook parameter.
@immutable
class ParamRange {
  final double min;
  final double max;

  const ParamRange(this.min, this.max);

  double clamp(double v) => v.clamp(min, max).toDouble();
  bool contains(double v) => v >= min && v <= max;

  factory ParamRange.fromJson(dynamic raw, ParamRange fallback) {
    if (raw is List && raw.length == 2 && raw[0] is num && raw[1] is num) {
      return ParamRange((raw[0] as num).toDouble(), (raw[1] as num).toDouble());
    }
    return fallback;
  }
}

/// Parameter ranges for OneovaLook validation.
///
/// Defaults are documented in `docs/looks/config_keys.md` and can be
/// overridden per key with the Remote Config JSON `looks_param_ranges`,
/// e.g. `{"primary.exposure": [-3, 3]}`.
@immutable
class LookParamRanges {
  static const String remoteConfigKey = 'looks_param_ranges';

  static const Map<String, ParamRange> defaults = {
    'intensity': ParamRange(0, 1),
    'primary.exposure': ParamRange(-2, 2),
    'primary.contrast': ParamRange(0.5, 2),
    'primary.pivot': ParamRange(0, 1),
    'primary.highlights': ParamRange(-1, 1),
    'primary.shadows': ParamRange(-1, 1),
    'primary.whites': ParamRange(-1, 1),
    'primary.blacks': ParamRange(-1, 1),
    'color.temperature': ParamRange(-100, 100),
    'color.tint': ParamRange(-100, 100),
    'color.vibrance': ParamRange(-1, 1),
    'color.saturation': ParamRange(0, 2),
    'wheels.channel': ParamRange(-1, 1),
    'hsl.hue': ParamRange(-180, 180),
    'hsl.sat': ParamRange(-1, 1),
    'hsl.lum': ParamRange(-1, 1),
    'lut.intensity': ParamRange(0, 1),
    'lut.size': ParamRange(2, 65),
    'film.grain': ParamRange(0, 1),
    'film.fade': ParamRange(0, 1),
    'optics.vignette': ParamRange(0, 1),
    'detail.sharpen': ParamRange(0, 1),
  };

  final Map<String, ParamRange> ranges;

  const LookParamRanges([this.ranges = defaults]);

  ParamRange operator [](String key) => ranges[key] ?? defaults[key]!;

  /// Parses the Remote Config JSON; unknown or malformed keys keep defaults.
  factory LookParamRanges.fromJsonString(String raw) {
    if (raw.trim().isEmpty) return const LookParamRanges();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const LookParamRanges();
      return LookParamRanges({
        for (final e in defaults.entries)
          e.key: ParamRange.fromJson(decoded[e.key], e.value),
      });
    } catch (e) {
      debugPrint('[LookParamRanges] Invalid $remoteConfigKey: $e');
      return const LookParamRanges();
    }
  }

  /// Reads the active Remote Config value (fetch is owned by app startup).
  factory LookParamRanges.fromRemoteConfig() {
    try {
      return LookParamRanges.fromJsonString(
          FirebaseRemoteConfig.instance.getString(remoteConfigKey));
    } catch (_) {
      return const LookParamRanges();
    }
  }
}

/// Realtime budget for Live and Camera; Remote Config key `looks_realtime_budget`.
@immutable
class LookRealtimeBudget {
  static const String remoteConfigKey = 'looks_realtime_budget';

  /// LUTs are pre-composed into one texture, so this caps CPU compose time.
  final int maxLutStack;
  final int maxLutSize;
  final bool allowSharpen;

  /// Cross-fade between the old and new look when Live/Camera switches.
  final int crossFadeMs;

  const LookRealtimeBudget({
    this.maxLutStack = 4,
    this.maxLutSize = 33,
    this.allowSharpen = true,
    this.crossFadeMs = 300,
  });

  factory LookRealtimeBudget.fromJsonString(String raw) {
    const d = LookRealtimeBudget();
    if (raw.trim().isEmpty) return d;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return LookRealtimeBudget(
        maxLutStack: (m['maxLutStack'] as num?)?.toInt() ?? d.maxLutStack,
        maxLutSize: (m['maxLutSize'] as num?)?.toInt() ?? d.maxLutSize,
        allowSharpen: m['allowSharpen'] as bool? ?? d.allowSharpen,
        crossFadeMs: (m['crossFadeMs'] as num?)?.toInt() ?? d.crossFadeMs,
      );
    } catch (e) {
      debugPrint('[LookRealtimeBudget] Invalid $remoteConfigKey: $e');
      return d;
    }
  }

  factory LookRealtimeBudget.fromRemoteConfig() {
    try {
      return LookRealtimeBudget.fromJsonString(
          FirebaseRemoteConfig.instance.getString(remoteConfigKey));
    } catch (_) {
      return const LookRealtimeBudget();
    }
  }
}

/// Validation, clamping and realtime checks for [OneovaLook].
extension OneovaLookValidation on OneovaLook {
  Map<String, double> _scalarParams() => {
        'intensity': intensity,
        'primary.exposure': primary.exposure,
        'primary.contrast': primary.contrast,
        'primary.pivot': primary.pivot,
        'primary.highlights': primary.highlights,
        'primary.shadows': primary.shadows,
        'primary.whites': primary.whites,
        'primary.blacks': primary.blacks,
        'color.temperature': color.temperature,
        'color.tint': color.tint,
        'color.vibrance': color.vibrance,
        'color.saturation': color.saturation,
        'film.grain': film.grain,
        'film.fade': film.fade,
        'optics.vignette': optics.vignette,
        'detail.sharpen': detail.sharpen,
      };

  /// Returns a human-readable list of out-of-range parameters (empty = valid).
  List<String> validate([LookParamRanges ranges = const LookParamRanges()]) {
    final errors = <String>[];
    _scalarParams().forEach((key, v) {
      final r = ranges[key];
      if (!v.isFinite || !r.contains(v)) {
        errors.add('$key=$v outside [${r.min}, ${r.max}]');
      }
    });
    final wr = ranges['wheels.channel'];
    for (final (name, w) in [
      ('lift', wheels.lift),
      ('gamma', wheels.gamma),
      ('gain', wheels.gain),
    ]) {
      for (final (c, v) in [('r', w.r), ('g', w.g), ('b', w.b), ('lum', w.lum)]) {
        if (!wr.contains(v)) errors.add('wheels.$name.$c=$v outside [${wr.min}, ${wr.max}]');
      }
    }
    for (final (band, b) in hsl.bands) {
      if (!ranges['hsl.hue'].contains(b.hue)) errors.add('hsl.$band.hue=${b.hue}');
      if (!ranges['hsl.sat'].contains(b.sat)) errors.add('hsl.$band.sat=${b.sat}');
      if (!ranges['hsl.lum'].contains(b.lum)) errors.add('hsl.$band.lum=${b.lum}');
    }
    for (final l in lutStack) {
      if (!ranges['lut.intensity'].contains(l.intensity)) errors.add('lut.${l.id}.intensity=${l.intensity}');
      if (!ranges['lut.size'].contains(l.size.toDouble())) errors.add('lut.${l.id}.size=${l.size}');
    }
    return errors;
  }

  /// Returns a copy with every scalar clamped into [ranges].
  OneovaLook clampedTo([LookParamRanges ranges = const LookParamRanges()]) {
    double c(String k, double v) => ranges[k].clamp(v.isFinite ? v : 0);
    ColorWheel cw(ColorWheel w) => ColorWheel(
          r: c('wheels.channel', w.r),
          g: c('wheels.channel', w.g),
          b: c('wheels.channel', w.b),
          lum: c('wheels.channel', w.lum),
        );
    HslBand hb(HslBand b) => HslBand(
          hue: c('hsl.hue', b.hue),
          sat: c('hsl.sat', b.sat),
          lum: c('hsl.lum', b.lum),
        );
    return copyWith(
      intensity: c('intensity', intensity),
      primary: primary.copyWith(
        exposure: c('primary.exposure', primary.exposure),
        contrast: c('primary.contrast', primary.contrast),
        pivot: c('primary.pivot', primary.pivot),
        highlights: c('primary.highlights', primary.highlights),
        shadows: c('primary.shadows', primary.shadows),
        whites: c('primary.whites', primary.whites),
        blacks: c('primary.blacks', primary.blacks),
      ),
      color: color.copyWith(
        temperature: c('color.temperature', color.temperature),
        tint: c('color.tint', color.tint),
        vibrance: c('color.vibrance', color.vibrance),
        saturation: c('color.saturation', color.saturation),
      ),
      wheels: LookWheels(
        lift: cw(wheels.lift),
        gamma: cw(wheels.gamma),
        gain: cw(wheels.gain),
        offset: cw(wheels.offset),
      ),
      hsl: LookHsl(
        red: hb(hsl.red),
        orange: hb(hsl.orange),
        yellow: hb(hsl.yellow),
        green: hb(hsl.green),
        aqua: hb(hsl.aqua),
        blue: hb(hsl.blue),
        purple: hb(hsl.purple),
        magenta: hb(hsl.magenta),
      ),
      lutStack: [
        for (final l in lutStack)
          l.copyWith(intensity: c('lut.intensity', l.intensity)),
      ],
      film: film.copyWith(
        grain: c('film.grain', film.grain),
        fade: c('film.fade', film.fade),
      ),
      optics: optics.copyWith(vignette: c('optics.vignette', optics.vignette)),
      detail: detail.copyWith(sharpen: c('detail.sharpen', detail.sharpen)),
    );
  }

  /// True if the look fits the Live/Camera budget.
  bool isRealtimeCompatibleWith(LookRealtimeBudget budget) {
    final luts = lutStack.where((l) => l.isEnabled).toList();
    if (luts.length > budget.maxLutStack) return false;
    if (luts.any((l) => l.size > budget.maxLutSize)) return false;
    if (!budget.allowSharpen && detail.sharpen > 0) return false;
    return true;
  }
}
