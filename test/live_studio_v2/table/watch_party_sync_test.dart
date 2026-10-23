import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/table/watch_party_sync.dart';

import 'fakes/fake_table.dart';

class _FakeTimer implements Timer {
  _FakeTimer(this.interval, this.cb);
  final Duration interval;
  final void Function(Timer) cb;
  bool cancelled = false;
  int ticks = 0;
  void fire() {
    ticks++;
    cb(this);
  }

  @override
  void cancel() => cancelled = true;
  @override
  bool get isActive => !cancelled;
  @override
  int get tick => ticks;
}

void main() {
  late FakeWatchPlayer player;
  late FakeClock clock;
  late WatchPartySync sync;
  _FakeTimer? timer;

  setUp(() {
    player = FakeWatchPlayer();
    clock = FakeClock(10000);
    timer = null;
    sync = WatchPartySync(
      player: player,
      clock: clock,
      timerFactory: (d, cb) => timer = _FakeTimer(d, cb),
    );
  });

  WatchParty playing(int pos, int anchor, {double rate = 1}) => WatchParty(
      catalogId: 'c1', state: PlaybackState.playing, positionMs: pos, anchorServerMs: anchor, rate: rate);

  test('drift under the threshold: no seek, just plays', () async {
    player.positionMs = 5000 + 299; // target 5000
    final r = await sync.update(playing(5000, 10000));
    expect(r.driftMs, 299);
    expect(r.seeked, isFalse);
    expect(r.played, isTrue);
    expect(player.log, ['play']);
  });

  test('drift exactly at the threshold does not seek', () async {
    player.positionMs = 5000 - StudioLimits.maxDriftMs;
    final r = await sync.update(playing(5000, 10000));
    expect(r.seeked, isFalse);
  });

  test('drift over the threshold (ahead or behind) seeks to target', () async {
    player.positionMs = 5301;
    var r = await sync.update(playing(5000, 10000));
    expect(r.seeked, isTrue);
    expect(player.positionMs, 5000);

    player.positionMs = 4000; // behind
    clock.localMs = 11000; // target 6000
    r = await sync.sync();
    expect(r.driftMs, -2000);
    expect(player.positionMs, 6000);
  });

  test('target advances with server time while playing', () async {
    await sync.update(playing(0, 10000));
    clock.localMs = 13500;
    expect(sync.targetNowMs(), 3500);
  });

  test('paused: target frozen, player paused, seeks to the paused position', () async {
    player
      ..isPlaying = true
      ..positionMs = 9000;
    const p = WatchParty(catalogId: 'c1', state: PlaybackState.paused, positionMs: 4000, anchorServerMs: 1);
    final r = await sync.update(p);
    expect(r.paused, isTrue);
    expect(r.seeked, isTrue);
    expect(player.isPlaying, isFalse);
    expect(player.positionMs, 4000);
    clock.localMs = 99999;
    expect(sync.targetNowMs(), 4000);
    final again = await sync.sync();
    expect(again.didSomething, isFalse);
  });

  test('ended pauses the player', () async {
    player.isPlaying = true;
    await sync.update(const WatchParty(catalogId: 'c1', state: PlaybackState.ended, positionMs: 0));
    expect(player.isPlaying, isFalse);
  });

  test('rate: follows the party rate and scales the target', () async {
    final r = await sync.update(playing(1000, 10000, rate: 2));
    expect(r.rateChanged, isTrue);
    expect(player.rate, 2);
    clock.localMs = 11000;
    expect(sync.targetNowMs(), 3000);
    final again = await sync.sync();
    expect(again.rateChanged, isFalse);
  });

  test('re-anchor: a new anchor/position syncs at once', () async {
    player.positionMs = 5000;
    await sync.update(playing(5000, 10000));
    player.log.clear();
    // Host seeks to 60 s at server time 10000.
    final r = await sync.update(playing(60000, 10000));
    expect(r.seeked, isTrue);
    expect(player.positionMs, 60000);
  });

  test('same party twice is not a state change', () async {
    await sync.update(playing(0, 10000));
    player.log.clear();
    final r = await sync.update(playing(0, 10000));
    expect(r, same(WatchSyncResult.idle));
    expect(player.log, isEmpty);
  });

  test('clock offset: uses server time, not local time', () async {
    clock
      ..localMs = 10000
      ..offsetMs = 2500; // server is 2.5 s ahead
    player.positionMs = 0;
    final r = await sync.update(playing(0, 10000));
    expect(r.targetMs, 2500);
    expect(r.seeked, isTrue);
    expect(player.positionMs, 2500);
  });

  test('target clamps to [0, duration]', () async {
    player.durationMs = 3000;
    await sync.update(playing(2000, 10000));
    clock.localMs = 20000;
    expect(sync.targetNowMs(), 3000);
    await sync.update(const WatchParty(catalogId: 'c1', positionMs: -50));
    expect(sync.targetNowMs(), 0);
  });

  test('no party: pauses a playing player', () async {
    await sync.update(playing(0, 10000));
    expect(player.isPlaying, isTrue);
    final r = await sync.update(null);
    expect(r.paused, isTrue);
    expect(player.isPlaying, isFalse);
  });

  test('periodic check every second; stop cancels', () async {
    await sync.update(playing(0, 10000));
    sync.start();
    expect(timer!.interval, const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);
    player.positionMs = 0;
    clock.localMs = 12000; // drift -2000
    timer!.fire();
    await Future<void>.delayed(Duration.zero);
    expect(player.positionMs, 2000);
    sync.stop();
    expect(timer!.cancelled, isTrue);
    expect(sync.isRunning, isFalse);
  });

  test('overlapping syncs are coalesced', () async {
    await sync.update(playing(0, 10000));
    final a = sync.sync();
    final b = sync.sync();
    expect(identical(a, b), isTrue);
    await a;
  });
}
