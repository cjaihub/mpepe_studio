import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:oneova/hub/phone_controller/computer_action_log.dart';
import 'package:oneova/hub/phone_controller/controller_link.dart';
import 'package:oneova/hub/phone_controller/widgets/live_screen_view.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  late List<Map<String, dynamic>> reliable;
  late List<Map<String, dynamic>> fast;
  late List<String> logged;
  late ControllerLink link;

  setUp(() {
    reliable = [];
    fast = [];
    logged = [];
    link = ControllerLink(
      sendFast: (p) {
        fast.add(p);
        return true;
      },
      sendReliable: (p) {
        reliable.add(p);
        return true;
      },
      recorder: (source, action, params, {secret = false}) =>
          logged.add('${source.name}:$action'),
    );
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 200,
              child: LiveScreenView(
                renderer: null,
                link: link,
                hasVideo: true,
                enabled: true,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('tapping the live screen clicks at that spot (normalised)', (tester) async {
    await pumpScreen(tester);
    final box = tester.getRect(find.byType(LiveScreenView));
    await tester.tapAt(box.topLeft + const Offset(80, 150)); // 25%, 75%
    await tester.pump(const Duration(milliseconds: 400));
    final click = reliable.single;
    expect(click['action'], 'mouse_click_normalized');
    expect((click['nx'] as num).toDouble(), closeTo(0.25, 0.01));
    expect((click['ny'] as num).toDouble(), closeTo(0.75, 0.01));
    expect(logged, ['touch:click']);
  });

  testWidgets('hold then slide drags; hold and release right-clicks', (tester) async {
    await pumpScreen(tester);
    final box = tester.getRect(find.byType(LiveScreenView));
    final g = await tester.startGesture(box.center);
    await tester.pump(const Duration(milliseconds: 420));
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump(const Duration(milliseconds: 400));
    final actions = reliable.map((p) => p['action']).toList();
    expect(actions, containsAllInOrder(['mouse_move_normalized', 'mouse_left_down', 'mouse_left_up']));
    expect(fast.where((p) => p['a'] == 'mt'), isNotEmpty);

    reliable.clear();
    final h = await tester.startGesture(box.center);
    await tester.pump(const Duration(milliseconds: 420));
    await h.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(reliable.single['action'], 'mouse_right_click_normalized');
  });

  test('action log merges pointer moves and redacts secrets', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final log = container.read(computerActionLogProvider.notifier);
    log.record(ActionSource.trackpad, 'move', params: {'dx': 3.0, 'dy': 1.0});
    log.record(ActionSource.trackpad, 'move', params: {'dx': 2.0, 'dy': -1.0});
    log.record(ActionSource.ai, 'type_text', params: {'text': 'hunter2'}, secret: true);
    log.record(ActionSource.system, 'unlock', params: {'password': 'p@ss'});

    final steps = container.read(computerActionLogProvider).steps;
    expect(steps.length, 3);
    final move = steps.last;
    expect(move.count, 2);
    expect(move.params['dx'], 5.0);
    expect(steps[1].params.containsKey('text'), isFalse);
    expect(steps[1].summary, 'Typed hidden text');
    expect(steps.first.params.containsKey('password'), isFalse);
  });

  test('voice instructions label following steps for the dataset', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final log = container.read(computerActionLogProvider.notifier);
    log.record(ActionSource.voice, 'user_said', params: {'text': 'open Safari'});
    log.record(ActionSource.ai, 'key_combo', params: {'combo': 'cmd+space'});
    final step = container.read(computerActionLogProvider).steps.first;
    expect(step.instruction, 'open Safari');
    expect(step.toJson()['instruction'], 'open Safari');
  });
}
