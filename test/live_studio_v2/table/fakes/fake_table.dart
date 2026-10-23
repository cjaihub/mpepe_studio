// Test-only fakes for the "On the table" workstream.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/contracts/studio_ports.dart';
import 'package:oneova/backend/live_studio/session/studio_session_controller.dart';
import 'package:oneova/backend/live_studio/table/studio_table_controller.dart';
import 'package:oneova/backend/live_studio/table/table_sources.dart';
import 'package:oneova/backend/live_studio/table/watch_party_sync.dart';
import 'package:oneova/social_hub/live/studio_v2/table/watch_player_handle.dart';

import '../../session/fakes/fake_studio.dart';

export '../../session/fakes/fake_studio.dart';

class FakeClock implements StudioClockPort {
  FakeClock([this.localMs = 0, this.offsetMs = 0]);
  int localMs;
  @override
  int offsetMs;
  int calibrations = 0;
  @override
  int serverNowMs() => localMs + offsetMs;
  @override
  Future<void> calibrate() async => calibrations++;
}

class FakeWatchPlayer implements WatchPlayer {
  @override
  int positionMs = 0;
  @override
  bool isPlaying = false;
  @override
  double rate = 1;
  @override
  int? durationMs;
  final List<String> log = [];

  @override
  Future<void> play() async {
    isPlaying = true;
    log.add('play');
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    log.add('pause');
  }

  @override
  Future<void> seekTo(int ms) async {
    positionMs = ms;
    log.add('seek $ms');
  }

  @override
  Future<void> setRate(double r) async {
    rate = r;
    log.add('rate $r');
  }
}

class FakePlayerHandle implements WatchPlayerHandle {
  FakePlayerHandle(this.url);
  final String url;
  final FakeWatchPlayer fake = FakeWatchPlayer();
  bool disposed = false;
  @override
  WatchPlayer get player => fake;
  @override
  Widget buildView(BuildContext context) => const SizedBox.expand(key: Key('fake-player'));
  @override
  Future<void> dispose() async => disposed = true;
}

class FakeTableRoom extends FakeRoom {
  StudioVideoHandle? screen;
  int starts = 0, stops = 0;
  Object? startError;

  @override
  StudioVideoHandle? tableScreen() => screen;
  @override
  Future<void> startTableScreenShare() async {
    starts++;
    if (startError != null) throw startError!;
  }

  @override
  Future<void> stopTableScreenShare() async => stops++;
}

class FakeVideoHandle implements StudioVideoHandle {
  @override
  String get uid => 'host';
  @override
  bool get hasVideo => true;
  @override
  void setRenderSize(double width, double height) {}
}

class FakeGoodsStore implements TableGoodsStore {
  final Map<String, TableGoodsItem?> items = {};
  @override
  Stream<TableGoodsItem?> watch(String streamId, GoodsRef ref) =>
      Stream.value(items['${ref.source.wire}/${ref.productId}']);
}

class FakeCatalogStore implements WatchCatalogStore {
  final Map<String, WatchCatalogEntry> entries = {};
  @override
  Stream<WatchCatalogEntry?> watchEntry(String id) => Stream.value(entries[id]);
  @override
  Stream<List<WatchCatalogEntry>> watchKind(TableMode kind) =>
      Stream.value([for (final e in entries.values) if (e.kind == kind) e]);
}

const int kNow = 1700000000000;

WatchCatalogEntry catalogEntry(String id, TableMode kind, {int? validUntilMs, String title = 'Home vs Away'}) =>
    WatchCatalogEntry(
      id: id,
      kind: kind,
      title: title,
      subtitle: 'Football',
      hlsUrl: 'https://cdn.example/$id.m3u8',
      rightsHolder: 'League',
      territories: const ['TZ'],
      validFromMs: kNow - 1000,
      validUntilMs: validUntilMs ?? kNow + 3600000,
    );

StudioState tableState(TableState t, {int seq = 1}) => StudioState(
      streamId: 's1',
      hostId: 'host',
      status: StudioStatus.live,
      seq: seq,
      stage: const StageLayout(centerUid: 'host'),
      table: t,
    );

/// Answers lsSetTable / lsPlayback like the server (minimal).
FakeCallPort tableServer({TableState initial = const TableState(), int seq = 1}) {
  var cur = initial;
  var s = seq;
  final port = FakeCallPort();
  port.on(StudioCallables.setTable, (a) {
    final mode = TableMode.fromWire(a['mode']);
    final ref = a['ref'] as Map<String, Object?>?;
    cur = TableState(
      mode: mode,
      goods: mode == TableMode.goods && ref != null ? GoodsRef.fromJson(Map<String, dynamic>.from(ref)) : cur.goods,
      screen: mode == TableMode.screen ? ScreenRef(publisherUid: (ref?['publisherUid'] as String?) ?? 'host') : cur.screen,
      watch: mode.isWatchParty
          ? (ref == null ? null : WatchParty(catalogId: ref['catalogId'] as String, anchorServerMs: kNow))
          : cur.watch,
    );
    return {'ok': true, 'seq': ++s, 'table': cur.toJson()};
  });
  port.on(StudioCallables.playback, (a) {
    final w = cur.watch!;
    cur = TableState(
      mode: cur.mode,
      goods: cur.goods,
      screen: cur.screen,
      watch: WatchParty(
        catalogId: w.catalogId,
        state: PlaybackState.fromWire(a['state']),
        positionMs: a['positionMs'] as int,
        anchorServerMs: kNow,
      ),
    );
    return {'ok': true, 'seq': ++s, 'table': cur.toJson()};
  });
  return port;
}

List<Override> tableOverrides({
  required StudioCallPort port,
  required Stream<StudioState> states,
  StudioRole role = StudioRole.host,
  FakeTableRoom? room,
  FakeGoodsStore? goods,
  FakeCatalogStore? catalog,
  FakeClock? clock,
  List<FakePlayerHandle>? players,
}) =>
    [
      studioCallPortProvider.overrideWithValue(port),
      studioTableStateSourceProvider.overrideWith((ref, id) => states),
      studioTableRoleProvider.overrideWith((ref, id) => role),
      studioTableRoomProvider.overrideWith((ref, id) => room ?? FakeTableRoom()),
      studioTableMyUidProvider.overrideWithValue('host'),
      tableGoodsStoreProvider.overrideWithValue(goods ?? FakeGoodsStore()),
      watchCatalogStoreProvider.overrideWithValue(catalog ?? FakeCatalogStore()),
      tableNowMsProvider.overrideWithValue(() => kNow),
      studioClockProvider.overrideWithValue(clock ?? FakeClock(kNow)),
      watchPlayerFactoryProvider.overrideWithValue((url) async {
        final h = FakePlayerHandle(url);
        players?.add(h);
        return h;
      }),
    ];
