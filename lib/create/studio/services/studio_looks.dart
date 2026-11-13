import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../looks/engine/look_compiler.dart';
import '../../../looks/filters/oneova_filter_library.dart';
import '../../../looks/models/oneova_look.dart';
import '../models/studio_project.dart';

/// A Studio Look preset, built on the Oneova Look engine.
class StudioLookDef {
  final String id;
  final String name;
  final String group;
  final OneovaLook look;
  const StudioLookDef(this.id, this.name, this.group, this.look);
}

const _id = [CurvePoint(0, 0), CurvePoint(1, 1)];

/// Oneova Looks for Studio. A clip's Look and its tone/detail adjustments
/// run through `shaders/studio_look.frag` in the preview and through the
/// same shader (GLSL ES port) in the Media3 export.
class StudioLooks {
  StudioLooks._();

  static const groups = ['Cinematic', 'Portrait', 'Mood', 'Film', 'Vivid', 'Mono'];

  static const presets = <StudioLookDef>[
    StudioLookDef('none', 'None', 'Cinematic', OneovaLook(id: 'studio_none')),
    StudioLookDef(
      'teal_orange',
      'Blockbuster',
      'Cinematic',
      OneovaLook(
        id: 'studio_teal_orange',
        primary: LookPrimary(contrast: 1.12, highlights: -0.15, shadows: 0.1),
        color: LookColor(temperature: 6, vibrance: 0.15),
        wheels: LookWheels(lift: ColorWheel(r: -0.03, g: 0.01, b: 0.05), gain: ColorWheel(r: 0.05, g: 0.01, b: -0.05)),
        hsl: LookHsl(orange: HslBand(sat: 0.15), blue: HslBand(hue: -10, sat: 0.1), aqua: HslBand(hue: 15)),
        optics: LookOptics(vignette: 0.25),
      ),
    ),
    StudioLookDef(
      'noir_film',
      'Night city',
      'Cinematic',
      OneovaLook(
        id: 'studio_night_city',
        primary: LookPrimary(exposure: -0.1, contrast: 1.18, blacks: -0.2, highlights: -0.1),
        color: LookColor(temperature: -14, tint: 4, saturation: 0.9),
        wheels: LookWheels(lift: ColorWheel(b: 0.04), gain: ColorWheel(r: 0.02, b: 0.03)),
        optics: LookOptics(vignette: 0.35),
      ),
    ),
    StudioLookDef(
      'epic',
      'Epic',
      'Cinematic',
      OneovaLook(
        id: 'studio_epic',
        primary: LookPrimary(contrast: 1.22, highlights: -0.25, shadows: 0.12, whites: 0.1, blacks: -0.15),
        color: LookColor(saturation: 0.92, vibrance: 0.1),
        curves: LookCurves(master: [CurvePoint(0, 0.02), CurvePoint(0.25, 0.2), CurvePoint(0.75, 0.8), CurvePoint(1, 0.97)]),
        detail: LookDetail(sharpen: 0.25),
        optics: LookOptics(vignette: 0.3),
      ),
    ),
    StudioLookDef(
      'desert',
      'Desert',
      'Cinematic',
      OneovaLook(
        id: 'studio_desert',
        primary: LookPrimary(contrast: 1.05, highlights: -0.1),
        color: LookColor(temperature: 22, saturation: 0.85),
        wheels: LookWheels(gain: ColorWheel(r: 0.04, g: 0.02, b: -0.04), lift: ColorWheel(r: 0.02)),
        film: LookFilm(fade: 0.15, grain: 0.1),
      ),
    ),
    StudioLookDef(
      'soft_skin',
      'Soft skin',
      'Portrait',
      OneovaLook(
        id: 'studio_soft_skin',
        primary: LookPrimary(exposure: 0.08, contrast: 0.94, highlights: -0.1, shadows: 0.15),
        color: LookColor(temperature: 6, vibrance: 0.1, saturation: 0.97),
        hsl: LookHsl(orange: HslBand(sat: -0.05, lum: 0.12), red: HslBand(sat: -0.05)),
        film: LookFilm(fade: 0.05),
      ),
    ),
    StudioLookDef(
      'melanin',
      'Melanin glow',
      'Portrait',
      OneovaLook(
        id: 'studio_melanin',
        primary: LookPrimary(contrast: 1.06, shadows: 0.22, highlights: -0.08),
        color: LookColor(temperature: 8, vibrance: 0.18),
        hsl: LookHsl(orange: HslBand(sat: 0.08, lum: 0.08), red: HslBand(lum: 0.05), yellow: HslBand(sat: 0.05)),
        wheels: LookWheels(gain: ColorWheel(r: 0.02, g: 0.01)),
      ),
    ),
    StudioLookDef(
      'studio_portrait',
      'Studio',
      'Portrait',
      OneovaLook(
        id: 'studio_portrait',
        primary: LookPrimary(contrast: 1.1, whites: 0.08, blacks: -0.08),
        color: LookColor(saturation: 1.02),
        detail: LookDetail(sharpen: 0.3),
        optics: LookOptics(vignette: 0.15),
      ),
    ),
    StudioLookDef(
      'peach',
      'Peach',
      'Portrait',
      OneovaLook(
        id: 'studio_peach',
        primary: LookPrimary(exposure: 0.1, contrast: 0.96),
        color: LookColor(temperature: 10, tint: 6, saturation: 0.95),
        wheels: LookWheels(lift: ColorWheel(r: 0.03, b: 0.02)),
        film: LookFilm(fade: 0.12),
      ),
    ),
    StudioLookDef(
      'moody',
      'Moody',
      'Mood',
      OneovaLook(
        id: 'studio_moody',
        primary: LookPrimary(exposure: -0.15, contrast: 1.12, highlights: -0.3, blacks: -0.1),
        color: LookColor(temperature: -6, saturation: 0.8),
        hsl: LookHsl(green: HslBand(hue: 20, sat: -0.35), blue: HslBand(sat: -0.2)),
        film: LookFilm(fade: 0.1),
        optics: LookOptics(vignette: 0.35),
      ),
    ),
    StudioLookDef(
      'dreamy',
      'Dreamy',
      'Mood',
      OneovaLook(
        id: 'studio_dreamy',
        primary: LookPrimary(exposure: 0.12, contrast: 0.85, highlights: 0.1),
        color: LookColor(tint: 8, saturation: 0.9),
        wheels: LookWheels(lift: ColorWheel(r: 0.03, b: 0.05)),
        film: LookFilm(fade: 0.3),
      ),
    ),
    StudioLookDef(
      'cold_blue',
      'Cold blue',
      'Mood',
      OneovaLook(
        id: 'studio_cold_blue',
        primary: LookPrimary(contrast: 1.08),
        color: LookColor(temperature: -30, saturation: 0.85),
        wheels: LookWheels(gain: ColorWheel(b: 0.04)),
      ),
    ),
    StudioLookDef(
      'golden_hour',
      'Golden hour',
      'Mood',
      OneovaLook(
        id: 'studio_golden_hour',
        primary: LookPrimary(exposure: 0.05, highlights: -0.15, shadows: 0.1),
        color: LookColor(temperature: 28, vibrance: 0.2),
        wheels: LookWheels(gain: ColorWheel(r: 0.05, g: 0.02, b: -0.05)),
        optics: LookOptics(vignette: 0.2),
      ),
    ),
    StudioLookDef(
      'forest',
      'Forest',
      'Mood',
      OneovaLook(
        id: 'studio_forest',
        primary: LookPrimary(contrast: 1.08, shadows: 0.08),
        color: LookColor(temperature: -4, saturation: 0.95),
        hsl: LookHsl(green: HslBand(hue: -12, sat: 0.1, lum: -0.1), yellow: HslBand(hue: -10)),
        film: LookFilm(grain: 0.1),
      ),
    ),
    StudioLookDef(
      'kodak',
      'Warm film',
      'Film',
      OneovaLook(
        id: 'studio_warm_film',
        primary: LookPrimary(contrast: 1.06, highlights: -0.12),
        color: LookColor(temperature: 12, saturation: 0.92),
        curves: LookCurves(master: [CurvePoint(0, 0.05), CurvePoint(0.5, 0.52), CurvePoint(1, 0.96)]),
        film: LookFilm(grain: 0.3, fade: 0.15),
        optics: LookOptics(vignette: 0.2),
      ),
    ),
    StudioLookDef(
      'fuji',
      'Green film',
      'Film',
      OneovaLook(
        id: 'studio_green_film',
        primary: LookPrimary(contrast: 1.04),
        color: LookColor(tint: -8, saturation: 0.9),
        wheels: LookWheels(lift: ColorWheel(g: 0.02, b: 0.03)),
        hsl: LookHsl(green: HslBand(hue: 10, sat: 0.08), red: HslBand(sat: -0.08)),
        film: LookFilm(grain: 0.25, fade: 0.1),
      ),
    ),
    StudioLookDef(
      'super8',
      'Super 8',
      'Film',
      OneovaLook(
        id: 'studio_super8',
        primary: LookPrimary(exposure: 0.05, contrast: 1.15, highlights: -0.2),
        color: LookColor(temperature: 18, saturation: 0.8),
        film: LookFilm(grain: 0.6, fade: 0.25),
        optics: LookOptics(vignette: 0.5),
      ),
    ),
    StudioLookDef(
      'faded',
      'Faded',
      'Film',
      OneovaLook(
        id: 'studio_faded',
        primary: LookPrimary(contrast: 0.88),
        color: LookColor(saturation: 0.75),
        curves: LookCurves(master: [CurvePoint(0, 0.1), CurvePoint(1, 0.92)]),
        film: LookFilm(fade: 0.3, grain: 0.15),
      ),
    ),
    StudioLookDef(
      'pop',
      'Pop',
      'Vivid',
      OneovaLook(
        id: 'studio_pop',
        primary: LookPrimary(contrast: 1.15, whites: 0.08),
        color: LookColor(vibrance: 0.4, saturation: 1.15),
        detail: LookDetail(sharpen: 0.2),
      ),
    ),
    StudioLookDef(
      'neon_city',
      'Neon',
      'Vivid',
      OneovaLook(
        id: 'studio_neon',
        primary: LookPrimary(contrast: 1.2, blacks: -0.15),
        color: LookColor(tint: 10, vibrance: 0.35, saturation: 1.2),
        hsl: LookHsl(magenta: HslBand(sat: 0.25), blue: HslBand(sat: 0.2), purple: HslBand(sat: 0.2)),
        optics: LookOptics(vignette: 0.25),
      ),
    ),
    StudioLookDef(
      'tropical',
      'Tropical',
      'Vivid',
      OneovaLook(
        id: 'studio_tropical',
        primary: LookPrimary(exposure: 0.05, contrast: 1.08),
        color: LookColor(vibrance: 0.3, saturation: 1.1),
        hsl: LookHsl(aqua: HslBand(sat: 0.25, hue: -8), green: HslBand(sat: 0.15), yellow: HslBand(sat: 0.15)),
      ),
    ),
    StudioLookDef(
      'food',
      'Food',
      'Vivid',
      OneovaLook(
        id: 'studio_food',
        primary: LookPrimary(exposure: 0.08, contrast: 1.06, shadows: 0.12),
        color: LookColor(temperature: 8, vibrance: 0.25),
        hsl: LookHsl(red: HslBand(sat: 0.12), orange: HslBand(sat: 0.12), yellow: HslBand(sat: 0.1)),
        detail: LookDetail(sharpen: 0.35),
      ),
    ),
    StudioLookDef(
      'bw_classic',
      'Classic B&W',
      'Mono',
      OneovaLook(
        id: 'studio_bw_classic',
        primary: LookPrimary(contrast: 1.15),
        color: LookColor(saturation: 0),
        film: LookFilm(grain: 0.2),
      ),
    ),
    StudioLookDef(
      'bw_high',
      'High contrast',
      'Mono',
      OneovaLook(
        id: 'studio_bw_high',
        primary: LookPrimary(contrast: 1.45, blacks: -0.25, whites: 0.15),
        color: LookColor(saturation: 0),
        optics: LookOptics(vignette: 0.4),
      ),
    ),
    StudioLookDef(
      'bw_soft',
      'Soft mono',
      'Mono',
      OneovaLook(
        id: 'studio_bw_soft',
        primary: LookPrimary(contrast: 0.9),
        color: LookColor(saturation: 0, temperature: 10),
        film: LookFilm(fade: 0.2, grain: 0.15),
      ),
    ),
  ];

