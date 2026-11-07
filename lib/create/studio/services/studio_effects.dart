import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/studio_project.dart';

/// One effect in `shaders/studio_fx.frag` (preview) and StudioFxShader.kt
/// (export). [type] is the shader's `uType`.
class StudioEffectDef {
  final String id;
  final String name;
  final String group;
  final int type;
  final IconData icon;
  final double amount;
  const StudioEffectDef(this.id, this.name, this.group, this.type, this.icon, {this.amount = 0.7});
}

class StudioEffects {
  StudioEffects._();

  static const groups = ['Motion', 'Glitch', 'Lens', 'Color', 'Retro', 'Layout', 'Transition'];

  static const all = <StudioEffectDef>[
    StudioEffectDef('shake', 'Shake', 'Motion', 7, Icons.vibration_rounded, amount: 0.6),
    StudioEffectDef('zoom_pulse', 'Zoom pulse', 'Motion', 8, Icons.zoom_out_map_rounded, amount: 0.6),
    StudioEffectDef('strobe', 'Strobe', 'Motion', 19, Icons.flare_rounded, amount: 0.5),
    StudioEffectDef('flicker', 'Flicker', 'Motion', 9, Icons.wb_iridescent_outlined, amount: 0.6),
    StudioEffectDef('radial_blur', 'Zoom blur', 'Motion', 21, Icons.blur_circular_rounded, amount: 0.6),
    StudioEffectDef('glitch', 'Glitch', 'Glitch', 3, Icons.broken_image_outlined),
    StudioEffectDef('rgb_split', 'RGB split', 'Glitch', 2, Icons.layers_outlined, amount: 0.6),
    StudioEffectDef('vhs', 'VHS', 'Glitch', 4, Icons.videocam_outlined),
    StudioEffectDef('pixelate', 'Pixelate', 'Glitch', 5, Icons.grid_on_rounded, amount: 0.5),
    StudioEffectDef('blur', 'Soft blur', 'Lens', 1, Icons.blur_on_rounded, amount: 0.5),
    StudioEffectDef('dreamy', 'Dreamy glow', 'Lens', 23, Icons.auto_awesome_outlined, amount: 0.6),
    StudioEffectDef('bulge', 'Fisheye', 'Lens', 15, Icons.circle_outlined, amount: 0.5),
    StudioEffectDef('spotlight', 'Spotlight', 'Lens', 14, Icons.highlight_rounded, amount: 0.6),
    StudioEffectDef('light_leak', 'Light leak', 'Lens', 10, Icons.wb_sunny_outlined, amount: 0.7),
    StudioEffectDef('neon_edges', 'Neon edges', 'Color', 22, Icons.gesture_rounded, amount: 0.8),
    StudioEffectDef('duotone', 'Duotone', 'Color', 13, Icons.gradient_rounded, amount: 0.8),
    StudioEffectDef('thermal', 'Thermal', 'Color', 25, Icons.thermostat_rounded, amount: 0.9),
    StudioEffectDef('invert', 'Invert', 'Color', 12, Icons.invert_colors_rounded, amount: 1),
    StudioEffectDef('posterize', 'Posterize', 'Color', 11, Icons.palette_outlined, amount: 0.6),
    StudioEffectDef('bw', 'Black & white', 'Color', 24, Icons.contrast_rounded, amount: 1),
    StudioEffectDef('sepia', 'Sepia', 'Retro', 18, Icons.coffee_outlined, amount: 0.8),
    StudioEffectDef('old_film', 'Old film', 'Retro', 20, Icons.movie_filter_outlined),
    StudioEffectDef('crt', 'CRT', 'Retro', 17, Icons.tv_rounded),
    StudioEffectDef('mirror', 'Mirror', 'Layout', 6, Icons.flip_rounded, amount: 1),
    StudioEffectDef('kaleido', 'Four-way', 'Layout', 16, Icons.window_outlined, amount: 1),
    StudioEffectDef('triple', 'Triple', 'Layout', 26, Icons.view_agenda_outlined, amount: 1),
    StudioEffectDef('quad', 'Quad', 'Layout', 27, Icons.grid_view_rounded, amount: 1),
    StudioEffectDef('flash_in', 'Flash in', 'Transition', 28, Icons.flash_on_rounded, amount: 1),
    StudioEffectDef('fade_in', 'Fade from black', 'Transition', 29, Icons.gradient_outlined, amount: 1),
    StudioEffectDef('fade_out', 'Fade to black', 'Transition', 30, Icons.brightness_3_outlined, amount: 1),
  ];

