import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/contracts/studio_ports.dart';
import 'package:oneova/backend/live_studio/media/game_stream.dart';
import 'package:oneova/backend/live_studio/media/studio_video_view.dart';
import 'package:oneova/social_hub/live/studio_v2/gaming/gaming.dart';
import 'package:oneova/social_hub/live/studio_v2/theme/live_studio_tokens.dart';

import 'fakes/fake_gaming_room.dart';

void main() {
  const size = Size(400, 240);

  Future<void> pump(WidgetTester tester, Widget Function(BuildContext) build) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Builder(builder: (c) => SizedBox(width: 400, height: 240, child: build(c)))),
        ),
      );

  testWidgets('host with a screen track: center shows the screen share (contain)', (tester) async {
    final room = FakeGamingRoom(screenOwner: 'host');
    await pump(
      tester,
      (_) => gamingVideoFor(room: room, uid: 'host', hostId: 'host', renderSize: size, viewerIsHost: false),
    );
    final view = tester.widget<StudioVideoView>(find.byKey(const ValueKey('gaming-screen')));
    expect(view.fit, BoxFit.contain);
    expect(view.handle!.uid, 'host');
    expect(find.text(GamingWaitingPlaceholder.waitingText), findsNothing);
  });

  testWidgets('no screen track: host sees the Start button, viewers only the waiting text', (tester) async {
    final room = FakeGamingRoom();
    var taps = 0;
    await pump(
      tester,
      (_) => gamingVideoFor(
        room: room,
        uid: 'host',
        hostId: 'host',
        renderSize: size,
        viewerIsHost: true,
        onStartGame: () => taps++,
      ),
    );
    expect(find.text(GamingWaitingPlaceholder.waitingText), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('gaming-start-stream')));
    expect(taps, 1);

    await pump(
      tester,
      (_) => gamingVideoFor(
        room: room,
        uid: 'host',
        hostId: 'host',
        renderSize: size,
        viewerIsHost: false,
        onStartGame: () => taps++,
      ),
    );
    expect(find.text(GamingWaitingPlaceholder.waitingText), findsOneWidget);
    expect(find.byKey(const ValueKey('gaming-start-stream')), findsNothing);
  });

  testWidgets('guests keep their camera on the wall', (tester) async {
    final room = FakeGamingRoom(screenOwner: 'host', cameras: {'g1'});
    await pump(
      tester,
      (_) => gamingVideoFor(room: room, uid: 'g1', hostId: 'host', renderSize: size, viewerIsHost: true),
    );
    final view = tester.widget<StudioVideoView>(find.byType(StudioVideoView));
    expect(view.handle!.uid, 'g1');
    expect(view.fit, BoxFit.cover);

    await pump(
      tester,
      (_) => gamingVideoFor(room: room, uid: 'g2', hostId: 'host', renderSize: size, viewerIsHost: true),
    );
    expect(find.byType(StudioVideoView), findsNothing);
  });

  test('gaming stage members force the host center to video', () {
    const host = StageMember(uid: 'host', displayName: 'H', role: StudioRole.host, camOn: false);
    const g = StageMember(uid: 'g1', displayName: 'G', role: StudioRole.guest, camOn: false);
    final out = gamingStageMembers({'host': host, 'g1': g}, 'host');
    expect(out['host']!.camOn, isTrue);
    expect(out['host']!.role, StudioRole.host);
    expect(out['g1']!.camOn, isFalse);
    final same = {'host': const StageMember(uid: 'host', displayName: 'H')};
    expect(identical(gamingStageMembers(same, 'host'), same), isTrue);
  });

  testWidgets('Switch to game starts the stream once and shows the tip', (tester) async {
    final room = FakeGamingRoom();
    late BuildContext ctx;
    await pump(tester, (c) {
      ctx = c;
      return const SizedBox();
    });
    expect(await startGameStreamFlow(ctx, room, showTip: true), isTrue);
    await tester.pump();
    expect(room.gameStarts, 1);
    expect(find.text(kSwitchToGameTip), findsOneWidget);

    // Already streaming: no second start.
    expect(await startGameStreamFlow(ctx, room), isTrue);
    expect(room.gameStarts, 1);
  });

  testWidgets('refused consent reports an error', (tester) async {
    final room = FakeGamingRoom(failStart: true);
    late BuildContext ctx;
    await pump(tester, (c) {
      ctx = c;
      return const SizedBox();
    });
    expect(await startGameStreamFlow(ctx, room, showTip: true), isFalse);
    await tester.pump();
    expect(find.text(kSwitchToGameTip), findsNothing);
    expect(find.textContaining('Could not start the game stream'), findsOneWidget);
  });

  test('rooms without the game port fall back to the table screen share', () async {
    final plain = PlainRoom();
    await startGameStreamOn(plain);
    expect(plain.inner.tableStarts, 1);
    final StudioRoomPort game = FakeGamingRoom();
    await startGameStreamOn(game);
    expect((game as FakeGamingRoom).gameStarts, 1);
    expect(game.tableStarts, 0);
  });

  testWidgets('Now playing pill and Switch to game button render', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          const NowPlayingPill(tokens: _t, gameTitle: 'Ludo'),
          SwitchToGameButton(tokens: _t, onTap: () => taps++),
          SwitchToGameButton(tokens: _t, onTap: () => taps++, compact: true),
        ]),
      ),
    ));
    expect(find.textContaining('Ludo', findRichText: true), findsOneWidget);
    await tester.tap(find.text(SwitchToGameButton.label));
    expect(taps, 1);
  });
}

const _t = LiveStudioTokens.dark;
