import 'dart:ui';

// ─────────────────────────────────────────────────────────────────────────────
// Projective math for wall tiles (SPEC §2). A flat tile of `size` with its
// origin at the top-left is mapped onto four wall corners (TL, TR, BR, BL) by
// a CSS-style `matrix3d` (16 values, column-major — the same order as
// `Matrix4.fromList`). The math is Heckbert's unit-square → quad mapping,
// copied from v1 (`lib/social_hub/live/studio/live_studio_geometry.dart`).
// ─────────────────────────────────────────────────────────────────────────────

/// Computes the column-major `matrix3d` mapping an element of [size] (origin
/// top-left) onto [corners] (TL, TR, BR, BL).
List<double> homographyFromQuad(Size size, List<Offset> corners) {
  assert(corners.length == 4, 'Expected 4 corners: TL, TR, BR, BL');
  final p0 = corners[0], p1 = corners[1], p2 = corners[2], p3 = corners[3];

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

  final w = size.width, ht = size.height;
  return <double>[
    a / w, b / w, 0, g / w, //
    c / ht, d / ht, 0, h / ht, //
    0, 0, 1, 0, //
    p0.dx, p0.dy, 0, 1,
  ];
}

/// Projects a tile-space point through a column-major `matrix3d` (z = 0).
Offset projectPoint(List<double> m, Offset p) {
  final w = m[3] * p.dx + m[7] * p.dy + m[15];
  return Offset(
    (m[0] * p.dx + m[4] * p.dy + m[12]) / w,
    (m[1] * p.dx + m[5] * p.dy + m[13]) / w,
  );
}

/// The four projected corners (TL, TR, BR, BL) of a tile of [size].
List<Offset> projectTile(List<double> m, Size size) => [
      projectPoint(m, Offset.zero),
      projectPoint(m, Offset(size.width, 0)),
      projectPoint(m, Offset(size.width, size.height)),
      projectPoint(m, Offset(0, size.height)),
    ];

/// Bounds of a polygon.
Rect polygonBounds(List<Offset> pts) {
  var l = double.infinity, t = double.infinity;
  var r = double.negativeInfinity, b = double.negativeInfinity;
  for (final p in pts) {
    if (p.dx < l) l = p.dx;
    if (p.dy < t) t = p.dy;
    if (p.dx > r) r = p.dx;
    if (p.dy > b) b = p.dy;
  }
  return Rect.fromLTRB(l, t, r, b);
}

/// `m · translate(tx, ty) · scale(sx, sy)` for a column-major matrix3d. Used
/// for the wall glow behind a tile (SPEC §1.3) and for expand buttons.
List<double> matrixTranslateScale(List<double> m, double tx, double ty,
    [double sx = 1, double sy = 1]) {
  // Columns of m: c0 = m[0..3], c1 = m[4..7], c2 = m[8..11], c3 = m[12..15].
  return <double>[
    m[0] * sx, m[1] * sx, m[2] * sx, m[3] * sx, //
    m[4] * sy, m[5] * sy, m[6] * sy, m[7] * sy, //
    m[8], m[9], m[10], m[11], //
    m[0] * tx + m[4] * ty + m[12],
    m[1] * tx + m[5] * ty + m[13],
    m[2] * tx + m[6] * ty + m[14],
    m[3] * tx + m[7] * ty + m[15],
  ];
}

/// Element-wise linear interpolation of two matrices (S/M/L tween).
List<double> lerpMatrix(List<double> a, List<double> b, double t) =>
    List<double>.generate(16, (i) => a[i] + (b[i] - a[i]) * t, growable: false);
