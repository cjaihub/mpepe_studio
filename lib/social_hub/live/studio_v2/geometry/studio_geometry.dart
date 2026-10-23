import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import 'homography.dart';
import 'svg_path.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Typed loader for assets/live_studio/studio-geometry.json (SPEC §2).
// Studios are keyed by studioId; a new studio is a new JSON entry, no code.
// World space = background photo pixels; UI space = artboard pixels.
// ─────────────────────────────────────────────────────────────────────────────

const String kStudioGeometryAsset = 'assets/live_studio/studio-geometry.json';

enum StudioOrientation { landscape, phone }

double _d(Object? v, [double fallback = 0]) => v is num ? v.toDouble() : fallback;
Map<String, dynamic> _m(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
List<double> _nums(Object? v) =>
    v is List ? v.whereType<num>().map((e) => e.toDouble()).toList() : const <double>[];

Size _size(Object? v, [Size fallback = Size.zero]) {
  final n = _nums(v);
  return n.length >= 2 ? Size(n[0], n[1]) : fallback;
}

Rect _rect(Object? v) {
  final n = _nums(v);
  return n.length >= 4 ? Rect.fromLTWH(n[0], n[1], n[2], n[3]) : Rect.zero;
}

Offset _offset(Object? v, [Offset fallback = Offset.zero]) {
  final n = _nums(v);
  return n.length >= 2 ? Offset(n[0], n[1]) : fallback;
}

/// The root of the geometry file.
class StudioGeometry {
  final Map<String, StudioDef> studios;
  const StudioGeometry(this.studios);

  factory StudioGeometry.fromJson(Map<String, dynamic> j) {
    final raw = _m(j['studios']);
    return StudioGeometry({
      for (final e in raw.entries) e.key: StudioDef.fromJson(e.key, _m(e.value)),
    });
  }

  static StudioGeometry parse(String source) =>
      StudioGeometry.fromJson(Map<String, dynamic>.from(jsonDecode(source) as Map));

  static Future<StudioGeometry> load([AssetBundle? bundle]) async =>
      parse(await (bundle ?? rootBundle).loadString(kStudioGeometryAsset));

  /// The studio for [studioId], or the first studio when it is unknown.
  StudioDef studio(String studioId) => studios[studioId] ?? studios.values.first;
}

/// Loaded once per app; the stage waits on it.
final studioGeometryProvider = FutureProvider<StudioGeometry>((ref) => StudioGeometry.load());

class StudioBackground {
  final String asset;
  final Size size;
  final String alt;
  const StudioBackground({required this.asset, required this.size, required this.alt});
  factory StudioBackground.fromJson(Map<String, dynamic> j) => StudioBackground(
        asset: j['asset'] as String? ?? '',
        size: Size(_d(j['width'], 1376), _d(j['height'], 768)),
        alt: j['alt'] as String? ?? '',
      );
}

class StudioDef {
  final String id;
  final String label;
  final StudioBackground background;
  final OrientationGeometry landscape;
  final OrientationGeometry phone;

  const StudioDef({
    required this.id,
    required this.label,
    required this.background,
    required this.landscape,
    required this.phone,
  });

  factory StudioDef.fromJson(String id, Map<String, dynamic> j) => StudioDef(
        id: id,
        label: j['label'] as String? ?? id,
        background: StudioBackground.fromJson(_m(j['background'])),
        landscape: OrientationGeometry.fromJson(StudioOrientation.landscape, _m(j['landscape'])),
        phone: OrientationGeometry.fromJson(StudioOrientation.phone, _m(j['phone'])),
      );

  OrientationGeometry of(StudioOrientation o) =>
      o == StudioOrientation.phone ? phone : landscape;

  StudioCamera camera(StudioOrientation o, Size viewport) =>
      StudioCamera.forViewport(of(o), background.size, viewport);

  /// The comment box in viewport (UI) pixels. See [commentsRectFor].
  Rect commentsRect(StudioOrientation o, GuestSize preset, Size viewport) =>
      commentsRectFor(this, o, preset, viewport);
}

class CameraSpec {
  final double scale;
  final Offset translate;
  final String fit; // 'height' | 'crop'
  const CameraSpec({required this.scale, required this.translate, required this.fit});
  factory CameraSpec.fromJson(Map<String, dynamic> j) => CameraSpec(
        scale: _d(j['scale'], 1),
        translate: _offset(j['translate']),
        fit: j['fit'] as String? ?? 'height',
      );
}

class HostGeometry {
  /// World-space screen rect.
  final Rect rect;
  final String clipPathData;
  final String rimPathData;

  /// Avatar box inside the screen: left, bottom, width, height.
  final Rect avatarBox;
  final double avatarBottom;
  final Offset? labels;
  final Offset? livePill;
  final Offset? expandButton;
  final double? expandSize;
  final Rect? floorGlow;

  HostGeometry({
    required this.rect,
    required this.clipPathData,
    required this.rimPathData,
    required this.avatarBox,
    required this.avatarBottom,
    this.labels,
    this.livePill,
    this.expandButton,
    this.expandSize,
    this.floorGlow,
  });

  factory HostGeometry.fromJson(Map<String, dynamic> j) {
    final ab = _m(j['avatarBox']);
    final lb = _m(j['labels']);
    final lp = _m(j['livePill']);
    final ex = _m(j['expandButton']);
    final fg = _m(j['floorGlow']);
    return HostGeometry(
      rect: _rect(j['rect']),
      clipPathData: j['clipPath'] as String? ?? '',
      rimPathData: j['rimPath'] as String? ?? (j['clipPath'] as String? ?? ''),
      avatarBox: Rect.fromLTWH(_d(ab['left']), 0, _d(ab['width']), _d(ab['height'])),
      avatarBottom: _d(ab['bottom']),
      labels: lb.isEmpty ? null : Offset(_d(lb['left']), _d(lb['top'])),
      livePill: lp.isEmpty ? null : Offset(_d(lp['left']), _d(lp['top'])),
      expandButton: ex.isEmpty ? null : Offset(_d(ex['left']), _d(ex['top'])),
      expandSize: ex.isEmpty ? null : _d(ex['size']),
      floorGlow: fg.isEmpty ? null : _rect(fg['rect']),
    );
  }

  Path? _clip, _rim;

  /// Clip path in the screen's local coordinates (origin = rect.topLeft).
  Path get clipPath => _clip ??= parseSvgPath(clipPathData);
  Path get rimPath => _rim ??= parseSvgPath(rimPathData);
}

class SlotGeometry {
  final String id;
  final Size tile;
  final List<Offset> quad;
  final List<double> matrix3d;
  final Offset expandOffset;
  final double expandSize;

  const SlotGeometry({
    required this.id,
    required this.tile,
    required this.quad,
    required this.matrix3d,
    required this.expandOffset,
    required this.expandSize,
  });

  bool get portrait => tile.height > tile.width;

  /// The matrix computed from [quad] (the JSON matrix is kept as reference).
  List<double> get computedMatrix => homographyFromQuad(tile, quad);

  /// World-space projected corners.
  List<Offset> get projected => projectTile(matrix3d, tile);
}

class GlowSpec {
  final Offset translateFactor;
  final Offset scale;
  final double blur;
  final double opacity;
  final double radius;
  const GlowSpec({
    this.translateFactor = const Offset(-0.12, -0.1),
    this.scale = const Offset(1.24, 1.2),
    this.blur = 16,
    this.opacity = 0.32,
    this.radius = 18,
  });
  factory GlowSpec.fromJson(Map<String, dynamic> j) => GlowSpec(
        translateFactor: _offset(j['translateFactor'], const Offset(-0.12, -0.1)),
        scale: _offset(j['scale'], const Offset(1.24, 1.2)),
        blur: _d(j['blur'], 16),
        opacity: _d(j['opacity'], 0.32),
        radius: _d(j['radius'], 18),
      );
}

class StandSpec {
  final Rect beam, disc, ring;
  const StandSpec({required this.beam, required this.disc, required this.ring});
  factory StandSpec.fromJson(Map<String, dynamic> j) => StandSpec(
        beam: _rect(_m(j['beam'])['rect']),
        disc: _rect(_m(j['disc'])['rect']),
        ring: _rect(_m(j['ring'])['rect']),
      );
}

/// Everything for one orientation.
class OrientationGeometry {
  final StudioOrientation orientation;
  final Size artboard;
  final CameraSpec camera;
  final HostGeometry host;
  final List<String> slotOrder;

  /// Landscape: one map per preset. Phone: the single slot set is stored
  /// under every preset key so callers need no special case.
  final Map<GuestSize, Map<String, SlotGeometry>> presets;
  final GuestSize defaultPreset;
  final GlowSpec glow;
  final double tileRadius;
  final double tileFrameFactor;
  final Rect table;
  final double tableRadius;
  final StandSpec stand;
  final Rect comments;
  final double commentsFadeStop;
  final Rect popoutDefault;
  final Size popoutMin;

  const OrientationGeometry({
    required this.orientation,
    required this.artboard,
    required this.camera,
    required this.host,
    required this.slotOrder,
    required this.presets,
    required this.defaultPreset,
    required this.glow,
    required this.tileRadius,
    required this.tileFrameFactor,
    required this.table,
    required this.tableRadius,
    required this.stand,
    required this.comments,
    required this.commentsFadeStop,
    required this.popoutDefault,
    required this.popoutMin,
  });

  bool get isPhone => orientation == StudioOrientation.phone;

  factory OrientationGeometry.fromJson(StudioOrientation o, Map<String, dynamic> j) {
    final order = (j['guestSlotOrder'] as List? ?? const []).whereType<String>().toList();

    Offset wideOff = const Offset(134, 6), portraitOff = const Offset(54, 6);
    double expandSize = 20;
    final eo = j['expandButtonOffset'];
    if (eo is Map) {
      final m = Map<String, dynamic>.from(eo);
      wideOff = _offset(m['wide'], wideOff);
      portraitOff = _offset(m['portrait'], portraitOff);
      expandSize = _d(m['size'], expandSize);
    } else if (eo is List) {
      wideOff = portraitOff = _offset(eo, wideOff);
      expandSize = _d(j['expandButtonSize'], 30);
    }

    Map<String, SlotGeometry> slots(Map<String, dynamic> raw) => {
          for (final e in raw.entries)
            e.key: () {
              final s = _m(e.value);
              final tile = _size(s['tile']);
              final quad = (s['quad'] as List? ?? const []).map((p) => _offset(p)).toList();
              final m = _nums(s['matrix3d']);
              return SlotGeometry(
                id: e.key,
                tile: tile,
                quad: quad,
                matrix3d: m.length == 16 ? m : homographyFromQuad(tile, quad),
                expandOffset: tile.height > tile.width ? portraitOff : wideOff,
                expandSize: expandSize,
              );
            }(),
        };

    final presets = <GuestSize, Map<String, SlotGeometry>>{};
    final gp = _m(j['guestPresets']);
    if (gp.isNotEmpty) {
      for (final g in GuestSize.values) {
        if (gp[g.wire] != null) presets[g] = slots(_m(gp[g.wire]));
      }
    } else {
      final single = slots(_m(j['guestSlots']));
      for (final g in GuestSize.values) {
        presets[g] = single;
      }
    }

    final table = _m(j['table']);
    final comments = _m(j['comments']);
    final pop = _m(j['popout']);
    return OrientationGeometry(
      orientation: o,
      artboard: _size(j['artboard'], o == StudioOrientation.phone ? const Size(390, 844) : const Size(1440, 810)),
      camera: CameraSpec.fromJson(_m(j['camera'])),
      host: HostGeometry.fromJson(_m(j['host'])),
      slotOrder: order,
      presets: presets,
      defaultPreset: GuestSize.fromWire(j['defaultPreset']),
      glow: GlowSpec.fromJson(_m(j['glow'])),
      tileRadius: _d(j['tileRadius'], o == StudioOrientation.phone ? 14 : 10),
      tileFrameFactor: _d(j['tileFrameFactor'], 1),
      table: _rect(table['rect']),
      tableRadius: _d(table['radius'], 14),
      stand: StandSpec.fromJson(_m(j['stand'])),
      comments: _rect(comments['rect']),
      commentsFadeStop: _d(comments['fadeStop'], 0.38),
      popoutDefault: _rect(pop['default']),
      popoutMin: _size(pop['min'], const Size(160, 120)),
    );
  }

  /// Slots for [preset] (phone ignores the preset), keyed by slot id.
  Map<String, SlotGeometry> slotsFor(GuestSize preset) =>
      presets[preset] ?? presets[defaultPreset] ?? presets.values.first;

  /// Slot for wall index [i] (StageLayout.wall order), or null if this
  /// orientation has fewer slots.
  SlotGeometry? slotAt(int i, GuestSize preset) =>
      i < slotOrder.length ? slotsFor(preset)[slotOrder[i]] : null;

  /// Tile border width for a settings frameWidth (phone: round(fw·1.5, 0.1)).
  double tileBorder(int frameWidth) => (frameWidth * tileFrameFactor * 10).round() / 10;

  /// Host-screen frame stroke (SPEC §2): 2·fw / cameraScale, to 0.1.
  double hostStroke(int frameWidth) => (2 * frameWidth / camera.scale * 10).round() / 10;

  /// Pink rim under the frame stroke: 2·fw / cameraScale + 4, to 0.1.
  double hostRim(int frameWidth) => ((2 * frameWidth / camera.scale + 4) * 10).round() / 10;
}

/// World → UI (viewport) and artboard → UI transforms (SPEC §2 "Camera").
///
/// Landscape fits the photo height and centers it horizontally; phone keeps
/// the prototype crop (0.66, translate (-259, 30) at 390 wide) scaled by
/// viewportW / 390. UI-space elements (table, stand, comments, pop-out) are
/// authored in artboard pixels and map through [artboardToUi].
class StudioCamera {
  /// World → UI.
  final double scale;
  final Offset translate;

  /// Artboard → UI.
  final double uiScale;
  final Offset uiTranslate;
  final Size viewport;

  const StudioCamera({
    required this.scale,
    required this.translate,
    required this.uiScale,
    required this.uiTranslate,
    required this.viewport,
  });

  factory StudioCamera.forViewport(OrientationGeometry g, Size world, Size viewport) {
    if (g.isPhone) {
      final k = viewport.width / g.artboard.width;
      return StudioCamera(
        scale: g.camera.scale * k,
        translate: g.camera.translate * k,
        uiScale: k,
        uiTranslate: Offset.zero,
        viewport: viewport,
      );
    }
    final s = viewport.height / world.height;
    final u = viewport.height / g.artboard.height;
    return StudioCamera(
      scale: s,
      translate: Offset((viewport.width - world.width * s) / 2, 0),
      uiScale: u,
      uiTranslate: Offset((viewport.width - g.artboard.width * u) / 2, 0),
      viewport: viewport,
    );
  }

  Offset worldToUi(Offset p) => p * scale + translate;
  Offset uiToWorld(Offset p) => (p - translate) / scale;
  Rect worldRectToUi(Rect r) => Rect.fromPoints(worldToUi(r.topLeft), worldToUi(r.bottomRight));
  List<Offset> worldPolyToUi(List<Offset> pts) => [for (final p in pts) worldToUi(p)];

  Offset artboardToUi(Offset p) => p * uiScale + uiTranslate;
  Offset uiToArtboard(Offset p) => (p - uiTranslate) / uiScale;
  Rect artboardRectToUi(Rect r) =>
      Rect.fromPoints(artboardToUi(r.topLeft), artboardToUi(r.bottomRight));

  /// The viewport expressed in artboard pixels (pop-out clamp bounds).
  Rect get viewportInArtboard =>
      Rect.fromPoints(uiToArtboard(Offset.zero), uiToArtboard(Offset(viewport.width, viewport.height)));

  /// Column-major world → UI matrix for a `Transform`.
  List<double> get worldMatrix => <double>[
        scale, 0, 0, 0, 0, scale, 0, 0, 0, 0, 1, 0, translate.dx, translate.dy, 0, 1, //
      ];
  List<double> get artboardMatrix => <double>[
        uiScale, 0, 0, 0, 0, uiScale, 0, 0, 0, 0, 1, 0, uiTranslate.dx, uiTranslate.dy, 0, 1, //
      ];
}

/// Screens the comment box must never cover, in UI pixels: the host clip
/// bounds, every projected wall tile of [preset] and the table.
List<Rect> stageScreensUi(StudioDef studio, StudioOrientation o, GuestSize preset, Size viewport) {
  final g = studio.of(o);
  final cam = studio.camera(o, viewport);
  final hostLocal = polygonBounds(svgPathPoints(g.host.clipPathData));
  return [
    cam.worldRectToUi(hostLocal.shift(g.host.rect.topLeft)),
    for (final s in g.slotsFor(preset).values) polygonBounds(cam.worldPolyToUi(s.projected)),
    cam.artboardRectToUi(g.table),
  ];
}

/// The comment box for [o]/[preset] at [viewport], in UI pixels.
///
/// Starts from the JSON rect (left-anchored to the viewport, scaled with the
/// artboard). Any screen whose horizontal span overlaps the box and whose
/// bottom reaches into it pushes the top down to `bottom + 4` (SPEC §2: at
/// preset L the projected LP bottom ≈ 534 → top ≈ 538, height ≈ 164). A screen
/// starting inside the box's vertical span to its right (the table on narrow
/// viewports) shrinks the right edge to `screen.left − 8`.
Rect commentsRectFor(StudioDef studio, StudioOrientation o, GuestSize preset, Size viewport) {
  final g = studio.of(o);
  final cam = studio.camera(o, viewport);
  final u = cam.uiScale;
  final c = g.comments;
  var left = c.left * u;
  var top = c.top * u + cam.uiTranslate.dy;
  var right = c.right * u;
  final bottom = c.bottom * u + cam.uiTranslate.dy;

  final screens = stageScreensUi(studio, o, preset, viewport);
  // Right edge first: the table (last) may start inside the box on narrow
  // viewports; the box then stops 8px before it.
  final table = screens.last;
  if (table.bottom > top && table.top < bottom && table.left > left && table.left < right + 8 * u) {
    right = table.left - 8 * u;
  }
  for (final s in screens) {
    final hOverlap = s.right > left && s.left < right;
    if (hOverlap && s.bottom > top && s.top < bottom) top = s.bottom + 4 * u;
  }
  if (top > bottom) top = bottom;
  return Rect.fromLTRB(left, top, right, bottom);
}
