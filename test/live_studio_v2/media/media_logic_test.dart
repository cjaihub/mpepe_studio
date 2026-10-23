import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' show ConnectionQuality;
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/contracts/studio_ports.dart';
import 'package:oneova/backend/live_studio/media/audio_only_fallback.dart';
import 'package:oneova/backend/live_studio/media/livekit_studio_room.dart';
import 'package:oneova/backend/live_studio/media/livekit_video_handle.dart';
import 'package:oneova/backend/live_studio/media/publish_profile.dart';
import 'package:oneova/backend/live_studio/media/qos_sampler.dart';
import 'package:oneova/backend/live_studio/media/reconnect_policy.dart';
import 'package:oneova/backend/live_studio/media/studio_media_api.dart';
import 'package:oneova/backend/live_studio/media/studio_packet_decoder.dart';

import '../session/fakes/fake_studio.dart';

class _FixedRandom implements Random {
  _FixedRandom(this.v);
  final double v;
  @override
  double nextDouble() => v;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

class _Sink implements StudioMetricsSink {
  final Map<String, double> last = {};
  final List<String> names = [];
  Map<String, String>? attrs;
  @override
  void metric(String name, double value, Map<String, String> attributes) {
    last[name] = value;
    names.add(name);
    attrs = attributes;
  }
}

void main() {
  group('reconnect backoff', () {
    test('follows StudioLimits.reconnectBackoff without jitter, then holds 30 s', () {
      final b = StudioReconnectBackoff(random: _FixedRandom(0.5)); // 0.5 → factor 1.0
      expect([for (var i = 0; i < 8; i++) b.delayFor(i).inSeconds], [1, 2, 4, 8, 16, 30, 30, 30]);
    });

    test('jitter stays within ±20 %', () {
      final lo = StudioReconnectBackoff(random: _FixedRandom(0));
      final hi = StudioReconnectBackoff(random: _FixedRandom(0.999999));
      expect(lo.delayFor(3).inMilliseconds, 6400);
      expect(hi.delayFor(3).inMilliseconds, closeTo(9600, 1));
      final r = StudioReconnectBackoff(random: Random(7));
      for (var i = 0; i < 200; i++) {
        final ms = r.delayFor(2).inMilliseconds;
        expect(ms, inInclusiveRange(3200, 4800));
      }
    });

    test('fatal join errors are not retried', () {
      FirebaseFunctionsException e(String code) => FirebaseFunctionsException(message: 'x', code: code);
      expect(isFatalJoinError(e('failed-precondition')), isTrue);
      expect(isFatalJoinError(e('permission-denied')), isTrue);
      expect(isFatalJoinError(e('unauthenticated')), isTrue);
      expect(isFatalJoinError(e('unavailable')), isFalse);
      expect(isFatalJoinError(e('deadline-exceeded')), isFalse);
      expect(isFatalJoinError(StateError('socket')), isFalse);
    });
  });

  group('audio-only fallback', () {
    final t0 = DateTime(2026, 10, 17, 12);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('poor for 5 s → audio-only; good for 15 s → recovers', () {
      final f = AudioOnlyFallback();
      expect(f.onQuality(StudioLinkQuality.poor, at(0)), isFalse);
      expect(f.evaluate(at(4999)), isFalse);
      expect(f.evaluate(at(5000)), isTrue);
      expect(f.audioOnly, isTrue);

      expect(f.onQuality(StudioLinkQuality.good, at(6000)), isFalse);
      expect(f.evaluate(at(20999)), isFalse);
      expect(f.evaluate(at(21000)), isTrue);
      expect(f.audioOnly, isFalse);
      expect(f.audioOnlyTime(at(30000)), const Duration(seconds: 16));
    });

    test('a good blip restarts the poor timer', () {
      final f = AudioOnlyFallback();
      f.onQuality(StudioLinkQuality.poor, at(0));
      f.onQuality(StudioLinkQuality.good, at(3000));
      f.onQuality(StudioLinkQuality.poor, at(3500));
      expect(f.evaluate(at(8000)), isFalse);
      expect(f.evaluate(at(8500)), isTrue);
    });

    test('poor → lost does not restart the timer (both bad)', () {
      final f = AudioOnlyFallback();
      f.onQuality(StudioLinkQuality.poor, at(0));
      f.onQuality(StudioLinkQuality.lost, at(2000));
      expect(f.evaluate(at(5000)), isTrue);
    });

    test('a poor blip during recovery restarts the good timer', () {
      final f = AudioOnlyFallback();
      f.onQuality(StudioLinkQuality.poor, at(0));
      f.evaluate(at(5000));
      f.onQuality(StudioLinkQuality.excellent, at(6000));
      f.onQuality(StudioLinkQuality.poor, at(16000));
      f.onQuality(StudioLinkQuality.good, at(17000));
      expect(f.evaluate(at(31000)), isFalse);
      expect(f.audioOnly, isTrue);
      expect(f.evaluate(at(32000)), isTrue);
      expect(f.audioOnlyTime(at(40000)), const Duration(seconds: 27));
    });

    test('good ↔ excellent changes keep the good timer', () {
      final f = AudioOnlyFallback();
      f.onQuality(StudioLinkQuality.poor, at(0));
      f.evaluate(at(5000));
      f.onQuality(StudioLinkQuality.good, at(5000));
      f.onQuality(StudioLinkQuality.excellent, at(10000));
      expect(f.evaluate(at(20000)), isTrue);
    });

    test('LiveKit quality mapping', () {
      expect(studioLinkQualityOf(ConnectionQuality.poor), StudioLinkQuality.poor);
      expect(studioLinkQualityOf(ConnectionQuality.lost), StudioLinkQuality.lost);
      expect(studioLinkQualityOf(ConnectionQuality.unknown), StudioLinkQuality.good);
      expect(studioLinkQualityOf(ConnectionQuality.excellent), StudioLinkQuality.excellent);
    });
  });

  group('publish profile and subscription plan', () {
    test('guests: 3 layers 180/360/720; host with 1080 camera: 180/720/1080', () {
      expect(StudioPublishProfile.forRole(StudioRole.guest, supports1080: true).layerHeights, [180, 360, 720]);
      expect(StudioPublishProfile.forRole(StudioRole.coHost, supports1080: true).layerHeights, [180, 360, 720]);
      expect(StudioPublishProfile.forRole(StudioRole.host, supports1080: false).layerHeights, [180, 360, 720]);
      expect(StudioPublishProfile.forRole(StudioRole.host, supports1080: true).layerHeights, [180, 720, 1080]);
      final p = StudioPublishProfile.standard.publishOptions;
      expect(p.simulcast, isTrue);
      expect(p.name, StudioTrackNames.camera);
    });

    test('screen share track is named table_screen', () {
      expect(kTableScreenPublishOptions.name, kTableScreenTrack);
      expect(StudioTrackNames.tableScreen, 'table_screen');
    });

    test('0×0 pauses; sizes map to the covering layer', () {
      expect(StudioSubscriptionPlan.forSize(0, 0).enabled, isFalse);
      expect(StudioSubscriptionPlan.forSize(100, 0).enabled, isFalse);
      expect(StudioSubscriptionPlan.forSize(double.nan, 10).enabled, isFalse);
      const layers = [180, 360, 720];
      final wall = StudioSubscriptionPlan.forSize(240, 150.4);
      expect(wall.enabled, isTrue);
      expect(wall.height, 151);
      expect(wall.expectedLayer(layers), 180);
      expect(StudioSubscriptionPlan.forSize(1280, 700).expectedLayer(layers), 720);
      expect(StudioSubscriptionPlan.forSize(4000, 2000).expectedLayer(layers), 720);
    });

    test('handle: the largest view wins, all hidden → paused', () {
      final h = LiveKitVideoHandle('u1');
      expect(h.hasVideo, isFalse);
      expect(h.plan.enabled, isFalse);
      final a = Object(), b = Object();
      h.reportView(a, 200, 120);
      h.reportView(b, 1280, 720);
      expect(h.plan.height, 720);
      h.removeView(b);
      expect(h.plan.height, 120);
      h.setRenderSize(640, 360);
      expect(h.plan.height, 360);
      h.setRenderSize(0, 0);
      h.reportView(a, 0, 0);
      expect(h.plan.enabled, isFalse);
      var n = 0;
      h.addListener(() => n++);
      h.setSuppressed(true);
      h.setSuppressed(true);
      expect(n, 1);
      h.dispose();
    });
  });

  group('data packets', () {
    List<int> enc(Object o) => utf8.encode(jsonEncode(o));

    test('decodes by topic', () {
      final e = decodeStudioPacket(enc({'v': 1, 'type': 'state.patch', 'seq': 4, 'path': 'title', 'value': 'x'}),
          topic: StudioTopics.state);
      expect(e, isA<StatePatchEvent>());
      expect((e as StatePatchEvent).seq, 4);
      final c = decodeStudioPacket(enc({'v': 1, 'type': 'counts', 'viewers': 3, 'participants': 1}),
          topic: StudioTopics.counts);
      expect((c as CountsEvent).viewers, 3);
    });

    test('drops participant-sent, topic-less and malformed packets', () {
      final ok = enc({'type': 'comment.deleted', 'id': 'a'});
      expect(decodeStudioPacket(ok, topic: 'chat', fromParticipant: true), isNull);
      expect(decodeStudioPacket(ok), isNull);
      expect(decodeStudioPacket(utf8.encode('not json'), topic: 'chat'), isNull);
      expect(decodeStudioPacket(enc([1, 2]), topic: 'chat'), isNull);
      expect(decodeStudioPacket(enc({'type': 'future.thing'}), topic: 'x'), isA<UnknownEvent>());
    });
  });

  group('QoS sampler', () {
    test('emits rtt, loss delta, jitter, layer, reconnects, audio-only; first frame once', () {
      var now = DateTime(2026, 1, 1);
      final sink = _Sink();
      final q = StudioQosSampler(sink: sink, streamId: 's1', clock: () => now)
        ..role = 'guest'
        ..audioOnlyTime = () => const Duration(seconds: 3);
      q.markJoinStart();
      now = now.add(const Duration(milliseconds: 850));
      q.markFirstFrame();
      now = now.add(const Duration(seconds: 1));
      q.markFirstFrame(); // ignored
      q.onReceiverStats('t1', packetsLost: 5, packetsReceived: 95, jitterSeconds: 0.012, frameHeight: 360);
      q.onReceiverStats('t2', packetsLost: 0, packetsReceived: 100, jitterSeconds: 0.03, frameHeight: 180);
      q.onSenderStats(roundTripTimeSeconds: 0.08);
      q.onSenderStats(roundTripTimeSeconds: 0.12);
      q.onReconnect();

      final first = q.flush();
      expect(first[StudioQosMetrics.joinToFirstFrameMs], 850);
      expect(first[StudioQosMetrics.lossPct], closeTo(2.5, 1e-9));
      expect(first[StudioQosMetrics.jitterMs], closeTo(30, 1e-9));
      expect(first[StudioQosMetrics.layerHeight], 360);
      expect(first[StudioQosMetrics.rttMs], closeTo(100, 1e-9));
      expect(first[StudioQosMetrics.reconnects], 1);
      expect(first[StudioQosMetrics.audioOnlyMs], 3000);
      expect(sink.attrs, {'streamId': 's1', 'role': 'guest'});

      // Next interval: loss is a delta; first frame and rtt not repeated.
      q.onReceiverStats('t1', packetsLost: 15, packetsReceived: 185);
      final second = q.flush();
      expect(second.containsKey(StudioQosMetrics.joinToFirstFrameMs), isFalse);
      expect(second.containsKey(StudioQosMetrics.rttMs), isFalse);
      expect(second[StudioQosMetrics.lossPct], closeTo(10, 1e-9));
      expect(second[StudioQosMetrics.layerHeight], 0);
    });

    test('interval is 10 s', () => expect(StudioQosSampler.interval, const Duration(seconds: 10)));
  });

  group('media api', () {
    test('lsToken / lsStart / lsStateFull / lsSetOwnMedia wire format', () async {
      final calls = FakeCallPort()
          .on(StudioCallables.token, (_) => {'token': 'jwt', 'url': 'wss://x', 'role': 'guest'})
          .on(StudioCallables.start, (_) => {'streamId': 'new', 'token': 't', 'url': 'wss://x'})
          .on(StudioCallables.stateFull, (_) => {'state': testState(seq: 9).toJson()});
      final api = StudioMediaApi(calls);
      final c = await api.token('s1');
      expect((c.token, c.url, c.role), ('jwt', 'wss://x', StudioRole.guest));
      final s = await api.start('Hello', settings: {'theme': 'light'});
      expect(s.streamId, 'new');
      expect(s.credentials.role, StudioRole.host);
      expect(calls.calls[1].$2, {'title': 'Hello', 'settings': {'theme': 'light'}});
      expect((await api.stateFull('s1'))!.seq, 9);
      await api.setOwnMedia('s1', micOn: false, camOn: true);
      expect(calls.calls.last.$2, {'streamId': 's1', 'micOn': false, 'camOn': true});
    });
  });
}
