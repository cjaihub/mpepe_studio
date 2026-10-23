import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/social_hub/live/studio_v2/geometry/geometry.dart';

void main() {
  final geo = StudioGeometry.parse(File('assets/live_studio/studio-geometry.json').readAsStringSync());
  final studio = geo.studio('broadcast_curved_wall');

  Iterable<(String, SlotGeometry)> allSlots() sync* {
    for (final p in GuestSize.values) {
      for (final s in studio.landscape.slotsFor(p).values) {
        yield ('landscape/${p.wire}/${s.id}', s);
      }
    }
    for (final s in studio.phone.slotsFor(GuestSize.m).values) {
      yield ('phone/${s.id}', s);
    }
  }

  group('loader', () {
    test('reads studios, presets and anchors', () {
      expect(geo.studios.keys, contains('broadcast_curved_wall'));
      expect(studio.background.size, const Size(1376, 768));
      expect(studio.landscape.slotOrder, kLandscapeSlotOrder);
      expect(studio.phone.slotOrder, kPhoneSlotOrder);
      for (final p in GuestSize.values) {
        expect(studio.landscape.slotsFor(p).length, 6);
      }
      expect(studio.phone.slotsFor(GuestSize.l).length, 4);
      expect(studio.landscape.host.rect, const Rect.fromLTWH(413, 206, 547, 286));
      expect(studio.landscape.table, const Rect.fromLTWH(576, 450, 288, 162));
      expect(studio.phone.table, const Rect.fromLTWH(74, 378, 240, 135));
      expect(studio.landscape.popoutMin, const Size(240, 150));
      expect(studio.phone.popoutDefault, const Rect.fromLTWH(20, 120, 350, 240));
      expect(studio.phone.host.floorGlow, const Rect.fromLTWH(600, 522, 176, 10));
      expect(studio.landscape.slotsFor(GuestSize.m)['LP']!.expandOffset, const Offset(54, 6));
      expect(studio.landscape.slotsFor(GuestSize.m)['L1']!.expandOffset, const Offset(134, 6));
      expect(studio.phone.slotsFor(GuestSize.m)['PL1']!.expandOffset, const Offset(114, 6));
      expect(studio.phone.slotsFor(GuestSize.m)['PL1']!.expandSize, 30);
    });

    test('unknown studio id falls back; new studios need no code', () {
      expect(geo.studio('nope').id, 'broadcast_curved_wall');
      final extra = StudioGeometry.fromJson({
        'studios': {
          'tiny': {
            'background': {'asset': 'x.jpg', 'width': 100, 'height': 50},
            'landscape': {
              'artboard': [200, 100],
              'camera': {'scale': 2, 'translate': [0, 0]},
              'host': {'rect': [10, 10, 20, 20], 'clipPath': 'M0 0 L20 0 L20 20 Z'},
              'guestSlotOrder': ['A'],
              'guestPresets': {
                'm': {
                  'A': {
                    'tile': [10, 10],
                    'quad': [[0, 0], [10, 0], [10, 10], [0, 10]],
                  }
                }
              },
            },
            'phone': {},
          }
        }
      });
      final s = extra.studio('tiny');
      expect(s.landscape.slotsFor(GuestSize.l)['A']!.matrix3d[0], closeTo(1, 1e-9));
      expect(s.landscape.host.clipPath.getBounds(), const Rect.fromLTWH(0, 0, 20, 20));
    });

    test('frame formulas match the prototype', () {
      expect(studio.landscape.tileBorder(4), 4);
      expect(studio.phone.tileBorder(4), 6);
      expect(studio.phone.tileBorder(3), 4.5);
      expect(studio.landscape.hostStroke(4), 7.6); // round(2·4/1.0547, .1)
      expect(studio.landscape.hostRim(4), 11.6);
      expect(studio.phone.hostStroke(4), 12.1);
      expect(studio.phone.hostRim(4), 16.1);
    });
  });

  group('(a) homography reproduces the prototype matrix3d', () {
    for (final (name, s) in allSlots()) {
      test(name, () {
        final m = homographyFromQuad(s.tile, s.quad);
        for (var i = 0; i < 16; i++) {
          final want = s.matrix3d[i];
          // 1e-3, relative to magnitude: the JSON quads are rounded to 2
          // decimals while the prototype matrices used the unrounded corner,
          // so translation entries (≈160–360) differ by up to 0.005 (≤ 3e-4
          // relative). Every non-translation entry also passes 1e-3 absolute.
          expect((m[i] - want).abs(), lessThanOrEqualTo(1e-3 * (want.abs() > 1 ? want.abs() : 1)),
              reason: '$name m[$i] = ${m[i]} vs $want');
          if (i != 12 && i != 13) expect(m[i], closeTo(want, 1e-3), reason: '$name m[$i]');
        }
      });
    }
  });

  group('(b) projecting tile corners gives the quad', () {
    for (final (name, s) in allSlots()) {
      test(name, () {
        final computed = projectTile(homographyFromQuad(s.tile, s.quad), s.tile);
        final fromJson = projectTile(s.matrix3d, s.tile);
        for (var k = 0; k < 4; k++) {
          expect(computed[k].dx, closeTo(s.quad[k].dx, 1e-6));
          expect(computed[k].dy, closeTo(s.quad[k].dy, 1e-6));
          expect(fromJson[k].dx, closeTo(s.quad[k].dx, 0.02), reason: '$name corner $k');
          expect(fromJson[k].dy, closeTo(s.quad[k].dy, 0.02), reason: '$name corner $k');
        }
      });
    }

    test('matrixTranslateScale composes like CSS', () {
      final s = studio.landscape.slotsFor(GuestSize.m)['L1']!;
      final m = matrixTranslateScale(s.matrix3d, 134, 6);
      final p = projectPoint(m, Offset.zero);
      final q = projectPoint(s.matrix3d, const Offset(134, 6));
      expect(p.dx, closeTo(q.dx, 1e-9));
      expect(p.dy, closeTo(q.dy, 1e-9));
      final g = matrixTranslateScale(s.matrix3d, -19.2, -10, 1.24, 1.2);
      final a = projectPoint(g, const Offset(160, 100));
      final b = projectPoint(s.matrix3d, const Offset(-19.2 + 160 * 1.24, -10 + 100 * 1.2));
      expect(a.dx, closeTo(b.dx, 1e-9));
    });
  });

  group('(c) SVG path parser', () {
    test('landscape host clip bounds', () {
      final b = studio.landscape.host.clipPath.getBounds();
      expect(b.left, closeTo(0, 0.01));
      expect(b.top, closeTo(0, 0.01)); // Q control point 547,0
      expect(b.right, closeTo(547, 0.01));
      expect(b.bottom, closeTo(285.9, 0.15)); // bottom curve centre
      final pts = polygonBounds(svgPathPoints(studio.landscape.host.clipPathData));
      expect(pts, b);
    });

    test('phone host clip bounds', () {
      final b = studio.phone.host.clipPath.getBounds();
      expect(b.left, closeTo(0, 0.01));
      expect(b.right, closeTo(196, 0.01));
      expect(b.bottom, closeTo(279.9, 0.01));
      expect(b.top, lessThan(6));
    });

    test('shape: sagging top edge, curved corners, inside/outside', () {
      final p = studio.landscape.host.clipPath;
      expect(p.contains(const Offset(273, 45)), isTrue); // just under the sag
      expect(p.contains(const Offset(273, 30)), isFalse); // above the sag (39px)
      expect(p.contains(const Offset(1, 1)), isFalse); // rounded corner
      expect(p.contains(const Offset(20, 140)), isTrue);
    });

    test('subset: implicit L after M, Q, Z; rejects others', () {
      final p = parseSvgPath('M0 0 10 0 Q20 0 20 10 L0 10 Z');
      expect(p.getBounds(), const Rect.fromLTWH(0, 0, 20, 10));
      expect(() => parseSvgPath('M0 0 C1 1 2 2 3 3'), throwsFormatException);
      expect(() => parseSvgPath('0 0'), throwsFormatException);
    });
  });

  group('camera', () {
    test('landscape fits height and centers', () {
      final c = studio.camera(StudioOrientation.landscape, const Size(1440, 810));
      expect(c.scale, closeTo(1.0547, 1e-4));
      expect(c.translate.dx, closeTo(-5.6, 0.05));
      expect(c.uiScale, 1);
      final wide = studio.camera(StudioOrientation.landscape, const Size(2400, 1080));
      expect(wide.scale, closeTo(1080 / 768, 1e-9));
      expect(wide.worldToUi(const Offset(688, 0)).dx, closeTo(1200, 1e-9)); // world centre
    });

    test('phone keeps the prototype crop and scales by width', () {
      final c = studio.camera(StudioOrientation.phone, const Size(390, 844));
      expect(c.scale, 0.66);
      expect(c.translate, const Offset(-259, 30));
      final big = studio.camera(StudioOrientation.phone, const Size(430, 932));
      expect(big.scale, closeTo(0.66 * 430 / 390, 1e-9));
      final p = big.worldToUi(const Offset(688, 380));
      expect(big.uiToWorld(p).dx, closeTo(688, 1e-9));
    });
  });

  group('(d) comments never cover a screen', () {
    const viewports = {
      StudioOrientation.landscape: [Size(1440, 810), Size(1280, 800), Size(1180, 820), Size(2560, 1440), Size(1024, 768)],
      StudioOrientation.phone: [Size(390, 844), Size(375, 812), Size(430, 932), Size(360, 640)],
    };

    for (final o in StudioOrientation.values) {
      for (final v in viewports[o]!) {
        for (final p in o == StudioOrientation.phone ? [GuestSize.m] : GuestSize.values) {
          test('${o.name} ${v.width.toInt()}×${v.height.toInt()} preset ${p.wire}', () {
            final c = studio.commentsRect(o, p, v);
            expect(c.height, greaterThan(100 * v.height / (o == StudioOrientation.phone ? 844 : 810)));
            expect(c.width, greaterThan(150));
            for (final s in stageScreensUi(studio, o, p, v)) {
              expect(c.overlaps(s), isFalse, reason: 'comments $c overlaps $s');
            }
          });
        }
      }
    }

    test('SPEC §2 fix at preset L: top = projected LP bottom + 4', () {
      const v = Size(1440, 810);
      final cam = studio.camera(StudioOrientation.landscape, v);
      final lp = studio.landscape.slotsFor(GuestSize.l)['LP']!;
      final lpBottom = polygonBounds(cam.worldPolyToUi(lp.projected)).bottom;
      expect(lpBottom, closeTo(534, 0.6));
      final c = studio.commentsRect(StudioOrientation.landscape, GuestSize.l, v);
      expect(c.top, closeTo(lpBottom + 4, 1e-6));
      expect(c.height, closeTo(164, 0.6));
      // S and M keep the JSON rect.
      final m = studio.commentsRect(StudioOrientation.landscape, GuestSize.m, v);
      expect(m, const Rect.fromLTWH(24, 528, 420, 174));
      expect(studio.commentsRect(StudioOrientation.phone, GuestSize.m, const Size(390, 844)),
          const Rect.fromLTWH(12, 556, 272, 212));
    });
  });
}
