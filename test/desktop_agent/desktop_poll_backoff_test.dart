import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/desktop_agent/desktop_firebase_rest_client.dart';

const _quota = DesktopCloudException(
  code: 'resource-exhausted',
  message: 'Quota exceeded.',
  statusCode: 429,
);
const _denied = DesktopCloudException(
  code: 'permission-denied',
  message: 'Missing or insufficient permissions.',
  statusCode: 403,
);
const _flaky = DesktopCloudException(
  code: 'unavailable',
  message: 'Service unavailable',
  statusCode: 503,
);

/// Drives a [DesktopCollectionPoller] on fake time inside [testWidgets].
class _Harness {
  _Harness(this.tester, {List<Object?>? script}) : _script = script ?? [] {
    gate = DesktopPollGate(now: () => DateTime(2026, 11, 9).add(elapsed));
    poller = DesktopCollectionPoller(
      path: 'registered_computers/x/webrtc_signaling',
      gate: gate,
      backoff: DesktopPollBackoff(random: () => 1.0),
      fetch: () async {
        fetches++;
        final next = _script.isEmpty ? null : _script.removeAt(0);
        if (next is Exception) throw next;
        return (next as List<DesktopRestDoc>?) ?? docs;
      },
    );
  }

  final WidgetTester tester;
  final List<Object?> _script;
  late final DesktopPollGate gate;
  late final DesktopCollectionPoller poller;
  Duration elapsed = Duration.zero;
  int fetches = 0;
  List<DesktopRestDoc> docs = const [
    DesktopRestDoc(id: 'a', data: {'type': 'offer'}, updateTime: 't1'),
  ];

  Future<void> advance(Duration d) async {
    // Step in small slices so timers fire at their own deadlines.
    const step = Duration(milliseconds: 50);
    var left = d;
    while (left > Duration.zero) {
      final s = left < step ? left : step;
      elapsed += s;
      await tester.pump(s);
      left -= s;
    }
  }
}