  /// A Studio preset or any Oneova filter (`ov_…` ids from the library).
  static StudioLookDef byId(String id) {
    if (OneovaFilterLibrary.isFilterId(id)) {
      final f = OneovaFilterLibrary.byId(id);
      if (f != null) return StudioLookDef(f.id, f.name, f.category, f.look);
    }
    return presets.firstWhere((p) => p.id == id, orElse: () => presets.first);
  }

  static double _l(double from, double to, double t) => from + (to - from) * t;

  /// Preset at [t] (0 = neutral, 1 = full) plus the clip's tone and detail
  /// adjustments; null when nothing would change.
  static OneovaLook? forClip(StudioClip c) => forLook(c.lookId, c.lookIntensity, c.adjust);

  /// [forClip] without a clip (the camera's live filter uses it, so the
  /// viewfinder matches the editor and the export exactly).
  static OneovaLook? forLook(String lookId, double intensity, StudioAdjust a) {
    if (lookId == 'none' && !a.hasLookKeys) return null;
    final p = byId(lookId).look;
    final t = lookId == 'none' ? 0.0 : intensity.clamp(0.0, 1.0);
    ColorWheel w(ColorWheel x) => ColorWheel(r: x.r * t, g: x.g * t, b: x.b * t, lum: x.lum * t);
    HslBand h(HslBand x) => HslBand(hue: x.hue * t, sat: x.sat * t, lum: x.lum * t);
    List<CurvePoint> cv(List<CurvePoint> pts) => [for (final q in pts) CurvePoint(q.x, _l(q.x, q.y, t))];
    return OneovaLook(
      id: 'studio_clip_${lookId}_${t.toStringAsFixed(2)}_${a.toJson().values.join('_')}',
      primary: LookPrimary(
        exposure: p.primary.exposure * t,
        contrast: _l(1, p.primary.contrast, t),
        pivot: p.primary.pivot,
        highlights: (p.primary.highlights * t + a.highlights).clamp(-1.0, 1.0),
        shadows: (p.primary.shadows * t + a.shadows).clamp(-1.0, 1.0),
        whites: (p.primary.whites * t + a.whites).clamp(-1.0, 1.0),
        blacks: (p.primary.blacks * t + a.blacks).clamp(-1.0, 1.0),
      ),
      color: LookColor(
        temperature: p.color.temperature * t,
        tint: p.color.tint * t,
        vibrance: (p.color.vibrance * t + a.vibrance).clamp(-1.0, 1.0),
        saturation: _l(1, p.color.saturation, t),
      ),
      wheels: LookWheels(lift: w(p.wheels.lift), gamma: w(p.wheels.gamma), gain: w(p.wheels.gain), offset: w(p.wheels.offset)),
      curves: LookCurves(
        master: p.curves.master.length > 2 || p.curves.master.first.y != 0 ? cv(p.curves.master) : _id,
        red: cv(p.curves.red),
        green: cv(p.curves.green),
        blue: cv(p.curves.blue),
      ),
      hsl: LookHsl(
        red: h(p.hsl.red),
        orange: h(p.hsl.orange),
        yellow: h(p.hsl.yellow),
        green: h(p.hsl.green),
        aqua: h(p.hsl.aqua),
        blue: h(p.hsl.blue),
        purple: h(p.hsl.purple),
        magenta: h(p.hsl.magenta),
      ),
      film: LookFilm(grain: (p.film.grain * t + a.grain).clamp(0.0, 1.0), fade: p.film.fade * t),
      detail: LookDetail(sharpen: (p.detail.sharpen * t + a.sharpen).clamp(0.0, 1.0)),
      optics: LookOptics(vignette: (p.optics.vignette * t + a.vignette).clamp(0.0, 1.0)),
    );
  }

