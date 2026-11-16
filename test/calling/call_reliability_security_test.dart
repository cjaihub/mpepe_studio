import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/calling/providers/active_call_controller.dart';
import 'package:oneova/backend/calling/providers/call_media_service.dart';
import 'package:oneova/backend/calling/providers/webrtc_connection_manager.dart';
import 'package:oneova/backend/calling/services/call_ice_config.dart';
import 'package:oneova/inbox/calling/widgets/call_widgets.dart';
import 'package:oneova/shared/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebRTC FrameCryptor null-track SIGSEGV prevention', () {
    test('skips sender cryptor when audio call pre-allocates video transceiver with null track', () {
      final seenKinds = <String>{};

      final audioPlan = WebRTCConnectionManager.planTransceiverCryptor(
        stopped: false,
        senderTrackKind: 'audio',
        receiverTrackKind: 'audio',
        senderAlreadyAttached: false,
        receiverAlreadyAttached: false,
        index: 0,
        seenKinds: seenKinds,
      );
      expect(audioPlan.attachSender, isTrue);
      expect(audioPlan.attachReceiver, isTrue);
      expect(audioPlan.kindKey, equals('audio'));

      // Critical crash scenario observed on Android 16: video sender track is null.
      final videoPlan = WebRTCConnectionManager.planTransceiverCryptor(
        stopped: false,
        senderTrackKind: null,
        receiverTrackKind: null,
        senderAlreadyAttached: false,
        receiverAlreadyAttached: false,
        index: 1,
        seenKinds: seenKinds,
      );
      expect(videoPlan.attachSender, isFalse);
      expect(videoPlan.attachReceiver, isFalse);
    });

    test('attaches video sender cryptor safely once camera/screen track is added mid-call', () {
      final firstPass = <String>{};
      WebRTCConnectionManager.planTransceiverCryptor(
        stopped: false,
        senderTrackKind: 'audio',
        receiverTrackKind: 'audio',
        senderAlreadyAttached: false,
        receiverAlreadyAttached: false,
        index: 0,
        seenKinds: firstPass,
      );

      // Remote video present in SDP answer, local camera still off -> only receiver attaches.
      final rxOnlyPlan = WebRTCConnectionManager.planTransceiverCryptor(
        stopped: false,
        senderTrackKind: null,
        receiverTrackKind: 'video',
        senderAlreadyAttached: false,
        receiverAlreadyAttached: false,
        index: 1,
        seenKinds: firstPass,
      );
      expect(rxOnlyPlan.attachSender, isFalse);
      expect(rxOnlyPlan.attachReceiver, isTrue);
      expect(rxOnlyPlan.kindKey, equals('video'));

      // Pass 2 after user turns camera or screen share on -> only sender attaches now.
      final secondPass = <String>{};
      final audioPass2 = WebRTCConnectionManager.planTransceiverCryptor(
        stopped: false,
        senderTrackKind: 'audio',
        receiverTrackKind: 'audio',
        senderAlreadyAttached: true,
        receiverAlreadyAttached: true,
        index: 0,
        seenKinds: secondPass,
      );
      expect(audioPass2.attachSender, isFalse);
      expect(audioPass2.attachReceiver, isFalse);

      final videoUpgradePlan = WebRTCConnectionManager.planTransceiverCryptor(
        stopped: false,
        senderTrackKind: 'video',
        receiverTrackKind: 'video',
        senderAlreadyAttached: false,
        receiverAlreadyAttached: true,
        index: 1,
        seenKinds: secondPass,
      );
      expect(videoUpgradePlan.attachSender, isTrue);
      expect(videoUpgradePlan.attachReceiver, isFalse);
      expect(videoUpgradePlan.kindKey, equals('video'));
    });

    test('skips stopped transceivers completely', () {
      final plan = WebRTCConnectionManager.planTransceiverCryptor(
        stopped: true,
        senderTrackKind: 'video',
        receiverTrackKind: 'video',
        senderAlreadyAttached: false,
        receiverAlreadyAttached: false,
        index: 1,
        seenKinds: <String>{},
      );
      expect(plan.attachSender, isFalse);
      expect(plan.attachReceiver, isFalse);
    });
  });

  group('Call ICE/TURN config & connectivity handovers', () {
    test('mergeIceServers merges STUN, TURN relay, and Remote Config without duplicates', () {
      final cfg = CallIceConfig.buildConfiguration(
        extraServers: [
          {
            'urls': ['turn:turn.cloudflare.com:3478?transport=udp'],
            'username': 'u1',
            'credential': 'p1',
          },
        ],
        remoteConfigServers: [
          {
            'urls': ['turn:turn.cloudflare.com:3478?transport=udp'],
            'username': 'u1',
            'credential': 'p1',
          },
          {
            'urls': ['turns:turn.cloudflare.com:5349?transport=tcp'],
            'username': 'u1',
            'credential': 'p1',
          },
        ],
      );

      final servers = cfg['iceServers'] as List<Map<String, dynamic>>;
      expect(servers.length, equals(3));
      expect(cfg['iceTransportPolicy'], equals('all'));
    });

    test('shouldRestartOnConnectivityChange detects offline→online and Wi-Fi↔cellular handovers', () {
      expect(
        ActiveCallController.shouldRestartOnConnectivityChange(
          const [ConnectivityResult.wifi],
          const [ConnectivityResult.mobile],
        ),
        isTrue,
      );
      expect(
        ActiveCallController.shouldRestartOnConnectivityChange(
          const [ConnectivityResult.none],
          const [ConnectivityResult.wifi],
        ),
        isTrue,
      );
      expect(
        ActiveCallController.shouldRestartOnConnectivityChange(
          const [ConnectivityResult.wifi],
          const [ConnectivityResult.wifi],
        ),
        isFalse,
      );
      expect(
        ActiveCallController.shouldRestartOnConnectivityChange(
          const [ConnectivityResult.wifi],
          const [ConnectivityResult.none],
        ),
        isFalse,
      );
    });

    test('androidAudioDeviceTypeName maps all routes to flutter_webrtc AudioDeviceKind names', () {
      expect(CallMediaService.androidAudioDeviceTypeName(AudioRoute.bluetooth), equals('bluetooth'));
      expect(CallMediaService.androidAudioDeviceTypeName(AudioRoute.wired), equals('wired-headset'));
      expect(CallMediaService.androidAudioDeviceTypeName(AudioRoute.speaker), equals('speaker'));
      expect(CallMediaService.androidAudioDeviceTypeName(AudioRoute.earpiece), equals('earpiece'));
    });
  });

  group('Call UI dual-mode & interactive shield chip', () {
    testWidgets('CallEncryptedChip renders in light/dark mode and handles tap', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          home: Scaffold(
            body: Center(
              child: CallEncryptedChip(
                frameEncrypted: true,
                onTap: () => tapped++,
              ),
            ),
          ),
        ),
      );
      expect(find.text('End-to-end encrypted'), findsOneWidget);
      await tester.tap(find.text('End-to-end encrypted'));
      expect(tapped, equals(1));
    });
  });
}
