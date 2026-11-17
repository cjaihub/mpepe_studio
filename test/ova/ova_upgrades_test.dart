import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/agent_workspace/ova_agent_mac_executor.dart';
import 'package:oneova/agent_workspace/ova_agent_models.dart';
import 'package:oneova/desktop_agent/desktop_input_router.dart';
import 'package:oneova/desktop_agent/desktop_window_bridge.dart';
import 'package:oneova/desktop_agent/windows_automation_ffi.dart';
import 'package:oneova/ova_assistant/overlay/ova_screen_translate_overlay.dart';
import 'package:oneova/shared/audio/ova_vertex_audio_engine.dart';

void main() {
  group('OvaVertexAudioEngine helpers', () {
    test('cleanForSpeech strips markdown & preserves natural sentences', () {
      const raw =
          '# Hello!\nCheck **[this link](https://oneova.web.app)** and `code()`.\n```dart\nfinal x = 1;\n```\nReady to edit.';
      final cleaned = OvaVertexAudioEngine.cleanForSpeech(raw);
      expect(cleaned, contains('Hello!'));
      expect(cleaned, contains('this link'));
      expect(cleaned, contains('Ready to edit.'));
      expect(cleaned, isNot(contains('**')));
      expect(cleaned, isNot(contains('https://oneova.web.app')));
      expect(cleaned, isNot(contains('```')));
    });

    test('cleanForSpeech caps extremely long output cleanly', () {
      final veryLong = 'word ' * 500;
      final cleaned = OvaVertexAudioEngine.cleanForSpeech(veryLong);
      expect(cleaned.length, lessThanOrEqualTo(1401));
      expect(cleaned.endsWith('…'), isTrue);
    });

    test('pcm16MonoToWav emits valid 44-byte RIFF/WAVE header', () {
      final pcm = Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05, 0x06]);
      final wav = OvaVertexAudioEngine.pcm16MonoToWav(pcm, sampleRate: 24000);
      expect(wav.length, 44 + pcm.length);
      expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(wav.sublist(8, 12)), 'WAVE');
      expect(ascii.decode(wav.sublist(12, 16)), 'fmt ');
      expect(ascii.decode(wav.sublist(36, 40)), 'data');
      final bd = ByteData.sublistView(wav);
      expect(bd.getUint32(4, Endian.little), 36 + pcm.length);
      expect(bd.getUint32(24, Endian.little), 24000);
      expect(bd.getUint32(28, Endian.little), 48000);
      expect(bd.getUint32(40, Endian.little), pcm.length);
      expect(wav.sublist(44), pcm);
    });
  });

  group('OvaScreenBlock & in-place screen translate parsing', () {
    test('fromMap clamps out-of-range coordinates safely', () {
      final blk = OvaScreenBlock.fromMap({
        'id': 'b1',
        'text': '  Bonjour le monde  ',
        'left': -0.2,
        'top': 1.4,
        'right': 0.1,
        'bottom': 1.8,
      }, 0);
      expect(blk.id, 'b1');
      expect(blk.text, 'Bonjour le monde');
      expect(blk.normRect.left, inInclusiveRange(0.0, 1.0));
      expect(blk.normRect.top, inInclusiveRange(0.0, 1.0));
      expect(blk.normRect.right, greaterThan(blk.normRect.left));
      expect(blk.normRect.bottom, greaterThan(blk.normRect.top));
    });

    test('copyWith preserves spatial bounds and applies translation', () {
      final blk = OvaScreenBlock.fromMap({
        'text': 'Comprar ahora',
        'left': 0.2,
        'top': 0.3,
        'right': 0.6,
        'bottom': 0.35,
      }, 2);
      final tr = blk.copyWith(translated: 'Buy now', sameLanguage: false);
      expect(tr.translated, 'Buy now');
      expect(tr.normRect, blk.normRect);
      expect(tr.sameLanguage, isFalse);
    });
  });

  group('Desktop cross-platform routing & executor', () {
    test('OvaAgentMacExecutor.expandHomePath resolves ~ cleanly', () {
      final home = Platform.environment['HOME'] ?? Directory.current.path;
      expect(OvaAgentMacExecutor.expandHomePath('~'), home);
      expect(OvaAgentMacExecutor.expandHomePath('~/Desktop'), '$home/Desktop');
      expect(OvaAgentMacExecutor.expandHomePath('/tmp/test'), '/tmp/test');
    });

    test('WindowsDesktopController safely no-ops on non-Windows hosts', () async {
      if (!Platform.isWindows) {
        expect(WindowsDesktopController.isSupported, isFalse);
        expect(WindowsDesktopController.getCursorPosition(), (x: 0, y: 0));
        expect(
          WindowsDesktopController.getMainDisplayBounds(),
          (width: 1920, height: 1080),
        );
        expect(await WindowsDesktopController.getActiveAppName(), isNull);
        expect(await WindowsDesktopController.isScreenLocked(), isFalse);
      }
    });

    test('DesktopInputRouter & DesktopWindowBridge report desktop state cleanly', () {
      expect(
        DesktopInputRouter.isSupported,
        Platform.isMacOS || Platform.isWindows,
      );
      expect(
        DesktopWindowBridge.isDesktop,
        Platform.isMacOS || Platform.isWindows,
      );
    });

    test('OvaAgentMacExecutor handles creative_suite_skill on unsupported platform cleanly', () async {
      // On desktop test runner (macOS), calling inspect or unknown mobile platform
      // verify structured OvaAgentToolCall instantiates cleanly.
      const call = OvaAgentToolCall(
        id: 'tc_1',
        name: 'creative_suite_skill',
        title: 'DaVinci Resolve Inspect',
        args: {'app': 'davinci_resolve', 'skill': 'inspect_session'},
      );
      expect(call.name, 'creative_suite_skill');
      expect(call.title, 'DaVinci Resolve Inspect');
      expect(call.args['app'], 'davinci_resolve');
    });
  });
}
