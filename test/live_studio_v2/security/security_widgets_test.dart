import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/security/studio_security_models.dart';
import 'package:oneova/social_hub/live/studio_v2/security/live_health_sheet.dart';
import 'package:oneova/social_hub/live/studio_v2/security/security_advisory_banner.dart';
import 'package:oneova/social_hub/live/studio_v2/theme/live_studio_tokens.dart';

import 'fakes/fake_security.dart';

void main() {
  late FakeSecuritySource source;
  late FakeCallPort calls;
  late StreamController<StudioSecurityPacket> packets;

  setUp(() {
    source = FakeSecuritySource(
      advisories: [advisory()],
      incidents: [
        incident('i1', StudioSeverity.critical, atMs: 1000, reason: '70 comment attempts from one account in 60 s'),
        incident('i2', StudioSeverity.warn, atMs: 1000 - 5 * 60000, reason: '35 brand-new accounts joined in 60 s'),
      ],
    );
    calls = FakeCallPort();
    packets = StreamController<StudioSecurityPacket>.broadcast(sync: true);
  });

  tearDown(() => packets.close());

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: securityOverrides(source: source, calls: calls, packets: packets),
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    ));
    await tester.pumpAndSettle();
  }

  group('SecurityAdvisoryBanner', () {
    for (final tokens in [LiveStudioTokens.dark, LiveStudioTokens.light]) {
      testWidgets('host sees assessment and actions (${tokens.theme.name})', (tester) async {
        await pump(tester, SecurityAdvisoryBanner(streamId: kStream, role: StudioRole.host, tokens: tokens));
        expect(find.text('One viewer is flooding the chat.'), findsOneWidget);
        expect(find.text('Mute chat Ana'), findsOneWidget);
        expect(find.text('Slow mode'), findsOneWidget);
        expect(find.text('Details'), findsOneWidget);
        for (final f in [find.text('Mute chat Ana'), find.text('Slow mode'), find.bySemanticsLabel('Dismiss alert')]) {
          final box = tester.getSize(find.ancestor(of: f, matching: find.byType(Semantics)).first);
          expect(box.height, greaterThanOrEqualTo(44));
          expect(box.width, greaterThanOrEqualTo(44));
        }
        expect(find.bySemanticsLabel(RegExp('^Live health alert')), findsOneWidget);
      });
    }

    testWidgets('hidden for viewers and guests', (tester) async {
      await pump(tester, const SecurityAdvisoryBanner(streamId: kStream, role: StudioRole.viewer, tokens: LiveStudioTokens.dark));
      expect(find.textContaining('flooding'), findsNothing);
      await pump(tester, const SecurityAdvisoryBanner(streamId: kStream, role: StudioRole.guest, tokens: LiveStudioTokens.dark));
      expect(find.textContaining('flooding'), findsNothing);
    });

    testWidgets('co-host action goes through the confirmation, then calls', (tester) async {
      final confirm = FakeConfirm(true);
      await pump(
        tester,
        SecurityAdvisoryBanner(streamId: kStream, role: StudioRole.coHost, tokens: LiveStudioTokens.dark, confirm: confirm.call),
      );
      await tester.tap(find.text('Mute chat Ana'));
      await tester.pumpAndSettle();
      expect(confirm.prompts.single.title, 'Mute Ana in chat?');
      expect(calls.calls.single.$1, StudioCallables.muteChat);
      expect(find.bySemanticsLabel('Mute chat Ana, done'), findsOneWidget);
    });

    testWidgets('default confirm is the studio dialog; cancel runs nothing', (tester) async {
      await pump(tester, const SecurityAdvisoryBanner(streamId: kStream, role: StudioRole.host, tokens: LiveStudioTokens.dark));
      await tester.tap(find.text('Slow mode'));
      await tester.pumpAndSettle();
      expect(find.text('Turn on slow mode?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls.calls, isEmpty);
    });

    testWidgets('dismiss hides the banner', (tester) async {
      await pump(tester, const SecurityAdvisoryBanner(streamId: kStream, role: StudioRole.host, tokens: LiveStudioTokens.dark));
      await tester.tap(find.bySemanticsLabel('Dismiss alert'));
      await tester.pumpAndSettle();
      expect(find.textContaining('flooding'), findsNothing);
    });

    testWidgets('Details opens the live health sheet', (tester) async {
      await pump(tester, const SecurityAdvisoryBanner(streamId: kStream, role: StudioRole.host, tokens: LiveStudioTokens.dark));
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Live health'), findsWidgets);
      expect(find.text('70 comment attempts from one account in 60 s'), findsOneWidget);
    });
  });

  group('LiveHealthSheet', () {
    for (final tokens in [LiveStudioTokens.dark, LiveStudioTokens.light]) {
      testWidgets('lists incidents with age (${tokens.theme.name})', (tester) async {
        await pump(
          tester,
          LiveHealthSheet(streamId: kStream, tokens: tokens, now: () => DateTime.fromMillisecondsSinceEpoch(1000 + 30000)),
        );
        expect(find.text('70 comment attempts from one account in 60 s'), findsOneWidget);
        expect(find.text('just now'), findsOneWidget);
        expect(find.text('5 min ago'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('^critical alert')), findsOneWidget);
        expect(tester.getSize(find.bySemanticsLabel('Close live health')).height, greaterThanOrEqualTo(44));
      });
    }

    testWidgets('empty state', (tester) async {
      source.incidents = const [];
      await pump(tester, const LiveHealthSheet(streamId: kStream, tokens: LiveStudioTokens.dark));
      expect(find.text('No security alerts. All good.'), findsOneWidget);
    });
  });

  test('age labels', () {
    expect(studioAgeLabel(0, 59000), 'just now');
    expect(studioAgeLabel(0, 120000), '2 min ago');
    expect(studioAgeLabel(0, 7200000), '2 h ago');
  });
}
