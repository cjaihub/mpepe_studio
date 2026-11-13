import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:oneova/hub/phone_controller/controller_link.dart';
import 'package:oneova/hub/phone_controller/widgets/controller_trackpad.dart';
import 'package:oneova/hub/phone_controller/widgets/volume_dial.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  late List<Map<String, dynamic>> fast;
  late List<Map<String, dynamic>> reliable;
  late ControllerLink link;

  setUp(() {
    fast = [];
    reliable = [];
    link = ControllerLink(
      sendFast: (p) {
        fast.add(p);
        return true;
      },
      sendReliable: (p) {
        reliable.add(p);
        return true;
      },
    );
  });

  Future<void> pumpPad(WidgetTester tester, {bool dragLock = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 480,
            child: ControllerTrackpad(
              link: link,
              enabled: true,
              dragLock: dragLock,
            ),
          ),
        ),
      ),
    );
  }

  List<String> actions() => reliable.map((p) => p['action'] as String).toList();

  testWidgets('tap sends a left click on the reliable channel', (tester) async {
    await pumpPad(tester);
    await tester.tapAt(const Offset(150, 200));
    await tester.pump(const Duration(milliseconds: 600));
    expect(actions(), ['mouse_left_click']);
    expect(fast, isEmpty);
  });

  testWidgets('one-finger move sends deltas on the fast lane', (tester) async {
    await pumpPad(tester);
    final g = await tester.startGesture(const Offset(100, 200));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(6, 2));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await g.up();
    await tester.pump(const Duration(milliseconds: 600));
    expect(fast, isNotEmpty);
    expect(fast.every((p) => p['a'] == 'mv'), isTrue);
    final dx = fast.fold<double>(0, (s, p) => s + (p['dx'] as num));
    expect(dx, greaterThan(60)); // accelerated ≥ 1:1
    expect(actions(), isEmpty, reason: 'a move is not a click');
  });

  testWidgets('two-finger tap is a right click', (tester) async {
    await pumpPad(tester);
    final a = await tester.startGesture(const Offset(120, 200), pointer: 1);
    final b = await tester.startGesture(const Offset(180, 200), pointer: 2);
    await tester.pump(const Duration(milliseconds: 60));
    await a.up();
    await b.up();
    await tester.pump(const Duration(milliseconds: 600));
    expect(actions(), ['mouse_right_click']);
  });

  testWidgets('two-finger flick keeps gliding after release, then settles', (
    tester,
  ) async {
    await pumpPad(tester);
    // Real timestamps so the velocity tracker sees a ~3000 px/s flick.
    final a = await tester.createGesture(pointer: 1);
    final b = await tester.createGesture(pointer: 2);
    await a.down(const Offset(120, 360), timeStamp: Duration.zero);
    await b.down(const Offset(180, 360), timeStamp: Duration.zero);
    for (var i = 1; i <= 8; i++) {
      final ts = Duration(milliseconds: 8 * i);
      await a.moveBy(const Offset(0, -24), timeStamp: ts);
      await b.moveBy(const Offset(0, -24), timeStamp: ts);
      await tester.pump(const Duration(milliseconds: 8));
    }
    await a.up(timeStamp: const Duration(milliseconds: 66));
    await b.up(timeStamp: const Duration(milliseconds: 67));
    final atRelease = fast.length;
    expect(fast.every((p) => p['a'] == 'sc'), isTrue);

    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(fast.length, greaterThan(atRelease), reason: 'momentum continues');
    final glide = fast
        .sublist(atRelease)
        .map((p) => (p['dy'] as num).toDouble())
        .toList();
    expect(
      glide.every((dy) => dy < 0),
      isTrue,
      reason: 'glide follows the flick',
    );

    // Exponential decay: well under the first step after a while, then stops.
    await tester.pump(const Duration(milliseconds: 400));
    final later = (fast.last['dy'] as num).abs();
    expect(later, lessThan(glide.first.abs()));
    await tester.pumpAndSettle();
    final settled = fast.length;
    await tester.pump(const Duration(milliseconds: 200));
    expect(fast.length, settled);
  });

  testWidgets('hold then move drags with button down/up', (tester) async {
    await pumpPad(tester);
    final g = await tester.startGesture(const Offset(150, 200));
    await tester.pump(const Duration(milliseconds: 450));
    expect(actions(), ['mouse_left_down']);
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(8, 0));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await g.up();
    await tester.pump(const Duration(milliseconds: 600));
    expect(actions(), ['mouse_left_down', 'mouse_left_up']);
    expect(fast.where((p) => p['a'] == 'mv'), isNotEmpty);
  });

  testWidgets('volume dial reports a rising level when turned clockwise', (
    tester,
  ) async {
    final values = <int>[];
    int? ended;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VolumeDial(
              value: 50,
              muted: false,
              onChanged: values.add,
              onChangeEnd: (v) => ended = v,
            ),
          ),
        ),
      ),
    );
    final center = tester.getCenter(find.byType(VolumeDial));
    // Start at the top of the dial (value 50) and turn toward the right.
    final g = await tester.startGesture(center + const Offset(0, -100));
    await g.moveTo(center + const Offset(50, -87));
    await g.moveTo(center + const Offset(87, -50));
    await g.up();
    await tester.pump();
    expect(values, isNotEmpty);
    expect(values.last, greaterThan(50));
    expect(ended, values.last);
  });
}
