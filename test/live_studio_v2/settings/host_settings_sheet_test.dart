import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/settings/studio_catalog.dart';
import 'package:oneova/social_hub/live/studio_v2/settings/host_settings_sheet.dart';

import 'fakes/fake_settings_ports.dart';

const _catalog = [
  StudioCatalogEntry(id: 'broadcast_curved_wall', label: 'Broadcast studio — curved wall'),
  StudioCatalogEntry(id: 'loft', label: 'Loft'),
];

void main() {
  late FakeSettingsCallPort port;
  late StreamController<StudioState> states;

  Future<void> pumpSheet(WidgetTester tester, {StudioSettings s = const StudioSettings(), bool viaShow = false}) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    port = FakeSettingsCallPort(s);
    states = stateController();
    addTearDown(states.close);
    await tester.pumpWidget(ProviderScope(
      overrides: settingsOverrides(port: port, states: states.stream, catalog: _catalog),
      child: MaterialApp(
        home: Scaffold(
          body: viaShow
              ? Builder(
                  builder: (ctx) => TextButton(
                    onPressed: () => showHostSettingsSheet(ctx, streamId: 's1'),
                    child: const Text('open'),
                  ),
                )
              : const Align(alignment: Alignment.bottomCenter, child: HostSettingsSheet(streamId: 's1')),
        ),
      ),
    ));
    if (viaShow) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }
    states.add(stateWith(s));
    await tester.pumpAndSettle();
  }

  Future<void> tapLabel(WidgetTester tester, String label) async {
    final f = find.bySemanticsLabel(label);
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('every control has a semantics label', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpSheet(tester);
    for (final l in [
      HostSettingsLabels.sheet,
      HostSettingsLabels.studio('Broadcast studio — curved wall'),
      HostSettingsLabels.studio('Loft'),
      HostSettingsLabels.themeDark,
      HostSettingsLabels.themeLight,
      HostSettingsLabels.frameWidth,
      for (var i = 0; i < 4; i++) HostSettingsLabels.frameColor(i),
      for (final g in GuestSize.values) HostSettingsLabels.guestSize(g),
      HostSettingsLabels.showNames,
      HostSettingsLabels.studioDim,
      for (final m in SpeakerMode.values) HostSettingsLabels.speakerMode(m),
    ]) {
      expect(find.bySemanticsLabel(l), findsWidgets, reason: l);
    }
    handle.dispose();
  });

  testWidgets('discrete controls call the controller', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpSheet(tester);

    await tapLabel(tester, HostSettingsLabels.studio('Loft'));
    expect(port.partials.last, {'studioId': 'loft'});

    await tapLabel(tester, HostSettingsLabels.frameColor(2));
    expect(port.partials.last, {'frameColor': '#2F7BFF'});

    await tapLabel(tester, HostSettingsLabels.guestSize(GuestSize.l));
    expect(port.partials.last, {'guestSize': 'l'});

    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(port.partials.last, {'showNames': false});

    await tapLabel(tester, HostSettingsLabels.speakerMode(SpeakerMode.autoActiveSpeaker));
    expect(port.partials.last, {'speakerMode': 'autoActiveSpeaker'});

    await tapLabel(tester, HostSettingsLabels.themeLight);
    expect(port.partials.last, {'theme': 'light', 'frameColor': '#2F7BFF'});
    expect(port.calls.every((c) => c.args['streamId'] == 's1'), isTrue);
    handle.dispose();
  });

  testWidgets('sliders are clamped to their ranges and send once on release', (tester) async {
    await pumpSheet(tester);
    final sliders = find.byType(Slider);
    expect(sliders, findsNWidgets(2));

    await tester.drag(sliders.at(0), const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(sliders.at(0)).value, 12);
    expect(find.text('12 px'), findsOneWidget);

    await tester.ensureVisible(sliders.at(1));
    await tester.drag(sliders.at(1), const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(sliders.at(1)).value, 0);
    expect(find.text('0%'), findsOneWidget);

    await tester.drag(sliders.at(1), const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(sliders.at(1)).value, closeTo(0.6, 1e-9));

    final widths = port.partials.where((p) => p.containsKey('frameWidth')).map((p) => p['frameWidth']);
    final dims = port.partials.where((p) => p.containsKey('studioDim')).map((p) => p['studioDim']);
    expect(widths.last, 12);
    expect(widths.every((w) => (w as int) >= 0 && w <= 12), isTrue);
    expect(dims.last, 0.6);
    expect(dims.every((d) => (d as double) >= 0 && d <= 0.6), isTrue);
  });

  testWidgets('a failed save reverts the control', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpSheet(tester);
    port.fail = true;
    await tapLabel(tester, HostSettingsLabels.guestSize(GuestSize.s));
    final seg = tester.getSemantics(find.bySemanticsLabel(HostSettingsLabels.guestSize(GuestSize.m)));
    expect(seg.getSemanticsData().flagsCollection.isSelected, Tristate.isTrue);
    expect(find.textContaining("Couldn't save"), findsOneWidget);
    handle.dispose();
  });

  testWidgets('renders in the light theme with light swatches', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpSheet(tester, s: StudioSettings.defaultsFor(StudioTheme.light));
    expect(tester.takeException(), isNull);
    await tapLabel(tester, HostSettingsLabels.frameColor(1));
    expect(port.partials.last, {'frameColor': '#8C97AE'});
    handle.dispose();
  });

  testWidgets('targets are at least 44 px', (tester) async {
    await pumpSheet(tester);
    for (final label in ['S', 'M', 'L', 'Dark', 'Light']) {
      final box = tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(Container)).first);
      expect(box.height, greaterThanOrEqualTo(44), reason: label);
    }
  });

  testWidgets('showHostSettingsSheet fires a light haptic and opens the sheet', (tester) async {
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    });
    addTearDown(() =>
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpSheet(tester, viaShow: true);
    expect(haptics, contains('HapticFeedbackType.lightImpact'));
    expect(find.byType(HostSettingsSheet), findsOneWidget);
  });
}
