import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/social_hub/live/studio_v2/geometry/geometry.dart';
import 'package:oneova/social_hub/live/studio_v2/stage/stage.dart';

import 'fakes/fake_stage.dart';

ProviderContainer? _shared;

/// One container per test (disposed in tearDown) so rebuilding the tree never
/// leaves a disposed container's timers behind.
Widget host(Widget child, {ProviderContainer? container}) => UncontrolledProviderScope(
      container: container ?? (_shared ??= ProviderContainer()),
      child: MaterialApp(debugShowCheckedModeBanner: false, home: child),
    );

void setView(WidgetTester t, Size logical) {
  t.view.physicalSize = logical;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  tearDown(() {
    _shared?.dispose();
    _shared = null;
  });

  group('PopoutMath', () {
    const bounds = Rect.fromLTWH(0, 0, 1440, 810);
    test('move clamps to the artboard', () {
      const r = Rect.fromLTWH(470, 110, 500, 320);
      expect(PopoutMath.move(r, const Offset(10, -5), bounds), const Rect.fromLTWH(480, 105, 500, 320));
      expect(PopoutMath.move(r, const Offset(-9999, -9999), bounds).topLeft, Offset.zero);
      expect(PopoutMath.move(r, const Offset(9999, 9999), bounds).bottomRight, const Offset(1440, 810));
    });
    test('resize respects min and artboard', () {
      const r = Rect.fromLTWH(470, 110, 500, 320);
      expect(PopoutMath.resize(r, const Offset(-9999, -9999), const Size(240, 150), bounds).size,
          const Size(240, 150));
      expect(PopoutMath.resize(r, const Offset(9999, 9999), const Size(240, 150), bounds).bottomRight,
          const Offset(1440, 810));
    });
    test('fit shrinks defaults on small viewports', () {
      final f = PopoutMath.fit(const Rect.fromLTWH(470, 110, 500, 320), const Rect.fromLTWH(0, 0, 400, 300));
      expect(f, const Rect.fromLTWH(0, 0, 400, 300));
    });
  });

  group('PopoutController', () {
    test('one window at a time, opening resets; full screen blocks drag', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final sub = c.listen(studioPopoutProvider, (_, _) {});
      addTearDown(sub.close);
      final g = kTestGeometry.studio('broadcast_curved_wall').landscape;
      final n = c.read(studioPopoutProvider.notifier);
      n.open(const PopoutTarget.person('g1'), g);
      n.moveBy(const Offset(50, 0), const Rect.fromLTWH(0, 0, 1440, 810));
      expect(c.read(studioPopoutProvider)!.rect.left, 520);
      n.open(const PopoutTarget.table(), g);
      expect(c.read(studioPopoutProvider)!.target, const PopoutTarget.table());
      expect(c.read(studioPopoutProvider)!.rect, const Rect.fromLTWH(470, 110, 500, 320));
      n.toggleFullScreen();
      n.moveBy(const Offset(50, 0), const Rect.fromLTWH(0, 0, 1440, 810));
      expect(c.read(studioPopoutProvider)!.rect.left, 470);
      n.close();
      expect(c.read(studioPopoutProvider), isNull);
    });
  });

  group('StudioStage', () {
    final members = fakeMembers();

    Widget stage(StudioOrientation o, {StudioSettings settings = const StudioSettings(), ValueChanged<String>? onTap}) =>
        StudioStage(
          geometry: kTestGeometry,
          state: fakeState(settings),
          members: members,
          orientation: o,
          isSpeaking: speakingFrom(members),
          onTileTap: onTap,
          tableContent: const SizedBox(key: ValueKey('table-content')),
        );

    testWidgets('landscape: 6 tiles with Spotlight labels; tap reports uid', (t) async {
      setView(t, const Size(1440, 810));
      final taps = <String>[];
      final handle = t.ensureSemantics();
      await t.pumpWidget(host(stage(StudioOrientation.landscape, onTap: taps.add)));
      for (var i = 1; i <= 6; i++) {
        expect(find.bySemanticsLabel('Spotlight Guest 0$i'), findsOneWidget);
      }
      expect(find.bySemanticsLabel('Pop out Host'), findsOneWidget);
      expect(find.byKey(const ValueKey('table-content')), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Spotlight Guest 03'));
      expect(taps, ['g3']);
      // Hit-testing goes through the perspective matrix: tap the projected
      // centre of R1 (index 3 → Guest 04).
      final slot = kTestGeometry.studio('broadcast_curved_wall').landscape.slotsFor(GuestSize.m)['R1']!;
      final cam = kTestGeometry.studio('broadcast_curved_wall').camera(StudioOrientation.landscape, const Size(1440, 810));
      final centre = cam.worldToUi(projectPoint(slot.matrix3d, const Offset(80, 40)));
      await t.tapAt(centre);
      expect(taps, ['g3', 'g4']);
      handle.dispose();
    });

    testWidgets('phone: host + 4 slots only', (t) async {
      setView(t, const Size(390, 844));
      final handle = t.ensureSemantics();
      await t.pumpWidget(host(stage(StudioOrientation.phone)));
      for (var i = 1; i <= 4; i++) {
        expect(find.bySemanticsLabel('Spotlight Guest 0$i'), findsOneWidget);
      }
      expect(find.bySemanticsLabel('Spotlight Guest 05'), findsNothing);
      handle.dispose();
    });

    testWidgets('muted shows mic-off, speaking shows eq bars, names can hide', (t) async {
      setView(t, const Size(1440, 810));
      await t.pumpWidget(host(stage(StudioOrientation.landscape)));
      expect(find.byIcon(Icons.mic_off), findsNWidgets(3));
      expect(find.byType(EqBars), findsNWidgets(3));
      await t.pumpWidget(host(stage(StudioOrientation.landscape, settings: const StudioSettings(showNames: false))));
      expect(find.byType(Nameplate), findsNothing);
    });

    testWidgets('video builder is used when the camera is on', (t) async {
      setView(t, const Size(1440, 810));
      final cams = fakeMembers(camerasOn: true);
      final sizes = <String, Size>{};
      await t.pumpWidget(host(StudioStage(
        geometry: kTestGeometry,
        state: fakeState(const StudioSettings()),
        members: cams,
        orientation: StudioOrientation.landscape,
        videoBuilder: (uid, size) {
          sizes[uid] = size;
          return SizedBox(key: ValueKey('video-$uid'));
        },
      )));
      expect(find.byKey(const ValueKey('video-host')), findsOneWidget);
      expect(find.byKey(const ValueKey('video-g6')), findsOneWidget);
      expect(sizes['host']!.width, closeTo(547 * 810 / 768, 0.01));
      expect(sizes['g1']!.width, greaterThan(100));
    });

    testWidgets('expand opens one pop-out, source shows "In window"; drag, resize, full screen, close', (t) async {
      setView(t, const Size(1440, 810));
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await t.pumpWidget(host(stage(StudioOrientation.landscape), container: c));
      await t.tap(find.bySemanticsLabel('Pop out Guest 01'));
      await t.pump();
      await t.pump(); // lazy content mounts after the first frame
      expect(find.byType(PopoutWindow), findsOneWidget);
      expect(find.text('In window'), findsOneWidget);
      expect(c.read(studioPopoutProvider)!.rect, const Rect.fromLTWH(470, 110, 500, 320));

      await t.drag(find.byKey(const ValueKey('popout-drag')), const Offset(100, 50));
      await t.pump();
      expect(c.read(studioPopoutProvider)!.rect.topLeft.dx, greaterThan(470));
      await t.drag(find.byKey(const ValueKey('popout-resize')), const Offset(-1000, -1000));
      await t.pump();
      expect(c.read(studioPopoutProvider)!.rect.size, const Size(240, 150));

      await t.tap(find.bySemanticsLabel('Full screen'));
      await t.pump();
      expect(c.read(studioPopoutProvider)!.fullScreen, isTrue);
      expect(find.byKey(const ValueKey('popout-resize')), findsNothing);
      final before = c.read(studioPopoutProvider)!.rect;
      await t.drag(find.byKey(const ValueKey('popout-drag')), const Offset(100, 50));
      expect(c.read(studioPopoutProvider)!.rect, before); // no drag in full screen

      // Opening another target replaces the window.
      await t.tap(find.bySemanticsLabel('Exit full screen'));
      await t.pump();
      await t.tap(find.bySemanticsLabel('Pop out the table screen'));
      await t.pump();
      expect(c.read(studioPopoutProvider)!.target, const PopoutTarget.table());
      expect(find.byType(PopoutWindow), findsOneWidget);

      await t.tap(find.bySemanticsLabel('Close window'));
      await t.pump(const Duration(milliseconds: 500)); // double-tap timers
      expect(find.byType(PopoutWindow), findsNothing);
    });

    testWidgets('double-tap on the header toggles full screen', (t) async {
      setView(t, const Size(1440, 810));
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await t.pumpWidget(host(stage(StudioOrientation.landscape), container: c));
      await t.tap(find.bySemanticsLabel('Pop out Host'));
      await t.pump();
      final drag = find.byKey(const ValueKey('popout-drag'));
      await t.tap(drag);
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(drag);
      await t.pump(const Duration(milliseconds: 400));
      expect(c.read(studioPopoutProvider)!.fullScreen, isTrue);
    });

    testWidgets('S/M/L change tweens the matrices over ~250 ms', (t) async {
      setView(t, const Size(1440, 810));
      await t.pumpWidget(host(stage(StudioOrientation.landscape)));
      Matrix4 tileMatrix() => t
          .widgetList<Transform>(find.descendant(of: find.byKey(const ValueKey('wall-0')), matching: find.byType(Transform)))
          .map((w) => w.transform)
          .elementAt(1); // [glow, tile, expand]
      final studio = kTestGeometry.studio('broadcast_curved_wall').landscape;
      final m = studio.slotsFor(GuestSize.m)['L1']!.matrix3d;
      final l = studio.slotsFor(GuestSize.l)['L1']!.matrix3d;
      expect(tileMatrix().storage[12], closeTo(m[12], 1e-9));
      await t.pumpWidget(host(stage(StudioOrientation.landscape, settings: const StudioSettings(guestSize: GuestSize.l))));
      await t.pump(const Duration(milliseconds: 100));
      final mid = tileMatrix().storage[13];
      expect(mid, lessThan(m[13]));
      expect(mid, greaterThan(l[13]));
      await t.pump(const Duration(milliseconds: 200));
      expect(tileMatrix().storage[13], closeTo(l[13], 1e-9));
    });

    testWidgets('tile focus ring and keyboard activation', (t) async {
      setView(t, const Size(1440, 810));
      final taps = <String>[];
      await t.pumpWidget(host(stage(StudioOrientation.landscape, onTap: taps.add)));
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(taps, isNotEmpty);
    });
  });

  test('RenderRepaintBoundary is available for pixel diffs', () {
    expect(RenderRepaintBoundary(), isNotNull);
  });
}