  static Future<CompiledLook> compiled(OneovaLook look) => LookCompiler.compile(look, maxLutSize: 33);

  /// Native export payload for [look] (see LookSpec in the media engine).
  static Future<Map<String, Object?>> exportSpec(OneovaLook look) async {
    final compiled = await LookCompiler.compile(look, maxLutSize: 33);
    return {
      'uniforms': LookCompiler.uniformValues(compiled, ui.Size.zero),
      'lut': compiled.lutAtlasRgba,
      'lutSize': compiled.lutSize,
      'curves': compiled.curvesRgba,
    };
  }

  static Future<ui.FragmentProgram?>? _program;
  static Future<ui.FragmentProgram?> program() => _program ??= ui.FragmentProgram.fromAsset('shaders/studio_look.frag')
      .then<ui.FragmentProgram?>((p) => p, onError: (Object e) {
        debugPrint('[StudioLooks] shader load failed: $e');
        _program = null;
        return null;
      });
}

/// Grades [child] with a Look on the GPU (Impeller). Without shader filter
/// support the preview shows the clip ungraded; the export still applies it.
class StudioLookFilter extends StatefulWidget {
  final OneovaLook? look;
  final Widget child;
  const StudioLookFilter({super.key, required this.look, required this.child});

  @override
  State<StudioLookFilter> createState() => _StudioLookFilterState();
}

