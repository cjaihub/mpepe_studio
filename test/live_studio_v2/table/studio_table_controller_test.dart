import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/table/studio_table_controller.dart';

import 'fakes/fake_table.dart';

void main() {
  late StreamController<StudioState> states;
  late FakeCallPort port;
  late FakeTableRoom room;
  late ProviderContainer c;

  StudioTableController ctl() => c.read(studioTableControllerProvider('s1').notifier);
  StudioTableView view() => c.read(studioTableControllerProvider('s1'));
  Future<void> idle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> boot({StudioRole role = StudioRole.host, TableState table = const TableState()}) async {
    states = StreamController<StudioState>.broadcast();
    port = tableServer(initial: table);
    room = FakeTableRoom();
    c = ProviderContainer(overrides: tableOverrides(port: port, states: states.stream, role: role, room: room));
    addTearDown(() {
      c.dispose();
      states.close();
    });
    c.listen(studioTableControllerProvider('s1'), (_, _) {});
    states.add(tableState(table));
    await idle();
  }

  test('exposes the table from the session states', () async {
    await boot();
    expect(view().ready, isTrue);
    expect(view().mode, TableMode.goods);
    states.add(tableState(const TableState(mode: TableMode.movie), seq: 5));
    await idle();
    expect(view().mode, TableMode.movie);
    expect(c.read(studioTableStateProvider('s1')).mode, TableMode.movie);
  });

  test('ignores stale states (lower seq)', () async {
    await boot();
    states.add(tableState(const TableState(mode: TableMode.match), seq: 9));
    await idle();
    states.add(tableState(const TableState(mode: TableMode.screen), seq: 3));
    await idle();
    expect(view().mode, TableMode.match);
  });

  test('setMode calls lsSetTable without a ref and applies the result', () async {
    await boot();
    final f = ctl().setMode(TableMode.match);
    expect(view().shownMode, TableMode.match); // optimistic pick
    expect(await f, isTrue);
    final call = port.calls.single;
    expect(call.$1, StudioCallables.setTable);
    expect(call.$2, {'streamId': 's1', 'mode': 'match'});
    expect(view().mode, TableMode.match);
    expect(view().pendingMode, isNull);
    expect(view().busy, isFalse);
  });

  test('putGoods / putWatch / putScreen send typed refs', () async {
    await boot();
    await ctl().putGoods(const GoodsRef(source: GoodsSource.stream, productId: 'p9'));
    await ctl().putWatch(TableMode.movie, 'cat1');
    await ctl().putScreen(publisherUid: 'g1');
    expect(port.calls[0].$2['ref'], {'source': 'stream', 'productId': 'p9'});
    expect(port.calls[1].$2['ref'], {'catalogId': 'cat1'});
    expect(port.calls[2].$2['ref'], {'publisherUid': 'g1'});
    expect(view().table.screen!.publisherUid, 'g1');
    expect(view().table.goods!.productId, 'p9');
  });

  test('viewers and guests cannot change the table', () async {
    for (final role in [StudioRole.viewer, StudioRole.guest]) {
      await boot(role: role);
      expect(view().canManage, isFalse);
      expect(await ctl().setMode(TableMode.movie), isFalse);
      expect(await ctl().shareScreenToTable(), isFalse);
      expect(port.calls, isEmpty);
      expect(room.starts, 0);
      c.dispose();
    }
  });

  test('co-host can manage', () async {
    await boot(role: StudioRole.coHost);
    expect(await ctl().setMode(TableMode.screen), isTrue);
  });

  test('server error: reverts the optimistic mode and keeps the error', () async {
    await boot();
    port.on(StudioCallables.setTable, (_) => throw StateError('permission-denied'));
    expect(await ctl().setMode(TableMode.movie), isFalse);
    expect(view().shownMode, TableMode.goods);
    expect(view().error, isA<StateError>());
  });

  test('playback commands re-anchor through lsPlayback in watch modes only', () async {
    await boot();
    expect(await ctl().play(0), isFalse); // goods mode
    await ctl().putWatch(TableMode.match, 'c1');
    expect(await ctl().play(1500), isTrue);
    expect(port.calls.last.$1, StudioCallables.playback);
    expect(port.calls.last.$2, {'streamId': 's1', 'state': 'playing', 'positionMs': 1500});
    expect(view().table.watch!.state, PlaybackState.playing);
    await ctl().seek(9000);
    expect(port.calls.last.$2['state'], 'playing');
    await ctl().pause(9100);
    expect(view().table.watch!.state, PlaybackState.paused);
    await ctl().end(9200);
    expect(port.calls.last.$2['state'], 'ended');
    await ctl().pause(-5);
    expect(port.calls.last.$2['positionMs'], 0);
  });

  test('Join ↔ Watching is local per stream mode', () async {
    await boot(role: StudioRole.viewer);
    ctl().toggleJoin(TableMode.match);
    expect(view().isJoined(TableMode.match), isTrue);
    expect(view().isJoined(TableMode.movie), isFalse);
    ctl().toggleJoin(TableMode.goods); // not a stream mode
    expect(view().joined, {TableMode.match});
    ctl().toggleJoin(TableMode.match);
    expect(view().isJoined(TableMode.match), isFalse);
    ctl().setJoined(TableMode.screen, true);
    expect(view().isJoined(TableMode.screen), isTrue);
    expect(port.calls, isEmpty);
  });

  test('shareScreenToTable starts the share then sets screen mode', () async {
    await boot();
    expect(await ctl().shareScreenToTable(), isTrue);
    expect(room.starts, 1);
    expect(port.calls.single.$2['mode'], 'screen');
    expect(view().mode, TableMode.screen);
  });

  test('shareScreenToTable: start failure does not touch the table', () async {
    await boot();
    room.startError = StateError('denied');
    expect(await ctl().shareScreenToTable(), isFalse);
    expect(port.calls, isEmpty);
    expect(view().error, isA<StateError>());
  });

  test('shareScreenToTable: table failure stops the share again', () async {
    await boot();
    port.on(StudioCallables.setTable, (_) => throw StateError('x'));
    expect(await ctl().shareScreenToTable(), isFalse);
    expect(room.starts, 1);
    expect(room.stops, 1);
  });
}
