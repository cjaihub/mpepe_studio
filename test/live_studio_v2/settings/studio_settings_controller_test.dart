import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/contracts/studio_ports.dart';
import 'package:oneova/backend/live_studio/settings/studio_settings_controller.dart';

import 'fakes/fake_settings_ports.dart';

void main() {
  late FakeSettingsCallPort port;
  late StreamController<StudioState> states;
  late ProviderContainer c;

  StudioSettingsController ctl() => c.read(studioSettingsControllerProvider('s1').notifier);
  StudioSettingsView view() => c.read(studioSettingsControllerProvider('s1'));

  Future<void> boot(WidgetTester tester, [StudioSettings s = const StudioSettings()]) async {
    port = FakeSettingsCallPort(s);
    states = stateController();
    c = ProviderContainer(overrides: settingsOverrides(port: port, states: states.stream));
    addTearDown(() {
      c.dispose();
      states.close();
    });
    c.listen(studioSettingsControllerProvider('s1'), (_, _) {});
    states.add(stateWith(s));
    await idle(tester);
  }

  testWidgets('reads applied settings from StudioState', (tester) async {
    await boot(tester, const StudioSettings(frameWidth: 7));
    expect(view().ready, isTrue);
    expect(view().applied.frameWidth, 7);
    states.add(stateWith(const StudioSettings(guestSize: GuestSize.l), seq: 2));
    await idle(tester);
    expect(view().effective.guestSize, GuestSize.l);
  });

  test('unwired state source fails loudly', () async {
    final bare = ProviderContainer(
      retry: (_, _) => null,
      overrides: [studioCallPortProvider.overrideWithValue(FakeSettingsCallPort())],
    );
    addTearDown(bare.dispose);
    expect(() => bare.read(studioSettingsControllerProvider('x')), throwsA(anything));
  });

  testWidgets('discrete edits apply at once and call lsSetSettings with the stream id', (tester) async {
    await boot(tester);
    ctl().setGuestSize(GuestSize.s);
    expect(view().effective.guestSize, GuestSize.s); // optimistic
    expect(view().applied.guestSize, GuestSize.m);
    await idle(tester);
    expect(port.calls.single.name, StudioCallables.setSettings);
    expect(port.calls.single.args['streamId'], 's1');
    expect(port.partials.single, {'guestSize': 's'});
    await idle(tester);
    expect(view().applied.guestSize, GuestSize.s);
    expect(view().saving, isFalse);
  });

  testWidgets('reverts on callable error', (tester) async {
    await boot(tester);
    port.fail = true;
    ctl().setSpeakerMode(SpeakerMode.manual);
    expect(view().effective.speakerMode, SpeakerMode.manual);
    await idle(tester);
    await idle(tester);
    expect(view().effective.speakerMode, SpeakerMode.hostPinned);
    expect(view().error, isNotNull);
  });

  testWidgets('sliders send at most one call per 250 ms, with the latest value', (tester) async {
    await boot(tester);
    for (var w = 5; w <= 12; w++) {
      ctl().setFrameWidth(w);
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(port.calls, isEmpty);
    expect(view().effective.frameWidth, 12);
    await tester.pump(const Duration(milliseconds: 100)); // 260 ms since first change
    expect(port.partials, [
      {'frameWidth': 12}
    ]);
    ctl().setStudioDim(0.3);
    ctl().setStudioDim(0.45);
    await tester.pump(const Duration(milliseconds: 249));
    expect(port.calls.length, 1);
    await tester.pump(const Duration(milliseconds: 2));
    expect(port.partials.last, {'studioDim': 0.45});
    await idle(tester);
    expect(view().applied.studioDim, 0.45);
  });

  testWidgets('flush sends a throttled slider value immediately', (tester) async {
    await boot(tester);
    ctl().setStudioDim(0.5);
    ctl().flush();
    await idle(tester);
    expect(port.partials, [
      {'studioDim': 0.5}
    ]);
  });

  testWidgets('a discrete edit carries a pending slider value in the same call', (tester) async {
    await boot(tester);
    ctl().setFrameWidth(9);
    ctl().setShowNames(false);
    await idle(tester);
    expect(port.partials, [
      {'frameWidth': 9, 'showNames': false}
    ]);
    await tester.pump(const Duration(milliseconds: 300));
    expect(port.calls.length, 1);
  });

  testWidgets('ranges are clamped before preview and send', (tester) async {
    await boot(tester);
    ctl().setFrameWidth(40);
    expect(view().effective.frameWidth, 12);
    ctl().setStudioDim(-3);
    expect(view().effective.studioDim, 0);
    ctl().flush();
    await idle(tester);
    expect(port.partials.single, {'frameWidth': 12, 'studioDim': 0.0});
  });

  testWidgets('theme switch maps the frame color and sends both', (tester) async {
    await boot(tester, const StudioSettings(frameColor: '#2F7BFF'));
    ctl().setTheme(StudioTheme.light);
    expect(view().effective.theme, StudioTheme.light);
    expect(view().effective.frameColor, '#2F7BFF');
    await idle(tester);
    expect(port.partials.single, {'theme': 'light', 'frameColor': '#2F7BFF'});

    ctl().setFrameColor('#15151B'); // a dark option: ignored in light
    ctl().setFrameColor('#8c97ae');
    await idle(tester);
    expect(port.partials.last, {'frameColor': '#8C97AE'});
  });

  testWidgets('no-op edits make no call', (tester) async {
    await boot(tester);
    ctl().setShowNames(true);
    ctl().setTheme(StudioTheme.dark);
    ctl().setFrameWidth(4);
    await tester.pump(const Duration(milliseconds: 300));
    expect(port.calls, isEmpty);
  });

  testWidgets('a newer edit survives the confirmation of an older one', (tester) async {
    await boot(tester);
    ctl().setGuestSize(GuestSize.s);
    ctl().setGuestSize(GuestSize.l);
    await idle(tester);
    await idle(tester);
    await idle(tester);
    expect(view().effective.guestSize, GuestSize.l);
    expect(port.partials.map((p) => p['guestSize']), ['s', 'l']);
  });
}

/// Drains queued microtasks / chained calls without advancing the clock.
Future<void> idle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}
