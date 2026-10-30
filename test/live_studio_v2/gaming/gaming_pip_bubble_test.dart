import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/social_hub/live/studio_v2/gaming/gaming_pip_bubble.dart';

void main() {
  const insets = EdgeInsets.fromLTRB(10, 100, 10, 70);
  const area = Size(400, 800);

  group('snapPipOffset', () {
    test('snaps to the nearest side and clamps y', () {
      expect(snapPipOffset(dropped: const Offset(50, 300), area: area, diameter: 96, insets: insets),
          const Offset(10, 300));
      expect(snapPipOffset(dropped: const Offset(250, 300), area: area, diameter: 96, insets: insets),
          const Offset(400 - 10 - 96, 300));
      expect(snapPipOffset(dropped: const Offset(250, -40), area: area, diameter: 96, insets: insets).dy, 100);
      expect(snapPipOffset(dropped: const Offset(250, 2000), area: area, diameter: 96, insets: insets).dy,
          800 - 70 - 96);
    });

    test('tiny areas never produce negative ranges', () {
      final o = snapPipOffset(dropped: Offset.zero, area: const Size(50, 50), diameter: 96, insets: insets);
      expect(o.dx, 10);
      expect(o.dy, 100);
    });
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = area;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: GamingPipBubble(insets: insets, child: ColoredBox(color: Color(0xFF000000))),
      ),
    ));
  }

  testWidgets('starts top-right, drags and snaps to the left side', (tester) async {
    await pump(tester);
    final bubble = find.byKey(GamingPipBubble.bubbleKey);
    expect(tester.getTopLeft(bubble), const Offset(400 - 10 - 96, 100));

    await tester.drag(bubble, const Offset(-300, 200));
    await tester.pumpAndSettle();
    final p = tester.getTopLeft(bubble);
    expect(p.dx, 10);
    expect(p.dy, closeTo(300, 20)); // drag slop eats a few px
  });

  testWidgets('tap hides to a tab, tap on the tab shows it again', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(GamingPipBubble.bubbleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(GamingPipBubble.bubbleKey), findsNothing);
    expect(find.byKey(GamingPipBubble.tabKey), findsOneWidget);
    // Tab hugs the right edge (the bubble's side).
    expect(tester.getTopRight(find.byKey(GamingPipBubble.tabKey)).dx, 400);

    await tester.tap(find.byKey(GamingPipBubble.tabKey));
    await tester.pumpAndSettle();
    expect(find.byKey(GamingPipBubble.bubbleKey), findsOneWidget);
    expect(tester.getSize(find.byKey(GamingPipBubble.bubbleKey)), const Size(96, 96));
  });
}