void main() {
  group('DesktopPollBackoff', () {
    test('classifies quota, permission and transient errors', () {
      expect(DesktopPollBackoff.classify(_quota), DesktopPollErrorKind.quota);
      expect(
        DesktopPollBackoff.classify(const DesktopCloudException(
          code: 'firestore-error',
          message: 'Quota exceeded.',
        )),
        DesktopPollErrorKind.quota,
      );
      expect(
        DesktopPollBackoff.classify(_denied),
        DesktopPollErrorKind.permissionDenied,
      );
      expect(
        DesktopPollBackoff.classify(_flaky),
        DesktopPollErrorKind.transient,
      );
    });

    test('doubles transient delays up to the cap', () {
      final b = DesktopPollBackoff(
        base: const Duration(seconds: 2),
        max: const Duration(seconds: 20),
        random: () => 1.0,
      );
      final delays = [for (var i = 0; i < 6; i++) b.onError(_flaky)!.inSeconds];
      expect(delays, [2, 4, 8, 16, 20, 20]);
      b.reset();
      expect(b.onError(_flaky), const Duration(seconds: 2));
    });

    test('quota errors start long and cap at quotaMax', () {
      final b = DesktopPollBackoff(random: () => 1.0);
      expect(b.onError(_quota), const Duration(seconds: 30));
      expect(b.onError(_quota), const Duration(seconds: 60));
      for (var i = 0; i < 10; i++) {
        b.onError(_quota);
      }
      expect(b.onError(_quota), const Duration(minutes: 15));
    });

    test('jitter stays between 50% and 100% of the delay', () {
      final low = DesktopPollBackoff(random: () => 0.0);
      final high = DesktopPollBackoff(random: () => 1.0);
      expect(low.onError(_quota), const Duration(seconds: 15));
      expect(high.onError(_quota), const Duration(seconds: 30));
    });

    test('permission-denied means pause', () {
      expect(DesktopPollBackoff().onError(_denied), isNull);
    });
  });

  group('DesktopCollectionPoller', () {
    // Subscriptions are cancelled without `await`: awaiting cancel() under
    // testWidgets' fake clock stalls the next pump.
    testWidgets('two watchers of one path share each read', (tester) async {
      final h = _Harness(tester);
      final a = <int>[];
      final b = <int>[];
      final subA = h.poller
          .watch(interval: const Duration(milliseconds: 500))
          .listen((d) => a.add(d.length));
      final subB = h.poller
          .watch(interval: const Duration(milliseconds: 500))
          .listen((d) => b.add(d.length));

      await h.advance(const Duration(milliseconds: 1100));
      // One immediate read, then one per 500 ms (no idle slow-down yet
      // because it ramps only after unchanged reads).
      expect(h.fetches, lessThanOrEqualTo(3));
      expect(a.length, h.fetches);
      expect(b.length, greaterThanOrEqualTo(h.fetches - 1));

      subA.cancel();
      subB.cancel();
      await h.advance(const Duration(seconds: 4));
      expect(h.poller.isDisposed, isTrue);
    });

    testWidgets('slows down while idle and speeds up on change',
        (tester) async {
      final h = _Harness(tester);
      final sub = h.poller
          .watch(
            interval: const Duration(milliseconds: 500),
            idleInterval: const Duration(seconds: 3),
          )
          .listen((_) {});

      await h.advance(const Duration(seconds: 30));
      // At 500 ms fixed this would be ~60 reads; idle ramps to 3 s.
      expect(h.fetches, lessThan(16));

      final before = h.fetches;
      h.docs = const [
        DesktopRestDoc(id: 'a', data: {}, updateTime: 't2'),
      ];
      await h.advance(const Duration(seconds: 6));
      final afterChange = h.fetches - before;
      // Change seen within one idle period, then back to the fast interval.
      expect(afterChange, greaterThanOrEqualTo(3));

      sub.cancel();
      h.poller.dispose();
    });

    testWidgets('keepFast holds the fast interval', (tester) async {
      final h = _Harness(tester);
      var negotiating = true;
      final sub = h.poller
          .watch(
            interval: const Duration(milliseconds: 500),
            idleInterval: const Duration(seconds: 3),
            keepFast: () => negotiating,
          )
          .listen((_) {});
      await h.advance(const Duration(seconds: 5));
      expect(h.fetches, greaterThanOrEqualTo(10));
      negotiating = false;
      final before = h.fetches;
      await h.advance(const Duration(seconds: 15));
      expect(h.fetches - before, lessThan(12));
      sub.cancel();
      h.poller.dispose();
    });

    testWidgets('quota errors back off instead of retrying every interval',
        (tester) async {
      final h = _Harness(tester, script: [_quota, _quota, _quota]);
      final errors = <Object>[];
      final sub = h.poller
          .watch(interval: const Duration(milliseconds: 750))
          .listen((_) {}, onError: errors.add);

      await h.advance(const Duration(seconds: 60));
      // Read at 0 s fails -> wait 30 s -> fails -> wait 60 s.
      expect(h.fetches, 2);
      // Error reported once per streak, not per retry.
      expect(errors, hasLength(1));
      expect(h.gate.remainingCooldown(), greaterThan(Duration.zero));

      await h.advance(const Duration(seconds: 61));
      expect(h.fetches, 3);
      await h.advance(const Duration(minutes: 3));
      // Third failure waits 120 s, then reads succeed again.
      expect(h.fetches, greaterThan(4));
      sub.cancel();
      h.poller.dispose();
    });

    testWidgets('quota cooldown is shared by pollers on the same gate',
        (tester) async {
      final h = _Harness(tester);
      h.gate.noteQuotaExceeded(const Duration(seconds: 20));
      final sub = h.poller
          .watch(interval: const Duration(milliseconds: 500))
          .listen((_) {});
      await h.advance(const Duration(seconds: 19));
      expect(h.fetches, 0);
      await h.advance(const Duration(seconds: 2));
      expect(h.fetches, greaterThanOrEqualTo(1));
      expect(h.fetches, lessThanOrEqualTo(4));
      sub.cancel();
      h.poller.dispose();
    });

    testWidgets('permission-denied pauses until watched again', (tester) async {
      final h = _Harness(tester, script: [_denied]);
      final errors = <Object>[];
      final sub = h.poller
          .watch(interval: const Duration(milliseconds: 500))
          .listen((_) {}, onError: errors.add);

      await h.advance(const Duration(minutes: 2));
      expect(h.fetches, 1);
      expect(h.poller.isPaused, isTrue);
      expect(errors, hasLength(1));

      // Rebind: cancel the old watcher and watch again.
      sub.cancel();
      final got = <List<DesktopRestDoc>>[];
      final sub2 = h.poller
          .watch(interval: const Duration(milliseconds: 500))
          .listen(got.add);
      await h.advance(const Duration(milliseconds: 100));
      expect(h.poller.isPaused, isFalse);
      expect(h.fetches, 2);
      expect(got, isNotEmpty);
      sub2.cancel();
      h.poller.dispose();
    });

    testWidgets('a slow read never overlaps the next one', (tester) async {
      var inFlight = 0;
      var maxInFlight = 0;
      var fetches = 0;
      final poller = DesktopCollectionPoller(
        path: 'p',
        fetch: () async {
          fetches++;
          inFlight++;
          if (inFlight > maxInFlight) maxInFlight = inFlight;
          await Future<void>.delayed(const Duration(seconds: 2));
          inFlight--;
          return const [];
        },
      );
      final sub = poller
          .watch(interval: const Duration(milliseconds: 200))
          .listen((_) {});
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(maxInFlight, 1);
      expect(fetches, lessThanOrEqualTo(5));
      sub.cancel();
      poller.dispose();
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
