import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/contracts/studio_ports.dart';
import 'package:oneova/backend/live_studio/social/studio_social.dart';

import 'fakes/fake_social_ports.dart';

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeRoomPort room;
  late FakeCallPort calls;
  late ProviderContainer c;
  const sid = 's1';

  setUp(() {
    room = FakeRoomPort();
    calls = FakeCallPort();
    c = ProviderContainer(overrides: [
      studioSocialRoomPortProvider.overrideWith((ref, id) => room),
      studioCallPortProvider.overrideWithValue(calls),
    ]);
    c.listen(studioReactionsProvider(sid), (_, _) {});
  });
  tearDown(() => c.dispose());

  StudioReactionsController ctl() => c.read(studioReactionsProvider(sid).notifier);
  StudioReactionsState st() => c.read(studioReactionsProvider(sid));

  test('taps are optimistic and emit local bursts', () async {
    final bursts = <StudioReactionBurst>[];
    final sub = ctl().bursts.listen(bursts.add);
    ctl().tap(ReactionKind.love);
    ctl().tap(ReactionKind.love);
    ctl().tap(ReactionKind.sparkles);
    await settle();
    expect(st().loves, 2);
    expect(st().sparkles, 1);
    expect(st().myLoves, 2);
    expect(bursts.where((b) => b.local).length, 3);
    expect(calls.calls, isEmpty, reason: 'nothing sent before the flush tick');
    await sub.cancel();
  });

  test('batches into calls of at most reactionMaxPerCall, one call per flush', () async {
    for (var i = 0; i < 25; i++) {
      ctl().tap(ReactionKind.love);
    }
    await ctl().flush();
    await ctl().flush();
    await ctl().flush();
    await ctl().flush();
    final ns = calls.calls.map((c) => c.args['n']).toList();
    expect(ns, [10, 10, 5]);
    for (final call in calls.calls) {
      expect(call.name, StudioCallables.react);
      expect(call.args['kind'], 'love');
      expect(call.args['streamId'], sid);
    }
    expect(st().loves, 25, reason: 'acked taps stay counted until an aggregate arrives');
  });

  test('alternates kinds between flushes', () async {
    for (var i = 0; i < 12; i++) {
      ctl().tap(ReactionKind.love);
      ctl().tap(ReactionKind.sparkles);
    }
    for (var i = 0; i < 4; i++) {
      await ctl().flush();
    }
    expect(calls.calls.map((c) => '${c.args['kind']}:${c.args['n']}').toList(),
        ['love:10', 'sparkles:10', 'love:2', 'sparkles:2']);
  });

  test('the 300 ms timer flushes automatically', () async {
    ctl().tap(ReactionKind.love, 3);
    await Future<void>.delayed(kStudioReactionFlushInterval + const Duration(milliseconds: 120));
    expect(calls.calls.map((c) => c.args['n']), [3]);
  });

  test('a failed batch is rolled back', () async {
    calls.handler = (name, args) => throw StateError('resource-exhausted');
    ctl().tap(ReactionKind.love, 4);
    expect(st().loves, 4);
    await ctl().flush();
    expect(st().loves, 0);
    expect(st().myLoves, 0);
  });

  test('aggregate totals replace acked taps; remote bursts exclude own taps', () async {
    final bursts = <StudioReactionBurst>[];
    final sub = ctl().bursts.listen(bursts.add);
    ctl().tap(ReactionKind.love, 3);
    await ctl().flush();
    bursts.clear();
    room.emit(const ReactionAggEvent(loves: 10, sparkles: 2, totals: StudioCounts(loves: 103, sparkles: 2)));
    await settle();
    expect(st().loves, 103);
    expect(st().sparkles, 2);
    expect(bursts.map((b) => '${b.kind.wire}:${b.count}:${b.local}'), ['love:7:false', 'sparkles:2:false']);
    // Pending local taps add on top of server totals.
    ctl().tap(ReactionKind.love);
    expect(st().loves, 104);
    // Older (lower) totals never move the counter back.
    room.emit(const ReactionAggEvent(loves: 0, sparkles: 0, totals: StudioCounts(loves: 50)));
    await settle();
    expect(st().loves, 104);
    await sub.cancel();
  });

  test('in-flight taps stay counted while the call is pending', () async {
    final gate = Completer<void>();
    calls.gate = gate;
    ctl().tap(ReactionKind.sparkles, 2);
    final f = ctl().flush();
    await settle();
    expect(st().sparkles, 2);
    await ctl().flush(); // ignored while sending
    expect(calls.calls, hasLength(1));
    gate.complete();
    await f;
    expect(st().sparkles, 2);
  });
}
