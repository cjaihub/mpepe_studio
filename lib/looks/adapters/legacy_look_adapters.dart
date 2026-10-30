import 'dart:math' as math;

import '../../create/models/cinema_preset.dart';
import '../../backend/photo_studio/preset_manager.dart';
import '../../backend/photo_studio/photo_studio_models.dart';
import '../../backend/projects/models/pro_project_models.dart' hide ColorWheel;
import '../../backend/projects/models/oneova_draft_model.dart';
import '../../backend/mask_engine/universal_mask_models.dart';
import '../../backend/live/models/live_models.dart';
import '../models/oneova_look.dart';

/// Bidirectional & inbound adapters mapping legacy color/preset representations
/// into the unified OneovaLook (schemaVersion 2).
class LegacyLookAdapters {
  /// Converts a [CinemaPreset] into a cinematic [OneovaLook].
  static OneovaLook fromCinemaPreset(CinemaPreset cp) {
    // Map kelvin (3200..8000) to temperature (-100..100) centered at 5600K
    final tempNormalized = ((cp.kelvin - 5600) / 2400.0 * 100.0).clamp(-100.0, 100.0);
    final tintNormalized = (cp.tint * 10.0).clamp(-100.0, 100.0);

    return OneovaLook(
      id: cp.id,
      name: cp.name,
      categories: ['cinematic', cp.colorScience.name],
      tags: [cp.colorScience.shortTag, if (cp.isAiEnhanced) 'ai_enhanced'],
      source: cp.isUserCustom ? 'user' : 'catalog',
      primary: LookPrimary(
        exposure: cp.exposure.clamp(-2.0, 2.0),
        contrast: cp.contrast.clamp(0.5, 2.0),
      ),
      color: LookColor(
        temperature: tempNormalized,
        tint: tintNormalized,
        saturation: cp.saturation.clamp(0.0, 2.0),
      ),
      film: LookFilm(
        emulationProfile: cp.colorScience.name,
        grain: cp.filmGrain.clamp(0.0, 1.0),
      ),
      createdAt: cp.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  /// Converts a [ColorGradingPayload] into a [OneovaLook].
  static OneovaLook fromColorGradingPayload(ColorGradingPayload payload, {String id = 'payload_look', String name = 'Mask Grade'}) {
    return OneovaLook(
      id: id,
      name: name,
      primary: LookPrimary(
        exposure: (payload.exposure ?? 0.0).clamp(-2.0, 2.0),
        contrast: (payload.contrast != null ? (1.0 + payload.contrast!) : 1.0).clamp(0.5, 2.0),
        highlights: (payload.highlights ?? 0.0).clamp(-1.0, 1.0),
        shadows: (payload.shadows ?? 0.0).clamp(-1.0, 1.0),
      ),
      color: LookColor(
        temperature: (payload.temperature ?? 0.0).clamp(-100.0, 100.0),
        tint: (payload.tint ?? 0.0).clamp(-100.0, 100.0),
        saturation: (payload.saturation != null ? (1.0 + payload.saturation!) : 1.0).clamp(0.0, 2.0),
      ),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Converts a multi-layer [StudioPreset] into a [OneovaLook].
  static OneovaLook fromStudioPreset(StudioPreset sp) {
    final base = fromColorGradingPayload(sp.globalAdjustments, id: sp.id, name: sp.name);
    return base.copyWith(
      categories: ['studio', 'retouch'],
    );
  }

  /// Converts a [PhotoPreset] into a [OneovaLook], keeping its adjustments.
  static OneovaLook fromPhotoPreset(PhotoPreset pp) {
    return fromEditGraph(pp.graph, id: pp.id, name: pp.name).copyWith(
      categories: [pp.category.toLowerCase(), 'photo'],
    );
  }

  /// Maps the global (first) layer of a Photo Studio [EditGraph] into a look.
  ///
  /// Photo Studio sliders store -1..1 (`value`), wheels store hue in degrees
  /// with saturation 0..1 and luminance -1..1, HSL stores -100..100 per
  /// channel, and curves store normalised `[x, y]` points. Masked layers are
  /// rendered by the mask engine, not by a global look.
  static OneovaLook fromEditGraph(EditGraph graph, {String id = 'photo_graph', String name = 'Photo Edit'}) {
    final now = DateTime.now();
    if (graph.layers.isEmpty) {
      return OneovaLook(id: id, name: name, createdAt: now, updatedAt: now);
    }
    final layer = graph.layers.first;
    final adjustments = layer.adjustments.where((a) => a.isEnabled).toList();

    double v(AdjustmentType t) {
      for (final a in adjustments.reversed) {
        if (a.type == t) return (a.parameters['value'] as num?)?.toDouble() ?? 0.0;
      }
      return 0.0;
    }

    ColorWheel wheel(AdjustmentType t) {
      for (final a in adjustments.reversed) {
        if (a.type != t) continue;
        final hue = (a.parameters['hue'] as num?)?.toDouble() ?? 0.0;
        final sat = ((a.parameters['saturation'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0);
        final lum = ((a.parameters['luminance'] as num?)?.toDouble() ?? 0.0).clamp(-1.0, 1.0);
        // Hue/saturation on the wheel → RGB push (120° apart), scaled so a
        // full-saturation wheel shifts a channel by a quarter of its range.
        final rad = hue * math.pi / 180;
        const k = 0.25;
        return ColorWheel(
          r: k * sat * math.cos(rad),
          g: k * sat * math.cos(rad - 2 * math.pi / 3),
          b: k * sat * math.cos(rad - 4 * math.pi / 3),
          lum: k * lum,
        );
      }
      return const ColorWheel();
    }

    List<CurvePoint>? curve(AdjustmentType t) {
      for (final a in adjustments.reversed) {
        if (a.type != t) continue;
        final raw = a.parameters['points'];
        if (raw is! List) return null;
        final pts = <CurvePoint>[
          for (final p in raw)
            if (p is List && p.length >= 2 && p[0] is num && p[1] is num)
              CurvePoint((p[0] as num).toDouble().clamp(0.0, 1.0), (p[1] as num).toDouble().clamp(0.0, 1.0)),
        ];
        return pts.length >= 2 ? pts : null;
      }
      return null;
    }

    HslBand band(String channel) {
      for (final a in adjustments.reversed) {
        if (a.type == AdjustmentType.HSL && a.parameters['channel'] == channel) {
          double p(String k) => ((a.parameters[k] as num?)?.toDouble() ?? 0.0).clamp(-100.0, 100.0) / 100.0;
          // Lightroom-style hue slider: ±100 ≈ ±30°.
          return HslBand(hue: p('hue') * 30.0, sat: p('saturation'), lum: p('luminance'));
        }
      }
      return const HslBand();
    }

    const identity = [CurvePoint(0, 0), CurvePoint(1, 1)];
    return OneovaLook(
      id: id,
      name: name,
      categories: const ['photo'],
      primary: LookPrimary(
        exposure: v(AdjustmentType.EXPOSURE).clamp(-2.0, 2.0),
        contrast: math.pow(2.0, v(AdjustmentType.CONTRAST)).toDouble().clamp(0.5, 2.0),
        highlights: v(AdjustmentType.HIGHLIGHTS).clamp(-1.0, 1.0),
        shadows: v(AdjustmentType.SHADOWS).clamp(-1.0, 1.0),
        whites: v(AdjustmentType.WHITES).clamp(-1.0, 1.0),
        blacks: v(AdjustmentType.BLACKS).clamp(-1.0, 1.0),
      ),
      color: LookColor(
        temperature: (v(AdjustmentType.TEMPERATURE) * 100).clamp(-100.0, 100.0),
        tint: (v(AdjustmentType.TINT) * 100).clamp(-100.0, 100.0),
        vibrance: v(AdjustmentType.VIBRANCE).clamp(-1.0, 1.0),
        saturation: (1 + v(AdjustmentType.SATURATION)).clamp(0.0, 2.0),
      ),
      wheels: LookWheels(
        lift: wheel(AdjustmentType.COLOR_WHEELS_SHADOWS),
        gamma: wheel(AdjustmentType.COLOR_WHEELS_MIDTONES),
        gain: wheel(AdjustmentType.COLOR_WHEELS_HIGHLIGHTS),
      ),
      curves: LookCurves(
        master: curve(AdjustmentType.CURVES_RGB) ?? identity,
        red: curve(AdjustmentType.CURVES_RED) ?? identity,
        green: curve(AdjustmentType.CURVES_GREEN) ?? identity,
        blue: curve(AdjustmentType.CURVES_BLUE) ?? identity,
      ),
      hsl: LookHsl(
        red: band('red'),
        orange: band('orange'),
        yellow: band('yellow'),
        green: band('green'),
        aqua: band('cyan'), // Photo Studio names the aqua band 'cyan'.
        blue: band('blue'),
        purple: band('purple'),
        magenta: band('magenta'),
      ),
      detail: LookDetail(sharpen: v(AdjustmentType.SHARPNESS).abs().clamp(0.0, 1.0)),
      optics: LookOptics(vignette: v(AdjustmentType.VIGNETTE).abs().clamp(0.0, 1.0)),
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Converts a [ColorPreset] from video production into a [OneovaLook].
  static OneovaLook fromColorPreset(ColorPreset cp) {
    final cs = cp.state;
    return OneovaLook(
      id: cp.id,
      name: cp.name,
      categories: [cp.category.toLowerCase(), 'video'],
      primary: LookPrimary(
        exposure: (cs.exposure * 2.0).clamp(-2.0, 2.0),
        contrast: cs.contrast.clamp(0.5, 2.0),
        highlights: cs.highlights.clamp(-1.0, 1.0),
        shadows: cs.shadows.clamp(-1.0, 1.0),
      ),
      color: LookColor(
        temperature: (cs.temperature * 100.0).clamp(-100.0, 100.0),
        tint: (cs.tint * 100.0).clamp(-100.0, 100.0),
      ),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Converts an [OneovaColorGrade] draft into a [OneovaLook].
  static OneovaLook fromOneovaColorGrade(OneovaColorGrade ocg, {String id = 'draft_grade', String name = 'Draft Grade'}) {
    return OneovaLook(
      id: id,
      name: name,
      primary: LookPrimary(
        exposure: (ocg.exposure * 2.0).clamp(-2.0, 2.0),
        contrast: ocg.contrast.clamp(0.5, 2.0),
      ),
      color: LookColor(
        temperature: (ocg.temperature * 100.0).clamp(-100.0, 100.0),
        tint: (ocg.tint * 100.0).clamp(-100.0, 100.0),
        saturation: ocg.saturation.clamp(0.0, 2.0),
      ),
      film: LookFilm(
        emulationProfile: ocg.lutPreset,
      ),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Converts [LiveBeautyConfig] into modern [BoostBeautyConfig].
  static BoostBeautyConfig fromLiveBeautyConfig(LiveBeautyConfig lbc) {
    final hasBeauty = lbc.smoothSkinLevel > 0 || lbc.warmToneLevel > 0;
    return BoostBeautyConfig(
      isEnabled: hasBeauty,
      smoothSkin: lbc.smoothSkinLevel.clamp(0.0, 1.0),
      evenTone: (lbc.smoothSkinLevel * 0.8).clamp(0.0, 1.0),
      eyeBrighten: (lbc.ringLightIntensity * 0.5).clamp(0.0, 1.0),
      autoBoostLevel: lbc.smoothSkinLevel.clamp(0.0, 1.0),
    );
  }

  /// Converts modern [BoostBeautyConfig] back to [LiveBeautyConfig] for legacy live listeners.
  static LiveBeautyConfig toLiveBeautyConfig(BoostBeautyConfig bbc) {
    if (!bbc.isEnabled) {
      return const LiveBeautyConfig();
    }
    return LiveBeautyConfig(
      smoothSkinLevel: bbc.smoothSkin,
      ringLightIntensity: (bbc.eyeBrighten * 2.0).clamp(0.0, 1.0),
      warmToneLevel: 0.0,
      backgroundBlurEnabled: false,
    );
  }
}
