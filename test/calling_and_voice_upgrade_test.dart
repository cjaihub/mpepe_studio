import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/calling/providers/call_room_controller.dart';
import 'package:oneova/backend/calling/providers/webrtc_connection_manager.dart';
import 'package:oneova/backend/calling/services/call_ice_config.dart';
import 'package:oneova/hub/messaging/chat_assist_service.dart';
import 'package:oneova/shared/widgets/advanced_voice_interface.dart';
import 'package:oneova/shared/widgets/live_recording_waveform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebRTC Zero-Cost Opus HD SDP & Low-Latency ICE', () {
    test('tuneOpusSdp injects FEC, DTX, 20ms ptime, and 48kbps HD mono voice', () {
      const rawSdp = 'v=0\r\n'
          'm=audio 9 UDP/TLS/RTP/SAVPF 111 0\r\n'
          'a=rtpmap:111 opus/48000/2\r\n'
          'a=fmtp:111 minptime=10;useinbandfec=0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
          'a=rtpmap:96 VP8/90000\r\n';

      final tuned = WebRTCConnectionManager.tuneOpusSdp(rawSdp)!;
      expect(tuned, contains('a=fmtp:111 '));
      expect(tuned, contains('useinbandfec=1'));
      expect(tuned, contains('usedtx=1'));
      expect(tuned, contains('maxaveragebitrate=48000'));
      expect(tuned, contains('ptime=20'));
      expect(tuned, contains('minptime=10'));
      expect(tuned, contains('stereo=0'));
      expect(tuned, contains('sprop-stereo=0'));
      expect(tuned, contains('a=rtpmap:96 VP8/90000'));
    });

    test('tuneOpusSdp inserts fmtp line when Opus rtpmap has no fmtp yet', () {
      const rawSdp = 'v=0\n'
          'm=audio 9 UDP/TLS/RTP/SAVPF 109\n'
          'a=rtpmap:109 opus/48000/2\n';

      final tuned = WebRTCConnectionManager.tuneOpusSdp(rawSdp)!;
      expect(tuned, contains('a=fmtp:109 '));
      expect(tuned, contains('useinbandfec=1'));
      expect(tuned, contains('maxaveragebitrate=48000'));
    });

    test('CallIceConfig enables Unified Plan, max-bundle, RTCP mux, and pre-pooled ICE', () {
      final cfg = CallIceConfig.configuration();
      expect(cfg['sdpSemantics'], equals('unified-plan'));
      expect(cfg['bundlePolicy'], equals('max-bundle'));
      expect(cfg['rtcpMuxPolicy'], equals('require'));
      expect(cfg['iceCandidatePoolSize'], equals(4));

      final servers = cfg['iceServers'] as List<Map<String, dynamic>>;
      expect(servers, isNotEmpty);
      final urls = servers.first['urls'] as List;
      expect(urls, contains('stun:stun.cloudflare.com:3478'));
      expect(urls, contains('stun:stun.l.google.com:19302'));
    });

    test('CallLayout supports 50/50 split-screen camera exchange', () {
      expect(CallLayout.values, containsAll([CallLayout.grid, CallLayout.spotlight, CallLayout.split]));
    });
  });

  group('Compact Voice Note Bubbles, Waveforms & Voice-Matched Translation', () {
    test('computeCompactWidth keeps short notes sleek and caps long notes well below 290px', () {
      final shortW = InteractiveVoiceNotePlayer.computeCompactWidth(
        Duration.zero,
        initialDuration: '0:03',
        hasTranslationAction: true,
      );
      final longW = InteractiveVoiceNotePlayer.computeCompactWidth(
        const Duration(minutes: 2),
        hasTranslationAction: true,
      );
      expect(shortW, lessThan(172));
      expect(longW, lessThanOrEqualTo(224));
      expect(longW, greaterThan(shortW));
    });

    test('downsampleLevels preserves peaks into compact 24-bar waveform', () {
      final raw = List<double>.generate(240, (i) => i == 120 ? 0.96 : 0.22);
      final bars = downsampleLevels(raw, 24);
      expect(bars.length, equals(24));
      expect(bars.reduce((a, b) => a > b ? a : b), closeTo(0.96, 1e-6));
    });

    test('ChatPrefs parses aiAutoTranslateVoice toggle', () {
      final prefs = ChatPrefs.fromMap({
        'aiEnabled': true,
        'aiAutoTranslate': false,
        'aiAutoTranslateVoice': true,
      });
      expect(prefs.aiEnabled, isTrue);
      expect(prefs.aiAutoTranslate, isFalse);
      expect(prefs.aiAutoTranslateVoice, isTrue);
    });

    test('VoiceAudioDiskCache seeds local file and deduplicates translation requests', () async {
      final tmp = await Directory.systemTemp.createTemp('oneova_vn_test_');
      addTearDown(() => tmp.delete(recursive: true));
      final localFile = File('${tmp.path}/sample.m4a');
      await localFile.writeAsBytes([1, 2, 3, 4]);

      const remoteUrl = 'https://example.com/chats/c1/voice_note_1.m4a';
      VoiceAudioDiskCache.seedLocalFile(remoteUrl, localFile.path);
      final resolved = await VoiceAudioDiskCache.resolvePlayablePath(remoteUrl);
      expect(resolved, equals(localFile.path));

      var calls = 0;
      final results = await Future.wait([
        VoiceAudioDiskCache.runDeduplicatedTranslation('msg1::en', () async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return const VoiceTranslationResult(
            transcript: 'Hola amigo',
            translated: 'Hello friend',
            source: 'es',
            target: 'en',
            same: false,
            voiceName: 'Charon',
            pitch: 0.96,
            rate: 1.02,
          );
        }),
        VoiceAudioDiskCache.runDeduplicatedTranslation('msg1::en', () async {
          calls++;
          return const VoiceTranslationResult(
            transcript: 'Duplicate',
            translated: 'Duplicate',
            source: 'es',
            target: 'en',
            same: false,
          );
        }),
      ]);

      expect(calls, equals(1));
      expect(results[0].translated, equals('Hello friend'));
      expect(results[1].voiceName, equals('Charon'));
    });
  });
}
