// LIVE STUDIO v2 — server clock offset via `lsTime` (ARCHITECTURE §9).
//
// 5 pings; the sample with the lowest round trip wins:
//   offset = serverMs + rtt / 2 − localReceiveMs.

import '../contracts/studio_contracts.dart';
import '../contracts/studio_ports.dart';

class CallableStudioClock implements StudioClockPort {
  CallableStudioClock(this._call, {int Function()? localNowMs, this.samples = 5})
      : _now = localNowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final StudioCallPort _call;
  final int Function() _now;
  final int samples;

  int _offsetMs = 0;
  int? _bestRttMs;
  Future<void>? _inFlight;

  @override
  int get offsetMs => _offsetMs;

  /// Round trip of the sample the offset came from (null = never calibrated).
  int? get bestRttMs => _bestRttMs;

  bool get calibrated => _bestRttMs != null;

  @override
  int serverNowMs() => _now() + _offsetMs;

  /// Runs [samples] pings. Concurrent calls share one run. Failed pings are
  /// skipped; if all fail the previous offset is kept.
  @override
  Future<void> calibrate() => _inFlight ??= _run().whenComplete(() => _inFlight = null);

  Future<void> _run() async {
    int? bestRtt;
    int? bestOffset;
    for (var i = 0; i < samples; i++) {
      try {
        final t0 = _now();
        final r = await _call.call(StudioCallables.time, const {});
        final t1 = _now();
        final server = r['serverMs'];
        if (server is! num) continue;
        final rtt = t1 - t0;
        if (bestRtt == null || rtt < bestRtt) {
          bestRtt = rtt;
          bestOffset = (server + rtt / 2 - t1).round();
        }
      } catch (_) {
        // Skip this sample.
      }
    }
    if (bestRtt != null && bestOffset != null) {
      _bestRttMs = bestRtt;
      _offsetMs = bestOffset;
    }
  }
}