  static StudioEffectDef? byId(String id) => all.where((e) => e.id == id).firstOrNull;

  static Future<ui.FragmentProgram?>? _program;
  static Future<ui.FragmentProgram?> program() => _program ??= ui.FragmentProgram.fromAsset('shaders/studio_fx.frag')
      .then<ui.FragmentProgram?>((p) => p, onError: (Object e) {
        debugPrint('[StudioEffects] shader load failed: $e');
        _program = null;
        return null;
      });

  /// Splits [effects] into passes with no overlap inside a pass (one shader
  /// pass per group in the export).
  static List<List<StudioEffect>> passes(List<StudioEffect> effects) {
    final sorted = [...effects]..sort((a, b) => a.startMs.compareTo(b.startMs));
    final out = <List<StudioEffect>>[];
    for (final e in sorted) {
      final pass = out.where((p) => p.last.endMs <= e.startMs).firstOrNull;
      if (pass != null) {
        pass.add(e);
      } else {
        out.add([e]);
      }
    }
    return out;
  }

  /// Native windows for the clip spanning [clipStart, clipEnd) of output time.
  static List<List<Map<String, Object?>>> exportPasses(List<StudioEffect> effects, int clipStart, int clipEnd) {
    final result = <List<Map<String, Object?>>>[];
    for (final pass in passes(effects)) {
      final windows = <Map<String, Object?>>[];
      for (final e in pass) {
        final def = byId(e.effectId);
        if (def == null || e.endMs <= clipStart || e.startMs >= clipEnd || e.amount <= 0) continue;
        final s = e.startMs < clipStart ? clipStart : e.startMs;
        final en = e.endMs > clipEnd ? clipEnd : e.endMs;
        windows.add({
          'type': def.type,
          'amount': e.amount,
          'startMs': s - clipStart,
          'endMs': en - clipStart,
          'layerOffsetMs': s - e.startMs,
          'layerMs': e.endMs - e.startMs,
        });
      }
      if (windows.isNotEmpty) result.add(windows);
    }
    return result;
  }
}

/// Applies the effects active at [posMs] to [child] (preview). Effects need
/// Impeller's shader filters; without them the preview shows the plain frame
/// (exports still bake the effects).
class StudioFxFilter extends StatefulWidget {
  final List<StudioEffect> effects;
  final int posMs;
  final Widget child;
  const StudioFxFilter({super.key, required this.effects, required this.posMs, required this.child});

  @override
  State<StudioFxFilter> createState() => _StudioFxFilterState();
}

class _StudioFxFilterState extends State<StudioFxFilter> {
  ui.FragmentProgram? _program;
  final List<ui.FragmentShader> _shaders = [];

  @override
  void initState() {
    super.initState();
    if (ui.ImageFilter.isShaderFilterSupported) {
      StudioEffects.program().then((p) {
        if (mounted) setState(() => _program = p);
      });
    }
  }

  @override
  void dispose() {
    for (final s in _shaders) {
      s.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final program = _program;
    final pos = widget.posMs;
    final active = widget.effects.where((e) => pos >= e.startMs && pos < e.endMs && e.amount > 0).toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    if (program == null || active.isEmpty) return widget.child;
    while (_shaders.length < active.length) {
      _shaders.add(program.fragmentShader());
    }
    var child = widget.child;
    for (var i = 0; i < active.length; i++) {
      final e = active[i];
      final def = StudioEffects.byId(e.effectId);
      if (def == null) continue;
      final dur = (e.endMs - e.startMs).clamp(1, 1 << 31);
      final shader = _shaders[i]
        ..setFloat(2, def.type.toDouble())
        ..setFloat(3, e.amount)
        ..setFloat(4, (pos - e.startMs) / 1000)
        ..setFloat(5, ((pos - e.startMs) / dur).clamp(0.0, 1.0));
      child = ImageFiltered(imageFilter: ui.ImageFilter.shader(shader), child: child);
    }
    return child;
  }
}
