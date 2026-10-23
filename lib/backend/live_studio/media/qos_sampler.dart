// LIVE STUDIO v2 — QoS sampling (pure aggregation, ARCHITECTURE §7).
//
// The room feeds raw stats in; [flush] (every 10 s) emits one batch of
// metrics to a [StudioMetricsSink] (TelemetryService in production).

import 'dart:math' as math;

import '../../observability/telemetry_service.dart';

/// Where QoS metrics go.
abstract class StudioMetricsSink {
  void metric(String name, double value, Map<String, String> attributes);
}

class TelemetryMetricsSink implements StudioMetricsSink {
  const TelemetryMetricsSink(this._t);
  final TelemetryService _t;
  @override
  void metric(String name, double value, Map<String, String> attributes) =>
      _t.recordMetric(name, value, attributes: attributes);
}

/// Metric names (prefix `live_studio.media.`).
class StudioQosMetrics {
  StudioQosMetrics._();
  static const String joinToFirstFrameMs = 'live_studio.media.join_to_first_frame_ms';
  static const String rttMs = 'live_studio.media.rtt_ms';
  static const String lossPct = 'live_studio.media.packet_loss_pct';
  static const String jitterMs = 'live_studio.media.jitter_ms';
  static const String layerHeight = 'live_studio.media.layer_height';
  static const String reconnects = 'live_studio.media.reconnects';
  static const String audioOnlyMs = 'live_studio.media.audio_only_ms';
}

class _Counters {
  num lost = 0;
  num received = 0;
}

class StudioQosSampler {
  StudioQosSampler({required this.sink, required this.streamId, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const Duration interval = Duration(seconds: 10);

  final StudioMetricsSink sink;
  final String streamId;
  final DateTime Function() _clock;

  String role = 'viewer';
  DateTime? _joinStart;
  int? _firstFrameMs;
  bool _firstFrameReported = false;
  int _reconnects = 0;
  Duration Function() audioOnlyTime = () => Duration.zero;

  // Per-track cumulative counters (last seen / at last flush).
  final Map<String, _Counters> _latest = {};
  final Map<String, _Counters> _atFlush = {};
  final List<double> _rttMs = [];
  double _jitterMs = 0;
  int _layer = 0;

  int? get firstFrameMs => _firstFrameMs;
  int get reconnects => _reconnects;

  void markJoinStart() {
    _joinStart ??= _clock();
  }

  /// First decoded remote video frame (or first local preview frame).
  void markFirstFrame() {
    final start = _joinStart;
    if (start == null || _firstFrameMs != null) return;
    _firstFrameMs = _clock().difference(start).inMilliseconds;
  }

  void onReconnect() => _reconnects++;

  /// Cumulative receiver stats of one track (WebRTC getStats semantics).
  void onReceiverStats(String trackId, {num? packetsLost, num? packetsReceived, num? jitterSeconds, num? frameHeight}) {
    final c = _latest.putIfAbsent(trackId, _Counters.new);
    if (packetsLost != null) c.lost = packetsLost;
    if (packetsReceived != null) c.received = packetsReceived;
    if (jitterSeconds != null) _jitterMs = math.max(_jitterMs, jitterSeconds * 1000);
    if (frameHeight != null) _layer = math.max(_layer, frameHeight.toInt());
  }

  void onSenderStats({num? roundTripTimeSeconds, num? jitterSeconds}) {
    if (roundTripTimeSeconds != null) _rttMs.add(roundTripTimeSeconds * 1000);
    if (jitterSeconds != null) _jitterMs = math.max(_jitterMs, jitterSeconds * 1000);
  }

  void forgetTrack(String trackId) {
    _latest.remove(trackId);
    _atFlush.remove(trackId);
  }

  /// Packet loss % since the previous flush, across all receive tracks.
  double _lossPct() {
    num lost = 0, recv = 0;
    _latest.forEach((id, c) {
      final prev = _atFlush[id];
      lost += math.max(0, c.lost - (prev?.lost ?? 0));
      recv += math.max(0, c.received - (prev?.received ?? 0));
    });
    final total = lost + recv;
    return total == 0 ? 0 : lost * 100 / total;
  }

  /// Emits one sample and resets the interval aggregates.
  Map<String, double> flush() {
    final attrs = {'streamId': streamId, 'role': role};
    final out = <String, double>{
      StudioQosMetrics.lossPct: _lossPct(),
      StudioQosMetrics.jitterMs: _jitterMs,
      StudioQosMetrics.layerHeight: _layer.toDouble(),
      StudioQosMetrics.reconnects: _reconnects.toDouble(),
      StudioQosMetrics.audioOnlyMs: audioOnlyTime().inMilliseconds.toDouble(),
      if (_rttMs.isNotEmpty) StudioQosMetrics.rttMs: _rttMs.reduce((a, b) => a + b) / _rttMs.length,
      if (_firstFrameMs != null && !_firstFrameReported) StudioQosMetrics.joinToFirstFrameMs: _firstFrameMs!.toDouble(),
    };
    if (_firstFrameMs != null) _firstFrameReported = true;
    out.forEach((k, v) => sink.metric(k, v, attrs));

    _latest.forEach((id, c) => _atFlush[id] = _Counters()
      ..lost = c.lost
      ..received = c.received);
    _rttMs.clear();
    _jitterMs = 0;
    _layer = 0;
    return out;
  }
}
