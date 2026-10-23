import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/social_hub/live/studio_v2/geometry/geometry.dart';
import 'package:oneova/social_hub/live/studio_v2/stage/stage.dart';

import 'fakes/fake_stage.dart';
import 'support/stage_diff.dart';

// Goldens of the world layer (+ stand, fades and an empty table frame) at the
// artboard sizes, rendered at 2× like the reference PNGs, then a pixel diff
// against `docs/live-studio/reference exaclt/*` inside the stage regions only
// (text, icons, table and comments masked — fonts differ in tests).
//
// Regenerate: flutter test --update-goldens test/live_studio_v2/stage/stage_golden_test.dart

const _ref = 'docs/live-studio/reference exaclt';

class _Case {
  const _Case(this.name, this.orientation, this.settings, this.reference, this.size);
  final String name;
  final StudioOrientation orientation;
  final StudioSettings settings;
  final String reference;
  final Size size;
}

final _cases = [
  _Case('landscape_dark_L', StudioOrientation.landscape, const StudioSettings(guestSize: GuestSize.l),
      '$_ref/Live studio — landscape@2x.png', const Size(1440, 810)),
  _Case('landscape_light_M', StudioOrientation.landscape, StudioSettings.defaultsFor(StudioTheme.light),
      '$_ref/Live studio — landscape, light@2x.png', const Size(1440, 810)),
  _Case('phone_dark', StudioOrientation.phone, const StudioSettings(), '$_ref/Live studio — phone@2x.png',
      const Size(390, 844)),
  _Case('phone_light', StudioOrientation.phone, StudioSettings.defaultsFor(StudioTheme.light),
      '$_ref/Live studio — phone, light@2x.png', const Size(390, 844)),
];

final _results = <StageDiffResult>[];

void main() {
  for (final c in _cases) {
    testWidgets('golden + reference diff: ${c.name}', (t) async {
      t.view.physicalSize = c.size * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final key = GlobalKey();
      final members = fakeMembers();
      final studio = kTestGeometry.studio(c.settings.studioId);

      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(
            key: key,
            child: StudioStage(
              geometry: kTestGeometry,
              state: fakeState(c.settings),
              members: members,
              orientation: c.orientation,
              isSpeaking: speakingFrom(members),
            ),
          ),
        ),
      ));
      await t.runAsync(() async {
        final ctx = key.currentContext!;
        await precacheImage(AssetImage(studio.background.asset), ctx);
      });
      await t.pump();

      await expectLater(find.byKey(key), matchesGoldenFile('goldens/${c.name}.png'));

      final bytes = await t.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      final r = diffStage(
        label: c.name,
        renderedRgba: bytes!,
        width: (c.size.width * 2).round(),
        height: (c.size.height * 2).round(),
        referencePath: c.reference,
        studio: studio,
        orientation: c.orientation,
        preset: c.settings.guestSize,
        viewport: c.size,
      );
      _results.add(r);
      // ignore: avoid_print
      print('[stage diff] $r');
      expect(r.hostPixels, greaterThan(10000));
      expect(r.tilePixels, greaterThan(10000));
      // Regression guard, not the 2% acceptance gate (that one belongs to the
      // shell's full-screen goldens with chrome and real fonts).
      expect(r.totalPct, lessThan(35));
    });
  }

  tearDownAll(() {
    for (final r in _results) {
      // ignore: avoid_print
      print('[stage diff summary] $r');
    }
  });
}
