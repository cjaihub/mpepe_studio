import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/social_hub/live/studio_v2/table/table.dart';
import 'package:oneova/social_hub/live/studio_v2/theme/live_studio_tokens.dart';

import 'fakes/fake_table.dart';

class _Rig {
  _Rig(this.port, this.states, this.room, this.goods, this.catalog, this.players);
  final FakeCallPort port;
  final StreamController<StudioState> states;
  final FakeTableRoom room;
  final FakeGoodsStore goods;
  final FakeCatalogStore catalog;
  final List<FakePlayerHandle> players;
}

void main() {
  Future<_Rig> pump(
    WidgetTester tester, {
    required TableState table,
    StudioRole role = StudioRole.viewer,
    bool phone = false,
    Size? size,
    void Function(_Rig rig)? setup,
    Widget Function(String streamId)? child,
  }) async {
    final rig = _Rig(tableServer(initial: table), StreamController<StudioState>.broadcast(), FakeTableRoom(),
        FakeGoodsStore(), FakeCatalogStore(), []);
    setup?.call(rig);
    addTearDown(rig.states.close);
    final s = size ??
        (phone
            ? const Size(TableMetrics.phoneWidth, TableMetrics.phoneHeight)
            : const Size(TableMetrics.landscapeWidth, TableMetrics.landscapeHeight));
    await tester.pumpWidget(ProviderScope(
      overrides: tableOverrides(
        port: rig.port,
        states: rig.states.stream,
        role: role,
        room: rig.room,
        goods: rig.goods,
        catalog: rig.catalog,
        players: rig.players,
      ),
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: s.width,
              height: s.height,
              child: child?.call('s1') ?? StudioTableContent(streamId: 's1', phone: phone),
            ),
          ),
        ),
      ),
    ));
    rig.states.add(tableState(table));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    return rig;
  }

  /// Disposes the tree (cancels the screen-mode poll timer).
  Future<void> done(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  group('goods', () {
    const ref = GoodsRef(source: GoodsSource.biz, productId: 'p1');

    testWidgets('product card: tag, name, price, View item; no LIVE pill', (tester) async {
      TableGoodsItem? opened;
      await pump(
        tester,
        table: const TableState(goods: ref),
        setup: (r) => r.goods.items['biz/p1'] =
            const TableGoodsItem(source: GoodsSource.biz, productId: 'p1', name: 'Studio Mic', price: 199, currency: 'USD'),
        child: (id) => StudioTableContent(streamId: id, onViewItem: (i) => opened = i),
      );
      expect(find.text('PRESENTER’S GOODS'), findsOneWidget);
      expect(find.text('Studio Mic'), findsOneWidget);
      expect(find.text('\$199.00'), findsOneWidget);
      expect(find.text('LIVE'), findsNothing);
      expect(find.byIcon(Icons.inventory_2), findsOneWidget); // cube fallback (no image)
      await tester.tap(find.text('View item'));
      expect(opened?.productId, 'p1');
      await done(tester);
    });

    testWidgets('nothing on the table: host hint, no CTA', (tester) async {
      await pump(tester, table: const TableState(), role: StudioRole.host);
      expect(find.text(TableModeCopy.noGoods), findsOneWidget);
      expect(find.text(TableModeCopy.noGoodsHost), findsOneWidget);
      expect(find.text('View item'), findsNothing);
      await done(tester);
    });

    test('price formatting', () {
      expect(formatTablePrice(12.5, 'USD'), '\$12.50');
      expect(formatTablePrice(null, 'USD'), '');
      expect(formatTablePrice(5000, 'TZS'), contains('5,000'));
    });
  });

  group('screen', () {
    testWidgets('no track: Waiting for screen share, LIVE pill, no CTA', (tester) async {
      await pump(tester, table: const TableState(mode: TableMode.screen, screen: ScreenRef(publisherUid: 'host')));
      expect(find.text('SCREEN SHARE'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text(TableModeCopy.waitingScreen), findsOneWidget);
      expect(find.text('Join'), findsNothing);
      await done(tester);
    });

    testWidgets('track: Join ↔ Watching toggles locally', (tester) async {
      final rig = await pump(
        tester,
        table: const TableState(mode: TableMode.screen, screen: ScreenRef(publisherUid: 'host')),
        setup: (r) => r.room.screen = FakeVideoHandle(),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(TableModeCopy.hostScreen), findsOneWidget);
      await tester.tap(find.text('Join'));
      await tester.pump();
      expect(find.text('Watching'), findsOneWidget);
      await tester.tap(find.text('Watching'));
      await tester.pump();
      expect(find.text('Join'), findsOneWidget);
      expect(rig.port.calls, isEmpty);
      await done(tester);
    });
  });

  group('match / movie', () {
    testWidgets('empty catalog: host sees "No licensed content available"', (tester) async {
      await pump(tester, table: const TableState(mode: TableMode.match), role: StudioRole.host);
      expect(find.text('LIVE MATCH'), findsOneWidget);
      expect(find.text(TableModeCopy.noLicensed), findsOneWidget);
      expect(find.text('Join'), findsNothing);
      await done(tester);
    });

    testWidgets('empty catalog: viewers see a placeholder', (tester) async {
      await pump(tester, table: const TableState(mode: TableMode.movie));
      expect(find.text('WATCH PARTY'), findsOneWidget);
      expect(find.text(TableModeCopy.viewerNothing), findsOneWidget);
      expect(find.text(TableModeCopy.noLicensed), findsNothing);
      await done(tester);
    });

    testWidgets('poster until Join; Watching builds the synced player', (tester) async {
      final rig = await pump(
        tester,
        table: const TableState(mode: TableMode.match, watch: WatchParty(catalogId: 'c1', anchorServerMs: kNow)),
        setup: (r) => r.catalog.entries['c1'] = catalogEntry('c1', TableMode.match),
      );
      expect(find.text('Home vs Away'), findsOneWidget);
      expect(find.text('Football'), findsOneWidget);
      expect(find.byKey(const Key('fake-player')), findsNothing);
      expect(rig.players, isEmpty); // lazy: no player before Join

      await tester.tap(find.text('Join'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Watching'), findsOneWidget);
      expect(rig.players.single.url, 'https://cdn.example/c1.m3u8');
      expect(find.byKey(const Key('fake-player')), findsOneWidget);

      // Host presses play → the player follows.
      rig.states.add(tableState(
          const TableState(
              mode: TableMode.match,
              watch: WatchParty(catalogId: 'c1', state: PlaybackState.playing, anchorServerMs: kNow)),
          seq: 2));
      await tester.pump();
      await tester.pump();
      expect(rig.players.single.fake.isPlaying, isTrue);

      await tester.tap(find.text('Watching'));
      await tester.pump();
      expect(find.byKey(const Key('fake-player')), findsNothing);
      expect(rig.players.single.disposed, isTrue);
      await done(tester);
    });

    testWidgets('expired entry: unavailable, Join disabled', (tester) async {
      final rig = await pump(
        tester,
        table: const TableState(mode: TableMode.movie, watch: WatchParty(catalogId: 'old')),
        setup: (r) => r.catalog.entries['old'] = catalogEntry('old', TableMode.movie, validUntilMs: kNow - 1),
      );
      expect(find.text(TableModeCopy.unavailable), findsOneWidget);
      await tester.tap(find.text('Join'), warnIfMissed: false);
      await tester.pump();
      expect(find.text('Watching'), findsNothing);
      expect(rig.players, isEmpty);
      await done(tester);
    });

    testWidgets('host gets a play control that calls lsPlayback', (tester) async {
      final rig = await pump(
        tester,
        role: StudioRole.host,
        table: const TableState(mode: TableMode.movie, watch: WatchParty(catalogId: 'm1', anchorServerMs: kNow)),
        setup: (r) => r.catalog.entries['m1'] = catalogEntry('m1', TableMode.movie, title: 'Film'),
      );
      await tester.tap(find.bySemanticsLabel('Play for everyone'));
      await tester.pump();
      expect(rig.port.calls.single.$1, StudioCallables.playback);
      expect(rig.port.calls.single.$2['state'], 'playing');
      await done(tester);
    });

    testWidgets('viewer has no play control', (tester) async {
      await pump(
        tester,
        table: const TableState(mode: TableMode.movie, watch: WatchParty(catalogId: 'm1')),
        setup: (r) => r.catalog.entries['m1'] = catalogEntry('m1', TableMode.movie),
      );
      expect(find.bySemanticsLabel('Play for everyone'), findsNothing);
      await done(tester);
    });
  });

  testWidgets('phone size renders scaled-down typography', (tester) async {
    await pump(tester, table: const TableState(mode: TableMode.match), phone: true);
    final tag = tester.widget<Text>(find.text('LIVE MATCH'));
    expect(tag.style!.fontSize, 9);
    await done(tester);
  });

  testWidgets('pop-out size scales typography up', (tester) async {
    await pump(tester, table: const TableState(mode: TableMode.match), size: const Size(576, 324));
    final tag = tester.widget<Text>(find.text('LIVE MATCH'));
    expect(tag.style!.fontSize, 20);
    await done(tester);
  });

  group('pickers', () {
    const t = LiveStudioTokens.dark;

    testWidgets('capsule: manager switches; active chip shows its label', (tester) async {
      final rig = await pump(tester,
          table: const TableState(),
          role: StudioRole.host,
          size: const Size(480, 44),
          child: (id) => TableModePicker(streamId: id, kind: TableModePickerKind.capsule, tokens: t));
      expect(find.text('On the table'), findsOneWidget);
      expect(find.text('Goods'), findsOneWidget);
      expect(find.text('Movie'), findsNothing); // idle chips are icon-only
      await tester.tap(find.byIcon(Icons.movie));
      await tester.pump();
      expect(rig.port.calls.single.$2['mode'], 'movie');
      expect(find.text('Movie'), findsOneWidget);
    });

    testWidgets('rail: viewer is read-only', (tester) async {
      final rig = await pump(tester,
          table: const TableState(mode: TableMode.screen),
          child: (id) => TableModePicker(streamId: id, kind: TableModePickerKind.rail, tokens: t));
      expect(find.byIcon(Icons.sports_soccer), findsOneWidget);
      await tester.tap(find.byIcon(Icons.sports_soccer));
      await tester.pump();
      expect(rig.port.calls, isEmpty);
      final sem = tester.getSemantics(find.bySemanticsLabel('Put Match on the table'));
      expect(sem.flagsCollection.isEnabled, isNot(true));
    });

    testWidgets('grid: hidden for viewers when asked', (tester) async {
      await pump(tester,
          table: const TableState(),
          child: (id) =>
              TableModePicker(streamId: id, kind: TableModePickerKind.grid, tokens: t, hideWhenReadOnly: true));
      expect(find.text('On the table'), findsNothing);
    });

    testWidgets('grid: 44px labelled buttons for managers', (tester) async {
      await pump(tester,
          table: const TableState(),
          role: StudioRole.coHost,
          size: const Size(360, 80),
          child: (id) => TableModePicker(streamId: id, kind: TableModePickerKind.grid, tokens: LiveStudioTokens.light));
      for (final l in ['Goods', 'Screen', 'Match', 'Movie']) {
        expect(find.text(l), findsOneWidget);
      }
      expect(tester.getSize(find.bySemanticsLabel('Put Screen on the table')).height, 44);
    });
  });

  group('share to table', () {
    testWidgets('manager: starts the share and sets screen mode', (tester) async {
      final rig = await pump(tester,
          table: const TableState(),
          role: StudioRole.host,
          child: (id) => ShareToTableButton(streamId: id, tokens: LiveStudioTokens.dark));
      await tester.tap(find.text('Share'));
      await tester.pump();
      await tester.pump();
      expect(rig.room.starts, 1);
      expect(rig.port.calls.single.$2['mode'], 'screen');
    });

    testWidgets('viewer: hidden', (tester) async {
      await pump(tester,
          table: const TableState(),
          child: (id) => ShareToTableButton(
              streamId: id, tokens: LiveStudioTokens.dark, variant: ShareToTableVariant.phone));
      expect(find.byIcon(Icons.cast), findsNothing);
    });
  });
}
