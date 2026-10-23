import 'package:flutter/widgets.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// LIVE STUDIO GEOMETRY — the ONLY place studio-image geometry lives.
///
/// All values are in the studio image's native pixel space (the "world").
/// To swap the studio photo: replace [kStudioGeometry.imageAsset] and
/// [imageSize], then re-measure the wall quads. Each slot can be expressed as
/// a raw CSS-style `matrix3d` (column-major, identical to `Matrix4.fromList`)
/// or as four corner points via [WallSlot.fromQuad], which runs
/// [homographyFromQuad] for you.
/// ─────────────────────────────────────────────────────────────────────────────

/// A wall-mounted video window: a flat element of [nativeSize] placed at
/// world (0,0) and projected onto the wall by [matrix] (origin top-left).
class WallSlot {
  final String id;
  final Size nativeSize;
  final List<double> matrix3d; // 16 values, column-major (CSS matrix3d order)
  final bool portrait;

  const WallSlot({
    required this.id,
    required this.nativeSize,
    required this.matrix3d,
    this.portrait = false,
  });

  /// Build a slot from its four wall corners (TL, TR, BR, BL) in world px.
  factory WallSlot.fromQuad({
    required String id,
    required Size nativeSize,
    required List<Offset> corners,
    bool portrait = false,
  }) =>
      WallSlot(
        id: id,
        nativeSize: nativeSize,
        matrix3d: homographyFromQuad(nativeSize, corners),
        portrait: portrait,
      );

  Matrix4 get transform => Matrix4.fromList(matrix3d);

  /// Projects a native-space point onto the world (useful for anchoring).
  Offset project(Offset p) {
    final m = matrix3d;
    final w = m[3] * p.dx + m[7] * p.dy + m[15];
    return Offset(
      (m[0] * p.dx + m[4] * p.dy + m[12]) / w,
      (m[1] * p.dx + m[5] * p.dy + m[13]) / w,
    );
  }
}

/// The curved LED wall used as the center stage.
///
/// Shape (SVG, local to [rect]):
/// `M0 0 Q{w/2} {topSag} {w} 0 L{w} {bottomEdgeY} Q{w/2} {bottomControlY} 0 {bottomEdgeY} Z`
class CurvedStage {
  final Rect rect;
  final double topSag;
  final double bottomEdgeY;
  final double bottomControlY;
  final double strokeWidth;

  const CurvedStage({
    required this.rect,
    required this.topSag,
    required this.bottomEdgeY,
    required this.bottomControlY,
    this.strokeWidth = 3,
  });

  /// Clip path in the stage box's local coordinates.
  Path localPath() {
    final w = rect.width;
    return Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(w / 2, topSag, w, 0)
      ..lineTo(w, bottomEdgeY)
      ..quadraticBezierTo(w / 2, bottomControlY, 0, bottomEdgeY)
      ..close();
  }

  String get svgPath {
    final w = rect.width;
    String n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    return 'M0 0 Q${n(w / 2)} ${n(topSag)} ${n(w)} 0 L${n(w)} ${n(bottomEdgeY)} '
        'Q${n(w / 2)} ${n(bottomControlY)} 0 ${n(bottomEdgeY)} Z';
  }
}

/// The glowing presentation stand on the round stage floor.
class PresentationStand {
  final Offset center;
  final Size size;
  const PresentationStand({required this.center, required this.size});
}

class StudioLayoutGeometry {
  final CurvedStage stage;
  final List<WallSlot> slots;
  const StudioLayoutGeometry({required this.stage, required this.slots});
}

class StudioGeometry {
  final String imageAsset;
  final Size imageSize;

  /// Image x that sits at the horizontal screen center on phones.
  final double phoneFocusX;

  /// Phone world scale at the reference width, and that width.
  final double phoneScale;
  final double phoneReferenceWidth;
  final double phoneTop;

  final StudioLayoutGeometry landscape;
  final StudioLayoutGeometry phone;
  final PresentationStand stand;

  const StudioGeometry({
    required this.imageAsset,
    required this.imageSize,
    required this.phoneFocusX,
    required this.phoneScale,
    required this.phoneReferenceWidth,
    required this.phoneTop,
    required this.landscape,
    required this.phone,
    required this.stand,
  });
}

/// Breakpoint between the phone and landscape layouts.
const double kStudioLandscapeMinWidth = 768;

