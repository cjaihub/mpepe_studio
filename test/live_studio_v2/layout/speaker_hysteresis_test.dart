import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/layout/layout.dart';

import 'fakes/fake_ports.dart';

/// A synthetic speech timeline: at each [atMs] the speaker list becomes
/// [speakers]; we evaluate every 50 ms and record promotions.
List<(int, String)> runTimeline(
  List<(int, List<String>)> events, {
  required int untilMs,
  SpeakerMode mode = SpeakerMode.autoActiveSpeaker,
  StageLayout Function(StageLayout s, String promoted)? apply,
  StageLayout? initial,
  int startHoldMs = 4000,
}) {
  final clock = FakeClock();
  final t0 = clock.ms;
  final h = SpeakerHysteresis(nowMs: clock.now);
  var stage = initial ?? stage6();
  h.observeStage(stage);
  clock.advance(startHoldMs); // let the initial hold expire before t = 0
  final base = clock.ms;
  final out = <(int, String)>[];
  var e = 0;
  for (var t = 0; t <= untilMs; t += 50) {
    clock.ms = base + t;
    while (e < events.length && events[e].$1 <= t) {
      h.onSpeakers(events[e].$2);
      e++;
    }
    final uid = h.evaluate(stage: stage, mode: mode);
    if (uid != null) {
      out.add((t, uid));
      stage = (apply ?? swapIn)(stage, uid);
    }
  }
  expect(clock.ms - t0, greaterThan(0));
  return out;
}

/// What the server does on autoPromote: the previous center goes to the
/// vacated slot.
StageLayout swapIn(StageLayout s, String uid) {
  final wall = List<String?>.from(s.wall);
  final i = wall.indexOf(uid);
  final overflow = List<String>.from(s.overflow);
  if (i >= 0) {
    wall[i] = s.centerUid;
  } else {
    overflow[overflow.indexOf(uid)] = s.centerUid;
  }
  return s.copyWith(centerUid: uid, wall: wall, overflow: overflow);
}

void main() {
  test('1.5 s of continuous speech takes the center', () {
    final r = runTimeline([(0, ['g1'])], untilMs: 3000);
    expect(r, [(1500, 'g1')]);
  });

  test('1.4 s is not enough; a gap restarts the run', () {
    final r = runTimeline([
      (0, ['g1']),
      (1400, []),
      (1450, ['g1']),
    ], untilMs: 2800);
    expect(r, isEmpty); // run restarted at 1450 → would fire at 2950
    final r2 = runTimeline([
      (0, ['g1']),
      (1400, []),
      (1450, ['g1']),
    ], untilMs: 3100);
    expect(r2, [(2950, 'g1')]);
  });

  test('the center stays at least 4 s', () {
    final r = runTimeline([
      (0, ['g1']),
      (1600, ['g2']), // g2 speaks continuously from 1.6 s
    ], untilMs: 8000);
    // g1 promoted at 1.5 s; g2 qualifies at 3.1 s but the hold lasts to 5.5 s.
    expect(r, [(1500, 'g1'), (5500, 'g2')]);
  });

  test('previous center moves into the vacated slot', () {
    var stage = stage6();
    final clock = FakeClock();
    final h = SpeakerHysteresis(nowMs: clock.now);
    h.observeStage(stage);
    clock.advance(4000);
    h.onSpeakers(['g3']);
    clock.advance(1500);
    final uid = h.evaluate(stage: stage, mode: SpeakerMode.autoActiveSpeaker);
    expect(uid, 'g3');
    stage = swapIn(stage, uid!);
    expect(stage.centerUid, 'g3');
    expect(stage.wall[2], 'host');
  });

  test('a pin blocks auto until unpinned', () {
    final clock = FakeClock();
    final h = SpeakerHysteresis(nowMs: clock.now);
    final pinned = stage6(pinned: 'host');
    h.observeStage(pinned);
    h.onSpeakers(['g1']);
    clock.advance(10000);
    expect(h.evaluate(stage: pinned, mode: SpeakerMode.autoActiveSpeaker), isNull);
    final unpinned = pinned.copyWith(clearPin: true);
    expect(h.evaluate(stage: unpinned, mode: SpeakerMode.autoActiveSpeaker), 'g1');
  });

  test('hostPinned and manual never promote', () {
    for (final m in [SpeakerMode.hostPinned, SpeakerMode.manual]) {
      expect(runTimeline([(0, ['g1', 'g2'])], untilMs: 20000, mode: m), isEmpty);
    }
  });

  test('loudest qualifying speaker wins; center and non-members ignored', () {
    final r = runTimeline([
      (0, ['host', 'stranger', 'g2', 'g1']),
    ], untilMs: 2000);
    expect(r, [(1500, 'g2')]);
  });

  test('overflow members can be promoted', () {
    final r = runTimeline([(0, ['o1'])],
        untilMs: 2000, initial: stage6(overflow: ['o1']));
    expect(r, [(1500, 'o1')]);
  });

  test('a manual change of center restarts the hold', () {
    final clock = FakeClock();
    final h = SpeakerHysteresis(nowMs: clock.now);
    h.observeStage(stage6());
    clock.advance(5000);
    h.onSpeakers(['g1']);
    clock.advance(1000);
    final moved = swapIn(stage6(), 'g4'); // host/coHost swapped manually
    expect(h.evaluate(stage: moved, mode: SpeakerMode.autoActiveSpeaker), isNull);
    clock.advance(3900);
    expect(h.evaluate(stage: moved, mode: SpeakerMode.autoActiveSpeaker), isNull);
    clock.advance(100);
    expect(h.evaluate(stage: moved, mode: SpeakerMode.autoActiveSpeaker), 'g1');
  });

  test('back-and-forth chatter does not thrash', () {
    // Two guests alternate every 1 s for 20 s: nobody reaches 1.5 s.
    final events = <(int, List<String>)>[
      for (var t = 0; t < 20000; t += 1000) (t, [t ~/ 1000 % 2 == 0 ? 'g1' : 'g2']),
    ];
    expect(runTimeline(events, untilMs: 20000), isEmpty);
  });

  test('overlapping speech: both speaking, promotions spaced by the hold', () {
    final r = runTimeline([(0, ['g1', 'g2'])], untilMs: 15000);
    expect(r.first, (1500, 'g1'));
    for (var i = 1; i < r.length; i++) {
      expect(r[i].$1 - r[i - 1].$1, greaterThanOrEqualTo(4000));
    }
  });

  test('nextDecisionAtMs predicts the promotion time', () {
    final clock = FakeClock();
    final h = SpeakerHysteresis(nowMs: clock.now);
    final s = stage6();
    h.observeStage(s);
    final start = clock.ms;
    h.onSpeakers(['g1']);
    expect(h.nextDecisionAtMs(stage: s, mode: SpeakerMode.autoActiveSpeaker), start + 4000);
    clock.advance(3000);
    h.onSpeakers(['g1']);
    expect(h.nextDecisionAtMs(stage: s, mode: SpeakerMode.manual), isNull);
  });
}
