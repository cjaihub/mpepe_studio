import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/social_hub/live/studio_v2/geometry/geometry.dart';

/// Pixel diff of a rendered stage against a reference PNG, restricted to the
/// stage regions (inside the host clip path and inside each projected wall
/// tile) with text, icons, the table and the comment box masked out.
class StageDiffResult {
  StageDiffResult(this.label);
  final String label;
  int hostPixels = 0, hostDiff = 0, tilePixels = 0, tileDiff = 0;
  double hostDelta = 0, tileDelta = 0;

  double get hostPct => hostPixels == 0 ? 0 : 100 * hostDiff / hostPixels;
  double get tilePct => tilePixels == 0 ? 0 : 100 * tileDiff / tilePixels;
  double get totalPct =>
      hostPixels + tilePixels == 0 ? 0 : 100 * (hostDiff + tileDiff) / (hostPixels + tilePixels);

  @override
  String toString() => '$label: host ${hostPct.toStringAsFixed(2)}% '
      '(${hostPixels}px, mean Δ ${(hostDelta / (hostPixels == 0 ? 1 : hostPixels)).toStringAsFixed(1)}) · '
      'tiles ${tilePct.toStringAsFixed(2)}% '
      '(${tilePixels}px, mean Δ ${(tileDelta / (tilePixels == 0 ? 1 : tilePixels)).toStringAsFixed(1)}) · '
      'total ${totalPct.toStringAsFixed(2)}%';
}

/// Inverse of the 2D projective part of a column-major matrix3d.
List<double> _inverse3(List<double> m) {
  final a = m[0], b = m[4], c = m[12];
  final d = m[1], e = m[5], f = m[13];
  final g = m[3], h = m[7], i = m[15];
  final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
  return [
    (e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det, //
    (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det, //
    (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det,
  ];
}

Offset _apply3(List<double> n, Offset p) {
  final w = n[6] * p.dx + n[7] * p.dy + n[8];
  return Offset((n[0] * p.dx + n[1] * p.dy + n[2]) / w, (n[3] * p.dx + n[4] * p.dy + n[5]) / w);
}

StageDiffResult diffStage({
  required String label,
  required Uint8List renderedRgba,
  required int width,
  required int height,
  required String referencePath,
  required StudioDef studio,
  required StudioOrientation orientation,
  required GuestSize preset,
  required Size viewport,
  double pixelRatio = 2,
  int threshold = 32,
}) {
  final ref = img.decodePng(File(referencePath).readAsBytesSync())!;
  assert(ref.width == width && ref.height == height, 'reference ${ref.width}×${ref.height} vs $width×$height');
  final g = studio.of(orientation);
  final cam = studio.camera(orientation, viewport);
  final phone = orientation == StudioOrientation.phone;
  final host = g.host;
  final clip = host.clipPath;

  // Host masks (screen-local px): labels, LIVE pill, expand button.
  final hs = host.rect.size;
  final hostMasks = <Rect>[
    if (host.labels != null) Rect.fromLTWH(host.labels!.dx, host.labels!.dy, 340, 76) else Rect.fromLTWH(10, hs.height - 92, hs.width - 20, 82),
    if (host.livePill != null) Rect.fromLTWH(host.livePill!.dx - 2, host.livePill!.dy - 2, 74, 24) else Rect.fromLTWH(hs.width - 104, 18, 92, 34),
    Rect.fromLTWH((host.expandButton?.dx ?? 16) - 2, (host.expandButton?.dy ?? 22) - 2, (host.expandSize ?? 40) + 4, (host.expandSize ?? 40) + 4),
  ];
  final uiMasks = <Rect>[
    cam.artboardRectToUi(g.table).inflate(24), // table content + its shadow/expand
    studio.commentsRect(orientation, preset, viewport),
  ];

  final slots = <(SlotGeometry, List<double>)>[];
  for (var i = 0; i < g.slotOrder.length; i++) {
    final s = g.slotAt(i, preset);
    if (s != null) slots.add((s, _inverse3(s.matrix3d)));
  }
  final plate = phone ? 34.0 : 20.0;

  final out = StageDiffResult(label);
  final rgba = ref.convert(numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final ui = Offset((x + 0.5) / pixelRatio, (y + 0.5) / pixelRatio);
      if (uiMasks.any((r) => r.contains(ui))) continue;
      final w = cam.uiToWorld(ui);
      var inTile = false;
      var masked = false;
      for (final (s, inv) in slots) {
        final t = _apply3(inv, w);
        if (t.dx >= 0 && t.dy >= 0 && t.dx <= s.tile.width && t.dy <= s.tile.height) {
          inTile = true;
          final exp = Rect.fromLTWH(s.expandOffset.dx - 2, s.expandOffset.dy - 2, s.expandSize + 4, s.expandSize + 4);
          masked = t.dy > s.tile.height - plate || exp.contains(t);
          break;
        }
      }
      var inHost = false;
      if (!inTile) {
        final local = w - host.rect.topLeft;
        if (clip.contains(local)) {
          inHost = true;
          masked = hostMasks.any((r) => r.contains(local));
        }
      }
      if ((!inTile && !inHost) || masked) continue;

      final o = (y * width + x) * 4;
      final p = rgba.getPixel(x, y);
      final dr = (renderedRgba[o] - p.r.toInt()).abs();
      final dg = (renderedRgba[o + 1] - p.g.toInt()).abs();
      final db = (renderedRgba[o + 2] - p.b.toInt()).abs();
      final d = dr > dg ? (dr > db ? dr : db) : (dg > db ? dg : db);
      if (inTile) {
        out.tilePixels++;
        out.tileDelta += d;
        if (d > threshold) out.tileDiff++;
      } else {
        out.hostPixels++;
        out.hostDelta += d;
        if (d > threshold) out.hostDiff++;
      }
    }
  }
  return out;
}