const StudioGeometry kStudioGeometry = StudioGeometry(
  imageAsset: 'assets/images/live_studio_1376.jpg',
  imageSize: Size(1376, 768),
  phoneFocusX: 688,
  phoneScale: 0.66,
  phoneReferenceWidth: 390,
  phoneTop: 30,
  stand: PresentationStand(center: Offset(688, 556), size: Size(280, 54)),

  // ── LANDSCAPE: center stage + 4 gallery tiles + 2 portrait glass panels ──
  landscape: StudioLayoutGeometry(
    stage: CurvedStage(
      rect: Rect.fromLTWH(413, 206, 547, 286),
      topSag: 78,
      bottomEdgeY: 266,
      bottomControlY: 306,
    ),
    slots: [
      // Gallery tiles (upper glass), native 160×100. Fill order L1, L2, R2, R1.
      WallSlot(id: 'L1', nativeSize: Size(160, 100), matrix3d: [
        0.804471, 0.0346266, 0, -0.000358206, 0, 0.778229, 0, 0, //
        0, 0, 1, 0, 24, 162.743, 0, 1,
      ]),
      WallSlot(id: 'R1', nativeSize: Size(160, 100), matrix3d: [
        1.37624, -0.0367318, 0, 0.000379984, 0, 0.825543, 0, 0, //
        0, 0, 1, 0, 1214, 178.514, 0, 1,
      ]),
      WallSlot(id: 'L2', nativeSize: Size(160, 100), matrix3d: [
        0.795596, 0.0342446, 0, -0.000354254, 0, 0.833086, 0, 0, //
        0, 0, 1, 0, 184, 181.029, 0, 1,
      ]),
      WallSlot(id: 'R2', nativeSize: Size(160, 100), matrix3d: [
        1.36014, -0.0363022, 0, 0.00037554, 0, 0.883143, 0, 0, //
        0, 0, 1, 0, 1046, 197.714, 0, 1,
      ]),
      // Lower glass panels, portrait for mobile guests, native 80×180.
      WallSlot(id: 'LP', nativeSize: Size(80, 180), portrait: true, matrix3d: [
        0.967241, 0.183621, 0, 0.000431034, 0, 0.833333, 0, 0, //
        0, 0, 1, 0, 264, 336, 0, 1,
      ]),
      WallSlot(id: 'RP', nativeSize: Size(80, 180), portrait: true, matrix3d: [
        0.361667, -0.1775, 0, -0.000416667, 0, 0.805556, 0, 0, //
        0, 0, 1, 0, 1046, 339, 0, 1,
      ]),
    ],
  ),

  // ── PHONE: top band of the LED wall + 4 tiles on the lower curved band ──
  phone: StudioLayoutGeometry(
    stage: CurvedStage(
      rect: Rect.fromLTWH(413, 206, 547, 138),
      topSag: 78,
      bottomEdgeY: 104,
      bottomControlY: 138,
    ),
    slots: [
      WallSlot(id: 'P1', nativeSize: Size(140, 124), matrix3d: [
        0.710467, -0.0745638, 0, -0.000360212, 0, 0.946698, 0, 0, //
        0, 0, 1, 0, 419, 350.477, 0, 1,
      ]),
      WallSlot(id: 'P2', nativeSize: Size(140, 124), matrix3d: [
        0.846694, -0.0247787, 0, -0.000119704, 0, 0.999094, 0, 0, //
        0, 0, 1, 0, 554, 358.418, 0, 1,
      ]),
      WallSlot(id: 'P3', nativeSize: Size(140, 124), matrix3d: [
        1.03317, 0.0263417, 0, 0.000127255, 0, 1.0161, 0, 0, //
        0, 0, 1, 0, 692, 360.996, 0, 1,
      ]),
      WallSlot(id: 'P4', nativeSize: Size(140, 124), matrix3d: [
        1.24166, 0.0772326, 0, 0.000373104, 0, 0.996148, 0, 0, //
        0, 0, 1, 0, 830, 357.972, 0, 1,
      ]),
    ],
  ),
);

/// Computes the projective transform (CSS `matrix3d`, column-major) that maps
/// an element of [size] with origin at its top-left onto [corners]
/// (TL, TR, BR, BL) in world space.
List<double> homographyFromQuad(Size size, List<Offset> corners) {
  assert(corners.length == 4, 'Expected 4 corners: TL, TR, BR, BL');
  final p0 = corners[0], p1 = corners[1], p2 = corners[2], p3 = corners[3];

  // Unit square → quad (Heckbert).
  final dx1 = p1.dx - p2.dx, dx2 = p3.dx - p2.dx;
  final dy1 = p1.dy - p2.dy, dy2 = p3.dy - p2.dy;
  final sx = p0.dx - p1.dx + p2.dx - p3.dx;
  final sy = p0.dy - p1.dy + p2.dy - p3.dy;

  double g = 0, h = 0;
  if (sx.abs() > 1e-9 || sy.abs() > 1e-9) {
    final den = dx1 * dy2 - dx2 * dy1;
    g = (sx * dy2 - dx2 * sy) / den;
    h = (dx1 * sy - sx * dy1) / den;
  }
  final a = p1.dx - p0.dx + g * p1.dx;
  final b = p1.dy - p0.dy + g * p1.dy;
  final c = p3.dx - p0.dx + h * p3.dx;
  final d = p3.dy - p0.dy + h * p3.dy;

  // Pre-scale so the element's native size maps onto the unit square.
  final w = size.width, ht = size.height;
  return [
    a / w, b / w, 0, g / w, //
    c / ht, d / ht, 0, h / ht, //
    0, 0, 1, 0, //
    p0.dx, p0.dy, 0, 1,
  ];
}

/// How the 1376×768 world is placed on screen for a given viewport.
class StudioWorldPlacement {
  final double scale;
  final Offset offset;
  final bool isLandscape;

  const StudioWorldPlacement({
    required this.scale,
    required this.offset,
    required this.isLandscape,
  });

  factory StudioWorldPlacement.forViewport(Size viewport,
      {StudioGeometry geometry = kStudioGeometry}) {
    final img = geometry.imageSize;
    if (viewport.width >= kStudioLandscapeMinWidth) {
      final s = viewport.height / img.height;
      return StudioWorldPlacement(
        scale: s,
        offset: Offset((viewport.width - img.width * s) / 2, 0),
        isLandscape: true,
      );
    }
    // Phone: 0.66 at 390px wide, scaled proportionally for other widths.
    final s = geometry.phoneScale * viewport.width / geometry.phoneReferenceWidth;
    return StudioWorldPlacement(
      scale: s,
      offset: Offset(viewport.width / 2 - geometry.phoneFocusX * s, geometry.phoneTop),
      isLandscape: false,
    );
  }

  StudioLayoutGeometry layoutOf(StudioGeometry g) => isLandscape ? g.landscape : g.phone;

  Offset worldToScreen(Offset p) => offset + p * scale;
}