class _StudioLookFilterState extends State<StudioLookFilter> {
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    if (ui.ImageFilter.isShaderFilterSupported) {
      StudioLooks.program().then((p) {
        if (!mounted || p == null) return;
        _program = p;
        _compile();
      });
    }
  }

  @override
  void didUpdateWidget(StudioLookFilter old) {
    super.didUpdateWidget(old);
    if (old.look?.id != widget.look?.id) _compile();
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  Future<void> _compile() async {
    final look = widget.look;
    final program = _program;
    final req = ++_req;
    if (look == null || program == null) {
      if (_shader != null) setState(() => _shader = null);
      return;
    }
    try {
      final c = await LookCompiler.compile(look, maxLutSize: 33);
      if (!mounted || req != _req) return;
      final shader = program.fragmentShader();
      final Float32List values = LookCompiler.uniformValues(c, ui.Size.zero);
      for (var i = 2; i < values.length; i++) {
        shader.setFloat(i, values[i]);
      }
      shader.setImageSampler(1, c.lutAtlas);
      shader.setImageSampler(2, c.curves);
      setState(() => _shader = shader);
    } catch (e) {
      debugPrint('[StudioLookFilter] compile failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    if (widget.look == null || shader == null) return widget.child;
    return ImageFiltered(imageFilter: ui.ImageFilter.shader(shader), child: widget.child);
  }
}
